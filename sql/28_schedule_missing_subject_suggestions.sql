-- =============================================================
-- مدارس أمين الرضا (ع) — اقتراح وإضافة الحصص الناقصة
-- يعتمد على تقرير المواد الناقصة ويقترح أول خانة فارغة مناسبة
-- مع معلم مسند لنفس الشعبة والمادة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) اقتراح أماكن للحصص الناقصة
-- -------------------------------------------------------------
create or replace function public.schedule_missing_subject_suggestions(
  p_academic_period_id uuid default null
)
returns table(
  class_id uuid,
  class_name text,
  section_id uuid,
  section_code text,
  section_name text,
  subject_id uuid,
  subject_name text,
  required_subject text,
  teacher_assignment_id uuid,
  teacher_id uuid,
  teacher_name text,
  suggested_day int,
  suggested_period int,
  can_auto_add boolean,
  reason text
)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return query
  with missing as (
    select *
    from public.schedule_required_subjects_report(p_academic_period_id)
    where status = 'missing'
      and matched_subject_id is not null
  ), with_teacher as (
    select
      m.*,
      ta.id as ta_id,
      ta.teacher_id as ta_teacher_id,
      u.name as ta_teacher_name
    from missing m
    left join lateral (
      select ta.*
      from public.teacher_assignments ta
      where ta.section_id = m.section_id
        and ta.subject_id = m.matched_subject_id
        and ta.is_active = true
        and (p_academic_period_id is null or ta.academic_period_id is null or ta.academic_period_id = p_academic_period_id)
      order by ta.academic_period_id nulls last, ta.updated_at desc nulls last
      limit 1
    ) ta on true
    left join public.users u on u.id = ta.teacher_id
  ), slots as (
    select
      wt.*,
      gs_day.day_no,
      gs_period.period_no
    from with_teacher wt
    cross join lateral generate_series(0,4) as gs_day(day_no)
    cross join lateral generate_series(
      1,
      case when public.schedule_stage_type(wt.class_name) = 'primary' then 5 else 3 end
    ) as gs_period(period_no)
  ), free_slots as (
    select
      s.*,
      row_number() over (
        partition by s.section_id, s.matched_subject_id
        order by s.day_no, s.period_no
      ) as rn
    from slots s
    where s.ta_teacher_id is not null
      and not exists (
        select 1
        from public.weekly_schedule ws
        where (p_academic_period_id is null or ws.academic_period_id = p_academic_period_id)
          and ws.section_id = s.section_id
          and ws.day = s.day_no
          and ws.period_number = s.period_no
      )
      and not exists (
        select 1
        from public.weekly_schedule wt
        where (p_academic_period_id is null or wt.academic_period_id = p_academic_period_id)
          and wt.teacher_id = s.ta_teacher_id
          and wt.day = s.day_no
          and wt.period_number = s.period_no
      )
  )
  select
    wt.class_id,
    wt.class_name,
    wt.section_id,
    wt.section_code,
    wt.section_name,
    wt.matched_subject_id as subject_id,
    wt.matched_subject_name as subject_name,
    wt.required_subject,
    wt.ta_id as teacher_assignment_id,
    wt.ta_teacher_id as teacher_id,
    wt.ta_teacher_name as teacher_name,
    fs.day_no as suggested_day,
    fs.period_no as suggested_period,
    (wt.ta_teacher_id is not null and fs.day_no is not null) as can_auto_add,
    case
      when wt.ta_teacher_id is null then 'لا يوجد إسناد معلم لهذه المادة والشعبة'
      when fs.day_no is null then 'لا توجد خانة فارغة مناسبة أو يوجد تعارض مع جدول المعلم'
      else 'جاهز للإضافة'
    end as reason
  from with_teacher wt
  left join free_slots fs
    on fs.section_id = wt.section_id
   and fs.matched_subject_id = wt.matched_subject_id
   and fs.rn = 1
  order by wt.class_name, wt.section_code, wt.required_subject;
end;
$$;

grant execute on function public.schedule_missing_subject_suggestions(uuid) to authenticated;

-- -------------------------------------------------------------
-- 2) إضافة حصة مقترحة واحدة
-- -------------------------------------------------------------
create or replace function public.add_missing_schedule_slot(
  p_academic_period_id uuid,
  p_section_id uuid,
  p_subject_id uuid,
  p_teacher_id uuid,
  p_day int,
  p_period_number int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  sec record;
  assignment_result jsonb;
  assignment_id uuid;
begin
  if not exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (
        u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor')
        or coalesce(u.is_super_admin,false)=true
      )
  ) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إضافة حصص للجدول');
  end if;

  select * into sec from public.sections where id = p_section_id;
  if sec.id is null then
    return jsonb_build_object('ok', false, 'message', 'الشعبة غير موجودة');
  end if;

  if p_day not between 0 and 4 then
    return jsonb_build_object('ok', false, 'message', 'اليوم غير صالح');
  end if;

  if p_period_number < 1 then
    return jsonb_build_object('ok', false, 'message', 'رقم الحصة غير صالح');
  end if;

  if exists(
    select 1 from public.weekly_schedule ws
    where ws.academic_period_id is not distinct from p_academic_period_id
      and ws.section_id = p_section_id
      and ws.day = p_day
      and ws.period_number = p_period_number
  ) then
    return jsonb_build_object('ok', false, 'message', 'هذه الخانة مشغولة في جدول الشعبة');
  end if;

  if exists(
    select 1 from public.weekly_schedule ws
    where ws.academic_period_id is not distinct from p_academic_period_id
      and ws.teacher_id = p_teacher_id
      and ws.day = p_day
      and ws.period_number = p_period_number
  ) then
    return jsonb_build_object('ok', false, 'message', 'المعلم لديه حصة أخرى في نفس الوقت');
  end if;

  assignment_result := public.upsert_teacher_assignment(
    p_teacher_id,
    p_section_id,
    p_subject_id,
    p_academic_period_id,
    '2026-2027'
  );

  if coalesce((assignment_result->>'ok')::boolean,false) = false then
    return assignment_result;
  end if;

  assignment_id := (assignment_result->>'teacher_assignment_id')::uuid;

  insert into public.weekly_schedule (
    academic_period_id,
    class_id,
    section_id,
    subject_id,
    teacher_id,
    teacher_assignment_id,
    day,
    period_number,
    source
  ) values (
    p_academic_period_id,
    sec.class_id,
    p_section_id,
    p_subject_id,
    p_teacher_id,
    assignment_id,
    p_day,
    p_period_number,
    'missing_subject_suggestion'
  );

  return jsonb_build_object('ok', true, 'message', 'تمت إضافة الحصة الناقصة');
exception when unique_violation then
  return jsonb_build_object('ok', false, 'message', 'تعارض: الخانة أصبحت مشغولة');
when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.add_missing_schedule_slot(uuid,uuid,uuid,uuid,int,int) to authenticated;

notify pgrst, 'reload schema';

select 'missing_subject_suggestions_ready' as status;

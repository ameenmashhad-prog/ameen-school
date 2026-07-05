-- =============================================================
-- مدارس أمين الرضا (ع) — ربط الجلسات بالشعب والإسنادات + نقل جماعي
-- يكمل المرحلة بعد إنشاء sections / teacher_assignments.
-- لا يحذف بيانات.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) إضافة section_id و teacher_assignment_id إلى class_sessions
-- -------------------------------------------------------------
alter table public.class_sessions add column if not exists section_id uuid null references public.sections(id) on delete set null;
alter table public.class_sessions add column if not exists teacher_assignment_id uuid null references public.teacher_assignments(id) on delete set null;

create index if not exists idx_class_sessions_section on public.class_sessions(section_id, session_date);
create index if not exists idx_class_sessions_assignment on public.class_sessions(teacher_assignment_id, session_date);

-- مزامنة الجلسات الحالية من weekly_schedule
update public.class_sessions cs
set section_id = ws.section_id,
    teacher_assignment_id = ws.teacher_assignment_id
from public.weekly_schedule ws
where ws.id = cs.weekly_schedule_id
  and (cs.section_id is null or cs.teacher_assignment_id is null);

-- -------------------------------------------------------------
-- 2) مزامنة weekly_schedule مع teacher_assignments
-- -------------------------------------------------------------
create or replace function public.sync_weekly_schedule_assignments()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  n int := 0;
begin
  update public.weekly_schedule ws
  set teacher_assignment_id = ta.id
  from public.teacher_assignments ta
  where ta.academic_year = '2026-2027'
    and ta.teacher_id = ws.teacher_id
    and ta.section_id = ws.section_id
    and ta.subject_id = ws.subject_id
    and (ta.academic_period_id is not distinct from ws.academic_period_id)
    and (ws.teacher_assignment_id is distinct from ta.id);

  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function public.sync_weekly_schedule_assignments() to authenticated;

select public.sync_weekly_schedule_assignments();

-- -------------------------------------------------------------
-- 3) دالة نقل جماعي للطلاب بين الشعب
-- -------------------------------------------------------------
create or replace function public.bulk_move_students_to_section(
  p_student_ids uuid[],
  p_section_id uuid,
  p_academic_year text default '2026-2027'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid;
  moved int := 0;
  failed int := 0;
  result jsonb;
begin
  if not exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)
  ) then
    return jsonb_build_object('ok',false,'message','ليست لديك صلاحية نقل الطلاب جماعياً');
  end if;

  if p_student_ids is null or array_length(p_student_ids,1) is null then
    return jsonb_build_object('ok',false,'message','لم يتم تحديد طلاب');
  end if;

  foreach sid in array p_student_ids loop
    begin
      result := public.move_student_to_section(sid, p_section_id, p_academic_year);
      if coalesce((result->>'ok')::boolean,false) then
        moved := moved + 1;
      else
        failed := failed + 1;
      end if;
    exception when others then
      failed := failed + 1;
    end;
  end loop;

  return jsonb_build_object('ok',true,'moved',moved,'failed',failed);
end;
$$;

grant execute on function public.bulk_move_students_to_section(uuid[],uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 4) تحديث دالة توليد الجلسات لتخزن section_id و teacher_assignment_id
-- -------------------------------------------------------------
create or replace function public.generate_class_sessions(
  p_start date,
  p_end date,
  p_academic_period_id uuid default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  d date;
  dow_school int;
  ws record;
  h record;
  inserted_count int := 0;
  stage_kind text;
  settings jsonb;
  p_start_time text;
  p_duration int;
  p_break int;
  start_minutes int;
  s_time time;
  e_time time;
begin
  select schedule_time_settings into settings
  from public.school_calendar_settings
  where id = 'main';

  if settings is null then
    settings := '{
      "primary": {"start": "12:45", "periods": 5, "duration": 45, "break": 10},
      "secondary": {"start": "13:00", "periods": 3, "duration": 75, "break": 10}
    }'::jsonb;
  end if;

  d := p_start;
  while d <= p_end loop
    -- PostgreSQL Sunday=0, Saturday=6; school Saturday=0
    dow_school := ((extract(dow from d)::int + 1) % 7);

    select * into h
    from public.school_holidays sh
    where sh.holiday_date = d
       or (sh.is_recurring = true and to_char(sh.holiday_date,'MM-DD') = to_char(d,'MM-DD'))
    limit 1;

    for ws in
      select w.*, c.name as class_name
      from public.weekly_schedule w
      left join public.classes c on c.id = w.class_id
      where w.day = dow_school
        and (p_academic_period_id is null or w.academic_period_id = p_academic_period_id)
    loop
      stage_kind := case
        when ws.class_name ilike '%ابتدائي%' then 'primary'
        else 'secondary'
      end;

      p_start_time := coalesce(settings -> stage_kind ->> 'start', case when stage_kind='primary' then '12:45' else '13:00' end);
      p_duration := coalesce((settings -> stage_kind ->> 'duration')::int, case when stage_kind='primary' then 45 else 75 end);
      p_break := coalesce((settings -> stage_kind ->> 'break')::int, 10);

      start_minutes := split_part(p_start_time, ':', 1)::int * 60
                     + split_part(p_start_time, ':', 2)::int
                     + ((ws.period_number - 1) * (p_duration + p_break));

      s_time := make_time((start_minutes / 60)::int % 24, start_minutes % 60, 0);
      e_time := make_time(((start_minutes + p_duration) / 60)::int % 24, (start_minutes + p_duration) % 60, 0);

      insert into public.class_sessions (
        academic_period_id,
        weekly_schedule_id,
        teacher_assignment_id,
        session_date,
        day,
        period_number,
        start_time,
        end_time,
        class_id,
        section_id,
        subject_id,
        teacher_id,
        status,
        holiday_id
      ) values (
        ws.academic_period_id,
        ws.id,
        ws.teacher_assignment_id,
        d,
        dow_school,
        ws.period_number,
        s_time,
        e_time,
        ws.class_id,
        ws.section_id,
        ws.subject_id,
        ws.teacher_id,
        case when h.id is not null then 'holiday' else 'scheduled' end,
        h.id
      )
      on conflict (weekly_schedule_id, session_date) do update
      set
        teacher_assignment_id = excluded.teacher_assignment_id,
        section_id = excluded.section_id,
        start_time = excluded.start_time,
        end_time = excluded.end_time,
        status = excluded.status,
        holiday_id = excluded.holiday_id,
        updated_at = now();

      inserted_count := inserted_count + 1;
    end loop;

    d := d + 1;
  end loop;

  return inserted_count;
end;
$$;

grant execute on function public.generate_class_sessions(date,date,uuid) to authenticated;

-- -------------------------------------------------------------
-- 5) View تفصيلي للجلسات بعد ربطها بالشعب
-- -------------------------------------------------------------
create or replace view public.v_class_sessions_detailed
with (security_invoker=true) as
select
  cs.id,
  cs.session_date,
  cs.academic_period_id,
  ap.name as academic_period_name,
  cs.weekly_schedule_id,
  cs.teacher_assignment_id,
  cs.class_id,
  c.name as class_name,
  cs.section_id,
  sec.code as section_code,
  sec.name as section_name,
  cs.subject_id,
  sub.name as subject_name,
  cs.teacher_id,
  u.name as teacher_name,
  cs.day,
  cs.period_number,
  cs.start_time,
  cs.end_time,
  cs.status,
  cs.holiday_id,
  h.name as holiday_name
from public.class_sessions cs
left join public.academic_periods ap on ap.id = cs.academic_period_id
left join public.classes c on c.id = cs.class_id
left join public.sections sec on sec.id = cs.section_id
left join public.subjects sub on sub.id = cs.subject_id
left join public.users u on u.id = cs.teacher_id
left join public.school_holidays h on h.id = cs.holiday_id;

grant select on public.v_class_sessions_detailed to authenticated;

notify pgrst, 'reload schema';

select
  (select count(*) from public.class_sessions where section_id is not null) as sessions_with_sections,
  (select count(*) from public.class_sessions where teacher_assignment_id is not null) as sessions_with_assignments,
  (select public.sync_weekly_schedule_assignments()) as schedule_rows_synced;

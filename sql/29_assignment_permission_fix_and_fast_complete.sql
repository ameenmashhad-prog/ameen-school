-- =============================================================
-- مدارس أمين الرضا (ع) — تسريع العمل: إصلاح صلاحية الإسناد من SQL Editor
-- + إسناد وإضافة المواد الناقصة تلقائياً عند الإمكان
--
-- السبب: عند تشغيل الدوال من Supabase SQL Editor تكون auth.uid() = null.
-- الحل: السماح بالتشغيل من SQL Editor، مع بقاء التحقق عند التشغيل من الواجهة.
-- =============================================================

create extension if not exists pgcrypto;

create or replace function public._can_manage_assignments()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select auth.uid() is null
    or exists(
      select 1
      from public.users u
      where u.id = auth.uid()
        and (
          u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor')
          or coalesce(u.is_super_admin,false)=true
        )
    );
$$;

grant execute on function public._can_manage_assignments() to authenticated;

-- -------------------------------------------------------------
-- إصلاح upsert_teacher_assignment ليعمل من SQL Editor أيضاً
-- -------------------------------------------------------------
create or replace function public.upsert_teacher_assignment(
  p_teacher_id uuid,
  p_section_id uuid,
  p_subject_id uuid,
  p_academic_period_id uuid default null,
  p_academic_year text default '2026-2027'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  sec record;
  assignment_id uuid;
begin
  if not public._can_manage_assignments() then
    return jsonb_build_object('ok',false,'message','ليست لديك صلاحية إسناد المعلمين');
  end if;

  if p_teacher_id is null then
    return jsonb_build_object('ok',false,'message','لم يتم تحديد المعلم');
  end if;

  select * into sec from public.sections where id = p_section_id;
  if sec.id is null then
    return jsonb_build_object('ok',false,'message','الشعبة غير موجودة');
  end if;

  insert into public.teacher_assignments (
    academic_year,
    academic_period_id,
    teacher_id,
    class_id,
    section_id,
    subject_id,
    weekly_hours,
    is_active
  ) values (
    p_academic_year,
    p_academic_period_id,
    p_teacher_id,
    sec.class_id,
    sec.id,
    p_subject_id,
    0,
    true
  )
  on conflict (academic_year, academic_period_id, teacher_id, section_id, subject_id) do update
  set is_active = true,
      updated_at = now()
  returning id into assignment_id;

  return jsonb_build_object('ok',true,'message','تم حفظ إسناد المعلم','teacher_assignment_id',assignment_id);
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.upsert_teacher_assignment(uuid,uuid,uuid,uuid,text) to authenticated;

-- -------------------------------------------------------------
-- إصلاح update_teacher_assignment ليعمل من SQL Editor أيضاً
-- -------------------------------------------------------------
create or replace function public.update_teacher_assignment(
  p_assignment_id uuid,
  p_teacher_id uuid,
  p_section_id uuid,
  p_subject_id uuid,
  p_academic_period_id uuid default null,
  p_update_linked_schedule boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  sec record;
  old_assignment record;
  new_class_id uuid;
begin
  if not public._can_manage_assignments() then
    return jsonb_build_object('ok',false,'message','ليست لديك صلاحية تعديل الإسنادات');
  end if;

  select * into old_assignment from public.teacher_assignments where id = p_assignment_id;
  if old_assignment.id is null then
    return jsonb_build_object('ok',false,'message','الإسناد غير موجود');
  end if;

  select * into sec from public.sections where id = p_section_id;
  if sec.id is null then
    return jsonb_build_object('ok',false,'message','الشعبة غير موجودة');
  end if;

  new_class_id := sec.class_id;

  update public.teacher_assignments
  set teacher_id = p_teacher_id,
      section_id = p_section_id,
      class_id = new_class_id,
      subject_id = p_subject_id,
      academic_period_id = p_academic_period_id,
      is_active = true,
      updated_at = now()
  where id = p_assignment_id;

  if p_update_linked_schedule then
    update public.weekly_schedule
    set teacher_id = p_teacher_id,
        section_id = p_section_id,
        class_id = new_class_id,
        subject_id = p_subject_id,
        academic_period_id = p_academic_period_id,
        updated_at = now()
    where teacher_assignment_id = p_assignment_id;

    update public.class_sessions
    set teacher_id = p_teacher_id,
        section_id = p_section_id,
        class_id = new_class_id,
        subject_id = p_subject_id,
        academic_period_id = p_academic_period_id,
        updated_at = now()
    where teacher_assignment_id = p_assignment_id;
  end if;

  return jsonb_build_object('ok',true,'message','تم تعديل الإسناد');
exception when unique_violation then
  return jsonb_build_object('ok',false,'message','يوجد إسناد أو حصة بنفس القيم يسبب تكراراً. راجعي الجدول قبل التعديل.');
when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.update_teacher_assignment(uuid,uuid,uuid,uuid,uuid,boolean) to authenticated;

-- -------------------------------------------------------------
-- إصلاح set_teacher_assignment_active ليعمل من SQL Editor أيضاً
-- -------------------------------------------------------------
create or replace function public.set_teacher_assignment_active(
  p_assignment_id uuid,
  p_active boolean,
  p_update_linked_schedule boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
begin
  if not public._can_manage_assignments() then
    return jsonb_build_object('ok',false,'message','ليست لديك صلاحية تعديل الإسنادات');
  end if;

  select * into a from public.teacher_assignments where id = p_assignment_id;
  if a.id is null then
    return jsonb_build_object('ok',false,'message','الإسناد غير موجود');
  end if;

  update public.teacher_assignments
  set is_active = p_active,
      updated_at = now()
  where id = p_assignment_id;

  if p_update_linked_schedule and p_active = false then
    update public.weekly_schedule set teacher_assignment_id = null where teacher_assignment_id = p_assignment_id;
    update public.class_sessions set teacher_assignment_id = null where teacher_assignment_id = p_assignment_id;
  end if;

  return jsonb_build_object('ok',true,'message',case when p_active then 'تم تفعيل الإسناد' else 'تم إيقاف الإسناد' end);
end;
$$;

grant execute on function public.set_teacher_assignment_active(uuid,boolean,boolean) to authenticated;

-- -------------------------------------------------------------
-- دالة تسريع: إسناد المواد الناقصة إلى معلم، ثم إضافتها تلقائياً عند وجود خانة
-- p_teacher_name اختياري. إذا لم يحدد، يختار أكثر معلم عنده حصص في نفس الشعبة.
-- -------------------------------------------------------------
create or replace function public.auto_assign_and_add_missing_subjects(
  p_academic_period_id uuid,
  p_class_name text,
  p_section_code text default 'أ',
  p_teacher_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_teacher_id uuid;
  v_assignment jsonb;
  v_suggestion record;
  v_add jsonb;
  assigned_count int := 0;
  added_count int := 0;
  failed_count int := 0;
  messages jsonb := '[]'::jsonb;
begin
  if not public._can_manage_assignments() then
    return jsonb_build_object('ok',false,'message','ليست لديك صلاحية تنفيذ الإسناد التلقائي');
  end if;

  for r in
    select *
    from public.schedule_missing_subject_suggestions(p_academic_period_id)
    where class_name = p_class_name
      and section_code = p_section_code
  loop
    -- اختيار المعلم
    v_teacher_id := null;

    if p_teacher_name is not null then
      select id into v_teacher_id
      from public.users
      where role = 'teacher'
        and name = p_teacher_name
      limit 1;
    end if;

    if v_teacher_id is null then
      select ws.teacher_id into v_teacher_id
      from public.weekly_schedule ws
      where ws.section_id = r.section_id
        and ws.teacher_id is not null
        and (p_academic_period_id is null or ws.academic_period_id = p_academic_period_id)
      group by ws.teacher_id
      order by count(*) desc
      limit 1;
    end if;

    if v_teacher_id is null then
      select id into v_teacher_id
      from public.users
      where role = 'teacher'
      order by name
      limit 1;
    end if;

    if v_teacher_id is null then
      failed_count := failed_count + 1;
      messages := messages || jsonb_build_array(jsonb_build_object('subject', r.required_subject, 'status', 'failed', 'reason', 'لا يوجد أي معلم'));
      continue;
    end if;

    -- إنشاء الإسناد
    v_assignment := public.upsert_teacher_assignment(v_teacher_id, r.section_id, r.subject_id, p_academic_period_id, '2026-2027');
    if coalesce((v_assignment->>'ok')::boolean,false) = false then
      failed_count := failed_count + 1;
      messages := messages || jsonb_build_array(jsonb_build_object('subject', r.required_subject, 'status', 'failed', 'reason', v_assignment->>'message'));
      continue;
    end if;
    assigned_count := assigned_count + 1;

    -- بعد الإسناد، أعد جلب الاقتراح للمادة نفسها
    select * into v_suggestion
    from public.schedule_missing_subject_suggestions(p_academic_period_id)
    where class_name = p_class_name
      and section_code = p_section_code
      and subject_id = r.subject_id
    limit 1;

    if v_suggestion.can_auto_add then
      v_add := public.add_missing_schedule_slot(
        p_academic_period_id,
        v_suggestion.section_id,
        v_suggestion.subject_id,
        v_suggestion.teacher_id,
        v_suggestion.suggested_day,
        v_suggestion.suggested_period
      );

      if coalesce((v_add->>'ok')::boolean,false) then
        added_count := added_count + 1;
        messages := messages || jsonb_build_array(jsonb_build_object('subject', r.required_subject, 'status', 'added', 'teacher_id', v_teacher_id));
      else
        failed_count := failed_count + 1;
        messages := messages || jsonb_build_array(jsonb_build_object('subject', r.required_subject, 'status', 'assigned_not_added', 'reason', v_add->>'message'));
      end if;
    else
      messages := messages || jsonb_build_array(jsonb_build_object('subject', r.required_subject, 'status', 'assigned_only', 'reason', v_suggestion.reason));
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'assigned_count', assigned_count,
    'added_count', added_count,
    'failed_count', failed_count,
    'messages', messages
  );
end;
$$;

grant execute on function public.auto_assign_and_add_missing_subjects(uuid,text,text,text) to authenticated;

notify pgrst, 'reload schema';

select 'assignment_permission_and_auto_missing_ready' as status;

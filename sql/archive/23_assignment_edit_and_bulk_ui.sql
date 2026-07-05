-- =============================================================
-- مدارس أمين الرضا (ع) — تعديل/تعطيل إسنادات المعلمين وربط الحصص
-- يكمل صفحة section-assignment-management.html
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) دالة تعديل إسناد معلم موجود
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
  if not exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)) then
    return jsonb_build_object('ok',false,'message','ليست لديك صلاحية تعديل الإسنادات');
  end if;

  select * into old_assignment
  from public.teacher_assignments
  where id = p_assignment_id;

  if old_assignment.id is null then
    return jsonb_build_object('ok',false,'message','الإسناد غير موجود');
  end if;

  select * into sec
  from public.sections
  where id = p_section_id;

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
-- 2) تفعيل/تعطيل إسناد
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
  if not exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)) then
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

  -- عند إيقاف الإسناد، يمكن ترك الجدول كما هو أو فك ارتباطه حسب اختيار المستخدم.
  if p_update_linked_schedule and p_active = false then
    update public.weekly_schedule
    set teacher_assignment_id = null
    where teacher_assignment_id = p_assignment_id;

    update public.class_sessions
    set teacher_assignment_id = null
    where teacher_assignment_id = p_assignment_id;
  end if;

  -- عند إعادة التفعيل، لا نغيّر الحصص تلقائياً لتجنب ربط غير مقصود.
  return jsonb_build_object('ok',true,'message',case when p_active then 'تم تفعيل الإسناد' else 'تم إيقاف الإسناد' end);
end;
$$;

grant execute on function public.set_teacher_assignment_active(uuid,boolean,boolean) to authenticated;

-- -------------------------------------------------------------
-- 3) تحسين Views لتفصل النشط والمتوقف
-- -------------------------------------------------------------
create or replace view public.v_teacher_assignments
with (security_invoker=true) as
select
  ta.id as teacher_assignment_id,
  ta.academic_year,
  ta.academic_period_id,
  ap.name as academic_period_name,
  ta.teacher_id,
  u.name as teacher_name,
  ta.class_id,
  c.name as class_name,
  ta.section_id,
  sec.code as section_code,
  sec.name as section_name,
  ta.subject_id,
  sub.name as subject_name,
  ta.weekly_hours,
  ta.is_active
from public.teacher_assignments ta
left join public.users u on u.id = ta.teacher_id
left join public.classes c on c.id = ta.class_id
left join public.sections sec on sec.id = ta.section_id
left join public.subjects sub on sub.id = ta.subject_id
left join public.academic_periods ap on ap.id = ta.academic_period_id
where public.current_user_is_admin()
   or (ta.teacher_id = auth.uid() and ta.is_active = true);

create or replace view public.v_teacher_schedule
with (security_invoker=true) as
select
  ws.id,
  ws.academic_period_id,
  ap.name as academic_period_name,
  ws.class_id,
  c.name as class_name,
  ws.section_id,
  sec.code as section_code,
  sec.name as section_name,
  ws.subject_id,
  sub.name as subject_name,
  ws.teacher_id,
  u.name as teacher_name,
  ws.day,
  ws.period_number,
  ws.teacher_assignment_id
from public.weekly_schedule ws
left join public.academic_periods ap on ap.id = ws.academic_period_id
left join public.classes c on c.id = ws.class_id
left join public.sections sec on sec.id = ws.section_id
left join public.subjects sub on sub.id = ws.subject_id
left join public.users u on u.id = ws.teacher_id
left join public.teacher_assignments ta on ta.id = ws.teacher_assignment_id
where public.current_user_is_admin()
   or (ta.teacher_id = auth.uid() and ta.is_active = true)
   or (ws.teacher_assignment_id is null and ws.teacher_id = auth.uid());

grant select on public.v_teacher_assignments to authenticated;
grant select on public.v_teacher_schedule to authenticated;

notify pgrst, 'reload schema';

select 'assignment_edit_ready' as status;

-- =============================================================
-- مدارس أمين الرضا (ع) — تضييق خيارات مخطط المنهج حسب جدول المعلم
-- المعلم يرى فقط الصفوف/الشعب/المواد المسندة له في v_teacher_schedule أو v_teacher_assignments.
-- الإدارة/الأكاديمي يرى الكل.
-- =============================================================

create extension if not exists pgcrypto;

create or replace function public.get_curriculum_planner_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  u record;
  is_admin_like boolean := false;
  plans jsonb := '[]'::jsonb;
  progress jsonb := '[]'::jsonb;
  slots jsonb := '[]'::jsonb;
  sources jsonb := '[]'::jsonb;
  classes jsonb := '[]'::jsonb;
  subjects jsonb := '[]'::jsonb;
  sections jsonb := '[]'::jsonb;
  periods jsonb := '[]'::jsonb;
  audit jsonb := '[]'::jsonb;
begin
  select id,name,email,role,is_super_admin into u from public.users where id=auth.uid();
  if u.id is null then return jsonb_build_object('ok',false,'message','يجب تسجيل الدخول'); end if;
  if to_regprocedure('public.current_user_can_curriculum()') is not null and not public.current_user_can_curriculum() then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية تخطيط المنهج');
  end if;

  is_admin_like := coalesce(u.is_super_admin,false) or u.role in ('admin','academic','academic_admin','scientific','supervisor');

  if to_regclass('public.curriculum_plans') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    into plans
    from (select * from public.curriculum_plans where teacher_id=u.id or is_admin_like order by created_at desc limit 100) x;
  end if;

  if to_regclass('public.v_curriculum_plan_progress') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.last_update desc nulls last), '[]'::jsonb)
    into progress
    from (select * from public.v_curriculum_plan_progress where teacher_id=u.id or is_admin_like order by last_update desc nulls last limit 100) x;
  end if;

  if to_regclass('public.v_curriculum_plan_slots_detailed') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.month_index, x.week_index, x.slot_order), '[]'::jsonb)
    into slots
    from (select * from public.v_curriculum_plan_slots_detailed where teacher_id=u.id or is_admin_like order by month_index, week_index, slot_order limit 1500) x;
  end if;

  if to_regclass('public.curriculum_sources') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    into sources
    from (select * from public.curriculum_sources where teacher_id=u.id or is_admin_like order by created_at desc limit 100) x;
  end if;

  -- الصفوف/المواد/الشعب: المعلم يرى المسند له فقط.
  if is_admin_like then
    if to_regclass('public.classes') is not null then
      select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name), '[]'::jsonb) into classes from public.classes;
    end if;
    if to_regclass('public.subjects') is not null then
      select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name), '[]'::jsonb) into subjects from public.subjects;
    end if;
    if to_regclass('public.sections') is not null then
      select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code,'class_id',class_id) order by name), '[]'::jsonb) into sections from public.sections;
    end if;
  else
    if to_regclass('public.v_teacher_schedule') is not null then
      select coalesce(jsonb_agg(distinct jsonb_build_object('id',x.class_id,'name',x.class_name)), '[]'::jsonb)
      into classes
      from public.v_teacher_schedule x
      where x.teacher_id=u.id and x.class_id is not null;

      select coalesce(jsonb_agg(distinct jsonb_build_object('id',x.subject_id,'name',x.subject_name)), '[]'::jsonb)
      into subjects
      from public.v_teacher_schedule x
      where x.teacher_id=u.id and x.subject_id is not null;

      select coalesce(jsonb_agg(distinct jsonb_build_object('id',x.section_id,'name',coalesce(x.section_name,x.section_code,x.class_name),'code',x.section_code,'class_id',x.class_id)), '[]'::jsonb)
      into sections
      from public.v_teacher_schedule x
      where x.teacher_id=u.id and x.section_id is not null;
    elsif to_regclass('public.v_teacher_assignments') is not null then
      select coalesce(jsonb_agg(distinct jsonb_build_object('id',x.class_id,'name',x.class_name)), '[]'::jsonb)
      into classes
      from public.v_teacher_assignments x
      where x.teacher_id=u.id and x.class_id is not null;

      select coalesce(jsonb_agg(distinct jsonb_build_object('id',x.subject_id,'name',x.subject_name)), '[]'::jsonb)
      into subjects
      from public.v_teacher_assignments x
      where x.teacher_id=u.id and x.subject_id is not null;

      select coalesce(jsonb_agg(distinct jsonb_build_object('id',x.section_id,'name',coalesce(x.section_name,x.section_code,x.class_name),'code',x.section_code,'class_id',x.class_id)), '[]'::jsonb)
      into sections
      from public.v_teacher_assignments x
      where x.teacher_id=u.id and x.section_id is not null;
    end if;
  end if;

  if to_regclass('public.academic_periods') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name), '[]'::jsonb) into periods from public.academic_periods;
  end if;

  if to_regclass('public.curriculum_plan_audit') is not null and to_regclass('public.curriculum_plans') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    into audit
    from (
      select a.* from public.curriculum_plan_audit a
      left join public.curriculum_plans p on p.id=a.plan_id
      where p.teacher_id=u.id or is_admin_like
      order by a.created_at desc limit 80
    ) x;
  end if;

  return jsonb_build_object(
    'ok',true,
    'profile',to_jsonb(u),
    'scoped_for_teacher', not is_admin_like,
    'plans',plans,
    'progress',progress,
    'slots',slots,
    'sources',sources,
    'classes',classes,
    'subjects',subjects,
    'sections',sections,
    'periods',periods,
    'audit',audit,
    'scope_note', case when is_admin_like then 'الإدارة ترى كل الصفوف والمواد' else 'المعلم يرى فقط الصفوف والمواد المسندة له في الجدول' end
  );
end;
$$;

grant execute on function public.get_curriculum_planner_payload() to authenticated;

create or replace function public.curriculum_teacher_scope_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'checked_at', now(),
    'payload_rpc', to_regprocedure('public.get_curriculum_planner_payload()') is not null,
    'teacher_schedule_view', to_regclass('public.v_teacher_schedule') is not null,
    'teacher_assignments_view', to_regclass('public.v_teacher_assignments') is not null,
    'note', 'مخطط المنهج يستخدم الصفوف والمواد المسندة للمعلم فقط، بينما الإدارة ترى الكل.'
  );
end;
$$;

grant execute on function public.curriculum_teacher_scope_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.curriculum_teacher_scope_health_check() as curriculum_teacher_scope_health;

-- ============================================================================
-- 135) Hotfix أمني: تقييد create_session_homework بصاحب الحصة أو الإدارة فقط
--
-- المشكلة:
-- النسخة السابقة من create_session_homework لم تتحقق من هوية المستدعي.
--
-- الحل:
-- لا يسمح بإنشاء واجب مرتبط بحصة إلا إذا كان:
-- - المعلم/المعلمة نفسها للحصة
-- - أو مدير / مسؤول أعلى
-- - أو معاون/إدارة أكاديمية
-- ============================================================================

create or replace function public.current_user_can_manage_teacher_workflow()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1
    from public.users u
    where u.id = auth.uid()
      and (
        coalesce(u.is_super_admin,false)=true
        or u.role in ('admin','academic','academic_admin','scientific','supervisor')
      )
  );
$$;

grant execute on function public.current_user_can_manage_teacher_workflow() to authenticated;

create or replace function public.create_session_homework(
  p_session_id uuid,
  p_title text,
  p_description text default null,
  p_due_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s record;
  hw_id uuid;
  actor uuid := auth.uid();
begin
  select * into s
  from public.class_sessions
  where id = p_session_id;

  if s.id is null then
    return jsonb_build_object('ok', false, 'message', 'الحصة غير موجودة');
  end if;

  if s.teacher_id is null then
    return jsonb_build_object('ok', false, 'message', 'لا توجد معلمة مرتبطة بهذه الحصة');
  end if;

  if actor is not null and s.teacher_id <> actor and not public.current_user_can_manage_teacher_workflow() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إنشاء واجب لهذه الحصة');
  end if;

  if s.status = 'holiday' then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن إنشاء واجب في يوم عطلة');
  end if;

  insert into public.homeworks (
    class_session_id,
    academic_period_id,
    class_id,
    subject_id,
    teacher_id,
    title,
    description,
    assigned_date,
    due_date,
    status
  ) values (
    p_session_id,
    s.academic_period_id,
    s.class_id,
    s.subject_id,
    s.teacher_id,
    coalesce(nullif(trim(p_title),''),'واجب'),
    p_description,
    s.session_date,
    p_due_date,
    'published'
  ) returning id into hw_id;

  insert into public.teacher_activity_log (
    class_session_id,
    teacher_id,
    activity_type,
    evidence_table,
    evidence_id,
    activity_weight,
    notes,
    created_by
  ) values (
    p_session_id,
    s.teacher_id,
    'homework',
    'homeworks',
    hw_id,
    1,
    'تم تسجيل نشاط بسبب نشر واجب',
    actor
  ) on conflict do nothing;

  update public.class_sessions
  set status = 'completed', updated_at = now()
  where id = p_session_id;

  return jsonb_build_object('ok', true, 'message', 'تم إنشاء الواجب وتثبيت نشاط المعلم', 'homework_id', hw_id);
end;
$$;

grant execute on function public.create_session_homework(uuid,text,text,date) to authenticated;

notify pgrst, 'reload schema';

select 'teacher_homework_permission_hotfix_ready' as status;

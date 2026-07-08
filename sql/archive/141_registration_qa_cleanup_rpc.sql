-- ============================================================================
-- تنظيف آمن لسجلات QA الخاصة بمحور التسجيلات
--
-- الهدف:
-- 1) معاينة السجلات المرشحة للحذف قبل التنفيذ
-- 2) حذف سجلات QA من registration_families / registration_students / registration_teachers
-- 3) حذف الحسابات المفعّلة الناتجة عن QA اختيارياً عند تمرير p_remove_activated = true
--
-- مبدأ الأمان:
-- - لا يعمل إلا للمسؤول الإداري / super admin
-- - يرفض أي وسم لا يبدأ بـ QA
-- - الحذف يعتمد على Prefix واضح في الاسم/اسم المستخدم/البريد المحلي
--
-- أمثلة مقترحة للوسم:
--   QA-REG-20260709
--   QA-TEACHER-
--
-- يفضّل استخدام نفس الوسم عند:
-- - guardian_name / student_name / full_name
-- - generated_username
--
-- ثم تشغيل:
--   select public.registration_qa_cleanup_preview('QA-REG-20260709');
--   select public.registration_qa_cleanup_execute('QA-REG-20260709', false);
--   select public.registration_qa_cleanup_execute('QA-REG-20260709', true);
-- ============================================================================

create or replace function public.registration_qa_cleanup_preview(p_tag text default 'QA-')
returns jsonb
language plpgsql
security definer
set search_path = public, auth, storage
as $$
declare
  v_tag text := trim(coalesce(p_tag, 'QA-'));
  v_prefix text;

  v_family_ids uuid[] := '{}'::uuid[];
  v_reg_student_ids uuid[] := '{}'::uuid[];
  v_teacher_reg_ids uuid[] := '{}'::uuid[];

  v_parent_user_ids uuid[] := '{}'::uuid[];
  v_student_user_ids uuid[] := '{}'::uuid[];
  v_teacher_user_ids uuid[] := '{}'::uuid[];
  v_public_student_ids uuid[] := '{}'::uuid[];
  v_all_user_ids uuid[] := '{}'::uuid[];

  v_photo_paths text[] := '{}'::text[];
begin
  if not public.is_admin_user() then
    raise exception 'غير مصرح: هذه الدالة للمسؤول الإداري فقط';
  end if;

  if v_tag = '' or upper(left(v_tag, 2)) <> 'QA' then
    raise exception 'وسم QA غير صالح. يجب أن يبدأ بـ QA';
  end if;

  v_prefix := lower(regexp_replace(v_tag, '[^a-zA-Z0-9]', '', 'g'));
  if coalesce(length(v_prefix), 0) < 2 then
    raise exception 'وسم QA بعد التنقية قصير جداً';
  end if;

  select coalesce(array_agg(distinct f.id), '{}'::uuid[])
    into v_family_ids
  from public.registration_families f
  where f.guardian_name ilike v_tag || '%'
     or lower(coalesce(f.generated_username, '')) like v_prefix || '%';

  select coalesce(array_agg(distinct s.id), '{}'::uuid[])
    into v_reg_student_ids
  from public.registration_students s
  where s.family_id = any(v_family_ids)
     or s.student_name ilike v_tag || '%'
     or lower(coalesce(s.generated_username, '')) like v_prefix || '%';

  select coalesce(array_agg(distinct t.id), '{}'::uuid[])
    into v_teacher_reg_ids
  from public.registration_teachers t
  where t.full_name ilike v_tag || '%'
     or lower(coalesce(t.generated_username, '')) like v_prefix || '%';

  select coalesce(array_agg(distinct u.id), '{}'::uuid[])
    into v_parent_user_ids
  from public.users u
  where lower(coalesce(u.role, '')) = 'parent'
    and (
      u.name ilike v_tag || '%'
      or lower(split_part(coalesce(u.email, ''), '@', 1)) like v_prefix || '%'
    );

  select coalesce(array_agg(distinct u.id), '{}'::uuid[])
    into v_student_user_ids
  from public.users u
  where lower(coalesce(u.role, '')) = 'student'
    and (
      u.name ilike v_tag || '%'
      or lower(split_part(coalesce(u.email, ''), '@', 1)) like v_prefix || '%'
    );

  select coalesce(array_agg(distinct u.id), '{}'::uuid[])
    into v_teacher_user_ids
  from public.users u
  where lower(coalesce(u.role, '')) = 'teacher'
    and (
      u.name ilike v_tag || '%'
      or lower(split_part(coalesce(u.email, ''), '@', 1)) like v_prefix || '%'
    );

  select coalesce(array_agg(distinct s.id), '{}'::uuid[])
    into v_public_student_ids
  from public.students s
  where s.id = any(v_student_user_ids)
     or s.user_id = any(v_student_user_ids)
     or s.student_name ilike v_tag || '%';

  select coalesce(array_agg(distinct x), '{}'::uuid[])
    into v_all_user_ids
  from unnest(v_parent_user_ids || v_student_user_ids || v_teacher_user_ids) as x;

  select coalesce(array_agg(distinct photo_path), '{}'::text[])
    into v_photo_paths
  from (
    select rs.photo_path
    from public.registration_students rs
    where rs.id = any(v_reg_student_ids)
      and rs.photo_path is not null
      and btrim(rs.photo_path) <> ''
    union all
    select rt.photo_path
    from public.registration_teachers rt
    where rt.id = any(v_teacher_reg_ids)
      and rt.photo_path is not null
      and btrim(rt.photo_path) <> ''
  ) q;

  return jsonb_build_object(
    'ok', true,
    'tag', v_tag,
    'username_prefix', v_prefix,
    'registration_candidates', jsonb_build_object(
      'families', coalesce(array_length(v_family_ids, 1), 0),
      'students', coalesce(array_length(v_reg_student_ids, 1), 0),
      'teachers', coalesce(array_length(v_teacher_reg_ids, 1), 0)
    ),
    'activated_candidates', jsonb_build_object(
      'parent_users', coalesce(array_length(v_parent_user_ids, 1), 0),
      'student_users', coalesce(array_length(v_student_user_ids, 1), 0),
      'teacher_users', coalesce(array_length(v_teacher_user_ids, 1), 0),
      'public_students', coalesce(array_length(v_public_student_ids, 1), 0),
      'auth_users_total', coalesce(array_length(v_all_user_ids, 1), 0)
    ),
    'storage_candidates', jsonb_build_object(
      'photo_objects', coalesce(array_length(v_photo_paths, 1), 0)
    ),
    'note', 'هذه معاينة فقط. استخدم registration_qa_cleanup_execute بعد التحقق من النتائج.'
  );
end;
$$;

grant execute on function public.registration_qa_cleanup_preview(text) to authenticated;


create or replace function public.registration_qa_cleanup_execute(
  p_tag text default 'QA-',
  p_remove_activated boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, storage
as $$
declare
  v_tag text := trim(coalesce(p_tag, 'QA-'));
  v_prefix text;

  v_family_ids uuid[] := '{}'::uuid[];
  v_reg_student_ids uuid[] := '{}'::uuid[];
  v_teacher_reg_ids uuid[] := '{}'::uuid[];

  v_parent_user_ids uuid[] := '{}'::uuid[];
  v_student_user_ids uuid[] := '{}'::uuid[];
  v_teacher_user_ids uuid[] := '{}'::uuid[];
  v_public_student_ids uuid[] := '{}'::uuid[];
  v_all_user_ids uuid[] := '{}'::uuid[];

  v_photo_paths text[] := '{}'::text[];

  v_deleted_storage int := 0;
  v_deleted_public_students int := 0;
  v_deleted_public_users int := 0;
  v_deleted_auth_identities int := 0;
  v_deleted_auth_users int := 0;
  v_deleted_reg_students int := 0;
  v_deleted_reg_families int := 0;
  v_deleted_reg_teachers int := 0;
begin
  if not public.is_admin_user() then
    raise exception 'غير مصرح: هذه الدالة للمسؤول الإداري فقط';
  end if;

  if v_tag = '' or upper(left(v_tag, 2)) <> 'QA' then
    raise exception 'وسم QA غير صالح. يجب أن يبدأ بـ QA';
  end if;

  v_prefix := lower(regexp_replace(v_tag, '[^a-zA-Z0-9]', '', 'g'));
  if coalesce(length(v_prefix), 0) < 2 then
    raise exception 'وسم QA بعد التنقية قصير جداً';
  end if;

  select coalesce(array_agg(distinct f.id), '{}'::uuid[])
    into v_family_ids
  from public.registration_families f
  where f.guardian_name ilike v_tag || '%'
     or lower(coalesce(f.generated_username, '')) like v_prefix || '%';

  select coalesce(array_agg(distinct s.id), '{}'::uuid[])
    into v_reg_student_ids
  from public.registration_students s
  where s.family_id = any(v_family_ids)
     or s.student_name ilike v_tag || '%'
     or lower(coalesce(s.generated_username, '')) like v_prefix || '%';

  select coalesce(array_agg(distinct t.id), '{}'::uuid[])
    into v_teacher_reg_ids
  from public.registration_teachers t
  where t.full_name ilike v_tag || '%'
     or lower(coalesce(t.generated_username, '')) like v_prefix || '%';

  select coalesce(array_agg(distinct u.id), '{}'::uuid[])
    into v_parent_user_ids
  from public.users u
  where lower(coalesce(u.role, '')) = 'parent'
    and (
      u.name ilike v_tag || '%'
      or lower(split_part(coalesce(u.email, ''), '@', 1)) like v_prefix || '%'
    );

  select coalesce(array_agg(distinct u.id), '{}'::uuid[])
    into v_student_user_ids
  from public.users u
  where lower(coalesce(u.role, '')) = 'student'
    and (
      u.name ilike v_tag || '%'
      or lower(split_part(coalesce(u.email, ''), '@', 1)) like v_prefix || '%'
    );

  select coalesce(array_agg(distinct u.id), '{}'::uuid[])
    into v_teacher_user_ids
  from public.users u
  where lower(coalesce(u.role, '')) = 'teacher'
    and (
      u.name ilike v_tag || '%'
      or lower(split_part(coalesce(u.email, ''), '@', 1)) like v_prefix || '%'
    );

  select coalesce(array_agg(distinct s.id), '{}'::uuid[])
    into v_public_student_ids
  from public.students s
  where s.id = any(v_student_user_ids)
     or s.user_id = any(v_student_user_ids)
     or s.student_name ilike v_tag || '%';

  select coalesce(array_agg(distinct x), '{}'::uuid[])
    into v_all_user_ids
  from unnest(v_parent_user_ids || v_student_user_ids || v_teacher_user_ids) as x;

  select coalesce(array_agg(distinct photo_path), '{}'::text[])
    into v_photo_paths
  from (
    select rs.photo_path
    from public.registration_students rs
    where rs.id = any(v_reg_student_ids)
      and rs.photo_path is not null
      and btrim(rs.photo_path) <> ''
    union all
    select rt.photo_path
    from public.registration_teachers rt
    where rt.id = any(v_teacher_reg_ids)
      and rt.photo_path is not null
      and btrim(rt.photo_path) <> ''
  ) q;

  if coalesce(array_length(v_photo_paths, 1), 0) > 0 then
    delete from storage.objects
    where name = any(v_photo_paths)
      and bucket_id in ('registration-photos', 'student-photos');
    get diagnostics v_deleted_storage = row_count;
  end if;

  if p_remove_activated then
    if coalesce(array_length(v_public_student_ids, 1), 0) > 0 then
      delete from public.students
      where id = any(v_public_student_ids)
         or user_id = any(v_student_user_ids);
      get diagnostics v_deleted_public_students = row_count;
    end if;

    if coalesce(array_length(v_all_user_ids, 1), 0) > 0 then
      delete from public.users where id = any(v_all_user_ids);
      get diagnostics v_deleted_public_users = row_count;

      delete from auth.identities where user_id = any(v_all_user_ids);
      get diagnostics v_deleted_auth_identities = row_count;

      delete from auth.users where id = any(v_all_user_ids);
      get diagnostics v_deleted_auth_users = row_count;
    end if;
  end if;

  if coalesce(array_length(v_reg_student_ids, 1), 0) > 0 then
    delete from public.registration_students where id = any(v_reg_student_ids);
    get diagnostics v_deleted_reg_students = row_count;
  end if;

  if coalesce(array_length(v_family_ids, 1), 0) > 0 then
    delete from public.registration_families where id = any(v_family_ids);
    get diagnostics v_deleted_reg_families = row_count;
  end if;

  if coalesce(array_length(v_teacher_reg_ids, 1), 0) > 0 then
    delete from public.registration_teachers where id = any(v_teacher_reg_ids);
    get diagnostics v_deleted_reg_teachers = row_count;
  end if;

  return jsonb_build_object(
    'ok', true,
    'tag', v_tag,
    'remove_activated', p_remove_activated,
    'deleted', jsonb_build_object(
      'storage_objects', v_deleted_storage,
      'registration_students', v_deleted_reg_students,
      'registration_families', v_deleted_reg_families,
      'registration_teachers', v_deleted_reg_teachers,
      'public_students', v_deleted_public_students,
      'public_users', v_deleted_public_users,
      'auth_identities', v_deleted_auth_identities,
      'auth_users', v_deleted_auth_users
    ),
    'note', case when p_remove_activated then 'تم حذف سجلات التسجيل وسجلات التفعيل المرتبطة بوسم QA.' else 'تم حذف سجلات التسجيل فقط. لم تُحذف الحسابات المفعّلة.' end
  );
end;
$$;

grant execute on function public.registration_qa_cleanup_execute(text, boolean) to authenticated;

notify pgrst, 'reload schema';

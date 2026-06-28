-- =============================================================
-- مدارس أمين الرضا (ع) — تشخيص وإصلاح ربط واجبات الطالب بالشعبة/الصف
-- يستخدم بعد أن تكون v/RPC موجودة لكن واجباتي لا تعرض شيئاً.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) RPC واجبات الطالب مع معلومات debug للواجهة
-- -------------------------------------------------------------
create or replace function public.get_student_homeworks_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  result jsonb := '[]'::jsonb;
  debug jsonb := '{}'::jsonb;
  uid uuid := auth.uid();
  my_students_count int := 0;
  published_count int := 0;
begin
  select count(*) into published_count
  from public.homeworks
  where status in ('published','closed')
    and (publish_at is null or publish_at <= now());

  if uid is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'لا توجد جلسة مستخدم. افتحي الصفحة بعد تسجيل الدخول كطالب أو ولي أمر.',
      'homeworks', '[]'::jsonb,
      'debug', jsonb_build_object('auth_uid', null, 'published_homeworks', published_count)
    );
  end if;

  with my_students as (
    select s.*
    from public.students s
    where s.user_id = uid
       or s.parent_id = uid
  )
  select count(*) into my_students_count from my_students;

  with my_students as (
    select s.*
    from public.students s
    where s.user_id = uid
       or s.parent_id = uid
  ),
  visible_homeworks as (
    select
      h.id as homework_id,
      h.title,
      h.description,
      h.status,
      h.publish_at,
      h.assigned_date,
      h.due_date,
      h.due_time,
      h.max_score,
      h.class_id,
      c.name as class_name,
      h.section_id,
      sec.code as section_code,
      h.subject_id,
      sub.name as subject_name,
      h.teacher_id,
      u.name as teacher_name,
      ms.id as student_id,
      ms.name as student_name,
      hg.score as grade_score,
      hg.max_score as grade_max_score,
      hg.feedback as grade_feedback,
      hg.graded_at,
      coalesce(att.attachment_count,0) as attachment_count,
      h.created_at,
      h.updated_at,
      case
        when h.section_id is not null and ms.section_id = h.section_id then 'student.section_id'
        when h.section_id is not null and exists(select 1 from public.student_enrollments se where se.student_id = ms.id and se.section_id = h.section_id and se.enrollment_status = 'active') then 'student_enrollments.section_id'
        when h.section_id is null and ms.class_id = h.class_id then 'student.class_id'
        when h.section_id is null and exists(select 1 from public.student_enrollments se where se.student_id = ms.id and se.class_id = h.class_id and se.enrollment_status = 'active') then 'student_enrollments.class_id'
        else 'unknown'
      end as match_source
    from public.homeworks h
    join my_students ms
      on (
        (h.section_id is not null and (
          ms.section_id = h.section_id
          or exists(select 1 from public.student_enrollments se where se.student_id = ms.id and se.section_id = h.section_id and se.enrollment_status = 'active')
        ))
        or
        (h.section_id is null and h.class_id is not null and (
          ms.class_id = h.class_id
          or exists(select 1 from public.student_enrollments se where se.student_id = ms.id and se.class_id = h.class_id and se.enrollment_status = 'active')
        ))
      )
    left join public.classes c on c.id = h.class_id
    left join public.sections sec on sec.id = h.section_id
    left join public.subjects sub on sub.id = h.subject_id
    left join public.users u on u.id = h.teacher_id
    left join public.homework_grades hg on hg.homework_id = h.id and hg.student_id = ms.id
    left join lateral (
      select count(*) as attachment_count
      from public.homework_attachments ha
      where ha.homework_id = h.id
    ) att on true
    where h.status in ('published','closed')
      and (h.publish_at is null or h.publish_at <= now())
  )
  select coalesce(jsonb_agg(to_jsonb(vh) order by vh.due_date nulls last, vh.created_at desc), '[]'::jsonb)
  into result
  from visible_homeworks vh;

  debug := jsonb_build_object(
    'auth_uid', uid,
    'my_students_count', my_students_count,
    'published_homeworks', published_count,
    'visible_homeworks', jsonb_array_length(coalesce(result,'[]'::jsonb))
  );

  return jsonb_build_object('ok', true, 'homeworks', coalesce(result,'[]'::jsonb), 'debug', debug);
end;
$$;

grant execute on function public.get_student_homeworks_payload() to authenticated;

-- -------------------------------------------------------------
-- 2) تقرير عام لا يعتمد على auth.uid لمعرفة هل الواجبات تطابق الطلاب أم لا.
-- -------------------------------------------------------------
create or replace function public.student_homeworks_match_report()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  students_json jsonb;
  homeworks_json jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(x) order by x.student_name), '[]'::jsonb)
  into students_json
  from (
    select
      s.id as student_id,
      s.name as student_name,
      s.user_id,
      s.parent_id,
      s.class_id,
      c.name as class_name,
      s.section_id,
      sec.code as section_code,
      coalesce(en.enrollments,'[]'::jsonb) as active_enrollments,
      (
        select count(*)
        from public.homeworks h
        where h.status in ('published','closed')
          and (h.publish_at is null or h.publish_at <= now())
          and (
            (h.section_id is not null and (s.section_id = h.section_id or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.section_id=h.section_id and se.enrollment_status='active')))
            or
            (h.section_id is null and h.class_id is not null and (s.class_id = h.class_id or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.class_id=h.class_id and se.enrollment_status='active')))
          )
      ) as matching_homeworks_count,
      coalesce((
        select jsonb_agg(jsonb_build_object('title', h.title, 'status', h.status, 'class_id', h.class_id, 'section_id', h.section_id) order by h.created_at desc)
        from public.homeworks h
        where h.status in ('published','closed')
          and (h.publish_at is null or h.publish_at <= now())
          and (
            (h.section_id is not null and (s.section_id = h.section_id or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.section_id=h.section_id and se.enrollment_status='active')))
            or
            (h.section_id is null and h.class_id is not null and (s.class_id = h.class_id or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.class_id=h.class_id and se.enrollment_status='active')))
          )
      ), '[]'::jsonb) as matching_homeworks
    from public.students s
    left join public.classes c on c.id = s.class_id
    left join public.sections sec on sec.id = s.section_id
    left join lateral (
      select jsonb_agg(jsonb_build_object('class_id', se.class_id, 'section_id', se.section_id, 'status', se.enrollment_status, 'academic_year', se.academic_year)) as enrollments
      from public.student_enrollments se
      where se.student_id = s.id
        and se.enrollment_status = 'active'
    ) en on true
  ) x;

  select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at desc), '[]'::jsonb)
  into homeworks_json
  from (
    select
      h.id,
      h.title,
      h.status,
      h.class_id,
      c.name as class_name,
      h.section_id,
      sec.code as section_code,
      h.publish_at,
      h.due_date,
      h.created_at
    from public.homeworks h
    left join public.classes c on c.id = h.class_id
    left join public.sections sec on sec.id = h.section_id
    where h.status in ('published','closed')
    order by h.created_at desc
    limit 20
  ) h;

  return jsonb_build_object(
    'checked_at', now(),
    'students', students_json,
    'published_homeworks', homeworks_json
  );
end;
$$;

grant execute on function public.student_homeworks_match_report() to authenticated;

-- -------------------------------------------------------------
-- 3) مزامنة students.class_id/section_id من active enrollment عند الحاجة.
-- افتراضياً تقرير فقط. استخدم p_apply=true للتنفيذ.
-- -------------------------------------------------------------
create or replace function public.sync_students_from_active_enrollments(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  changes jsonb;
  updated_count int := 0;
begin
  with latest as (
    select distinct on (se.student_id)
      se.student_id,
      se.class_id,
      se.section_id,
      se.academic_year
    from public.student_enrollments se
    where se.enrollment_status = 'active'
    order by se.student_id, se.updated_at desc nulls last, se.created_at desc nulls last
  ),
  diff as (
    select
      s.id as student_id,
      s.name as student_name,
      s.class_id as old_class_id,
      l.class_id as new_class_id,
      s.section_id as old_section_id,
      l.section_id as new_section_id,
      s.academic_year as old_academic_year,
      l.academic_year as new_academic_year
    from public.students s
    join latest l on l.student_id = s.id
    where s.class_id is distinct from l.class_id
       or s.section_id is distinct from l.section_id
       or coalesce(s.academic_year,'') is distinct from coalesce(l.academic_year,'')
  )
  select coalesce(jsonb_agg(to_jsonb(diff)), '[]'::jsonb)
  into changes
  from diff;

  if p_apply then
    with latest as (
      select distinct on (se.student_id)
        se.student_id,
        se.class_id,
        se.section_id,
        se.academic_year
      from public.student_enrollments se
      where se.enrollment_status = 'active'
      order by se.student_id, se.updated_at desc nulls last, se.created_at desc nulls last
    )
    update public.students s
    set class_id = l.class_id,
        section_id = l.section_id,
        academic_year = coalesce(l.academic_year, s.academic_year)
    from latest l
    where s.id = l.student_id
      and (
        s.class_id is distinct from l.class_id
        or s.section_id is distinct from l.section_id
        or coalesce(s.academic_year,'') is distinct from coalesce(l.academic_year,'')
      );

    get diagnostics updated_count = row_count;
  end if;

  return jsonb_build_object(
    'ok', true,
    'apply', p_apply,
    'updated_count', updated_count,
    'changes', changes
  );
end;
$$;

grant execute on function public.sync_students_from_active_enrollments(boolean) to authenticated;

-- -------------------------------------------------------------
-- 4) Health Check محدّث
-- -------------------------------------------------------------
create or replace function public.student_homeworks_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  payload jsonb;
begin
  payload := public.get_student_homeworks_payload();

  return jsonb_build_object(
    'checked_at', now(),
    'auth_uid', uid,
    'rpc_exists', to_regprocedure('public.get_student_homeworks_payload()') is not null,
    'view_exists', to_regclass('public.v_student_homeworks') is not null,
    'homeworks_table_exists', to_regclass('public.homeworks') is not null,
    'published_homeworks', (select count(*) from public.homeworks where status in ('published','closed')),
    'student_count', (select count(*) from public.students),
    'payload_ok', payload->>'ok',
    'payload_debug', payload->'debug',
    'attachments_count', (select count(*) from public.homework_attachments),
    'grades_count', (select count(*) from public.homework_grades),
    'sample_match_report_hint', 'إذا كانت visible_homeworks=0 في الموقع، شغّل select public.student_homeworks_match_report();'
  );
end;
$$;

grant execute on function public.student_homeworks_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'student_homeworks_visibility_diagnostics_ready' as status;

-- =============================================================
-- مدارس أمين الرضا (ع) — Payload لتقارير متابعة الواجبات للمعلم والإدارة
-- يعالج لبس SQL Editor حيث auth.uid() = null، ويوفر RPC مباشر للواجهة.
-- =============================================================

create extension if not exists pgcrypto;

-- تأكيد دالة الإدارة الأساسية
create or replace function public.current_user_is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (u.role = 'admin' or coalesce(u.is_super_admin,false)=true)
  );
$$;

grant execute on function public.current_user_is_admin() to authenticated;

-- تأكيد دالة مطابقة الطالب مع الواجب
create or replace function public.student_matches_homework(p_student_id uuid, p_homework_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1
    from public.homeworks h
    join public.students s on s.id = p_student_id
    where h.id = p_homework_id
      and (
        (h.section_id is not null and (
          s.section_id = h.section_id
          or exists(
            select 1 from public.student_enrollments se
            where se.student_id = s.id
              and se.section_id = h.section_id
              and se.enrollment_status = 'active'
          )
        ))
        or
        (h.section_id is null and h.class_id is not null and (
          s.class_id = h.class_id
          or exists(
            select 1 from public.student_enrollments se
            where se.student_id = s.id
              and se.class_id = h.class_id
              and se.enrollment_status = 'active'
          )
        ))
      )
  );
$$;

grant execute on function public.student_matches_homework(uuid,uuid) to authenticated;

-- -------------------------------------------------------------
-- RPC رئيسي للتقارير
-- إذا auth.uid() = null في SQL Editor يرجع كل البيانات للتشخيص فقط.
-- في الواجهة لا يعمل إلا للمستخدم authenticated.
-- -------------------------------------------------------------
create or replace function public.get_homework_followup_payload(p_homework_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  uid uuid := auth.uid();
  reports jsonb := '[]'::jsonb;
  missing jsonb := '[]'::jsonb;
  stats jsonb := '{}'::jsonb;
begin
  with scoped_homeworks as (
    select h.*
    from public.homeworks h
    where (p_homework_id is null or h.id = p_homework_id)
      and (
        uid is null
        or public.current_user_is_admin()
        or h.teacher_id = uid
      )
  ),
  assigned as (
    select
      h.id as homework_id,
      h.title,
      h.status,
      h.teacher_id,
      u.name as teacher_name,
      h.class_id,
      c.name as class_name,
      h.section_id,
      sec.code as section_code,
      h.subject_id,
      sub.name as subject_name,
      h.publish_at,
      h.due_date,
      h.due_time,
      h.max_score,
      h.created_at,
      h.updated_at,
      s.id as student_id
    from scoped_homeworks h
    left join public.users u on u.id = h.teacher_id
    left join public.classes c on c.id = h.class_id
    left join public.sections sec on sec.id = h.section_id
    left join public.subjects sub on sub.id = h.subject_id
    left join public.students s on public.student_matches_homework(s.id, h.id)
  ),
  report_rows as (
    select
      a.homework_id,
      max(a.title) as title,
      max(a.status) as status,
      max(a.teacher_id::text)::uuid as teacher_id,
      max(a.teacher_name) as teacher_name,
      max(a.class_id::text)::uuid as class_id,
      max(a.class_name) as class_name,
      max(a.section_id::text)::uuid as section_id,
      max(a.section_code) as section_code,
      max(a.subject_id::text)::uuid as subject_id,
      max(a.subject_name) as subject_name,
      max(a.publish_at) as publish_at,
      max(a.due_date) as due_date,
      max(a.due_time) as due_time,
      max(a.max_score) as max_score,
      count(distinct a.student_id) filter (where a.student_id is not null) as assigned_count,
      count(distinct hs.student_id) filter (where hs.status in ('submitted','late','graded','returned')) as submitted_count,
      count(distinct hs.student_id) filter (where hs.status = 'late') as late_count,
      count(distinct hs.student_id) filter (where hs.status = 'graded') as graded_count,
      greatest(count(distinct a.student_id) filter (where a.student_id is not null) - count(distinct hs.student_id) filter (where hs.status in ('submitted','late','graded','returned')), 0) as missing_count,
      round(100.0 * count(distinct hs.student_id) filter (where hs.status in ('submitted','late','graded','returned')) / nullif(count(distinct a.student_id) filter (where a.student_id is not null),0), 2) as submitted_percent,
      round(avg(case when hg.max_score > 0 then hg.score / hg.max_score * 100 end),2) as average_grade_percent,
      max(a.created_at) as created_at,
      max(a.updated_at) as updated_at
    from assigned a
    left join public.homework_submissions hs on hs.homework_id = a.homework_id and hs.student_id = a.student_id
    left join public.homework_grades hg on hg.homework_id = a.homework_id and hg.student_id = a.student_id
    group by a.homework_id
  )
  select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc), '[]'::jsonb)
  into reports
  from report_rows r;

  with scoped_homeworks as (
    select h.*
    from public.homeworks h
    where h.status = 'published'
      and (h.publish_at is null or h.publish_at <= now())
      and (p_homework_id is null or h.id = p_homework_id)
      and (
        uid is null
        or public.current_user_is_admin()
        or h.teacher_id = uid
      )
  ),
  missing_rows as (
    select
      h.id as homework_id,
      h.title,
      h.status as homework_status,
      h.teacher_id,
      h.class_id,
      c.name as class_name,
      h.section_id,
      sec.code as section_code,
      h.subject_id,
      sub.name as subject_name,
      h.due_date,
      h.due_time,
      s.id as student_id,
      s.name as student_name,
      s.user_id as student_user_id,
      s.parent_id,
      hs.id as submission_id,
      hs.status as submission_status,
      hs.updated_at as submission_updated_at,
      case
        when hs.id is null then 'no_submission'
        when hs.status = 'draft' then 'draft_only'
        else hs.status
      end as missing_status,
      case
        when h.due_date is null then false
        when now() > (h.due_date + coalesce(h.due_time, time '23:59')) then true
        else false
      end as is_overdue,
      case
        when h.due_date is null then null
        else extract(day from ((h.due_date + coalesce(h.due_time, time '23:59')) - now()))::int
      end as days_until_due
    from scoped_homeworks h
    join public.students s on public.student_matches_homework(s.id, h.id)
    left join public.homework_submissions hs on hs.homework_id = h.id and hs.student_id = s.id
    left join public.classes c on c.id = h.class_id
    left join public.sections sec on sec.id = h.section_id
    left join public.subjects sub on sub.id = h.subject_id
    where hs.id is null or hs.status = 'draft'
  )
  select coalesce(jsonb_agg(to_jsonb(m) order by m.due_date nulls last, m.student_name), '[]'::jsonb)
  into missing
  from missing_rows m;

  stats := jsonb_build_object(
    'reports_count', jsonb_array_length(coalesce(reports,'[]'::jsonb)),
    'missing_count', jsonb_array_length(coalesce(missing,'[]'::jsonb)),
    'published_homeworks', (select count(*) from public.homeworks where status='published'),
    'submissions_count', (select count(*) from public.homework_submissions),
    'auth_uid', uid,
    'sql_editor_mode', uid is null
  );

  return jsonb_build_object('ok', true, 'reports', reports, 'missing', missing, 'stats', stats);
end;
$$;

grant execute on function public.get_homework_followup_payload(uuid) to authenticated;

-- -------------------------------------------------------------
-- فحص محدّث لا يعتمد على Views الأمنية
-- -------------------------------------------------------------
create or replace function public.homework_followup_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
begin
  payload := public.get_homework_followup_payload(null);
  return jsonb_build_object(
    'checked_at', now(),
    'completion_view_exists', to_regclass('public.v_homework_completion_report') is not null,
    'missing_view_exists', to_regclass('public.v_homework_missing_students') is not null,
    'payload_rpc_exists', to_regprocedure('public.get_homework_followup_payload(uuid)') is not null,
    'published_homeworks', (select count(*) from public.homeworks where status='published'),
    'submissions_count', (select count(*) from public.homework_submissions),
    'payload_stats', payload->'stats',
    'note', 'في SQL Editor يكون auth_uid=null، لذلك Views قد تظهر صفر، لكن payload يرجع بيانات التشخيص.'
  );
end;
$$;

grant execute on function public.homework_followup_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'homework_followup_payload_reports_page_ready' as status;

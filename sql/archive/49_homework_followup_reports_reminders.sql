-- =============================================================
-- مدارس أمين الرضا (ع) — تقارير متابعة الواجبات وتذكير المتأخرين
-- للمعلم والإدارة: نسبة التسليم، غير المسلّمين، متوسط الدرجات، إرسال تذكير.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) تأكيد الجداول الأساسية
-- -------------------------------------------------------------
create table if not exists public.school_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid null references public.users(id) on delete cascade,
  recipient_role text,
  title text not null,
  body text,
  notification_type text not null default 'info',
  entity_table text,
  entity_id uuid,
  read_at timestamptz,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.homework_submissions (
  id uuid primary key default gen_random_uuid(),
  homework_id uuid not null references public.homeworks(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  answer_text text,
  status text not null default 'draft',
  submitted_at timestamptz,
  reviewed_by uuid null references public.users(id),
  reviewed_at timestamptz,
  teacher_feedback text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- -------------------------------------------------------------
-- 2) مطابقة الطالب مع الواجب
-- -------------------------------------------------------------
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
-- 3) تقرير إنجاز الواجبات
-- -------------------------------------------------------------
create or replace view public.v_homework_completion_report
with (security_invoker=true) as
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
  count(distinct s.id) as assigned_count,
  count(distinct hs.student_id) filter (where hs.status in ('submitted','late','graded','returned')) as submitted_count,
  count(distinct hs.student_id) filter (where hs.status = 'late') as late_count,
  count(distinct hs.student_id) filter (where hs.status = 'graded') as graded_count,
  greatest(count(distinct s.id) - count(distinct hs.student_id) filter (where hs.status in ('submitted','late','graded','returned')), 0) as missing_count,
  round(
    100.0 * count(distinct hs.student_id) filter (where hs.status in ('submitted','late','graded','returned')) / nullif(count(distinct s.id),0),
    2
  ) as submitted_percent,
  round(avg(case when hg.max_score > 0 then hg.score / hg.max_score * 100 end),2) as average_grade_percent,
  h.created_at,
  h.updated_at
from public.homeworks h
left join public.users u on u.id = h.teacher_id
left join public.classes c on c.id = h.class_id
left join public.sections sec on sec.id = h.section_id
left join public.subjects sub on sub.id = h.subject_id
left join public.students s on public.student_matches_homework(s.id, h.id)
left join public.homework_submissions hs on hs.homework_id = h.id and hs.student_id = s.id
left join public.homework_grades hg on hg.homework_id = h.id and hg.student_id = s.id
where public.current_user_is_admin()
   or h.teacher_id = auth.uid()
group by h.id, h.title, h.status, h.teacher_id, u.name, h.class_id, c.name, h.section_id, sec.code, h.subject_id, sub.name, h.publish_at, h.due_date, h.due_time, h.max_score, h.created_at, h.updated_at;

grant select on public.v_homework_completion_report to authenticated;

-- -------------------------------------------------------------
-- 4) الطلاب الذين لم يسلموا أو ما زالوا على مسودة
-- -------------------------------------------------------------
create or replace view public.v_homework_missing_students
with (security_invoker=true) as
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
from public.homeworks h
join public.students s on public.student_matches_homework(s.id, h.id)
left join public.homework_submissions hs on hs.homework_id = h.id and hs.student_id = s.id
left join public.classes c on c.id = h.class_id
left join public.sections sec on sec.id = h.section_id
left join public.subjects sub on sub.id = h.subject_id
where h.status = 'published'
  and (h.publish_at is null or h.publish_at <= now())
  and (public.current_user_is_admin() or h.teacher_id = auth.uid())
  and (hs.id is null or hs.status = 'draft');

grant select on public.v_homework_missing_students to authenticated;

-- -------------------------------------------------------------
-- 5) إرسال تذكير للطلاب/الأهل غير المسلّمين
-- -------------------------------------------------------------
create or replace function public.send_homework_reminders(p_homework_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  inserted_students int := 0;
  inserted_parents int := 0;
  total_students int := 0;
  total_parents int := 0;
begin
  if p_homework_id is not null then
    select * into h from public.homeworks where id = p_homework_id;
    if h.id is null then
      return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود');
    end if;
    if not (public.current_user_is_admin() or h.teacher_id = auth.uid()) then
      return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إرسال تذكير لهذا الواجب');
    end if;
  end if;

  -- الطلاب
  insert into public.school_notifications(
    recipient_user_id,
    recipient_role,
    title,
    body,
    notification_type,
    entity_table,
    entity_id,
    created_by
  )
  select distinct
    ms.student_user_id,
    'student',
    'تذكير بتسليم واجب',
    'يرجى تسليم الواجب: ' || coalesce(ms.title,'واجب') || case when ms.due_date is not null then ' — الموعد: ' || ms.due_date::text else '' end,
    'homework_reminder',
    'homeworks',
    ms.homework_id,
    auth.uid()
  from public.v_homework_missing_students ms
  where ms.student_user_id is not null
    and (p_homework_id is null or ms.homework_id = p_homework_id)
    and not exists(
      select 1 from public.school_notifications n
      where n.recipient_user_id = ms.student_user_id
        and n.entity_table = 'homeworks'
        and n.entity_id = ms.homework_id
        and n.notification_type = 'homework_reminder'
        and n.created_at::date = current_date
    );

  get diagnostics inserted_students = row_count;

  -- أولياء الأمور
  insert into public.school_notifications(
    recipient_user_id,
    recipient_role,
    title,
    body,
    notification_type,
    entity_table,
    entity_id,
    created_by
  )
  select distinct
    ms.parent_id,
    'parent',
    'تذكير بتسليم واجب الطالب',
    'لم يتم تسليم الواجب بعد: ' || coalesce(ms.title,'واجب') || case when ms.due_date is not null then ' — الموعد: ' || ms.due_date::text else '' end,
    'homework_reminder',
    'homeworks',
    ms.homework_id,
    auth.uid()
  from public.v_homework_missing_students ms
  where ms.parent_id is not null
    and (p_homework_id is null or ms.homework_id = p_homework_id)
    and not exists(
      select 1 from public.school_notifications n
      where n.recipient_user_id = ms.parent_id
        and n.entity_table = 'homeworks'
        and n.entity_id = ms.homework_id
        and n.notification_type = 'homework_reminder'
        and n.created_at::date = current_date
    );

  get diagnostics inserted_parents = row_count;

  return jsonb_build_object(
    'ok', true,
    'message', 'تم إرسال التذكيرات',
    'students', inserted_students,
    'parents', inserted_parents,
    'count', inserted_students + inserted_parents
  );
end;
$$;

grant execute on function public.send_homework_reminders(uuid) to authenticated;

-- -------------------------------------------------------------
-- 6) فحص سريع
-- -------------------------------------------------------------
create or replace function public.homework_followup_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'completion_view_exists', to_regclass('public.v_homework_completion_report') is not null,
    'missing_view_exists', to_regclass('public.v_homework_missing_students') is not null,
    'published_homeworks', (select count(*) from public.homeworks where status='published'),
    'submissions_count', (select count(*) from public.homework_submissions),
    'missing_rows_visible_to_current_user', (select count(*) from public.v_homework_missing_students),
    'completion_rows_visible_to_current_user', (select count(*) from public.v_homework_completion_report)
  );
end;
$$;

grant execute on function public.homework_followup_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'homework_followup_reports_reminders_ready' as status;

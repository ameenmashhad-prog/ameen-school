-- =============================================================
-- مدارس أمين الرضا (ع) — Mega Batch: مشاهدة الواجب + التعليقات + تذكير من لم يفتح
-- 10+ تحسينات دفعة واحدة لتسريع متابعة الواجبات.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) جداول مشاهدة الواجب والتعليقات
-- -------------------------------------------------------------
create table if not exists public.homework_views (
  id uuid primary key default gen_random_uuid(),
  homework_id uuid not null references public.homeworks(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  viewed_by uuid null references public.users(id),
  viewed_at timestamptz not null default now(),
  last_viewed_at timestamptz not null default now(),
  view_count int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(homework_id, student_id)
);

create table if not exists public.homework_submission_comments (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.homework_submissions(id) on delete cascade,
  author_id uuid null references public.users(id),
  author_role text,
  comment_text text not null,
  is_internal boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_homework_views_homework on public.homework_views(homework_id, student_id);
create index if not exists idx_homework_comments_submission on public.homework_submission_comments(submission_id, created_at);

-- -------------------------------------------------------------
-- 2) صلاحيات القراءة/الكتابة
-- -------------------------------------------------------------
create or replace function public.can_read_homework_submission(p_submission_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  hs record;
  h record;
begin
  select * into hs from public.homework_submissions where id = p_submission_id;
  if hs.id is null then return false; end if;

  select * into h from public.homeworks where id = hs.homework_id;
  if h.id is null then return false; end if;

  return public.current_user_is_admin()
    or h.teacher_id = auth.uid()
    or exists(select 1 from public.students s where s.id = hs.student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()));
end;
$$;

grant execute on function public.can_read_homework_submission(uuid) to authenticated;

create or replace function public.can_comment_homework_submission(p_submission_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.can_read_homework_submission(p_submission_id);
$$;

grant execute on function public.can_comment_homework_submission(uuid) to authenticated;

alter table public.homework_views enable row level security;
alter table public.homework_submission_comments enable row level security;

drop policy if exists homework_views_read_scoped on public.homework_views;
drop policy if exists homework_views_write_scoped on public.homework_views;
drop policy if exists homework_comments_read_scoped on public.homework_submission_comments;
drop policy if exists homework_comments_write_scoped on public.homework_submission_comments;

create policy homework_views_read_scoped on public.homework_views
  for select to authenticated
  using (
    public.current_user_is_admin()
    or exists(select 1 from public.students s where s.id = student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
    or exists(select 1 from public.homeworks h where h.id = homework_id and h.teacher_id = auth.uid())
  );

create policy homework_views_write_scoped on public.homework_views
  for all to authenticated
  using (
    public.current_user_is_admin()
    or exists(select 1 from public.students s where s.id = student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
    or exists(select 1 from public.homeworks h where h.id = homework_id and h.teacher_id = auth.uid())
  )
  with check (
    public.current_user_is_admin()
    or exists(select 1 from public.students s where s.id = student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
    or exists(select 1 from public.homeworks h where h.id = homework_id and h.teacher_id = auth.uid())
  );

create policy homework_comments_read_scoped on public.homework_submission_comments
  for select to authenticated
  using (public.can_read_homework_submission(submission_id));

create policy homework_comments_write_scoped on public.homework_submission_comments
  for all to authenticated
  using (public.can_comment_homework_submission(submission_id))
  with check (public.can_comment_homework_submission(submission_id));

grant select, insert, update on public.homework_views to authenticated;
grant select, insert, update, delete on public.homework_submission_comments to authenticated;

-- -------------------------------------------------------------
-- 3) تعليم الواجب كمشاهد
-- -------------------------------------------------------------
create or replace function public.mark_homework_viewed(
  p_homework_id uuid,
  p_student_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  st record;
  view_id uuid;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود'); end if;

  select * into st from public.students where id = p_student_id;
  if st.id is null then return jsonb_build_object('ok', false, 'message', 'الطالب غير موجود'); end if;

  if not (public.current_user_is_admin() or st.user_id = auth.uid() or st.parent_id = auth.uid() or h.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعليم مشاهدة هذا الواجب');
  end if;

  if not public.student_matches_homework(p_student_id, p_homework_id) then
    return jsonb_build_object('ok', false, 'message', 'هذا الواجب غير مخصص لهذا الطالب');
  end if;

  update public.homework_views
  set last_viewed_at = now(),
      view_count = coalesce(view_count,0) + 1,
      viewed_by = auth.uid(),
      updated_at = now()
  where homework_id = p_homework_id
    and student_id = p_student_id
  returning id into view_id;

  if view_id is null then
    insert into public.homework_views(homework_id, student_id, viewed_by)
    values (p_homework_id, p_student_id, auth.uid())
    returning id into view_id;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم تسجيل مشاهدة الواجب', 'view_id', view_id);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.mark_homework_viewed(uuid,uuid) to authenticated;

-- -------------------------------------------------------------
-- 4) إضافة تعليق على تسليم الواجب
-- -------------------------------------------------------------
create or replace function public.add_homework_submission_comment(
  p_submission_id uuid,
  p_comment_text text,
  p_is_internal boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  hs record;
  h record;
  st record;
  u record;
  comment_id uuid;
  author_role text;
  is_teacher boolean := false;
begin
  if nullif(trim(coalesce(p_comment_text,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'نص التعليق مطلوب');
  end if;

  select * into hs from public.homework_submissions where id = p_submission_id;
  if hs.id is null then return jsonb_build_object('ok', false, 'message', 'تسليم الواجب غير موجود'); end if;

  select * into h from public.homeworks where id = hs.homework_id;
  if h.id is null then return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود'); end if;

  select * into st from public.students where id = hs.student_id;
  select * into u from public.users where id = auth.uid();
  author_role := coalesce(u.role, 'user');
  is_teacher := public.current_user_is_admin() or h.teacher_id = auth.uid();

  if not public.can_comment_homework_submission(p_submission_id) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية التعليق على هذا التسليم');
  end if;

  if p_is_internal and not is_teacher then
    return jsonb_build_object('ok', false, 'message', 'التعليق الداخلي للمعلم والإدارة فقط');
  end if;

  insert into public.homework_submission_comments(submission_id, author_id, author_role, comment_text, is_internal)
  values (p_submission_id, auth.uid(), author_role, trim(p_comment_text), coalesce(p_is_internal,false))
  returning id into comment_id;

  -- إشعار الطرف الآخر فقط للتعليقات غير الداخلية
  if not coalesce(p_is_internal,false) then
    if is_teacher then
      insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
      select st.user_id, 'student', 'تعليق جديد على الواجب', coalesce(h.title,'واجب') || ' — ' || left(trim(p_comment_text),120), 'homework_comment', 'homework_submissions', p_submission_id, auth.uid()
      where st.user_id is not null;

      insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
      select st.parent_id, 'parent', 'تعليق جديد على واجب الطالب', coalesce(h.title,'واجب') || ' — ' || left(trim(p_comment_text),120), 'homework_comment', 'homework_submissions', p_submission_id, auth.uid()
      where st.parent_id is not null;
    else
      insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
      select h.teacher_id, 'teacher', 'تعليق طالب على الواجب', coalesce(st.name,'طالب') || ' — ' || left(trim(p_comment_text),120), 'homework_comment', 'homework_submissions', p_submission_id, auth.uid()
      where h.teacher_id is not null;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم إضافة التعليق', 'comment_id', comment_id);
exception when others then
  perform public.log_teacher_error('add_homework_submission_comment', sqlerrm, jsonb_build_object('submission_id', p_submission_id));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.add_homework_submission_comment(uuid,text,boolean) to authenticated;

-- -------------------------------------------------------------
-- 5) View التعليقات
-- -------------------------------------------------------------
drop view if exists public.v_homework_submission_comments_detailed;

create view public.v_homework_submission_comments_detailed
with (security_invoker=true) as
select
  c.id as comment_id,
  c.submission_id,
  hs.homework_id,
  hs.student_id,
  h.teacher_id,
  c.author_id,
  u.name as author_name,
  c.author_role,
  c.comment_text,
  c.is_internal,
  c.created_at,
  c.updated_at
from public.homework_submission_comments c
join public.homework_submissions hs on hs.id = c.submission_id
join public.homeworks h on h.id = hs.homework_id
left join public.users u on u.id = c.author_id
where public.can_read_homework_submission(c.submission_id)
  and (
    c.is_internal = false
    or public.current_user_is_admin()
    or h.teacher_id = auth.uid()
  );

grant select on public.v_homework_submission_comments_detailed to authenticated;

-- -------------------------------------------------------------
-- 6) تذكير من لم يفتح الواجب
-- -------------------------------------------------------------
create or replace function public.send_homework_not_viewed_reminders(p_homework_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  inserted_students int := 0;
  inserted_parents int := 0;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود'); end if;

  if not (public.current_user_is_admin() or h.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إرسال تذكير لهذا الواجب');
  end if;

  insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
  select distinct s.user_id, 'student', 'لم يتم فتح الواجب بعد', 'يرجى فتح الواجب: ' || coalesce(h.title,'واجب'), 'homework_not_viewed', 'homeworks', h.id, auth.uid()
  from public.students s
  where s.user_id is not null
    and public.student_matches_homework(s.id, h.id)
    and not exists(select 1 from public.homework_views hv where hv.homework_id = h.id and hv.student_id = s.id)
    and not exists(select 1 from public.school_notifications n where n.recipient_user_id=s.user_id and n.entity_id=h.id and n.notification_type='homework_not_viewed' and n.created_at::date=current_date);
  get diagnostics inserted_students = row_count;

  insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
  select distinct s.parent_id, 'parent', 'الطالب لم يفتح الواجب بعد', 'يرجى متابعة الواجب: ' || coalesce(h.title,'واجب'), 'homework_not_viewed', 'homeworks', h.id, auth.uid()
  from public.students s
  where s.parent_id is not null
    and public.student_matches_homework(s.id, h.id)
    and not exists(select 1 from public.homework_views hv where hv.homework_id = h.id and hv.student_id = s.id)
    and not exists(select 1 from public.school_notifications n where n.recipient_user_id=s.parent_id and n.entity_id=h.id and n.notification_type='homework_not_viewed' and n.created_at::date=current_date);
  get diagnostics inserted_parents = row_count;

  return jsonb_build_object('ok', true, 'message', 'تم إرسال تذكير لمن لم يفتح الواجب', 'students', inserted_students, 'parents', inserted_parents, 'count', inserted_students+inserted_parents);
end;
$$;

grant execute on function public.send_homework_not_viewed_reminders(uuid) to authenticated;

-- -------------------------------------------------------------
-- 7) Payload متابعة فتح الواجب
-- -------------------------------------------------------------
create or replace function public.get_homework_engagement_payload(p_homework_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  reports jsonb;
  not_viewed jsonb;
  uid uuid := auth.uid();
begin
  with scoped_homeworks as (
    select h.* from public.homeworks h
    where (p_homework_id is null or h.id = p_homework_id)
      and (uid is null or public.current_user_is_admin() or h.teacher_id = uid)
  ), assigned as (
    select h.id as homework_id, h.title, h.teacher_id, h.status, s.id as student_id, s.name as student_name, hv.last_viewed_at, hv.view_count
    from scoped_homeworks h
    join public.students s on public.student_matches_homework(s.id,h.id)
    left join public.homework_views hv on hv.homework_id=h.id and hv.student_id=s.id
  )
  select coalesce(jsonb_agg(to_jsonb(r) order by r.title), '[]'::jsonb)
  into reports
  from (
    select homework_id, max(title) as title, max(status) as status, count(*) as assigned_count, count(last_viewed_at) as viewed_count, count(*)-count(last_viewed_at) as not_viewed_count, round(100.0*count(last_viewed_at)/nullif(count(*),0),2) as viewed_percent
    from assigned
    group by homework_id
  ) r;

  with scoped_homeworks as (
    select h.* from public.homeworks h
    where (p_homework_id is null or h.id = p_homework_id)
      and (uid is null or public.current_user_is_admin() or h.teacher_id = uid)
  )
  select coalesce(jsonb_agg(to_jsonb(x) order by x.title, x.student_name), '[]'::jsonb)
  into not_viewed
  from (
    select h.id as homework_id, h.title, s.id as student_id, s.name as student_name, s.user_id, s.parent_id
    from scoped_homeworks h
    join public.students s on public.student_matches_homework(s.id,h.id)
    where not exists(select 1 from public.homework_views hv where hv.homework_id=h.id and hv.student_id=s.id)
  ) x;

  return jsonb_build_object('ok', true, 'reports', coalesce(reports,'[]'::jsonb), 'not_viewed', coalesce(not_viewed,'[]'::jsonb));
end;
$$;

grant execute on function public.get_homework_engagement_payload(uuid) to authenticated;

-- -------------------------------------------------------------
-- 8) تحديث Payload واجبات الطالب ليشمل المشاهدة والتعليقات
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
  select count(*) into published_count from public.homeworks where status in ('published','closed') and (publish_at is null or publish_at <= now());

  if uid is null then
    return jsonb_build_object('ok', false, 'message', 'لا توجد جلسة مستخدم', 'homeworks', '[]'::jsonb, 'debug', jsonb_build_object('auth_uid', null, 'published_homeworks', published_count));
  end if;

  with my_students as (select s.* from public.students s where s.user_id = uid or s.parent_id = uid)
  select count(*) into my_students_count from my_students;

  with my_students as (
    select s.* from public.students s where s.user_id = uid or s.parent_id = uid
  ), visible_homeworks as (
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
      hs.id as submission_id,
      hs.status as submission_status,
      hs.answer_text as submission_answer_text,
      hs.submitted_at,
      hs.teacher_feedback as submission_teacher_feedback,
      hv.last_viewed_at as viewed_at,
      hv.view_count,
      coalesce(satt.submission_attachment_count,0) as submission_attachment_count,
      coalesce(cmt.comments_count,0) as comments_count,
      coalesce(att.attachment_count,0) as attachment_count,
      h.created_at,
      h.updated_at
    from public.homeworks h
    join my_students ms on public.student_matches_homework(ms.id, h.id)
    left join public.classes c on c.id = h.class_id
    left join public.sections sec on sec.id = h.section_id
    left join public.subjects sub on sub.id = h.subject_id
    left join public.users u on u.id = h.teacher_id
    left join public.homework_grades hg on hg.homework_id = h.id and hg.student_id = ms.id
    left join public.homework_submissions hs on hs.homework_id = h.id and hs.student_id = ms.id
    left join public.homework_views hv on hv.homework_id = h.id and hv.student_id = ms.id
    left join lateral (select count(*) as attachment_count from public.homework_attachments ha where ha.homework_id = h.id) att on true
    left join lateral (select count(*) as submission_attachment_count from public.homework_submission_attachments hsa where hsa.submission_id = hs.id) satt on true
    left join lateral (select count(*) as comments_count from public.homework_submission_comments hc where hc.submission_id = hs.id and (hc.is_internal=false or public.current_user_is_admin() or h.teacher_id=auth.uid())) cmt on true
    where h.status in ('published','closed') and (h.publish_at is null or h.publish_at <= now())
  )
  select coalesce(jsonb_agg(to_jsonb(vh) order by vh.due_date nulls last, vh.created_at desc), '[]'::jsonb)
  into result
  from visible_homeworks vh;

  debug := jsonb_build_object('auth_uid', uid, 'my_students_count', my_students_count, 'published_homeworks', published_count, 'visible_homeworks', jsonb_array_length(coalesce(result,'[]'::jsonb)));
  return jsonb_build_object('ok', true, 'homeworks', coalesce(result,'[]'::jsonb), 'debug', debug);
end;
$$;

grant execute on function public.get_student_homeworks_payload() to authenticated;

-- -------------------------------------------------------------
-- 9) Health
-- -------------------------------------------------------------
create or replace function public.homework_engagement_comments_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'homework_views', to_regclass('public.homework_views') is not null,
    'homework_comments', to_regclass('public.homework_submission_comments') is not null,
    'comments_view', to_regclass('public.v_homework_submission_comments_detailed') is not null,
    'mark_viewed_rpc', to_regprocedure('public.mark_homework_viewed(uuid,uuid)') is not null,
    'add_comment_rpc', to_regprocedure('public.add_homework_submission_comment(uuid,text,boolean)') is not null,
    'engagement_rpc', to_regprocedure('public.get_homework_engagement_payload(uuid)') is not null,
    'views_count', (select count(*) from public.homework_views),
    'comments_count', (select count(*) from public.homework_submission_comments)
  );
end;
$$;

grant execute on function public.homework_engagement_comments_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'homework_engagement_comments_mega_batch_ready' as status;

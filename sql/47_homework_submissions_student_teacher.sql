-- =============================================================
-- مدارس أمين الرضا (ع) — تسليم الواجبات من الطالب ومراجعتها من المعلم
-- يدعم: نص الإجابة، مرفقات الطالب، حفظ مسودة، تسليم، مراجعة وتصحيح.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) جداول تسليم الواجبات
-- -------------------------------------------------------------
create table if not exists public.homework_submissions (
  id uuid primary key default gen_random_uuid(),
  homework_id uuid not null references public.homeworks(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  answer_text text,
  status text not null default 'draft' check (status in ('draft','submitted','late','returned','graded','cancelled')),
  submitted_at timestamptz,
  reviewed_by uuid null references public.users(id),
  reviewed_at timestamptz,
  teacher_feedback text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.homework_submission_attachments (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.homework_submissions(id) on delete cascade,
  file_name text not null,
  file_type text,
  file_size bigint,
  storage_path text not null,
  sort_order int not null default 0,
  uploaded_by uuid null references public.users(id),
  created_at timestamptz not null default now()
);

-- تنظيف التكرارات إن وجدت ثم إنشاء unique index، لكن الدوال لا تعتمد على ON CONFLICT.
with ranked as (
  select id, row_number() over(partition by homework_id, student_id order by updated_at desc nulls last, created_at desc nulls last, id desc) rn
  from public.homework_submissions
)
delete from public.homework_submissions hs using ranked r where hs.id=r.id and r.rn>1;

do $$ begin
  begin
    create unique index if not exists uq_homework_submissions_homework_student on public.homework_submissions(homework_id, student_id);
  exception when others then
    raise notice 'تعذر إنشاء unique index لتسليمات الواجب: %', sqlerrm;
  end;
end $$;

create index if not exists idx_homework_submissions_homework on public.homework_submissions(homework_id, status);
create index if not exists idx_homework_submissions_student on public.homework_submissions(student_id, updated_at desc);
create index if not exists idx_homework_submission_attachments_submission on public.homework_submission_attachments(submission_id, sort_order);

-- -------------------------------------------------------------
-- 2) Storage bucket لمرفقات تسليم الطالب
-- -------------------------------------------------------------
do $$ begin
  begin
    insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
    values (
      'homework-submissions',
      'homework-submissions',
      false,
      26214400,
      array[
        'image/jpeg','image/png','image/webp','application/pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation'
      ]
    )
    on conflict (id) do update
    set public=false,
        file_size_limit=excluded.file_size_limit,
        allowed_mime_types=excluded.allowed_mime_types;

    if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='homework_submissions_storage_select') then
      create policy homework_submissions_storage_select on storage.objects
        for select to authenticated
        using (bucket_id='homework-submissions');
    end if;
    if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='homework_submissions_storage_insert') then
      create policy homework_submissions_storage_insert on storage.objects
        for insert to authenticated
        with check (bucket_id='homework-submissions');
    end if;
    if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='homework_submissions_storage_update') then
      create policy homework_submissions_storage_update on storage.objects
        for all to authenticated
        using (bucket_id='homework-submissions')
        with check (bucket_id='homework-submissions');
    end if;
  exception when others then
    raise notice 'تعذر إنشاء bucket/policies homework-submissions: %', sqlerrm;
  end;
end $$;

-- -------------------------------------------------------------
-- 3) RLS للجداول
-- -------------------------------------------------------------
alter table public.homework_submissions enable row level security;
alter table public.homework_submission_attachments enable row level security;

drop policy if exists homework_submissions_read_scoped on public.homework_submissions;
drop policy if exists homework_submissions_student_write on public.homework_submissions;
drop policy if exists homework_submission_attachments_read_scoped on public.homework_submission_attachments;
drop policy if exists homework_submission_attachments_write_scoped on public.homework_submission_attachments;

create policy homework_submissions_read_scoped on public.homework_submissions
  for select to authenticated
  using (
    public.current_user_is_admin()
    or exists(select 1 from public.students s where s.id=student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid()))
    or exists(select 1 from public.homeworks h where h.id=homework_id and h.teacher_id=auth.uid())
  );

create policy homework_submissions_student_write on public.homework_submissions
  for all to authenticated
  using (
    public.current_user_is_admin()
    or exists(select 1 from public.students s where s.id=student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid()))
    or exists(select 1 from public.homeworks h where h.id=homework_id and h.teacher_id=auth.uid())
  )
  with check (
    public.current_user_is_admin()
    or exists(select 1 from public.students s where s.id=student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid()))
    or exists(select 1 from public.homeworks h where h.id=homework_id and h.teacher_id=auth.uid())
  );

create policy homework_submission_attachments_read_scoped on public.homework_submission_attachments
  for select to authenticated
  using (exists(select 1 from public.homework_submissions hs where hs.id=submission_id));

create policy homework_submission_attachments_write_scoped on public.homework_submission_attachments
  for all to authenticated
  using (exists(select 1 from public.homework_submissions hs where hs.id=submission_id and (
    public.current_user_is_admin()
    or exists(select 1 from public.students s where s.id=hs.student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid()))
    or exists(select 1 from public.homeworks h where h.id=hs.homework_id and h.teacher_id=auth.uid())
  )))
  with check (exists(select 1 from public.homework_submissions hs where hs.id=submission_id and (
    public.current_user_is_admin()
    or exists(select 1 from public.students s where s.id=hs.student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid()))
    or exists(select 1 from public.homeworks h where h.id=hs.homework_id and h.teacher_id=auth.uid())
  )));

grant select, insert, update, delete on public.homework_submissions to authenticated;
grant select, insert, update, delete on public.homework_submission_attachments to authenticated;

-- -------------------------------------------------------------
-- 4) Helpers
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
          or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.section_id=h.section_id and se.enrollment_status='active')
        ))
        or
        (h.section_id is null and h.class_id is not null and (
          s.class_id = h.class_id
          or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.class_id=h.class_id and se.enrollment_status='active')
        ))
      )
  );
$$;

grant execute on function public.student_matches_homework(uuid,uuid) to authenticated;

-- -------------------------------------------------------------
-- 5) حفظ مسودة/تسليم الواجب من الطالب أو ولي الأمر
-- -------------------------------------------------------------
create or replace function public.save_homework_submission(
  p_homework_id uuid,
  p_student_id uuid,
  p_answer_text text default null,
  p_status text default 'draft'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  st record;
  old_s record;
  sub_id uuid;
  desired_status text := coalesce(nullif(p_status,''),'draft');
  final_status text;
  due_ts timestamptz;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود'); end if;

  if h.status <> 'published' then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن تسليم واجب غير منشور أو مغلق');
  end if;

  if h.publish_at is not null and h.publish_at > now() then
    return jsonb_build_object('ok', false, 'message', 'لم يبدأ وقت نشر هذا الواجب بعد');
  end if;

  select * into st from public.students where id = p_student_id;
  if st.id is null then return jsonb_build_object('ok', false, 'message', 'الطالب غير موجود'); end if;

  if not (public.current_user_is_admin() or st.user_id = auth.uid() or st.parent_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تسليم هذا الواجب لهذا الطالب');
  end if;

  if not public.student_matches_homework(p_student_id, p_homework_id) then
    return jsonb_build_object('ok', false, 'message', 'هذا الواجب غير مخصص لهذا الطالب');
  end if;

  if desired_status not in ('draft','submitted') then desired_status := 'draft'; end if;

  due_ts := case when h.due_date is not null then (h.due_date::text || ' ' || coalesce(h.due_time, '23:59'::time)::text)::timestamptz else null end;

  select * into old_s
  from public.homework_submissions
  where homework_id = p_homework_id and student_id = p_student_id
  order by updated_at desc nulls last, created_at desc nulls last
  limit 1;

  final_status := case
    when desired_status = 'submitted' and due_ts is not null and now() > due_ts then 'late'
    when desired_status = 'submitted' then 'submitted'
    when old_s.status in ('submitted','late','graded') then old_s.status
    else 'draft'
  end;

  if old_s.id is not null then
    update public.homework_submissions
    set answer_text = p_answer_text,
        status = final_status,
        submitted_at = case when final_status in ('submitted','late') and old_s.submitted_at is null then now() else old_s.submitted_at end,
        updated_at = now()
    where id = old_s.id
    returning id into sub_id;
  else
    insert into public.homework_submissions(homework_id, student_id, answer_text, status, submitted_at)
    values (p_homework_id, p_student_id, p_answer_text, final_status, case when final_status in ('submitted','late') then now() else null end)
    returning id into sub_id;
  end if;

  if final_status in ('submitted','late') and h.teacher_id is not null then
    insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
    select h.teacher_id, 'teacher', 'تسليم واجب من طالب', coalesce(st.name,'طالب') || ' سلّم واجب: ' || coalesce(h.title,'واجب'), 'homework_submitted', 'homework_submissions', sub_id, auth.uid()
    where not exists(
      select 1 from public.school_notifications n
      where n.recipient_user_id = h.teacher_id
        and n.entity_table = 'homework_submissions'
        and n.entity_id = sub_id
        and n.notification_type = 'homework_submitted'
    );
  end if;

  return jsonb_build_object('ok', true, 'message', case when final_status='draft' then 'تم حفظ مسودة الحل' else 'تم تسليم الواجب' end, 'submission_id', sub_id, 'status', final_status);
exception when others then
  perform public.log_teacher_error('save_homework_submission', sqlerrm, jsonb_build_object('homework_id', p_homework_id, 'student_id', p_student_id));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.save_homework_submission(uuid,uuid,text,text) to authenticated;

-- -------------------------------------------------------------
-- 6) إضافة مرفق لتسليم الطالب
-- -------------------------------------------------------------
create or replace function public.add_homework_submission_attachment(
  p_submission_id uuid,
  p_file_name text,
  p_file_type text,
  p_file_size bigint,
  p_storage_path text,
  p_sort_order int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  hs record;
  att_id uuid;
begin
  select * into hs from public.homework_submissions where id = p_submission_id;
  if hs.id is null then return jsonb_build_object('ok', false, 'message', 'تسليم الواجب غير موجود'); end if;

  if not (
    public.current_user_is_admin()
    or exists(select 1 from public.students s where s.id=hs.student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid()))
    or exists(select 1 from public.homeworks h where h.id=hs.homework_id and h.teacher_id=auth.uid())
  ) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إضافة مرفق لهذا التسليم');
  end if;

  insert into public.homework_submission_attachments(submission_id, file_name, file_type, file_size, storage_path, sort_order, uploaded_by)
  values (p_submission_id, p_file_name, p_file_type, p_file_size, p_storage_path, p_sort_order, auth.uid())
  returning id into att_id;

  return jsonb_build_object('ok', true, 'attachment_id', att_id);
exception when others then
  perform public.log_teacher_error('add_homework_submission_attachment', sqlerrm, jsonb_build_object('submission_id', p_submission_id, 'file_name', p_file_name));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.add_homework_submission_attachment(uuid,text,text,bigint,text,int) to authenticated;

-- -------------------------------------------------------------
-- 7) مراجعة وتصحيح التسليم من المعلم
-- -------------------------------------------------------------
create or replace function public.review_homework_submission(
  p_submission_id uuid,
  p_score numeric,
  p_feedback text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  hs record;
  h record;
  grade_result jsonb;
begin
  select * into hs from public.homework_submissions where id = p_submission_id;
  if hs.id is null then return jsonb_build_object('ok', false, 'message', 'تسليم الواجب غير موجود'); end if;

  select * into h from public.homeworks where id = hs.homework_id;
  if h.id is null then return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود'); end if;

  if not (public.current_user_is_admin() or h.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تصحيح هذا التسليم');
  end if;

  grade_result := public.save_homework_grade(hs.homework_id, hs.student_id, p_score, p_feedback);
  if grade_result->>'ok' <> 'true' then
    return grade_result;
  end if;

  update public.homework_submissions
  set status = 'graded',
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      teacher_feedback = p_feedback,
      updated_at = now()
  where id = p_submission_id;

  insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
  select s.user_id, 'student', 'تم تصحيح واجبك', coalesce(h.title,'واجب') || ' — الدرجة: ' || p_score::text || '/' || coalesce(h.max_score,10)::text, 'homework_graded', 'homeworks', h.id, auth.uid()
  from public.students s
  where s.id = hs.student_id and s.user_id is not null;

  insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
  select s.parent_id, 'parent', 'تم تصحيح واجب الطالب', coalesce(h.title,'واجب') || ' — الدرجة: ' || p_score::text || '/' || coalesce(h.max_score,10)::text, 'homework_graded', 'homeworks', h.id, auth.uid()
  from public.students s
  where s.id = hs.student_id and s.parent_id is not null;

  return jsonb_build_object('ok', true, 'message', 'تم تصحيح التسليم وحفظ درجة الواجب', 'grading', grade_result);
exception when others then
  perform public.log_teacher_error('review_homework_submission', sqlerrm, jsonb_build_object('submission_id', p_submission_id, 'score', p_score));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.review_homework_submission(uuid,numeric,text) to authenticated;

-- -------------------------------------------------------------
-- 8) تحديث payload واجبات الطالب ليشمل التسليم
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

  with my_students as (
    select s.* from public.students s where s.user_id = uid or s.parent_id = uid
  ) select count(*) into my_students_count from my_students;

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
      coalesce(satt.submission_attachment_count,0) as submission_attachment_count,
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
    left join lateral (select count(*) as attachment_count from public.homework_attachments ha where ha.homework_id = h.id) att on true
    left join lateral (select count(*) as submission_attachment_count from public.homework_submission_attachments hsa where hsa.submission_id = hs.id) satt on true
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
-- 9) View للمعلم لعرض التسليمات
-- -------------------------------------------------------------
create or replace view public.v_teacher_homework_submissions
with (security_invoker=true) as
select
  h.id as homework_id,
  h.title as homework_title,
  h.status as homework_status,
  h.max_score as homework_max_score,
  h.due_date,
  h.due_time,
  h.teacher_id,
  h.class_id,
  c.name as class_name,
  h.section_id,
  sec.code as section_code,
  h.subject_id,
  sub.name as subject_name,
  s.id as student_id,
  s.name as student_name,
  hs.id as submission_id,
  hs.answer_text,
  hs.status as submission_status,
  hs.submitted_at,
  hs.teacher_feedback,
  hg.score as grade_score,
  hg.max_score as grade_max_score,
  hg.feedback as grade_feedback,
  coalesce(att.attachment_count,0) as submission_attachment_count,
  hs.created_at,
  hs.updated_at
from public.homeworks h
join public.students s on public.student_matches_homework(s.id, h.id)
left join public.homework_submissions hs on hs.homework_id = h.id and hs.student_id = s.id
left join public.homework_grades hg on hg.homework_id = h.id and hg.student_id = s.id
left join public.classes c on c.id = h.class_id
left join public.sections sec on sec.id = h.section_id
left join public.subjects sub on sub.id = h.subject_id
left join lateral (select count(*) as attachment_count from public.homework_submission_attachments hsa where hsa.submission_id = hs.id) att on true
where public.current_user_is_admin() or h.teacher_id = auth.uid();

grant select on public.v_teacher_homework_submissions to authenticated;

-- -------------------------------------------------------------
-- 10) فحص سريع
-- -------------------------------------------------------------
create or replace function public.homework_submissions_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'submissions_table', to_regclass('public.homework_submissions') is not null,
    'submission_attachments_table', to_regclass('public.homework_submission_attachments') is not null,
    'teacher_view', to_regclass('public.v_teacher_homework_submissions') is not null,
    'submission_count', (select count(*) from public.homework_submissions),
    'submitted_count', (select count(*) from public.homework_submissions where status in ('submitted','late','graded')),
    'published_homeworks', (select count(*) from public.homeworks where status='published')
  );
end;
$$;

grant execute on function public.homework_submissions_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'homework_submissions_student_teacher_ready' as status;

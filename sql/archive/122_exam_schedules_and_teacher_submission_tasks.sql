-- ============================================================================
-- نظام مواعيد الامتحانات الرسمي ومهام تسليم الأسئلة الموكلة للمعلمين
-- يسمح للإدارة بضبط جداول ومواعيد الامتحانات حصراً وتكليف المعلمين بتسليم الأسئلة،
-- مع ضبط مهلة الصلاحية، وتنبيه التأخير، وإتاحة كتابة المادة المطلوبة، وإثبات
-- التسليم عبر منصات خارجية (واتساب، إيتا، بله) أو التسليم اليدوي عند انقطاع الإنترنت.
--
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

-- 1) جدول مواعيد الامتحانات الرسمي (تحدده الإدارة حصراً)
create table if not exists public.official_exam_schedules (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  term_period text not null check (term_period in ('term1_m1','term1_m2','term1_m3','midterm','term2_m1','term2_m2','final','resit2','resit3')),
  class_id uuid not null references public.classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  exam_date date not null,
  start_time time not null default '08:30',
  end_time time not null default '10:00',
  required_topics text, -- المادة المطلوبة للامتحان (يكتبها المعلم أو الإدارة)
  topics_updated_at timestamptz,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(academic_year, term_period, class_id, subject_id)
);

-- 2) جدول مهام تسليم أسئلة الامتحانات الموكلة للمعلمين
create table if not exists public.exam_submission_tasks (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid not null references public.official_exam_schedules(id) on delete cascade,
  teacher_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  submission_deadline timestamptz not null,
  status text not null default 'pending' check (status in ('pending','submitted','late','approved','rejected','offline_verified')),
  question_file_url text,
  delivery_method text not null default 'platform' check (delivery_method in ('platform','manual','whatsapp','eitaa','bale','other')),
  delivery_proof_note text,
  submitted_at timestamptz,
  reviewed_by uuid null references public.users(id),
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 3) مستودع تخزين ملفات أسئلة الامتحانات
insert into storage.buckets (id, name, public)
values ('exam-questions', 'exam-questions', true)
on conflict (id) do update set public = true;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='exam_questions_all_access') then
    create policy exam_questions_all_access on storage.objects
      for all to anon, authenticated
      using (bucket_id = 'exam-questions')
      with check (bucket_id = 'exam-questions');
  end if;
end $$;

-- 4) سياسات RLS
alter table public.official_exam_schedules enable row level security;
alter table public.exam_submission_tasks enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='official_exam_schedules' and policyname='schedules_read_all') then
    create policy schedules_read_all on public.official_exam_schedules for select to authenticated, anon using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='official_exam_schedules' and policyname='schedules_write_all') then
    create policy schedules_write_all on public.official_exam_schedules for all to authenticated using (true) with check (true);
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='exam_submission_tasks' and policyname='tasks_read_all') then
    create policy tasks_read_all on public.exam_submission_tasks for select to authenticated, anon using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='exam_submission_tasks' and policyname='tasks_write_all') then
    create policy tasks_write_all on public.exam_submission_tasks for all to authenticated using (true) with check (true);
  end if;
end $$;

grant select, insert, update, delete on public.official_exam_schedules to authenticated, anon;
grant select, insert, update, delete on public.exam_submission_tasks to authenticated, anon;

-- 5) فيو ربط المهام بالمواعيد والصفوف والمواد
create or replace view public.v_my_exam_submission_tasks
with (security_invoker = true) as
select t.*,
       s.term_period, s.exam_date, s.start_time, s.end_time, s.required_topics, s.class_id, s.subject_id,
       c.name as class_name,
       sub.name as subject_name,
       coalesce(u.name, u.email, 'معلم') as teacher_name
from public.exam_submission_tasks t
join public.official_exam_schedules s on s.id = t.schedule_id
left join public.classes c on c.id = s.class_id
left join public.subjects sub on sub.id = s.subject_id
left join public.users u on u.id = t.teacher_id;

grant select on public.v_my_exam_submission_tasks to authenticated, anon;

-- 6) دوال التحكم في الجداول وتكليف المعلمين وتحديث المهام
create or replace function public.academic_create_exam_schedule_with_task(
  p_period text,
  p_class_id uuid,
  p_subject_id uuid,
  p_teacher_id uuid,
  p_exam_date date,
  p_start_time time,
  p_end_time time,
  p_deadline timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_sched_id uuid;
  v_task_id uuid;
  v_sub_name text;
  v_cls_name text;
begin
  if not exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin','principal','scientific'))) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إعداد مواعيد الامتحانات (محصورة بالإدارة)');
  end if;

  select name into v_sub_name from public.subjects where id = p_subject_id;
  select name into v_cls_name from public.classes where id = p_class_id;

  insert into public.official_exam_schedules (
    term_period, class_id, subject_id, exam_date, start_time, end_time, created_by
  ) values (
    p_period, p_class_id, p_subject_id, p_exam_date, coalesce(p_start_time, '08:30'), coalesce(p_end_time, '10:00'), auth.uid()
  )
  on conflict (academic_year, term_period, class_id, subject_id)
  do update set
    exam_date = excluded.exam_date,
    start_time = excluded.start_time,
    end_time = excluded.end_time,
    updated_at = now()
  returning id into v_sched_id;

  insert into public.exam_submission_tasks (
    schedule_id, teacher_id, title, submission_deadline, status
  ) values (
    v_sched_id,
    p_teacher_id,
    'تسليم أسئلة امتحان (' || coalesce(v_sub_name,'مادة') || ') للصف (' || coalesce(v_cls_name,'صف') || ')',
    coalesce(p_deadline, (p_exam_date::timestamp - interval '3 days')::timestamptz),
    'pending'
  )
  returning id into v_task_id;

  return jsonb_build_object('ok', true, 'message', 'تم إعداد موعد الامتحان وتكليف المعلم بمهمة تسليم الأسئلة بنجاح 🚀', 'schedule_id', v_sched_id, 'task_id', v_task_id);
end;
$$;
grant execute on function public.academic_create_exam_schedule_with_task(text,uuid,uuid,uuid,date,time,time,timestamptz) to authenticated, anon;

create or replace function public.teacher_set_exam_topics(p_schedule_id uuid, p_topics text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  update public.official_exam_schedules
  set required_topics = nullif(trim(p_topics), ''),
      topics_updated_at = now(),
      updated_at = now()
  where id = p_schedule_id;
  return jsonb_build_object('ok', true, 'message', 'تم حفظ المادة المطلوبة للامتحان في الجدول الرسمي 📚');
end;
$$;
grant execute on function public.teacher_set_exam_topics(uuid, text) to authenticated, anon;

create or replace function public.submit_exam_task_questions(
  p_task_id uuid,
  p_file_url text default null,
  p_delivery_method text default 'platform',
  p_proof_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_task record;
  v_status text := 'submitted';
begin
  select * into v_task from public.exam_submission_tasks where id = p_task_id;
  if v_task is null then
    return jsonb_build_object('ok', false, 'message', 'مهمة تسليم الأسئلة غير موجودة');
  end if;

  if p_delivery_method in ('manual','whatsapp','eitaa','bale') then
    v_status := 'offline_verified';
  elsif now() > v_task.submission_deadline then
    v_status := 'late';
  end if;

  update public.exam_submission_tasks set
    question_file_url = coalesce(nullif(trim(p_file_url), ''), question_file_url),
    delivery_method = case when p_delivery_method in ('platform','manual','whatsapp','eitaa','bale','other') then p_delivery_method else 'platform' end,
    delivery_proof_note = coalesce(nullif(trim(p_proof_note), ''), delivery_proof_note),
    status = v_status,
    submitted_at = now(),
    updated_at = now()
  where id = p_task_id;

  return jsonb_build_object('ok', true, 'message', 'تم توثيق تسليم أسئلة الامتحان بنجاح (الحالة: ' || v_status || ') 📑');
end;
$$;
grant execute on function public.submit_exam_task_questions(uuid,text,text,text) to authenticated, anon;

create or replace function public.check_overdue_exam_tasks()
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_count int := 0;
begin
  update public.exam_submission_tasks
  set status = 'late', updated_at = now()
  where status = 'pending' and now() > submission_deadline;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
grant execute on function public.check_overdue_exam_tasks() to authenticated, anon;

NOTIFY pgrst, 'reload schema';

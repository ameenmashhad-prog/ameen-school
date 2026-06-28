-- =============================================================
-- مدارس أمين الرضا (ع) — إصلاح واجباتي بشكل مستقل عن View و Schema Cache
-- يعالج حالة: student_homeworks_health_check غير موجودة أو v_student_homeworks 404.
-- شغّل هذا الملف كاملاً ثم افتح student-homeworks.html بعد Ctrl+F5.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) تأكيد الجداول والأعمدة الأساسية
-- -------------------------------------------------------------
create table if not exists public.homeworks (
  id uuid primary key default gen_random_uuid(),
  class_session_id uuid null references public.class_sessions(id) on delete set null,
  academic_period_id uuid null references public.academic_periods(id) on delete set null,
  class_id uuid null references public.classes(id),
  subject_id uuid null references public.subjects(id),
  teacher_id uuid null references public.users(id),
  title text not null,
  description text,
  assigned_date date not null default current_date,
  due_date date,
  status text not null default 'published',
  created_at timestamptz not null default now()
);

alter table public.homeworks add column if not exists section_id uuid null references public.sections(id) on delete set null;
alter table public.homeworks add column if not exists publish_at timestamptz;
alter table public.homeworks add column if not exists due_time time;
alter table public.homeworks add column if not exists max_score numeric not null default 10;
alter table public.homeworks add column if not exists updated_at timestamptz not null default now();
alter table public.homeworks add column if not exists created_by uuid null references public.users(id);

create table if not exists public.homework_attachments (
  id uuid primary key default gen_random_uuid(),
  homework_id uuid not null references public.homeworks(id) on delete cascade,
  file_name text not null,
  file_type text,
  file_size bigint,
  storage_path text not null,
  public_url text,
  sort_order int not null default 0,
  uploaded_by uuid null references public.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.homework_grades (
  id uuid primary key default gen_random_uuid(),
  homework_id uuid not null references public.homeworks(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  score numeric not null,
  max_score numeric not null default 10,
  feedback text,
  graded_by uuid null references public.users(id),
  graded_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_homeworks_status_class_section on public.homeworks(status, class_id, section_id);
create index if not exists idx_homework_attachments_homework on public.homework_attachments(homework_id, sort_order);
create index if not exists idx_homework_grades_student_homework on public.homework_grades(student_id, homework_id);

grant select on public.homeworks to authenticated;
grant select on public.homework_attachments to authenticated;
grant select on public.homework_grades to authenticated;

-- -------------------------------------------------------------
-- 2) RPC موثوق لواجهة واجباتي، لا يعتمد على v_student_homeworks ولا PostgREST view cache.
-- -------------------------------------------------------------
create or replace function public.get_student_homeworks_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  result jsonb;
  uid uuid := auth.uid();
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'message', 'لا توجد جلسة مستخدم', 'homeworks', '[]'::jsonb);
  end if;

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
      h.updated_at
    from public.homeworks h
    join my_students ms
      on (
        (h.section_id is not null and (
          ms.section_id = h.section_id
          or exists(
            select 1 from public.student_enrollments se
            where se.student_id = ms.id
              and se.section_id = h.section_id
              and se.enrollment_status = 'active'
          )
        ))
        or
        (h.section_id is null and h.class_id is not null and (
          ms.class_id = h.class_id
          or exists(
            select 1 from public.student_enrollments se
            where se.student_id = ms.id
              and se.class_id = h.class_id
              and se.enrollment_status = 'active'
          )
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

  return jsonb_build_object('ok', true, 'homeworks', coalesce(result, '[]'::jsonb));
end;
$$;

grant execute on function public.get_student_homeworks_payload() to authenticated;

-- -------------------------------------------------------------
-- 3) محاولة إنشاء View أيضاً، لكن لو فشلت لا يتوقف الملف لأن الواجهة ستستخدم RPC.
-- -------------------------------------------------------------
do $$
begin
  begin
    execute 'drop view if exists public.v_student_homeworks';

    execute $sql$
      create view public.v_student_homeworks
      with (security_invoker=true) as
      select
        x.homework_id,
        x.title,
        x.description,
        x.status,
        x.publish_at,
        x.assigned_date,
        x.due_date,
        x.due_time,
        x.max_score,
        x.class_id,
        x.class_name,
        x.section_id,
        x.section_code,
        x.subject_id,
        x.subject_name,
        x.teacher_id,
        x.teacher_name,
        x.student_id,
        x.student_name,
        x.grade_score,
        x.grade_max_score,
        x.grade_feedback,
        x.graded_at,
        x.attachment_count,
        x.created_at,
        x.updated_at
      from jsonb_to_recordset((public.get_student_homeworks_payload()->'homeworks')) as x(
        homework_id uuid,
        title text,
        description text,
        status text,
        publish_at timestamptz,
        assigned_date date,
        due_date date,
        due_time time,
        max_score numeric,
        class_id uuid,
        class_name text,
        section_id uuid,
        section_code text,
        subject_id uuid,
        subject_name text,
        teacher_id uuid,
        teacher_name text,
        student_id uuid,
        student_name text,
        grade_score numeric,
        grade_max_score numeric,
        grade_feedback text,
        graded_at timestamptz,
        attachment_count bigint,
        created_at timestamptz,
        updated_at timestamptz
      )
    $sql$;

    execute 'grant select on public.v_student_homeworks to authenticated';
  exception when others then
    raise notice 'تعذر إنشاء v_student_homeworks، سيعمل RPC البديل: %', sqlerrm;
  end;
end $$;

-- -------------------------------------------------------------
-- 4) Health Check — الآن ستوجد حتى لو فشل إنشاء الـ View.
-- -------------------------------------------------------------
create or replace function public.student_homeworks_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  visible_count int := 0;
begin
  if uid is not null then
    select jsonb_array_length(coalesce(public.get_student_homeworks_payload()->'homeworks','[]'::jsonb)) into visible_count;
  end if;

  return jsonb_build_object(
    'checked_at', now(),
    'auth_uid', uid,
    'view_exists', to_regclass('public.v_student_homeworks') is not null,
    'rpc_exists', to_regprocedure('public.get_student_homeworks_payload()') is not null,
    'homeworks_table_exists', to_regclass('public.homeworks') is not null,
    'published_homeworks', (select count(*) from public.homeworks where status in ('published','closed')),
    'student_count', (select count(*) from public.students),
    'my_visible_homeworks_in_sql_editor_may_be_zero_if_auth_uid_null', visible_count,
    'attachments_count', (select count(*) from public.homework_attachments),
    'grades_count', (select count(*) from public.homework_grades),
    'sample_homeworks', coalesce((
      select jsonb_agg(jsonb_build_object('title', title, 'class_id', class_id, 'section_id', section_id, 'status', status) order by created_at desc)
      from (
        select * from public.homeworks
        where status in ('published','closed')
        order by created_at desc
        limit 5
      ) h
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.student_homeworks_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'student_homeworks_rpc_health_fix_ready' as status;

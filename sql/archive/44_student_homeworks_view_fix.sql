-- =============================================================
-- مدارس أمين الرضا (ع) — إصلاح ظهور واجبات الطالب 404
-- يحل: /rest/v1/v_student_homeworks يرجع 404 لأن الـ View غير موجودة أو schema cache لم يحدث.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) تأكيد الجداول والأعمدة المطلوبة
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

-- -------------------------------------------------------------
-- 2) دوال صلاحيات الواجبات
-- -------------------------------------------------------------
create or replace function public.can_read_homework(p_homework_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  h record;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return false; end if;

  if public.current_user_is_admin() or h.teacher_id = auth.uid() then
    return true;
  end if;

  if h.status not in ('published','closed') then
    return false;
  end if;

  if h.publish_at is not null and h.publish_at > now() then
    return false;
  end if;

  return exists(
    select 1
    from public.students s
    where (s.user_id = auth.uid() or s.parent_id = auth.uid())
      and (
        (h.section_id is not null and (
          s.section_id = h.section_id
          or exists(select 1 from public.student_enrollments se where se.student_id = s.id and se.section_id = h.section_id and se.enrollment_status = 'active')
        ))
        or
        (h.section_id is null and h.class_id is not null and (
          s.class_id = h.class_id
          or exists(select 1 from public.student_enrollments se where se.student_id = s.id and se.class_id = h.class_id and se.enrollment_status = 'active')
        ))
      )
  );
end;
$$;

grant execute on function public.can_read_homework(uuid) to authenticated;

create or replace function public.can_write_homework(p_homework_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  h record;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return false; end if;
  return public.current_user_is_admin() or h.teacher_id = auth.uid();
end;
$$;

grant execute on function public.can_write_homework(uuid) to authenticated;

-- -------------------------------------------------------------
-- 3) RLS متوافق للواجبات والمرفقات والدرجات
-- -------------------------------------------------------------
alter table public.homeworks enable row level security;
alter table public.homework_attachments enable row level security;
alter table public.homework_grades enable row level security;

drop policy if exists homeworks_teacher_admin_student_parent_read on public.homeworks;
drop policy if exists homeworks_teacher_admin_write on public.homeworks;
drop policy if exists homework_attachments_read_scoped on public.homework_attachments;
drop policy if exists homework_attachments_teacher_write_scoped on public.homework_attachments;
drop policy if exists homework_grades_read_scoped on public.homework_grades;
drop policy if exists homework_grades_teacher_write_scoped on public.homework_grades;

create policy homeworks_teacher_admin_student_parent_read on public.homeworks
  for select to authenticated
  using (public.can_read_homework(id));

create policy homeworks_teacher_admin_write on public.homeworks
  for all to authenticated
  using (public.current_user_is_admin() or teacher_id = auth.uid())
  with check (public.current_user_is_admin() or teacher_id = auth.uid());

create policy homework_attachments_read_scoped on public.homework_attachments
  for select to authenticated
  using (public.can_read_homework(homework_id));

create policy homework_attachments_teacher_write_scoped on public.homework_attachments
  for all to authenticated
  using (public.can_write_homework(homework_id))
  with check (public.can_write_homework(homework_id));

create policy homework_grades_read_scoped on public.homework_grades
  for select to authenticated
  using (
    public.current_user_is_admin()
    or exists(select 1 from public.homeworks h where h.id = homework_id and h.teacher_id = auth.uid())
    or exists(select 1 from public.students s where s.id = student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
  );

create policy homework_grades_teacher_write_scoped on public.homework_grades
  for all to authenticated
  using (public.can_write_homework(homework_id))
  with check (public.can_write_homework(homework_id));

grant select, insert, update on public.homeworks to authenticated;
grant select, insert, update, delete on public.homework_attachments to authenticated;
grant select, insert, update, delete on public.homework_grades to authenticated;

-- -------------------------------------------------------------
-- 4) View واجبات الطالب/ولي الأمر
-- -------------------------------------------------------------
drop view if exists public.v_student_homeworks;

create view public.v_student_homeworks
with (security_invoker=true) as
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
  s.id as student_id,
  s.name as student_name,
  hg.score as grade_score,
  hg.max_score as grade_max_score,
  hg.feedback as grade_feedback,
  hg.graded_at,
  coalesce(att.attachment_count,0) as attachment_count,
  h.created_at,
  h.updated_at
from public.homeworks h
join public.students s
  on (s.user_id = auth.uid() or s.parent_id = auth.uid())
 and (
   (h.section_id is not null and (
      s.section_id = h.section_id
      or exists(select 1 from public.student_enrollments se where se.student_id = s.id and se.section_id = h.section_id and se.enrollment_status = 'active')
   ))
   or
   (h.section_id is null and h.class_id is not null and (
      s.class_id = h.class_id
      or exists(select 1 from public.student_enrollments se where se.student_id = s.id and se.class_id = h.class_id and se.enrollment_status = 'active')
   ))
 )
left join public.classes c on c.id = h.class_id
left join public.sections sec on sec.id = h.section_id
left join public.subjects sub on sub.id = h.subject_id
left join public.users u on u.id = h.teacher_id
left join public.homework_grades hg on hg.homework_id = h.id and hg.student_id = s.id
left join lateral (
  select count(*) as attachment_count
  from public.homework_attachments ha
  where ha.homework_id = h.id
) att on true
where h.status in ('published','closed')
  and (h.publish_at is null or h.publish_at <= now());

grant select on public.v_student_homeworks to authenticated;

-- -------------------------------------------------------------
-- 5) RPC بديل لو احتاجته الواجهة عند تأخر schema cache
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
begin
  select coalesce(jsonb_agg(to_jsonb(x) order by x.due_date nulls last, x.created_at desc), '[]'::jsonb)
  into result
  from public.v_student_homeworks x;

  return jsonb_build_object('ok', true, 'homeworks', result);
end;
$$;

grant execute on function public.get_student_homeworks_payload() to authenticated;

-- -------------------------------------------------------------
-- 6) فحص صحة واجبات الطالب
-- -------------------------------------------------------------
create or replace function public.student_homeworks_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'view_exists', to_regclass('public.v_student_homeworks') is not null,
    'homeworks_table_exists', to_regclass('public.homeworks') is not null,
    'published_homeworks', (select count(*) from public.homeworks where status in ('published','closed')),
    'student_count', (select count(*) from public.students),
    'attachments_count', (select count(*) from public.homework_attachments),
    'grades_count', (select count(*) from public.homework_grades),
    'sample_homeworks', coalesce((select jsonb_agg(jsonb_build_object('title', title, 'class_id', class_id, 'section_id', section_id, 'status', status) order by created_at desc) from (select * from public.homeworks where status in ('published','closed') order by created_at desc limit 5) h), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.student_homeworks_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'student_homeworks_view_fix_ready' as status;

-- =============================================================
-- مدارس أمين الرضا (ع) — تحسين صلاحيات وعرض مرفقات تسليم الواجب
-- يتيح للطالب/ولي الأمر والمعلم فتح مرفقات تسليم الواجب بأمان.
-- =============================================================

create extension if not exists pgcrypto;

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

create index if not exists idx_homework_submission_attachments_submission on public.homework_submission_attachments(submission_id, sort_order);

-- -------------------------------------------------------------
-- Helpers
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

create or replace function public.can_write_homework_submission_attachment(p_submission_id uuid)
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

  -- الطالب/ولي الأمر يستطيع إضافة مرفق إذا لم يتم تصحيح التسليم بعد.
  return public.current_user_is_admin()
    or h.teacher_id = auth.uid()
    or (
      hs.status in ('draft','submitted','late')
      and exists(select 1 from public.students s where s.id = hs.student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
    );
end;
$$;

grant execute on function public.can_write_homework_submission_attachment(uuid) to authenticated;

-- -------------------------------------------------------------
-- RLS محكم للمرفقات
-- -------------------------------------------------------------
alter table public.homework_submission_attachments enable row level security;

drop policy if exists homework_submission_attachments_read_scoped on public.homework_submission_attachments;
drop policy if exists homework_submission_attachments_write_scoped on public.homework_submission_attachments;

create policy homework_submission_attachments_read_scoped on public.homework_submission_attachments
  for select to authenticated
  using (public.can_read_homework_submission(submission_id));

create policy homework_submission_attachments_write_scoped on public.homework_submission_attachments
  for all to authenticated
  using (public.can_write_homework_submission_attachment(submission_id))
  with check (public.can_write_homework_submission_attachment(submission_id));

grant select, insert, update, delete on public.homework_submission_attachments to authenticated;

-- -------------------------------------------------------------
-- View تفصيلية اختيارية للواجهات
-- -------------------------------------------------------------
drop view if exists public.v_homework_submission_attachments_detailed;

create view public.v_homework_submission_attachments_detailed
with (security_invoker=true) as
select
  a.id as attachment_id,
  a.submission_id,
  hs.homework_id,
  hs.student_id,
  h.teacher_id,
  a.file_name,
  a.file_type,
  a.file_size,
  a.storage_path,
  a.sort_order,
  a.uploaded_by,
  a.created_at
from public.homework_submission_attachments a
join public.homework_submissions hs on hs.id = a.submission_id
join public.homeworks h on h.id = hs.homework_id
where public.can_read_homework_submission(a.submission_id);

grant select on public.v_homework_submission_attachments_detailed to authenticated;

-- -------------------------------------------------------------
-- Health check
-- -------------------------------------------------------------
create or replace function public.homework_submission_attachments_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'table_exists', to_regclass('public.homework_submission_attachments') is not null,
    'view_exists', to_regclass('public.v_homework_submission_attachments_detailed') is not null,
    'attachments_count', (select count(*) from public.homework_submission_attachments),
    'submissions_count', (select count(*) from public.homework_submissions)
  );
end;
$$;

grant execute on function public.homework_submission_attachments_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'homework_submission_attachments_access_ready' as status;

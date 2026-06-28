-- =============================================================
-- مدارس أمين الرضا (ع) — Hotfix الوثائق: سياسات Idempotent + تصنيفات افتراضية
-- يحل: policy "document_records_manage_update" already exists
-- يمكن تشغيله أكثر من مرة بأمان.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) دوال الصلاحيات الأساسية
-- -------------------------------------------------------------
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

create or replace function public.documents_can_manage()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.current_user_is_admin()
    or exists(
      select 1 from public.users u
      where u.id = auth.uid()
        and u.role in ('staff','academic','academic_admin','scientific','supervisor','finance','hr','teacher','registrar')
    );
$$;

grant execute on function public.documents_can_manage() to authenticated;

-- -------------------------------------------------------------
-- 2) تأكيد الجداول بأمان
-- -------------------------------------------------------------
create table if not exists public.document_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.document_records (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category_id uuid null references public.document_categories(id) on delete set null,
  owner_user_id uuid null references public.users(id) on delete set null,
  student_id uuid null references public.students(id) on delete set null,
  related_table text,
  related_id uuid,
  visibility text not null default 'private' check (visibility in ('private','student_parent','staff','public_authenticated')),
  status text not null default 'active' check (status in ('active','archived','deleted')),
  description text,
  tags jsonb not null default '[]'::jsonb,
  created_by uuid null references public.users(id),
  archived_by uuid null references public.users(id),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.document_files (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.document_records(id) on delete cascade,
  file_name text not null,
  file_type text,
  file_size bigint,
  storage_path text not null,
  version_no int not null default 1,
  uploaded_by uuid null references public.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.document_access_logs (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.document_records(id) on delete cascade,
  file_id uuid null references public.document_files(id) on delete set null,
  user_id uuid null references public.users(id),
  action text not null default 'view' check (action in ('view','download','create','archive','restore','delete')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- -------------------------------------------------------------
-- 3) دالة قراءة الوثيقة
-- -------------------------------------------------------------
create or replace function public.document_user_can_read(p_document_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  d record;
begin
  select * into d from public.document_records where id = p_document_id;
  if d.id is null or d.status = 'deleted' then return false; end if;

  if public.documents_can_manage() then return true; end if;
  if d.owner_user_id = auth.uid() then return true; end if;
  if d.visibility = 'public_authenticated' and auth.uid() is not null then return true; end if;
  if d.visibility = 'staff' and exists(select 1 from public.users u where u.id=auth.uid() and u.role not in ('student','parent')) then return true; end if;

  if d.student_id is not null then
    return exists(
      select 1 from public.students s
      where s.id = d.student_id
        and (s.user_id = auth.uid() or s.parent_id = auth.uid())
    );
  end if;

  return false;
end;
$$;

grant execute on function public.document_user_can_read(uuid) to authenticated;

-- -------------------------------------------------------------
-- 4) إعادة إنشاء السياسات بعد حذفها لتجنب already exists
-- -------------------------------------------------------------
alter table public.document_categories enable row level security;
alter table public.document_records enable row level security;
alter table public.document_files enable row level security;
alter table public.document_access_logs enable row level security;

drop policy if exists document_categories_read_write on public.document_categories;
drop policy if exists document_records_read_scoped on public.document_records;
drop policy if exists document_records_manage_write on public.document_records;
drop policy if exists document_records_manage_update on public.document_records;
drop policy if exists document_files_read_scoped on public.document_files;
drop policy if exists document_files_manage_write on public.document_files;
drop policy if exists document_access_logs_read_write on public.document_access_logs;

create policy document_categories_read_write on public.document_categories
  for all to authenticated
  using (public.documents_can_manage() or is_active=true)
  with check (public.documents_can_manage());

create policy document_records_read_scoped on public.document_records
  for select to authenticated
  using (public.document_user_can_read(id));

create policy document_records_manage_write on public.document_records
  for insert to authenticated
  with check (public.documents_can_manage() or owner_user_id = auth.uid());

create policy document_records_manage_update on public.document_records
  for update to authenticated
  using (public.documents_can_manage() or owner_user_id = auth.uid())
  with check (public.documents_can_manage() or owner_user_id = auth.uid());

create policy document_files_read_scoped on public.document_files
  for select to authenticated
  using (public.document_user_can_read(document_id));

create policy document_files_manage_write on public.document_files
  for insert to authenticated
  with check (exists(select 1 from public.document_records d where d.id=document_id and (public.documents_can_manage() or d.owner_user_id=auth.uid())));

create policy document_access_logs_read_write on public.document_access_logs
  for all to authenticated
  using (public.documents_can_manage() or user_id = auth.uid())
  with check (auth.uid() is not null);

grant select, insert, update on public.document_categories to authenticated;
grant select, insert, update on public.document_records to authenticated;
grant select, insert on public.document_files to authenticated;
grant select, insert on public.document_access_logs to authenticated;

-- -------------------------------------------------------------
-- 5) تصنيفات افتراضية
-- -------------------------------------------------------------
create or replace function public.documents_seed_defaults()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare inserted int := 0;
begin
  insert into public.document_categories(name, description)
  values
    ('ملفات الطلاب', 'وثائق خاصة بالطلاب وأولياء الأمور'),
    ('ملفات الموظفين', 'وثائق إدارية للموظفين'),
    ('إدارية', 'تعاميم وقرارات داخلية'),
    ('مالية', 'مستندات مالية'),
    ('أصول ومخزون', 'وثائق الأصول والمخزون'),
    ('النقل المدرسي', 'وثائق النقل والحافلات'),
    ('المكتبة', 'وثائق المكتبة والإعارات')
  on conflict (name) do update
  set description = excluded.description,
      is_active = true;

  get diagnostics inserted = row_count;
  return jsonb_build_object('ok', true, 'message', 'تمت تهيئة تصنيفات الأرشيف', 'upserted_categories', inserted);
end;
$$;

grant execute on function public.documents_seed_defaults() to authenticated;

select public.documents_seed_defaults();

-- -------------------------------------------------------------
-- 6) Views + فحص
-- -------------------------------------------------------------
create or replace view public.v_documents_detailed
with (security_invoker=true) as
select
  d.id as document_id,
  d.title,
  d.category_id,
  c.name as category_name,
  d.owner_user_id,
  ou.name as owner_name,
  d.student_id,
  s.name as student_name,
  d.related_table,
  d.related_id,
  d.visibility,
  d.status,
  d.description,
  d.tags,
  d.created_by,
  cu.name as created_by_name,
  d.archived_by,
  au.name as archived_by_name,
  d.archived_at,
  count(f.id) as files_count,
  max(f.created_at) as last_file_at,
  d.created_at,
  d.updated_at
from public.document_records d
left join public.document_categories c on c.id = d.category_id
left join public.users ou on ou.id = d.owner_user_id
left join public.students s on s.id = d.student_id
left join public.users cu on cu.id = d.created_by
left join public.users au on au.id = d.archived_by
left join public.document_files f on f.document_id = d.id
where public.document_user_can_read(d.id)
group by d.id, c.name, ou.name, s.name, cu.name, au.name;

grant select on public.v_documents_detailed to authenticated;

create or replace view public.v_document_files_detailed
with (security_invoker=true) as
select
  f.id as file_id,
  f.document_id,
  d.title as document_title,
  f.file_name,
  f.file_type,
  f.file_size,
  f.storage_path,
  f.version_no,
  f.uploaded_by,
  u.name as uploaded_by_name,
  f.created_at
from public.document_files f
join public.document_records d on d.id = f.document_id
left join public.users u on u.id = f.uploaded_by
where public.document_user_can_read(f.document_id);

grant select on public.v_document_files_detailed to authenticated;

create or replace function public.documents_policy_seed_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'policies_recreated', true,
    'categories_count', (select count(*) from public.document_categories),
    'records_table', to_regclass('public.document_records') is not null,
    'files_table', to_regclass('public.document_files') is not null,
    'documents_view', to_regclass('public.v_documents_detailed') is not null,
    'files_view', to_regclass('public.v_document_files_detailed') is not null,
    'documents_ui', case when to_regprocedure('public.get_documents_payload()') is not null then public.get_documents_payload()->'stats' else '{}'::jsonb end
  );
end;
$$;

grant execute on function public.documents_policy_seed_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'documents_policy_idempotent_seed_ready' as status;

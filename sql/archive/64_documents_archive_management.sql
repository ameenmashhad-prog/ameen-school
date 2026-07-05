-- =============================================================
-- مدارس أمين الرضا (ع) — وحدة الوثائق والأرشفة الإلكترونية
-- أرشفة ملفات الطلاب/الموظفين/الإدارة، مرفقات، صلاحيات، سجل فتح.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) صلاحيات
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
-- 1) الجداول
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

create index if not exists idx_document_records_student on public.document_records(student_id, status);
create index if not exists idx_document_records_owner on public.document_records(owner_user_id, status);
create index if not exists idx_document_records_category on public.document_records(category_id, status);
create index if not exists idx_document_files_document on public.document_files(document_id, version_no desc);
create index if not exists idx_document_access_logs_document on public.document_access_logs(document_id, created_at desc);

-- -------------------------------------------------------------
-- 2) Bucket Storage
-- -------------------------------------------------------------
do $$ begin
  begin
    insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
    values (
      'documents-archive',
      'documents-archive',
      false,
      52428800,
      array[
        'image/jpeg','image/png','image/webp','application/pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'text/plain'
      ]
    )
    on conflict (id) do update
    set public=false,
        file_size_limit=excluded.file_size_limit,
        allowed_mime_types=excluded.allowed_mime_types;

    if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='documents_archive_storage_select') then
      create policy documents_archive_storage_select on storage.objects
        for select to authenticated
        using (bucket_id='documents-archive');
    end if;
    if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='documents_archive_storage_insert') then
      create policy documents_archive_storage_insert on storage.objects
        for insert to authenticated
        with check (bucket_id='documents-archive');
    end if;
    if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='documents_archive_storage_update') then
      create policy documents_archive_storage_update on storage.objects
        for all to authenticated
        using (bucket_id='documents-archive')
        with check (bucket_id='documents-archive');
    end if;
  exception when others then
    raise notice 'تعذر إنشاء bucket/policies documents-archive: %', sqlerrm;
  end;
end $$;

-- -------------------------------------------------------------
-- 3) صلاحية قراءة الوثيقة
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
-- 4) RLS
-- -------------------------------------------------------------
alter table public.document_categories enable row level security;
alter table public.document_records enable row level security;
alter table public.document_files enable row level security;
alter table public.document_access_logs enable row level security;

drop policy if exists document_categories_read_write on public.document_categories;
drop policy if exists document_records_read_scoped on public.document_records;
drop policy if exists document_records_manage_write on public.document_records;
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
-- 5) Views
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

-- -------------------------------------------------------------
-- 6) Functions
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
    ('أصول ومخزون', 'وثائق الأصول والمخزون')
  on conflict (name) do nothing;
  get diagnostics inserted = row_count;
  return jsonb_build_object('ok', true, 'message', 'تمت تهيئة تصنيفات الأرشيف', 'inserted_categories', inserted);
end;
$$;

grant execute on function public.documents_seed_defaults() to authenticated;

create or replace function public.document_create_record(
  p_title text,
  p_category text default null,
  p_student_id uuid default null,
  p_owner_user_id uuid default null,
  p_related_table text default null,
  p_related_id uuid default null,
  p_visibility text default 'private',
  p_description text default null,
  p_tags jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cat_id uuid;
  doc_id uuid;
  v_visibility text := coalesce(p_visibility,'private');
begin
  if nullif(trim(coalesce(p_title,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'عنوان الوثيقة مطلوب');
  end if;

  if v_visibility not in ('private','student_parent','staff','public_authenticated') then v_visibility := 'private'; end if;

  if not (public.documents_can_manage() or coalesce(p_owner_user_id,auth.uid()) = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إنشاء هذه الوثيقة');
  end if;

  if nullif(trim(coalesce(p_category,'')), '') is not null then
    insert into public.document_categories(name)
    values (trim(p_category))
    on conflict (name) do update set name=excluded.name
    returning id into cat_id;
  end if;

  insert into public.document_records(title, category_id, owner_user_id, student_id, related_table, related_id, visibility, description, tags, created_by)
  values (trim(p_title), cat_id, coalesce(p_owner_user_id, auth.uid()), p_student_id, p_related_table, p_related_id, v_visibility, p_description, coalesce(p_tags,'[]'::jsonb), auth.uid())
  returning id into doc_id;

  return jsonb_build_object('ok', true, 'message', 'تم إنشاء سجل الوثيقة', 'document_id', doc_id);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.document_create_record(text,text,uuid,uuid,text,uuid,text,text,jsonb) to authenticated;

create or replace function public.document_add_file(
  p_document_id uuid,
  p_file_name text,
  p_file_type text,
  p_file_size bigint,
  p_storage_path text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  d record;
  ver int;
  file_id uuid;
begin
  select * into d from public.document_records where id = p_document_id;
  if d.id is null then return jsonb_build_object('ok', false, 'message', 'الوثيقة غير موجودة'); end if;

  if not (public.documents_can_manage() or d.owner_user_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إضافة ملف لهذه الوثيقة');
  end if;

  select coalesce(max(version_no),0)+1 into ver from public.document_files where document_id = p_document_id;

  insert into public.document_files(document_id, file_name, file_type, file_size, storage_path, version_no, uploaded_by)
  values (p_document_id, p_file_name, p_file_type, p_file_size, p_storage_path, ver, auth.uid())
  returning id into file_id;

  insert into public.document_access_logs(document_id, file_id, user_id, action, metadata)
  values (p_document_id, file_id, auth.uid(), 'create', jsonb_build_object('file_name', p_file_name, 'version', ver));

  return jsonb_build_object('ok', true, 'message', 'تمت إضافة الملف', 'file_id', file_id, 'version_no', ver);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.document_add_file(uuid,text,text,bigint,text) to authenticated;

create or replace function public.document_set_status(
  p_document_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare d record; st text := coalesce(p_status,'active');
begin
  select * into d from public.document_records where id=p_document_id;
  if d.id is null then return jsonb_build_object('ok', false, 'message', 'الوثيقة غير موجودة'); end if;
  if not (public.documents_can_manage() or d.owner_user_id=auth.uid()) then return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل الوثيقة'); end if;
  if st not in ('active','archived','deleted') then st := 'active'; end if;

  update public.document_records
  set status=st,
      archived_by=case when st='archived' then auth.uid() else archived_by end,
      archived_at=case when st='archived' then now() else archived_at end,
      updated_at=now()
  where id=p_document_id;

  insert into public.document_access_logs(document_id, user_id, action, metadata)
  values (p_document_id, auth.uid(), case when st='archived' then 'archive' when st='deleted' then 'delete' else 'view' end, jsonb_build_object('status', st));

  return jsonb_build_object('ok', true, 'message', 'تم تحديث حالة الوثيقة', 'status', st);
end;
$$;

grant execute on function public.document_set_status(uuid,text) to authenticated;

create or replace function public.document_log_access(p_document_id uuid, p_file_id uuid default null, p_action text default 'view')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.document_user_can_read(p_document_id) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية فتح الوثيقة');
  end if;
  if p_action not in ('view','download') then p_action := 'view'; end if;
  insert into public.document_access_logs(document_id, file_id, user_id, action)
  values (p_document_id, p_file_id, auth.uid(), p_action);
  return jsonb_build_object('ok', true, 'message', 'تم تسجيل فتح الوثيقة');
end;
$$;

grant execute on function public.document_log_access(uuid,uuid,text) to authenticated;

create or replace function public.get_documents_dashboard_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'stats', jsonb_build_object(
      'documents', (select count(*) from public.document_records d where public.document_user_can_read(d.id) and d.status='active'),
      'archived', (select count(*) from public.document_records d where public.document_user_can_read(d.id) and d.status='archived'),
      'files', (select count(*) from public.document_files f where public.document_user_can_read(f.document_id)),
      'categories', (select count(*) from public.document_categories where is_active=true)
    ),
    'recent', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from public.v_documents_detailed order by created_at desc limit 15) x), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_documents_dashboard_payload() to authenticated;

create or replace function public.documents_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'categories_table', to_regclass('public.document_categories') is not null,
    'records_table', to_regclass('public.document_records') is not null,
    'files_table', to_regclass('public.document_files') is not null,
    'logs_table', to_regclass('public.document_access_logs') is not null,
    'documents_view', to_regclass('public.v_documents_detailed') is not null,
    'files_view', to_regclass('public.v_document_files_detailed') is not null,
    'dashboard_rpc', to_regprocedure('public.get_documents_dashboard_payload()') is not null,
    'create_rpc', to_regprocedure('public.document_create_record(text,text,uuid,uuid,text,uuid,text,text,jsonb)') is not null,
    'add_file_rpc', to_regprocedure('public.document_add_file(uuid,text,text,bigint,text)') is not null,
    'stats', public.get_documents_dashboard_payload()->'stats'
  );
end;
$$;

grant execute on function public.documents_health_check() to authenticated;

-- -------------------------------------------------------------
-- إضافة documents إلى صلاحيات البوابة إن كانت دالة البوابة موجودة
-- -------------------------------------------------------------
create or replace function public.portal_default_permissions(p_role text, p_is_super_admin boolean default false)
returns text[]
language plpgsql
stable
as $$
declare r text := lower(coalesce(p_role,''));
begin
  if coalesce(p_is_super_admin,false) or r = 'admin' then
    return array['admin','staff.dashboard','finance','academic','schedule','sections','grades','attendance','behavior','counseling','users','reports','registrations','system','teacher','student','parent','homework','homework.reports','homework.audit','question_bank','online_exams','exam_integrity','library','inventory','assets','hr','transport','labs','activities','documents','notifications'];
  end if;
  if r='finance' then return array['staff.dashboard','finance','reports','homework.reports','library','inventory','assets','documents','notifications']; end if;
  if r in ('academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor') then return array['staff.dashboard','academic','schedule','sections','grades','attendance','behavior','reports','registrations','question_bank','online_exams','exam_integrity','homework.reports','library','transport','labs','activities','documents','notifications']; end if;
  if r='discipline' then return array['staff.dashboard','attendance','behavior','students','reports','transport','homework.reports','notifications']; end if;
  if r in ('counselor','psychologist') then return array['staff.dashboard','counseling','behavior','students','attendance','reports','notifications']; end if;
  if r='teacher' then return array['teacher','attendance','homework','homework.reports','homework.audit','grades','question_bank','online_exams','library','transport','labs','activities','documents','notifications']; end if;
  if r='student' then return array['student','homework','online_exams','grades','attendance','behavior','library','transport','activities','documents','notifications']; end if;
  if r='parent' then return array['parent','student','homework','online_exams','grades','attendance','behavior','finance','library','transport','activities','documents','notifications']; end if;
  if r='staff' then return array['staff.dashboard','attendance','students','reports','library','inventory','assets','transport','activities','documents','notifications']; end if;
  if r='hr' then return array['staff.dashboard','hr','reports','documents','notifications']; end if;
  if r in ('inventory','procurement') then return array['staff.dashboard','inventory','reports','documents','notifications']; end if;
  if r in ('transport','transport_manager') then return array['staff.dashboard','transport','reports','notifications']; end if;
  if r='librarian' then return array['library','reports','documents','notifications']; end if;
  return array['notifications'];
end;
$$;

grant execute on function public.portal_default_permissions(text,boolean) to authenticated;

notify pgrst, 'reload schema';

select 'documents_archive_management_ready' as status;

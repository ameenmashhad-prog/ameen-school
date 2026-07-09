-- ============================================================================
-- Forms Engine v3 — backend foundation (RPC-only)
--
-- الهدف:
-- - تخزين تعريفات النماذج ونسخها
-- - دعم drafts / restore / publish
-- - دعم تذاكر رفع المرفقات
-- - دعم استلام submissions الخاصة بالنماذج الإنتاجية
--
-- مبدأ الأمان:
-- - لا كتابة مباشرة من الواجهة إلى الجداول
-- - كل الكتابة إلى الجداول تمر عبر RPC فقط
-- - الجداول مفعّل عليها RLS ولا تمنح سياسات كتابة مباشرة للعامة
-- ============================================================================

create extension if not exists pgcrypto;

create table if not exists public.forms_v3_definitions (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  visibility text not null default 'public' check (visibility in ('public','administrative','finance_admin')),
  latest_locale text not null default 'ar' check (latest_locale in ('ar','fa','en')),
  latest_schema jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft','issued')),
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.forms_v3_versions (
  id uuid primary key default gen_random_uuid(),
  form_id uuid not null references public.forms_v3_definitions(id) on delete cascade,
  form_slug text not null,
  locale text not null default 'ar' check (locale in ('ar','fa','en')),
  version_label text not null,
  visibility text not null default 'public' check (visibility in ('public','administrative','finance_admin')),
  autosave boolean not null default true,
  schema_snapshot jsonb not null default '{}'::jsonb,
  form_values jsonb not null default '{}'::jsonb,
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.forms_v3_upload_tickets (
  id uuid primary key default gen_random_uuid(),
  form_slug text not null,
  locale text not null default 'ar' check (locale in ('ar','fa','en')),
  field_id text not null,
  file_name text not null,
  content_type text,
  byte_size bigint not null default 0,
  object_path text,
  upload_strategy text not null default 'server_ticketed_transport',
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  consumed_at timestamptz,
  submission_ref text,
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.forms_v3_submissions (
  id uuid primary key default gen_random_uuid(),
  form_slug text not null,
  locale text not null default 'ar' check (locale in ('ar','fa','en')),
  visibility text not null default 'public' check (visibility in ('public','administrative','finance_admin')),
  submission_ref text not null unique,
  schema_snapshot jsonb not null default '{}'::jsonb,
  submission_values jsonb not null default '{}'::jsonb,
  upload_ticket_id uuid null references public.forms_v3_upload_tickets(id) on delete set null,
  uploaded_attachment jsonb,
  status text not null default 'received' check (status in ('received','reviewed','issued','rejected','archived')),
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists idx_forms_v3_versions_slug_created_at on public.forms_v3_versions(form_slug, created_at desc);
create index if not exists idx_forms_v3_upload_tickets_form_slug_created_at on public.forms_v3_upload_tickets(form_slug, created_at desc);
create index if not exists idx_forms_v3_submissions_form_slug_created_at on public.forms_v3_submissions(form_slug, created_at desc);
create index if not exists idx_forms_v3_submissions_visibility_status on public.forms_v3_submissions(visibility, status, created_at desc);

alter table public.forms_v3_definitions enable row level security;
alter table public.forms_v3_versions enable row level security;
alter table public.forms_v3_upload_tickets enable row level security;
alter table public.forms_v3_submissions enable row level security;

-- سياسات قراءة إدارية اختيارية، ولا توجد سياسات insert/update/delete مباشرة من الواجهة.
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='forms_v3_definitions' and policyname='forms_v3_definitions_admin_read') then
    create policy forms_v3_definitions_admin_read on public.forms_v3_definitions
      for select to authenticated
      using (public.is_admin_user() or public.current_user_is_super_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='forms_v3_versions' and policyname='forms_v3_versions_admin_read') then
    create policy forms_v3_versions_admin_read on public.forms_v3_versions
      for select to authenticated
      using (public.is_admin_user() or public.current_user_is_super_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='forms_v3_upload_tickets' and policyname='forms_v3_upload_tickets_admin_read') then
    create policy forms_v3_upload_tickets_admin_read on public.forms_v3_upload_tickets
      for select to authenticated
      using (public.is_admin_user() or public.current_user_is_super_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='forms_v3_submissions' and policyname='forms_v3_submissions_admin_read') then
    create policy forms_v3_submissions_admin_read on public.forms_v3_submissions
      for select to authenticated
      using (public.is_admin_user() or public.current_user_is_super_admin());
  end if;
end $$;

create or replace function public.forms_save_draft_v3(
  p_form_slug text,
  p_locale text,
  p_version_label text,
  p_visibility text,
  p_schema jsonb,
  p_form_values jsonb default '{}'::jsonb,
  p_autosave boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slug text := trim(coalesce(p_form_slug, ''));
  v_locale text := lower(trim(coalesce(p_locale, 'ar')));
  v_visibility text := lower(trim(coalesce(p_visibility, 'public')));
  v_form_id uuid;
  v_version_id uuid;
begin
  if v_slug = '' then
    return jsonb_build_object('ok', false, 'error', 'form_slug_required');
  end if;

  if v_locale not in ('ar','fa','en') then
    v_locale := 'ar';
  end if;

  if v_visibility not in ('public','administrative','finance_admin') then
    v_visibility := 'public';
  end if;

  insert into public.forms_v3_definitions(slug, visibility, latest_locale, latest_schema, status, created_by, updated_at)
  values (v_slug, v_visibility, v_locale, coalesce(p_schema, '{}'::jsonb), 'draft', auth.uid(), now())
  on conflict (slug) do update set
    visibility = excluded.visibility,
    latest_locale = excluded.latest_locale,
    latest_schema = excluded.latest_schema,
    status = 'draft',
    updated_at = now()
  returning id into v_form_id;

  insert into public.forms_v3_versions(
    form_id, form_slug, locale, version_label, visibility, autosave, schema_snapshot, form_values, created_by
  ) values (
    v_form_id,
    v_slug,
    v_locale,
    coalesce(nullif(trim(coalesce(p_version_label,'')), ''), now()::text),
    v_visibility,
    coalesce(p_autosave, true),
    coalesce(p_schema, '{}'::jsonb),
    coalesce(p_form_values, '{}'::jsonb),
    auth.uid()
  ) returning id into v_version_id;

  return jsonb_build_object(
    'ok', true,
    'form_id', v_form_id,
    'version_id', v_version_id,
    'saved_at', now()
  );
end;
$$;

grant execute on function public.forms_save_draft_v3(text,text,text,text,jsonb,jsonb,boolean) to authenticated, anon;

create or replace function public.forms_restore_version_v3(
  p_version_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rec public.forms_v3_versions%rowtype;
begin
  select * into v_rec from public.forms_v3_versions where id = p_version_id;
  if v_rec.id is null then
    return jsonb_build_object('ok', false, 'error', 'version_not_found');
  end if;

  return jsonb_build_object(
    'ok', true,
    'schema', v_rec.schema_snapshot,
    'form_values', v_rec.form_values,
    'restored_from', v_rec.id
  );
end;
$$;

grant execute on function public.forms_restore_version_v3(uuid) to authenticated, anon;

create or replace function public.forms_publish_v3(
  p_form_slug text,
  p_locale text,
  p_visibility text,
  p_schema jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res jsonb;
  v_form_id uuid;
begin
  v_res := public.forms_save_draft_v3(
    p_form_slug,
    p_locale,
    'publish:' || now()::text,
    p_visibility,
    p_schema,
    '{}'::jsonb,
    false
  );

  if coalesce((v_res->>'ok')::boolean, false) = false then
    return v_res;
  end if;

  v_form_id := (v_res->>'form_id')::uuid;

  update public.forms_v3_definitions
    set status = 'issued',
        updated_at = now()
  where id = v_form_id;

  return jsonb_build_object(
    'ok', true,
    'published_form_id', v_form_id,
    'issued_at', now(),
    'status', 'issued'
  );
end;
$$;

grant execute on function public.forms_publish_v3(text,text,text,jsonb) to authenticated, anon;

create or replace function public.forms_list_versions_v3(
  p_form_slug text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'versions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'version_id', id,
        'version_label', version_label,
        'saved_at', created_at,
        'autosave', autosave
      ) order by created_at desc)
      from public.forms_v3_versions
      where form_slug = trim(coalesce(p_form_slug, ''))
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.forms_list_versions_v3(text) to authenticated, anon;

create or replace function public.forms_request_upload_ticket_v3(
  p_form_slug text,
  p_locale text,
  p_field_id text,
  p_file_name text,
  p_content_type text,
  p_byte_size bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_slug text := trim(coalesce(p_form_slug, ''));
  v_locale text := lower(trim(coalesce(p_locale, 'ar')));
  v_field text := trim(coalesce(p_field_id, 'file'));
  v_name text := trim(coalesce(p_file_name, 'upload.bin'));
  v_safe_name text;
  v_object_path text;
  v_expires timestamptz := now() + interval '30 minutes';
begin
  if v_slug = '' then
    return jsonb_build_object('ok', false, 'error', 'form_slug_required');
  end if;

  if v_locale not in ('ar','fa','en') then
    v_locale := 'ar';
  end if;

  v_id := gen_random_uuid();
  v_safe_name := regexp_replace(v_name, '[^a-zA-Z0-9._-]+', '_', 'g');
  v_object_path := v_slug || '/' || v_field || '/' || v_id::text || '_' || v_safe_name;

  insert into public.forms_v3_upload_tickets(
    id, form_slug, locale, field_id, file_name, content_type, byte_size, object_path, expires_at, created_by
  ) values (
    v_id,
    v_slug,
    v_locale,
    v_field,
    v_name,
    nullif(trim(coalesce(p_content_type,'')), ''),
    greatest(coalesce(p_byte_size,0), 0),
    v_object_path,
    v_expires,
    auth.uid()
  );

  return jsonb_build_object(
    'ok', true,
    'ticket_id', v_id,
    'expires_at', v_expires,
    'object_path', v_object_path,
    'upload_strategy', 'server_ticketed_transport'
  );
end;
$$;

grant execute on function public.forms_request_upload_ticket_v3(text,text,text,text,text,bigint) to authenticated, anon;

create or replace function public.forms_resolve_upload_ticket_v3(
  p_ticket_id uuid,
  p_form_slug text,
  p_field_id text,
  p_file_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ticket public.forms_v3_upload_tickets%rowtype;
begin
  select * into v_ticket
  from public.forms_v3_upload_tickets
  where id = p_ticket_id;

  if v_ticket.id is null then
    return jsonb_build_object('ok', false, 'error', 'upload_ticket_not_found');
  end if;

  if v_ticket.expires_at < now() then
    return jsonb_build_object('ok', false, 'error', 'upload_ticket_expired');
  end if;

  if trim(coalesce(p_form_slug,'')) <> v_ticket.form_slug then
    return jsonb_build_object('ok', false, 'error', 'upload_ticket_form_mismatch');
  end if;

  if trim(coalesce(p_field_id,'')) <> v_ticket.field_id then
    return jsonb_build_object('ok', false, 'error', 'upload_ticket_field_mismatch');
  end if;

  if trim(coalesce(p_file_name,'')) <> v_ticket.file_name then
    return jsonb_build_object('ok', false, 'error', 'upload_ticket_file_name_mismatch');
  end if;

  return jsonb_build_object(
    'ok', true,
    'ticket_id', v_ticket.id,
    'object_path', v_ticket.object_path,
    'expires_at', v_ticket.expires_at
  );
end;
$$;

grant execute on function public.forms_resolve_upload_ticket_v3(uuid,text,text,text) to authenticated, anon;

create or replace function public.forms_finalize_upload_ticket_v3(
  p_ticket_id uuid,
  p_object_path text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ticket public.forms_v3_upload_tickets%rowtype;
begin
  select * into v_ticket from public.forms_v3_upload_tickets where id = p_ticket_id;
  if v_ticket.id is null then
    return jsonb_build_object('ok', false, 'error', 'upload_ticket_not_found');
  end if;

  update public.forms_v3_upload_tickets
    set object_path = coalesce(nullif(trim(coalesce(p_object_path,'')),''), object_path),
        consumed_at = now()
  where id = p_ticket_id;

  return jsonb_build_object(
    'ok', true,
    'ticket_id', p_ticket_id,
    'object_path', coalesce(nullif(trim(coalesce(p_object_path,'')),''), v_ticket.object_path),
    'consumed_at', now()
  );
end;
$$;

grant execute on function public.forms_finalize_upload_ticket_v3(uuid,text) to authenticated, anon;

create or replace function public.forms_submit_student_registration_v3(
  p_form_slug text,
  p_locale text,
  p_visibility text,
  p_submission_ref text,
  p_schema jsonb,
  p_values jsonb,
  p_upload_ticket_id uuid default null,
  p_uploaded_attachment jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_slug text := trim(coalesce(p_form_slug, ''));
  v_locale text := lower(trim(coalesce(p_locale, 'ar')));
  v_visibility text := lower(trim(coalesce(p_visibility, 'public')));
  v_ref text := trim(coalesce(p_submission_ref, ''));
begin
  if v_slug = '' then
    return jsonb_build_object('ok', false, 'error', 'form_slug_required');
  end if;
  if v_ref = '' then
    return jsonb_build_object('ok', false, 'error', 'submission_ref_required');
  end if;
  if v_locale not in ('ar','fa','en') then
    v_locale := 'ar';
  end if;
  if v_visibility not in ('public','administrative','finance_admin') then
    v_visibility := 'public';
  end if;

  insert into public.forms_v3_submissions(
    form_slug, locale, visibility, submission_ref, schema_snapshot, submission_values,
    upload_ticket_id, uploaded_attachment, status, created_by
  ) values (
    v_slug,
    v_locale,
    v_visibility,
    v_ref,
    coalesce(p_schema, '{}'::jsonb),
    coalesce(p_values, '{}'::jsonb),
    p_upload_ticket_id,
    p_uploaded_attachment,
    'received',
    auth.uid()
  ) returning id into v_id;

  if p_upload_ticket_id is not null then
    update public.forms_v3_upload_tickets
      set submission_ref = v_ref
    where id = p_upload_ticket_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'submission_id', v_id,
    'submission_ref', v_ref,
    'status', 'received'
  );
end;
$$;

grant execute on function public.forms_submit_student_registration_v3(text,text,text,text,jsonb,jsonb,uuid,jsonb) to authenticated, anon;

create or replace function public.forms_v3_health_check()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select jsonb_build_object(
    'ok', true,
    'definitions', to_regclass('public.forms_v3_definitions') is not null,
    'versions', to_regclass('public.forms_v3_versions') is not null,
    'upload_tickets', to_regclass('public.forms_v3_upload_tickets') is not null,
    'submissions', to_regclass('public.forms_v3_submissions') is not null,
    'rpc_save', to_regprocedure('public.forms_save_draft_v3(text,text,text,text,jsonb,jsonb,boolean)') is not null,
    'rpc_restore', to_regprocedure('public.forms_restore_version_v3(uuid)') is not null,
    'rpc_publish', to_regprocedure('public.forms_publish_v3(text,text,text,jsonb)') is not null,
    'rpc_list_versions', to_regprocedure('public.forms_list_versions_v3(text)') is not null,
    'rpc_request_upload_ticket', to_regprocedure('public.forms_request_upload_ticket_v3(text,text,text,text,text,bigint)') is not null,
    'rpc_resolve_upload_ticket', to_regprocedure('public.forms_resolve_upload_ticket_v3(uuid,text,text,text)') is not null,
    'rpc_finalize_upload_ticket', to_regprocedure('public.forms_finalize_upload_ticket_v3(uuid,text)') is not null,
    'rpc_submit_student_registration', to_regprocedure('public.forms_submit_student_registration_v3(text,text,text,text,jsonb,jsonb,uuid,jsonb)') is not null
  );
$$;

grant execute on function public.forms_v3_health_check() to authenticated, anon;

notify pgrst, 'reload schema';

-- ============================================================================
-- CRITICAL SECURITY LOCKDOWN — registration admin + Forms v3
-- Run this AFTER migrations 144..169 in Supabase SQL Editor.
--
-- Fixes:
-- 1) Blocks anonymous/list/detail/status access to Forms v3 review RPCs.
-- 2) Blocks direct anonymous calls to account-activation SECURITY DEFINER RPCs.
-- 3) Keeps one authenticated, role-checked activation wrapper for the admin page.
-- 4) Replaces birth-date/default passwords with one-time random credentials.
-- 5) Scrubs generated passwords from stored form-submission JSON.
-- 6) Makes registration photos private and removes public read/update/delete policies.
-- 7) Invalidates the historically hard-coded test account password if that account exists.
-- ============================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

alter table if exists public.registration_families
  add column if not exists password_policy_status text;
alter table if exists public.registration_students
  add column if not exists password_policy_status text;
alter table if exists public.registration_teachers
  add column if not exists password_policy_status text;

-- --------------------------------------------------------------------------
-- A. Authorization helper used only by privileged database code.
-- --------------------------------------------------------------------------
create or replace function public.registration_security_is_reviewer_v170()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and exists (
       select 1
       from public.users u
       where u.id = auth.uid()
         and coalesce(u.active, true) = true
         and (
           coalesce(u.is_super_admin, false) = true
           or lower(coalesce(u.role, '')) in ('admin', 'academic', 'academic_admin')
         )
     );
$$;

revoke all on function public.registration_security_is_reviewer_v170() from public, anon, authenticated;
grant execute on function public.registration_security_is_reviewer_v170() to service_role;

-- --------------------------------------------------------------------------
-- B. Preserve the latest activation implementation behind a private name,
--    then expose a role-checked wrapper under the name used by the UI.
-- --------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.activate_registered_user_rpc_internal_v170(text,uuid)') is null then
    if to_regprocedure('public.activate_registered_user_rpc(text,uuid)') is null then
      raise exception 'activate_registered_user_rpc(text,uuid) is missing; run migration 153 first';
    end if;

    alter function public.activate_registered_user_rpc(text, uuid)
      rename to activate_registered_user_rpc_internal_v170;
  end if;
end $$;

revoke all on function public.activate_registered_user_rpc_internal_v170(text, uuid) from public, anon, authenticated;
grant execute on function public.activate_registered_user_rpc_internal_v170(text, uuid) to service_role;

-- Old overloaded activation functions must never be callable by a browser user.
do $$
begin
  if to_regprocedure('public.activate_registered_user(text,uuid)') is not null then
    revoke all on function public.activate_registered_user(text, uuid) from public, anon, authenticated;
    grant execute on function public.activate_registered_user(text, uuid) to service_role;
  end if;

  if to_regprocedure('public.activate_registered_user(uuid,text)') is not null then
    revoke all on function public.activate_registered_user(uuid, text) from public, anon, authenticated;
    grant execute on function public.activate_registered_user(uuid, text) to service_role;
  end if;

  if to_regprocedure('public.registration_sync_finance_after_family_activation(uuid,uuid,uuid)') is not null then
    revoke all on function public.registration_sync_finance_after_family_activation(uuid, uuid, uuid) from public, anon, authenticated;
    grant execute on function public.registration_sync_finance_after_family_activation(uuid, uuid, uuid) to service_role;
  end if;
end $$;

create or replace function public.activate_registered_user_rpc(
  p_reg_type text,
  p_reg_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_type text := lower(trim(coalesce(p_reg_type, '')));
  v_result jsonb;
  v_credentials jsonb := '[]'::jsonb;
  v_temp_password text;
  v_user_id uuid;
  v_email text;
  v_name text;
  v_student record;
begin
  if not public.registration_security_is_reviewer_v170() then
    return jsonb_build_object('ok', false, 'error', 'forbidden_registration_review');
  end if;

  if v_type not in ('family', 'teacher') then
    return jsonb_build_object('ok', false, 'error', 'unsupported_registration_type');
  end if;

  v_result := public.activate_registered_user_rpc_internal_v170(v_type, p_reg_id);
  if not coalesce((v_result->>'ok')::boolean, false) then
    return v_result;
  end if;

  -- The legacy implementation may briefly choose a birth-date/default password.
  -- Rotate it in the SAME transaction before returning control to the caller.
  if v_type = 'teacher' then
    begin
      v_user_id := nullif(v_result->>'id', '')::uuid;
    exception when others then
      v_user_id := null;
    end;

    if v_user_id is not null then
      v_temp_password := 'A!' || encode(gen_random_bytes(12), 'hex');

      update auth.users
      set encrypted_password = crypt(v_temp_password, gen_salt('bf')),
          raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
            || jsonb_build_object('password_change_required', true),
          updated_at = now()
      where id = v_user_id
      returning email, coalesce(raw_user_meta_data->>'name', email)
        into v_email, v_name;

      if found then
        v_credentials := v_credentials || jsonb_build_array(jsonb_build_object(
          'role', 'teacher',
          'name', v_name,
          'login', v_email,
          'temporary_password', v_temp_password
        ));
      end if;
    end if;

    update public.registration_teachers
    set initial_password = null,
        password_policy_status = 'one_time_random_issued',
        updated_at = now()
    where id = p_reg_id;
  else
    begin
      v_user_id := nullif(v_result->>'parent_id', '')::uuid;
    exception when others then
      v_user_id := null;
    end;

    if v_user_id is not null then
      v_temp_password := 'A!' || encode(gen_random_bytes(12), 'hex');

      update auth.users
      set encrypted_password = crypt(v_temp_password, gen_salt('bf')),
          raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
            || jsonb_build_object('password_change_required', true),
          updated_at = now()
      where id = v_user_id
      returning email, coalesce(raw_user_meta_data->>'name', email)
        into v_email, v_name;

      if found then
        v_credentials := v_credentials || jsonb_build_array(jsonb_build_object(
          'role', 'parent',
          'name', v_name,
          'login', v_email,
          'temporary_password', v_temp_password
        ));
      end if;
    end if;

    for v_student in
      select
        rs.id,
        rs.student_name,
        case
          when position('@' in lower(trim(coalesce(rs.generated_username, '')))) > 0
            then lower(trim(rs.generated_username))
          else lower(trim(coalesce(nullif(rs.generated_username, ''), rs.student_code, 'stu_' || substr(rs.id::text, 1, 8)))) || '@ameen.iq'
        end as login_email
      from public.registration_students rs
      where rs.family_id = p_reg_id
    loop
      select au.id, au.email, coalesce(au.raw_user_meta_data->>'name', v_student.student_name, au.email)
      into v_user_id, v_email, v_name
      from auth.users au
      where lower(au.email) = lower(v_student.login_email)
      limit 1;

      if v_user_id is not null then
        v_temp_password := 'A!' || encode(gen_random_bytes(12), 'hex');

        update auth.users
        set encrypted_password = crypt(v_temp_password, gen_salt('bf')),
            raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
              || jsonb_build_object('password_change_required', true),
            updated_at = now()
        where id = v_user_id;

        v_credentials := v_credentials || jsonb_build_array(jsonb_build_object(
          'role', 'student',
          'name', v_name,
          'login', v_email,
          'temporary_password', v_temp_password
        ));
      end if;
    end loop;

    update public.registration_families
    set initial_password = null,
        password_policy_status = 'one_time_random_issued',
        updated_at = now()
    where id = p_reg_id;

    update public.registration_students
    set initial_password = null,
        password_policy_status = 'one_time_random_issued',
        updated_at = now()
    where family_id = p_reg_id;
  end if;

  return v_result || jsonb_build_object(
    'credentials', v_credentials,
    'credentials_notice', 'Shown once. Deliver securely and require a password change.'
  );
end;
$$;

revoke all on function public.activate_registered_user_rpc(text, uuid) from public, anon;
grant execute on function public.activate_registered_user_rpc(text, uuid) to authenticated, service_role;

-- --------------------------------------------------------------------------
-- C. Remove password material from form-submission JSON, now and in future.
-- --------------------------------------------------------------------------
create or replace function public.forms_scrub_passwords_v170(p_payload jsonb)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = public
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_students jsonb := '[]'::jsonb;
  v_item jsonb;
begin
  v_payload := v_payload
    - 'initial_password'
    - 'guardian_initial_password'
    - 'student_initial_password'
    - 'teacher_initial_password';

  if jsonb_typeof(v_payload->'guardian') = 'object' then
    v_payload := jsonb_set(
      v_payload,
      '{guardian}',
      (v_payload->'guardian') - 'initial_password' - 'guardian_initial_password',
      true
    );
  end if;

  if jsonb_typeof(v_payload->'students') = 'array' then
    for v_item in select value from jsonb_array_elements(v_payload->'students')
    loop
      v_students := v_students || jsonb_build_array(
        v_item - 'initial_password' - 'student_initial_password'
      );
    end loop;
    v_payload := jsonb_set(v_payload, '{students}', v_students, true);
  end if;

  return v_payload;
end;
$$;

revoke all on function public.forms_scrub_passwords_v170(jsonb) from public, anon, authenticated;
grant execute on function public.forms_scrub_passwords_v170(jsonb) to service_role;

create or replace function public.forms_scrub_passwords_trigger_v170()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.submission_values := public.forms_scrub_passwords_v170(new.submission_values);
  return new;
end;
$$;

revoke all on function public.forms_scrub_passwords_trigger_v170() from public, anon, authenticated;

alter table if exists public.forms_v3_submissions enable row level security;

drop trigger if exists trg_forms_scrub_passwords_v170 on public.forms_v3_submissions;
create trigger trg_forms_scrub_passwords_v170
before insert or update of submission_values on public.forms_v3_submissions
for each row execute function public.forms_scrub_passwords_trigger_v170();

update public.forms_v3_submissions
set submission_values = public.forms_scrub_passwords_v170(submission_values)
where submission_values is not null;

-- --------------------------------------------------------------------------
-- D. All Forms v3 RPCs are server-only. Public form submissions continue via
--    the Next.js API, whose server holds the service-role key.
-- --------------------------------------------------------------------------
do $$
declare
  v_signature text;
begin
  for v_signature in
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'forms\_%\_v3' escape '\'
      and p.proname not in ('forms_scrub_passwords_v170', 'forms_scrub_passwords_trigger_v170')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', v_signature);
    execute format('grant execute on function %s to service_role', v_signature);
  end loop;
end $$;

-- --------------------------------------------------------------------------
-- E. Database-backed limiter used by the public Next.js routes.
-- --------------------------------------------------------------------------
create table if not exists public.forms_v3_rate_limits (
  key_hash text not null,
  action text not null,
  window_started_at timestamptz not null,
  request_count integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (key_hash, action)
);

alter table public.forms_v3_rate_limits enable row level security;
revoke all on table public.forms_v3_rate_limits from public, anon, authenticated;
grant select, insert, update, delete on table public.forms_v3_rate_limits to service_role;

create or replace function public.forms_rate_limit_check_v3(
  p_key_hash text,
  p_action text,
  p_limit integer,
  p_window_seconds integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_window interval := make_interval(secs => greatest(coalesce(p_window_seconds, 60), 1));
  v_count integer;
  v_started timestamptz;
begin
  if trim(coalesce(p_key_hash, '')) = '' or trim(coalesce(p_action, '')) = '' then
    return jsonb_build_object('ok', false, 'allowed', false, 'error', 'rate_limit_key_required');
  end if;

  insert into public.forms_v3_rate_limits(key_hash, action, window_started_at, request_count, updated_at)
  values (trim(p_key_hash), trim(p_action), v_now, 1, v_now)
  on conflict (key_hash, action) do update
  set request_count = case
        when public.forms_v3_rate_limits.window_started_at + v_window <= v_now then 1
        else public.forms_v3_rate_limits.request_count + 1
      end,
      window_started_at = case
        when public.forms_v3_rate_limits.window_started_at + v_window <= v_now then v_now
        else public.forms_v3_rate_limits.window_started_at
      end,
      updated_at = v_now
  returning request_count, window_started_at into v_count, v_started;

  return jsonb_build_object(
    'ok', true,
    'allowed', v_count <= greatest(coalesce(p_limit, 1), 1),
    'count', v_count,
    'limit', greatest(coalesce(p_limit, 1), 1),
    'retry_after_seconds', greatest(0, extract(epoch from ((v_started + v_window) - v_now))::integer)
  );
end;
$$;

revoke all on function public.forms_rate_limit_check_v3(text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.forms_rate_limit_check_v3(text, text, integer, integer) to service_role;

-- --------------------------------------------------------------------------
-- F. Registration photos must not be publicly readable or replaceable.
-- --------------------------------------------------------------------------
update storage.buckets
set public = false
where id = 'registration-photos';

drop policy if exists registration_photos_select_all on storage.objects;
drop policy if exists registration_photos_update_all on storage.objects;
drop policy if exists registration_photos_delete_all on storage.objects;

-- Keep public INSERT support for the legacy registration form, but not read/update/delete.
-- Existing admin-only read policy remains authoritative.

-- --------------------------------------------------------------------------
-- G. Invalidate the password publicly embedded in historical migration 117.
--    The account can later be re-issued securely from registrations-admin.
-- --------------------------------------------------------------------------
update auth.users
set encrypted_password = crypt('A!' || encode(gen_random_bytes(24), 'hex'), gen_salt('bf')),
    raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
      || jsonb_build_object('password_change_required', true, 'security_rotation_v170', true),
    updated_at = now()
where lower(email) = 'slyman@ameen.iq';

-- --------------------------------------------------------------------------
-- H. Health check (SQL Editor / service role only).
-- --------------------------------------------------------------------------
create or replace function public.forms_security_lockdown_health_check_v170()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select jsonb_build_object(
    'ok', true,
    'activation_wrapper_exists', to_regprocedure('public.activate_registered_user_rpc(text,uuid)') is not null,
    'activation_internal_exists', to_regprocedure('public.activate_registered_user_rpc_internal_v170(text,uuid)') is not null,
    'anon_can_activate', has_function_privilege('anon', 'public.activate_registered_user_rpc(text,uuid)', 'EXECUTE'),
    'authenticated_can_activate', has_function_privilege('authenticated', 'public.activate_registered_user_rpc(text,uuid)', 'EXECUTE'),
    'anon_can_list_submissions', case
      when to_regprocedure('public.forms_list_submissions_v3(text,text,text,date,date,integer)') is null then false
      else has_function_privilege('anon', 'public.forms_list_submissions_v3(text,text,text,date,date,integer)', 'EXECUTE')
    end,
    'registration_photos_private', coalesce((select not public from storage.buckets where id='registration-photos'), true),
    'password_scrub_trigger', exists(
      select 1 from pg_trigger where tgname='trg_forms_scrub_passwords_v170' and not tgisinternal
    ),
    'rate_limit_rpc_exists', to_regprocedure('public.forms_rate_limit_check_v3(text,text,integer,integer)') is not null
  );
$$;

revoke all on function public.forms_security_lockdown_health_check_v170() from public, anon, authenticated;
grant execute on function public.forms_security_lockdown_health_check_v170() to service_role;

notify pgrst, 'reload schema';

-- Verify after running:
-- select public.forms_security_lockdown_health_check_v170();
-- Expected: anon_can_activate=false, authenticated_can_activate=true,
--           anon_can_list_submissions=false, registration_photos_private=true.

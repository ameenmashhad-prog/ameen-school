-- =============================================================
-- مدارس أمين الرضا (ع) — Standalone Fix لتفعيل RLS وفحص users
-- استخدم هذا الملف إذا ظهر:
-- function public.users_rls_final_health_check() does not exist
-- آمن ويمكن تشغيله أكثر من مرة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) تأكد أن جدول users موجود
-- -------------------------------------------------------------
do $$ begin
  if to_regclass('public.users') is null then
    raise exception 'جدول public.users غير موجود. لا يمكن تفعيل RLS.';
  end if;
end $$;

-- -------------------------------------------------------------
-- 2) دوال صلاحيات آمنة
-- -------------------------------------------------------------
create or replace function public.current_user_is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1
    from public.users u
    where u.id = auth.uid()
      and (u.role = 'admin' or coalesce(u.is_super_admin,false)=true)
  );
$$;

grant execute on function public.current_user_is_admin() to authenticated;

create or replace function public.current_user_is_super_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1
    from public.users u
    where u.id = auth.uid()
      and coalesce(u.is_super_admin,false)=true
  );
$$;

grant execute on function public.current_user_is_super_admin() to authenticated;

-- -------------------------------------------------------------
-- 3) View عامة مستقبلية للأسماء والأدوار
-- -------------------------------------------------------------
drop view if exists public.v_user_public_profiles;

create view public.v_user_public_profiles
with (security_invoker=true) as
select
  id,
  name,
  email,
  role,
  is_super_admin
from public.users;

grant select on public.v_user_public_profiles to authenticated;

-- -------------------------------------------------------------
-- 4) تفعيل RLS وسياسات متوافقة
-- -------------------------------------------------------------
alter table public.users enable row level security;

-- حذف أي سياسات قديمة من محاولات سابقة
DROP POLICY IF EXISTS users_select_authenticated_safe ON public.users;
DROP POLICY IF EXISTS users_insert_admin_safe ON public.users;
DROP POLICY IF EXISTS users_update_admin_safe ON public.users;
DROP POLICY IF EXISTS users_delete_super_admin_safe ON public.users;
DROP POLICY IF EXISTS users_self_select ON public.users;
DROP POLICY IF EXISTS users_admin_all ON public.users;
DROP POLICY IF EXISTS users_read_all_authenticated ON public.users;
DROP POLICY IF EXISTS users_admin_write ON public.users;

-- قراءة للمستخدمين المسجلين حفاظاً على توافق كل الصفحات الحالية.
create policy users_select_authenticated_safe
on public.users
for select
to authenticated
using (true);

-- الإضافة للإدارة فقط.
create policy users_insert_admin_safe
on public.users
for insert
to authenticated
with check (public.current_user_is_admin());

-- التعديل للإدارة فقط.
create policy users_update_admin_safe
on public.users
for update
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

-- الحذف للمسؤول الأعلى فقط.
create policy users_delete_super_admin_safe
on public.users
for delete
to authenticated
using (public.current_user_is_super_admin());

grant select, insert, update, delete on public.users to authenticated;

-- -------------------------------------------------------------
-- 5) Health Check مستقل
-- -------------------------------------------------------------
create or replace function public.users_rls_final_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rls_enabled boolean := false;
  policy_rows jsonb := '[]'::jsonb;
  current_profile jsonb := null;
  has_users boolean := false;
begin
  has_users := to_regclass('public.users') is not null;

  if has_users then
    select c.relrowsecurity
    into rls_enabled
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname='public'
      and c.relname='users';

    select coalesce(jsonb_agg(jsonb_build_object(
      'policyname', policyname,
      'cmd', cmd,
      'roles', roles,
      'qual', qual,
      'with_check', with_check
    ) order by policyname), '[]'::jsonb)
    into policy_rows
    from pg_policies
    where schemaname='public'
      and tablename='users';

    select to_jsonb(u)
    into current_profile
    from (
      select id, name, email, role, is_super_admin
      from public.users
      where id = auth.uid()
    ) u;
  end if;

  return jsonb_build_object(
    'checked_at', now(),
    'users_table_exists', has_users,
    'rls_enabled', coalesce(rls_enabled,false),
    'policies_count', jsonb_array_length(coalesce(policy_rows,'[]'::jsonb)),
    'policies', coalesce(policy_rows,'[]'::jsonb),
    'auth_uid', auth.uid(),
    'current_profile_visible', current_profile is not null,
    'current_profile', current_profile,
    'expected_result', jsonb_build_object(
      'rls_enabled_should_be', true,
      'policies_count_minimum', 4,
      'current_profile_visible_should_be', auth.uid() is not null
    ),
    'notes', jsonb_build_array(
      'RLS مفعل على users.',
      'القراءة متاحة لكل authenticated مؤقتاً للحفاظ على توافق الصفحات.',
      'الإضافة والتعديل للإدارة فقط، والحذف للمسؤول الأعلى فقط.',
      'Rollback الطارئ: sql/84_users_rls_rollback_disable.sql'
    )
  );
end;
$$;

grant execute on function public.users_rls_final_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'users_rls_final_standalone_fix_ready' as status;

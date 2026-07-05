-- =============================================================
-- مدارس أمين الرضا (ع) — RLS النهائي الآمن لجدول users
-- الهدف: تفعيل RLS على users بدون كسر تسجيل الدخول أو الصفحات الحالية.
-- السياسة الحالية تسمح لكل مستخدم authenticated بقراءة ملفات المستخدمين الأساسية
-- لأن النظام الحالي يعتمد على public.users في Views وصفحات كثيرة لعرض أسماء المعلمين/الأهل/المستلمين.
-- التعديل/الإضافة/الحذف محصور بالإدارة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) دوال صلاحيات آمنة SECURITY DEFINER
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

-- View عام مستقبلي يمكن استخدامه لاحقاً بدلاً من قراءة users مباشرة.
-- لا يكسر شيئاً الآن، فقط يوفّر طبقة أنظف للمرحلة القادمة.
create or replace view public.v_user_public_profiles
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
-- 2) تفعيل RLS على users
-- ملاحظة: لا نستخدم FORCE ROW LEVEL SECURITY حتى لا نكسر SECURITY DEFINER functions.
-- -------------------------------------------------------------
alter table public.users enable row level security;

-- إزالة سياسات قديمة بنفس الأسماء إن وجدت
DROP POLICY IF EXISTS users_select_authenticated_safe ON public.users;
DROP POLICY IF EXISTS users_insert_admin_safe ON public.users;
DROP POLICY IF EXISTS users_update_admin_safe ON public.users;
DROP POLICY IF EXISTS users_delete_super_admin_safe ON public.users;
DROP POLICY IF EXISTS users_self_select ON public.users;
DROP POLICY IF EXISTS users_admin_all ON public.users;

-- -------------------------------------------------------------
-- 3) سياسات القراءة
-- -------------------------------------------------------------
-- قراءة كل المستخدمين للمستخدمين المسجلين فقط.
-- هذا مقصود حالياً للحفاظ على عمل:
-- teacher names, parent names, receivers, audit labels, reports, views.
create policy users_select_authenticated_safe
on public.users
for select
to authenticated
using (true);

-- -------------------------------------------------------------
-- 4) سياسات الكتابة
-- -------------------------------------------------------------
-- إنشاء مستخدم داخل public.users للإدارة فقط.
create policy users_insert_admin_safe
on public.users
for insert
to authenticated
with check (public.current_user_is_admin());

-- تعديل المستخدمين للإدارة فقط.
-- يمنع المستخدم العادي من رفع صلاحياته أو تغيير role/is_super_admin عبر الواجهة.
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

-- Grants مطلوبة للـ PostgREST، والـ RLS يحدد الصفوف.
grant select, insert, update, delete on public.users to authenticated;

-- -------------------------------------------------------------
-- 5) فحص صحة RLS على users
-- -------------------------------------------------------------
create or replace function public.users_rls_final_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rls_enabled boolean;
  policy_rows jsonb;
  current_profile jsonb;
begin
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

  return jsonb_build_object(
    'checked_at', now(),
    'users_table_exists', to_regclass('public.users') is not null,
    'rls_enabled', coalesce(rls_enabled,false),
    'policies_count', jsonb_array_length(policy_rows),
    'policies', policy_rows,
    'auth_uid', auth.uid(),
    'current_profile_visible', current_profile is not null,
    'current_profile', current_profile,
    'notes', jsonb_build_array(
      'RLS مفعل على users.',
      'القراءة متاحة لكل authenticated حفاظاً على توافق الصفحات الحالية.',
      'الإضافة والتعديل للإدارة فقط، والحذف للمسؤول الأعلى فقط.',
      'إذا حصل منع دخول أو خطأ صلاحيات، شغّل rollback: sql/84_users_rls_rollback_disable.sql'
    )
  );
end;
$$;

grant execute on function public.users_rls_final_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'users_final_rls_enabled_safe' as status;

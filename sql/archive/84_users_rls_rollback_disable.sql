-- =============================================================
-- مدارس أمين الرضا (ع) — Rollback طارئ لتعطيل RLS على users
-- استخدمه فقط إذا حصلت مشكلة دخول/صلاحيات بعد تفعيل SQL 83.
-- =============================================================

alter table public.users disable row level security;

DROP POLICY IF EXISTS users_select_authenticated_safe ON public.users;
DROP POLICY IF EXISTS users_insert_admin_safe ON public.users;
DROP POLICY IF EXISTS users_update_admin_safe ON public.users;
DROP POLICY IF EXISTS users_delete_super_admin_safe ON public.users;

notify pgrst, 'reload schema';

select 'users_rls_disabled_rollback_done' as status;

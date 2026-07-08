-- ============================================================================
-- Fix: eliminate PostgREST RPC ambiguity for activate_registered_user
--
-- المشكلة:
-- وجود دالتين بنفس الاسم:
--   public.activate_registered_user(text, uuid)
--   public.activate_registered_user(uuid, text)
--
-- يجعل استدعاء RPC عبر PostgREST بالوسائط المسماة غامضاً أحياناً:
--   PGRST203: Could not choose the best candidate function ...
--
-- الحل الآمن والسريع:
-- إنشاء اسم RPC فريد غير محمّل (غير overloaded) تستخدمه الواجهة الإدارية.
-- ============================================================================

create or replace function public.activate_registered_user_rpc(
  p_reg_type text,
  p_reg_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
begin
  return public.activate_registered_user(p_reg_type, p_reg_id);
end;
$$;

grant execute on function public.activate_registered_user_rpc(text, uuid) to authenticated, anon;

notify pgrst, 'reload schema';

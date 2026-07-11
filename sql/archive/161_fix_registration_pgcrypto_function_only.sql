-- ============================================================================
-- SAFEST PATCH — إصلاح دالة تشفير كلمات المرور فقط بدون المساس بالـ triggers
--
-- استخدم هذا الملف إذا ظهر deadlock عند محاولة drop/create trigger.
--
-- الفكرة:
-- - لا نحذف أي trigger
-- - لا نعيد إنشاء أي trigger
-- - نعيد تعريف نفس الدالة فقط:
--     public._hash_initial_password_trg()
-- - بما أن الـ triggers الحالية تستدعي هذه الدالة بالاسم نفسه، فسيتم استخدام
--   النسخة الجديدة مباشرة بعد create or replace function.
-- ============================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create or replace function public._hash_initial_password_trg()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if NEW.initial_password is not null and NEW.initial_password not like '$2%' then
    NEW.initial_password := crypt(NEW.initial_password, gen_salt('bf'));
  end if;
  return NEW;
end;
$$;

notify pgrst, 'reload schema';

-- ============================================================================
-- إعادة تعريف قيد no_plain_initial_password ليقبل:
--   - القيمة الفارغة (NULL)
--   - صيغة تاريخ الميلاد DDMMYYYY (8 أرقام) — خيار صاحب المشروع (كلمة المرور = تاريخ الميلاد)
--   - الهاش bcrypt ($2...) — كبول أمان إن اشتغل الـ Trigger بالتشفير
-- هذا يضمن نجاح insert كلمة المرور بصيغة تاريخ الميلاد سواء تشفّرت أم لا.
-- شغّل في Supabase -> SQL Editor (idempotent).
-- ============================================================================

do $$ begin
  -- teachers
  alter table public.registration_teachers
    drop constraint if exists registration_teachers_no_plain_initial_password;
  alter table public.registration_teachers
    add constraint registration_teachers_no_plain_initial_password
    check (initial_password is null
           or initial_password ~ '^[0-9]{8}$'
           or initial_password like '$2%');

  -- families
  alter table public.registration_families
    drop constraint if exists registration_families_no_plain_initial_password;
  alter table public.registration_families
    add constraint registration_families_no_plain_initial_password
    check (initial_password is null
           or initial_password ~ '^[0-9]{8}$'
           or initial_password like '$2%');

  -- students
  alter table public.registration_students
    drop constraint if exists registration_students_no_plain_initial_password;
  alter table public.registration_students
    add constraint registration_students_no_plain_initial_password
    check (initial_password is null
           or initial_password ~ '^[0-9]{8}$'
           or initial_password like '$2%');
end $$;

-- تشخيص: هل الـ Trigger التشفيري موجود فعلاً؟ (للتأكد مستقبلاً)
select tgname, tgrelid::regclass as table_name, tgenabled
from pg_trigger
where tgname = 'trg_hash_initial_password';

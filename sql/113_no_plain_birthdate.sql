-- ============================================================================
-- حل نهائي لمشكلة no_plain_initial_password:
-- إعادة تعريف القيد ليقبل أي كلمة بطول >= 8 (يغطي تاريخ الميلاد DDMMYYYY = 8 خانات
-- وأي كلمة بديلة) أو هاش bcrypt ($2...) كبول أمان. هذا يضمن نجاح insert كلمة المرور
-- بغض النظر عن القيمة المُرسلة من الواجهة.
-- شغّل في Supabase -> SQL Editor ولصق المخرجات للتأكد. (idempotent)
-- ============================================================================

do $$ begin
  alter table public.registration_teachers
    drop constraint if exists registration_teachers_no_plain_initial_password;
  alter table public.registration_teachers
    add constraint registration_teachers_no_plain_initial_password
    check (initial_password is null or length(initial_password) >= 8 or initial_password like '$2%');

  alter table public.registration_families
    drop constraint if exists registration_families_no_plain_initial_password;
  alter table public.registration_families
    add constraint registration_families_no_plain_initial_password
    check (initial_password is null or length(initial_password) >= 8 or initial_password like '$2%');

  alter table public.registration_students
    drop constraint if exists registration_students_no_plain_initial_password;
  alter table public.registration_students
    add constraint registration_students_no_plain_initial_password
    check (initial_password is null or length(initial_password) >= 8 or initial_password like '$2%');
end $$;

-- إعادة تحميل مخطط PostgREST (احتياطي، حتى تنعكس أي تغييرات هيكلية على الـ REST API).
notify pgrst, 'reload schema';

-- التحقق: طباعة تعريف القيود الحالي للتأكد من التطبيق.
select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conname like '%no_plain_initial_password'
order by conname;

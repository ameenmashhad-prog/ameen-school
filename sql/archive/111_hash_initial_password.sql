-- ============================================================================
-- حل خطأ: violates check constraint "registration_families_no_plain_initial_password"
-- المشكلة: وحدة التسجيل ترسل كلمة المرور المؤقتة بنص واضح إلى عمود initial_password،
--          وقيد no_plain_initial_password (موجود في Supabase) يمنع تخزين النص الواضح.
-- الحل: Trigger على مستوى القاعدة يشفّر initial_password تلقائياً (bcrypt) قبل التخزين
--       عبر pgcrypto، دون أي تعديل على واجهة JS ولا مكتبات خارجية.
--       ينطبق على registration_families / registration_students / registration_teachers.
-- ملاحظة أمان: هذا لا يكسر الدخول — auth.users (Supabase Auth) منفصل، وعمود initial_password
--       مجرد سجل؛ كلمة الدخول الفعلية تُدار عبر Supabase Auth.
-- ============================================================================

create extension if not exists pgcrypto;

-- دالة التشفير: تشفّر فقط القيمة النصية غير المشفّرة مسبقاً (تتجاهل القيم الفارغة والهاش).
create or replace function public._hash_initial_password_trg()
returns trigger language plpgsql as $$
begin
  if NEW.initial_password is not null and NEW.initial_password not like '$2%' then
    NEW.initial_password = crypt(NEW.initial_password, gen_salt('bf'));
  end if;
  return NEW;
end $$;

-- تطبيق الـ trigger على الجداول الثلاثة (idempotent — يحذف القديم أولاً).
do $$ begin
  if not exists(select 1 from pg_tables where schemaname='public' and tablename='registration_families') then
    raise notice 'registration_families غير موجود — يتم التخطي';
  else
    drop trigger if exists trg_hash_initial_password on public.registration_families;
    create trigger trg_hash_initial_password
      before insert or update of initial_password on public.registration_families
      for each row execute function public._hash_initial_password_trg();
  end if;

  if not exists(select 1 from pg_tables where schemaname='public' and tablename='registration_students') then
    raise notice 'registration_students غير موجود — يتم التخطي';
  else
    drop trigger if exists trg_hash_initial_password on public.registration_students;
    create trigger trg_hash_initial_password
      before insert or update of initial_password on public.registration_students
      for each row execute function public._hash_initial_password_trg();
  end if;

  if not exists(select 1 from pg_tables where schemaname='public' and tablename='registration_teachers') then
    raise notice 'registration_teachers غير موجود — يتم التخطي';
  else
    drop trigger if exists trg_hash_initial_password on public.registration_teachers;
    create trigger trg_hash_initial_password
      before insert or update of initial_password on public.registration_teachers
      for each row execute function public._hash_initial_password_trg();
  end if;
end $$;

-- تنظيف أي قيم نصية واضعة موجودة مسبقاً (تشفيرها مرة واحدة).
update public.registration_families
  set initial_password = crypt(initial_password, gen_salt('bf'))
  where initial_password is not null and initial_password not like '$2%';
update public.registration_students
  set initial_password = crypt(initial_password, gen_salt('bf'))
  where initial_password is not null and initial_password not like '$2%';
update public.registration_teachers
  set initial_password = crypt(initial_password, gen_salt('bf'))
  where initial_password is not null and initial_password not like '$2%';

-- ============================================================================
-- ملف شامل واحد: يجعل كلمة المرور المؤقتة = تاريخ الميلاد بصيغة DDMMYYYY
-- ويُرضي قيدي no_plain_initial_password و initial_password_strength معاً.
-- شغّل هذا الملف فقط في Supabase -> SQL Editor (idempotent / آمن للتكرار).
--
-- ما يفعله:
--  1) يتأكد من توفر ملحق pgcrypto (للتشفير).
--  2) يضيف Trigger يشفّر initial_password تلقائياً (bcrypt) قبل التخزين -> no_plain.
--  3) يخفّف قيد القوة إلى "الطول >= 8" ليسمح بصيغة تاريخ الميلاد (DDMMYYYY) كبول أمان.
--  4) يشفّر أي قيم نصية موجودة مسبقاً.
-- ملاحظة أمان: كلمة الدخول الفعلية تُدار عبر Supabase Auth؛ هذا العمود مجرد سجل،
--          وتاريخ الميلاد مخزّن أصلاً في عمود birth_date فتبقى قابلة للاسترجاع.
-- ============================================================================

create extension if not exists pgcrypto;

-- دالة التشفير (تشفّر النص غير المشفّر مسبقاً فقط).
create or replace function public._hash_initial_password_trg()
returns trigger language plpgsql as $$
begin
  if NEW.initial_password is not null and NEW.initial_password not like '$2%' then
    NEW.initial_password = crypt(NEW.initial_password, gen_salt('bf'));
  end if;
  return NEW;
end $$;

-- تطبيق الـ Trigger على الجداول الثلاثة.
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

-- تشفير أي قيم نصية موجودة مسبقاً.
update public.registration_families
  set initial_password = crypt(initial_password, gen_salt('bf'))
  where initial_password is not null and initial_password not like '$2%';
update public.registration_students
  set initial_password = crypt(initial_password, gen_salt('bf'))
  where initial_password is not null and initial_password not like '$2%';
update public.registration_teachers
  set initial_password = crypt(initial_password, gen_salt('bf'))
  where initial_password is not null and initial_password not like '$2%';

-- تخفيف قيد القوة للسماح بصيغة تاريخ الميلاد (DDMMYYYY = 8 خانات) كبول أمان.
-- (يُضاف not valid حتى لا يُعاد فحص الصفوف القديمة.)
do $$ begin
  alter table public.registration_families
    drop constraint if exists registration_families_initial_password_strength;
  alter table public.registration_families
    add constraint registration_families_initial_password_strength
    check (initial_password is null or length(initial_password) >= 8) not valid;

  alter table public.registration_students
    drop constraint if exists registration_students_initial_password_strength;
  alter table public.registration_students
    add constraint registration_students_initial_password_strength
    check (initial_password is null or length(initial_password) >= 8) not valid;

  alter table public.registration_teachers
    drop constraint if exists registration_teachers_initial_password_strength;
  alter table public.registration_teachers
    add constraint registration_teachers_initial_password_strength
    check (initial_password is null or length(initial_password) >= 8) not valid;
end $$;

-- التحقق.
select
  (select count(*) from public.registration_teachers where initial_password is not null and initial_password not like '$2%') as teachers_remaining_plaintext,
  (select count(*) from public.registration_teachers where initial_password like '$2%') as teachers_hashed;

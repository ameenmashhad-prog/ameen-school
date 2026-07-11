-- ============================================================================
-- Fix registration password hashing trigger + ensure pgcrypto visibility
--
-- المشكلة:
-- submit family-registration-v3 كان يفشل برسالة:
--   function gen_salt(unknown) does not exist
--
-- السبب:
-- trigger hashing على registration_families / registration_students / registration_teachers
-- يستدعي crypt / gen_salt بدون search_path يضمن رؤية pgcrypto.
--
-- الحل:
-- 1) التأكد من وجود pgcrypto
-- 2) إعادة تعريف trigger function مع search_path مناسب
-- 3) إعادة تركيب الـ triggers على جداول التسجيل
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

do $$ begin
  if exists(select 1 from pg_tables where schemaname='public' and tablename='registration_families') then
    drop trigger if exists trg_hash_initial_password on public.registration_families;
    create trigger trg_hash_initial_password
      before insert or update of initial_password on public.registration_families
      for each row execute function public._hash_initial_password_trg();
  end if;

  if exists(select 1 from pg_tables where schemaname='public' and tablename='registration_students') then
    drop trigger if exists trg_hash_initial_password on public.registration_students;
    create trigger trg_hash_initial_password
      before insert or update of initial_password on public.registration_students
      for each row execute function public._hash_initial_password_trg();
  end if;

  if exists(select 1 from pg_tables where schemaname='public' and tablename='registration_teachers') then
    drop trigger if exists trg_hash_initial_password on public.registration_teachers;
    create trigger trg_hash_initial_password
      before insert or update of initial_password on public.registration_teachers
      for each row execute function public._hash_initial_password_trg();
  end if;
end $$;

notify pgrst, 'reload schema';

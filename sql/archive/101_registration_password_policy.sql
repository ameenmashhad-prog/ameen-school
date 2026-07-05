-- =============================================================
-- مدارس أمين الرضا (ع) — سياسة كلمات المرور المؤقتة للتسجيلات
-- يمنع مستقبلاً كلمات المرور الضعيفة المبنية من تاريخ الميلاد.
-- لا يغيّر البيانات القديمة؛ القيود NOT VALID لكنها تُطبّق على الإدخالات الجديدة.
-- =============================================================

create extension if not exists pgcrypto;

do $$
begin
  if to_regclass('public.registration_families') is not null then
    alter table public.registration_families
      add constraint registration_families_initial_password_strength
      check (initial_password is null or (length(initial_password) >= 10 and initial_password !~ '^[0-9]{6,10}$')) not valid;
  end if;
exception when duplicate_object then null;
end $$;

do $$
begin
  if to_regclass('public.registration_students') is not null then
    alter table public.registration_students
      add constraint registration_students_initial_password_strength
      check (initial_password is null or (length(initial_password) >= 10 and initial_password !~ '^[0-9]{6,10}$')) not valid;
  end if;
exception when duplicate_object then null;
end $$;

do $$
begin
  if to_regclass('public.registration_teachers') is not null then
    alter table public.registration_teachers
      add constraint registration_teachers_initial_password_strength
      check (initial_password is null or (length(initial_password) >= 10 and initial_password !~ '^[0-9]{6,10}$')) not valid;
  end if;
exception when duplicate_object then null;
end $$;

create or replace function public.registration_password_policy_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'checked_at', now(),
    'policy', 'temporary passwords must be random, length >= 10, and not digits-only date values',
    'weak_existing_preview', jsonb_build_object(
      'families', case when to_regclass('public.registration_families') is null then 0 else (select count(*) from public.registration_families where initial_password ~ '^[0-9]{6,10}$') end,
      'students', case when to_regclass('public.registration_students') is null then 0 else (select count(*) from public.registration_students where initial_password ~ '^[0-9]{6,10}$') end,
      'teachers', case when to_regclass('public.registration_teachers') is null then 0 else (select count(*) from public.registration_teachers where initial_password ~ '^[0-9]{6,10}$') end
    ),
    'constraints', (
      select coalesce(jsonb_agg(jsonb_build_object('table', conrelid::regclass::text, 'constraint', conname, 'validated', convalidated) order by conname), '[]'::jsonb)
      from pg_constraint
      where conname in (
        'registration_families_initial_password_strength',
        'registration_students_initial_password_strength',
        'registration_teachers_initial_password_strength'
      )
    )
  );
end;
$$;

grant execute on function public.registration_password_policy_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.registration_password_policy_health_check() as registration_password_policy;

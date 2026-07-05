-- =============================================================
-- مدارس أمين الرضا (ع) — تنظيف كلمات المرور الضعيفة القديمة في التسجيلات
-- يعالج نتائج weak_existing_preview من SQL 101.
-- آمن ويمكن تشغيله أكثر من مرة.
-- ملاحظة: هذا ينظف جدول التسجيلات فقط. إذا تم إنشاء حساب Auth سابقاً بكلمة ضعيفة،
-- يجب إجبار المستخدم على إعادة تعيين كلمة المرور من لوحة Auth/النظام.
-- =============================================================

create extension if not exists pgcrypto;

create or replace function public._registration_random_temp_password()
returns text
language sql
security definer
set search_path = public
volatile
as $$
  -- بديل متوافق لا يعتمد على gen_random_bytes لأن بعض بيئات Supabase لا تفعّله.
  -- كلمة مؤقتة بطول 16+ وتحتوي حروفاً ورمزاً ورقماً، وليست مبنية على تاريخ الميلاد.
  select upper(substr(md5(clock_timestamp()::text || random()::text || coalesce(auth.uid()::text,'')), 1, 6))
      || lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6))
      || '!A7';
$$;

revoke all on function public._registration_random_temp_password() from public;

-- -------------------------------------------------------------
-- 1) أعمدة تتبع اختيارية
-- -------------------------------------------------------------
do $$
begin
  if to_regclass('public.registration_families') is not null then
    alter table public.registration_families add column if not exists password_policy_status text;
    alter table public.registration_families add column if not exists password_rotated_at timestamptz;
  end if;
  if to_regclass('public.registration_students') is not null then
    alter table public.registration_students add column if not exists password_policy_status text;
    alter table public.registration_students add column if not exists password_rotated_at timestamptz;
  end if;
  if to_regclass('public.registration_teachers') is not null then
    alter table public.registration_teachers add column if not exists password_policy_status text;
    alter table public.registration_teachers add column if not exists password_rotated_at timestamptz;
  end if;
end $$;

-- -------------------------------------------------------------
-- 2) تدوير القيم الرقمية الضعيفة القديمة
-- -------------------------------------------------------------
do $$
begin
  if to_regclass('public.registration_families') is not null then
    update public.registration_families
    set initial_password = public._registration_random_temp_password(),
        password_policy_status = 'rotated_random_temp_requires_delivery_or_reset',
        password_rotated_at = now()
    where initial_password ~ '^[0-9]{6,10}$';
  end if;

  if to_regclass('public.registration_students') is not null then
    update public.registration_students
    set initial_password = public._registration_random_temp_password(),
        password_policy_status = 'rotated_random_temp_requires_delivery_or_reset',
        password_rotated_at = now()
    where initial_password ~ '^[0-9]{6,10}$';
  end if;

  if to_regclass('public.registration_teachers') is not null then
    update public.registration_teachers
    set initial_password = public._registration_random_temp_password(),
        password_policy_status = 'rotated_random_temp_requires_delivery_or_reset',
        password_rotated_at = now()
    where initial_password ~ '^[0-9]{6,10}$';
  end if;
end $$;

-- -------------------------------------------------------------
-- 3) تثبيت القيود والتحقق منها بعد التنظيف
-- -------------------------------------------------------------
do $$
begin
  if to_regclass('public.registration_families') is not null then
    begin
      alter table public.registration_families validate constraint registration_families_initial_password_strength;
    exception when undefined_object then
      alter table public.registration_families
        add constraint registration_families_initial_password_strength
        check (initial_password is null or (length(initial_password) >= 10 and initial_password !~ '^[0-9]{6,10}$')) not valid;
      alter table public.registration_families validate constraint registration_families_initial_password_strength;
    end;
  end if;

  if to_regclass('public.registration_students') is not null then
    begin
      alter table public.registration_students validate constraint registration_students_initial_password_strength;
    exception when undefined_object then
      alter table public.registration_students
        add constraint registration_students_initial_password_strength
        check (initial_password is null or (length(initial_password) >= 10 and initial_password !~ '^[0-9]{6,10}$')) not valid;
      alter table public.registration_students validate constraint registration_students_initial_password_strength;
    end;
  end if;

  if to_regclass('public.registration_teachers') is not null then
    begin
      alter table public.registration_teachers validate constraint registration_teachers_initial_password_strength;
    exception when undefined_object then
      alter table public.registration_teachers
        add constraint registration_teachers_initial_password_strength
        check (initial_password is null or (length(initial_password) >= 10 and initial_password !~ '^[0-9]{6,10}$')) not valid;
      alter table public.registration_teachers validate constraint registration_teachers_initial_password_strength;
    end;
  end if;
end $$;

-- -------------------------------------------------------------
-- 4) Health Check
-- -------------------------------------------------------------
create or replace function public.registration_weak_password_cleanup_health_check()
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
    'weak_remaining', jsonb_build_object(
      'families', case when to_regclass('public.registration_families') is null then 0 else (select count(*) from public.registration_families where initial_password ~ '^[0-9]{6,10}$') end,
      'students', case when to_regclass('public.registration_students') is null then 0 else (select count(*) from public.registration_students where initial_password ~ '^[0-9]{6,10}$') end,
      'teachers', case when to_regclass('public.registration_teachers') is null then 0 else (select count(*) from public.registration_teachers where initial_password ~ '^[0-9]{6,10}$') end
    ),
    'rotated_rows', jsonb_build_object(
      'families', case when to_regclass('public.registration_families') is null then 0 else (select count(*) from public.registration_families where password_policy_status='rotated_random_temp_requires_delivery_or_reset') end,
      'students', case when to_regclass('public.registration_students') is null then 0 else (select count(*) from public.registration_students where password_policy_status='rotated_random_temp_requires_delivery_or_reset') end,
      'teachers', case when to_regclass('public.registration_teachers') is null then 0 else (select count(*) from public.registration_teachers where password_policy_status='rotated_random_temp_requires_delivery_or_reset') end
    ),
    'constraints', (
      select coalesce(jsonb_agg(jsonb_build_object('table', conrelid::regclass::text, 'constraint', conname, 'validated', convalidated) order by conname), '[]'::jsonb)
      from pg_constraint
      where conname in (
        'registration_families_initial_password_strength',
        'registration_students_initial_password_strength',
        'registration_teachers_initial_password_strength'
      )
    ),
    'important_note', 'إذا كانت حسابات Supabase Auth قد أنشئت سابقاً بهذه كلمات المرور الضعيفة، يجب فرض إعادة تعيين كلمة المرور للمستخدمين المعنيين.'
  );
end;
$$;

grant execute on function public.registration_weak_password_cleanup_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.registration_weak_password_cleanup_health_check() as registration_weak_password_cleanup;

-- =============================================================
-- مدارس أمين الرضا (ع) — استعادة الفصول الدراسية وربط الجدول بالتقويم
-- 2026/2027
-- لا يحذف أي بيانات.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) استعادة الفصول الدراسية إذا حُذفت
-- يعمل بمرونة حسب الأعمدة الموجودة في academic_periods.
-- -------------------------------------------------------------
do $$
declare
  v_table_exists boolean;
  v_name text;
  v_start date;
  v_end date;
  v_is_current boolean;
  v_cols text;
  v_vals text;
begin
  select to_regclass('public.academic_periods') is not null into v_table_exists;
  if not v_table_exists then
    raise notice 'جدول academic_periods غير موجود، سيتم تخطي استعادة الفصول.';
    return;
  end if;

  for v_name, v_start, v_end, v_is_current in
    values
      ('الفصل الدراسي الأول 2026/2027', date '2026-09-01', date '2027-01-31', true),
      ('الفصل الدراسي الثاني 2026/2027', date '2027-02-01', date '2027-05-31', false)
  loop
    if exists(select 1 from public.academic_periods where name = v_name) then
      continue;
    end if;

    v_cols := 'name';
    v_vals := quote_literal(v_name);

    if exists(select 1 from information_schema.columns where table_schema='public' and table_name='academic_periods' and column_name='academic_year') then
      v_cols := v_cols || ', academic_year';
      v_vals := v_vals || ', ' || quote_literal('2026-2027');
    end if;

    if exists(select 1 from information_schema.columns where table_schema='public' and table_name='academic_periods' and column_name='start_date') then
      v_cols := v_cols || ', start_date';
      v_vals := v_vals || ', ' || quote_literal(v_start);
    end if;

    if exists(select 1 from information_schema.columns where table_schema='public' and table_name='academic_periods' and column_name='end_date') then
      v_cols := v_cols || ', end_date';
      v_vals := v_vals || ', ' || quote_literal(v_end);
    end if;

    if exists(select 1 from information_schema.columns where table_schema='public' and table_name='academic_periods' and column_name='is_current') then
      v_cols := v_cols || ', is_current';
      v_vals := v_vals || ', ' || case when v_is_current then 'true' else 'false' end;
    end if;

    execute format('insert into public.academic_periods (%s) values (%s)', v_cols, v_vals);
  end loop;
end $$;

-- -------------------------------------------------------------
-- 2) إعدادات التقويم وأوقات الدوام
-- -------------------------------------------------------------
create table if not exists public.school_calendar_settings (
  id text primary key default 'main',
  academic_year text not null default '2026-2027',
  academic_year_start_date date not null default date '2026-09-01',
  schedule_time_settings jsonb not null default '{
    "primary": {"start": "12:45", "periods": 5, "duration": 45, "break": 10},
    "secondary": {"start": "13:00", "periods": 3, "duration": 75, "break": 10}
  }'::jsonb,
  weekend_days int[] not null default array[5,6],
  updated_by uuid null references public.users(id),
  updated_at timestamptz not null default now()
);

insert into public.school_calendar_settings (id, academic_year, academic_year_start_date)
values ('main', '2026-2027', date '2026-09-01')
on conflict (id) do nothing;

-- -------------------------------------------------------------
-- 3) العطل الرسمية/المدرسية
-- يمكن إدخالها من واجهة إدارة الجدول.
-- -------------------------------------------------------------
create table if not exists public.school_holidays (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  holiday_date date not null,
  holiday_type text not null default 'official' check (holiday_type in ('official','school','exam','custom')),
  is_recurring boolean not null default false,
  calendar_system text not null default 'gregorian' check (calendar_system in ('gregorian','hijri','persian')),
  source text not null default 'manual',
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_school_holidays_date on public.school_holidays(holiday_date);
create index if not exists idx_school_holidays_type on public.school_holidays(holiday_type);

-- -------------------------------------------------------------
-- 4) Views تساعد في ربط الجدول بالتقويم لاحقاً
-- -------------------------------------------------------------
create or replace view public.v_school_holidays_current_year
with (security_invoker=true) as
select *
from public.school_holidays
where holiday_date between date '2026-09-01' and date '2027-05-31'
   or is_recurring = true
order by holiday_date;

grant select on public.school_calendar_settings to authenticated;
grant select, insert, update on public.school_calendar_settings to authenticated;
grant select, insert, update, delete on public.school_holidays to authenticated;
grant select on public.v_school_holidays_current_year to authenticated;

-- -------------------------------------------------------------
-- 5) RLS مبسط لإعدادات الجدول: الإدارة والمسؤول العلمي فقط للتعديل.
-- -------------------------------------------------------------
alter table public.school_calendar_settings enable row level security;
alter table public.school_holidays enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='school_calendar_settings' and policyname='school_calendar_settings_read') then
    create policy school_calendar_settings_read on public.school_calendar_settings for select to authenticated using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='school_calendar_settings' and policyname='school_calendar_settings_admin_write') then
    create policy school_calendar_settings_admin_write on public.school_calendar_settings for all to authenticated
    using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)))
    with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='school_holidays' and policyname='school_holidays_read') then
    create policy school_holidays_read on public.school_holidays for select to authenticated using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='school_holidays' and policyname='school_holidays_admin_write') then
    create policy school_holidays_admin_write on public.school_holidays for all to authenticated
    using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)))
    with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)));
  end if;
end $$;

-- النتيجة
select name from public.academic_periods where name like '%2026/2027%' order by name;

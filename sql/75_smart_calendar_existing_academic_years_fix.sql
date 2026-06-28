-- =============================================================
-- مدارس أمين الرضا (ع) — Hotfix التقويم الذكي للجدول academic_years الموجود مسبقاً
-- يحل: column "school_id" of relation "academic_years" does not exist
-- السبب: جدول academic_years كان موجوداً ببنية قديمة، و CREATE TABLE IF NOT EXISTS لا يضيف الأعمدة.
-- شغّل هذا الملف ثم أعد تشغيل SQL 74.
-- =============================================================

create extension if not exists pgcrypto;

-- تأكيد الدول والفروع لأن academic_years يشير إليها.
create table if not exists public.countries (
  id uuid primary key default gen_random_uuid(),
  country_code text not null unique,
  name_ar text not null,
  name_en text,
  name_local text,
  default_timezone text not null default 'UTC',
  default_language text not null default 'ar',
  direction text not null default 'rtl',
  primary_calendar text not null default 'gregorian',
  weekend_days int[] not null default array[5,6],
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.countries(country_code,name_ar,name_en,name_local,default_timezone,default_language,direction,primary_calendar,weekend_days)
values
('IR','إيران','Iran','ایران','Asia/Tehran','fa','rtl','solar',array[5]),
('IQ','العراق','Iraq','العراق','Asia/Baghdad','ar','rtl','gregorian',array[5,6]),
('SA','السعودية','Saudi Arabia','السعودية','Asia/Riyadh','ar','rtl','lunar',array[5,6]),
('AE','الإمارات','United Arab Emirates','الإمارات','Asia/Dubai','ar','rtl','gregorian',array[6,0]),
('US','الولايات المتحدة','United States','United States','America/New_York','en','ltr','gregorian',array[6,0])
on conflict (country_code) do update
set name_ar=excluded.name_ar,
    name_en=excluded.name_en,
    name_local=excluded.name_local,
    default_timezone=excluded.default_timezone,
    default_language=excluded.default_language,
    direction=excluded.direction,
    primary_calendar=excluded.primary_calendar,
    weekend_days=excluded.weekend_days,
    is_active=true,
    updated_at=now();

create table if not exists public.school_branches (
  id uuid primary key default gen_random_uuid(),
  school_id text not null default 'main',
  branch_name text not null,
  country_code text not null references public.countries(country_code),
  timezone text not null default 'Asia/Tehran',
  weekend_days int[] not null default array[5],
  is_main boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(school_id, branch_name)
);

insert into public.school_branches(school_id,branch_name,country_code,timezone,weekend_days,is_main)
values('main','الفرع الرئيسي','IR','Asia/Tehran',array[5],true)
on conflict (school_id,branch_name) do nothing;

-- أنشئ الجدول إن لم يكن موجوداً، لكن الأهم هو ALTER للأعمدة إذا كان موجوداً مسبقاً.
create table if not exists public.academic_years (
  id uuid primary key default gen_random_uuid()
);

alter table public.academic_years add column if not exists school_id text default 'main';
alter table public.academic_years add column if not exists branch_id uuid null references public.school_branches(id) on delete set null;
alter table public.academic_years add column if not exists country_code text default 'IR';
alter table public.academic_years add column if not exists name text;
alter table public.academic_years add column if not exists start_date_gregorian date;
alter table public.academic_years add column if not exists end_date_gregorian date;
alter table public.academic_years add column if not exists is_active boolean not null default false;
alter table public.academic_years add column if not exists created_at timestamptz not null default now();
alter table public.academic_years add column if not exists updated_at timestamptz not null default now();

-- تعبئة الأعمدة الفارغة للبيانات القديمة بدون افتراض أسماء أعمدة قد لا توجد.
update public.academic_years
set school_id = coalesce(school_id, 'main'),
    country_code = coalesce(country_code, 'IR'),
    name = coalesce(nullif(name,''), '2026-2027'),
    start_date_gregorian = coalesce(start_date_gregorian, date '2026-09-01'),
    end_date_gregorian = coalesce(end_date_gregorian, date '2027-05-31'),
    updated_at = now()
where school_id is null
   or country_code is null
   or name is null
   or start_date_gregorian is null
   or end_date_gregorian is null;

-- اجعل الأعمدة الأساسية not null بعد التعبئة.
do $$ begin
  begin alter table public.academic_years alter column school_id set not null; exception when others then null; end;
  begin alter table public.academic_years alter column country_code set not null; exception when others then null; end;
  begin alter table public.academic_years alter column name set not null; exception when others then null; end;
  begin alter table public.academic_years alter column start_date_gregorian set not null; exception when others then null; end;
  begin alter table public.academic_years alter column end_date_gregorian set not null; exception when others then null; end;
end $$;

-- فهرس فريد آمن بدلاً من constraint قد يفشل إذا كان موجوداً باسم آخر.
create unique index if not exists uq_academic_years_school_branch_name
on public.academic_years(school_id, coalesce(branch_id,'00000000-0000-0000-0000-000000000000'::uuid), name);

-- أدخل السنة الأساسية إذا غير موجودة.
insert into public.academic_years(school_id, branch_id, country_code, name, start_date_gregorian, end_date_gregorian, is_active)
select 'main', null, 'IR', '2026-2027', date '2026-09-01', date '2027-05-31', true
where not exists(select 1 from public.academic_years where name='2026-2027');

grant select, insert, update on public.countries to authenticated;
grant select, insert, update on public.school_branches to authenticated;
grant select, insert, update on public.academic_years to authenticated;

notify pgrst, 'reload schema';

select 'smart_calendar_academic_years_existing_table_fixed' as status;

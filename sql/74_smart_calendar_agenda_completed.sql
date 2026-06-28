-- =============================================================
-- مدارس أمين الرضا (ع) — التقويم المدرسي الذكي والأجندة والإنجازات
-- Offline-first، بدون APIs خارجية، تخزين داخلي Gregorian، عرض ثلاثي Calendar.
-- آمن: لا يحذف أي جدول أو بيانات، ويضيف/يوسع فقط.
-- =============================================================

create extension if not exists pgcrypto;


create or replace function public.current_user_is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (u.role = 'admin' or coalesce(u.is_super_admin,false)=true)
  );
$$;

grant execute on function public.current_user_is_admin() to authenticated;

-- =============================================================
-- 0) Date Converter Service داخل PostgreSQL
-- ملاحظة: التاريخ الهجري القمري هنا حسابي وقد يختلف عن التاريخ الرسمي يوماً واحداً حسب الرؤية أو قرار الدولة.
-- =============================================================

create or replace function public._cal_div(a numeric, b numeric)
returns int language sql immutable as $$ select floor(a / b)::int; $$;

do $$ begin
  create or replace function public.calendar_is_gregorian_leap(y int)
  returns boolean language sql immutable as $f$
    select (y % 4 = 0) and ((y % 100 <> 0) or (y % 400 = 0));
  $f$;
exception when others then null; end $$;

grant execute on function public.calendar_is_gregorian_leap(int) to authenticated;

create or replace function public.calendar_gregorian_to_solar(p_date date)
returns jsonb
language plpgsql
immutable
as $$
declare
  gy int := extract(year from p_date)::int - 1600;
  gm int := extract(month from p_date)::int - 1;
  gd int := extract(day from p_date)::int - 1;
  gdm int[] := array[31,28,31,30,31,30,31,31,30,31,30,31];
  jdm int[] := array[31,31,31,31,31,31,30,30,30,30,30,29];
  g_day_no int;
  j_day_no int;
  j_np int;
  jy int;
  jm int := 1;
  jd int;
  i int;
begin
  g_day_no := 365*gy + floor((gy+3)/4)::int - floor((gy+99)/100)::int + floor((gy+399)/400)::int;
  for i in 0..gm-1 loop
    g_day_no := g_day_no + gdm[i+1];
  end loop;
  if gm > 1 and public.calendar_is_gregorian_leap(gy+1600) then
    g_day_no := g_day_no + 1;
  end if;
  g_day_no := g_day_no + gd;

  j_day_no := g_day_no - 79;
  j_np := floor(j_day_no / 12053)::int;
  j_day_no := j_day_no % 12053;
  jy := 979 + 33*j_np + 4*floor(j_day_no/1461)::int;
  j_day_no := j_day_no % 1461;
  if j_day_no >= 366 then
    jy := jy + floor((j_day_no - 1)/365)::int;
    j_day_no := (j_day_no - 1) % 365;
  end if;

  for i in 1..11 loop
    if j_day_no >= jdm[i] then
      j_day_no := j_day_no - jdm[i];
      jm := jm + 1;
    else
      exit;
    end if;
  end loop;
  jd := j_day_no + 1;

  return jsonb_build_object('year',jy,'month',jm,'day',jd,'text',jy||'/'||lpad(jm::text,2,'0')||'/'||lpad(jd::text,2,'0'));
end;
$$;

grant execute on function public.calendar_gregorian_to_solar(date) to authenticated;

create or replace function public.calendar_solar_to_gregorian(jy int, jm int, jd int)
returns date
language plpgsql
immutable
as $$
declare
  j_y int := jy + 1595;
  days int;
  gy int;
  gd int;
  sal_a int[];
  gm int := 1;
  i int;
begin
  days := -355668 + (365*j_y) + floor(j_y/33)::int*8 + floor(((j_y % 33)+3)/4)::int + jd + case when jm < 7 then (jm-1)*31 else ((jm-7)*30)+186 end;
  gy := 400 * floor(days/146097)::int;
  days := days % 146097;
  if days > 36524 then
    gy := gy + 100 * floor((days-1)/36524)::int;
    days := (days-1) % 36524;
    if days >= 365 then days := days + 1; end if;
  end if;
  gy := gy + 4 * floor(days/1461)::int;
  days := days % 1461;
  if days > 365 then
    gy := gy + floor((days-1)/365)::int;
    days := (days-1) % 365;
  end if;
  gd := days + 1;
  sal_a := array[31, case when public.calendar_is_gregorian_leap(gy) then 29 else 28 end, 31,30,31,30,31,31,30,31,30,31];
  for i in 1..12 loop
    if gd > sal_a[i] then
      gd := gd - sal_a[i];
      gm := gm + 1;
    else
      exit;
    end if;
  end loop;
  return make_date(gy, gm, gd);
end;
$$;

grant execute on function public.calendar_solar_to_gregorian(int,int,int) to authenticated;

create or replace function public.calendar_gregorian_to_jdn(p_date date)
returns int
language plpgsql
immutable
as $$
declare
  y int := extract(year from p_date)::int;
  m int := extract(month from p_date)::int;
  d int := extract(day from p_date)::int;
  a int;
  yy int;
  mm int;
begin
  a := floor((14-m)/12)::int;
  yy := y + 4800 - a;
  mm := m + 12*a - 3;
  return d + floor((153*mm+2)/5)::int + 365*yy + floor(yy/4)::int - floor(yy/100)::int + floor(yy/400)::int - 32045;
end;
$$;

grant execute on function public.calendar_gregorian_to_jdn(date) to authenticated;

create or replace function public.calendar_jdn_to_gregorian(jdn int)
returns date
language plpgsql
immutable
as $$
declare
  a int;
  b int;
  c int;
  d int;
  e int;
  m int;
  day int;
  month int;
  year int;
begin
  a := jdn + 32044;
  b := floor((4*a+3)/146097)::int;
  c := a - floor((146097*b)/4)::int;
  d := floor((4*c+3)/1461)::int;
  e := c - floor((1461*d)/4)::int;
  m := floor((5*e+2)/153)::int;
  day := e - floor((153*m+2)/5)::int + 1;
  month := m + 3 - 12*floor(m/10)::int;
  year := 100*b + d - 4800 + floor(m/10)::int;
  return make_date(year, month, day);
end;
$$;

grant execute on function public.calendar_jdn_to_gregorian(int) to authenticated;

create or replace function public.calendar_lunar_to_gregorian_approx(hy int, hm int, hd int)
returns date
language plpgsql
immutable
as $$
declare
  jdn int;
begin
  -- التقويم الهجري القمري هنا حسابي وقد يختلف عن الرسمي يوماً واحداً حسب الرؤية أو قرار الدولة.
  jdn := hd + ceil(29.5*(hm-1))::int + (hy-1)*354 + floor((3+11*hy)/30)::int + 1948439 - 1;
  return public.calendar_jdn_to_gregorian(jdn);
end;
$$;

grant execute on function public.calendar_lunar_to_gregorian_approx(int,int,int) to authenticated;

create or replace function public.calendar_gregorian_to_lunar(p_date date)
returns jsonb
language plpgsql
immutable
as $$
declare
  jd int := public.calendar_gregorian_to_jdn(p_date);
  l int;
  n int;
  j int;
  m int;
  d int;
  y int;
begin
  -- التقويم الهجري القمري هنا حسابي وقد يختلف عن الرسمي يوماً واحداً حسب الرؤية أو قرار الدولة.
  l := jd - 1948440 + 10632;
  n := floor((l-1)/10631)::int;
  l := l - 10631*n + 354;
  j := floor((10985-l)/5316)::int * floor((50*l)/17719)::int + floor(l/5670)::int * floor((43*l)/15238)::int;
  l := l - floor((30-j)/15)::int * floor((17719*j)/50)::int - floor(j/16)::int * floor((15238*j)/43)::int + 29;
  m := floor((24*l)/709)::int;
  d := l - floor((709*m)/24)::int;
  y := 30*n + j - 30;
  return jsonb_build_object('year',y,'month',m,'day',d,'text',y||'/'||lpad(m::text,2,'0')||'/'||lpad(d::text,2,'0'), 'note','حسابي وقد يختلف يوماً عن الرسمي');
end;
$$;

grant execute on function public.calendar_gregorian_to_lunar(date) to authenticated;

create or replace function public.calendar_format_triple(p_date date)
returns jsonb
language plpgsql
immutable
as $$
declare
  sol jsonb;
  lun jsonb;
  g text;
begin
  sol := public.calendar_gregorian_to_solar(p_date);
  lun := public.calendar_gregorian_to_lunar(p_date);
  g := to_char(p_date,'YYYY-MM-DD');
  return jsonb_build_object(
    'gregorian', g,
    'solar', sol->>'text',
    'lunar', lun->>'text',
    'display', (sol->>'text') || ' - ' || replace(g,'-','/') || ' - ' || (lun->>'text'),
    'lunar_note', 'التاريخ الهجري القمري هنا حسابي وقد يختلف عن التاريخ الرسمي يوماً واحداً حسب الرؤية أو قرار الدولة.'
  );
end;
$$;

grant execute on function public.calendar_format_triple(date) to authenticated;

-- =============================================================
-- 1) الدول والفروع والإعدادات والسنوات
-- =============================================================
create table if not exists public.countries (
  id uuid primary key default gen_random_uuid(),
  country_code text not null unique,
  name_ar text not null,
  name_en text,
  name_local text,
  default_timezone text not null default 'UTC',
  default_language text not null default 'ar',
  direction text not null default 'rtl',
  primary_calendar text not null default 'gregorian' check (primary_calendar in ('gregorian','solar','lunar')),
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
set name_ar=excluded.name_ar, name_en=excluded.name_en, name_local=excluded.name_local, default_timezone=excluded.default_timezone, default_language=excluded.default_language, direction=excluded.direction, primary_calendar=excluded.primary_calendar, weekend_days=excluded.weekend_days, is_active=true, updated_at=now();

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

-- جدول school_calendar_settings موجود سابقاً بمفتاح id text، نوسعه فقط.
alter table public.school_calendar_settings add column if not exists school_id text default 'main';
alter table public.school_calendar_settings add column if not exists branch_id uuid null references public.school_branches(id) on delete set null;
alter table public.school_calendar_settings add column if not exists country_code text default 'IR' references public.countries(country_code);
alter table public.school_calendar_settings add column if not exists timezone text default 'Asia/Tehran';
alter table public.school_calendar_settings add column if not exists language text default 'ar';
alter table public.school_calendar_settings add column if not exists direction text default 'rtl';
alter table public.school_calendar_settings add column if not exists primary_calendar text default 'solar';
alter table public.school_calendar_settings add column if not exists secondary_calendar text default 'gregorian';
alter table public.school_calendar_settings add column if not exists third_calendar text default 'lunar';
alter table public.school_calendar_settings add column if not exists week_start int default 6;
alter table public.school_calendar_settings add column if not exists enable_lunar_review boolean not null default true;
alter table public.school_calendar_settings add column if not exists enable_holiday_generation boolean not null default true;

create table if not exists public.academic_years (
  id uuid primary key default gen_random_uuid(),
  school_id text not null default 'main',
  branch_id uuid null references public.school_branches(id) on delete set null,
  country_code text not null default 'IR' references public.countries(country_code),
  name text not null,
  start_date_gregorian date not null,
  end_date_gregorian date not null,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(school_id, branch_id, name)
);

-- توافق مع جدول academic_years قديم: CREATE TABLE IF NOT EXISTS لا يضيف الأعمدة إذا كان الجدول موجوداً.
alter table public.academic_years add column if not exists school_id text default 'main';
alter table public.academic_years add column if not exists branch_id uuid null references public.school_branches(id) on delete set null;
alter table public.academic_years add column if not exists country_code text default 'IR';
alter table public.academic_years add column if not exists name text;
alter table public.academic_years add column if not exists start_date_gregorian date;
alter table public.academic_years add column if not exists end_date_gregorian date;
alter table public.academic_years add column if not exists is_active boolean not null default false;
alter table public.academic_years add column if not exists created_at timestamptz not null default now();
alter table public.academic_years add column if not exists updated_at timestamptz not null default now();
update public.academic_years
set school_id=coalesce(school_id,'main'),
    country_code=coalesce(country_code,'IR'),
    name=coalesce(nullif(name,''),'2026-2027'),
    start_date_gregorian=coalesce(start_date_gregorian,date '2026-09-01'),
    end_date_gregorian=coalesce(end_date_gregorian,date '2027-05-31'),
    updated_at=now()
where school_id is null or country_code is null or name is null or start_date_gregorian is null or end_date_gregorian is null;
create unique index if not exists uq_academic_years_school_branch_name
on public.academic_years(school_id, coalesce(branch_id,'00000000-0000-0000-0000-000000000000'::uuid), name);

insert into public.academic_years(school_id,branch_id,country_code,name,start_date_gregorian,end_date_gregorian,is_active)
select 'main', null, 'IR', '2026-2027', date '2026-09-01', date '2027-05-31', true
where not exists(select 1 from public.academic_years where name='2026-2027');

-- =============================================================
-- 2) قواعد العطل والعطل المعتمدة
-- =============================================================
create table if not exists public.holiday_rules (
  id uuid primary key default gen_random_uuid(),
  country_code text not null references public.countries(country_code),
  title_ar text not null,
  title_en text,
  title_local text,
  calendar_type text not null check (calendar_type in ('gregorian','solar','lunar')),
  month int not null check (month between 1 and 12),
  day int not null check (day between 1 and 31),
  duration_days int not null default 1,
  holiday_type text not null default 'official' check (holiday_type in ('official','religious','national','school','custom')),
  requires_manual_review boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(country_code, title_ar, calendar_type, month, day)
);

insert into public.holiday_rules(country_code,title_ar,title_en,title_local,calendar_type,month,day,duration_days,holiday_type,requires_manual_review)
values
('IR','النوروز','Nowruz','نوروز','solar',1,1,4,'national',false),
('IR','عاشوراء','Ashura','عاشورا','lunar',1,10,1,'religious',true),
('IQ','رأس السنة الميلادية','New Year','رأس السنة','gregorian',1,1,1,'official',false),
('IQ','عاشوراء','Ashura','عاشوراء','lunar',1,10,1,'religious',true),
('SA','اليوم الوطني','National Day','اليوم الوطني','gregorian',9,23,1,'national',false),
('AE','اليوم الوطني','National Day','اليوم الوطني','gregorian',12,2,2,'national',false),
('US','Independence Day','Independence Day','Independence Day','gregorian',7,4,1,'national',false)
on conflict (country_code, title_ar, calendar_type, month, day) do nothing;

create table if not exists public.holidays (
  id uuid primary key default gen_random_uuid(),
  school_id text not null default 'main',
  branch_id uuid null references public.school_branches(id) on delete set null,
  country_code text not null references public.countries(country_code),
  academic_year_id uuid null references public.academic_years(id) on delete cascade,
  title_ar text not null,
  title_en text,
  title_local text,
  date_gregorian date not null,
  solar_date text,
  lunar_date text,
  holiday_type text not null default 'official' check (holiday_type in ('official','religious','national','school','custom','weather')),
  source text not null default 'manual' check (source in ('rule','manual','import')),
  review_status text not null default 'approved' check (review_status in ('approved','needs_review','rejected')),
  affects_attendance boolean not null default true,
  affects_assignments boolean not null default true,
  affects_exams boolean not null default true,
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_holidays_no_duplicate on public.holidays(
  coalesce(school_id,'main'),
  coalesce(branch_id,'00000000-0000-0000-0000-000000000000'::uuid),
  country_code,
  coalesce(academic_year_id,'00000000-0000-0000-0000-000000000000'::uuid),
  date_gregorian,
  title_ar
);

create index if not exists idx_holidays_lookup on public.holidays(school_id, branch_id, country_code, academic_year_id, date_gregorian);
create index if not exists idx_holiday_rules_lookup on public.holiday_rules(country_code, calendar_type, month, day);

-- مزامنة school_holidays القديمة إلى holidays للعرض الموحد
insert into public.holidays(school_id,country_code,title_ar,date_gregorian,solar_date,lunar_date,holiday_type,source,review_status,created_by)
select 'main','IR', sh.name, sh.holiday_date,
       public.calendar_gregorian_to_solar(sh.holiday_date)->>'text',
       public.calendar_gregorian_to_lunar(sh.holiday_date)->>'text',
       case when sh.holiday_type in ('official','school','custom') then sh.holiday_type else 'official' end,
       'manual','approved',sh.created_by
from public.school_holidays sh
where not exists(select 1 from public.holidays h where h.date_gregorian=sh.holiday_date and h.title_ar=sh.name);

-- =============================================================
-- 3) Exam periods + calendar events + completed
-- =============================================================
create table if not exists public.exam_periods (
  id uuid primary key default gen_random_uuid(),
  school_id text not null default 'main',
  branch_id uuid null references public.school_branches(id) on delete set null,
  academic_year_id uuid null references public.academic_years(id) on delete cascade,
  title text not null,
  exam_period_type text not null default 'monthly' check (exam_period_type in ('monthly','mid_year','final_year','quiz','makeup','practical','oral','custom')),
  start_date_gregorian date not null,
  end_date_gregorian date not null,
  country_code text not null default 'IR',
  applies_to text not null default 'whole_school' check (applies_to in ('whole_school','branch','grade','class','group')),
  grade_id uuid null,
  class_id uuid null references public.classes(id) on delete set null,
  color text default '#2563EB',
  background_color text default '#DBEAFE',
  border_color text default '#2563EB',
  icon text default 'calendar-check',
  priority int not null default 10,
  status text not null default 'draft' check (status in ('draft','published','locked','archived')),
  affects_attendance boolean not null default false,
  restrict_assignments boolean not null default false,
  restrict_new_exams boolean not null default false,
  show_on_calendar boolean not null default true,
  show_in_agenda boolean not null default true,
  notes text,
  created_by uuid null references public.users(id),
  approved_by uuid null references public.users(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_exam_periods_lookup on public.exam_periods(school_id, branch_id, academic_year_id, exam_period_type, start_date_gregorian, end_date_gregorian, class_id, status);

alter table public.exams add column if not exists school_id text default 'main';
alter table public.exams add column if not exists branch_id uuid null references public.school_branches(id) on delete set null;
alter table public.exams add column if not exists exam_period_id uuid null references public.exam_periods(id) on delete set null;
alter table public.exams add column if not exists title text;
alter table public.exams add column if not exists exam_date_gregorian date;
alter table public.exams add column if not exists start_time time;
alter table public.exams add column if not exists end_time time;
alter table public.exams add column if not exists room text;
alter table public.exams add column if not exists notes text;
update public.exams set title = coalesce(title, exam_name), exam_date_gregorian = coalesce(exam_date_gregorian, exam_date) where title is null or exam_date_gregorian is null;
create index if not exists idx_exams_calendar on public.exams(exam_date_gregorian, exam_period_id, class_id, subject_id, teacher_id);

alter table public.homeworks add column if not exists due_date_gregorian date;
update public.homeworks set due_date_gregorian = coalesce(due_date_gregorian, due_date) where due_date_gregorian is null and due_date is not null;
create index if not exists idx_homeworks_calendar on public.homeworks(due_date_gregorian, class_id, subject_id, teacher_id);

create table if not exists public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  school_id text not null default 'main',
  branch_id uuid null references public.school_branches(id) on delete set null,
  title text not null,
  description text,
  event_type text not null check (event_type in ('assignment','exam','attendance','meeting','activity','holiday','note','exam_period')),
  date_gregorian date not null,
  start_time time,
  end_time time,
  class_id uuid null references public.classes(id) on delete set null,
  subject_id uuid null references public.subjects(id) on delete set null,
  teacher_id uuid null references public.users(id) on delete set null,
  related_table text,
  related_id uuid,
  color text,
  icon text,
  is_all_day boolean not null default true,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_calendar_events_lookup on public.calendar_events(date_gregorian, event_type, school_id, branch_id, class_id);

create table if not exists public.completed_items (
  id uuid primary key default gen_random_uuid(),
  school_id text not null default 'main',
  branch_id uuid null references public.school_branches(id) on delete set null,
  user_id uuid null references public.users(id) on delete cascade,
  role text,
  title text not null,
  description text,
  completion_type text not null default 'custom',
  source_table text,
  source_id uuid,
  related_table text,
  related_id uuid,
  related_class_id uuid,
  related_subject_id uuid,
  related_student_id uuid,
  related_teacher_id uuid,
  date_gregorian date not null default current_date,
  completed_at timestamptz not null default now(),
  priority text not null default 'normal' check (priority in ('urgent','high','normal','low')),
  status text not null default 'completed' check (status in ('completed','reverted','archived')),
  points numeric,
  icon text,
  color text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists uq_completed_no_duplicate on public.completed_items(user_id, completion_type, source_table, source_id) where source_id is not null and status='completed';
create index if not exists idx_completed_lookup on public.completed_items(school_id, branch_id, user_id, role, date_gregorian, completed_at, completion_type);

-- =============================================================
-- 4) RLS مختصر
-- =============================================================
alter table public.countries enable row level security;
alter table public.school_branches enable row level security;
alter table public.academic_years enable row level security;
alter table public.holiday_rules enable row level security;
alter table public.holidays enable row level security;
alter table public.exam_periods enable row level security;
alter table public.calendar_events enable row level security;
alter table public.completed_items enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='countries' and policyname='countries_read_all') then
    create policy countries_read_all on public.countries for select to authenticated using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='school_branches' and policyname='branches_read_all') then
    create policy branches_read_all on public.school_branches for select to authenticated using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='academic_years' and policyname='years_read_all') then
    create policy years_read_all on public.academic_years for select to authenticated using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='holiday_rules' and policyname='holiday_rules_read_all') then
    create policy holiday_rules_read_all on public.holiday_rules for select to authenticated using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='holidays' and policyname='holidays_read_all') then
    create policy holidays_read_all on public.holidays for select to authenticated using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='exam_periods' and policyname='exam_periods_read_scoped') then
    create policy exam_periods_read_scoped on public.exam_periods for select to authenticated using (status in ('published','locked') or public.current_user_is_admin() or created_by=auth.uid());
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='calendar_events' and policyname='calendar_events_read_all') then
    create policy calendar_events_read_all on public.calendar_events for select to authenticated using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='completed_items' and policyname='completed_own_or_admin') then
    create policy completed_own_or_admin on public.completed_items for all to authenticated using (public.current_user_is_admin() or user_id=auth.uid()) with check (public.current_user_is_admin() or user_id=auth.uid());
  end if;
end $$;

grant select, insert, update on public.countries to authenticated;
grant select, insert, update on public.school_branches to authenticated;
grant select, insert, update on public.academic_years to authenticated;
grant select, insert, update on public.holiday_rules to authenticated;
grant select, insert, update, delete on public.holidays to authenticated;
grant select, insert, update on public.exam_periods to authenticated;
grant select, insert, update, delete on public.calendar_events to authenticated;
grant select, insert, update on public.completed_items to authenticated;

-- =============================================================
-- 5) School Day + Holidays functions
-- =============================================================
create or replace function public.calendar_is_weekend(p_date date, p_branch_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  wd int := extract(dow from p_date)::int;
  weekends int[];
begin
  if p_branch_id is not null then
    select b.weekend_days into weekends from public.school_branches b where b.id=p_branch_id;
  end if;
  if weekends is null then
    select s.weekend_days into weekends from public.school_calendar_settings s order by updated_at desc limit 1;
  end if;
  weekends := coalesce(weekends, array[5]);
  return wd = any(weekends);
end;
$$;

grant execute on function public.calendar_is_weekend(date,uuid) to authenticated;

create or replace function public.calendar_is_holiday(p_date date, p_branch_id uuid default null)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.holidays h
    where h.date_gregorian = p_date
      and h.review_status in ('approved','needs_review')
      and (p_branch_id is null or h.branch_id is null or h.branch_id=p_branch_id)
      and h.affects_attendance = true
  )
  or exists(
    select 1 from public.school_holidays sh
    where sh.holiday_date = p_date
  );
$$;

grant execute on function public.calendar_is_holiday(date,uuid) to authenticated;

create or replace function public.calendar_is_school_day(p_date date, p_branch_id uuid default null)
returns boolean language sql stable security definer set search_path=public as $$
  select not public.calendar_is_weekend(p_date,p_branch_id) and not public.calendar_is_holiday(p_date,p_branch_id);
$$;

grant execute on function public.calendar_is_school_day(date,uuid) to authenticated;

create or replace function public.calendar_count_working_days(p_start date, p_end date, p_branch_id uuid default null)
returns int language sql stable security definer set search_path=public as $$
  select count(*)::int from generate_series(p_start,p_end,interval '1 day') d where public.calendar_is_school_day(d::date,p_branch_id);
$$;

grant execute on function public.calendar_count_working_days(date,date,uuid) to authenticated;

create or replace function public.generate_holidays_for_academic_year(p_academic_year_id uuid, p_mode text default 'merge')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  y record;
  r record;
  d date;
  cur date;
  inserted int := 0;
  skipped int := 0;
  status text;
  sol jsonb;
  lun jsonb;
  i int;
begin
  select * into y from public.academic_years where id=p_academic_year_id;
  if y.id is null then return jsonb_build_object('ok',false,'message','السنة الدراسية غير موجودة'); end if;

  if p_mode = 'replace_official' then
    delete from public.holidays where academic_year_id=p_academic_year_id and source='rule' and holiday_type in ('official','religious','national');
  end if;

  for r in select * from public.holiday_rules where country_code=y.country_code and is_active=true loop
    for i in extract(year from y.start_date_gregorian)::int..extract(year from y.end_date_gregorian)::int loop
      if r.calendar_type='gregorian' then
        d := make_date(i,r.month,r.day);
      else
        d := null;
      end if;

      -- تحسين solar/lunar: جرّب سنوات محيطة من التقويم المعني حتى يقع داخل السنة الدراسية.
      if r.calendar_type='solar' then
        d := null;
        for cur in select public.calendar_solar_to_gregorian((public.calendar_gregorian_to_solar(y.start_date_gregorian)->>'year')::int + g, r.month, r.day) from generate_series(-1,1) g loop
          if cur between y.start_date_gregorian and y.end_date_gregorian then d := cur; exit; end if;
        end loop;
      elsif r.calendar_type='lunar' then
        d := null;
        for cur in select public.calendar_lunar_to_gregorian_approx((public.calendar_gregorian_to_lunar(y.start_date_gregorian)->>'year')::int + g, r.month, r.day) from generate_series(0,2) g loop
          if cur between y.start_date_gregorian and y.end_date_gregorian then d := cur; exit; end if;
        end loop;
      end if;

      if d is not null and d between y.start_date_gregorian and y.end_date_gregorian then
        for cur in select (d + offs)::date from generate_series(0,greatest(coalesce(r.duration_days,1)-1,0)) offs loop
          sol := public.calendar_gregorian_to_solar(cur);
          lun := public.calendar_gregorian_to_lunar(cur);
          status := case when r.requires_manual_review or r.calendar_type='lunar' then 'needs_review' else 'approved' end;
          insert into public.holidays(school_id,branch_id,country_code,academic_year_id,title_ar,title_en,title_local,date_gregorian,solar_date,lunar_date,holiday_type,source,review_status,created_by)
          values(y.school_id,y.branch_id,y.country_code,y.id,r.title_ar,r.title_en,r.title_local,cur,sol->>'text',lun->>'text',r.holiday_type,'rule',status,auth.uid())
          on conflict do nothing;
          if found then inserted := inserted + 1; else skipped := skipped + 1; end if;
        end loop;
      end if;
    end loop;
  end loop;

  return jsonb_build_object('ok',true,'message','تم توليد العطل','inserted',inserted,'skipped',skipped,'academic_year_id',p_academic_year_id);
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.generate_holidays_for_academic_year(uuid,text) to authenticated;

-- =============================================================
-- 6) Calendar Aggregator + Agenda + Completed
-- =============================================================
create or replace function public.get_calendar_day_details(p_date date, p_branch_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  triple jsonb;
  holidays_json jsonb;
  homeworks_json jsonb;
  exams_json jsonb;
  periods_json jsonb;
  activities_json jsonb;
  events_json jsonb;
  warnings jsonb := '[]'::jsonb;
begin
  triple := public.calendar_format_triple(p_date);

  select coalesce(jsonb_agg(to_jsonb(h) order by h.title_ar), '[]'::jsonb) into holidays_json
  from public.holidays h
  where h.date_gregorian=p_date and h.review_status in ('approved','needs_review') and (p_branch_id is null or h.branch_id is null or h.branch_id=p_branch_id);

  select coalesce(jsonb_agg(jsonb_build_object('id',hw.id,'title',hw.title,'class_id',hw.class_id,'subject_id',hw.subject_id,'teacher_id',hw.teacher_id,'status',hw.status) order by hw.created_at), '[]'::jsonb) into homeworks_json
  from public.homeworks hw
  where coalesce(hw.due_date_gregorian,hw.due_date)=p_date;

  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'title',coalesce(e.title,e.exam_name),'class_id',e.class_id,'subject_id',e.subject_id,'teacher_id',e.teacher_id,'exam_period_id',e.exam_period_id,'start_time',e.start_time,'end_time',e.end_time,'room',e.room) order by e.start_time nulls last), '[]'::jsonb) into exams_json
  from public.exams e
  where coalesce(e.exam_date_gregorian,e.exam_date)=p_date;

  select coalesce(jsonb_agg(to_jsonb(ep) order by ep.priority desc, ep.start_date_gregorian), '[]'::jsonb) into periods_json
  from public.exam_periods ep
  where ep.show_on_calendar=true and ep.status in ('published','locked') and p_date between ep.start_date_gregorian and ep.end_date_gregorian;

  if to_regclass('public.school_activities') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'title',a.title,'location',a.location,'start_at',a.start_at,'status',a.status) order by a.start_at), '[]'::jsonb) into activities_json
    from public.school_activities a
    where a.status='published' and a.start_at::date=p_date;
  else
    activities_json := '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(to_jsonb(ev) order by ev.start_time nulls last), '[]'::jsonb) into events_json
  from public.calendar_events ev
  where ev.date_gregorian=p_date and (p_branch_id is null or ev.branch_id is null or ev.branch_id=p_branch_id);

  if public.calendar_is_holiday(p_date,p_branch_id) and jsonb_array_length(homeworks_json)>0 then
    warnings := warnings || jsonb_build_array(jsonb_build_object('type','assignment_on_holiday','message','يوجد واجب في يوم عطلة'));
  end if;
  if public.calendar_is_holiday(p_date,p_branch_id) and jsonb_array_length(exams_json)>0 then
    warnings := warnings || jsonb_build_array(jsonb_build_object('type','exam_on_holiday','message','يوجد اختبار في يوم عطلة'));
  end if;

  return jsonb_build_object(
    'date', p_date,
    'triple_date', triple,
    'is_weekend', public.calendar_is_weekend(p_date,p_branch_id),
    'is_holiday', public.calendar_is_holiday(p_date,p_branch_id),
    'is_school_day', public.calendar_is_school_day(p_date,p_branch_id),
    'holidays', holidays_json,
    'assignments', homeworks_json,
    'exams', exams_json,
    'exam_periods', periods_json,
    'activities', activities_json,
    'events', events_json,
    'warnings', warnings,
    'available_quick_actions', jsonb_build_array('assignment','exam','holiday','note')
  );
end;
$$;

grant execute on function public.get_calendar_day_details(date,uuid) to authenticated;

create or replace function public.get_calendar_month(p_year int, p_month int, p_branch_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  start_d date := make_date(p_year,p_month,1);
  end_d date := (make_date(p_year,p_month,1) + interval '1 month - 1 day')::date;
  days jsonb;
begin
  select jsonb_agg(public.get_calendar_day_details(d::date,p_branch_id) order by d)
  into days
  from generate_series(start_d,end_d,interval '1 day') d;
  return jsonb_build_object('ok',true,'year',p_year,'month',p_month,'days',coalesce(days,'[]'::jsonb));
end;
$$;

grant execute on function public.get_calendar_month(int,int,uuid) to authenticated;

create or replace function public.mark_completed(
  p_title text,
  p_completion_type text default 'custom',
  p_source_table text default null,
  p_source_id uuid default null,
  p_description text default null,
  p_priority text default 'normal'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid;
  role_text text;
begin
  select role into role_text from public.users where id=auth.uid();
  insert into public.completed_items(user_id,role,title,description,completion_type,source_table,source_id,date_gregorian,priority)
  values(auth.uid(),role_text,coalesce(nullif(trim(p_title),''),'إنجاز'),p_description,coalesce(p_completion_type,'custom'),p_source_table,p_source_id,current_date,case when p_priority in ('urgent','high','normal','low') then p_priority else 'normal' end)
  on conflict (user_id,completion_type,source_table,source_id) where source_id is not null and status='completed' do update
  set updated_at=now()
  returning id into cid;
  return jsonb_build_object('ok',true,'completed_id',cid);
end;
$$;

grant execute on function public.mark_completed(text,text,text,uuid,text,text) to authenticated;

create or replace function public.get_my_completed_items(p_range text default 'today')
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  from_d date;
  to_d date := current_date;
  items jsonb;
begin
  from_d := case p_range when 'week' then current_date-6 when 'month' then date_trunc('month',current_date)::date else current_date end;
  select coalesce(jsonb_agg(to_jsonb(c) order by c.completed_at desc), '[]'::jsonb) into items
  from public.completed_items c
  where c.user_id=auth.uid() and c.status='completed' and c.date_gregorian between from_d and to_d;
  return jsonb_build_object('ok',true,'range',p_range,'items',items,'count',jsonb_array_length(items));
end;
$$;

grant execute on function public.get_my_completed_items(text) to authenticated;

create or replace function public.revert_completed_item(p_completed_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  update public.completed_items set status='reverted', updated_at=now() where id=p_completed_id and (user_id=auth.uid() or public.current_user_is_admin());
  if not found then return jsonb_build_object('ok',false,'message','لا توجد صلاحية أو الإنجاز غير موجود'); end if;
  return jsonb_build_object('ok',true,'message','تم التراجع عن الإنجاز');
end; $$;

grant execute on function public.revert_completed_item(uuid) to authenticated;


create or replace function public.student_matches_homework(p_student_id uuid, p_homework_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1
    from public.homeworks h
    join public.students s on s.id = p_student_id
    where h.id = p_homework_id
      and (
        (h.section_id is not null and (
          s.section_id = h.section_id
          or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.section_id=h.section_id and se.enrollment_status='active')
        ))
        or
        (h.section_id is null and h.class_id is not null and (
          s.class_id = h.class_id
          or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.class_id=h.class_id and se.enrollment_status='active')
        ))
      )
  );
$$;

grant execute on function public.student_matches_homework(uuid,uuid) to authenticated;

create or replace function public.get_my_agenda(p_range text default 'today')
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  uid uuid := auth.uid();
  role_text text;
  from_d date := current_date;
  to_d date := current_date;
  agenda jsonb := '[]'::jsonb;
  st_ids uuid[];
begin
  select role into role_text from public.users where id=uid;
  if p_range='week' then to_d:=current_date+6; elsif p_range='tomorrow' then from_d:=current_date+1; to_d:=current_date+1; elsif p_range='overdue' then from_d:=current_date-365; to_d:=current_date-1; end if;
  select coalesce(array_agg(id),array[]::uuid[]) into st_ids from public.students where user_id=uid or parent_id=uid;

  -- واجبات الطالب/ولي الأمر
  if role_text in ('student','parent') then
    agenda := agenda || coalesce((
      select jsonb_agg(jsonb_build_object('id',hw.id,'source_table','homeworks','source_id',hw.id,'title',hw.title,'agenda_type','assignment','role_scope',role_text,'date_gregorian',coalesce(hw.due_date_gregorian,hw.due_date),'priority',case when coalesce(hw.due_date_gregorian,hw.due_date)<current_date then 'high' else 'normal' end,'status',case when coalesce(hw.due_date_gregorian,hw.due_date)<current_date then 'overdue' else 'pending' end,'action_label','عرض الواجب','action_url','student-homeworks.html','color','#0A6EDC','icon','assignment'))
      from public.homeworks hw
      where coalesce(hw.due_date_gregorian,hw.due_date) between from_d and to_d
        and exists(select 1 from unnest(st_ids) as sid(student_id) where public.student_matches_homework(sid.student_id,hw.id))
    ), '[]'::jsonb);
  end if;

  -- واجبات وتصحيح للمعلم
  if role_text='teacher' then
    agenda := agenda || coalesce((
      select jsonb_agg(jsonb_build_object('id',hw.id,'source_table','homeworks','source_id',hw.id,'title','واجب: '||hw.title,'agenda_type','assignment','role_scope','teacher','date_gregorian',coalesce(hw.due_date_gregorian,hw.due_date),'priority','normal','status','pending','action_label','فتح الواجبات','action_url','teacher.html','color','#0A6EDC','icon','assignment'))
      from public.homeworks hw where hw.teacher_id=uid and coalesce(hw.due_date_gregorian,hw.due_date) between from_d and to_d
    ), '[]'::jsonb);
  end if;

  -- الاختبارات
  agenda := agenda || coalesce((
    select jsonb_agg(jsonb_build_object('id',e.id,'source_table','exams','source_id',e.id,'title',coalesce(e.title,e.exam_name),'agenda_type','exam','role_scope','all','date_gregorian',coalesce(e.exam_date_gregorian,e.exam_date),'priority','high','status','pending','action_label','عرض الاختبارات','action_url','online-exams.html','color','#D32F2F','icon','exam'))
    from public.exams e
    where coalesce(e.exam_date_gregorian,e.exam_date) between from_d and to_d
      and (role_text in ('admin','academic','academic_admin','scientific','supervisor') or e.teacher_id=uid or e.class_id in (select class_id from public.students where id=any(st_ids)))
  ), '[]'::jsonb);

  -- الإشعارات
  agenda := agenda || coalesce((
    select jsonb_agg(jsonb_build_object('id',n.id,'source_table','school_notifications','source_id',n.id,'title',n.title,'description',n.body,'agenda_type','notification','role_scope','all','date_gregorian',n.created_at::date,'priority','normal','status',case when n.read_at is null then 'pending' else 'done' end,'action_label','فتح الإشعارات','action_url','notifications.html','color','#D4AF37','icon','bell'))
    from public.school_notifications n
    where n.recipient_user_id=uid and n.created_at::date between from_d and to_d and n.read_at is null
  ), '[]'::jsonb);

  return jsonb_build_object('ok',true,'range',p_range,'items',coalesce(agenda,'[]'::jsonb));
end;
$$;

grant execute on function public.get_my_agenda(text) to authenticated;

create or replace function public.get_dashboard_home()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  uid uuid := auth.uid();
  u record;
  today jsonb;
  month_payload jsonb;
  agenda jsonb;
  completed jsonb;
begin
  select id,name,email,role,is_super_admin into u from public.users where id=uid;
  today := public.get_calendar_day_details(current_date,null);
  month_payload := public.get_calendar_month(extract(year from current_date)::int, extract(month from current_date)::int, null);
  agenda := public.get_my_agenda('week');
  completed := public.get_my_completed_items('week');
  return jsonb_build_object('ok',true,'user',to_jsonb(u),'today',today,'calendar',month_payload,'agenda',agenda,'completed',completed);
end;
$$;

grant execute on function public.get_dashboard_home() to authenticated;

-- =============================================================
-- 7) Import JSON holiday package
-- =============================================================
create or replace function public.import_holiday_package(p_package jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cc text := p_package->>'country_code';
  r jsonb;
  added_country int := 0;
  added_rules int := 0;
  skipped_rules int := 0;
begin
  if cc is null then return jsonb_build_object('ok',false,'message','country_code مطلوب'); end if;
  insert into public.countries(country_code,name_ar,name_en,name_local,default_timezone,default_language,direction,primary_calendar,weekend_days)
  values(cc, coalesce(p_package->>'country_name_ar',cc), p_package->>'country_name_en', p_package->>'country_name_local', coalesce(p_package->>'timezone','UTC'), coalesce(p_package->>'default_language','ar'), coalesce(p_package->>'direction','rtl'), coalesce(p_package->>'primary_calendar','gregorian'), coalesce((select array_agg(value::int) from jsonb_array_elements_text(coalesce(p_package->'weekend_days','[]'::jsonb))), array[5,6]))
  on conflict (country_code) do nothing;
  if found then added_country:=1; end if;
  for r in select * from jsonb_array_elements(coalesce(p_package->'holiday_rules','[]'::jsonb)) loop
    insert into public.holiday_rules(country_code,title_ar,title_en,title_local,calendar_type,month,day,duration_days,holiday_type,requires_manual_review)
    values(cc,r->>'title_ar',r->>'title_en',r->>'title_local',coalesce(r->>'calendar_type','gregorian'),(r->>'month')::int,(r->>'day')::int,coalesce((r->>'duration_days')::int,1),coalesce(r->>'holiday_type','official'),coalesce((r->>'requires_manual_review')::boolean,false))
    on conflict do nothing;
    if found then added_rules:=added_rules+1; else skipped_rules:=skipped_rules+1; end if;
  end loop;
  return jsonb_build_object('ok',true,'countries_added',added_country,'rules_added',added_rules,'rules_skipped',skipped_rules);
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.import_holiday_package(jsonb) to authenticated;

-- =============================================================
-- 8) Exam Period Helpers
-- =============================================================
create or replace function public.exam_period_upsert(
  p_id uuid default null,
  p_title text default null,
  p_type text default 'monthly',
  p_start date default null,
  p_end date default null,
  p_class_id uuid default null,
  p_status text default 'draft'
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  eid uuid;
  bg text;
  br text;
  ic text;
begin
  if nullif(trim(coalesce(p_title,'')),'') is null then return jsonb_build_object('ok',false,'message','عنوان الفترة مطلوب'); end if;
  if p_start is null or p_end is null or p_end < p_start then return jsonb_build_object('ok',false,'message','تواريخ الفترة غير صحيحة'); end if;
  if p_type not in ('monthly','mid_year','final_year','quiz','makeup','practical','oral','custom') then p_type:='monthly'; end if;
  if p_status not in ('draft','published','locked','archived') then p_status:='draft'; end if;
  bg := case p_type when 'mid_year' then '#EDE9FE' when 'final_year' then '#FEE2E2' when 'quiz' then '#CFFAFE' when 'makeup' then '#FFEDD5' when 'practical' then '#DCFCE7' when 'oral' then '#FEF9C3' else '#DBEAFE' end;
  br := case p_type when 'mid_year' then '#7C3AED' when 'final_year' then '#DC2626' when 'quiz' then '#0891B2' when 'makeup' then '#EA580C' when 'practical' then '#16A34A' when 'oral' then '#CA8A04' else '#2563EB' end;
  ic := case p_type when 'mid_year' then 'milestone' when 'final_year' then 'award' when 'quiz' then 'zap' when 'makeup' then 'rotate-ccw' when 'practical' then 'flask' when 'oral' then 'mic' else 'calendar-check' end;
  if p_id is not null then
    update public.exam_periods set title=trim(p_title),exam_period_type=p_type,start_date_gregorian=p_start,end_date_gregorian=p_end,class_id=p_class_id,status=p_status,background_color=bg,border_color=br,icon=ic,updated_at=now(),published_at=case when p_status='published' then coalesce(published_at,now()) else published_at end where id=p_id returning id into eid;
  else
    insert into public.exam_periods(title,exam_period_type,start_date_gregorian,end_date_gregorian,class_id,status,background_color,border_color,icon,created_by,published_at)
    values(trim(p_title),p_type,p_start,p_end,p_class_id,p_status,bg,br,ic,auth.uid(),case when p_status='published' then now() else null end) returning id into eid;
  end if;
  return jsonb_build_object('ok',true,'exam_period_id',eid);
end; $$;

grant execute on function public.exam_period_upsert(uuid,text,text,date,date,uuid,text) to authenticated;

create or replace function public.suggest_exam_schedule(p_exam_period_id uuid)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare
  ep record;
  subjects jsonb;
  days jsonb;
begin
  select * into ep from public.exam_periods where id=p_exam_period_id;
  if ep.id is null then return jsonb_build_object('ok',false,'message','الفترة غير موجودة'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('subject_id',s.id,'subject_name',s.name) order by s.name),'[]'::jsonb) into subjects from public.subjects s limit 20;
  select coalesce(jsonb_agg(jsonb_build_object('date',d::date,'is_school_day',public.calendar_is_school_day(d::date,ep.branch_id)) order by d),'[]'::jsonb) into days from generate_series(ep.start_date_gregorian,ep.end_date_gregorian,interval '1 day') d;
  return jsonb_build_object('ok',true,'exam_period_id',ep.id,'days',days,'subjects',subjects,'note','اقتراح أولي محلي؛ لا يضع خارج الفترة ويبيّن أيام الدوام.');
end; $$;

grant execute on function public.suggest_exam_schedule(uuid) to authenticated;

-- =============================================================
-- 9) Health
-- =============================================================
create or replace function public.smart_calendar_health_check()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  return jsonb_build_object(
    'checked_at',now(),
    'countries',to_regclass('public.countries') is not null,
    'branches',to_regclass('public.school_branches') is not null,
    'academic_years',to_regclass('public.academic_years') is not null,
    'holiday_rules',to_regclass('public.holiday_rules') is not null,
    'holidays',to_regclass('public.holidays') is not null,
    'exam_periods',to_regclass('public.exam_periods') is not null,
    'calendar_events',to_regclass('public.calendar_events') is not null,
    'completed_items',to_regclass('public.completed_items') is not null,
    'month_rpc',to_regprocedure('public.get_calendar_month(int,int,uuid)') is not null,
    'day_rpc',to_regprocedure('public.get_calendar_day_details(date,uuid)') is not null,
    'agenda_rpc',to_regprocedure('public.get_my_agenda(text)') is not null,
    'completed_rpc',to_regprocedure('public.get_my_completed_items(text)') is not null,
    'dashboard_rpc',to_regprocedure('public.get_dashboard_home()') is not null,
    'triple_today', public.calendar_format_triple(current_date),
    'countries_count',(select count(*) from public.countries),
    'holiday_rules_count',(select count(*) from public.holiday_rules)
  );
end; $$;

grant execute on function public.smart_calendar_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'smart_calendar_agenda_completed_ready' as status;

-- =============================================================
-- 10) تكامل البوابة الموحدة + دوال توافق
-- =============================================================
create or replace function public.current_user_is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (u.role = 'admin' or coalesce(u.is_super_admin,false)=true)
  );
$$;

grant execute on function public.current_user_is_admin() to authenticated;

create or replace function public.student_matches_homework(p_student_id uuid, p_homework_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1
    from public.homeworks h
    join public.students s on s.id = p_student_id
    where h.id = p_homework_id
      and (
        (h.section_id is not null and (
          s.section_id = h.section_id
          or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.section_id=h.section_id and se.enrollment_status='active')
        ))
        or
        (h.section_id is null and h.class_id is not null and (
          s.class_id = h.class_id
          or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.class_id=h.class_id and se.enrollment_status='active')
        ))
      )
  );
$$;

grant execute on function public.student_matches_homework(uuid,uuid) to authenticated;

create or replace function public.portal_default_permissions(p_role text, p_is_super_admin boolean default false)
returns text[]
language plpgsql
stable
as $$
declare r text := lower(coalesce(p_role,''));
begin
  if coalesce(p_is_super_admin,false) or r = 'admin' then
    return array['admin','staff.dashboard','calendar','finance','academic','schedule','sections','grades','attendance','behavior','counseling','users','reports','analytics','announcements','registrations','system','teacher','student','parent','homework','homework.reports','homework.audit','question_bank','online_exams','exam_integrity','library','inventory','assets','hr','transport','labs','activities','documents','notifications'];
  end if;
  if r='finance' then return array['staff.dashboard','calendar','finance','reports','analytics','homework.reports','library','inventory','assets','documents','notifications']; end if;
  if r in ('academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor') then return array['staff.dashboard','calendar','academic','schedule','sections','grades','attendance','behavior','reports','analytics','announcements','registrations','question_bank','online_exams','exam_integrity','homework.reports','library','transport','labs','activities','documents','notifications']; end if;
  if r='discipline' then return array['staff.dashboard','calendar','attendance','behavior','students','reports','analytics','transport','homework.reports','notifications']; end if;
  if r in ('counselor','psychologist') then return array['staff.dashboard','calendar','counseling','behavior','students','attendance','reports','analytics','notifications']; end if;
  if r='teacher' then return array['teacher','calendar','attendance','homework','homework.reports','homework.audit','grades','question_bank','online_exams','library','transport','labs','activities','documents','notifications']; end if;
  if r='student' then return array['student','calendar','homework','online_exams','grades','attendance','behavior','library','transport','activities','documents','notifications']; end if;
  if r='parent' then return array['parent','student','calendar','homework','online_exams','grades','attendance','behavior','finance','library','transport','activities','documents','notifications']; end if;
  if r='staff' then return array['staff.dashboard','calendar','attendance','students','reports','analytics','announcements','library','inventory','assets','transport','activities','documents','notifications']; end if;
  if r='hr' then return array['staff.dashboard','calendar','hr','reports','analytics','documents','notifications']; end if;
  if r in ('inventory','procurement') then return array['staff.dashboard','calendar','inventory','reports','analytics','documents','notifications']; end if;
  if r in ('transport','transport_manager') then return array['staff.dashboard','calendar','transport','reports','analytics','notifications']; end if;
  if r='librarian' then return array['calendar','library','reports','documents','notifications']; end if;
  return array['calendar','notifications'];
end;
$$;

grant execute on function public.portal_default_permissions(text,boolean) to authenticated;

notify pgrst, 'reload schema';

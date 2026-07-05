-- =============================================================
-- مدارس أمين الرضا (ع) — إصلاح سريع للتقويم الذكي Health Check/Core Restore
-- يحل: function smart_calendar_health_check() does not exist
-- شغّل هذا الملف بعد 77، ثم افحص smart_calendar_health_check.
-- آمن: لا يحذف أي بيانات، ويضيف/يرمم الأساسيات فقط.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) دالة الإدارة الأساسية
-- -------------------------------------------------------------
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

-- -------------------------------------------------------------
-- 2) جداول التقويم الأساسية
-- -------------------------------------------------------------
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
  country_code text not null default 'IR',
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

create table if not exists public.school_calendar_settings (
  id text primary key default 'main'
);

alter table public.school_calendar_settings add column if not exists academic_year text not null default '2026-2027';
alter table public.school_calendar_settings add column if not exists academic_year_start_date date not null default date '2026-09-01';
alter table public.school_calendar_settings add column if not exists weekend_days int[] not null default array[5];
alter table public.school_calendar_settings add column if not exists school_id text default 'main';
alter table public.school_calendar_settings add column if not exists branch_id uuid null;
alter table public.school_calendar_settings add column if not exists country_code text default 'IR';
alter table public.school_calendar_settings add column if not exists timezone text default 'Asia/Tehran';
alter table public.school_calendar_settings add column if not exists language text default 'ar';
alter table public.school_calendar_settings add column if not exists direction text default 'rtl';
alter table public.school_calendar_settings add column if not exists primary_calendar text default 'solar';
alter table public.school_calendar_settings add column if not exists secondary_calendar text default 'gregorian';
alter table public.school_calendar_settings add column if not exists third_calendar text default 'lunar';
alter table public.school_calendar_settings add column if not exists week_start int default 6;
alter table public.school_calendar_settings add column if not exists enable_lunar_review boolean not null default true;
alter table public.school_calendar_settings add column if not exists enable_holiday_generation boolean not null default true;
alter table public.school_calendar_settings add column if not exists updated_by uuid null references public.users(id);
alter table public.school_calendar_settings add column if not exists updated_at timestamptz not null default now();

insert into public.school_calendar_settings(id) values('main') on conflict(id) do nothing;

create table if not exists public.academic_years (
  id uuid primary key default gen_random_uuid()
);

alter table public.academic_years add column if not exists school_id text default 'main';
alter table public.academic_years add column if not exists branch_id uuid null;
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

insert into public.academic_years(school_id,branch_id,country_code,name,start_date_gregorian,end_date_gregorian,is_active)
select 'main',null,'IR','2026-2027',date '2026-09-01',date '2027-05-31',true
where not exists(select 1 from public.academic_years where name='2026-2027');

create table if not exists public.holiday_rules (
  id uuid primary key default gen_random_uuid(),
  country_code text not null default 'IR',
  title_ar text not null,
  title_en text,
  title_local text,
  calendar_type text not null default 'gregorian',
  month int not null,
  day int not null,
  duration_days int not null default 1,
  holiday_type text not null default 'official',
  requires_manual_review boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_holiday_rules_basic
on public.holiday_rules(country_code,title_ar,calendar_type,month,day);

insert into public.holiday_rules(country_code,title_ar,title_en,title_local,calendar_type,month,day,duration_days,holiday_type,requires_manual_review)
values
('IR','النوروز','Nowruz','نوروز','solar',1,1,4,'national',false),
('IR','عاشوراء','Ashura','عاشورا','lunar',1,10,1,'religious',true),
('IQ','رأس السنة الميلادية','New Year','رأس السنة','gregorian',1,1,1,'official',false),
('SA','اليوم الوطني','National Day','اليوم الوطني','gregorian',9,23,1,'national',false),
('AE','اليوم الوطني','National Day','اليوم الوطني','gregorian',12,2,2,'national',false),
('US','Independence Day','Independence Day','Independence Day','gregorian',7,4,1,'national',false)
on conflict do nothing;

create table if not exists public.holidays (
  id uuid primary key default gen_random_uuid(),
  school_id text not null default 'main',
  branch_id uuid null,
  country_code text not null default 'IR',
  academic_year_id uuid null,
  title_ar text not null,
  title_en text,
  title_local text,
  date_gregorian date not null,
  solar_date text,
  lunar_date text,
  holiday_type text not null default 'official',
  source text not null default 'manual',
  review_status text not null default 'approved',
  affects_attendance boolean not null default true,
  affects_assignments boolean not null default true,
  affects_exams boolean not null default true,
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.exam_periods (
  id uuid primary key default gen_random_uuid(),
  school_id text not null default 'main',
  branch_id uuid null,
  academic_year_id uuid null,
  title text not null,
  exam_period_type text not null default 'monthly',
  start_date_gregorian date not null,
  end_date_gregorian date not null,
  country_code text not null default 'IR',
  applies_to text not null default 'whole_school',
  grade_id uuid null,
  class_id uuid null references public.classes(id) on delete set null,
  color text default '#2563EB',
  background_color text default '#DBEAFE',
  border_color text default '#2563EB',
  icon text default 'calendar-check',
  priority int not null default 10,
  status text not null default 'draft',
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

create table if not exists public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  school_id text not null default 'main',
  branch_id uuid null,
  title text not null,
  description text,
  event_type text not null default 'note',
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

create table if not exists public.completed_items (
  id uuid primary key default gen_random_uuid(),
  school_id text not null default 'main',
  branch_id uuid null,
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
  priority text not null default 'normal',
  status text not null default 'completed',
  points numeric,
  icon text,
  color text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- أعمدة توافق للواجبات والاختبارات
alter table public.homeworks add column if not exists due_date_gregorian date;
update public.homeworks set due_date_gregorian = coalesce(due_date_gregorian, due_date) where due_date_gregorian is null and due_date is not null;

alter table public.exams add column if not exists school_id text default 'main';
alter table public.exams add column if not exists branch_id uuid null;
alter table public.exams add column if not exists exam_period_id uuid null;
alter table public.exams add column if not exists title text;
alter table public.exams add column if not exists exam_date_gregorian date;
alter table public.exams add column if not exists start_time time;
alter table public.exams add column if not exists end_time time;
alter table public.exams add column if not exists room text;
alter table public.exams add column if not exists notes text;
update public.exams set title = coalesce(title, exam_name), exam_date_gregorian = coalesce(exam_date_gregorian, exam_date) where title is null or exam_date_gregorian is null;

-- فهارس
create index if not exists idx_holidays_lookup on public.holidays(school_id, branch_id, country_code, academic_year_id, date_gregorian);
create index if not exists idx_exam_periods_lookup on public.exam_periods(school_id, branch_id, academic_year_id, exam_period_type, start_date_gregorian, end_date_gregorian, class_id, status);
create index if not exists idx_calendar_events_lookup on public.calendar_events(date_gregorian, event_type, school_id, branch_id, class_id);
create index if not exists idx_completed_lookup on public.completed_items(school_id, branch_id, user_id, role, date_gregorian, completed_at, completion_type);
create index if not exists idx_homeworks_calendar on public.homeworks(due_date_gregorian, class_id, subject_id, teacher_id);
create index if not exists idx_exams_calendar on public.exams(exam_date_gregorian, exam_period_id, class_id, subject_id, teacher_id);

-- -------------------------------------------------------------
-- 3) دوال أساسية بسيطة تكفي لتشغيل الواجهة والفحص
-- -------------------------------------------------------------
create or replace function public.calendar_format_triple(p_date date)
returns jsonb
language plpgsql
immutable
as $$
declare
  g text := to_char(p_date,'YYYY-MM-DD');
begin
  -- نسخة fallback آمنة. إذا شغّل SQL 74 لاحقاً ستستبدل بدوال تحويل أدق.
  return jsonb_build_object(
    'gregorian', g,
    'solar', g,
    'lunar', g,
    'display', replace(g,'-','/') || ' - ' || replace(g,'-','/') || ' - ' || replace(g,'-','/'),
    'lunar_note', 'Fallback: التاريخ الهجري القمري حسابي في النسخة الكاملة وقد يختلف يوماً عن الرسمي.'
  );
end;
$$;

grant execute on function public.calendar_format_triple(date) to authenticated;

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
    select weekend_days into weekends from public.school_branches where id=p_branch_id;
  end if;
  if weekends is null then
    select weekend_days into weekends from public.school_calendar_settings order by updated_at desc limit 1;
  end if;
  weekends := coalesce(weekends,array[5]);
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
    where h.date_gregorian=p_date
      and h.review_status in ('approved','needs_review')
      and (p_branch_id is null or h.branch_id is null or h.branch_id=p_branch_id)
      and h.affects_attendance=true
  )
  or exists(
    select 1 from public.school_holidays sh
    where sh.holiday_date=p_date
  );
$$;

grant execute on function public.calendar_is_holiday(date,uuid) to authenticated;

create or replace function public.calendar_is_school_day(p_date date, p_branch_id uuid default null)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select not public.calendar_is_weekend(p_date,p_branch_id) and not public.calendar_is_holiday(p_date,p_branch_id);
$$;

grant execute on function public.calendar_is_school_day(date,uuid) to authenticated;

create or replace function public.get_calendar_day_details(p_date date, p_branch_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  holidays_json jsonb;
  homeworks_json jsonb;
  exams_json jsonb;
  periods_json jsonb;
  events_json jsonb;
  warnings jsonb := '[]'::jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(h)), '[]'::jsonb) into holidays_json from public.holidays h where h.date_gregorian=p_date and h.review_status in ('approved','needs_review');
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'class_id',class_id,'subject_id',subject_id,'teacher_id',teacher_id,'status',status)), '[]'::jsonb) into homeworks_json from public.homeworks where coalesce(due_date_gregorian,due_date)=p_date;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',coalesce(title,exam_name),'class_id',class_id,'subject_id',subject_id,'teacher_id',teacher_id,'exam_period_id',exam_period_id)), '[]'::jsonb) into exams_json from public.exams where coalesce(exam_date_gregorian,exam_date)=p_date;
  select coalesce(jsonb_agg(to_jsonb(ep)), '[]'::jsonb) into periods_json from public.exam_periods ep where ep.show_on_calendar=true and ep.status in ('published','locked') and p_date between ep.start_date_gregorian and ep.end_date_gregorian;
  select coalesce(jsonb_agg(to_jsonb(ev)), '[]'::jsonb) into events_json from public.calendar_events ev where ev.date_gregorian=p_date;

  if public.calendar_is_holiday(p_date,p_branch_id) and jsonb_array_length(homeworks_json)>0 then warnings := warnings || jsonb_build_array(jsonb_build_object('type','assignment_on_holiday','message','يوجد واجب في يوم عطلة')); end if;
  if public.calendar_is_holiday(p_date,p_branch_id) and jsonb_array_length(exams_json)>0 then warnings := warnings || jsonb_build_array(jsonb_build_object('type','exam_on_holiday','message','يوجد اختبار في يوم عطلة')); end if;

  return jsonb_build_object('date',p_date,'triple_date',public.calendar_format_triple(p_date),'is_weekend',public.calendar_is_weekend(p_date,p_branch_id),'is_holiday',public.calendar_is_holiday(p_date,p_branch_id),'is_school_day',public.calendar_is_school_day(p_date,p_branch_id),'holidays',holidays_json,'assignments',homeworks_json,'exams',exams_json,'exam_periods',periods_json,'activities','[]'::jsonb,'events',events_json,'warnings',warnings,'available_quick_actions',jsonb_build_array('assignment','exam','holiday','note'));
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

create or replace function public.mark_completed(p_title text, p_completion_type text default 'custom', p_source_table text default null, p_source_id uuid default null, p_description text default null, p_priority text default 'normal')
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
  on conflict do nothing
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
begin
  select role into role_text from public.users where id=uid;
  if p_range='week' then to_d:=current_date+6; elsif p_range='tomorrow' then from_d:=current_date+1; to_d:=current_date+1; elsif p_range='overdue' then from_d:=current_date-365; to_d:=current_date-1; end if;

  agenda := agenda || coalesce((
    select jsonb_agg(jsonb_build_object('id',n.id,'source_table','school_notifications','source_id',n.id,'title',n.title,'description',n.body,'agenda_type','notification','role_scope','all','date_gregorian',n.created_at::date,'priority','normal','status',case when n.read_at is null then 'pending' else 'done' end,'action_label','فتح الإشعارات','action_url','notifications.html','color','#D4AF37','icon','bell'))
    from public.school_notifications n
    where n.recipient_user_id=uid and n.created_at::date between from_d and to_d and n.read_at is null
  ), '[]'::jsonb);

  agenda := agenda || coalesce((
    select jsonb_agg(jsonb_build_object('id',hw.id,'source_table','homeworks','source_id',hw.id,'title',hw.title,'agenda_type','assignment','role_scope','teacher','date_gregorian',coalesce(hw.due_date_gregorian,hw.due_date),'priority','normal','status','pending','action_label','فتح الواجبات','action_url','teacher.html','color','#0A6EDC','icon','assignment'))
    from public.homeworks hw where hw.teacher_id=uid and coalesce(hw.due_date_gregorian,hw.due_date) between from_d and to_d
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
  u record;
begin
  select id,name,email,role,is_super_admin into u from public.users where id=auth.uid();
  return jsonb_build_object('ok',true,'user',to_jsonb(u),'today',public.get_calendar_day_details(current_date,null),'calendar',public.get_calendar_month(extract(year from current_date)::int,extract(month from current_date)::int,null),'agenda',public.get_my_agenda('week'),'completed',public.get_my_completed_items('week'));
end;
$$;

grant execute on function public.get_dashboard_home() to authenticated;

create or replace function public.smart_calendar_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
end;
$$;

grant execute on function public.smart_calendar_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'smart_calendar_healthcheck_core_restored' as status;

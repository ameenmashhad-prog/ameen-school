-- =============================================================
-- مدارس أمين الرضا (ع) — ربط الجدول بالتقويم والواجبات والرواتب
-- المرحلة: تأسيس كامل بدون حذف بيانات.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) تعريفات العطل الرسمية/الدينية المرشحة
-- التاريخ المتحرك هجرياً يحتاج اعتماد شهري قبل النشر.
-- -------------------------------------------------------------
create table if not exists public.school_holiday_definitions (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null,
  calendar_system text not null check (calendar_system in ('gregorian','persian','hijri')),
  month_no int not null check (month_no between 1 and 12),
  day_no int not null check (day_no between 1 and 31),
  is_official_iran boolean not null default true,
  needs_confirmation boolean not null default false,
  default_publish boolean not null default false,
  notes text,
  unique(name_ar, calendar_system, month_no, day_no)
);

insert into public.school_holiday_definitions
  (name_ar, calendar_system, month_no, day_no, is_official_iran, needs_confirmation, default_publish, notes)
values
  -- عطل شمسية إيرانية ثابتة تقريباً
  ('نوروز', 'persian', 1, 1, true, false, true, 'عيد النوروز'),
  ('عطلة نوروز', 'persian', 1, 2, true, false, true, 'اليوم الثاني من نوروز'),
  ('عطلة نوروز', 'persian', 1, 3, true, false, true, 'اليوم الثالث من نوروز'),
  ('عطلة نوروز', 'persian', 1, 4, true, false, true, 'اليوم الرابع من نوروز'),
  ('يوم الجمهورية الإسلامية', 'persian', 1, 12, true, false, true, '12 فروردين'),
  ('يوم الطبيعة', 'persian', 1, 13, true, false, true, '13 فروردين'),
  ('ذكرى رحيل الإمام الخميني', 'persian', 3, 14, true, false, true, '14 خرداد'),
  ('انتفاضة 15 خرداد', 'persian', 3, 15, true, false, true, '15 خرداد'),
  ('انتصار الثورة الإسلامية', 'persian', 11, 22, true, false, true, '22 بهمن'),
  ('يوم تأميم النفط', 'persian', 12, 29, true, false, true, '29 اسفند'),

  -- عطل هجرية تحتاج تأكيد شهري/سنوي لأن الرؤية قد تختلف
  ('تاسوعاء', 'hijri', 1, 9, true, true, false, 'تحتاج اعتماد حسب التقويم الرسمي'),
  ('عاشوراء', 'hijri', 1, 10, true, true, false, '10 محرم'),
  ('أربعينية الإمام الحسين', 'hijri', 2, 20, true, true, false, '20 صفر'),
  ('وفاة النبي محمد والإمام الحسن', 'hijri', 2, 28, true, true, false, '28 صفر'),
  ('استشهاد الإمام الرضا', 'hijri', 2, 30, true, true, false, '30 صفر إن وجد'),
  ('المولد النبوي والإمام الصادق', 'hijri', 3, 17, true, true, false, '17 ربيع الأول'),
  ('استشهاد السيدة فاطمة', 'hijri', 6, 3, true, true, false, '3 جمادى الآخرة'),
  ('ولادة الإمام علي', 'hijri', 7, 13, true, true, false, '13 رجب'),
  ('المبعث النبوي', 'hijri', 7, 27, true, true, false, '27 رجب'),
  ('ولادة الإمام المهدي', 'hijri', 8, 15, true, true, false, '15 شعبان'),
  ('استشهاد الإمام علي', 'hijri', 9, 21, true, true, false, '21 رمضان'),
  ('عيد الفطر', 'hijri', 10, 1, true, true, false, '1 شوال'),
  ('عطلة عيد الفطر', 'hijri', 10, 2, true, true, false, '2 شوال'),
  ('استشهاد الإمام الصادق', 'hijri', 10, 25, true, true, false, '25 شوال'),
  ('عيد الأضحى', 'hijri', 12, 10, true, true, false, '10 ذو الحجة'),
  ('عيد الغدير', 'hijri', 12, 18, true, true, false, '18 ذو الحجة')
on conflict (name_ar, calendar_system, month_no, day_no) do nothing;

-- -------------------------------------------------------------
-- 2) مقترحات العطل الشهرية قبل النشر
-- -------------------------------------------------------------
create table if not exists public.school_holiday_candidates (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  holiday_definition_id uuid null references public.school_holiday_definitions(id) on delete set null,
  name_ar text not null,
  calendar_system text not null check (calendar_system in ('gregorian','persian','hijri')),
  date_gregorian date not null,
  date_hijri jsonb not null default '{}'::jsonb,
  date_persian jsonb not null default '{}'::jsonb,
  month_key text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected','published')),
  confirmed_by uuid null references public.users(id),
  confirmed_at timestamptz,
  published_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  unique(academic_year, name_ar, date_gregorian)
);

-- -------------------------------------------------------------
-- 3) جلسات فعلية مولدة من الجدول الأسبوعي والتقويم
-- -------------------------------------------------------------
create table if not exists public.class_sessions (
  id uuid primary key default gen_random_uuid(),
  academic_period_id uuid null references public.academic_periods(id) on delete set null,
  weekly_schedule_id uuid null references public.weekly_schedule(id) on delete cascade,
  session_date date not null,
  day int,
  period_number int,
  start_time time,
  end_time time,
  class_id uuid null references public.classes(id),
  subject_id uuid null references public.subjects(id),
  teacher_id uuid null references public.users(id),
  status text not null default 'scheduled' check (status in ('scheduled','holiday','cancelled','completed')),
  holiday_id uuid null references public.school_holidays(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(weekly_schedule_id, session_date)
);

create index if not exists idx_class_sessions_date on public.class_sessions(session_date);
create index if not exists idx_class_sessions_teacher on public.class_sessions(teacher_id, session_date);
create index if not exists idx_class_sessions_class on public.class_sessions(class_id, session_date);

-- -------------------------------------------------------------
-- 4) الواجبات المرتبطة بالحصة
-- -------------------------------------------------------------
create table if not exists public.homeworks (
  id uuid primary key default gen_random_uuid(),
  class_session_id uuid null references public.class_sessions(id) on delete set null,
  academic_period_id uuid null references public.academic_periods(id) on delete set null,
  class_id uuid null references public.classes(id),
  subject_id uuid null references public.subjects(id),
  teacher_id uuid null references public.users(id),
  title text not null,
  description text,
  assigned_date date not null default current_date,
  due_date date,
  status text not null default 'published' check (status in ('draft','published','archived')),
  created_at timestamptz not null default now()
);

create index if not exists idx_homeworks_class_due on public.homeworks(class_id, due_date);
create index if not exists idx_homeworks_teacher on public.homeworks(teacher_id, created_at desc);

-- -------------------------------------------------------------
-- 5) سجل نشاط المعلمة داخل الحصة
-- أي نشاط يثبت أن المعلمة أخذت الحصة: حضور، واجب، تثبيت يدوي، ملاحظة درس...
-- -------------------------------------------------------------
create table if not exists public.teacher_activity_log (
  id uuid primary key default gen_random_uuid(),
  class_session_id uuid null references public.class_sessions(id) on delete cascade,
  teacher_id uuid not null references public.users(id),
  activity_type text not null check (activity_type in ('attendance','homework','lesson_note','manual_confirm','grade_entry','other')),
  evidence_table text,
  evidence_id uuid,
  activity_weight numeric not null default 1,
  notes text,
  occurred_at timestamptz not null default now(),
  created_by uuid null references public.users(id),
  unique(class_session_id, teacher_id, activity_type, evidence_table, evidence_id)
);

create index if not exists idx_teacher_activity_teacher on public.teacher_activity_log(teacher_id, occurred_at desc);
create index if not exists idx_teacher_activity_session on public.teacher_activity_log(class_session_id);

-- -------------------------------------------------------------
-- 6) قواعد حساب الرواتب من الحصص المثبتة بالنشاط
-- -------------------------------------------------------------
create table if not exists public.teacher_payroll_rules (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid null references public.users(id),
  currency text not null default 'USD',
  amount_per_verified_session numeric not null default 0,
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now()
);

create or replace view public.v_teacher_verified_sessions
with (security_invoker=true) as
select
  tal.teacher_id,
  u.name as teacher_name,
  cs.session_date,
  cs.class_id,
  c.name as class_name,
  cs.subject_id,
  s.name as subject_name,
  cs.period_number,
  cs.start_time,
  cs.end_time,
  tal.class_session_id,
  count(*) as activity_count,
  array_agg(distinct tal.activity_type) as activity_types,
  sum(tal.activity_weight) as activity_weight
from public.teacher_activity_log tal
join public.class_sessions cs on cs.id = tal.class_session_id
left join public.users u on u.id = tal.teacher_id
left join public.classes c on c.id = cs.class_id
left join public.subjects s on s.id = cs.subject_id
group by tal.teacher_id, u.name, cs.session_date, cs.class_id, c.name, cs.subject_id, s.name, cs.period_number, cs.start_time, cs.end_time, tal.class_session_id;

create or replace view public.v_teacher_payroll_preview
with (security_invoker=true) as
select
  v.teacher_id,
  v.teacher_name,
  date_trunc('month', v.session_date)::date as month,
  count(distinct v.class_session_id) as verified_sessions,
  coalesce(max(r.amount_per_verified_session) filter (where r.active = true), 0) as amount_per_session,
  coalesce(max(r.currency) filter (where r.active = true), 'USD') as currency,
  count(distinct v.class_session_id) * coalesce(max(r.amount_per_verified_session) filter (where r.active = true), 0) as estimated_amount
from public.v_teacher_verified_sessions v
left join public.teacher_payroll_rules r on (r.teacher_id = v.teacher_id or r.teacher_id is null) and r.active = true
group by v.teacher_id, v.teacher_name, date_trunc('month', v.session_date)::date;

grant select, insert, update on public.class_sessions to authenticated;
grant select, insert, update on public.homeworks to authenticated;
grant select, insert, update on public.teacher_activity_log to authenticated;
grant select, insert, update on public.teacher_payroll_rules to authenticated;
grant select on public.v_teacher_verified_sessions to authenticated;
grant select on public.v_teacher_payroll_preview to authenticated;
grant select, insert, update on public.school_holiday_candidates to authenticated;
grant select on public.school_holiday_definitions to authenticated;

-- -------------------------------------------------------------
-- 7) Trigger: عند نشر واجب، يسجل نشاط homework للمعلمة
-- -------------------------------------------------------------
create or replace function public.log_teacher_activity_from_homework()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.teacher_id is not null and new.class_session_id is not null then
    insert into public.teacher_activity_log (
      class_session_id,
      teacher_id,
      activity_type,
      evidence_table,
      evidence_id,
      activity_weight,
      notes,
      created_by
    ) values (
      new.class_session_id,
      new.teacher_id,
      'homework',
      'homeworks',
      new.id,
      1,
      'تم تسجيل نشاط تلقائي بسبب نشر واجب',
      new.teacher_id
    ) on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_homework_teacher_activity on public.homeworks;
create trigger trg_homework_teacher_activity
  after insert on public.homeworks
  for each row execute function public.log_teacher_activity_from_homework();

-- -------------------------------------------------------------
-- 8) دالة توليد جلسات التقويم من الجدول الأسبوعي
-- p_start / p_end: الفترة المراد توليدها
-- تستثني أيام العطل المنشورة/المعتمدة.
-- -------------------------------------------------------------
create or replace function public.generate_class_sessions(
  p_start date,
  p_end date,
  p_academic_period_id uuid default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  d date;
  dow_school int;
  ws record;
  h record;
  inserted_count int := 0;
  stage_kind text;
  settings jsonb;
  p_start_time text;
  p_duration int;
  p_break int;
  start_minutes int;
  s_time time;
  e_time time;
begin
  select schedule_time_settings into settings
  from public.school_calendar_settings
  where id = 'main';

  if settings is null then
    settings := '{
      "primary": {"start": "12:45", "periods": 5, "duration": 45, "break": 10},
      "secondary": {"start": "13:00", "periods": 3, "duration": 75, "break": 10}
    }'::jsonb;
  end if;

  d := p_start;
  while d <= p_end loop
    -- PostgreSQL: Sunday=0, Saturday=6
    -- school: Saturday=0, Sunday=1, Monday=2, Tuesday=3, Wednesday=4
    dow_school := ((extract(dow from d)::int + 1) % 7);

    select * into h
    from public.school_holidays sh
    where sh.holiday_date = d
       or (sh.is_recurring = true and to_char(sh.holiday_date,'MM-DD') = to_char(d,'MM-DD'))
    limit 1;

    for ws in
      select w.*, c.name as class_name
      from public.weekly_schedule w
      left join public.classes c on c.id = w.class_id
      where w.day = dow_school
        and (p_academic_period_id is null or w.academic_period_id = p_academic_period_id)
    loop
      stage_kind := case
        when ws.class_name ilike '%ابتدائي%' then 'primary'
        else 'secondary'
      end;

      p_start_time := coalesce(settings -> stage_kind ->> 'start', case when stage_kind='primary' then '12:45' else '13:00' end);
      p_duration := coalesce((settings -> stage_kind ->> 'duration')::int, case when stage_kind='primary' then 45 else 75 end);
      p_break := coalesce((settings -> stage_kind ->> 'break')::int, 10);

      start_minutes := split_part(p_start_time, ':', 1)::int * 60
                     + split_part(p_start_time, ':', 2)::int
                     + ((ws.period_number - 1) * (p_duration + p_break));

      s_time := make_time((start_minutes / 60)::int % 24, start_minutes % 60, 0);
      e_time := make_time(((start_minutes + p_duration) / 60)::int % 24, (start_minutes + p_duration) % 60, 0);

      insert into public.class_sessions (
        academic_period_id,
        weekly_schedule_id,
        session_date,
        day,
        period_number,
        start_time,
        end_time,
        class_id,
        subject_id,
        teacher_id,
        status,
        holiday_id
      ) values (
        ws.academic_period_id,
        ws.id,
        d,
        dow_school,
        ws.period_number,
        s_time,
        e_time,
        ws.class_id,
        ws.subject_id,
        ws.teacher_id,
        case when h.id is not null then 'holiday' else 'scheduled' end,
        h.id
      )
      on conflict (weekly_schedule_id, session_date) do update
      set
        start_time = excluded.start_time,
        end_time = excluded.end_time,
        status = excluded.status,
        holiday_id = excluded.holiday_id,
        updated_at = now();

      inserted_count := inserted_count + 1;
    end loop;

    d := d + 1;
  end loop;

  return inserted_count;
end;
$$;

grant execute on function public.generate_class_sessions(date,date,uuid) to authenticated;

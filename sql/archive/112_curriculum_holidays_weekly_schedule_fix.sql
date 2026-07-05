-- =============================================================
-- مدارس أمين الرضا (ع) — ربط مخطط المنهج بالعطل الرسمية وحصص الأسبوع
-- إيران IR حالياً: عطلات رسمية ثابتة بالتقويم الشمسي + استبعاد العطل/نهاية الأسبوع.
-- شغّل هذا الملف بعد SQL 110.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) إعداد الدولة/نهاية الأسبوع: إيران
-- Postgres DOW: الجمعة = 5. في إيران الجمعة عطلة أسبوعية افتراضياً.
-- -------------------------------------------------------------
do $$
begin
  if to_regclass('public.school_calendar_settings') is not null then
    update public.school_calendar_settings
    set country_code='IR', timezone='Asia/Tehran', weekend_days=array[5]
    where id='main' or id is not null;
  end if;

  if to_regclass('public.school_branches') is not null then
    update public.school_branches
    set country_code='IR', timezone='Asia/Tehran', weekend_days=array[5]
    where is_main=true or country_code is null or country_code='IR';
  end if;
end $$;

-- -------------------------------------------------------------
-- 2) تحويل جلالي/شمسي إلى ميلادي لتوليد العطل الإيرانية الثابتة
-- -------------------------------------------------------------
create or replace function public.curriculum_jalali_to_gregorian(jy int, jm int, jd int)
returns date
language plpgsql
security definer
set search_path = public
immutable
as $$
declare
  y int := jy + 1595;
  days int;
  gy int;
  gd int;
  gm int := 1;
  leap boolean;
  mdays int[];
begin
  if jm < 1 or jm > 12 or jd < 1 or jd > 31 then
    return null;
  end if;

  days := -355668 + (365 * y) + ((y / 33)::int * 8) + (((y % 33) + 3) / 4)::int + jd;
  if jm < 7 then
    days := days + ((jm - 1) * 31);
  else
    days := days + (((jm - 7) * 30) + 186);
  end if;

  gy := 400 * (days / 146097)::int;
  days := days % 146097;

  if days > 36524 then
    days := days - 1;
    gy := gy + 100 * (days / 36524)::int;
    days := days % 36524;
    if days >= 365 then days := days + 1; end if;
  end if;

  gy := gy + 4 * (days / 1461)::int;
  days := days % 1461;

  if days > 365 then
    gy := gy + ((days - 1) / 365)::int;
    days := (days - 1) % 365;
  end if;

  gd := days + 1;
  leap := (gy % 4 = 0 and gy % 100 <> 0) or (gy % 400 = 0);
  mdays := array[31, case when leap then 29 else 28 end, 31,30,31,30,31,31,30,31,30,31];

  while gm <= 12 and gd > mdays[gm] loop
    gd := gd - mdays[gm];
    gm := gm + 1;
  end loop;

  return make_date(gy, gm, gd);
end;
$$;

grant execute on function public.curriculum_jalali_to_gregorian(int,int,int) to authenticated;

-- -------------------------------------------------------------
-- 3) قواعد عطلات إيران الرسمية الثابتة في التقويم الشمسي
-- -------------------------------------------------------------
do $$
begin
  if to_regclass('public.holiday_rules') is not null then
    insert into public.holiday_rules(country_code,title_ar,title_en,title_local,calendar_type,month,day,duration_days,holiday_type,requires_manual_review,is_active)
    values
      ('IR','النوروز','Nowruz','نوروز','solar',1,1,4,'national',false,true),
      ('IR','يوم الجمهورية الإسلامية','Islamic Republic Day','روز جمهوری اسلامی','solar',1,12,1,'national',false,true),
      ('IR','يوم الطبيعة','Nature Day','روز طبیعت','solar',1,13,1,'national',false,true),
      ('IR','رحيل الإمام الخميني','Imam Khomeini Demise','رحلت امام خمینی','solar',3,14,1,'national',false,true),
      ('IR','انتفاضة 15 خرداد','15 Khordad Uprising','قیام ۱۵ خرداد','solar',3,15,1,'national',false,true),
      ('IR','انتصار الثورة الإسلامية','Islamic Revolution Victory','پیروزی انقلاب اسلامی','solar',11,22,1,'national',false,true),
      ('IR','تأميم النفط','Oil Nationalization Day','ملی شدن صنعت نفت','solar',12,29,1,'national',false,true),
      ('IR','عيد الفطر','Eid al-Fitr','عید فطر','lunar',10,1,2,'religious',true,true),
      ('IR','عيد الأضحى','Eid al-Adha','عید قربان','lunar',12,10,1,'religious',true,true),
      ('IR','عيد الغدير','Eid al-Ghadir','عید غدیر','lunar',12,18,1,'religious',true,true),
      ('IR','تاسوعاء','Tasua','تاسوعا','lunar',1,9,1,'religious',true,true),
      ('IR','عاشوراء','Ashura','عاشورا','lunar',1,10,1,'religious',true,true),
      ('IR','أربعينية الإمام الحسين','Arbaeen','اربعین','lunar',2,20,1,'religious',true,true)
    on conflict do nothing;
  end if;
end $$;

-- -------------------------------------------------------------
-- 4) توليد عطلات إيران الثابتة بالتقويم الشمسي داخل السنوات الدراسية
-- -------------------------------------------------------------
create or replace function public.curriculum_seed_iran_holidays_for_academic_years()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  y record;
  r record;
  jy int;
  d date;
  cur date;
  inserted int := 0;
  skipped int := 0;
  offs int;
begin
  if to_regclass('public.academic_years') is null or to_regclass('public.holidays') is null then
    return jsonb_build_object('ok',false,'message','جداول التقويم غير موجودة');
  end if;

  for y in select * from public.academic_years where coalesce(country_code,'IR')='IR' loop
    for r in select * from public.holiday_rules where country_code='IR' and calendar_type='solar' and is_active=true loop
      for jy in 1390..1425 loop
        d := public.curriculum_jalali_to_gregorian(jy, r.month, r.day);
        if d is not null and d between y.start_date_gregorian and y.end_date_gregorian then
          for offs in 0..greatest(coalesce(r.duration_days,1)-1,0) loop
            cur := d + offs;
            if not exists(
              select 1 from public.holidays h
              where h.country_code='IR'
                and h.date_gregorian=cur
                and h.title_ar=r.title_ar
                and (h.academic_year_id=y.id or h.academic_year_id is null)
            ) then
              insert into public.holidays(
                school_id, branch_id, country_code, academic_year_id,
                title_ar, title_en, title_local, date_gregorian,
                solar_date, holiday_type, source, review_status,
                affects_attendance, affects_assignments, affects_exams, created_by
              ) values (
                coalesce(y.school_id,'main'), y.branch_id, 'IR', y.id,
                r.title_ar, r.title_en, r.title_local, cur,
                jy::text || '-' || lpad(r.month::text,2,'0') || '-' || lpad((r.day+offs)::text,2,'0'),
                r.holiday_type, 'rule', 'approved', true, true, true, auth.uid()
              );
              inserted := inserted + 1;
            else
              skipped := skipped + 1;
            end if;
          end loop;
        end if;
      end loop;
    end loop;
  end loop;

  return jsonb_build_object('ok',true,'inserted',inserted,'skipped',skipped,'country_code','IR');
end;
$$;

grant execute on function public.curriculum_seed_iran_holidays_for_academic_years() to authenticated;

select public.curriculum_seed_iran_holidays_for_academic_years();

-- -------------------------------------------------------------
-- 5) يوم المدرسة وفهرس اليوم حسب weekly_schedule: 0=السبت، 1=الأحد ... 6=الجمعة
-- -------------------------------------------------------------
create or replace function public.curriculum_school_day_index(p_date date)
returns int
language sql
security definer
set search_path = public
immutable
as $$
  select ((extract(dow from p_date)::int + 1) % 7)::int;
$$;

grant execute on function public.curriculum_school_day_index(date) to authenticated;

create or replace function public.curriculum_is_school_day(p_date date, p_branch_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  weekends int[] := array[5];
  is_holiday boolean := false;
begin
  if p_branch_id is not null and to_regclass('public.school_branches') is not null then
    select sb.weekend_days into weekends from public.school_branches sb where sb.id=p_branch_id;
  end if;

  if weekends is null and to_regclass('public.school_calendar_settings') is not null then
    select scs.weekend_days into weekends from public.school_calendar_settings scs order by updated_at desc nulls last limit 1;
  end if;
  weekends := coalesce(weekends,array[5]);

  if to_regclass('public.holidays') is not null then
    select exists(
      select 1 from public.holidays h
      where h.date_gregorian=p_date
        and h.review_status in ('approved','needs_review')
        and coalesce(h.affects_attendance,true)=true
        and (p_branch_id is null or h.branch_id is null or h.branch_id=p_branch_id)
    ) into is_holiday;
  end if;

  return not (extract(dow from p_date)::int = any(weekends)) and not coalesce(is_holiday,false);
end;
$$;

grant execute on function public.curriculum_is_school_day(date,uuid) to authenticated;

-- -------------------------------------------------------------
-- 6) استنتاج عدد حصص المادة في الأسبوع من weekly_schedule
-- -------------------------------------------------------------
create or replace function public.curriculum_infer_lessons_per_week(
  p_teacher_id uuid,
  p_class_id uuid,
  p_section_id uuid,
  p_subject_id uuid,
  p_academic_period_id uuid default null
)
returns int
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v int := 0;
begin
  if to_regclass('public.weekly_schedule') is null then
    return 0;
  end if;

  select count(*)::int
  into v
  from public.weekly_schedule ws
  where (p_teacher_id is null or ws.teacher_id=p_teacher_id)
    and (p_class_id is null or ws.class_id=p_class_id)
    and (p_subject_id is null or ws.subject_id=p_subject_id)
    and (p_academic_period_id is null or ws.academic_period_id=p_academic_period_id)
    and (p_section_id is null or ws.section_id is null or ws.section_id=p_section_id)
    and ws.day is not null
    and ws.period_number is not null;

  return coalesce(v,0);
end;
$$;

grant execute on function public.curriculum_infer_lessons_per_week(uuid,uuid,uuid,uuid,uuid) to authenticated;

-- -------------------------------------------------------------
-- 7) سياق العطل والحمولة الأسبوعية للواجهة
-- -------------------------------------------------------------
create or replace function public.get_curriculum_holiday_context(p_plan_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  p record;
  country text := 'IR';
  weekends int[] := array[5];
  upcoming jsonb := '[]'::jsonb;
  inferred int := 0;
begin
  if p_plan_id is not null then
    select * into p from public.curriculum_plans where id=p_plan_id;
    if p.id is not null then
      inferred := public.curriculum_infer_lessons_per_week(p.teacher_id,p.class_id,p.section_id,p.subject_id,p.academic_period_id);
    end if;
  end if;

  if to_regclass('public.school_calendar_settings') is not null then
    select coalesce(country_code,'IR'), coalesce(weekend_days,array[5])
    into country, weekends
    from public.school_calendar_settings
    order by updated_at desc nulls last
    limit 1;
  end if;

  if to_regclass('public.holidays') is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'title', h.title_ar,
      'title_local', h.title_local,
      'date', h.date_gregorian,
      'type', h.holiday_type,
      'review_status', h.review_status
    ) order by h.date_gregorian), '[]'::jsonb)
    into upcoming
    from public.holidays h
    where h.country_code = coalesce(country,'IR')
      and h.date_gregorian between current_date and current_date + 365
      and h.review_status in ('approved','needs_review');
  end if;

  return jsonb_build_object(
    'ok', true,
    'country_code', country,
    'weekend_days', weekends,
    'inferred_lessons_per_week', inferred,
    'upcoming_holidays', upcoming,
    'holiday_count', jsonb_array_length(upcoming),
    'notes', 'التوزيع يستبعد العطل الرسمية ونهاية الأسبوع ويستخدم حصص الأسبوع من جدول المدرسة عند توفرها.'
  );
end;
$$;

grant execute on function public.get_curriculum_holiday_context(uuid) to authenticated;

-- -------------------------------------------------------------
-- 8) إعادة توزيع الدروس المتبقية مع استبعاد العطل واستخدام weekly_schedule
-- -------------------------------------------------------------
create or replace function public.curriculum_redistribute_remaining(p_plan_id uuid, p_lessons_per_week int default null, p_start_week int default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
  lpw int;
  inferred int := 0;
  start_w int;
  i int := 0;
  r record;
  before_json jsonb;
  moved int := 0;
  schedule_count int := 0;
  occ record;
  start_from date;
begin
  select * into p from public.curriculum_plans where id=p_plan_id;
  if p.id is null then return jsonb_build_object('ok',false,'message','الخطة غير موجودة'); end if;
  if not (p.teacher_id=auth.uid() or public.current_user_is_admin()) then return jsonb_build_object('ok',false,'message','لا توجد صلاحية'); end if;

  perform public.curriculum_snapshot_plan(p_plan_id,'before_holiday_aware_redistribute');

  inferred := public.curriculum_infer_lessons_per_week(p.teacher_id,p.class_id,p.section_id,p.subject_id,p.academic_period_id);
  if coalesce(p_lessons_per_week,0) > 0 then
    lpw := greatest(1, least(12, p_lessons_per_week));
  elsif inferred > 0 then
    lpw := inferred;
  else
    lpw := greatest(1, least(12, coalesce(p.lessons_per_week,4)));
  end if;

  schedule_count := inferred;
  select coalesce(min(week_index),1) into start_w from public.curriculum_plan_slots where plan_id=p_plan_id and status not in ('completed','cancelled');
  start_w := coalesce(p_start_week,start_w,1);
  start_from := p.start_date + (((start_w - 1) * 7)::int);

  for r in select * from public.curriculum_plan_slots where plan_id=p_plan_id and status not in ('completed','cancelled') order by week_index, slot_order loop
    before_json := to_jsonb(r);

    if schedule_count > 0 then
      select q.planned_date, q.day_index, q.period_number
      into occ
      from (
        select d::date as planned_date,
               public.curriculum_school_day_index(d::date) as day_index,
               ws.period_number
        from generate_series(start_from, start_from + interval '730 days', interval '1 day') d
        join public.weekly_schedule ws
          on ws.day = public.curriculum_school_day_index(d::date)
         and (p.teacher_id is null or ws.teacher_id=p.teacher_id)
         and (p.class_id is null or ws.class_id=p.class_id)
         and (p.subject_id is null or ws.subject_id=p.subject_id)
         and (p.academic_period_id is null or ws.academic_period_id=p.academic_period_id)
         and (p.section_id is null or ws.section_id is null or ws.section_id=p.section_id)
        where public.curriculum_is_school_day(d::date,null)
        order by d::date, ws.period_number
        offset i limit 1
      ) q;
    else
      select q.planned_date, q.day_index, null::int as period_number
      into occ
      from (
        select d::date as planned_date, public.curriculum_school_day_index(d::date) as day_index
        from generate_series(start_from, start_from + interval '730 days', interval '1 day') d
        where public.curriculum_is_school_day(d::date,null)
        order by d::date
        offset i limit 1
      ) q;
    end if;

    update public.curriculum_plan_slots
    set planned_date = coalesce(occ.planned_date, planned_date),
        day_index = coalesce(occ.day_index, day_index),
        week_index = greatest(1, floor(((coalesce(occ.planned_date,planned_date) - p.start_date)::numeric) / 7)::int + 1),
        month_index = ((greatest(1, floor(((coalesce(occ.planned_date,planned_date) - p.start_date)::numeric) / 7)::int + 1) - 1) / 4) + 1,
        slot_order = coalesce(occ.period_number, (i % lpw) + 1),
        manual_override = true,
        teacher_notes = coalesce(teacher_notes,'') || case when teacher_notes is null or teacher_notes='' then '' else E'\n' end || 'أعيد التوزيع مع مراعاة العطل الرسمية وحصص الأسبوع.',
        updated_at = now()
    where id = r.id;

    perform public.curriculum_log(p_plan_id,r.id,'holiday_aware_redistribute',before_json,(select to_jsonb(x) from public.curriculum_plan_slots x where x.id=r.id));
    i := i + 1; moved := moved + 1;
  end loop;

  update public.curriculum_plans set lessons_per_week=lpw, updated_at=now() where id=p_plan_id;

  return jsonb_build_object(
    'ok', true,
    'moved', moved,
    'lessons_per_week', lpw,
    'inferred_from_schedule', inferred,
    'country_code', 'IR',
    'message', 'تمت إعادة التوزيع مع مراعاة العطل الرسمية وحصص الأسبوع'
  );
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.curriculum_redistribute_remaining(uuid,int,int) to authenticated;

-- -------------------------------------------------------------
-- 9) Health Check
-- -------------------------------------------------------------
create or replace function public.curriculum_holidays_weekly_schedule_health_check()
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
    'country_code', 'IR',
    'functions', jsonb_build_object(
      'curriculum_is_school_day', to_regprocedure('public.curriculum_is_school_day(date,uuid)') is not null,
      'curriculum_infer_lessons_per_week', to_regprocedure('public.curriculum_infer_lessons_per_week(uuid,uuid,uuid,uuid,uuid)') is not null,
      'get_curriculum_holiday_context', to_regprocedure('public.get_curriculum_holiday_context(uuid)') is not null,
      'curriculum_redistribute_remaining', to_regprocedure('public.curriculum_redistribute_remaining(uuid,int,int)') is not null
    ),
    'holiday_rules_ir', case when to_regclass('public.holiday_rules') is null then 0 else (select count(*) from public.holiday_rules where country_code='IR' and is_active=true) end,
    'holidays_ir', case when to_regclass('public.holidays') is null then 0 else (select count(*) from public.holidays where country_code='IR' and review_status in ('approved','needs_review')) end,
    'weekly_schedule_rows', case when to_regclass('public.weekly_schedule') is null then 0 else (select count(*) from public.weekly_schedule) end,
    'settings', case when to_regclass('public.school_calendar_settings') is null then '{}'::jsonb else (select to_jsonb(x) from (select country_code, timezone, weekend_days from public.school_calendar_settings order by updated_at desc nulls last limit 1) x) end,
    'notes', 'مخطط المنهج الآن يستبعد عطلات إيران الرسمية ونهاية الأسبوع ويستنتج عدد الحصص من weekly_schedule عند توفرها.'
  );
end;
$$;

grant execute on function public.curriculum_holidays_weekly_schedule_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.curriculum_holidays_weekly_schedule_health_check() as curriculum_holidays_weekly_schedule_health;

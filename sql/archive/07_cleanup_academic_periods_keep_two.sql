-- =============================================================
-- مدارس أمين الرضا (ع) — تنظيف الفصول الدراسية بدون كسر FK
-- الهدف: الإبقاء فقط على:
-- 1) الفصل الدراسي الأول 2026/2027
-- 2) الفصل الدراسي الثاني 2026/2027
--
-- يعالج مشكلة:
-- academic_periods row is referenced from weekly_schedule
--
-- المنطق:
-- - ننشئ/نحدد الفصلين الأساسيين.
-- - ننقل سجلات الجداول المرتبطة من الفصول الزائدة إلى الفصل المناسب.
-- - إذا كان النقل يسبب تكرار حصة في weekly_schedule نحذف النسخة الزائدة فقط.
-- - بعدها نحذف الفصول الزائدة.
-- =============================================================

create extension if not exists pgcrypto;

-- 1) تأكد من وجود الفصلين الأساسيين
insert into public.academic_periods (name)
select 'الفصل الدراسي الأول 2026/2027'
where not exists (
  select 1 from public.academic_periods
  where name = 'الفصل الدراسي الأول 2026/2027'
);

insert into public.academic_periods (name)
select 'الفصل الدراسي الثاني 2026/2027'
where not exists (
  select 1 from public.academic_periods
  where name = 'الفصل الدراسي الثاني 2026/2027'
);

-- 2) اختيار نسخة واحدة للاحتفاظ بها من كل فصل
drop table if exists temp_keep_periods;
create temporary table temp_keep_periods as
select
  (
    select id
    from public.academic_periods
    where name = 'الفصل الدراسي الأول 2026/2027'
    order by created_at nulls last, id
    limit 1
  ) as first_id,
  (
    select id
    from public.academic_periods
    where name = 'الفصل الدراسي الثاني 2026/2027'
    order by created_at nulls last, id
    limit 1
  ) as second_id;

-- 3) خريطة تحويل كل فصل زائد إلى الفصل الأساسي المناسب
drop table if exists temp_period_map;
create temporary table temp_period_map as
select
  ap.id as old_id,
  ap.name as old_name,
  case
    when ap.name ilike '%ثاني%' or ap.name ilike '%الثاني%'
      then kp.second_id
    else kp.first_id
  end as target_id
from public.academic_periods ap
cross join temp_keep_periods kp
where ap.id not in (kp.first_id, kp.second_id);

-- إذا لا توجد فصول زائدة، اعرض النتيجة وتوقف عملياً.
do $$
begin
  if not exists (select 1 from temp_period_map) then
    raise notice 'لا توجد فصول زائدة للحذف.';
  end if;
end $$;

-- 4) معالجة weekly_schedule قبل حذف الفصول
-- 4.1 حذف النسخ الزائدة التي ستتعارض مع حصة موجودة في الفصل الهدف.
do $$
begin
  if to_regclass('public.weekly_schedule') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='weekly_schedule' and column_name='academic_period_id') then

    -- أ) حذف أي حصة من فصل زائد إذا كان نفس مكانها موجوداً مسبقاً في الفصل الهدف.
    delete from public.weekly_schedule ws
    using temp_period_map pm
    where ws.academic_period_id = pm.old_id
      and exists (
        select 1
        from public.weekly_schedule keep
        where keep.academic_period_id = pm.target_id
          and keep.class_id is not distinct from ws.class_id
          and keep.day is not distinct from ws.day
          and keep.period_number is not distinct from ws.period_number
      );

    -- ب) حذف التكرارات بين الفصول الزائدة نفسها قبل نقلها.
    -- مثال: فصلان زائدان يحتويان نفس الصف/اليوم/الحصة وينتقلان لنفس الفصل الهدف.
    with ranked as (
      select
        ws.id,
        row_number() over (
          partition by pm.target_id, ws.class_id, ws.day, ws.period_number
          order by ws.id
        ) as rn
      from public.weekly_schedule ws
      join temp_period_map pm on pm.old_id = ws.academic_period_id
    )
    delete from public.weekly_schedule ws
    using ranked r
    where ws.id = r.id
      and r.rn > 1;

    -- ج) الآن أصبح النقل آمناً ولا يخرق القيد الفريد.
    update public.weekly_schedule ws
    set academic_period_id = pm.target_id
    from temp_period_map pm
    where ws.academic_period_id = pm.old_id;
  end if;
end $$;

-- 5) معالجة exemptions قبل حذف الفصول
-- يوجد عندك UNIQUE على: student_id, academic_period_id, subject_id
-- لذلك نحذف النسخة الزائدة إذا كانت ستسبب تكراراً.
do $$
begin
  if to_regclass('public.exemptions') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='exemptions' and column_name='academic_period_id') then

    delete from public.exemptions e
    using temp_period_map pm
    where e.academic_period_id = pm.old_id
      and exists (
        select 1
        from public.exemptions keep
        where keep.academic_period_id = pm.target_id
          and keep.student_id is not distinct from e.student_id
          and keep.subject_id is not distinct from e.subject_id
      );

    update public.exemptions e
    set academic_period_id = pm.target_id
    from temp_period_map pm
    where e.academic_period_id = pm.old_id;
  end if;
end $$;

-- 6) معالجة grades إن وجد academic_period_id
do $$
begin
  if to_regclass('public.grades') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='grades' and column_name='academic_period_id') then
    update public.grades g
    set academic_period_id = pm.target_id
    from temp_period_map pm
    where g.academic_period_id = pm.old_id;
  end if;
end $$;

-- 7) معالجة schedule_import_batches إن وجد
do $$
begin
  if to_regclass('public.schedule_import_batches') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='schedule_import_batches' and column_name='academic_period_id') then
    update public.schedule_import_batches b
    set academic_period_id = pm.target_id
    from temp_period_map pm
    where b.academic_period_id = pm.old_id;
  end if;
end $$;

-- 8) محاولة نقل أي جدول آخر يحتوي academic_period_id بشكل عام
-- إذا فشل جدول بسبب قيد فريد، نطبع NOTICE ثم سيظهر عند الحذف إن بقي مرجع.
do $$
declare
  r record;
begin
  for r in
    select table_name
    from information_schema.columns
    where table_schema = 'public'
      and column_name = 'academic_period_id'
      and table_name not in (
        'academic_periods',
        'weekly_schedule',
        'exemptions',
        'grades',
        'schedule_import_batches'
      )
  loop
    begin
      execute format(
        'update public.%I t set academic_period_id = pm.target_id from temp_period_map pm where t.academic_period_id = pm.old_id',
        r.table_name
      );
    exception when others then
      raise notice 'تعذر تحديث %. السبب: %', r.table_name, sqlerrm;
    end;
  end loop;
end $$;

-- 9) حذف الفصول الزائدة الآن بعد نقل المراجع
delete from public.academic_periods ap
where ap.id in (select old_id from temp_period_map);

-- 10) ضبط الأسماء النهائية للفصلين الأساسيين
update public.academic_periods
set name = 'الفصل الدراسي الأول 2026/2027'
where id = (select first_id from temp_keep_periods);

update public.academic_periods
set name = 'الفصل الدراسي الثاني 2026/2027'
where id = (select second_id from temp_keep_periods);

-- 11) عرض النتيجة النهائية
select id, name
from public.academic_periods
order by name;

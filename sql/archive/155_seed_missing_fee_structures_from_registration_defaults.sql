-- ============================================================================
-- Seed missing class fees from legacy registration defaults
-- الهدف:
-- - تعبئة fee_structures للصفوف التي لا تملك قيمة حالياً
-- - اعتماد القيم المرجعية المستخدمة في استمارة التسجيل الحالية
-- - عدم تعديل الصفوف التي لها قيمة محفوظة مسبقاً
-- ============================================================================

with class_defaults as (
  select c.id as class_id,
         c.name as class_name,
         case
           when c.name like '%الأول الابتدائي%' then 500
           when c.name like '%الثاني الابتدائي%' then 500
           when c.name like '%الثالث الابتدائي%' then 500
           when c.name like '%الرابع الابتدائي%' then 500
           when c.name like '%الخامس الابتدائي%' then 500
           when c.name like '%السادس الابتدائي%' then 500
           when c.name like '%الأول المتوسط%' then 550
           when c.name like '%الثاني المتوسط%' then 550
           when c.name like '%الثالث المتوسط%' then 350
           when c.name like '%الرابع الإعدادي%' then 700
           when c.name like '%الخامس الإعدادي%' then 700
           when c.name like '%السادس الإعدادي%' then 50
           else null
         end::numeric as annual_fee_default
  from public.classes c
), missing_targets as (
  select d.class_id,
         d.class_name,
         d.annual_fee_default
  from class_defaults d
  left join public.fee_structures fs
    on fs.class_id = d.class_id
   and coalesce(fs.academic_year, '2026-2027') = '2026-2027'
  where d.annual_fee_default is not null
    and (
      fs.id is null
      or coalesce(fs.annual_fee, fs.amount, 0) <= 0
    )
)
insert into public.fee_structures(
  class_id,
  monthly_fee,
  annual_fee,
  amount,
  currency,
  academic_year,
  is_active,
  created_at,
  updated_at
)
select
  m.class_id,
  round((m.annual_fee_default / 9.0)::numeric, 2) as monthly_fee,
  m.annual_fee_default,
  m.annual_fee_default,
  'USD',
  '2026-2027',
  true,
  now(),
  now()
from missing_targets m
on conflict (class_id, academic_year)
do update set
  annual_fee = excluded.annual_fee,
  amount = excluded.amount,
  monthly_fee = excluded.monthly_fee,
  currency = excluded.currency,
  is_active = true,
  updated_at = now()
where coalesce(public.fee_structures.annual_fee, public.fee_structures.amount, 0) <= 0;

notify pgrst, 'reload schema';

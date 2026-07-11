-- ============================================================================
-- SAFE PATCH — fee_structures compatibility + public family fee catalog
--
-- استخدم هذا الملف إذا ظهرت مشكلة created_at / updated_at في fee_structures.
-- هذا الملف يتجنب الاعتماد على created_at داخل INSERT نفسها.
-- ============================================================================

alter table public.fee_structures
  add column if not exists created_at timestamptz;

alter table public.fee_structures
  add column if not exists updated_at timestamptz;

alter table public.fee_structures
  add column if not exists amount numeric not null default 0;

alter table public.fee_structures
  add column if not exists annual_fee numeric;

alter table public.fee_structures
  add column if not exists monthly_fee numeric not null default 0;

alter table public.fee_structures
  add column if not exists currency text not null default 'USD';

alter table public.fee_structures
  add column if not exists academic_year text not null default '2026-2027';

alter table public.fee_structures
  add column if not exists is_active boolean not null default true;

update public.fee_structures
set created_at = coalesce(created_at, now()),
    updated_at = coalesce(updated_at, now())
where created_at is null or updated_at is null;

alter table public.fee_structures
  alter column created_at set default now();

alter table public.fee_structures
  alter column updated_at set default now();

update public.fee_structures
set annual_fee = coalesce(annual_fee, nullif(amount,0), round((nullif(monthly_fee,0) * 9.0)::numeric, 2), 0),
    amount = coalesce(nullif(amount,0), annual_fee, round((nullif(monthly_fee,0) * 9.0)::numeric, 2), 0),
    monthly_fee = case
      when monthly_fee is null or monthly_fee = 0 then round((coalesce(annual_fee, amount, 0) / 9.0)::numeric, 2)
      else monthly_fee
    end,
    updated_at = now()
where annual_fee is null
   or amount is null
   or monthly_fee is null
   or annual_fee = 0
   or amount = 0
   or monthly_fee = 0;

create or replace function public.forms_get_family_registration_finance_catalog_v3(
  p_academic_year text default '2026-2027'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'class_id', c.id,
          'class_name', c.name,
          'fee_structure_id', fs.id,
          'annual_fee', coalesce(fs.annual_fee, fs.amount, 0),
          'monthly_fee', coalesce(fs.monthly_fee, round((coalesce(fs.annual_fee, fs.amount, 0) / 9.0)::numeric, 2), 0),
          'currency', coalesce(fs.currency, 'USD'),
          'academic_year', coalesce(fs.academic_year, p_academic_year),
          'has_finance_rule', (fs.id is not null)
        )
        order by c.name
      )
      from public.classes c
      left join lateral (
        select *
        from public.fee_structures f
        where f.class_id = c.id
          and coalesce(f.academic_year, p_academic_year) = p_academic_year
          and coalesce(f.is_active, true) = true
        order by f.updated_at desc nulls last, f.id desc
        limit 1
      ) fs on true
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.forms_get_family_registration_finance_catalog_v3(text) to authenticated, anon;

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
  is_active
)
select
  m.class_id,
  round((m.annual_fee_default / 9.0)::numeric, 2) as monthly_fee,
  m.annual_fee_default,
  m.annual_fee_default,
  'USD',
  '2026-2027',
  true
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

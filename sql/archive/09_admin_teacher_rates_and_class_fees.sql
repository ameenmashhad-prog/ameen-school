-- =============================================================
-- مدارس أمين الرضا (ع) — إعدادات المدير السرية
-- سعر حصة كل معلمة + الرسوم السنوية لكل صف
-- =============================================================

create extension if not exists pgcrypto;

-- 1) جدول الرسوم السنوية لكل صف إن لم يكن موجوداً
create table if not exists public.fee_structures (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  monthly_fee numeric not null default 0,
  currency text not null default 'USD',
  academic_year text not null default '2026-2027',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(class_id, academic_year)
);

alter table public.fee_structures add column if not exists monthly_fee numeric not null default 0;
alter table public.fee_structures add column if not exists amount numeric not null default 0;
alter table public.fee_structures add column if not exists annual_fee numeric;

alter table public.fee_structures add column if not exists currency text not null default 'USD';
alter table public.fee_structures add column if not exists academic_year text not null default '2026-2027';
alter table public.fee_structures add column if not exists updated_at timestamptz not null default now();


-- مزامنة العمود القديم amount مع monthly_fee لتجنب not-null constraints في النسخ القديمة.
update public.fee_structures
set annual_fee = coalesce(annual_fee, nullif(monthly_fee,0) * 9, amount, 0),
    amount = coalesce(annual_fee, amount, nullif(monthly_fee,0) * 9, 0),
    monthly_fee = case
      when monthly_fee is null or monthly_fee = 0 then round((coalesce(annual_fee, amount, 0) / 9.0)::numeric, 2)
      else monthly_fee
    end
where amount is null or monthly_fee is null or annual_fee is null or annual_fee = 0;

-- إذا الجدول قديم وفيه فهرس مختلف، لا نجبر unique إذا فيه تكرارات.
do $$ begin
  begin
    create unique index if not exists uq_fee_structures_class_year
      on public.fee_structures(class_id, academic_year);
  exception when others then
    raise notice 'تعذر إنشاء unique على fee_structures بسبب تكرارات حالية: %', sqlerrm;
  end;
end $$;

-- 2) جدول سعر الحصة للمعلمة إن لم يكن موجوداً
create table if not exists public.teacher_payroll_rules (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid null references public.users(id) on delete cascade,
  currency text not null default 'USD',
  amount_per_verified_session numeric not null default 0,
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.teacher_payroll_rules add column if not exists updated_at timestamptz not null default now();

-- قاعدة واحدة نشطة لكل معلمة، وقاعدة عامة واحدة teacher_id is null إن أردتِ.
do $$ begin
  begin
    create unique index if not exists uq_teacher_payroll_rules_teacher_active
      on public.teacher_payroll_rules(teacher_id)
      where active = true and teacher_id is not null;
  exception when others then
    raise notice 'تعذر إنشاء unique لسعر المعلمة بسبب تكرارات حالية: %', sqlerrm;
  end;
  begin
    create unique index if not exists uq_teacher_payroll_rules_global_active
      on public.teacher_payroll_rules((active))
      where active = true and teacher_id is null;
  exception when others then
    raise notice 'تعذر إنشاء unique للسعر العام بسبب تكرارات حالية: %', sqlerrm;
  end;
end $$;

-- 3) View الرواتب مع أولوية سعر المعلمة الخاص على السعر العام
create or replace view public.v_teacher_payroll_preview
with (security_invoker=true) as
with verified as (
  select
    tal.teacher_id,
    u.name as teacher_name,
    date_trunc('month', cs.session_date)::date as month,
    count(distinct tal.class_session_id) as verified_sessions
  from public.teacher_activity_log tal
  join public.class_sessions cs on cs.id = tal.class_session_id
  left join public.users u on u.id = tal.teacher_id
  group by tal.teacher_id, u.name, date_trunc('month', cs.session_date)::date
)
select
  v.teacher_id,
  v.teacher_name,
  v.month,
  v.verified_sessions,
  coalesce(specific.amount_per_verified_session, global_rule.amount_per_verified_session, 0) as amount_per_session,
  coalesce(specific.currency, global_rule.currency, 'USD') as currency,
  v.verified_sessions * coalesce(specific.amount_per_verified_session, global_rule.amount_per_verified_session, 0) as estimated_amount
from verified v
left join public.teacher_payroll_rules specific
  on specific.teacher_id = v.teacher_id and specific.active = true
left join public.teacher_payroll_rules global_rule
  on global_rule.teacher_id is null and global_rule.active = true;

grant select, insert, update on public.fee_structures to authenticated;
grant select, insert, update on public.teacher_payroll_rules to authenticated;
grant select on public.v_teacher_payroll_preview to authenticated;

-- 4) RLS: المدير فقط يرى ويعدل هذه الإعدادات
alter table public.fee_structures enable row level security;
alter table public.teacher_payroll_rules enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='fee_structures' and policyname='fee_structures_admin_only') then
    create policy fee_structures_admin_only on public.fee_structures
      for all to authenticated
      using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role='admin' or coalesce(u.is_super_admin,false)=true)))
      with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role='admin' or coalesce(u.is_super_admin,false)=true)));
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='teacher_payroll_rules' and policyname='teacher_payroll_rules_admin_only') then
    create policy teacher_payroll_rules_admin_only on public.teacher_payroll_rules
      for all to authenticated
      using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role='admin' or coalesce(u.is_super_admin,false)=true)))
      with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role='admin' or coalesce(u.is_super_admin,false)=true)));
  end if;
end $$;

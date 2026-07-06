-- ============================================================================
-- 132) Hotfix: generation expression is not immutable في الإقفال الشهري
--
-- الخطأ:
-- ERROR: 42P17 generation expression is not immutable
--
-- السبب:
-- استخدام to_char(...) داخل generated column في PostgreSQL.
--
-- الحل:
-- إزالة العمود المولد month_key من الجدول، وحسابه داخل الـ View فقط.
-- هذا الملف آمن للتشغيل سواء تم تنفيذ 131 جزئياً أو لم يتم.
-- ============================================================================

create extension if not exists pgcrypto;

create table if not exists public.finance_monthly_closes (
  id uuid primary key default gen_random_uuid(),
  month_start date not null unique,
  status text not null default 'draft' check (status in ('draft','approved')),
  snapshot jsonb not null,
  notes text,
  closed_by uuid null references public.users(id),
  closed_at timestamptz not null default now(),
  approved_by uuid null references public.users(id),
  approved_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.finance_monthly_closes drop column if exists month_key;

create index if not exists idx_finance_monthly_closes_month on public.finance_monthly_closes(month_start desc);

create or replace view public.v_finance_monthly_closes
with (security_invoker=true) as
select
  c.id,
  c.month_start,
  to_char(c.month_start,'YYYY-MM') as month_key,
  c.status,
  c.notes,
  c.closed_by,
  cu.name as closed_by_name,
  c.closed_at,
  c.approved_by,
  au.name as approved_by_name,
  c.approved_at,
  c.snapshot,
  coalesce((c.snapshot->>'cashIncome')::numeric,0) as cash_income,
  coalesce((c.snapshot->>'payrollTotal')::numeric,0) as payroll_total,
  coalesce((c.snapshot->>'teacherPayroll')::numeric,0) as teacher_payroll,
  coalesce((c.snapshot->>'operatingExpense')::numeric,0) as operating_expense,
  coalesce((c.snapshot->>'operatingSurplus')::numeric,0) as operating_surplus,
  coalesce((c.snapshot->>'overdueAmount')::numeric,0) as overdue_amount,
  coalesce((c.snapshot->>'collectionRate')::numeric,0) as collection_rate,
  c.created_at,
  c.updated_at
from public.finance_monthly_closes c
left join public.users cu on cu.id = c.closed_by
left join public.users au on au.id = c.approved_by;

grant select on public.v_finance_monthly_closes to authenticated;

notify pgrst, 'reload schema';

select 'finance_monthly_close_generated_column_hotfix_ready' as status;

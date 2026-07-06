-- ============================================================================
-- 131) إقفال مالي شهري واعتماد رسمي
-- الهدف:
-- - حفظ Snapshot رسمي للشهر المالي
-- - اعتماد الإقفال من المدير/الإدارة المالية
-- - تثبيت مرجع زمني للمقارنة وعدم الاعتماد على البيانات المتغيرة فقط
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

alter table public.finance_monthly_closes enable row level security;

drop policy if exists finance_monthly_closes_manage on public.finance_monthly_closes;
create policy finance_monthly_closes_manage on public.finance_monthly_closes
  for all to authenticated
  using (public.finance_can_manage())
  with check (public.finance_can_manage());

grant select, insert, update on public.finance_monthly_closes to authenticated;

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

create or replace function public.close_finance_month(
  p_month text,
  p_notes text default null,
  p_approve boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  m date;
  snap jsonb;
  cid uuid;
  actor uuid := auth.uid();
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية الإقفال المالي');
  end if;

  if coalesce(trim(p_month),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'الشهر مطلوب بصيغة YYYY-MM');
  end if;

  m := to_date(p_month || '-01', 'YYYY-MM-DD');
  snap := public.finance_growth_month_snapshot(m);

  insert into public.finance_monthly_closes(
    month_start, status, snapshot, notes, closed_by, closed_at, approved_by, approved_at
  ) values (
    m,
    case when p_approve then 'approved' else 'draft' end,
    snap,
    nullif(trim(p_notes),''),
    actor,
    now(),
    case when p_approve then actor else null end,
    case when p_approve then now() else null end
  )
  on conflict (month_start) do update set
    status = case when p_approve then 'approved' else excluded.status end,
    snapshot = excluded.snapshot,
    notes = excluded.notes,
    closed_by = excluded.closed_by,
    closed_at = excluded.closed_at,
    approved_by = case when p_approve then actor else public.finance_monthly_closes.approved_by end,
    approved_at = case when p_approve then now() else public.finance_monthly_closes.approved_at end,
    updated_at = now()
  returning id into cid;

  return jsonb_build_object(
    'ok', true,
    'message', case when p_approve then 'تم حفظ واعتماد الإقفال الشهري' else 'تم حفظ الإقفال الشهري كمسودة' end,
    'close_id', cid,
    'month', to_char(m,'YYYY-MM'),
    'status', case when p_approve then 'approved' else 'draft' end,
    'snapshot', snap
  );
end;
$$;

grant execute on function public.close_finance_month(text,text,boolean) to authenticated;

create or replace function public.finance_monthly_close_health_check()
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
    'close_table', to_regclass('public.finance_monthly_closes') is not null,
    'close_view', to_regclass('public.v_finance_monthly_closes') is not null,
    'close_rpc', to_regprocedure('public.close_finance_month(text,text,boolean)') is not null,
    'growth_snapshot_rpc', to_regprocedure('public.finance_growth_month_snapshot(date)') is not null,
    'count_closes', (select count(*) from public.finance_monthly_closes)
  );
end;
$$;

grant execute on function public.finance_monthly_close_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.finance_monthly_close_health_check() as finance_monthly_close_health;

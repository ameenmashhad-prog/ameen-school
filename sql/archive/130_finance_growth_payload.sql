-- ============================================================================
-- 130) Payload موحد للوحة نمو المؤسسة مالياً
-- يجمع الدخل + المصروف + رواتب HR + أجور المعلمين + المشتريات + المتأخرات
-- مع اتجاه 6 أشهر وتوقع أولي للشهر القادم.
-- ============================================================================

create or replace function public.finance_growth_month_snapshot(
  p_month date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  m date := date_trunc('month', coalesce(p_month, current_date))::date;
  y int := extract(year from date_trunc('month', coalesce(p_month, current_date)))::int;
  mo int := extract(month from date_trunc('month', coalesce(p_month, current_date)))::int;
  m_end date := (date_trunc('month', coalesce(p_month, current_date)) + interval '1 month - 1 day')::date;
  cash_income numeric := 0;
  non_salary_expense numeric := 0;
  hr_payroll numeric := 0;
  teacher_payroll numeric := 0;
  teacher_penalty_units numeric := 0;
  impacted_teachers int := 0;
  payroll_total numeric := 0;
  operating_expense numeric := 0;
  operating_surplus numeric := 0;
  procurement_committed numeric := 0;
  procurement_received numeric := 0;
  dues_this_month numeric := 0;
  overdue_amount numeric := 0;
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية عرض نمو المؤسسة مالياً');
  end if;

  select coalesce(sum(coalesce(amount_usd, amount)), 0)
    into cash_income
  from public.fee_payments
  where payment_date between m and m_end;

  if to_regclass('public.v_finance_expenses_detailed') is not null then
    select coalesce(sum(amount_usd), 0)
      into non_salary_expense
    from public.v_finance_expenses_detailed
    where payment_date between m and m_end;
  end if;

  if to_regclass('public.v_hr_payroll_detailed') is not null then
    select coalesce(sum(net_salary), 0)
      into hr_payroll
    from public.v_hr_payroll_detailed
    where payroll_year = y and payroll_month = mo;
  end if;

  if to_regclass('public.v_teacher_payroll_preview') is not null then
    select
      coalesce(sum(estimated_amount), 0),
      coalesce(sum(coalesce(penalty_session_units,0)), 0),
      count(distinct teacher_id) filter (where coalesce(penalty_session_units,0) > 0)
    into teacher_payroll, teacher_penalty_units, impacted_teachers
    from public.v_teacher_payroll_preview
    where month = m;
  end if;

  payroll_total := coalesce(hr_payroll,0) + coalesce(teacher_payroll,0);
  operating_expense := coalesce(non_salary_expense,0) + coalesce(payroll_total,0);
  operating_surplus := coalesce(cash_income,0) - coalesce(operating_expense,0);

  if to_regclass('public.v_purchase_requests_detailed') is not null then
    select coalesce(sum(total_estimated), 0)
      into procurement_committed
    from public.v_purchase_requests_detailed
    where coalesce(approved_at::date, created_at::date) between m and m_end;

    select coalesce(sum(total_estimated), 0)
      into procurement_received
    from public.v_purchase_requests_detailed
    where status = 'received'
      and coalesce(received_at::date, updated_at::date, created_at::date) between m and m_end;
  end if;

  select coalesce(sum(amount_due), 0)
    into dues_this_month
  from public.student_installments
  where due_date between m and m_end;

  select coalesce(sum(amount_due - coalesce(amount_paid,0)), 0)
    into overdue_amount
  from public.student_installments
  where due_date < current_date
    and coalesce(amount_paid,0) < amount_due;

  return jsonb_build_object(
    'ok', true,
    'month', to_char(m, 'YYYY-MM'),
    'cashIncome', cash_income,
    'nonSalaryExpense', non_salary_expense,
    'hrPayroll', hr_payroll,
    'teacherPayroll', teacher_payroll,
    'teacherPenaltyUnits', teacher_penalty_units,
    'impactedTeachers', impacted_teachers,
    'payrollTotal', payroll_total,
    'operatingExpense', operating_expense,
    'operatingSurplus', operating_surplus,
    'procurementCommitted', procurement_committed,
    'procurementReceived', procurement_received,
    'duesThisMonth', dues_this_month,
    'overdueAmount', overdue_amount,
    'payrollRatio', case when cash_income > 0 then round((payroll_total / cash_income) * 100) else 0 end,
    'teacherPayrollRatio', case when cash_income > 0 then round((teacher_payroll / cash_income) * 100) else 0 end,
    'hrPayrollRatio', case when cash_income > 0 then round((hr_payroll / cash_income) * 100) else 0 end,
    'expenseRatio', case when cash_income > 0 then round((operating_expense / cash_income) * 100) else 0 end,
    'procurementRatio', case when cash_income > 0 then round((procurement_committed / cash_income) * 100) else 0 end,
    'collectionRate', case when dues_this_month > 0 then round((cash_income / dues_this_month) * 100) else 0 end
  );
end;
$$;

grant execute on function public.finance_growth_month_snapshot(date) to authenticated;

create or replace function public.get_finance_growth_payload(
  p_month text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  base_month date;
  trend jsonb := '[]'::jsonb;
  stats jsonb;
  previous_stats jsonb;
  forecast jsonb := '{}'::jsonb;
begin
  if coalesce(p_month,'') <> '' then
    base_month := to_date(p_month || '-01', 'YYYY-MM-DD');
  else
    base_month := date_trunc('month', current_date)::date;
  end if;

  stats := public.finance_growth_month_snapshot(base_month);
  previous_stats := public.finance_growth_month_snapshot((base_month - interval '1 month')::date);

  with months as (
    select (date_trunc('month', base_month) - (g.n || ' months')::interval)::date as month_start
    from generate_series(5,0,-1) as g(n)
  )
  select coalesce(jsonb_agg(public.finance_growth_month_snapshot(month_start) order by month_start), '[]'::jsonb)
    into trend
  from months;

  with recent as (
    select public.finance_growth_month_snapshot((date_trunc('month', base_month) - (g.n || ' months')::interval)::date) as s
    from generate_series(2,0,-1) as g(n)
  )
  select jsonb_build_object(
    'month', to_char((base_month + interval '1 month')::date, 'YYYY-MM'),
    'cashIncome', round(avg((s->>'cashIncome')::numeric), 2),
    'payrollTotal', round(avg((s->>'payrollTotal')::numeric), 2),
    'operatingExpense', round(avg((s->>'operatingExpense')::numeric), 2),
    'procurementCommitted', round(avg((s->>'procurementCommitted')::numeric), 2),
    'operatingSurplus', round(avg((s->>'cashIncome')::numeric), 2) - round(avg((s->>'operatingExpense')::numeric), 2)
  )
  into forecast
  from recent;

  return jsonb_build_object(
    'ok', true,
    'month', to_char(base_month, 'YYYY-MM'),
    'stats', stats,
    'previous', previous_stats,
    'trend_6_months', trend,
    'forecast_next_month', forecast
  );
end;
$$;

grant execute on function public.get_finance_growth_payload(text) to authenticated;

create or replace function public.finance_growth_payload_health_check()
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
    'month_snapshot_rpc', to_regprocedure('public.finance_growth_month_snapshot(date)') is not null,
    'growth_payload_rpc', to_regprocedure('public.get_finance_growth_payload(text)') is not null,
    'teacher_payroll_view', to_regclass('public.v_teacher_payroll_preview') is not null,
    'hr_payroll_view', to_regclass('public.v_hr_payroll_detailed') is not null,
    'purchase_requests_view', to_regclass('public.v_purchase_requests_detailed') is not null,
    'expenses_view', to_regclass('public.v_finance_expenses_detailed') is not null
  );
end;
$$;

grant execute on function public.finance_growth_payload_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.finance_growth_payload_health_check() as finance_growth_payload_health;

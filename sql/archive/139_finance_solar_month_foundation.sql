-- ============================================================================
-- 139) اعتماد الشهر الشمسي كأساس مالي + إقفال ونمو مالي متوافقان معه
--
-- الهدف:
-- - جعل مرجع الشهر المالي في لوحات النمو والإقفال شهرًا شمسيًا (Persian/Solar).
-- - إبقاء التاريخ الميلادي تابعاً ومرجعاً فنياً للتخزين والنطاق الزمني.
-- - احتساب أجور المعلمين داخل الشهر الشمسي الفعلي حتى لو قطع شهرين ميلاديين.
-- - إبقاء التوافق الخلفي مع الإدخال القديم لو أرسل الواجهة شهراً ميلادياً YYYY-MM.
-- ============================================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) Bootstrap سريع لوظائف التقويم الشمسي
-- بعض البيئات لا تحتوي دوال smart calendar رغم وجود الجداول المالية.
-- لذلك نجعل الملف self-contained حتى يعمل مباشرة.
-- -------------------------------------------------------------
create or replace function public.calendar_is_gregorian_leap(y int)
returns boolean
language sql
immutable
as $$
  select (y % 4 = 0) and ((y % 100 <> 0) or (y % 400 = 0));
$$;

grant execute on function public.calendar_is_gregorian_leap(int) to authenticated;

create or replace function public.calendar_gregorian_to_solar(p_date date)
returns jsonb
language plpgsql
immutable
as $$
declare
  gy int := extract(year from p_date)::int - 1600;
  gm int := extract(month from p_date)::int - 1;
  gd int := extract(day from p_date)::int - 1;
  gdm int[] := array[31,28,31,30,31,30,31,31,30,31,30,31];
  jdm int[] := array[31,31,31,31,31,31,30,30,30,30,30,29];
  g_day_no int;
  j_day_no int;
  j_np int;
  jy int;
  jm int := 1;
  jd int;
  i int;
begin
  g_day_no := 365*gy + floor((gy+3)/4)::int - floor((gy+99)/100)::int + floor((gy+399)/400)::int;
  for i in 0..gm-1 loop
    g_day_no := g_day_no + gdm[i+1];
  end loop;
  if gm > 1 and public.calendar_is_gregorian_leap(gy+1600) then
    g_day_no := g_day_no + 1;
  end if;
  g_day_no := g_day_no + gd;

  j_day_no := g_day_no - 79;
  j_np := floor(j_day_no / 12053)::int;
  j_day_no := j_day_no % 12053;
  jy := 979 + 33*j_np + 4*floor(j_day_no/1461)::int;
  j_day_no := j_day_no % 1461;
  if j_day_no >= 366 then
    jy := jy + floor((j_day_no - 1)/365)::int;
    j_day_no := (j_day_no - 1) % 365;
  end if;

  for i in 1..11 loop
    if j_day_no >= jdm[i] then
      j_day_no := j_day_no - jdm[i];
      jm := jm + 1;
    else
      exit;
    end if;
  end loop;
  jd := j_day_no + 1;

  return jsonb_build_object('year',jy,'month',jm,'day',jd,'text',jy||'/'||lpad(jm::text,2,'0')||'/'||lpad(jd::text,2,'0'));
end;
$$;

grant execute on function public.calendar_gregorian_to_solar(date) to authenticated;

create or replace function public.calendar_solar_to_gregorian(jy int, jm int, jd int)
returns date
language plpgsql
immutable
as $$
declare
  j_y int := jy + 1595;
  days int;
  gy int;
  gd int;
  sal_a int[];
  gm int := 1;
  i int;
begin
  days := -355668 + (365*j_y) + floor(j_y/33)::int*8 + floor(((j_y % 33)+3)/4)::int + jd + case when jm < 7 then (jm-1)*31 else ((jm-7)*30)+186 end;
  gy := 400 * floor(days/146097)::int;
  days := days % 146097;
  if days > 36524 then
    gy := gy + 100 * floor((days-1)/36524)::int;
    days := (days-1) % 36524;
    if days >= 365 then days := days + 1; end if;
  end if;
  gy := gy + 4 * floor(days/1461)::int;
  days := days % 1461;
  if days > 365 then
    gy := gy + floor((days-1)/365)::int;
    days := (days-1) % 365;
  end if;
  gd := days + 1;
  sal_a := array[31, case when public.calendar_is_gregorian_leap(gy) then 29 else 28 end, 31,30,31,30,31,31,30,31,30,31];
  for i in 1..12 loop
    if gd > sal_a[i] then
      gd := gd - sal_a[i];
      gm := gm + 1;
    else
      exit;
    end if;
  end loop;
  return make_date(gy, gm, gd);
end;
$$;

grant execute on function public.calendar_solar_to_gregorian(int,int,int) to authenticated;

-- -------------------------------------------------------------
-- 1) أدوات مساعدة للشهر الشمسي
-- -------------------------------------------------------------
create or replace function public.finance_solar_month_key_from_date(p_date date)
returns text
language sql
immutable
as $$
  select
    (public.calendar_gregorian_to_solar(p_date)->>'year') || '-' ||
    lpad((public.calendar_gregorian_to_solar(p_date)->>'month'), 2, '0');
$$;

grant execute on function public.finance_solar_month_key_from_date(date) to authenticated;

create or replace function public.finance_solar_month_meta(p_month text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  raw text := nullif(trim(coalesce(p_month,'')), '');
  sol jsonb;
  sy int;
  sm int;
  next_sy int;
  next_sm int;
  start_date date;
  next_start date;
  end_date date;
  month_name text;
begin
  if raw is null then
    sol := public.calendar_gregorian_to_solar(current_date);
    sy := (sol->>'year')::int;
    sm := (sol->>'month')::int;
  elsif raw ~ '^[0-9]{4}-[0-9]{2}$' then
    if split_part(raw,'-',1)::int > 1700 then
      sol := public.calendar_gregorian_to_solar(to_date(raw || '-01', 'YYYY-MM-DD'));
      sy := (sol->>'year')::int;
      sm := (sol->>'month')::int;
    else
      sy := split_part(raw,'-',1)::int;
      sm := split_part(raw,'-',2)::int;
    end if;
  else
    raise exception 'month must be YYYY-MM';
  end if;

  if sm < 1 or sm > 12 then
    raise exception 'invalid solar month: %', sm;
  end if;

  next_sy := sy + case when sm = 12 then 1 else 0 end;
  next_sm := case when sm = 12 then 1 else sm + 1 end;

  start_date := public.calendar_solar_to_gregorian(sy, sm, 1);
  next_start := public.calendar_solar_to_gregorian(next_sy, next_sm, 1);
  end_date := next_start - 1;

  month_name := case sm
    when 1 then 'فروردين'
    when 2 then 'أرديبهشت'
    when 3 then 'خرداد'
    when 4 then 'تير'
    when 5 then 'مرداد'
    when 6 then 'شهريور'
    when 7 then 'مهر'
    when 8 then 'آبان'
    when 9 then 'آذر'
    when 10 then 'دي'
    when 11 then 'بهمن'
    else 'اسفند'
  end;

  return jsonb_build_object(
    'solar_year', sy,
    'solar_month', sm,
    'solar_key', sy || '-' || lpad(sm::text,2,'0'),
    'solar_label', month_name || ' ' || sy,
    'start_date', start_date,
    'end_date', end_date,
    'gregorian_start_month', to_char(start_date,'YYYY-MM'),
    'gregorian_end_month', to_char(end_date,'YYYY-MM'),
    'gregorian_range', to_char(start_date,'YYYY-MM-DD') || ' → ' || to_char(end_date,'YYYY-MM-DD')
  );
end;
$$;

grant execute on function public.finance_solar_month_meta(text) to authenticated;

create or replace function public.finance_solar_month_start(p_month text default null)
returns date
language sql
stable
as $$
  select (public.finance_solar_month_meta(p_month)->>'start_date')::date;
$$;

grant execute on function public.finance_solar_month_start(text) to authenticated;

create or replace function public.finance_solar_month_shift(p_month text, p_offset int default 0)
returns text
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  meta jsonb := public.finance_solar_month_meta(p_month);
  sy int := (meta->>'solar_year')::int;
  sm int := (meta->>'solar_month')::int;
  total int;
  ny int;
  nm int;
begin
  total := (sy * 12) + (sm - 1) + coalesce(p_offset,0);
  ny := total / 12;
  nm := mod(total, 12) + 1;
  return ny || '-' || lpad(nm::text,2,'0');
end;
$$;

grant execute on function public.finance_solar_month_shift(text,int) to authenticated;

-- -------------------------------------------------------------
-- 2) إعادة تعريف Snapshot النمو المالي ليعتمد الشهر الشمسي فعلياً
-- -------------------------------------------------------------
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
  ref_date date := coalesce(p_month, current_date);
  month_key text := public.finance_solar_month_key_from_date(ref_date);
  meta jsonb := public.finance_solar_month_meta(public.finance_solar_month_key_from_date(ref_date));
  m date := (meta->>'start_date')::date;
  m_end date := (meta->>'end_date')::date;
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
  collected_against_due_month numeric := 0;
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
    where coalesce(updated_at::date, created_at::date) between m and m_end;
  end if;

  if to_regclass('public.v_teacher_payroll_daily') is not null then
    with daily as (
      select
        d.teacher_id,
        max(d.teacher_name) as teacher_name,
        round(sum(d.earned_session_units), 2) as gross_verified_sessions,
        max(coalesce(d.amount_per_session,0)) as amount_per_session
      from public.v_teacher_payroll_daily d
      where d.session_date between m and m_end
      group by d.teacher_id
    ), penalties as (
      select
        z.teacher_id,
        round(sum(floor(z.late_events::numeric / nullif(z.repeat_count,0)) * z.penalty_session_units), 2) as penalty_session_units
      from (
        select
          e.teacher_id,
          r.repeat_count,
          r.penalty_session_units,
          count(*) as late_events
        from public.v_teacher_lateness_events e
        join public.teacher_lateness_rules r
          on r.is_active = true
         and e.late_status = 'late'
         and e.late_minutes >= r.min_late_minutes
         and (r.max_late_minutes is null or e.late_minutes <= r.max_late_minutes)
        where e.session_date between m and m_end
        group by e.teacher_id, r.id, r.repeat_count, r.penalty_session_units
      ) z
      group by z.teacher_id
    ), extras as (
      select
        x.teacher_id,
        round(sum(x.extra_amount), 2) as extra_session_amount
      from public.v_teacher_extra_sessions_detailed x
      where x.session_date between m and m_end
      group by x.teacher_id
    ), adj as (
      select
        a.teacher_id,
        round(sum(case when a.adjustment_type='bonus' then a.amount_usd else 0 end),2) as bonus_amount,
        round(sum(case when a.adjustment_type='deduction' then a.amount_usd else 0 end),2) as deduction_amount
      from public.teacher_payroll_adjustments a
      where a.is_active = true
        and public.finance_solar_month_key_from_date(a.effective_month) = month_key
      group by a.teacher_id
    )
    select
      coalesce(sum(round(
        greatest(0, d.gross_verified_sessions - coalesce(p.penalty_session_units,0)) * d.amount_per_session
        + coalesce(x.extra_session_amount,0)
        + coalesce(a.bonus_amount,0)
        - coalesce(a.deduction_amount,0)
      , 2)), 0),
      coalesce(sum(coalesce(p.penalty_session_units,0)), 0),
      count(*) filter (where coalesce(p.penalty_session_units,0) > 0)
    into teacher_payroll, teacher_penalty_units, impacted_teachers
    from daily d
    left join penalties p on p.teacher_id = d.teacher_id
    left join extras x on x.teacher_id = d.teacher_id
    left join adj a on a.teacher_id = d.teacher_id;
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

  select coalesce(sum(least(coalesce(amount_paid,0), amount_due)), 0)
    into collected_against_due_month
  from public.student_installments
  where due_date between m and m_end;

  select coalesce(sum(amount_due - coalesce(amount_paid,0)), 0)
    into overdue_amount
  from public.student_installments
  where due_date < current_date
    and coalesce(amount_paid,0) < amount_due;

  return jsonb_build_object(
    'ok', true,
    'month', month_key,
    'monthLabel', meta->>'solar_label',
    'monthStart', m,
    'monthEnd', m_end,
    'gregorianRange', meta->>'gregorian_range',
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
    'collectedAgainstDueMonth', collected_against_due_month,
    'overdueAmount', overdue_amount,
    'payrollRatio', case when cash_income > 0 then least(9999, round((payroll_total / cash_income) * 100)) else 0 end,
    'teacherPayrollRatio', case when cash_income > 0 then least(9999, round((teacher_payroll / cash_income) * 100)) else 0 end,
    'hrPayrollRatio', case when cash_income > 0 then least(9999, round((hr_payroll / cash_income) * 100)) else 0 end,
    'expenseRatio', case when cash_income > 0 then least(9999, round((operating_expense / cash_income) * 100)) else 0 end,
    'procurementRatio', case when cash_income > 0 then least(9999, round((procurement_committed / cash_income) * 100)) else 0 end,
    'collectionRate', case when dues_this_month > 0 then least(100, round((collected_against_due_month / dues_this_month) * 100)) else 0 end
  );
end;
$$;

grant execute on function public.finance_growth_month_snapshot(date) to authenticated;

-- -------------------------------------------------------------
-- 3) Payload موحد مبني على سلسلة أشهر شمسية
-- -------------------------------------------------------------
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
  base_key text := coalesce(nullif(trim(coalesce(p_month,'')),''), public.finance_solar_month_key_from_date(current_date));
  base_month date := public.finance_solar_month_start(base_key);
  trend jsonb := '[]'::jsonb;
  stats jsonb;
  previous_stats jsonb;
  forecast jsonb := '{}'::jsonb;
begin
  stats := public.finance_growth_month_snapshot(base_month);
  previous_stats := public.finance_growth_month_snapshot(public.finance_solar_month_start(public.finance_solar_month_shift(base_key, -1)));

  with months as (
    select public.finance_solar_month_start(public.finance_solar_month_shift(base_key, -g.n)) as month_start
    from generate_series(5,0,-1) as g(n)
  )
  select coalesce(jsonb_agg(public.finance_growth_month_snapshot(month_start) order by month_start), '[]'::jsonb)
    into trend
  from months;

  with recent as (
    select public.finance_growth_month_snapshot(public.finance_solar_month_start(public.finance_solar_month_shift(base_key, -g.n))) as s
    from generate_series(2,0,-1) as g(n)
  )
  select jsonb_build_object(
    'month', public.finance_solar_month_shift(base_key, 1),
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
    'month', base_key,
    'month_meta', public.finance_solar_month_meta(base_key),
    'stats', stats,
    'previous', previous_stats,
    'trend_6_months', trend,
    'forecast_next_month', forecast
  );
end;
$$;

grant execute on function public.get_finance_growth_payload(text) to authenticated;

-- -------------------------------------------------------------
-- 4) View / RPC الإقفال الشهري بالمرجع الشمسي
-- -------------------------------------------------------------
drop view if exists public.v_finance_monthly_closes;

create or replace view public.v_finance_monthly_closes
with (security_invoker=true) as
select
  c.id,
  c.month_start,
  (public.finance_solar_month_meta(to_char(c.month_start,'YYYY-MM'))->>'end_date')::date as month_end,
  public.finance_solar_month_meta(to_char(c.month_start,'YYYY-MM'))->>'solar_key' as month_key,
  public.finance_solar_month_meta(to_char(c.month_start,'YYYY-MM'))->>'solar_label' as month_label,
  public.finance_solar_month_meta(to_char(c.month_start,'YYYY-MM'))->>'gregorian_range' as gregorian_range,
  public.finance_solar_month_meta(to_char(c.month_start,'YYYY-MM'))->>'gregorian_start_month' as gregorian_start_month,
  public.finance_solar_month_meta(to_char(c.month_start,'YYYY-MM'))->>'gregorian_end_month' as gregorian_end_month,
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
  meta jsonb;
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

  meta := public.finance_solar_month_meta(p_month);
  m := (meta->>'start_date')::date;
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
    'month', meta->>'solar_key',
    'monthLabel', meta->>'solar_label',
    'gregorianRange', meta->>'gregorian_range',
    'status', case when p_approve then 'approved' else 'draft' end,
    'snapshot', snap
  );
end;
$$;

grant execute on function public.close_finance_month(text,text,boolean) to authenticated;

notify pgrst, 'reload schema';

select public.finance_growth_payload_health_check() as finance_growth_payload_health;
select public.finance_monthly_close_health_check() as finance_monthly_close_health;

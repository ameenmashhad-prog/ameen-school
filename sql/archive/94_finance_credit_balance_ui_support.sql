-- =============================================================
-- مدارس أمين الرضا (ع) — دعم عرض الرصيد الدائن في التقارير والواجهات
-- يضيف credit_balance إلى Views المالية التنفيذية والتحصيل.
-- آمن وتراكمي، لا يغير المدفوعات.
-- =============================================================

create extension if not exists pgcrypto;

alter table public.student_fees add column if not exists credit_balance numeric not null default 0;
alter table public.student_fees add column if not exists credit_notes text;

-- -------------------------------------------------------------
-- 1) تحديث View أرصدة الطلاب التنفيذية — إضافة credit_balance في نهاية الأعمدة
-- -------------------------------------------------------------
create or replace view public.v_finance_exec_student_balances
with (security_invoker=true) as
select
  sf.id as student_fee_id,
  sf.student_id,
  s.name as student_name,
  s.father_name,
  s.last_name,
  s.parent_id,
  pu.name as parent_name,
  s.class_id,
  c.name as class_name,
  sf.academic_year,
  coalesce(sf.base_amount,0) as base_amount,
  coalesce(sf.discount_amount,0) as discount_amount,
  coalesce(sf.net_amount, sf.base_amount, 0) as net_amount,
  coalesce(sf.total_paid,0) as total_paid,
  greatest(coalesce(sf.net_amount, sf.base_amount,0) - coalesce(sf.total_paid,0), 0) as remaining_amount,
  sf.status,
  coalesce(inst.overdue_installments,0) as overdue_installments,
  coalesce(inst.next_due_date, null) as next_due_date,
  sf.created_at,
  sf.updated_at,
  coalesce(sf.credit_balance,0) as credit_balance
from public.student_fees sf
join public.students s on s.id = sf.student_id
left join public.classes c on c.id = s.class_id
left join public.users pu on pu.id = s.parent_id
left join lateral (
  select
    count(*) filter (where coalesce(si.amount_paid,0) < coalesce(si.amount_due,0) and si.due_date < current_date) as overdue_installments,
    min(si.due_date) filter (where coalesce(si.amount_paid,0) < coalesce(si.amount_due,0)) as next_due_date
  from public.student_installments si
  where si.student_fee_id = sf.id
) inst on true
where public.finance_can_manage()
   or s.user_id = auth.uid()
   or s.parent_id = auth.uid();

grant select on public.v_finance_exec_student_balances to authenticated;

-- -------------------------------------------------------------
-- 2) تحديث ملخص الصفوف — إضافة total_credit في نهاية الأعمدة
-- -------------------------------------------------------------
create or replace view public.v_finance_exec_class_summary
with (security_invoker=true) as
select
  class_id,
  class_name,
  count(*) as fee_files,
  count(distinct student_id) as students_count,
  coalesce(sum(net_amount),0) as total_due,
  coalesce(sum(total_paid),0) as total_paid,
  coalesce(sum(remaining_amount),0) as total_remaining,
  count(*) filter (where remaining_amount <= 0) as paid_files,
  count(*) filter (where remaining_amount > 0 and total_paid > 0) as partial_files,
  count(*) filter (where total_paid <= 0) as unpaid_files,
  count(*) filter (where overdue_installments > 0) as overdue_files,
  coalesce(sum(credit_balance),0) as total_credit
from public.v_finance_exec_student_balances
group by class_id, class_name;

grant select on public.v_finance_exec_class_summary to authenticated;

-- -------------------------------------------------------------
-- 3) تحديث View التحصيل — إضافة credit_balance في نهاية الأعمدة
-- -------------------------------------------------------------
create or replace view public.v_finance_collection_students
with (security_invoker=true) as
select
  s.id as student_id,
  s.name as student_name,
  s.father_name,
  s.last_name,
  s.parent_id,
  p.name as parent_name,
  p.email as parent_email,
  s.class_id,
  c.name as class_name,
  sf.id as student_fee_id,
  sf.academic_year,
  coalesce(sf.net_amount,sf.base_amount,0) as net_amount,
  coalesce(sf.total_paid,0) as total_paid,
  greatest(coalesce(sf.net_amount,sf.base_amount,0)-coalesce(sf.total_paid,0),0) as remaining_amount,
  coalesce(ov.overdue_amount,0) as overdue_amount,
  coalesce(ov.overdue_installments,0) as overdue_installments,
  ov.oldest_due_date,
  case when ov.oldest_due_date is not null then current_date - ov.oldest_due_date else 0 end as max_days_late,
  coalesce(fu.open_followups,0) as open_followups,
  fu.last_followup_at,
  fu.next_promised_date,
  coalesce(sf.credit_balance,0) as credit_balance
from public.student_fees sf
join public.students s on s.id = sf.student_id
left join public.users p on p.id = s.parent_id
left join public.classes c on c.id = s.class_id
left join lateral (
  select
    count(*) as overdue_installments,
    coalesce(sum(greatest(coalesce(si.amount_due,0)-coalesce(si.amount_paid,0),0)),0) as overdue_amount,
    min(si.due_date) as oldest_due_date
  from public.student_installments si
  where si.student_fee_id = sf.id
    and coalesce(si.amount_paid,0) < coalesce(si.amount_due,0)
    and si.due_date < current_date
) ov on true
left join lateral (
  select
    count(*) filter (where ff.status='open') as open_followups,
    max(ff.created_at) as last_followup_at,
    min(ff.promised_date) filter (where ff.status='open' and ff.promised_date >= current_date) as next_promised_date
  from public.finance_followups ff
  where ff.student_id = s.id
) fu on true
where (public.finance_can_manage() or s.user_id = auth.uid() or s.parent_id = auth.uid());

grant select on public.v_finance_collection_students to authenticated;

-- -------------------------------------------------------------
-- 4) تحديث Payload التنفيذي ليضيف total_credit_balance
-- -------------------------------------------------------------
create or replace function public.get_finance_executive_payload(
  p_from date default date_trunc('month', current_date)::date,
  p_to date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  d1 date := coalesce(p_from, date_trunc('month', current_date)::date);
  d2 date := coalesce(p_to, current_date);
  stats jsonb;
  class_summary jsonb;
  receivers jsonb;
  methods jsonb;
  overdue jsonb;
  recent jsonb;
  daily jsonb;
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية عرض المركز المالي التنفيذي');
  end if;

  if d2 < d1 then d2 := d1; end if;

  select jsonb_build_object(
    'from', d1,
    'to', d2,
    'students_with_fees', count(distinct student_id),
    'fee_files', count(*),
    'total_due', coalesce(sum(net_amount),0),
    'total_paid_all_time', coalesce(sum(total_paid),0),
    'total_credit_balance', coalesce(sum(credit_balance),0),
    'total_remaining', coalesce(sum(remaining_amount),0),
    'paid_files', count(*) filter (where remaining_amount <= 0),
    'partial_files', count(*) filter (where remaining_amount > 0 and total_paid > 0),
    'unpaid_files', count(*) filter (where total_paid <= 0),
    'overdue_files', count(*) filter (where overdue_installments > 0),
    'period_payments_count', (select count(*) from public.v_finance_exec_payments p where p.payment_date between d1 and d2 and coalesce(p.voided,false)=false),
    'period_collected_usd', (select coalesce(sum(p.amount_usd),0) from public.v_finance_exec_payments p where p.payment_date between d1 and d2 and coalesce(p.voided,false)=false),
    'period_collected_irr', (select coalesce(sum(p.amount_irr),0) from public.v_finance_exec_payments p where p.payment_date between d1 and d2 and coalesce(p.voided,false)=false),
    'voided_count_period', (select count(*) from public.v_finance_exec_payments p where p.payment_date between d1 and d2 and coalesce(p.voided,false)=true)
  )
  into stats
  from public.v_finance_exec_student_balances;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_remaining desc), '[]'::jsonb)
  into class_summary
  from public.v_finance_exec_class_summary x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_usd desc), '[]'::jsonb)
  into receivers
  from (
    select
      receiver_name,
      received_by,
      receiver_role,
      count(*) filter (where coalesce(voided,false)=false) as payments_count,
      count(*) filter (where coalesce(voided,false)=true) as voided_count,
      coalesce(sum(amount_usd) filter (where coalesce(voided,false)=false),0) as total_usd,
      coalesce(sum(amount_irr) filter (where coalesce(voided,false)=false),0) as total_irr
    from public.v_finance_exec_payments
    where payment_date between d1 and d2
    group by receiver_name, received_by, receiver_role
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_usd desc), '[]'::jsonb)
  into methods
  from (
    select
      payment_method,
      count(*) filter (where coalesce(voided,false)=false) as payments_count,
      coalesce(sum(amount_usd) filter (where coalesce(voided,false)=false),0) as total_usd,
      coalesce(sum(amount_irr) filter (where coalesce(voided,false)=false),0) as total_irr
    from public.v_finance_exec_payments
    where payment_date between d1 and d2
    group by payment_method
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.days_late desc, x.remaining desc), '[]'::jsonb)
  into overdue
  from (select * from public.v_finance_exec_overdue_installments order by days_late desc, remaining desc limit 80) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into recent
  from (select * from public.v_finance_exec_payments where payment_date between d1 and d2 order by created_at desc limit 80) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.payment_date), '[]'::jsonb)
  into daily
  from (
    select payment_date, count(*) filter (where coalesce(voided,false)=false) as payments_count,
           coalesce(sum(amount_usd) filter (where coalesce(voided,false)=false),0) as total_usd,
           coalesce(sum(amount_irr) filter (where coalesce(voided,false)=false),0) as total_irr
    from public.v_finance_exec_payments
    where payment_date between d1 and d2
    group by payment_date
  ) x;

  return jsonb_build_object('ok', true, 'stats', stats, 'class_summary', class_summary, 'receivers', receivers, 'methods', methods, 'overdue', overdue, 'recent_payments', recent, 'daily', daily);
end;
$$;

grant execute on function public.get_finance_executive_payload(date,date) to authenticated;

-- -------------------------------------------------------------
-- 5) فحص
-- -------------------------------------------------------------
create or replace function public.finance_credit_ui_support_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'credit_column', exists(select 1 from information_schema.columns where table_schema='public' and table_name='student_fees' and column_name='credit_balance'),
    'student_balances_has_credit', exists(select 1 from information_schema.columns where table_schema='public' and table_name='v_finance_exec_student_balances' and column_name='credit_balance'),
    'class_summary_has_credit', exists(select 1 from information_schema.columns where table_schema='public' and table_name='v_finance_exec_class_summary' and column_name='total_credit'),
    'collections_has_credit', exists(select 1 from information_schema.columns where table_schema='public' and table_name='v_finance_collection_students' and column_name='credit_balance'),
    'executive_payload_credit', public.get_finance_executive_payload(date_trunc('month',current_date)::date,current_date)->'stats'->'total_credit_balance',
    'credit_files', (select count(*) from public.student_fees where coalesce(credit_balance,0)>0)
  );
end;
$$;

grant execute on function public.finance_credit_ui_support_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_credit_balance_ui_support_ready' as status;

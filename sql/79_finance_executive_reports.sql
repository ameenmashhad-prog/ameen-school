-- =============================================================
-- مدارس أمين الرضا (ع) — المركز المالي التنفيذي
-- تقارير سريعة: إجمالي الرسوم، المحصل، المتبقي، المتأخرات، المستلمين، طرق الدفع.
-- آمن وتراكمي ولا يحذف أي بيانات.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) صلاحيات مالية
-- -------------------------------------------------------------
create or replace function public.current_user_is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (u.role = 'admin' or coalesce(u.is_super_admin,false)=true)
  );
$$;

grant execute on function public.current_user_is_admin() to authenticated;

create or replace function public.finance_can_manage()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.current_user_is_admin()
    or exists(
      select 1 from public.users u
      where u.id = auth.uid()
        and u.role in ('finance','staff','accountant','cashier')
    );
$$;

grant execute on function public.finance_can_manage() to authenticated;

-- -------------------------------------------------------------
-- 1) أعمدة التوافق الأساسية
-- -------------------------------------------------------------
alter table public.fee_payments add column if not exists received_by uuid null references public.users(id) on delete set null;
alter table public.fee_payments add column if not exists receiver_name text;
alter table public.fee_payments add column if not exists receiver_role text;
alter table public.fee_payments add column if not exists voided boolean not null default false;
alter table public.fee_payments add column if not exists void_reason text;
alter table public.fee_payments add column if not exists amount_usd numeric;
alter table public.fee_payments add column if not exists amount_irr numeric;
alter table public.fee_payments add column if not exists payment_method text not null default 'cash';
alter table public.fee_payments add column if not exists payment_date date;
alter table public.fee_payments add column if not exists receipt_number text;
alter table public.fee_payments add column if not exists created_by uuid null references public.users(id);
alter table public.fee_payments add column if not exists created_by_name text;

create index if not exists idx_fee_payments_receiver_date on public.fee_payments(payment_date, received_by, receiver_name);
create index if not exists idx_student_fees_student_status on public.student_fees(student_id, status);
create index if not exists idx_student_installments_due_status on public.student_installments(due_date, status);

-- تعبئة مستلم السجلات القديمة
update public.fee_payments fp
set received_by = coalesce(fp.received_by, fp.created_by),
    receiver_name = coalesce(fp.receiver_name, fp.created_by_name, u.name, u.email, 'غير محدد'),
    receiver_role = coalesce(fp.receiver_role, u.role)
from public.users u
where fp.created_by = u.id
  and (fp.received_by is null or fp.receiver_name is null or fp.receiver_role is null);

update public.fee_payments
set receiver_name = coalesce(receiver_name, created_by_name, 'غير محدد')
where receiver_name is null or receiver_name = '';

-- -------------------------------------------------------------
-- 2) Views تنفيذية بأسماء جديدة لتجنب تعارض أعمدة Views قديمة
-- -------------------------------------------------------------
drop view if exists public.v_finance_exec_payments;
drop view if exists public.v_finance_exec_overdue_installments;
drop view if exists public.v_finance_exec_student_balances;
drop view if exists public.v_finance_exec_class_summary;

create view public.v_finance_exec_student_balances
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
  sf.updated_at
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

create view public.v_finance_exec_class_summary
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
  count(*) filter (where overdue_installments > 0) as overdue_files
from public.v_finance_exec_student_balances
group by class_id, class_name;

grant select on public.v_finance_exec_class_summary to authenticated;

create view public.v_finance_exec_payments
with (security_invoker=true) as
select
  p.id,
  p.student_fee_id,
  p.student_installment_id,
  p.receipt_number,
  coalesce(p.payment_date, p.created_at::date) as payment_date,
  p.created_at,
  p.amount,
  coalesce(p.amount_usd, p.amount,0) as amount_usd,
  coalesce(p.amount_irr,0) as amount_irr,
  p.currency,
  p.payment_method,
  p.transfer_number,
  p.transfer_date,
  p.transfer_source,
  p.payer_name,
  p.payer_relationship,
  p.received_by,
  coalesce(p.receiver_name, rb.name, p.created_by_name, 'غير محدد') as receiver_name,
  coalesce(rb.role, p.receiver_role) as receiver_role,
  p.voided,
  p.void_reason,
  sf.student_id,
  s.name as student_name,
  s.class_id,
  c.name as class_name,
  p.created_by,
  p.created_by_name
from public.fee_payments p
left join public.users rb on rb.id = p.received_by
left join public.student_fees sf on sf.id = p.student_fee_id
left join public.students s on s.id = sf.student_id
left join public.classes c on c.id = s.class_id
where public.finance_can_manage()
   or s.user_id = auth.uid()
   or s.parent_id = auth.uid();

grant select on public.v_finance_exec_payments to authenticated;

create view public.v_finance_exec_overdue_installments
with (security_invoker=true) as
select
  si.id as installment_id,
  si.student_fee_id,
  sf.student_id,
  s.name as student_name,
  s.father_name,
  s.last_name,
  s.parent_id,
  pu.name as parent_name,
  s.class_id,
  c.name as class_name,
  si.installment_number,
  si.due_date,
  coalesce(si.amount_due,0) as amount_due,
  coalesce(si.amount_paid,0) as amount_paid,
  greatest(coalesce(si.amount_due,0)-coalesce(si.amount_paid,0),0) as remaining,
  si.status,
  current_date - si.due_date as days_late
from public.student_installments si
join public.student_fees sf on sf.id = si.student_fee_id
join public.students s on s.id = sf.student_id
left join public.classes c on c.id = s.class_id
left join public.users pu on pu.id = s.parent_id
where coalesce(si.amount_paid,0) < coalesce(si.amount_due,0)
  and si.due_date < current_date
  and (public.finance_can_manage() or s.user_id = auth.uid() or s.parent_id = auth.uid());

grant select on public.v_finance_exec_overdue_installments to authenticated;

-- -------------------------------------------------------------
-- 3) Payload مالي تنفيذي
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
  from (
    select * from public.v_finance_exec_overdue_installments
    order by days_late desc, remaining desc
    limit 80
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into recent
  from (
    select * from public.v_finance_exec_payments
    where payment_date between d1 and d2
    order by created_at desc
    limit 80
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.payment_date), '[]'::jsonb)
  into daily
  from (
    select
      payment_date,
      count(*) filter (where coalesce(voided,false)=false) as payments_count,
      coalesce(sum(amount_usd) filter (where coalesce(voided,false)=false),0) as total_usd,
      coalesce(sum(amount_irr) filter (where coalesce(voided,false)=false),0) as total_irr
    from public.v_finance_exec_payments
    where payment_date between d1 and d2
    group by payment_date
  ) x;

  return jsonb_build_object(
    'ok', true,
    'stats', stats,
    'class_summary', class_summary,
    'receivers', receivers,
    'methods', methods,
    'overdue', overdue,
    'recent_payments', recent,
    'daily', daily
  );
end;
$$;

grant execute on function public.get_finance_executive_payload(date,date) to authenticated;

-- -------------------------------------------------------------
-- 4) فحص
-- -------------------------------------------------------------
create or replace function public.finance_executive_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'student_balances_view', to_regclass('public.v_finance_exec_student_balances') is not null,
    'class_summary_view', to_regclass('public.v_finance_exec_class_summary') is not null,
    'payments_view', to_regclass('public.v_finance_exec_payments') is not null,
    'overdue_view', to_regclass('public.v_finance_exec_overdue_installments') is not null,
    'payload_rpc', to_regprocedure('public.get_finance_executive_payload(date,date)') is not null,
    'sample_stats', case when public.finance_can_manage() then public.get_finance_executive_payload(date_trunc('month',current_date)::date,current_date)->'stats' else '{}'::jsonb end
  );
end;
$$;

grant execute on function public.finance_executive_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_executive_reports_ready' as status;

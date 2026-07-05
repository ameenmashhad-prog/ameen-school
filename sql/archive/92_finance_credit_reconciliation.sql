-- =============================================================
-- مدارس أمين الرضا (ع) — تسوية المدفوعات الزائدة كرصيد دائن Credit
-- آمن: لا يحذف ولا يلغي أي دفعة. يحافظ على كل السجلات.
-- يحل تحذيرات:
-- 1) overpaid_fees
-- 2) fee_total_mismatches
-- عبر إضافة credit_balance إلى student_fees.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) أعمدة الرصيد الدائن والتوافق
-- -------------------------------------------------------------
alter table public.student_fees add column if not exists credit_balance numeric not null default 0;
alter table public.student_fees add column if not exists credit_notes text;
alter table public.student_fees add column if not exists updated_at timestamptz not null default now();

alter table public.fee_payments add column if not exists voided boolean not null default false;
alter table public.fee_payments add column if not exists amount_usd numeric;
alter table public.fee_payments add column if not exists amount numeric;

-- -------------------------------------------------------------
-- 1) معاينة/تنفيذ تسوية كل ملف مالي
-- المبدأ:
-- payments_sum = مجموع الدفعات غير الملغاة
-- total_paid   = min(payments_sum, net_amount)
-- credit       = max(payments_sum - net_amount, 0)
-- -------------------------------------------------------------
create or replace function public.finance_reconcile_overpayments_to_credit(
  p_apply boolean default false,
  p_student_fee_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  preview jsonb;
  updated_count int := 0;
begin
  with calc as (
    select
      sf.id as student_fee_id,
      sf.student_id,
      s.name as student_name,
      s.class_id,
      c.name as class_name,
      coalesce(sf.net_amount, sf.base_amount, sf.gross_amount, 0) as net_amount,
      coalesce(sf.total_paid,0) as old_total_paid,
      coalesce(sf.credit_balance,0) as old_credit_balance,
      coalesce((
        select sum(coalesce(fp.amount_usd, fp.amount, 0))
        from public.fee_payments fp
        where fp.student_fee_id = sf.id
          and coalesce(fp.voided,false)=false
      ),0) as active_payments_sum
    from public.student_fees sf
    left join public.students s on s.id = sf.student_id
    left join public.classes c on c.id = s.class_id
    where p_student_fee_id is null or sf.id = p_student_fee_id
  ), target as (
    select
      *,
      least(active_payments_sum, net_amount) as new_total_paid,
      greatest(active_payments_sum - net_amount, 0) as new_credit_balance,
      case
        when active_payments_sum <= 0 then 'unpaid'
        when active_payments_sum >= net_amount then 'paid'
        else 'partial'
      end as new_status
    from calc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'student_fee_id', student_fee_id,
    'student_id', student_id,
    'student_name', student_name,
    'class_name', class_name,
    'net_amount', net_amount,
    'active_payments_sum', active_payments_sum,
    'old_total_paid', old_total_paid,
    'new_total_paid', new_total_paid,
    'old_credit_balance', old_credit_balance,
    'new_credit_balance', new_credit_balance,
    'new_status', new_status,
    'changed', (old_total_paid is distinct from new_total_paid or old_credit_balance is distinct from new_credit_balance)
  ) order by student_name), '[]'::jsonb)
  into preview
  from target
  where old_total_paid is distinct from new_total_paid
     or old_credit_balance is distinct from new_credit_balance;

  if coalesce(p_apply,false) then
    with calc as (
      select
        sf.id,
        coalesce(sf.net_amount, sf.base_amount, sf.gross_amount, 0) as net_amount,
        coalesce((
          select sum(coalesce(fp.amount_usd, fp.amount, 0))
          from public.fee_payments fp
          where fp.student_fee_id = sf.id
            and coalesce(fp.voided,false)=false
        ),0) as active_payments_sum
      from public.student_fees sf
      where p_student_fee_id is null or sf.id = p_student_fee_id
    ), target as (
      select
        id,
        least(active_payments_sum, net_amount) as new_total_paid,
        greatest(active_payments_sum - net_amount, 0) as new_credit_balance,
        case
          when active_payments_sum <= 0 then 'unpaid'
          when active_payments_sum >= net_amount then 'paid'
          else 'partial'
        end as new_status
      from calc
    )
    update public.student_fees sf
    set total_paid = target.new_total_paid,
        credit_balance = target.new_credit_balance,
        status = target.new_status,
        credit_notes = case when target.new_credit_balance > 0 then 'رصيد دائن ناتج عن مدفوعات زائدة محفوظة كسجل ولا يتم حذفها' else credit_notes end,
        updated_at = now()
    from target
    where sf.id = target.id
      and (
        sf.total_paid is distinct from target.new_total_paid
        or coalesce(sf.credit_balance,0) is distinct from target.new_credit_balance
        or sf.status is distinct from target.new_status
      );

    get diagnostics updated_count = row_count;
  end if;

  return jsonb_build_object(
    'ok', true,
    'apply', coalesce(p_apply,false),
    'changed_count', jsonb_array_length(coalesce(preview,'[]'::jsonb)),
    'updated_count', updated_count,
    'preview', preview,
    'note', 'لا يتم حذف أو إلغاء أي دفعة. المدفوعات الزائدة تحفظ في student_fees.credit_balance كرصد دائن.'
  );
end;
$$;

grant execute on function public.finance_reconcile_overpayments_to_credit(boolean,uuid) to authenticated;

-- -------------------------------------------------------------
-- 2) View للرصيد الدائن
-- -------------------------------------------------------------
drop view if exists public.v_finance_fee_credit_summary;
create view public.v_finance_fee_credit_summary
with (security_invoker=true) as
select
  sf.id as student_fee_id,
  sf.student_id,
  s.name as student_name,
  s.class_id,
  c.name as class_name,
  coalesce(sf.net_amount, sf.base_amount, sf.gross_amount,0) as net_amount,
  coalesce(sf.total_paid,0) as total_paid,
  coalesce(sf.credit_balance,0) as credit_balance,
  greatest(coalesce(sf.net_amount, sf.base_amount, sf.gross_amount,0)-coalesce(sf.total_paid,0),0) as remaining_amount,
  sf.status,
  sf.credit_notes,
  sf.updated_at
from public.student_fees sf
left join public.students s on s.id = sf.student_id
left join public.classes c on c.id = s.class_id
where coalesce(sf.credit_balance,0) > 0;

grant select on public.v_finance_fee_credit_summary to authenticated;

-- -------------------------------------------------------------
-- 3) فحص تسوية محدث يعتبر credit_balance جزءاً من مجموع المدفوعات
-- -------------------------------------------------------------
create or replace function public.finance_final_reconciliation_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  issues jsonb := '[]'::jsonb;
  stats jsonb;
  details jsonb;
  latest_payments jsonb;
  receiver_summary jsonb;
  class_summary jsonb;
  credits jsonb;
  null_due_open int := 0;
  invalid_months int := 0;
  payments_without_receiver int := 0;
  overpaid_fees int := 0;
  overpaid_installments int := 0;
  orphan_payments int := 0;
  fee_total_mismatches int := 0;
  credits_count int := 0;
begin
  select count(*) into null_due_open
  from public.student_installments
  where due_date is null
    and coalesce(amount_due,0) > coalesce(amount_paid,0);

  select count(*) into invalid_months
  from public.student_installments
  where installment_month is not null
    and installment_month not in (9,10,11,12,1,2,3,4,5);

  select count(*) into payments_without_receiver
  from public.fee_payments
  where coalesce(voided,false)=false
    and (receiver_name is null or receiver_name='');

  -- بعد credit_balance لا نعتبر المدفوعات الزائدة مشكلة إذا total_paid نفسه لا يتجاوز net_amount.
  select count(*) into overpaid_fees
  from public.student_fees
  where coalesce(total_paid,0) > coalesce(net_amount,base_amount,gross_amount,0) + 0.01;

  select count(*) into overpaid_installments
  from public.student_installments
  where coalesce(amount_paid,0) > coalesce(amount_due,0) + 0.01;

  select count(*) into orphan_payments
  from public.fee_payments fp
  left join public.student_fees sf on sf.id = fp.student_fee_id
  where fp.student_fee_id is not null
    and sf.id is null;

  -- total_paid + credit_balance يجب أن يطابق مجموع الدفعات الفعلية غير الملغاة.
  select count(*) into fee_total_mismatches
  from public.student_fees sf
  where (coalesce(sf.total_paid,0) + coalesce(sf.credit_balance,0)) is distinct from coalesce((
    select sum(coalesce(fp.amount_usd,fp.amount,0))
    from public.fee_payments fp
    where fp.student_fee_id=sf.id and coalesce(fp.voided,false)=false
  ),0);

  select count(*) into credits_count
  from public.student_fees
  where coalesce(credit_balance,0) > 0;

  if null_due_open > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','danger','code','null_due_open_installments','message','توجد أقساط مفتوحة بدون تاريخ استحقاق','count',null_due_open)); end if;
  if invalid_months > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','danger','code','invalid_installment_months','message','توجد أقساط بأشهر خارج السنة الدراسية','count',invalid_months)); end if;
  if payments_without_receiver > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','payments_without_receiver','message','توجد مدفوعات بدون اسم مستلم','count',payments_without_receiver)); end if;
  if overpaid_fees > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','overpaid_fees','message','توجد ملفات رسوم total_paid فيها أكبر من الصافي؛ شغّلي finance_reconcile_overpayments_to_credit(true,null)','count',overpaid_fees)); end if;
  if overpaid_installments > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','overpaid_installments','message','توجد أقساط مدفوعة أكثر من المستحق','count',overpaid_installments)); end if;
  if orphan_payments > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','danger','code','orphan_payments','message','توجد مدفوعات لا ترتبط بملف مالي موجود','count',orphan_payments)); end if;
  if fee_total_mismatches > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','fee_total_mismatches','message','total_paid + credit_balance لا يطابق مجموع المدفوعات غير الملغاة','count',fee_total_mismatches)); end if;

  stats := jsonb_build_object(
    'student_fees', (select count(*) from public.student_fees),
    'installments', (select count(*) from public.student_installments),
    'open_installments', (select count(*) from public.student_installments where coalesce(amount_due,0)>coalesce(amount_paid,0)),
    'payments', (select count(*) from public.fee_payments),
    'active_payments', (select count(*) from public.fee_payments where coalesce(voided,false)=false),
    'voided_payments', (select count(*) from public.fee_payments where coalesce(voided,false)=true),
    'total_due', (select coalesce(sum(coalesce(net_amount,base_amount,gross_amount,0)),0) from public.student_fees),
    'total_paid_recorded', (select coalesce(sum(coalesce(total_paid,0)),0) from public.student_fees),
    'total_credit_balance', (select coalesce(sum(coalesce(credit_balance,0)),0) from public.student_fees),
    'credit_files_count', credits_count,
    'total_payments_active', (select coalesce(sum(coalesce(amount_usd,amount,0)),0) from public.fee_payments where coalesce(voided,false)=false),
    'total_remaining', (select coalesce(sum(greatest(coalesce(net_amount,base_amount,gross_amount,0)-coalesce(total_paid,0),0)),0) from public.student_fees),
    'cashbox_closures', (select count(*) from public.finance_cashbox_closures),
    'followups', (select count(*) from public.finance_followups),
    'open_followups', (select count(*) from public.finance_followups where status='open')
  );

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) into latest_payments
  from (
    select fp.id, fp.receipt_number, coalesce(fp.payment_date, fp.created_at::date) as payment_date, fp.created_at, s.name as student_name, c.name as class_name, coalesce(fp.amount_usd,fp.amount,0) as amount_usd, fp.currency, fp.payment_method, fp.payer_name, fp.receiver_name, fp.voided
    from public.fee_payments fp
    left join public.student_fees sf on sf.id = fp.student_fee_id
    left join public.students s on s.id = sf.student_id
    left join public.classes c on c.id = s.class_id
    order by fp.created_at desc
    limit 15
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_usd desc), '[]'::jsonb) into receiver_summary
  from (
    select coalesce(receiver_name, created_by_name, 'غير محدد') as receiver_name, count(*) filter (where coalesce(voided,false)=false) as payments_count, coalesce(sum(coalesce(amount_usd,amount,0)) filter (where coalesce(voided,false)=false),0) as total_usd
    from public.fee_payments
    group by coalesce(receiver_name, created_by_name, 'غير محدد')
  ) x;

  if to_regclass('public.v_finance_exec_class_summary') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.total_remaining desc), '[]'::jsonb) into class_summary
    from (select * from public.v_finance_exec_class_summary) x;
  else class_summary := '[]'::jsonb; end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.credit_balance desc), '[]'::jsonb) into credits
  from (select * from public.v_finance_fee_credit_summary order by credit_balance desc) x;

  details := jsonb_build_object('latest_payments', latest_payments, 'receiver_summary', receiver_summary, 'class_summary', class_summary, 'credit_summary', credits);

  return jsonb_build_object('ok', jsonb_array_length(issues)=0, 'checked_at', now(), 'stats', stats, 'issues', issues, 'details', details, 'recommendation', case when jsonb_array_length(issues)=0 then 'المالية جاهزة تشغيلياً. راجعي credit_summary إن وجدت أرصدة دائنة.' else 'راجعي issues قبل الاعتماد النهائي للتقارير المالية.' end);
end;
$$;

grant execute on function public.finance_final_reconciliation_check() to authenticated;

-- -------------------------------------------------------------
-- 4) فحص
-- -------------------------------------------------------------
create or replace function public.finance_credit_reconciliation_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'credit_column_exists', exists(select 1 from information_schema.columns where table_schema='public' and table_name='student_fees' and column_name='credit_balance'),
    'credit_view_exists', to_regclass('public.v_finance_fee_credit_summary') is not null,
    'reconcile_rpc_exists', to_regprocedure('public.finance_reconcile_overpayments_to_credit(boolean,uuid)') is not null,
    'preview', public.finance_reconcile_overpayments_to_credit(false,null),
    'final_check_stats', public.finance_final_reconciliation_check()->'stats'
  );
end;
$$;

grant execute on function public.finance_credit_reconciliation_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_credit_reconciliation_ready' as status;

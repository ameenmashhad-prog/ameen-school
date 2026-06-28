-- =============================================================
-- مدارس أمين الرضا (ع) — فحص التسوية المالية النهائي
-- تقرير فقط: لا يغير أي بيانات.
-- =============================================================

create extension if not exists pgcrypto;

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
  null_due_open int := 0;
  invalid_months int := 0;
  payments_without_receiver int := 0;
  overpaid_fees int := 0;
  overpaid_installments int := 0;
  orphan_payments int := 0;
  fee_total_mismatches int := 0;
begin
  if not public.finance_can_manage() and auth.uid() is not null then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية فحص التسوية المالية');
  end if;

  -- أرقام رئيسية
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

  select count(*) into fee_total_mismatches
  from public.student_fees sf
  where coalesce(sf.total_paid,0) is distinct from coalesce((
    select sum(coalesce(fp.amount_usd,fp.amount,0))
    from public.fee_payments fp
    where fp.student_fee_id = sf.id
      and coalesce(fp.voided,false)=false
  ),0);

  if null_due_open > 0 then
    issues := issues || jsonb_build_array(jsonb_build_object('level','danger','code','null_due_open_installments','message','توجد أقساط مفتوحة بدون تاريخ استحقاق','count',null_due_open,'fix','شغّلي finance_repair_null_installment_due_dates(null,null,true)'));
  end if;
  if invalid_months > 0 then
    issues := issues || jsonb_build_array(jsonb_build_object('level','danger','code','invalid_installment_months','message','توجد أقساط بأشهر خارج السنة الدراسية','count',invalid_months));
  end if;
  if payments_without_receiver > 0 then
    issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','payments_without_receiver','message','توجد مدفوعات بدون اسم مستلم','count',payments_without_receiver,'fix','شغّلي SQL 66 أو عدّلي المستلم من تقارير المستلمين'));
  end if;
  if overpaid_fees > 0 then
    issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','overpaid_fees','message','توجد ملفات رسوم مدفوعة أكثر من الصافي؛ غالباً بيانات قديمة/تجريبية تحتاج مراجعة','count',overpaid_fees));
  end if;
  if overpaid_installments > 0 then
    issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','overpaid_installments','message','توجد أقساط مدفوعة أكثر من المستحق','count',overpaid_installments));
  end if;
  if orphan_payments > 0 then
    issues := issues || jsonb_build_array(jsonb_build_object('level','danger','code','orphan_payments','message','توجد مدفوعات لا ترتبط بملف مالي موجود','count',orphan_payments));
  end if;
  if fee_total_mismatches > 0 then
    issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','fee_total_mismatches','message','إجمالي total_paid في بعض ملفات الرسوم لا يطابق مجموع المدفوعات غير الملغاة. راجعي قبل تشغيل أي إعادة احتساب جماعية.','count',fee_total_mismatches));
  end if;

  stats := jsonb_build_object(
    'student_fees', (select count(*) from public.student_fees),
    'installments', (select count(*) from public.student_installments),
    'open_installments', (select count(*) from public.student_installments where coalesce(amount_due,0)>coalesce(amount_paid,0)),
    'payments', (select count(*) from public.fee_payments),
    'active_payments', (select count(*) from public.fee_payments where coalesce(voided,false)=false),
    'voided_payments', (select count(*) from public.fee_payments where coalesce(voided,false)=true),
    'total_due', (select coalesce(sum(coalesce(net_amount,base_amount,gross_amount,0)),0) from public.student_fees),
    'total_paid_recorded', (select coalesce(sum(coalesce(total_paid,0)),0) from public.student_fees),
    'total_payments_active', (select coalesce(sum(coalesce(amount_usd,amount,0)),0) from public.fee_payments where coalesce(voided,false)=false),
    'total_remaining', (select coalesce(sum(greatest(coalesce(net_amount,base_amount,gross_amount,0)-coalesce(total_paid,0),0)),0) from public.student_fees),
    'cashbox_closures', (select count(*) from public.finance_cashbox_closures),
    'followups', (select count(*) from public.finance_followups),
    'open_followups', (select count(*) from public.finance_followups where status='open')
  );

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into latest_payments
  from (
    select
      fp.id,
      fp.receipt_number,
      coalesce(fp.payment_date, fp.created_at::date) as payment_date,
      fp.created_at,
      s.name as student_name,
      c.name as class_name,
      coalesce(fp.amount_usd,fp.amount,0) as amount_usd,
      fp.currency,
      fp.payment_method,
      fp.payer_name,
      fp.receiver_name,
      fp.voided
    from public.fee_payments fp
    left join public.student_fees sf on sf.id = fp.student_fee_id
    left join public.students s on s.id = sf.student_id
    left join public.classes c on c.id = s.class_id
    order by fp.created_at desc
    limit 15
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_usd desc), '[]'::jsonb)
  into receiver_summary
  from (
    select
      coalesce(receiver_name, created_by_name, 'غير محدد') as receiver_name,
      count(*) filter (where coalesce(voided,false)=false) as payments_count,
      coalesce(sum(coalesce(amount_usd,amount,0)) filter (where coalesce(voided,false)=false),0) as total_usd
    from public.fee_payments
    group by coalesce(receiver_name, created_by_name, 'غير محدد')
  ) x;

  if to_regclass('public.v_finance_exec_class_summary') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.total_remaining desc), '[]'::jsonb)
    into class_summary
    from (select * from public.v_finance_exec_class_summary) x;
  else
    class_summary := '[]'::jsonb;
  end if;

  details := jsonb_build_object(
    'latest_payments', latest_payments,
    'receiver_summary', receiver_summary,
    'class_summary', class_summary
  );

  return jsonb_build_object(
    'ok', jsonb_array_length(issues) = 0,
    'checked_at', now(),
    'stats', stats,
    'issues', issues,
    'details', details,
    'recommendation', case when jsonb_array_length(issues)=0 then 'المالية جاهزة تشغيلياً.' else 'راجعي issues قبل الاعتماد النهائي للتقارير المالية.' end
  );
end;
$$;

grant execute on function public.finance_final_reconciliation_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_final_reconciliation_check_ready' as status;

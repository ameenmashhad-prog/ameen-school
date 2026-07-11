-- ============================================================================
-- Finance — transfer credit balance between siblings / same parent
--
-- الهدف:
-- 1) السماح بنقل جزء من الرصيد الدائن من طالب إلى طالب آخر لنفس ولي الأمر
-- 2) حفظ سجل مستقل للحركة
-- 3) إبقاء reconciliation منطقية عبر احتساب التحويلات الداخلة/الخارجة
-- ============================================================================

create table if not exists public.finance_credit_transfers (
  id uuid primary key default gen_random_uuid(),
  from_student_fee_id uuid not null references public.student_fees(id) on delete cascade,
  to_student_fee_id uuid not null references public.student_fees(id) on delete cascade,
  amount_usd numeric not null check (amount_usd > 0),
  note text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  check (from_student_fee_id <> to_student_fee_id)
);

create index if not exists idx_finance_credit_transfers_from_fee on public.finance_credit_transfers(from_student_fee_id, created_at desc);
create index if not exists idx_finance_credit_transfers_to_fee on public.finance_credit_transfers(to_student_fee_id, created_at desc);

alter table public.finance_credit_transfers enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='finance_credit_transfers' and policyname='finance_credit_transfers_admin_read') then
    create policy finance_credit_transfers_admin_read on public.finance_credit_transfers
      for select to authenticated
      using (
        exists(select 1 from public.users u where u.id = auth.uid() and (u.role in ('admin','finance','staff','accountant','cashier') or coalesce(u.is_super_admin,false)=true))
      );
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='finance_credit_transfers' and policyname='finance_credit_transfers_admin_insert') then
    create policy finance_credit_transfers_admin_insert on public.finance_credit_transfers
      for insert to authenticated
      with check (
        exists(select 1 from public.users u where u.id = auth.uid() and (u.role in ('admin','finance','staff','accountant','cashier') or coalesce(u.is_super_admin,false)=true))
      );
  end if;
end $$;

create or replace function public.get_finance_credit_transfer_targets(
  p_from_student_fee_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source record;
begin
  select
    sf.id as student_fee_id,
    sf.student_id,
    st.parent_id,
    st.name as student_name,
    c.name as class_name,
    coalesce(sf.net_amount, sf.base_amount, sf.gross_amount, 0) as net_amount,
    coalesce(sf.total_paid, 0) as total_paid,
    coalesce(sf.credit_balance, 0) as credit_balance,
    sf.status,
    sf.academic_year
  into v_source
  from public.student_fees sf
  join public.students st on st.id = sf.student_id
  left join public.classes c on c.id = st.class_id
  where sf.id = p_from_student_fee_id;

  if v_source.student_fee_id is null then
    return jsonb_build_object('ok', false, 'error', 'source_fee_not_found');
  end if;

  return jsonb_build_object(
    'ok', true,
    'source', jsonb_build_object(
      'student_fee_id', v_source.student_fee_id,
      'student_id', v_source.student_id,
      'student_name', v_source.student_name,
      'class_name', v_source.class_name,
      'academic_year', v_source.academic_year,
      'credit_balance', v_source.credit_balance,
      'net_amount', v_source.net_amount,
      'total_paid', v_source.total_paid,
      'status', v_source.status
    ),
    'targets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'student_fee_id', x.student_fee_id,
        'student_id', x.student_id,
        'student_name', x.student_name,
        'class_name', x.class_name,
        'academic_year', x.academic_year,
        'net_amount', x.net_amount,
        'total_paid', x.total_paid,
        'credit_balance', x.credit_balance,
        'remaining_amount', greatest(x.net_amount - x.total_paid, 0),
        'status', x.status
      ) order by x.student_name)
      from (
        select distinct on (sf.student_id)
          sf.id as student_fee_id,
          sf.student_id,
          st.name as student_name,
          c.name as class_name,
          sf.academic_year,
          coalesce(sf.net_amount, sf.base_amount, sf.gross_amount, 0) as net_amount,
          coalesce(sf.total_paid, 0) as total_paid,
          coalesce(sf.credit_balance, 0) as credit_balance,
          sf.status
        from public.student_fees sf
        join public.students st on st.id = sf.student_id
        left join public.classes c on c.id = st.class_id
        where st.parent_id = v_source.parent_id
          and sf.id <> v_source.student_fee_id
        order by sf.student_id, sf.updated_at desc nulls last, sf.created_at desc nulls last, sf.id desc
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_finance_credit_transfer_targets(uuid) to authenticated;

create or replace function public.finance_transfer_credit_between_students(
  p_from_student_fee_id uuid,
  p_to_student_fee_id uuid,
  p_amount_usd numeric,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from record;
  v_to record;
  v_amount numeric := round(coalesce(p_amount_usd, 0)::numeric, 2);
  v_target_effective numeric;
  v_target_net numeric;
  v_new_total_paid numeric;
  v_new_credit numeric;
  v_remaining_to_apply numeric;
  v_inst record;
  v_apply numeric;
  v_transfer_id uuid;
begin
  if v_amount <= 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_amount');
  end if;

  select
    sf.id as student_fee_id,
    sf.student_id,
    st.parent_id,
    st.name as student_name,
    coalesce(sf.credit_balance, 0) as credit_balance,
    coalesce(sf.net_amount, sf.base_amount, sf.gross_amount, 0) as net_amount,
    coalesce(sf.total_paid, 0) as total_paid,
    sf.status
  into v_from
  from public.student_fees sf
  join public.students st on st.id = sf.student_id
  where sf.id = p_from_student_fee_id;

  if v_from.student_fee_id is null then
    return jsonb_build_object('ok', false, 'error', 'source_fee_not_found');
  end if;

  select
    sf.id as student_fee_id,
    sf.student_id,
    st.parent_id,
    st.name as student_name,
    coalesce(sf.credit_balance, 0) as credit_balance,
    coalesce(sf.net_amount, sf.base_amount, sf.gross_amount, 0) as net_amount,
    coalesce(sf.total_paid, 0) as total_paid,
    sf.status
  into v_to
  from public.student_fees sf
  join public.students st on st.id = sf.student_id
  where sf.id = p_to_student_fee_id;

  if v_to.student_fee_id is null then
    return jsonb_build_object('ok', false, 'error', 'target_fee_not_found');
  end if;

  if v_from.student_fee_id = v_to.student_fee_id then
    return jsonb_build_object('ok', false, 'error', 'same_fee_not_allowed');
  end if;

  if v_from.parent_id is null or v_to.parent_id is null or v_from.parent_id <> v_to.parent_id then
    return jsonb_build_object('ok', false, 'error', 'different_guardian_not_allowed');
  end if;

  if v_from.credit_balance < v_amount then
    return jsonb_build_object('ok', false, 'error', 'insufficient_credit_balance', 'available_credit', v_from.credit_balance);
  end if;

  insert into public.finance_credit_transfers(
    from_student_fee_id,
    to_student_fee_id,
    amount_usd,
    note,
    created_by
  ) values (
    v_from.student_fee_id,
    v_to.student_fee_id,
    v_amount,
    nullif(trim(coalesce(p_note, '')), ''),
    auth.uid()
  ) returning id into v_transfer_id;

  update public.student_fees
    set credit_balance = round(greatest(coalesce(credit_balance,0) - v_amount, 0), 2),
        credit_notes = concat_ws(' | ', nullif(credit_notes,''), 'تم تحويل ' || v_amount || ' USD إلى ملف طالب آخر'),
        updated_at = now()
  where id = v_from.student_fee_id;

  v_target_net := v_to.net_amount;
  v_target_effective := round(coalesce(v_to.total_paid,0) + coalesce(v_to.credit_balance,0) + v_amount, 2);
  v_new_total_paid := round(least(v_target_effective, v_target_net), 2);
  v_new_credit := round(greatest(v_target_effective - v_target_net, 0), 2);

  update public.student_fees
    set total_paid = v_new_total_paid,
        credit_balance = v_new_credit,
        status = case
          when v_new_total_paid <= 0 then 'unpaid'
          when v_new_total_paid >= v_target_net then 'paid'
          else 'partial'
        end,
        credit_notes = case when v_new_credit > 0 then concat_ws(' | ', nullif(credit_notes,''), 'رصيد دائن بعد تحويل من طالب آخر') else credit_notes end,
        updated_at = now()
  where id = v_to.student_fee_id;

  v_remaining_to_apply := v_amount;
  for v_inst in
    select *
    from public.student_installments
    where student_fee_id = v_to.student_fee_id
      and greatest(coalesce(amount_due,0) - coalesce(amount_paid,0), 0) > 0
    order by due_date nulls last, installment_number
  loop
    exit when v_remaining_to_apply <= 0;
    v_apply := round(least(v_remaining_to_apply, greatest(coalesce(v_inst.amount_due,0) - coalesce(v_inst.amount_paid,0), 0)), 2);

    update public.student_installments
      set amount_paid = round(coalesce(amount_paid,0) + v_apply, 2),
          balance_remaining = round(greatest(coalesce(amount_due,0) - (coalesce(amount_paid,0) + v_apply), 0), 2),
          status = case
            when round(coalesce(amount_paid,0) + v_apply, 2) >= coalesce(amount_due,0) then 'paid'
            when round(coalesce(amount_paid,0) + v_apply, 2) > 0 then 'partial'
            else 'unpaid'
          end,
          actual_payment_date = coalesce(actual_payment_date, current_date),
          note = concat_ws(' | ', nullif(note,''), 'تسوية من رصيد دائن لطالب شقيق'),
          updated_at = now()
    where id = v_inst.id;

    v_remaining_to_apply := round(v_remaining_to_apply - v_apply, 2);
  end loop;

  return jsonb_build_object(
    'ok', true,
    'transfer_id', v_transfer_id,
    'from_student_fee_id', v_from.student_fee_id,
    'to_student_fee_id', v_to.student_fee_id,
    'from_student_name', v_from.student_name,
    'to_student_name', v_to.student_name,
    'amount_usd', v_amount,
    'source_credit_after', round(v_from.credit_balance - v_amount, 2),
    'target_total_paid_after', v_new_total_paid,
    'target_credit_after', v_new_credit,
    'message', 'تم تحويل الرصيد الدائن بنجاح بين الطالبين'
  );
end;
$$;

grant execute on function public.finance_transfer_credit_between_students(uuid,uuid,numeric,text) to authenticated;

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
      ),0)
      + coalesce((select sum(t.amount_usd) from public.finance_credit_transfers t where t.to_student_fee_id = sf.id),0)
      - coalesce((select sum(t.amount_usd) from public.finance_credit_transfers t where t.from_student_fee_id = sf.id),0)
      as effective_paid_equivalent
    from public.student_fees sf
    left join public.students s on s.id = sf.student_id
    left join public.classes c on c.id = s.class_id
    where p_student_fee_id is null or sf.id = p_student_fee_id
  ), target as (
    select
      *,
      least(effective_paid_equivalent, net_amount) as new_total_paid,
      greatest(effective_paid_equivalent - net_amount, 0) as new_credit_balance,
      case
        when effective_paid_equivalent <= 0 then 'unpaid'
        when effective_paid_equivalent >= net_amount then 'paid'
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
    'effective_paid_equivalent', effective_paid_equivalent,
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
        ),0)
        + coalesce((select sum(t.amount_usd) from public.finance_credit_transfers t where t.to_student_fee_id = sf.id),0)
        - coalesce((select sum(t.amount_usd) from public.finance_credit_transfers t where t.from_student_fee_id = sf.id),0)
        as effective_paid_equivalent
      from public.student_fees sf
      where p_student_fee_id is null or sf.id = p_student_fee_id
    ), target as (
      select
        id,
        least(effective_paid_equivalent, net_amount) as new_total_paid,
        greatest(effective_paid_equivalent - net_amount, 0) as new_credit_balance,
        case
          when effective_paid_equivalent <= 0 then 'unpaid'
          when effective_paid_equivalent >= net_amount then 'paid'
          else 'partial'
        end as new_status
      from calc
    )
    update public.student_fees sf
    set total_paid = target.new_total_paid,
        credit_balance = target.new_credit_balance,
        status = target.new_status,
        credit_notes = case when target.new_credit_balance > 0 then 'رصيد دائن ناتج عن مدفوعات زائدة أو تحويلات محفوظة كسجل' else credit_notes end,
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
    'note', 'تم احتساب المدفوعات الزائدة والتحويلات بين الإخوة ضمن الرصيد الدائن.'
  );
end;
$$;

grant execute on function public.finance_reconcile_overpayments_to_credit(boolean,uuid) to authenticated;

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
  transfer_summary jsonb;
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
  where (coalesce(sf.total_paid,0) + coalesce(sf.credit_balance,0)) is distinct from (
    coalesce((
      select sum(coalesce(fp.amount_usd,fp.amount,0))
      from public.fee_payments fp
      where fp.student_fee_id=sf.id and coalesce(fp.voided,false)=false
    ),0)
    + coalesce((select sum(t.amount_usd) from public.finance_credit_transfers t where t.to_student_fee_id = sf.id),0)
    - coalesce((select sum(t.amount_usd) from public.finance_credit_transfers t where t.from_student_fee_id = sf.id),0)
  );

  select count(*) into credits_count
  from public.student_fees
  where coalesce(credit_balance,0) > 0;

  if null_due_open > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','danger','code','null_due_open_installments','message','توجد أقساط مفتوحة بدون تاريخ استحقاق','count',null_due_open)); end if;
  if invalid_months > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','danger','code','invalid_installment_months','message','توجد أقساط بأشهر خارج السنة الدراسية','count',invalid_months)); end if;
  if payments_without_receiver > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','payments_without_receiver','message','توجد مدفوعات بدون اسم مستلم','count',payments_without_receiver)); end if;
  if overpaid_fees > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','overpaid_fees','message','توجد ملفات رسوم total_paid فيها أكبر من الصافي؛ شغّلي finance_reconcile_overpayments_to_credit(true,null)','count',overpaid_fees)); end if;
  if overpaid_installments > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','overpaid_installments','message','توجد أقساط مدفوعة أكثر من المستحق','count',overpaid_installments)); end if;
  if orphan_payments > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','danger','code','orphan_payments','message','توجد مدفوعات لا ترتبط بملف مالي موجود','count',orphan_payments)); end if;
  if fee_total_mismatches > 0 then issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','fee_total_mismatches','message','total_paid + credit_balance لا يطابق المدفوعات الفعلية + التحويلات بين الإخوة','count',fee_total_mismatches)); end if;

  stats := jsonb_build_object(
    'student_fees', (select count(*) from public.student_fees),
    'installments', (select count(*) from public.student_installments),
    'open_installments', (select count(*) from public.student_installments where coalesce(amount_due,0)>coalesce(amount_paid,0)),
    'payments', (select count(*) from public.fee_payments),
    'active_payments', (select count(*) from public.fee_payments where coalesce(voided,false)=false),
    'voided_payments', (select count(*) from public.fee_payments where coalesce(voided,false)=true),
    'credit_transfers', (select count(*) from public.finance_credit_transfers),
    'credit_transfers_total', (select coalesce(sum(amount_usd),0) from public.finance_credit_transfers),
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

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) into transfer_summary
  from (
    select t.id, t.created_at, t.amount_usd,
           s1.name as from_student_name,
           s2.name as to_student_name,
           t.note
    from public.finance_credit_transfers t
    left join public.student_fees sf1 on sf1.id = t.from_student_fee_id
    left join public.student_fees sf2 on sf2.id = t.to_student_fee_id
    left join public.students s1 on s1.id = sf1.student_id
    left join public.students s2 on s2.id = sf2.student_id
    order by t.created_at desc
    limit 25
  ) x;

  details := jsonb_build_object('latest_payments', latest_payments, 'receiver_summary', receiver_summary, 'class_summary', class_summary, 'credit_summary', credits, 'credit_transfers', transfer_summary);

  return jsonb_build_object('ok', jsonb_array_length(issues)=0, 'checked_at', now(), 'stats', stats, 'issues', issues, 'details', details, 'recommendation', case when jsonb_array_length(issues)=0 then 'المالية جاهزة تشغيلياً. راجعي تحويلات الرصيد إن احتجتِ نقل الرصيد بين الإخوة.' else 'راجعي issues قبل الاعتماد النهائي للتقارير المالية.' end);
end;
$$;

grant execute on function public.finance_final_reconciliation_check() to authenticated;

notify pgrst, 'reload schema';

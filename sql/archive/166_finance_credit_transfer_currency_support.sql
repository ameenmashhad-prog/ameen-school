-- ============================================================================
-- Finance credit transfer — currency support (USD / IRR)
--
-- الهدف:
-- 1) حفظ مبلغ التحويل بالدولار والريال وسعر الصرف المستخدم
-- 2) دعم إدخال التحويل بالريال أو الدولار من الواجهة
-- 3) إبقاء المنطق المالي الداخلي معتمدًا على USD للحسابات
-- ============================================================================

alter table public.finance_credit_transfers
  add column if not exists currency text not null default 'USD';

alter table public.finance_credit_transfers
  add column if not exists amount_irr numeric;

alter table public.finance_credit_transfers
  add column if not exists exchange_rate_value numeric;

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
    p.name as parent_name,
    coalesce(sf.credit_balance, 0) as credit_balance,
    coalesce(sf.net_amount, sf.base_amount, sf.gross_amount, 0) as net_amount,
    coalesce(sf.total_paid, 0) as total_paid,
    sf.status,
    sf.academic_year
  into v_source
  from public.student_fees sf
  join public.students st on st.id = sf.student_id
  left join public.classes c on c.id = st.class_id
  left join public.users p on p.id = st.parent_id
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
      'parent_name', v_source.parent_name,
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
        'parent_name', x.parent_name,
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
          p.name as parent_name,
          sf.academic_year,
          coalesce(sf.net_amount, sf.base_amount, sf.gross_amount, 0) as net_amount,
          coalesce(sf.total_paid, 0) as total_paid,
          coalesce(sf.credit_balance, 0) as credit_balance,
          sf.status
        from public.student_fees sf
        join public.students st on st.id = sf.student_id
        left join public.classes c on c.id = st.class_id
        left join public.users p on p.id = st.parent_id
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
  p_amount_input numeric,
  p_currency text default 'USD',
  p_exchange_rate_value numeric default null,
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
  v_currency text := upper(trim(coalesce(p_currency, 'USD')));
  v_amount_input numeric := round(coalesce(p_amount_input, 0)::numeric, 2);
  v_exchange_rate numeric := round(coalesce(p_exchange_rate_value, 0)::numeric, 4);
  v_amount_usd numeric;
  v_amount_irr numeric;
  v_target_effective numeric;
  v_target_net numeric;
  v_new_total_paid numeric;
  v_new_credit numeric;
  v_remaining_to_apply numeric;
  v_inst record;
  v_apply numeric;
  v_transfer_id uuid;
begin
  if v_currency not in ('USD','IRR') then
    return jsonb_build_object('ok', false, 'error', 'invalid_currency');
  end if;

  if v_amount_input <= 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_amount');
  end if;

  if v_currency = 'IRR' then
    if v_exchange_rate <= 0 then
      return jsonb_build_object('ok', false, 'error', 'exchange_rate_required_for_irr');
    end if;
    v_amount_irr := v_amount_input;
    v_amount_usd := round(v_amount_input / v_exchange_rate, 2);
  else
    v_amount_usd := round(v_amount_input, 2);
    v_amount_irr := case when v_exchange_rate > 0 then round(v_amount_usd * v_exchange_rate, 0) else null end;
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

  if v_from.credit_balance < v_amount_usd then
    return jsonb_build_object('ok', false, 'error', 'insufficient_credit_balance', 'available_credit_usd', v_from.credit_balance);
  end if;

  insert into public.finance_credit_transfers(
    from_student_fee_id,
    to_student_fee_id,
    amount_usd,
    amount_irr,
    currency,
    exchange_rate_value,
    note,
    created_by
  ) values (
    v_from.student_fee_id,
    v_to.student_fee_id,
    v_amount_usd,
    v_amount_irr,
    v_currency,
    nullif(v_exchange_rate, 0),
    nullif(trim(coalesce(p_note, '')), ''),
    auth.uid()
  ) returning id into v_transfer_id;

  update public.student_fees
    set credit_balance = round(greatest(coalesce(credit_balance,0) - v_amount_usd, 0), 2),
        credit_notes = concat_ws(' | ', nullif(credit_notes,''), 'تم تحويل ' || v_amount_usd || ' USD إلى ملف طالب آخر'),
        updated_at = now()
  where id = v_from.student_fee_id;

  v_target_net := v_to.net_amount;
  v_target_effective := round(coalesce(v_to.total_paid,0) + coalesce(v_to.credit_balance,0) + v_amount_usd, 2);
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

  v_remaining_to_apply := v_amount_usd;
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
    'currency', v_currency,
    'amount_usd', v_amount_usd,
    'amount_irr', v_amount_irr,
    'exchange_rate_value', nullif(v_exchange_rate, 0),
    'source_credit_after', round(v_from.credit_balance - v_amount_usd, 2),
    'target_total_paid_after', v_new_total_paid,
    'target_credit_after', v_new_credit,
    'message', 'تم تحويل الرصيد الدائن بنجاح بين الطالبين'
  );
end;
$$;

grant execute on function public.finance_transfer_credit_between_students(uuid,uuid,numeric,text,numeric,text) to authenticated;

notify pgrst, 'reload schema';

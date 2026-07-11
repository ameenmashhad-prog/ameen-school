-- ============================================================================
-- Fix family activation finance sync when student_installments.status disallows 'pending'
--
-- المشكلة المكتشفة:
-- بعض البيئات تحتوي constraint على student_installments.status لا تقبل 'pending'
-- وتقبل فقط الحالة المالية التقليدية مثل: unpaid / partial / paid
--
-- النتيجة:
-- فشل activation عند إنشاء الأقساط التلقائية.
--
-- الحل:
-- إعادة تعريف الدالة بحيث تنشئ الأقساط الجديدة بالحالة 'unpaid'
-- ============================================================================

create or replace function public.registration_sync_finance_after_family_activation(
  p_registration_student_id uuid,
  p_student_user_id uuid,
  p_operator_id uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reg public.registration_students%rowtype;
  v_fee_id uuid;
  v_plan_id uuid;
  v_item jsonb;
  v_net_amount numeric;
  v_installments_count int;
  v_start_date date;
  v_end_date date;
  v_due_date date;
  v_installment_month int;
  v_created_installments int := 0;
begin
  select * into v_reg
  from public.registration_students
  where id = p_registration_student_id;

  if v_reg.id is null then
    return jsonb_build_object('ok', false, 'error', 'registration_student_not_found');
  end if;

  v_net_amount := coalesce(v_reg.annual_fee_snapshot, 0);
  if v_net_amount <= 0 then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_fee_snapshot');
  end if;

  v_installments_count := greatest(coalesce(v_reg.finance_installments_count, 1), 1);
  v_start_date := coalesce(v_reg.finance_plan_start_date, date '2026-09-10');
  v_end_date := coalesce(v_reg.finance_plan_end_date, (v_start_date + ((v_installments_count - 1) * interval '30 days'))::date);

  select id into v_fee_id
  from public.student_fees
  where student_id = p_student_user_id
    and academic_year = coalesce(v_reg.academic_year, '2026-2027')
  order by created_at desc
  limit 1;

  if v_fee_id is null then
    insert into public.student_fees(
      student_id,
      class_id,
      academic_year,
      fee_structure_id,
      gross_amount,
      base_amount,
      discount_amount,
      discount_reason,
      net_amount,
      total_paid,
      status,
      plan_type,
      installments_count,
      created_by,
      updated_by,
      notes,
      updated_at
    ) values (
      p_student_user_id,
      v_reg.class_id,
      coalesce(v_reg.academic_year, '2026-2027'),
      v_reg.fee_structure_id,
      v_net_amount,
      v_net_amount,
      0,
      null,
      v_net_amount,
      0,
      'unpaid',
      coalesce(nullif(v_reg.finance_plan_type, ''), 'monthly'),
      v_installments_count,
      p_operator_id,
      p_operator_id,
      'Created automatically from family-registration-v3 activation',
      now()
    ) returning id into v_fee_id;
  else
    update public.student_fees
      set class_id = coalesce(v_reg.class_id, class_id),
          fee_structure_id = coalesce(v_reg.fee_structure_id, fee_structure_id),
          gross_amount = coalesce(nullif(gross_amount, 0), v_net_amount),
          base_amount = coalesce(nullif(base_amount, 0), v_net_amount),
          net_amount = coalesce(nullif(net_amount, 0), v_net_amount),
          status = case when coalesce(total_paid,0) >= coalesce(nullif(net_amount,0), v_net_amount) then 'paid' else 'unpaid' end,
          plan_type = coalesce(nullif(v_reg.finance_plan_type, ''), plan_type),
          installments_count = coalesce(v_installments_count, installments_count),
          updated_by = p_operator_id,
          updated_at = now(),
          notes = coalesce(notes, 'Created automatically from family-registration-v3 activation')
    where id = v_fee_id;
  end if;

  select id into v_plan_id
  from public.finance_payment_plans
  where student_fee_id = v_fee_id
    and status = 'active'
  order by created_at desc
  limit 1;

  if v_plan_id is null then
    insert into public.finance_payment_plans(
      student_fee_id,
      plan_type,
      installments_count,
      start_date,
      end_date,
      status,
      created_by,
      notes
    ) values (
      v_fee_id,
      coalesce(nullif(v_reg.finance_plan_type, ''), 'monthly'),
      v_installments_count,
      v_start_date,
      v_end_date,
      'active',
      p_operator_id,
      'Created automatically from family-registration-v3 activation'
    ) returning id into v_plan_id;
  else
    update public.finance_payment_plans
      set plan_type = coalesce(nullif(v_reg.finance_plan_type, ''), plan_type),
          installments_count = v_installments_count,
          start_date = v_start_date,
          end_date = v_end_date,
          notes = coalesce(notes, 'Created automatically from family-registration-v3 activation')
    where id = v_plan_id;
  end if;

  delete from public.student_installments
  where student_fee_id = v_fee_id
    and coalesce(amount_paid, 0) = 0
    and coalesce(status, 'unpaid') in ('pending', 'unpaid', 'partial');

  for v_item in
    select * from jsonb_array_elements(coalesce(v_reg.finance_installment_schedule, '[]'::jsonb))
  loop
    begin
      v_due_date := nullif(v_item->>'due_date', '')::date;
    exception when others then
      v_due_date := null;
    end;

    v_installment_month := public.finance_valid_academic_installment_month(v_due_date);
    if v_installment_month is null then
      v_installment_month := public.finance_valid_academic_installment_month(v_start_date);
    end if;
    if v_installment_month is null then
      v_installment_month := 9;
    end if;

    insert into public.student_installments(
      student_fee_id,
      installment_number,
      installment_month,
      due_date,
      amount_due,
      amount_paid,
      balance_remaining,
      status,
      actual_payment_date,
      note,
      updated_at
    ) values (
      v_fee_id,
      greatest(coalesce((v_item->>'installment_number')::int, 1), 1),
      v_installment_month,
      v_due_date,
      coalesce((v_item->>'amount_due')::numeric, 0),
      0,
      coalesce((v_item->>'amount_due')::numeric, 0),
      'unpaid',
      null,
      'Created automatically from family-registration-v3 activation',
      now()
    );
    v_created_installments := v_created_installments + 1;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'student_fee_id', v_fee_id,
    'finance_plan_id', v_plan_id,
    'installments_created', v_created_installments
  );
end;
$$;

grant execute on function public.registration_sync_finance_after_family_activation(uuid,uuid,uuid) to authenticated, anon;

notify pgrst, 'reload schema';

-- ============================================================================
-- 140) hotfix — إصلاح RPC تعديل المستلم + إلغاء الدفعة
--
-- المشاكل المكتشفة حيًا:
-- 1) update_payment_receiver غير موجودة في schema cache.
-- 2) void_fee_payment تفشل لأن finance_audit_logs في هذه البيئة تفتقد actor_id/actor_name.
--
-- هذا الملف:
-- - يضيف أعمدة التدقيق الناقصة إذا لم تكن موجودة.
-- - يعيد إنشاء RPC تعديل المستلم.
-- - يعيد إنشاء RPC إلغاء الدفعة بطريقة متوافقة مع مخطط التدقيق الحالي.
-- ============================================================================

create extension if not exists pgcrypto;

alter table if exists public.finance_audit_logs add column if not exists actor_id uuid;
alter table if exists public.finance_audit_logs add column if not exists actor_name text;
alter table if exists public.finance_audit_logs add column if not exists created_at timestamptz not null default now();

create or replace function public.update_payment_receiver(
  p_payment_id uuid,
  p_received_by uuid default null,
  p_receiver_name text default null,
  p_receiver_role text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
  old_row jsonb;
  new_receiver_name text;
  new_receiver_role text;
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل المستلم');
  end if;

  select * into p from public.fee_payments where id = p_payment_id;
  if p.id is null then
    return jsonb_build_object('ok', false, 'message', 'الدفعة غير موجودة');
  end if;

  old_row := to_jsonb(p);

  if p_received_by is not null then
    select coalesce(nullif(trim(u.name),''), p_receiver_name, p.receiver_name, 'غير محدد'),
           coalesce(nullif(trim(u.role),''), p_receiver_role, p.receiver_role)
      into new_receiver_name, new_receiver_role
    from public.users u
    where u.id = p_received_by;
  else
    new_receiver_name := coalesce(nullif(trim(coalesce(p_receiver_name,'')),''), 'مستلم يدوي');
    new_receiver_role := p_receiver_role;
  end if;

  update public.fee_payments
     set received_by = p_received_by,
         receiver_name = new_receiver_name,
         receiver_role = new_receiver_role,
         updated_at = now()
   where id = p_payment_id;

  insert into public.finance_audit_logs(table_name, action, old_data, new_data, actor_id, actor_name)
  values (
    'fee_payments',
    'UPDATE_RECEIVER',
    old_row,
    (select to_jsonb(px) from public.fee_payments px where px.id = p_payment_id),
    auth.uid(),
    (select u.name from public.users u where u.id = auth.uid())
  );

  return jsonb_build_object('ok', true, 'message', 'تم تعديل مستلم الدفعة');
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.update_payment_receiver(uuid,uuid,text,text) to authenticated;

create or replace function public.void_fee_payment(
  p_payment_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
  f record;
  inst record;
  usd numeric := 0;
  new_fee_paid numeric;
  new_inst_paid numeric;
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إلغاء الدفعة');
  end if;

  select * into p from public.fee_payments where id = p_payment_id;
  if p.id is null then return jsonb_build_object('ok', false, 'message', 'الدفعة غير موجودة'); end if;
  if coalesce(p.voided,false) then return jsonb_build_object('ok', true, 'message', 'الدفعة ملغاة مسبقاً'); end if;
  if nullif(trim(coalesce(p_reason,'')), '') is null then return jsonb_build_object('ok', false, 'message', 'سبب إلغاء الدفعة مطلوب'); end if;

  usd := coalesce(p.amount_usd, p.amount, 0);
  select * into f from public.student_fees where id = p.student_fee_id;

  if p.student_installment_id is not null then
    select * into inst from public.student_installments where id = p.student_installment_id;
    if inst.id is not null then
      new_inst_paid := greatest(coalesce(inst.amount_paid,0) - usd, 0);
      update public.student_installments
         set amount_paid = new_inst_paid,
             balance_remaining = greatest(coalesce(amount_due,0) - new_inst_paid, 0),
             status = case when new_inst_paid <= 0 then 'unpaid' when new_inst_paid < coalesce(amount_due,0) then 'partial' else 'paid' end,
             actual_payment_date = case when new_inst_paid <= 0 then null else actual_payment_date end,
             updated_at = now()
       where id = inst.id;
    end if;
  end if;

  if f.id is not null then
    new_fee_paid := greatest(coalesce(f.total_paid,0) - usd, 0);
    update public.student_fees
       set total_paid = new_fee_paid,
           status = case when new_fee_paid <= 0 then 'unpaid' when new_fee_paid < coalesce(net_amount,base_amount,gross_amount,0) then 'partial' else 'paid' end,
           updated_at = now()
     where id = f.id;
  end if;

  update public.fee_payments
     set voided = true,
         void_reason = trim(p_reason),
         voided_by = auth.uid(),
         voided_at = now(),
         updated_at = now()
   where id = p_payment_id;

  insert into public.finance_audit_logs(table_name, action, old_data, new_data, actor_id, actor_name)
  values (
    'fee_payments',
    'VOID',
    to_jsonb(p),
    (select to_jsonb(px) from public.fee_payments px where px.id = p_payment_id),
    auth.uid(),
    (select u.name from public.users u where u.id = auth.uid())
  );

  return jsonb_build_object('ok', true, 'message', 'تم إلغاء الدفعة وعكس الأرصدة', 'amount_usd', usd);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.void_fee_payment(uuid,text) to authenticated;

notify pgrst, 'reload schema';

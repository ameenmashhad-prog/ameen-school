-- =============================================================
-- مدارس أمين الرضا (ع) — دفعة مالية: تقارير المستلمين + إلغاء دفعة آمن
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
-- 1) أعمدة التوافق
-- -------------------------------------------------------------
alter table public.fee_payments add column if not exists received_by uuid null references public.users(id) on delete set null;
alter table public.fee_payments add column if not exists receiver_name text;
alter table public.fee_payments add column if not exists receiver_role text;
alter table public.fee_payments add column if not exists voided boolean not null default false;
alter table public.fee_payments add column if not exists void_reason text;
alter table public.fee_payments add column if not exists voided_by uuid null references public.users(id) on delete set null;
alter table public.fee_payments add column if not exists voided_at timestamptz;
alter table public.fee_payments add column if not exists amount_usd numeric;
alter table public.fee_payments add column if not exists amount_irr numeric;
alter table public.fee_payments add column if not exists payment_method text not null default 'cash';
alter table public.fee_payments add column if not exists payment_date date;
alter table public.fee_payments add column if not exists receipt_number text;
alter table public.fee_payments add column if not exists created_by uuid null references public.users(id);
alter table public.fee_payments add column if not exists created_by_name text;

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
-- 2) Audit logs إن لم تكن موجودة
-- -------------------------------------------------------------
create table if not exists public.finance_audit_logs (
  id uuid primary key default gen_random_uuid(),
  table_name text,
  record_id uuid,
  action text,
  old_data jsonb,
  new_data jsonb,
  actor_id uuid,
  actor_name text,
  gregorian_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- -------------------------------------------------------------
-- 3) Views تقريرية مستقرة
-- -------------------------------------------------------------
drop view if exists public.v_finance_receiver_monthly cascade;

create view public.v_finance_receiver_monthly
with (security_invoker=true) as
select
  date_trunc('month', coalesce(p.payment_date, p.created_at::date)::timestamp)::date as month_start,
  p.received_by,
  coalesce(p.receiver_name, rb.name, p.created_by_name, 'غير محدد') as receiver_name,
  coalesce(rb.role, p.receiver_role) as receiver_role,
  count(*) filter (where coalesce(p.voided,false)=false) as payments_count,
  count(*) filter (where coalesce(p.voided,false)=true) as voided_count,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false),0) as total_usd,
  coalesce(sum(coalesce(p.amount_irr,0)) filter (where coalesce(p.voided,false)=false),0) as total_irr,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false and p.payment_method='cash'),0) as cash_usd,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false and p.payment_method='card'),0) as card_usd,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false and p.payment_method='transfer'),0) as transfer_usd,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false and p.payment_method not in ('cash','card','transfer')),0) as other_usd
from public.fee_payments p
left join public.users rb on rb.id = p.received_by
where public.finance_can_manage()
group by date_trunc('month', coalesce(p.payment_date, p.created_at::date)::timestamp)::date, p.received_by, coalesce(p.receiver_name, rb.name, p.created_by_name, 'غير محدد'), coalesce(rb.role, p.receiver_role);

grant select on public.v_finance_receiver_monthly to authenticated;

-- -------------------------------------------------------------
-- 4) Payload تقرير المستلمين ضمن فترة
-- -------------------------------------------------------------
create or replace function public.get_finance_receiver_report(
  p_from date default current_date,
  p_to date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  by_receiver jsonb;
  by_method jsonb;
  payments jsonb;
  stats jsonb;
  d1 date := coalesce(p_from, current_date);
  d2 date := coalesce(p_to, coalesce(p_from,current_date));
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية عرض التقرير المالي');
  end if;

  if d2 < d1 then
    d2 := d1;
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_usd desc), '[]'::jsonb)
  into by_receiver
  from (
    select
      coalesce(p.receiver_name, rb.name, p.created_by_name, 'غير محدد') as receiver_name,
      p.received_by,
      coalesce(rb.role, p.receiver_role) as receiver_role,
      count(*) filter (where coalesce(p.voided,false)=false) as payments_count,
      count(*) filter (where coalesce(p.voided,false)=true) as voided_count,
      coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false),0) as total_usd,
      coalesce(sum(coalesce(p.amount_irr,0)) filter (where coalesce(p.voided,false)=false),0) as total_irr
    from public.fee_payments p
    left join public.users rb on rb.id = p.received_by
    where coalesce(p.payment_date, p.created_at::date) between d1 and d2
    group by coalesce(p.receiver_name, rb.name, p.created_by_name, 'غير محدد'), p.received_by, coalesce(rb.role, p.receiver_role)
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_usd desc), '[]'::jsonb)
  into by_method
  from (
    select
      coalesce(p.payment_method,'cash') as payment_method,
      count(*) filter (where coalesce(p.voided,false)=false) as payments_count,
      coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false),0) as total_usd,
      coalesce(sum(coalesce(p.amount_irr,0)) filter (where coalesce(p.voided,false)=false),0) as total_irr
    from public.fee_payments p
    where coalesce(p.payment_date, p.created_at::date) between d1 and d2
    group by coalesce(p.payment_method,'cash')
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into payments
  from (
    select
      p.id,
      p.receipt_number,
      coalesce(p.payment_date, p.created_at::date) as payment_date,
      p.created_at,
      p.student_fee_id,
      sf.student_id,
      s.name as student_name,
      c.name as class_name,
      coalesce(p.amount_usd,p.amount,0) as amount_usd,
      coalesce(p.amount_irr,0) as amount_irr,
      p.currency,
      p.payment_method,
      p.payer_name,
      coalesce(p.receiver_name, rb.name, p.created_by_name, 'غير محدد') as receiver_name,
      p.transfer_number,
      p.voided,
      p.void_reason,
      p.voided_at
    from public.fee_payments p
    left join public.users rb on rb.id = p.received_by
    left join public.student_fees sf on sf.id = p.student_fee_id
    left join public.students s on s.id = sf.student_id
    left join public.classes c on c.id = s.class_id
    where coalesce(p.payment_date, p.created_at::date) between d1 and d2
    order by p.created_at desc
    limit 500
  ) x;

  stats := jsonb_build_object(
    'from', d1,
    'to', d2,
    'payments_count', (select count(*) from public.fee_payments p where coalesce(p.payment_date,p.created_at::date) between d1 and d2 and coalesce(p.voided,false)=false),
    'voided_count', (select count(*) from public.fee_payments p where coalesce(p.payment_date,p.created_at::date) between d1 and d2 and coalesce(p.voided,false)=true),
    'total_usd', (select coalesce(sum(coalesce(p.amount_usd,p.amount,0)),0) from public.fee_payments p where coalesce(p.payment_date,p.created_at::date) between d1 and d2 and coalesce(p.voided,false)=false),
    'total_irr', (select coalesce(sum(coalesce(p.amount_irr,0)),0) from public.fee_payments p where coalesce(p.payment_date,p.created_at::date) between d1 and d2 and coalesce(p.voided,false)=false),
    'receivers_count', jsonb_array_length(coalesce(by_receiver,'[]'::jsonb))
  );

  return jsonb_build_object('ok', true, 'stats', stats, 'by_receiver', by_receiver, 'by_method', by_method, 'payments', payments);
end;
$$;

grant execute on function public.get_finance_receiver_report(date,date) to authenticated;

-- -------------------------------------------------------------
-- 5) تعديل المستلم لدفعة قديمة
-- -------------------------------------------------------------
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
  old_p record;
  u record;
  final_name text;
  final_role text;
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل مستلم الدفعة');
  end if;

  select * into old_p from public.fee_payments where id = p_payment_id;
  if old_p.id is null then
    return jsonb_build_object('ok', false, 'message', 'الدفعة غير موجودة');
  end if;

  if p_received_by is not null then
    select * into u from public.users where id = p_received_by;
  end if;

  final_name := coalesce(nullif(trim(p_receiver_name),''), u.name, u.email, old_p.receiver_name, old_p.created_by_name, 'غير محدد');
  final_role := coalesce(nullif(trim(p_receiver_role),''), u.role, old_p.receiver_role);

  update public.fee_payments
  set received_by = p_received_by,
      receiver_name = final_name,
      receiver_role = final_role,
      updated_at = now()
  where id = p_payment_id;

  insert into public.finance_audit_logs(table_name, record_id, action, old_data, new_data, actor_id, actor_name)
  values ('fee_payments', p_payment_id, 'UPDATE_RECEIVER', to_jsonb(old_p), (select to_jsonb(p) from public.fee_payments p where p.id = p_payment_id), auth.uid(), (select name from public.users where id=auth.uid()));

  return jsonb_build_object('ok', true, 'message', 'تم تحديث مستلم الدفعة', 'receiver_name', final_name);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.update_payment_receiver(uuid,uuid,text,text) to authenticated;

-- -------------------------------------------------------------
-- 6) إلغاء دفعة آمن مع عكس الأرصدة
-- -------------------------------------------------------------
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

  if nullif(trim(coalesce(p_reason,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'سبب إلغاء الدفعة مطلوب');
  end if;

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
        status = case when new_fee_paid <= 0 then 'unpaid' when new_fee_paid < coalesce(net_amount,base_amount,0) then 'partial' else 'paid' end,
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

  insert into public.finance_audit_logs(table_name, record_id, action, old_data, new_data, actor_id, actor_name)
  values ('fee_payments', p_payment_id, 'VOID', to_jsonb(p), (select to_jsonb(px) from public.fee_payments px where px.id=p_payment_id), auth.uid(), (select name from public.users where id=auth.uid()));

  return jsonb_build_object('ok', true, 'message', 'تم إلغاء الدفعة وعكس الأرصدة', 'amount_usd', usd);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.void_fee_payment(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 7) فحص
-- -------------------------------------------------------------
create or replace function public.finance_receiver_analytics_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'receiver_monthly_view', to_regclass('public.v_finance_receiver_monthly') is not null,
    'receiver_report_rpc', to_regprocedure('public.get_finance_receiver_report(date,date)') is not null,
    'update_receiver_rpc', to_regprocedure('public.update_payment_receiver(uuid,uuid,text,text)') is not null,
    'void_payment_rpc', to_regprocedure('public.void_fee_payment(uuid,text)') is not null,
    'payments_total', (select count(*) from public.fee_payments),
    'voided_total', (select count(*) from public.fee_payments where coalesce(voided,false)=true),
    'today_report', public.get_finance_receiver_report(current_date,current_date)->'stats'
  );
end;
$$;

grant execute on function public.finance_receiver_analytics_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_receiver_analytics_voiding_ready' as status;

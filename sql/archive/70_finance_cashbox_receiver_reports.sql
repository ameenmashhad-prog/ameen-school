-- =============================================================
-- مدارس أمين الرضا (ع) — صندوق اليومية وتقارير المستلم المالي
-- حسب مستلم المبلغ: المسؤول المالي / المدير / أي مستلم يدوي.
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
-- 1) أعمدة مستلم الدفعة
-- -------------------------------------------------------------
alter table public.fee_payments add column if not exists received_by uuid null references public.users(id) on delete set null;
alter table public.fee_payments add column if not exists receiver_name text;
alter table public.fee_payments add column if not exists receiver_role text;
alter table public.fee_payments add column if not exists voided boolean not null default false;
alter table public.fee_payments add column if not exists amount_usd numeric;
alter table public.fee_payments add column if not exists amount_irr numeric;
alter table public.fee_payments add column if not exists payment_method text not null default 'cash';
alter table public.fee_payments add column if not exists payment_date date;
alter table public.fee_payments add column if not exists receipt_number text;
alter table public.fee_payments add column if not exists created_by uuid null references public.users(id);
alter table public.fee_payments add column if not exists created_by_name text;

create index if not exists idx_fee_payments_receiver_date on public.fee_payments(payment_date, received_by, receiver_name);

-- تعبئة السجلات القديمة
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
-- 2) إغلاقات صندوق اليومية
-- -------------------------------------------------------------
create table if not exists public.finance_cashbox_closures (
  id uuid primary key default gen_random_uuid(),
  cashbox_date date not null,
  receiver_id uuid null references public.users(id) on delete set null,
  receiver_name text not null,
  expected_usd numeric not null default 0,
  expected_irr numeric not null default 0,
  actual_usd numeric not null default 0,
  actual_irr numeric not null default 0,
  variance_usd numeric not null default 0,
  variance_irr numeric not null default 0,
  payments_count int not null default 0,
  summary jsonb not null default '{}'::jsonb,
  status text not null default 'closed' check (status in ('draft','closed','reviewed','cancelled')),
  closed_by uuid null references public.users(id),
  closed_at timestamptz not null default now(),
  reviewed_by uuid null references public.users(id),
  reviewed_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(cashbox_date, receiver_name)
);

create index if not exists idx_finance_cashbox_date on public.finance_cashbox_closures(cashbox_date desc, receiver_name);

alter table public.finance_cashbox_closures enable row level security;

drop policy if exists finance_cashbox_manage on public.finance_cashbox_closures;
create policy finance_cashbox_manage on public.finance_cashbox_closures
  for all to authenticated
  using (public.finance_can_manage())
  with check (public.finance_can_manage());

grant select, insert, update on public.finance_cashbox_closures to authenticated;

-- -------------------------------------------------------------
-- 3) View تفصيلي للمدفوعات
-- -------------------------------------------------------------
create or replace view public.v_fee_payments_detailed
with (security_invoker=true) as
select
  p.*,
  coalesce(p.receiver_name, rb.name, p.created_by_name, 'غير محدد') as effective_receiver_name,
  rb.name as received_by_name,
  rb.email as received_by_email,
  rb.role as received_by_role,
  sf.student_id,
  s.name as student_name,
  s.class_id,
  c.name as class_name
from public.fee_payments p
left join public.users rb on rb.id = p.received_by
left join public.student_fees sf on sf.id = p.student_fee_id
left join public.students s on s.id = sf.student_id
left join public.classes c on c.id = s.class_id
where public.finance_can_manage()
   or exists(select 1 from public.students st where st.id = sf.student_id and (st.user_id = auth.uid() or st.parent_id = auth.uid()));

grant select on public.v_fee_payments_detailed to authenticated;

create or replace view public.v_finance_cashbox_daily
with (security_invoker=true) as
select
  coalesce(p.payment_date, p.created_at::date) as cashbox_date,
  p.received_by as receiver_id,
  coalesce(p.receiver_name, rb.name, p.created_by_name, 'غير محدد') as receiver_name,
  coalesce(rb.role, p.receiver_role) as receiver_role,
  count(*) filter (where coalesce(p.voided,false)=false) as payments_count,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false),0) as total_usd,
  coalesce(sum(coalesce(p.amount_irr,0)) filter (where coalesce(p.voided,false)=false),0) as total_irr,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false and p.payment_method='cash'),0) as cash_usd,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false and p.payment_method='card'),0) as card_usd,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false and p.payment_method='transfer'),0) as transfer_usd,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false and p.payment_method not in ('cash','card','transfer')),0) as other_usd,
  bool_or(cl.id is not null and cl.status in ('closed','reviewed')) as is_closed,
  max(cl.closed_at) as last_closed_at
from public.fee_payments p
left join public.users rb on rb.id = p.received_by
left join public.finance_cashbox_closures cl
  on cl.cashbox_date = coalesce(p.payment_date, p.created_at::date)
 and cl.receiver_name = coalesce(p.receiver_name, rb.name, p.created_by_name, 'غير محدد')
where public.finance_can_manage()
group by coalesce(p.payment_date, p.created_at::date), p.received_by, coalesce(p.receiver_name, rb.name, p.created_by_name, 'غير محدد'), coalesce(rb.role, p.receiver_role);

grant select on public.v_finance_cashbox_daily to authenticated;

-- -------------------------------------------------------------
-- 4) Payload للتقرير
-- -------------------------------------------------------------
create or replace function public.get_finance_cashbox_payload(p_date date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  rows_json jsonb;
  payments_json jsonb;
  closures_json jsonb;
  stats_json jsonb;
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية عرض صندوق اليومية');
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.receiver_name), '[]'::jsonb)
  into rows_json
  from (
    select *
    from public.v_finance_cashbox_daily
    where cashbox_date = coalesce(p_date,current_date)
  ) x;

  select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc), '[]'::jsonb)
  into payments_json
  from (
    select
      id,
      receipt_number,
      payment_date,
      created_at,
      student_name,
      class_name,
      amount_usd,
      amount_irr,
      amount,
      currency,
      payment_method,
      payer_name,
      effective_receiver_name,
      transfer_number,
      voided
    from public.v_fee_payments_detailed
    where coalesce(payment_date, created_at::date) = coalesce(p_date,current_date)
  ) p;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.closed_at desc), '[]'::jsonb)
  into closures_json
  from public.finance_cashbox_closures c
  where c.cashbox_date = coalesce(p_date,current_date);

  stats_json := jsonb_build_object(
    'date', coalesce(p_date,current_date),
    'payments_count', (select count(*) from public.v_fee_payments_detailed where coalesce(payment_date, created_at::date)=coalesce(p_date,current_date) and coalesce(voided,false)=false),
    'total_usd', (select coalesce(sum(coalesce(amount_usd,amount,0)),0) from public.v_fee_payments_detailed where coalesce(payment_date, created_at::date)=coalesce(p_date,current_date) and coalesce(voided,false)=false),
    'total_irr', (select coalesce(sum(coalesce(amount_irr,0)),0) from public.v_fee_payments_detailed where coalesce(payment_date, created_at::date)=coalesce(p_date,current_date) and coalesce(voided,false)=false),
    'receivers_count', jsonb_array_length(coalesce(rows_json,'[]'::jsonb)),
    'closures_count', jsonb_array_length(coalesce(closures_json,'[]'::jsonb))
  );

  return jsonb_build_object('ok', true, 'stats', stats_json, 'receivers', rows_json, 'payments', payments_json, 'closures', closures_json);
end;
$$;

grant execute on function public.get_finance_cashbox_payload(date) to authenticated;

-- -------------------------------------------------------------
-- 5) إغلاق صندوق مستلم
-- -------------------------------------------------------------
create or replace function public.close_finance_cashbox(
  p_date date,
  p_receiver_name text,
  p_receiver_id uuid default null,
  p_actual_usd numeric default 0,
  p_actual_irr numeric default 0,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  expected_usd numeric := 0;
  expected_irr numeric := 0;
  cnt int := 0;
  summary_json jsonb;
  closure_id uuid;
  old_row record;
  v_receiver_name text := coalesce(nullif(trim(p_receiver_name),''),'غير محدد');
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إغلاق صندوق اليومية');
  end if;

  select
    coalesce(sum(coalesce(amount_usd,amount,0)) filter (where coalesce(voided,false)=false),0),
    coalesce(sum(coalesce(amount_irr,0)) filter (where coalesce(voided,false)=false),0),
    count(*) filter (where coalesce(voided,false)=false),
    jsonb_build_object(
      'cash_usd', coalesce(sum(coalesce(amount_usd,amount,0)) filter (where coalesce(voided,false)=false and payment_method='cash'),0),
      'card_usd', coalesce(sum(coalesce(amount_usd,amount,0)) filter (where coalesce(voided,false)=false and payment_method='card'),0),
      'transfer_usd', coalesce(sum(coalesce(amount_usd,amount,0)) filter (where coalesce(voided,false)=false and payment_method='transfer'),0),
      'other_usd', coalesce(sum(coalesce(amount_usd,amount,0)) filter (where coalesce(voided,false)=false and payment_method not in ('cash','card','transfer')),0)
    )
  into expected_usd, expected_irr, cnt, summary_json
  from public.v_fee_payments_detailed
  where coalesce(payment_date, created_at::date) = coalesce(p_date,current_date)
    and effective_receiver_name = v_receiver_name;

  select * into old_row
  from public.finance_cashbox_closures
  where cashbox_date = coalesce(p_date,current_date)
    and receiver_name = v_receiver_name;

  if old_row.id is not null then
    update public.finance_cashbox_closures
    set receiver_id = p_receiver_id,
        expected_usd = expected_usd,
        expected_irr = expected_irr,
        actual_usd = coalesce(p_actual_usd,0),
        actual_irr = coalesce(p_actual_irr,0),
        variance_usd = coalesce(p_actual_usd,0) - expected_usd,
        variance_irr = coalesce(p_actual_irr,0) - expected_irr,
        payments_count = cnt,
        summary = summary_json,
        status = 'closed',
        closed_by = auth.uid(),
        closed_at = now(),
        notes = p_notes,
        updated_at = now()
    where id = old_row.id
    returning id into closure_id;
  else
    insert into public.finance_cashbox_closures(
      cashbox_date,
      receiver_id,
      receiver_name,
      expected_usd,
      expected_irr,
      actual_usd,
      actual_irr,
      variance_usd,
      variance_irr,
      payments_count,
      summary,
      status,
      closed_by,
      notes
    ) values (
      coalesce(p_date,current_date),
      p_receiver_id,
      v_receiver_name,
      expected_usd,
      expected_irr,
      coalesce(p_actual_usd,0),
      coalesce(p_actual_irr,0),
      coalesce(p_actual_usd,0) - expected_usd,
      coalesce(p_actual_irr,0) - expected_irr,
      cnt,
      summary_json,
      'closed',
      auth.uid(),
      p_notes
    ) returning id into closure_id;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم إغلاق صندوق المستلم', 'closure_id', closure_id, 'expected_usd', expected_usd, 'actual_usd', coalesce(p_actual_usd,0), 'variance_usd', coalesce(p_actual_usd,0)-expected_usd, 'payments_count', cnt);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.close_finance_cashbox(date,text,uuid,numeric,numeric,text) to authenticated;

-- -------------------------------------------------------------
-- 6) فحص
-- -------------------------------------------------------------
create or replace function public.finance_cashbox_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'receiver_columns', jsonb_build_object(
      'received_by', exists(select 1 from information_schema.columns where table_schema='public' and table_name='fee_payments' and column_name='received_by'),
      'receiver_name', exists(select 1 from information_schema.columns where table_schema='public' and table_name='fee_payments' and column_name='receiver_name'),
      'receiver_role', exists(select 1 from information_schema.columns where table_schema='public' and table_name='fee_payments' and column_name='receiver_role')
    ),
    'closures_table', to_regclass('public.finance_cashbox_closures') is not null,
    'payments_view', to_regclass('public.v_fee_payments_detailed') is not null,
    'cashbox_view', to_regclass('public.v_finance_cashbox_daily') is not null,
    'payload_rpc', to_regprocedure('public.get_finance_cashbox_payload(date)') is not null,
    'close_rpc', to_regprocedure('public.close_finance_cashbox(date,text,uuid,numeric,numeric,text)') is not null,
    'today_payload', public.get_finance_cashbox_payload(current_date)->'stats'
  );
end;
$$;

grant execute on function public.finance_cashbox_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_cashbox_receiver_reports_ready' as status;

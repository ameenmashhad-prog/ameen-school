-- =============================================================
-- مدارس أمين الرضا (ع) — النظام المالي الاحترافي
-- رسوم، خصومات، خطط أقساط، مدفوعات، أسعار صرف، Audit Trail
-- لا يحذف البيانات القديمة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) دالة تحويل ميلادي -> شمسي إيراني للتوثيق المالي
-- -------------------------------------------------------------
create or replace function public.gregorian_to_persian(p_date date)
returns jsonb
language plpgsql
immutable
as $$
declare
  gy int := extract(year from p_date)::int - 1600;
  gm int := extract(month from p_date)::int - 1;
  gd int := extract(day from p_date)::int - 1;
  g_days int[] := array[31,28,31,30,31,30,31,31,30,31,30,31];
  j_days int[] := array[31,31,31,31,31,31,30,30,30,30,30,29];
  g_day_no int;
  j_day_no int;
  j_np int;
  jy int;
  jm int := 0;
  jd int := 0;
  i int;
begin
  g_day_no := 365 * gy + floor((gy + 3) / 4)::int - floor((gy + 99) / 100)::int + floor((gy + 399) / 400)::int;
  for i in 1..gm loop
    g_day_no := g_day_no + g_days[i];
  end loop;
  if gm > 1 and ((gy + 1600) % 4 = 0 and ((gy + 1600) % 100 <> 0 or (gy + 1600) % 400 = 0)) then
    g_day_no := g_day_no + 1;
  end if;
  g_day_no := g_day_no + gd;
  j_day_no := g_day_no - 79;
  j_np := floor(j_day_no / 12053)::int;
  j_day_no := j_day_no % 12053;
  jy := 979 + 33 * j_np + 4 * floor(j_day_no / 1461)::int;
  j_day_no := j_day_no % 1461;
  if j_day_no >= 366 then
    jy := jy + floor((j_day_no - 1) / 365)::int;
    j_day_no := (j_day_no - 1) % 365;
  end if;
  for i in 1..12 loop
    if j_day_no < j_days[i] then
      jm := i;
      jd := j_day_no + 1;
      exit;
    end if;
    j_day_no := j_day_no - j_days[i];
  end loop;
  return jsonb_build_object('year',jy,'month',jm,'day',jd,'formatted',jy||'-'||lpad(jm::text,2,'0')||'-'||lpad(jd::text,2,'0'));
end;
$$;

-- -------------------------------------------------------------
-- 2) إعداد fee_structures ليحمل الرسوم السنوية والسنوي
-- -------------------------------------------------------------
create table if not exists public.fee_structures (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  monthly_fee numeric not null default 0,
  annual_fee numeric,
  currency text not null default 'USD',
  academic_year text not null default '2026-2027',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(class_id, academic_year)
);

alter table public.fee_structures add column if not exists monthly_fee numeric not null default 0;
alter table public.fee_structures add column if not exists amount numeric not null default 0;
alter table public.fee_structures add column if not exists annual_fee numeric;
alter table public.fee_structures add column if not exists academic_year text not null default '2026-2027';
alter table public.fee_structures add column if not exists is_active boolean not null default true;
alter table public.fee_structures add column if not exists updated_at timestamptz not null default now();

-- مزامنة fee_structures القديمة التي تستخدم amount بدلاً من monthly_fee.
update public.fee_structures
set annual_fee = coalesce(annual_fee, nullif(monthly_fee,0) * 9, amount, 0),
    amount = coalesce(annual_fee, amount, nullif(monthly_fee,0) * 9, 0),
    monthly_fee = case
      when monthly_fee is null or monthly_fee = 0 then round((coalesce(annual_fee, amount, 0) / 9.0)::numeric, 2)
      else monthly_fee
    end
where amount is null or monthly_fee is null or annual_fee is null or annual_fee = 0;

-- -------------------------------------------------------------
-- 3) توسيع student_fees
-- -------------------------------------------------------------
alter table public.student_fees add column if not exists class_id uuid null references public.classes(id) on delete set null;
alter table public.student_fees add column if not exists academic_year text not null default '2026-2027';
alter table public.student_fees add column if not exists fee_structure_id uuid null references public.fee_structures(id) on delete set null;
alter table public.student_fees add column if not exists gross_amount numeric;
alter table public.student_fees add column if not exists discount_amount numeric not null default 0;
alter table public.student_fees add column if not exists discount_reason text;
alter table public.student_fees add column if not exists plan_type text default 'custom';
alter table public.student_fees add column if not exists installments_count int;
alter table public.student_fees add column if not exists created_by uuid null references public.users(id);
alter table public.student_fees add column if not exists updated_by uuid null references public.users(id);
alter table public.student_fees add column if not exists updated_at timestamptz not null default now();
alter table public.student_fees add column if not exists notes text;

-- -------------------------------------------------------------
-- 4) خطط الأقساط المرنة
-- -------------------------------------------------------------
create table if not exists public.finance_payment_plans (
  id uuid primary key default gen_random_uuid(),
  student_fee_id uuid not null references public.student_fees(id) on delete cascade,
  plan_type text not null default 'custom' check (plan_type in ('two','three','four','six','monthly','quarterly','custom')),
  installments_count int not null check (installments_count > 0),
  start_date date not null,
  end_date date not null,
  status text not null default 'active' check (status in ('active','closed','cancelled')),
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  notes text
);

-- -------------------------------------------------------------
-- 5) توسيع الأقساط
-- -------------------------------------------------------------
alter table public.student_installments add column if not exists installment_number int;
alter table public.student_installments add column if not exists due_date date;
alter table public.student_installments add column if not exists actual_payment_date date;
alter table public.student_installments add column if not exists balance_remaining numeric not null default 0;
alter table public.student_installments add column if not exists note text;
alter table public.student_installments add column if not exists updated_at timestamptz not null default now();

create index if not exists idx_installments_due_status on public.student_installments(due_date, status);

-- -------------------------------------------------------------
-- 6) أسعار الصرف
-- -------------------------------------------------------------
create table if not exists public.exchange_rates (
  id uuid primary key default gen_random_uuid(),
  base_currency text not null default 'USD',
  quote_currency text not null default 'IRR',
  rate numeric not null,
  source text not null default 'manual',
  source_url text,
  is_manual boolean not null default true,
  rate_date date not null default current_date,
  fetched_at timestamptz not null default now(),
  created_by uuid null references public.users(id),
  notes text
);

create index if not exists idx_exchange_rates_date on public.exchange_rates(rate_date desc, fetched_at desc);

-- -------------------------------------------------------------
-- 7) توسيع المدفوعات
-- -------------------------------------------------------------
alter table public.fee_payments add column if not exists student_fee_id uuid null references public.student_fees(id) on delete set null;
alter table public.fee_payments add column if not exists student_installment_id uuid null references public.student_installments(id) on delete set null;
alter table public.fee_payments add column if not exists payment_method text not null default 'cash';
alter table public.fee_payments add column if not exists payment_date date;
alter table public.fee_payments add column if not exists currency text not null default 'USD';
alter table public.fee_payments add column if not exists amount_usd numeric;
alter table public.fee_payments add column if not exists amount_irr numeric;
alter table public.fee_payments add column if not exists exchange_rate_id uuid null references public.exchange_rates(id) on delete set null;
alter table public.fee_payments add column if not exists exchange_rate_value numeric;
alter table public.fee_payments add column if not exists transfer_number text;
alter table public.fee_payments add column if not exists transfer_date date;
alter table public.fee_payments add column if not exists transfer_source text;
alter table public.fee_payments add column if not exists payer_name text;
alter table public.fee_payments add column if not exists payer_relationship text;
alter table public.fee_payments add column if not exists receipt_number text;
alter table public.fee_payments add column if not exists created_by uuid null references public.users(id);
alter table public.fee_payments add column if not exists created_by_name text;
alter table public.fee_payments add column if not exists voided boolean not null default false;
alter table public.fee_payments add column if not exists void_reason text;
alter table public.fee_payments add column if not exists updated_at timestamptz not null default now();

create index if not exists idx_fee_payments_date on public.fee_payments(payment_date desc, created_at desc);
create index if not exists idx_fee_payments_receipt on public.fee_payments(receipt_number);

-- -------------------------------------------------------------
-- 8) Audit Trail مالي
-- -------------------------------------------------------------
create table if not exists public.finance_audit_logs (
  id uuid primary key default gen_random_uuid(),
  table_name text not null,
  record_id text,
  action text not null,
  user_id uuid null default auth.uid(),
  gregorian_at timestamptz not null default now(),
  persian_date jsonb not null default public.gregorian_to_persian(current_date),
  old_data jsonb,
  new_data jsonb,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_finance_audit_table_record on public.finance_audit_logs(table_name, record_id, gregorian_at desc);
create index if not exists idx_finance_audit_user on public.finance_audit_logs(user_id, gregorian_at desc);

create or replace function public.finance_audit_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rid text;
begin
  rid := coalesce((case when tg_op='DELETE' then old.id else new.id end)::text, null);
  insert into public.finance_audit_logs(table_name, record_id, action, old_data, new_data)
  values (
    tg_table_name,
    rid,
    tg_op,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end
  );
  return case when tg_op='DELETE' then old else new end;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['fee_structures','student_fees','finance_payment_plans','student_installments','fee_payments','exchange_rates'] loop
    execute format('drop trigger if exists trg_finance_audit_%I on public.%I', t, t);
    execute format('create trigger trg_finance_audit_%I after insert or update or delete on public.%I for each row execute function public.finance_audit_trigger()', t, t);
  end loop;
end $$;

-- أعمدة اسم الطالب المالية إن لم تكن موجودة في جدول students.
alter table public.students add column if not exists father_name text;
alter table public.students add column if not exists mother_name text;
alter table public.students add column if not exists last_name text;

-- حذف Views القديمة قبل إعادة إنشائها حتى لا تفشل عند اختلاف الأعمدة.
drop view if exists public.v_finance_class_revenue;
drop view if exists public.v_finance_installment_status;
drop view if exists public.v_finance_student_ledger;

-- -------------------------------------------------------------
-- 9) Views وتقارير
-- -------------------------------------------------------------
create or replace view public.v_finance_student_ledger
with (security_invoker=true) as
select
  s.id as student_id,
  s.name as student_name,
  s.father_name,
  s.last_name,
  c.name as class_name,
  p.name as parent_name,
  sf.id as student_fee_id,
  sf.academic_year,
  coalesce(sf.gross_amount, sf.base_amount, 0) as gross_amount,
  coalesce(sf.discount_amount, 0) as discount_amount,
  coalesce(sf.net_amount, sf.base_amount, 0) as net_amount,
  coalesce(sf.total_paid, 0) as total_paid,
  greatest(coalesce(sf.net_amount, sf.base_amount, 0) - coalesce(sf.total_paid, 0), 0) as remaining_amount,
  sf.status
from public.students s
left join public.classes c on c.id = s.class_id
left join public.users p on p.id = s.parent_id
left join public.student_fees sf on sf.student_id = s.id;

create or replace view public.v_finance_installment_status
with (security_invoker=true) as
select
  si.*,
  sf.student_id,
  s.name as student_name,
  c.name as class_name,
  case
    when coalesce(si.amount_paid,0) >= coalesce(si.amount_due,0) and coalesce(si.amount_due,0) > 0 then 'مدفوع'
    when coalesce(si.amount_paid,0) > 0 then 'مدفوع جزئياً'
    when si.due_date is not null and si.due_date < current_date then 'متأخر'
    else 'غير مدفوع'
  end as status_ar
from public.student_installments si
left join public.student_fees sf on sf.id = si.student_fee_id
left join public.students s on s.id = sf.student_id
left join public.classes c on c.id = s.class_id;

create or replace view public.v_finance_class_revenue
with (security_invoker=true) as
select
  c.id as class_id,
  c.name as class_name,
  count(distinct s.id) as students_count,
  coalesce(sum(coalesce(sf.net_amount, sf.base_amount, 0)),0) as total_due,
  coalesce(sum(coalesce(sf.total_paid, 0)),0) as total_paid,
  coalesce(sum(coalesce(sf.discount_amount, 0)),0) as total_discounts,
  greatest(coalesce(sum(coalesce(sf.net_amount, sf.base_amount, 0)),0)-coalesce(sum(coalesce(sf.total_paid, 0)),0),0) as total_remaining
from public.classes c
left join public.students s on s.class_id = c.id
left join public.student_fees sf on sf.student_id = s.id
group by c.id, c.name;

grant select on public.v_finance_student_ledger to authenticated;
grant select on public.v_finance_installment_status to authenticated;
grant select on public.v_finance_class_revenue to authenticated;
grant select on public.finance_audit_logs to authenticated;

-- -------------------------------------------------------------
-- 10) RLS أساسي: المدير والمالي فقط لإدارة المالي، الطالب/ولي الأمر يقرأ بياناته عبر سياساتك الحالية أو views لاحقاً
-- -------------------------------------------------------------
alter table public.exchange_rates enable row level security;
alter table public.finance_payment_plans enable row level security;
alter table public.finance_audit_logs enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='exchange_rates' and policyname='exchange_rates_finance_read') then
    create policy exchange_rates_finance_read on public.exchange_rates for select to authenticated using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='exchange_rates' and policyname='exchange_rates_finance_write') then
    create policy exchange_rates_finance_write on public.exchange_rates for insert to authenticated
    with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','finance') or coalesce(u.is_super_admin,false)=true)));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='finance_audit_logs' and policyname='finance_audit_admin_read') then
    create policy finance_audit_admin_read on public.finance_audit_logs for select to authenticated
    using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','finance') or coalesce(u.is_super_admin,false)=true)));
  end if;
end $$;

-- تحديث PostgREST schema cache في Supabase
notify pgrst, 'reload schema';

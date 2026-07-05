-- =============================================================
-- مدارس أمين الرضا (ع) — Hotfix توافق المخطط الحالي
-- شغّلي هذا الملف أولاً إذا ظهرت أخطاء أعمدة مفقودة.
-- لا يحذف بيانات.
-- =============================================================

create extension if not exists pgcrypto;

-- fee_structures compatibility
alter table public.fee_structures add column if not exists amount numeric not null default 0;
alter table public.fee_structures add column if not exists monthly_fee numeric not null default 0;
alter table public.fee_structures add column if not exists annual_fee numeric;
alter table public.fee_structures add column if not exists currency text not null default 'USD';
alter table public.fee_structures add column if not exists academic_year text not null default '2026-2027';
alter table public.fee_structures add column if not exists is_active boolean not null default true;
alter table public.fee_structures add column if not exists updated_at timestamptz not null default now();

update public.fee_structures
set annual_fee = coalesce(annual_fee, nullif(monthly_fee,0) * 9, amount, 0),
    amount = coalesce(annual_fee, amount, nullif(monthly_fee,0) * 9, 0),
    monthly_fee = case
      when monthly_fee is null or monthly_fee = 0 then round((coalesce(annual_fee, amount, 0) / 9.0)::numeric, 2)
      else monthly_fee
    end
where amount is null or monthly_fee is null or annual_fee is null or annual_fee = 0;

-- fee_payments compatibility
alter table public.fee_payments add column if not exists student_fee_id uuid null references public.student_fees(id) on delete set null;
alter table public.fee_payments add column if not exists student_installment_id uuid null references public.student_installments(id) on delete set null;
alter table public.fee_payments add column if not exists payment_method text not null default 'cash';
alter table public.fee_payments add column if not exists payment_date date;
alter table public.fee_payments add column if not exists currency text not null default 'USD';
alter table public.fee_payments add column if not exists amount_usd numeric;
alter table public.fee_payments add column if not exists amount_irr numeric;
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

-- students compatibility
alter table public.students add column if not exists father_name text;
alter table public.students add column if not exists mother_name text;
alter table public.students add column if not exists last_name text;

-- student_fees compatibility
alter table public.student_fees add column if not exists class_id uuid null references public.classes(id) on delete set null;
alter table public.student_fees add column if not exists academic_year text not null default '2026-2027';
alter table public.student_fees add column if not exists gross_amount numeric;
alter table public.student_fees add column if not exists discount_amount numeric not null default 0;
alter table public.student_fees add column if not exists discount_reason text;
alter table public.student_fees add column if not exists plan_type text default 'custom';
alter table public.student_fees add column if not exists installments_count int;
alter table public.student_fees add column if not exists created_by uuid null references public.users(id);
alter table public.student_fees add column if not exists updated_by uuid null references public.users(id);
alter table public.student_fees add column if not exists updated_at timestamptz not null default now();
alter table public.student_fees add column if not exists notes text;

-- student_installments compatibility
alter table public.student_installments add column if not exists installment_number int;
alter table public.student_installments add column if not exists due_date date;
alter table public.student_installments add column if not exists actual_payment_date date;
alter table public.student_installments add column if not exists balance_remaining numeric not null default 0;
alter table public.student_installments add column if not exists note text;
alter table public.student_installments add column if not exists updated_at timestamptz not null default now();

-- grades / behavior compatibility
alter table public.grades add column if not exists score numeric;
alter table public.grades add column if not exists grade numeric;
alter table public.grades add column if not exists mark numeric;
alter table public.grades add column if not exists value numeric;
alter table public.grades add column if not exists max_score numeric default 100;
alter table public.behavior_records add column if not exists points numeric default 0;
alter table public.behavior_records add column if not exists score numeric default 0;

-- remove potentially incompatible old views so files 10/11 can recreate them cleanly
drop view if exists public.v_finance_class_revenue;
drop view if exists public.v_finance_installment_status;
drop view if exists public.v_finance_student_ledger;
drop view if exists public.v_academic_student_summary;
drop view if exists public.v_academic_subject_results;

select 'hotfix_ok' as status;

-- تحديث PostgREST schema cache في Supabase
notify pgrst, 'reload schema';

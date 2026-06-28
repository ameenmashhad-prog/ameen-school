-- =============================================================
-- مدارس أمين الرضا (ع) — Hotfix تشغيل النظام المالي
-- يحل مشكلة payment_method في fee_payments ويحدّث schema cache.
-- =============================================================

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
alter table public.fee_payments add column if not exists note text;
alter table public.fee_payments add column if not exists created_by uuid null references public.users(id);
alter table public.fee_payments add column if not exists created_by_name text;
alter table public.fee_payments add column if not exists voided boolean not null default false;
alter table public.fee_payments add column if not exists void_reason text;
alter table public.fee_payments add column if not exists updated_at timestamptz not null default now();

-- تحديث PostgREST schema cache في Supabase
notify pgrst, 'reload schema';

select 'finance_runtime_hotfix_ok' as status;

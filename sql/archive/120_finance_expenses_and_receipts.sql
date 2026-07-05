-- ============================================================================
-- R5 و R8 — المصروفات وإرفاق صور السندات والفواتير في المالية
-- ينشئ جدول finance_expenses ومستودع التخزين finance-receipts، ويضيف عمود
-- attachment_url لجدول دفوعات الطلاب fee_payments، ويوفر دوال الإدارة والتقارير.
--
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

-- 1) جدول المصروفات المدرسية
create table if not exists public.finance_expenses (
  id uuid primary key default gen_random_uuid(),
  expense_code text unique default ('EXP-' || upper(substr(gen_random_uuid()::text,1,8))),
  title text not null,
  category text not null check (category in ('salaries','maintenance','utilities','supplies','activities','rent','other')),
  amount_usd numeric not null default 0,
  amount_irr numeric not null default 0,
  exchange_rate_value numeric,
  payment_method text not null default 'cash' check (payment_method in ('cash','bank_transfer','cheque','other')),
  payment_date date not null default current_date,
  beneficiary text,
  receipt_number text,
  attachment_url text,
  notes text,
  recorded_by uuid null references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2) إضافة عمود صورة السند لجدول دفعات الأقساط fee_payments
alter table public.fee_payments add column if not exists attachment_url text;

-- 3) مستودع تخزين صور السندات والفواتير (عام لتسهيل التحميل والعرض)
insert into storage.buckets (id, name, public)
values ('finance-receipts', 'finance-receipts', true)
on conflict (id) do update set public = true;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='finance_receipts_insert_all') then
    create policy finance_receipts_insert_all on storage.objects
      for insert to anon, authenticated
      with check (bucket_id = 'finance-receipts');
  end if;

  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='finance_receipts_select_all') then
    create policy finance_receipts_select_all on storage.objects
      for select to anon, authenticated
      using (bucket_id = 'finance-receipts');
  end if;

  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='finance_receipts_update_all') then
    create policy finance_receipts_update_all on storage.objects
      for update to anon, authenticated
      using (bucket_id = 'finance-receipts')
      with check (bucket_id = 'finance-receipts');
  end if;

  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='finance_receipts_delete_all') then
    create policy finance_receipts_delete_all on storage.objects
      for delete to anon, authenticated
      using (bucket_id = 'finance-receipts');
  end if;
end $$;

-- 4) سياسات RLS على جدول المصروفات
alter table public.finance_expenses enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='finance_expenses' and policyname='finance_expenses_manage') then
    create policy finance_expenses_manage on public.finance_expenses
      for all to authenticated
      using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','finance') or coalesce(u.is_super_admin,false)=true)))
      with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','finance') or coalesce(u.is_super_admin,false)=true)));
  end if;
end $$;

grant select, insert, update, delete on public.finance_expenses to authenticated, anon;

-- 5) فيو التقارير والتفاصيل
create or replace view public.v_finance_expenses_detailed
with (security_invoker = true) as
select e.*,
       coalesce(u.name, u.email, 'مسؤول مالي') as recorded_by_name
from public.finance_expenses e
left join public.users u on u.id = e.recorded_by;

grant select on public.v_finance_expenses_detailed to authenticated, anon;

-- 6) دوال تسجيل وحذف المصروفات
create or replace function public.finance_record_expense(
  p_title text,
  p_category text,
  p_amount_usd numeric,
  p_amount_irr numeric,
  p_exchange_rate numeric,
  p_payment_method text,
  p_payment_date date,
  p_beneficiary text,
  p_receipt_number text,
  p_attachment_url text,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_id uuid;
begin
  if coalesce(nullif(trim(p_title),''), '') = '' then
    return jsonb_build_object('ok', false, 'message', 'عنوان المصروف مطلوب');
  end if;
  if coalesce(p_amount_usd, 0) <= 0 and coalesce(p_amount_irr, 0) <= 0 then
    return jsonb_build_object('ok', false, 'message', 'يجب إدخال مبلغ أكبر من صفر');
  end if;

  insert into public.finance_expenses (
    title, category, amount_usd, amount_irr, exchange_rate_value,
    payment_method, payment_date, beneficiary, receipt_number, attachment_url, notes, recorded_by
  ) values (
    trim(p_title),
    case when p_category in ('salaries','maintenance','utilities','supplies','activities','rent','other') then p_category else 'other' end,
    coalesce(p_amount_usd, 0),
    coalesce(p_amount_irr, 0),
    p_exchange_rate,
    case when p_payment_method in ('cash','bank_transfer','cheque','other') then p_payment_method else 'cash' end,
    coalesce(p_payment_date, current_date),
    nullif(trim(p_beneficiary), ''),
    nullif(trim(p_receipt_number), ''),
    nullif(trim(p_attachment_url), ''),
    nullif(trim(p_notes), ''),
    auth.uid()
  ) returning id into v_id;

  return jsonb_build_object('ok', true, 'message', 'تم تسجيل المصروف وحفظ صورة السند بنجاح', 'expense_id', v_id);
end;
$$;

grant execute on function public.finance_record_expense(text,text,numeric,numeric,numeric,text,date,text,text,text,text) to authenticated, anon;

create or replace function public.finance_delete_expense(p_expense_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  delete from public.finance_expenses where id = p_expense_id;
  return jsonb_build_object('ok', true, 'message', 'تم حذف المصروف');
end;
$$;

grant execute on function public.finance_delete_expense(uuid) to authenticated, anon;

-- إعادة تحميل كاش المخطط في PostgREST
NOTIFY pgrst, 'reload schema';

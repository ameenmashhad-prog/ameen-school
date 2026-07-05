-- =============================================================
-- مدارس أمين الرضا (ع) — إضافة مستلم الدفعة المالية
-- يضيف اسم/حساب الشخص الذي استلم المبلغ: المسؤول المالي، المدير، أو شخص آخر.
-- =============================================================

create extension if not exists pgcrypto;

alter table public.fee_payments add column if not exists received_by uuid null references public.users(id) on delete set null;
alter table public.fee_payments add column if not exists receiver_name text;
alter table public.fee_payments add column if not exists receiver_role text;

create index if not exists idx_fee_payments_received_by on public.fee_payments(received_by, created_at desc);

-- تعبئة السجلات القديمة باسم منشئ الدفعة إن توفر، حتى لا تبقى فارغة.
update public.fee_payments fp
set received_by = coalesce(fp.received_by, fp.created_by),
    receiver_name = coalesce(fp.receiver_name, fp.created_by_name, u.name, u.email, 'غير محدد'),
    receiver_role = coalesce(fp.receiver_role, u.role)
from public.users u
where fp.created_by = u.id
  and (fp.received_by is null or fp.receiver_name is null or fp.receiver_role is null);

update public.fee_payments
set receiver_name = coalesce(receiver_name, created_by_name, 'غير محدد')
where receiver_name is null;

-- View اختياري لتقارير المدفوعات مع اسم المستلم
create or replace view public.v_fee_payments_detailed
with (security_invoker=true) as
select
  p.*,
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
left join public.classes c on c.id = s.class_id;

grant select on public.v_fee_payments_detailed to authenticated;

-- فحص سريع
create or replace function public.finance_payment_receiver_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'received_by_column', exists(select 1 from information_schema.columns where table_schema='public' and table_name='fee_payments' and column_name='received_by'),
    'receiver_name_column', exists(select 1 from information_schema.columns where table_schema='public' and table_name='fee_payments' and column_name='receiver_name'),
    'receiver_role_column', exists(select 1 from information_schema.columns where table_schema='public' and table_name='fee_payments' and column_name='receiver_role'),
    'view_exists', to_regclass('public.v_fee_payments_detailed') is not null,
    'payments_total', (select count(*) from public.fee_payments),
    'payments_without_receiver_name', (select count(*) from public.fee_payments where receiver_name is null or receiver_name='')
  );
end;
$$;

grant execute on function public.finance_payment_receiver_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_payment_receiver_ready' as status;

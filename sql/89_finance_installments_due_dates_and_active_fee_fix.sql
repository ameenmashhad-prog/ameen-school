-- =============================================================
-- مدارس أمين الرضا (ع) — إصلاح الأقساط بدون تواريخ + تشخيص خطة الدفع
-- يعالج:
-- 1) أقساط due_date = null فلا تظهر كمتأخرة ولا تتضح في التقارير.
-- 2) اختيار ملف مالي مدفوع/قديم بدلاً من الملف المفتوح في الواجهة.
-- آمن: preview أولاً، والتنفيذ فقط عند p_apply=true.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) تأكيد أعمدة أساسية
-- -------------------------------------------------------------
alter table public.student_installments add column if not exists due_date date;
alter table public.student_installments add column if not exists installment_number int;
alter table public.student_installments add column if not exists installment_month int;
alter table public.student_installments add column if not exists amount_due numeric default 0;
alter table public.student_installments add column if not exists amount_paid numeric default 0;
alter table public.student_installments add column if not exists balance_remaining numeric;
alter table public.student_installments add column if not exists status text default 'unpaid';
alter table public.student_installments add column if not exists updated_at timestamptz not null default now();

alter table public.student_fees add column if not exists net_amount numeric;
alter table public.student_fees add column if not exists base_amount numeric;
alter table public.student_fees add column if not exists gross_amount numeric;
alter table public.student_fees add column if not exists total_paid numeric default 0;
alter table public.student_fees add column if not exists status text default 'unpaid';
alter table public.student_fees add column if not exists updated_at timestamptz not null default now();

-- -------------------------------------------------------------
-- 2) إصلاح تواريخ الأقساط الفارغة — معاينة/تنفيذ
-- -------------------------------------------------------------
create or replace function public.finance_repair_null_installment_due_dates(
  p_student_fee_id uuid default null,
  p_start_date date default null,
  p_apply boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  preview jsonb;
  updated_count int := 0;
begin
  with target as (
    select
      si.id,
      si.student_fee_id,
      si.installment_number,
      si.due_date as old_due_date,
      si.amount_due,
      si.amount_paid,
      sf.student_id,
      s.name as student_name,
      coalesce(
        p_start_date,
        fpp.start_date,
        sf.created_at::date,
        current_date
      ) as base_date,
      row_number() over (
        partition by si.student_fee_id
        order by coalesce(si.installment_number,9999), si.created_at, si.id
      ) as rn
    from public.student_installments si
    join public.student_fees sf on sf.id = si.student_fee_id
    left join public.students s on s.id = sf.student_id
    left join public.finance_payment_plans fpp on fpp.student_fee_id = sf.id
    where si.due_date is null
      and coalesce(si.amount_due,0) > coalesce(si.amount_paid,0)
      and (p_student_fee_id is null or si.student_fee_id = p_student_fee_id)
  ), calc as (
    select
      *,
      (base_date + ((rn-1) || ' months')::interval)::date as new_due_date
    from target
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'installment_id', id,
    'student_fee_id', student_fee_id,
    'student_id', student_id,
    'student_name', student_name,
    'installment_number', installment_number,
    'amount_due', amount_due,
    'amount_paid', amount_paid,
    'old_due_date', old_due_date,
    'new_due_date', new_due_date
  ) order by student_name, new_due_date), '[]'::jsonb)
  into preview
  from calc;

  if coalesce(p_apply,false) then
    with target as (
      select
        si.id,
        coalesce(p_start_date, fpp.start_date, sf.created_at::date, current_date) as base_date,
        row_number() over (
          partition by si.student_fee_id
          order by coalesce(si.installment_number,9999), si.created_at, si.id
        ) as rn
      from public.student_installments si
      join public.student_fees sf on sf.id = si.student_fee_id
      left join public.finance_payment_plans fpp on fpp.student_fee_id = sf.id
      where si.due_date is null
        and coalesce(si.amount_due,0) > coalesce(si.amount_paid,0)
        and (p_student_fee_id is null or si.student_fee_id = p_student_fee_id)
    ), calc as (
      select id, (base_date + ((rn-1) || ' months')::interval)::date as new_due_date
      from target
    )
    update public.student_installments si
    set due_date = calc.new_due_date,
        installment_month = extract(month from calc.new_due_date)::int,
        balance_remaining = greatest(coalesce(si.amount_due,0)-coalesce(si.amount_paid,0),0),
        status = case
          when coalesce(si.amount_paid,0) >= coalesce(si.amount_due,0) then 'paid'
          when coalesce(si.amount_paid,0) > 0 then 'partial'
          else 'unpaid'
        end,
        updated_at = now()
    from calc
    where si.id = calc.id;

    get diagnostics updated_count = row_count;
  end if;

  return jsonb_build_object(
    'ok', true,
    'apply', coalesce(p_apply,false),
    'matched_count', jsonb_array_length(coalesce(preview,'[]'::jsonb)),
    'updated_count', updated_count,
    'preview', preview
  );
end;
$$;

grant execute on function public.finance_repair_null_installment_due_dates(uuid,date,boolean) to authenticated;

-- -------------------------------------------------------------
-- 3) إعادة احتساب إجمالي المدفوع في ملفات الرسوم من المدفوعات غير الملغاة
-- مفيد عند وجود ملف مالي total_paid خطأ.
-- -------------------------------------------------------------
create or replace function public.finance_recalculate_student_fee_totals(
  p_student_fee_id uuid default null,
  p_apply boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  preview jsonb;
  updated_count int := 0;
begin
  with calc as (
    select
      sf.id,
      sf.student_id,
      s.name as student_name,
      coalesce(sf.net_amount,sf.base_amount,sf.gross_amount,0) as net_amount,
      coalesce(sf.total_paid,0) as old_total_paid,
      coalesce((
        select sum(coalesce(fp.amount_usd, fp.amount, 0))
        from public.fee_payments fp
        where fp.student_fee_id = sf.id
          and coalesce(fp.voided,false)=false
      ),0) as new_total_paid
    from public.student_fees sf
    left join public.students s on s.id = sf.student_id
    where p_student_fee_id is null or sf.id = p_student_fee_id
  )
  select coalesce(jsonb_agg(to_jsonb(calc) order by student_name), '[]'::jsonb)
  into preview
  from calc
  where old_total_paid is distinct from new_total_paid;

  if coalesce(p_apply,false) then
    with calc as (
      select
        sf.id,
        coalesce(sf.net_amount,sf.base_amount,sf.gross_amount,0) as net_amount,
        coalesce((
          select sum(coalesce(fp.amount_usd, fp.amount, 0))
          from public.fee_payments fp
          where fp.student_fee_id = sf.id
            and coalesce(fp.voided,false)=false
        ),0) as new_total_paid
      from public.student_fees sf
      where p_student_fee_id is null or sf.id = p_student_fee_id
    )
    update public.student_fees sf
    set total_paid = calc.new_total_paid,
        status = case
          when calc.new_total_paid <= 0 then 'unpaid'
          when calc.new_total_paid >= calc.net_amount then 'paid'
          else 'partial'
        end,
        updated_at = now()
    from calc
    where sf.id = calc.id
      and coalesce(sf.total_paid,0) is distinct from calc.new_total_paid;

    get diagnostics updated_count = row_count;
  end if;

  return jsonb_build_object('ok', true, 'apply', coalesce(p_apply,false), 'mismatches', preview, 'updated_count', updated_count);
end;
$$;

grant execute on function public.finance_recalculate_student_fee_totals(uuid,boolean) to authenticated;

-- -------------------------------------------------------------
-- 4) فحص صحة خطط الأقساط والرسوم
-- -------------------------------------------------------------
create or replace function public.finance_payment_plan_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'student_fees_count', (select count(*) from public.student_fees),
    'installments_count', (select count(*) from public.student_installments),
    'open_installments', (select count(*) from public.student_installments where coalesce(amount_due,0) > coalesce(amount_paid,0)),
    'null_due_open_installments', (select count(*) from public.student_installments where due_date is null and coalesce(amount_due,0) > coalesce(amount_paid,0)),
    'fees_with_remaining', (select count(*) from public.student_fees where greatest(coalesce(net_amount,base_amount,gross_amount,0)-coalesce(total_paid,0),0) > 0),
    'fees_total_paid_mismatch_count', (
      select count(*)
      from public.student_fees sf
      where coalesce(sf.total_paid,0) is distinct from coalesce((
        select sum(coalesce(fp.amount_usd,fp.amount,0))
        from public.fee_payments fp
        where fp.student_fee_id=sf.id and coalesce(fp.voided,false)=false
      ),0)
    ),
    'null_due_preview', public.finance_repair_null_installment_due_dates(null,null,false)->'preview',
    'fee_total_mismatch_preview', public.finance_recalculate_student_fee_totals(null,false)->'mismatches'
  );
end;
$$;

grant execute on function public.finance_payment_plan_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_installments_due_dates_active_fee_fix_ready' as status;

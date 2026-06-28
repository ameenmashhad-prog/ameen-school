-- =============================================================
-- مدارس أمين الرضا (ع) — إصلاح نهائي للأقساط بلا تواريخ مع احترام installment_month_check
-- المشكلة السابقة: تم ضبط installment_month = 6 عند جعل أول قسط في يونيو،
-- بينما القيد يسمح غالباً بأشهر السنة الدراسية فقط: 9,10,11,12,1,2,3,4,5.
-- هذا الملف يستبدل الدالة بحيث:
-- 1) تبدأ من بداية السنة الدراسية عند عدم تحديد p_start_date.
-- 2) لا تضع installment_month خارج أشهر الدراسة.
-- 3) تملأ installment_number إذا كان فارغاً.
-- =============================================================

create extension if not exists pgcrypto;

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
-- دالة مساعدة: شهر دراسي صالح أم لا
-- -------------------------------------------------------------
create or replace function public.finance_valid_academic_installment_month(p_date date)
returns int
language sql
immutable
as $$
  select case
    when extract(month from p_date)::int in (9,10,11,12,1,2,3,4,5) then extract(month from p_date)::int
    else null
  end;
$$;

grant execute on function public.finance_valid_academic_installment_month(date) to authenticated;

-- -------------------------------------------------------------
-- دالة تحديد بداية مناسبة للأقساط
-- -------------------------------------------------------------
create or replace function public.finance_default_installment_start_date(p_student_fee_id uuid, p_start_date date default null)
returns date
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  d date;
begin
  if p_start_date is not null then
    return p_start_date;
  end if;

  -- خطة الدفع إن وجدت
  select fpp.start_date into d
  from public.finance_payment_plans fpp
  where fpp.student_fee_id = p_student_fee_id
    and fpp.start_date is not null
  order by fpp.created_at desc nulls last
  limit 1;
  if d is not null then return d; end if;

  -- بداية السنة الدراسية النشطة إن وجدت
  if to_regclass('public.academic_years') is not null then
    select ay.start_date_gregorian into d
    from public.academic_years ay
    where coalesce(ay.is_active,false)=true
      and ay.start_date_gregorian is not null
    order by ay.start_date_gregorian desc
    limit 1;
    if d is not null then return d; end if;
  end if;

  -- إعدادات التقويم القديمة
  if to_regclass('public.school_calendar_settings') is not null then
    select scs.academic_year_start_date into d
    from public.school_calendar_settings scs
    where scs.academic_year_start_date is not null
    order by scs.updated_at desc nulls last
    limit 1;
    if d is not null then return d; end if;
  end if;

  -- افتراضي آمن: بداية سبتمبر من سنة اليوم إذا كنا قبل سبتمبر، وإلا سبتمبر القادم/الحالي
  if extract(month from current_date)::int <= 8 then
    return make_date(extract(year from current_date)::int, 9, 1);
  end if;
  return make_date(extract(year from current_date)::int, 9, 1);
end;
$$;

grant execute on function public.finance_default_installment_start_date(uuid,date) to authenticated;

-- -------------------------------------------------------------
-- الإصلاح الرئيسي: معاينة/تنفيذ
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
      si.installment_month as old_installment_month,
      si.due_date as old_due_date,
      si.amount_due,
      si.amount_paid,
      sf.student_id,
      s.name as student_name,
      public.finance_default_installment_start_date(si.student_fee_id, p_start_date) as base_date,
      row_number() over (
        partition by si.student_fee_id
        order by coalesce(si.installment_number,9999), si.created_at, si.id
      ) as rn
    from public.student_installments si
    join public.student_fees sf on sf.id = si.student_fee_id
    left join public.students s on s.id = sf.student_id
    where si.due_date is null
      and coalesce(si.amount_due,0) > coalesce(si.amount_paid,0)
      and (p_student_fee_id is null or si.student_fee_id = p_student_fee_id)
  ), calc as (
    select
      *,
      (base_date + ((rn-1) || ' months')::interval)::date as new_due_date,
      public.finance_valid_academic_installment_month((base_date + ((rn-1) || ' months')::interval)::date) as new_installment_month
    from target
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'installment_id', id,
    'student_fee_id', student_fee_id,
    'student_id', student_id,
    'student_name', student_name,
    'installment_number', installment_number,
    'new_installment_number', coalesce(installment_number, rn),
    'old_installment_month', old_installment_month,
    'new_installment_month', new_installment_month,
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
        public.finance_default_installment_start_date(si.student_fee_id, p_start_date) as base_date,
        row_number() over (
          partition by si.student_fee_id
          order by coalesce(si.installment_number,9999), si.created_at, si.id
        ) as rn
      from public.student_installments si
      join public.student_fees sf on sf.id = si.student_fee_id
      where si.due_date is null
        and coalesce(si.amount_due,0) > coalesce(si.amount_paid,0)
        and (p_student_fee_id is null or si.student_fee_id = p_student_fee_id)
    ), calc as (
      select
        id,
        rn,
        (base_date + ((rn-1) || ' months')::interval)::date as new_due_date,
        public.finance_valid_academic_installment_month((base_date + ((rn-1) || ' months')::interval)::date) as new_installment_month
      from target
    )
    update public.student_installments si
    set due_date = calc.new_due_date,
        installment_number = coalesce(si.installment_number, calc.rn),
        installment_month = calc.new_installment_month,
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
    'preview', preview,
    'note', 'تم ضبط installment_month فقط إذا كان الشهر ضمن أشهر الدراسة 9-5، لتجنب constraint errors.'
  );
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm, 'hint', 'إذا ظهر constraint آخر أرسلي الرسالة كاملة.');
end;
$$;

grant execute on function public.finance_repair_null_installment_due_dates(uuid,date,boolean) to authenticated;

-- -------------------------------------------------------------
-- فحص صحة خطط الأقساط والرسوم
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
    'invalid_installment_months', (select count(*) from public.student_installments where installment_month is not null and installment_month not in (9,10,11,12,1,2,3,4,5)),
    'fees_with_remaining', (select count(*) from public.student_fees where greatest(coalesce(net_amount,base_amount,gross_amount,0)-coalesce(total_paid,0),0) > 0),
    'null_due_preview', public.finance_repair_null_installment_due_dates(null,null,false)->'preview'
  );
end;
$$;

grant execute on function public.finance_payment_plan_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_installment_due_month_constraint_fix_ready' as status;

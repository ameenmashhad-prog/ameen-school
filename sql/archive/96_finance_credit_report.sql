-- =============================================================
-- مدارس أمين الرضا (ع) — تقرير الأرصدة الدائنة
-- يعرض المدفوعات الزائدة المحفوظة كرصد دائن دون حذف أو إلغاء أي إيصال.
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
-- 1) أعمدة الرصيد الدائن
-- -------------------------------------------------------------
alter table public.student_fees add column if not exists credit_balance numeric not null default 0;
alter table public.student_fees add column if not exists credit_notes text;
alter table public.student_fees add column if not exists updated_at timestamptz not null default now();

-- -------------------------------------------------------------
-- 2) View الأرصدة الدائنة
-- -------------------------------------------------------------
drop view if exists public.v_finance_fee_credit_summary;

create view public.v_finance_fee_credit_summary
with (security_invoker=true) as
select
  sf.id as student_fee_id,
  sf.student_id,
  s.name as student_name,
  s.father_name,
  s.last_name,
  s.parent_id,
  pu.name as parent_name,
  s.class_id,
  c.name as class_name,
  sf.academic_year,
  coalesce(sf.net_amount, sf.base_amount, sf.gross_amount,0) as net_amount,
  coalesce(sf.total_paid,0) as total_paid,
  coalesce(sf.credit_balance,0) as credit_balance,
  greatest(coalesce(sf.net_amount, sf.base_amount, sf.gross_amount,0)-coalesce(sf.total_paid,0),0) as remaining_amount,
  sf.status,
  sf.credit_notes,
  sf.created_at,
  sf.updated_at
from public.student_fees sf
left join public.students s on s.id = sf.student_id
left join public.users pu on pu.id = s.parent_id
left join public.classes c on c.id = s.class_id
where coalesce(sf.credit_balance,0) > 0
  and (
    public.finance_can_manage()
    or s.user_id = auth.uid()
    or s.parent_id = auth.uid()
    or auth.uid() is null
  );

grant select on public.v_finance_fee_credit_summary to authenticated;

-- -------------------------------------------------------------
-- 3) Payload التقرير
-- -------------------------------------------------------------
create or replace function public.get_finance_credit_report(p_min_credit numeric default 0)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  rows_json jsonb;
  by_class_json jsonb;
  stats_json jsonb;
  min_credit numeric := greatest(coalesce(p_min_credit,0),0);
begin
  if not public.finance_can_manage() and auth.uid() is not null then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية عرض تقرير الرصيد الدائن');
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.credit_balance desc, x.student_name), '[]'::jsonb)
  into rows_json
  from (
    select *
    from public.v_finance_fee_credit_summary
    where credit_balance >= min_credit
    order by credit_balance desc, student_name
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.total_credit desc), '[]'::jsonb)
  into by_class_json
  from (
    select
      class_id,
      class_name,
      count(*) as files_count,
      count(distinct student_id) as students_count,
      coalesce(sum(credit_balance),0) as total_credit,
      coalesce(sum(net_amount),0) as total_net,
      coalesce(sum(total_paid),0) as total_paid
    from public.v_finance_fee_credit_summary
    where credit_balance >= min_credit
    group by class_id, class_name
  ) x;

  stats_json := jsonb_build_object(
    'min_credit', min_credit,
    'credit_files', (select count(*) from public.v_finance_fee_credit_summary where credit_balance >= min_credit),
    'credit_students', (select count(distinct student_id) from public.v_finance_fee_credit_summary where credit_balance >= min_credit),
    'total_credit_balance', (select coalesce(sum(credit_balance),0) from public.v_finance_fee_credit_summary where credit_balance >= min_credit),
    'max_credit_balance', (select coalesce(max(credit_balance),0) from public.v_finance_fee_credit_summary where credit_balance >= min_credit),
    'total_net_for_credit_files', (select coalesce(sum(net_amount),0) from public.v_finance_fee_credit_summary where credit_balance >= min_credit),
    'total_paid_for_credit_files', (select coalesce(sum(total_paid),0) from public.v_finance_fee_credit_summary where credit_balance >= min_credit)
  );

  return jsonb_build_object(
    'ok', true,
    'stats', stats_json,
    'rows', rows_json,
    'by_class', by_class_json,
    'note', 'الأرصدة الدائنة تمثل مدفوعات زائدة محفوظة دون حذف أو إلغاء أي إيصال.'
  );
end;
$$;

grant execute on function public.get_finance_credit_report(numeric) to authenticated;

-- -------------------------------------------------------------
-- 4) Health check
-- -------------------------------------------------------------
create or replace function public.finance_credit_report_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'credit_column', exists(select 1 from information_schema.columns where table_schema='public' and table_name='student_fees' and column_name='credit_balance'),
    'credit_view', to_regclass('public.v_finance_fee_credit_summary') is not null,
    'payload_rpc', to_regprocedure('public.get_finance_credit_report(numeric)') is not null,
    'stats', public.get_finance_credit_report(0)->'stats'
  );
end;
$$;

grant execute on function public.finance_credit_report_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_credit_report_ready' as status;

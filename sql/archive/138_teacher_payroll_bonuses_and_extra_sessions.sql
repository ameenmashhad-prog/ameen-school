-- ============================================================================
-- 138) المكافآت والحصص الإضافية للمعلمين
--
-- الهدف:
-- - إضافة منطقة واضحة للمكافآت مع ذكر السبب.
-- - إضافة حصص إضافية مثل:
--   * حلول المعلم مكان معلم غائب
--   * دوام أيام العطلات
--   * حصص إلكترونية
--   * دعم إضافي / مراجعات / مراقبة
-- - دمجها مباشرة في كشف راتب المعلم الشهري.
--
-- مبدأ الحساب:
-- - الحصة الإضافية تُسجل بوحدات Session Units
-- - تُحتسب بقيمة أجر الحصة المعتاد، أو بسعر override إذا حدده المدير
-- - المكافآت والخصومات اليدوية تكون بمبلغ مباشر مع سبب إلزامي
-- ============================================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) صلاحية إدارة التعويضات الإضافية
-- -------------------------------------------------------------
create or replace function public.current_user_can_manage_teacher_compensation()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1
    from public.users u
    where u.id = auth.uid()
      and (
        coalesce(u.is_super_admin,false)=true
        or u.role in ('admin','finance','academic','academic_admin','scientific','supervisor')
      )
  );
$$;

grant execute on function public.current_user_can_manage_teacher_compensation() to authenticated;

-- -------------------------------------------------------------
-- 2) جدول الحصص الإضافية
-- -------------------------------------------------------------
create table if not exists public.teacher_extra_sessions (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.users(id) on delete cascade,
  session_date date not null,
  category text not null check (category in ('substitute_absent_teacher','holiday_work','online_session','extra_support','exam_supervision','other')),
  session_units numeric not null default 1 check (session_units > 0),
  rate_override numeric null check (rate_override is null or rate_override >= 0),
  replacement_teacher_id uuid null references public.users(id) on delete set null,
  related_class_session_id uuid null references public.class_sessions(id) on delete set null,
  reason text not null,
  notes text,
  is_active boolean not null default true,
  created_by uuid null references public.users(id),
  approved_by uuid null references public.users(id),
  approved_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_teacher_extra_sessions_teacher_date on public.teacher_extra_sessions(teacher_id, session_date desc);

alter table public.teacher_extra_sessions enable row level security;
drop policy if exists teacher_extra_sessions_manage on public.teacher_extra_sessions;
create policy teacher_extra_sessions_manage on public.teacher_extra_sessions
  for all to authenticated
  using (public.current_user_can_manage_teacher_compensation())
  with check (public.current_user_can_manage_teacher_compensation());

grant select, insert, update on public.teacher_extra_sessions to authenticated;

-- -------------------------------------------------------------
-- 3) جدول المكافآت / الخصومات اليدوية
-- -------------------------------------------------------------
create table if not exists public.teacher_payroll_adjustments (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.users(id) on delete cascade,
  effective_month date not null,
  adjustment_type text not null check (adjustment_type in ('bonus','deduction')),
  amount_usd numeric not null check (amount_usd > 0),
  reason text not null,
  notes text,
  is_active boolean not null default true,
  created_by uuid null references public.users(id),
  approved_by uuid null references public.users(id),
  approved_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_teacher_payroll_adjustments_teacher_month on public.teacher_payroll_adjustments(teacher_id, effective_month desc);

alter table public.teacher_payroll_adjustments enable row level security;
drop policy if exists teacher_payroll_adjustments_manage on public.teacher_payroll_adjustments;
create policy teacher_payroll_adjustments_manage on public.teacher_payroll_adjustments
  for all to authenticated
  using (public.current_user_can_manage_teacher_compensation())
  with check (public.current_user_can_manage_teacher_compensation());

grant select, insert, update on public.teacher_payroll_adjustments to authenticated;

-- -------------------------------------------------------------
-- 4) دوال الإدخال السريع
-- -------------------------------------------------------------
create or replace function public.save_teacher_extra_session(
  p_teacher_id uuid,
  p_session_date date,
  p_category text,
  p_session_units numeric default 1,
  p_rate_override numeric default null,
  p_replacement_teacher_id uuid default null,
  p_reason text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid;
begin
  if not public.current_user_can_manage_teacher_compensation() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إضافة حصص إضافية');
  end if;

  if p_teacher_id is null then
    return jsonb_build_object('ok', false, 'message', 'المعلم مطلوب');
  end if;

  if p_session_date is null then
    return jsonb_build_object('ok', false, 'message', 'التاريخ مطلوب');
  end if;

  if coalesce(p_session_units,0) <= 0 then
    return jsonb_build_object('ok', false, 'message', 'عدد الوحدات يجب أن يكون أكبر من صفر');
  end if;

  if coalesce(trim(p_reason),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'سبب الحصة الإضافية مطلوب');
  end if;

  insert into public.teacher_extra_sessions(
    teacher_id, session_date, category, session_units, rate_override,
    replacement_teacher_id, reason, notes, created_by, approved_by, approved_at
  ) values (
    p_teacher_id,
    p_session_date,
    case when p_category in ('substitute_absent_teacher','holiday_work','online_session','extra_support','exam_supervision','other') then p_category else 'other' end,
    p_session_units,
    p_rate_override,
    p_replacement_teacher_id,
    trim(p_reason),
    nullif(trim(coalesce(p_notes,'')),''),
    auth.uid(),
    auth.uid(),
    now()
  ) returning id into sid;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ الحصة الإضافية', 'entry_id', sid);
end;
$$;

grant execute on function public.save_teacher_extra_session(uuid,date,text,numeric,numeric,uuid,text,text) to authenticated;

create or replace function public.save_teacher_payroll_adjustment(
  p_teacher_id uuid,
  p_effective_month text,
  p_adjustment_type text,
  p_amount_usd numeric,
  p_reason text,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  aid uuid;
  m date;
begin
  if not public.current_user_can_manage_teacher_compensation() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إضافة مكافآت/خصومات');
  end if;

  if p_teacher_id is null then
    return jsonb_build_object('ok', false, 'message', 'المعلم مطلوب');
  end if;

  if coalesce(trim(p_effective_month),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'الشهر مطلوب بصيغة YYYY-MM');
  end if;

  if coalesce(p_amount_usd,0) <= 0 then
    return jsonb_build_object('ok', false, 'message', 'المبلغ يجب أن يكون أكبر من صفر');
  end if;

  if coalesce(trim(p_reason),'') = '' then
    return jsonb_build_object('ok', false, 'message', 'سبب المكافأة/الخصم مطلوب');
  end if;

  m := to_date(p_effective_month || '-01', 'YYYY-MM-DD');

  insert into public.teacher_payroll_adjustments(
    teacher_id, effective_month, adjustment_type, amount_usd,
    reason, notes, created_by, approved_by, approved_at
  ) values (
    p_teacher_id,
    m,
    case when p_adjustment_type in ('bonus','deduction') then p_adjustment_type else 'bonus' end,
    p_amount_usd,
    trim(p_reason),
    nullif(trim(coalesce(p_notes,'')),''),
    auth.uid(),
    auth.uid(),
    now()
  ) returning id into aid;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ التعديل المالي للمعلم', 'adjustment_id', aid);
end;
$$;

grant execute on function public.save_teacher_payroll_adjustment(uuid,text,text,numeric,text,text) to authenticated;

-- -------------------------------------------------------------
-- 5) Views تفصيلية وتجميعية
-- -------------------------------------------------------------
create or replace view public.v_teacher_extra_sessions_detailed
with (security_invoker=true) as
select
  x.id,
  x.teacher_id,
  u.name as teacher_name,
  x.session_date,
  date_trunc('month', x.session_date)::date as month,
  x.category,
  x.session_units,
  x.rate_override,
  x.replacement_teacher_id,
  ru.name as replacement_teacher_name,
  x.related_class_session_id,
  x.reason,
  x.notes,
  x.is_active,
  x.created_by,
  cu.name as created_by_name,
  x.approved_by,
  au.name as approved_by_name,
  x.approved_at,
  x.created_at,
  x.updated_at,
  coalesce(x.rate_override, specific.amount_per_verified_session, global_rule.amount_per_verified_session, 0) as effective_rate,
  round(x.session_units * coalesce(x.rate_override, specific.amount_per_verified_session, global_rule.amount_per_verified_session, 0), 2) as extra_amount
from public.teacher_extra_sessions x
left join public.users u on u.id = x.teacher_id
left join public.users ru on ru.id = x.replacement_teacher_id
left join public.users cu on cu.id = x.created_by
left join public.users au on au.id = x.approved_by
left join public.teacher_payroll_rules specific on specific.teacher_id = x.teacher_id and specific.active = true
left join public.teacher_payroll_rules global_rule on global_rule.teacher_id is null and global_rule.active = true
where x.is_active = true;

grant select on public.v_teacher_extra_sessions_detailed to authenticated;

create or replace view public.v_teacher_extra_sessions_monthly
with (security_invoker=true) as
select
  teacher_id,
  teacher_name,
  month,
  count(*) as extra_sessions_count,
  round(sum(session_units),2) as extra_session_units,
  round(sum(extra_amount),2) as extra_session_amount
from public.v_teacher_extra_sessions_detailed
group by teacher_id, teacher_name, month;

grant select on public.v_teacher_extra_sessions_monthly to authenticated;

create or replace view public.v_teacher_payroll_adjustments_monthly
with (security_invoker=true) as
select
  a.teacher_id,
  u.name as teacher_name,
  date_trunc('month', a.effective_month)::date as month,
  round(sum(case when a.adjustment_type='bonus' then a.amount_usd else 0 end),2) as bonus_amount,
  round(sum(case when a.adjustment_type='deduction' then a.amount_usd else 0 end),2) as deduction_amount,
  round(sum(case when a.adjustment_type='bonus' then a.amount_usd else -a.amount_usd end),2) as net_adjustment_amount
from public.teacher_payroll_adjustments a
left join public.users u on u.id = a.teacher_id
where a.is_active = true
group by a.teacher_id, u.name, date_trunc('month', a.effective_month)::date;

grant select on public.v_teacher_payroll_adjustments_monthly to authenticated;

-- -------------------------------------------------------------
-- 6) إعادة بناء كشف الراتب الشهري النهائي مع المكافآت والحصص الإضافية
-- -------------------------------------------------------------
drop view if exists public.v_teacher_payroll_preview;

create or replace view public.v_teacher_payroll_preview
with (security_invoker=true) as
with monthly as (
  select
    d.teacher_id,
    d.teacher_name,
    date_trunc('month', d.session_date)::date as month,
    sum(d.total_sessions) as total_sessions,
    sum(d.prepared_sessions) as prepared_sessions,
    sum(d.homework_sessions) as homework_sessions,
    round(sum(d.earned_session_units), 2) as gross_verified_sessions,
    sum(d.fully_documented_sessions) as fully_documented_sessions,
    sum(d.incomplete_sessions) as incomplete_sessions,
    coalesce(r.amount_per_verified_session, gr.amount_per_verified_session, 0) as amount_per_session,
    coalesce(r.currency, gr.currency, 'USD') as currency
  from public.v_teacher_payroll_daily d
  left join public.teacher_payroll_rules r
    on r.teacher_id = d.teacher_id and r.active = true
  left join public.teacher_payroll_rules gr
    on gr.teacher_id is null and gr.active = true
  group by d.teacher_id, d.teacher_name, date_trunc('month', d.session_date)::date, r.amount_per_verified_session, gr.amount_per_verified_session, r.currency, gr.currency
), penalties as (
  select teacher_id, month, round(sum(penalty_session_units_total),2) as penalty_session_units
  from public.v_teacher_lateness_penalties_monthly
  group by teacher_id, month
), extras as (
  select teacher_id, month, extra_sessions_count, extra_session_units, extra_session_amount
  from public.v_teacher_extra_sessions_monthly
), adj as (
  select teacher_id, month, bonus_amount, deduction_amount, net_adjustment_amount
  from public.v_teacher_payroll_adjustments_monthly
)
select
  m.teacher_id,
  m.teacher_name,
  m.month,
  m.total_sessions,
  m.prepared_sessions,
  m.homework_sessions,
  m.gross_verified_sessions,
  coalesce(p.penalty_session_units,0) as penalty_session_units,
  greatest(0, round(m.gross_verified_sessions - coalesce(p.penalty_session_units,0), 2)) as verified_sessions,
  m.amount_per_session,
  m.currency,
  round(greatest(0, m.gross_verified_sessions - coalesce(p.penalty_session_units,0)) * m.amount_per_session, 2) as base_estimated_amount,
  coalesce(e.extra_sessions_count,0) as extra_sessions_count,
  coalesce(e.extra_session_units,0) as extra_session_units,
  coalesce(e.extra_session_amount,0) as extra_session_amount,
  coalesce(a.bonus_amount,0) as bonus_amount,
  coalesce(a.deduction_amount,0) as deduction_amount,
  round(
    greatest(0, m.gross_verified_sessions - coalesce(p.penalty_session_units,0)) * m.amount_per_session
    + coalesce(e.extra_session_amount,0)
    + coalesce(a.bonus_amount,0)
    - coalesce(a.deduction_amount,0)
  , 2) as estimated_amount,
  m.fully_documented_sessions,
  m.incomplete_sessions
from monthly m
left join penalties p on p.teacher_id = m.teacher_id and p.month = m.month
left join extras e on e.teacher_id = m.teacher_id and e.month = m.month
left join adj a on a.teacher_id = m.teacher_id and a.month = m.month;

grant select on public.v_teacher_payroll_preview to authenticated;

-- -------------------------------------------------------------
-- 7) Health Check
-- -------------------------------------------------------------
create or replace function public.teacher_payroll_compensation_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'checked_at', now(),
    'extra_sessions_table', to_regclass('public.teacher_extra_sessions') is not null,
    'adjustments_table', to_regclass('public.teacher_payroll_adjustments') is not null,
    'extra_sessions_monthly_view', to_regclass('public.v_teacher_extra_sessions_monthly') is not null,
    'adjustments_monthly_view', to_regclass('public.v_teacher_payroll_adjustments_monthly') is not null,
    'save_extra_session_rpc', to_regprocedure('public.save_teacher_extra_session(uuid,date,text,numeric,numeric,uuid,text,text)') is not null,
    'save_adjustment_rpc', to_regprocedure('public.save_teacher_payroll_adjustment(uuid,text,text,numeric,text,text)') is not null
  );
end;
$$;

grant execute on function public.teacher_payroll_compensation_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.teacher_payroll_compensation_health_check() as teacher_payroll_compensation_health;

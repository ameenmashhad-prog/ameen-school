-- ============================================================================
-- 137) Hotfix قوي: إعادة بناء أدلة راتب المعلم من الجداول الفعلية مباشرة
--
-- سبب هذا الملف:
-- في بعض البيئات بقيت Views الراتب القديمة فعالة حتى بعد تشغيل 136،
-- وظهر سلوك غير صحيح مثل:
--   has_lesson_plan = 0
--   has_homework    = 0
--   payroll_units   = 1.00
--
-- هذا الملف يتجاوز المنطق القديم تماماً ويعيد البناء من الجداول الفعلية:
-- - lesson_plans
-- - homeworks
-- - teacher_session_checkins
-- - teacher_lateness_rules / penalties
--
-- المنطق النهائي الثابت:
-- - تحضير الدرس = 0.5
-- - الواجب = 0.5
-- - إن وُجدا معاً = 1.0
-- - بدون الاثنين = 0.0
-- ============================================================================

-- إسقاط كل الطبقات السابقة التي قد تحمل منطقاً قديماً
 drop view if exists public.v_teacher_payroll_preview;
 drop view if exists public.v_teacher_payroll_daily;
 drop view if exists public.v_teacher_session_payroll_evidence;

create or replace view public.v_teacher_session_payroll_evidence
with (security_invoker=true) as
select
  cs.id as class_session_id,
  cs.session_date,
  cs.teacher_id,
  u.name as teacher_name,
  cs.class_id,
  c.name as class_name,
  cs.subject_id,
  s.name as subject_name,
  cs.period_number,
  cs.start_time,
  cs.end_time,
  case when exists(
    select 1 from public.lesson_plans lp
    where lp.class_session_id = cs.id and lp.teacher_id = cs.teacher_id
  ) then 1 else 0 end as has_lesson_plan,
  case when exists(
    select 1 from public.homeworks hw
    where hw.class_session_id = cs.id and hw.teacher_id = cs.teacher_id and hw.status in ('published','closed','draft')
  ) then 1 else 0 end as has_homework,
  case when exists(
    select 1 from public.teacher_activity_log tal
    where tal.class_session_id = cs.id and tal.teacher_id = cs.teacher_id and tal.activity_type = 'manual_confirm'
  ) then 1 else 0 end as has_manual_confirm,
  case when exists(
    select 1 from public.teacher_activity_log tal
    where tal.class_session_id = cs.id and tal.teacher_id = cs.teacher_id and tal.activity_type = 'attendance'
  ) then 1 else 0 end as has_attendance,
  case when exists(
    select 1 from public.teacher_activity_log tal
    where tal.class_session_id = cs.id and tal.teacher_id = cs.teacher_id and tal.activity_type = 'grade_entry'
  ) then 1 else 0 end as has_grade_entry,
  round(
    case
      when exists(select 1 from public.lesson_plans lp where lp.class_session_id = cs.id and lp.teacher_id = cs.teacher_id)
       and exists(select 1 from public.homeworks hw where hw.class_session_id = cs.id and hw.teacher_id = cs.teacher_id and hw.status in ('published','closed','draft'))
        then 1.0
      when exists(select 1 from public.lesson_plans lp where lp.class_session_id = cs.id and lp.teacher_id = cs.teacher_id)
        then 0.5
      when exists(select 1 from public.homeworks hw where hw.class_session_id = cs.id and hw.teacher_id = cs.teacher_id and hw.status in ('published','closed','draft'))
        then 0.5
      else 0.0
    end
  , 2) as payroll_units,
  case
    when exists(select 1 from public.lesson_plans lp where lp.class_session_id = cs.id and lp.teacher_id = cs.teacher_id)
     and exists(select 1 from public.homeworks hw where hw.class_session_id = cs.id and hw.teacher_id = cs.teacher_id and hw.status in ('published','closed','draft'))
      then 'موثقة بالكامل'
    when exists(select 1 from public.lesson_plans lp where lp.class_session_id = cs.id and lp.teacher_id = cs.teacher_id)
      then 'تحضير فقط'
    when exists(select 1 from public.homeworks hw where hw.class_session_id = cs.id and hw.teacher_id = cs.teacher_id and hw.status in ('published','closed','draft'))
      then 'واجب فقط'
    when exists(select 1 from public.teacher_activity_log tal where tal.class_session_id = cs.id and tal.teacher_id = cs.teacher_id and tal.activity_type = 'manual_confirm')
      then 'مثبتة يدوياً فقط'
    else 'غير مكتملة'
  end as payroll_status,
  (
    select min(tal.occurred_at)
    from public.teacher_activity_log tal
    where tal.class_session_id = cs.id and tal.teacher_id = cs.teacher_id
  ) as first_activity_at,
  (
    select max(tal.occurred_at)
    from public.teacher_activity_log tal
    where tal.class_session_id = cs.id and tal.teacher_id = cs.teacher_id
  ) as last_activity_at
from public.class_sessions cs
left join public.users u on u.id = cs.teacher_id
left join public.classes c on c.id = cs.class_id
left join public.subjects s on s.id = cs.subject_id;

grant select on public.v_teacher_session_payroll_evidence to authenticated;

create or replace view public.v_teacher_payroll_daily
with (security_invoker=true) as
select
  e.teacher_id,
  e.teacher_name,
  e.session_date,
  count(*) as total_sessions,
  sum(e.has_lesson_plan) as prepared_sessions,
  sum(e.has_homework) as homework_sessions,
  round(sum(e.payroll_units), 2) as earned_session_units,
  coalesce(r.amount_per_verified_session, gr.amount_per_verified_session, 0) as amount_per_session,
  coalesce(r.currency, gr.currency, 'USD') as currency,
  round(sum(e.payroll_units) * coalesce(r.amount_per_verified_session, gr.amount_per_verified_session, 0), 2) as estimated_amount,
  count(*) filter (where e.payroll_status = 'موثقة بالكامل') as fully_documented_sessions,
  count(*) filter (where e.payroll_status = 'غير مكتملة') as incomplete_sessions
from public.v_teacher_session_payroll_evidence e
left join public.teacher_payroll_rules r
  on r.teacher_id = e.teacher_id and r.active = true
left join public.teacher_payroll_rules gr
  on gr.teacher_id is null and gr.active = true
group by e.teacher_id, e.teacher_name, e.session_date, r.amount_per_verified_session, gr.amount_per_verified_session, r.currency, gr.currency;

grant select on public.v_teacher_payroll_daily to authenticated;

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
  round(greatest(0, m.gross_verified_sessions - coalesce(p.penalty_session_units,0)) * m.amount_per_session, 2) as estimated_amount,
  m.fully_documented_sessions,
  m.incomplete_sessions
from monthly m
left join penalties p on p.teacher_id = m.teacher_id and p.month = m.month;

grant select on public.v_teacher_payroll_preview to authenticated;

notify pgrst, 'reload schema';

select 'teacher_payroll_evidence_hard_rebuild_hotfix_ready' as status;

-- ============================================================================
-- 126) ربط راتب المعلم/المعلمة بتحضير الدرس + تنزيل الواجب بحسب الحصة اليومية
-- مدارس أمين الرضا (ع)
--
-- الفكرة:
-- - كل حصة (class_session) لها نقاط/وحدات راتبية.
-- - تحضير الدرس = 0.5 حصة
-- - تنزيل/نشر الواجب المرتبط بالحصة = 0.5 حصة
-- - إذا اجتمع الاثنان للحصة نفسها => تُحسب 1.0 حصة كاملة.
--
-- الهدف:
-- - ربط الراتب بسلوك العمل الفعلي المرتبط بالحصة
-- - إظهار كشف يومي/شهري واضح للإدارة المالية والمالك
-- - إبقاء السياسة مرنة وقابلة للتعديل لاحقاً عبر جدول أوزان
-- ============================================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) جدول أوزان الأنشطة الراتبية (مرن وقابل للتعديل لاحقاً)
-- -------------------------------------------------------------
create table if not exists public.teacher_payroll_activity_weights (
  id uuid primary key default gen_random_uuid(),
  activity_key text not null unique,
  activity_label text not null,
  weight numeric not null default 0,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.teacher_payroll_activity_weights(activity_key, activity_label, weight, is_active, notes)
values
  ('lesson_note','تحضير الدرس المرتبط بالحصة',0.5,true,'تحضير محفوظ عبر lesson_plans / save_lesson_plan'),
  ('homework','الواجب المنشور المرتبط بالحصة',0.5,true,'واجب محفوظ عبر homeworks / create_session_homework'),
  ('manual_confirm','تثبيت يدوي للحصة (معلوماتي فقط)',0.0,true,'لا يُحسب للراتب افتراضياً لكن يظهر في الدليل اليومي'),
  ('attendance','تحضير حضور مرتبط بالحصة',0.0,true,'مخصص للتوثيق المستقبلي إذا رغبت الإدارة'),
  ('grade_entry','إدخال درجات مرتبط بالحصة',0.0,true,'مخصص للتوثيق المستقبلي إذا رغبت الإدارة')
on conflict (activity_key) do update set
  activity_label = excluded.activity_label,
  weight = excluded.weight,
  is_active = excluded.is_active,
  notes = excluded.notes,
  updated_at = now();

-- -------------------------------------------------------------
-- 2) View: دليل الأنشطة الراتبية لكل حصة
-- -------------------------------------------------------------
create or replace view public.v_teacher_session_payroll_evidence
with (security_invoker=true) as
with act as (
  select
    tal.class_session_id,
    tal.teacher_id,
    max(case when tal.activity_type = 'lesson_note' then 1 else 0 end) as has_lesson_plan,
    max(case when tal.activity_type = 'homework' then 1 else 0 end) as has_homework,
    max(case when tal.activity_type = 'manual_confirm' then 1 else 0 end) as has_manual_confirm,
    max(case when tal.activity_type = 'attendance' then 1 else 0 end) as has_attendance,
    max(case when tal.activity_type = 'grade_entry' then 1 else 0 end) as has_grade_entry,
    min(tal.occurred_at) as first_activity_at,
    max(tal.occurred_at) as last_activity_at
  from public.teacher_activity_log tal
  group by tal.class_session_id, tal.teacher_id
),
weights as (
  select
    max(case when activity_key='lesson_note' and is_active then weight else 0 end) as w_lesson_note,
    max(case when activity_key='homework' and is_active then weight else 0 end) as w_homework,
    max(case when activity_key='manual_confirm' and is_active then weight else 0 end) as w_manual_confirm,
    max(case when activity_key='attendance' and is_active then weight else 0 end) as w_attendance,
    max(case when activity_key='grade_entry' and is_active then weight else 0 end) as w_grade_entry
  from public.teacher_payroll_activity_weights
)
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
  coalesce(a.has_lesson_plan,0) as has_lesson_plan,
  coalesce(a.has_homework,0) as has_homework,
  coalesce(a.has_manual_confirm,0) as has_manual_confirm,
  coalesce(a.has_attendance,0) as has_attendance,
  coalesce(a.has_grade_entry,0) as has_grade_entry,
  round(
    least(
      1.0,
      coalesce(a.has_lesson_plan,0) * w.w_lesson_note +
      coalesce(a.has_homework,0) * w.w_homework +
      coalesce(a.has_manual_confirm,0) * w.w_manual_confirm +
      coalesce(a.has_attendance,0) * w.w_attendance +
      coalesce(a.has_grade_entry,0) * w.w_grade_entry
    )
  , 2) as payroll_units,
  case
    when coalesce(a.has_lesson_plan,0)=1 and coalesce(a.has_homework,0)=1 then 'موثقة بالكامل'
    when coalesce(a.has_lesson_plan,0)=1 and coalesce(a.has_homework,0)=0 then 'تحضير فقط'
    when coalesce(a.has_lesson_plan,0)=0 and coalesce(a.has_homework,0)=1 then 'واجب فقط'
    when coalesce(a.has_manual_confirm,0)=1 then 'مثبتة يدوياً فقط'
    else 'غير مكتملة'
  end as payroll_status,
  a.first_activity_at,
  a.last_activity_at
from public.class_sessions cs
left join act a on a.class_session_id = cs.id and a.teacher_id = cs.teacher_id
left join public.users u on u.id = cs.teacher_id
left join public.classes c on c.id = cs.class_id
left join public.subjects s on s.id = cs.subject_id
cross join weights w;

grant select on public.v_teacher_session_payroll_evidence to authenticated;

-- -------------------------------------------------------------
-- 3) View: كشف يومي للراتب بحسب الحصص اليومية
-- -------------------------------------------------------------
create or replace view public.v_teacher_payroll_daily
with (security_invoker=true) as
select
  e.teacher_id,
  e.teacher_name,
  e.session_date,
  count(*) as total_sessions,
  sum(e.has_lesson_plan) as prepared_sessions,
  sum(e.has_homework) as homework_sessions,
  sum(e.payroll_units) as earned_session_units,
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

-- -------------------------------------------------------------
-- 4) Update: الملخص الشهري الحالي يستخدم الوحدات اليومية بدل مجرد وجود نشاط واحد
-- ملاحظة مهمة:
-- نُسقط الـ View أولاً لأن PostgreSQL لا يسمح بتغيير أسماء/ترتيب أعمدة View
-- عبر create or replace view إذا كانت النسخة السابقة مختلفة.
-- -------------------------------------------------------------
drop view if exists public.v_teacher_payroll_preview;

create or replace view public.v_teacher_payroll_preview
with (security_invoker=true) as
select
  d.teacher_id,
  d.teacher_name,
  date_trunc('month', d.session_date)::date as month,
  sum(d.total_sessions) as total_sessions,
  sum(d.prepared_sessions) as prepared_sessions,
  sum(d.homework_sessions) as homework_sessions,
  round(sum(d.earned_session_units), 2) as verified_sessions,
  coalesce(r.amount_per_verified_session, gr.amount_per_verified_session, 0) as amount_per_session,
  coalesce(r.currency, gr.currency, 'USD') as currency,
  round(sum(d.earned_session_units) * coalesce(r.amount_per_verified_session, gr.amount_per_verified_session, 0), 2) as estimated_amount,
  sum(d.fully_documented_sessions) as fully_documented_sessions,
  sum(d.incomplete_sessions) as incomplete_sessions
from public.v_teacher_payroll_daily d
left join public.teacher_payroll_rules r
  on r.teacher_id = d.teacher_id and r.active = true
left join public.teacher_payroll_rules gr
  on gr.teacher_id is null and gr.active = true
group by d.teacher_id, d.teacher_name, date_trunc('month', d.session_date)::date, r.amount_per_verified_session, gr.amount_per_verified_session, r.currency, gr.currency;

grant select on public.v_teacher_payroll_preview to authenticated;

-- -------------------------------------------------------------
-- 5) Health Check
-- -------------------------------------------------------------
create or replace function public.teacher_payroll_session_model_health_check()
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
    'weights_table', to_regclass('public.teacher_payroll_activity_weights') is not null,
    'session_evidence_view', to_regclass('public.v_teacher_session_payroll_evidence') is not null,
    'daily_payroll_view', to_regclass('public.v_teacher_payroll_daily') is not null,
    'monthly_payroll_view', to_regclass('public.v_teacher_payroll_preview') is not null,
    'lesson_weight', coalesce((select weight from public.teacher_payroll_activity_weights where activity_key='lesson_note' limit 1),0),
    'homework_weight', coalesce((select weight from public.teacher_payroll_activity_weights where activity_key='homework' limit 1),0)
  );
end;
$$;

grant execute on function public.teacher_payroll_session_model_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.teacher_payroll_session_model_health_check() as teacher_payroll_session_model_health;

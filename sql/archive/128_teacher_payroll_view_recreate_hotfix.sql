-- ============================================================================
-- 128) Hotfix: إعادة إنشاء View راتب المعلمين بعد خطأ تغيير أسماء الأعمدة
-- يحل الخطأ:
-- ERROR: cannot change name of view column "verified_sessions" to "total_sessions"
--
-- السبب:
-- PostgreSQL لا يسمح بتغيير أسماء/ترتيب أعمدة الـ View عبر
-- CREATE OR REPLACE VIEW إذا كانت النسخة السابقة ببنية مختلفة.
--
-- الحل:
-- إسقاط الـ View ثم إعادة إنشائه بالبنية النهائية.
-- ============================================================================

-- هذا الملف يفترض أن SQL 126 و/أو 127 قد أُضيفا أو سيتم تشغيلهما بعده.

-- أولاً أسقط الـ View القديم إن وجد
 drop view if exists public.v_teacher_payroll_preview;

-- إذا كانت الطبقة اليومية موجودة، أعد بناء الـ View الشهري النهائي
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

select 'teacher_payroll_preview_recreated' as status;

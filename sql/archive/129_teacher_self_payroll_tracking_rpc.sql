-- ============================================================================
-- 129) RPC للمعلم: تتبع الحصص والراتب والانضباط الزمني ذاتياً
-- يعرض للمعلم نفسه:
-- - حصص اليوم
-- - هل سُجل الدخول للحصة؟
-- - هل يوجد تحضير درس؟
-- - هل يوجد واجب؟
-- - كم وحدة راتبية اكتسبت الحصة؟
-- - تقدم التأخير الشهري بحسب القواعد
-- - ملخص الراتب الشهري الذاتي بعد الحسميات
-- ============================================================================

create or replace function public.get_my_teacher_payroll_tracking(
  p_month text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_month date;
  v_month_end date;
  v_teacher record;
  v_amount_per_session numeric := 0;
  v_currency text := 'USD';
  v_today_sessions jsonb := '[]'::jsonb;
  v_lateness_progress jsonb := '[]'::jsonb;
  v_summary jsonb := '{}'::jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'message', 'يجب تسجيل الدخول');
  end if;

  select id, name, role into v_teacher
  from public.users
  where id = v_uid;

  if v_teacher.id is null then
    return jsonb_build_object('ok', false, 'message', 'الحساب غير موجود');
  end if;

  if coalesce(p_month,'') <> '' then
    v_month := to_date(p_month || '-01', 'YYYY-MM-DD');
  else
    v_month := date_trunc('month', current_date)::date;
  end if;
  v_month_end := (v_month + interval '1 month - 1 day')::date;

  select
    coalesce(specific.amount_per_verified_session, global_rule.amount_per_verified_session, 0),
    coalesce(specific.currency, global_rule.currency, 'USD')
  into v_amount_per_session, v_currency
  from (select v_uid as teacher_id) t
  left join public.teacher_payroll_rules specific
    on specific.teacher_id = t.teacher_id and specific.active = true
  left join public.teacher_payroll_rules global_rule
    on global_rule.teacher_id is null and global_rule.active = true
  limit 1;

  if to_regclass('public.v_teacher_session_payroll_evidence') is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'class_session_id', e.class_session_id,
      'session_date', e.session_date,
      'period_number', e.period_number,
      'class_name', e.class_name,
      'subject_name', e.subject_name,
      'has_lesson_plan', e.has_lesson_plan,
      'has_homework', e.has_homework,
      'has_manual_confirm', e.has_manual_confirm,
      'payroll_units', e.payroll_units,
      'payroll_status', e.payroll_status,
      'late_status', coalesce(c.late_status, 'not_checked_in'),
      'late_minutes', coalesce(c.late_minutes, 0),
      'recommended_next_step',
        case
          when c.id is null then 'سجّل دخول الحصة أولاً'
          when e.has_lesson_plan = 0 and e.has_homework = 0 then 'أضيفي تحضير الدرس أو الواجب لإثبات الحصة'
          when e.has_lesson_plan = 0 then 'أكملي تحضير الدرس لهذه الحصة'
          when e.has_homework = 0 then 'أضيفي واجباً مرتبطاً بالحصة لتكتمل الحصة راتبياً'
          else 'الحصة مكتملة ويمكن احتسابها بالكامل'
        end
    ) order by e.period_number, e.class_session_id), '[]'::jsonb)
    into v_today_sessions
    from public.v_teacher_session_payroll_evidence e
    left join public.teacher_session_checkins c
      on c.class_session_id = e.class_session_id
     and c.teacher_id = v_uid
    where e.teacher_id = v_uid
      and e.session_date = current_date;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'rule_id', r.id,
    'rule_name', r.rule_name,
    'min_late_minutes', r.min_late_minutes,
    'max_late_minutes', r.max_late_minutes,
    'repeat_count', r.repeat_count,
    'penalty_session_units', r.penalty_session_units,
    'late_events', coalesce(m.late_events,0),
    'penalty_batches', coalesce(m.penalty_batches,0),
    'penalty_session_units_total', coalesce(m.penalty_session_units_total,0),
    'progress_to_next_penalty', case when r.repeat_count > 0 then mod(coalesce(m.late_events,0), r.repeat_count) else 0 end,
    'remaining_before_next_penalty', case when r.repeat_count > 0 then greatest(r.repeat_count - mod(coalesce(m.late_events,0), r.repeat_count), 0) else 0 end
  ) order by r.sort_order), '[]'::jsonb)
  into v_lateness_progress
  from public.teacher_lateness_rules r
  left join (
    select *
    from public.v_teacher_lateness_penalties_monthly
    where teacher_id = v_uid and month = v_month
  ) m on m.rule_id = r.id
  where r.is_active = true;

  with gross as (
    select
      coalesce(sum(e.payroll_units),0) as gross_units,
      coalesce(sum(case when e.has_lesson_plan=1 then 1 else 0 end),0) as prepared_sessions,
      coalesce(sum(case when e.has_homework=1 then 1 else 0 end),0) as homework_sessions,
      count(*) as total_sessions,
      coalesce(sum(case when e.payroll_status='موثقة بالكامل' then 1 else 0 end),0) as fully_documented_sessions,
      coalesce(sum(case when e.payroll_status='غير مكتملة' then 1 else 0 end),0) as incomplete_sessions
    from public.v_teacher_session_payroll_evidence e
    where e.teacher_id = v_uid
      and e.session_date between v_month and v_month_end
  ), penalties as (
    select coalesce(sum(penalty_session_units_total),0) as penalty_units
    from public.v_teacher_lateness_penalties_monthly
    where teacher_id = v_uid and month = v_month
  )
  select jsonb_build_object(
    'month', to_char(v_month,'YYYY-MM'),
    'teacher_id', v_uid,
    'teacher_name', coalesce(v_teacher.name, '—'),
    'amount_per_session', v_amount_per_session,
    'currency', v_currency,
    'gross_units', g.gross_units,
    'penalty_units', p.penalty_units,
    'net_units', greatest(0, round(g.gross_units - p.penalty_units, 2)),
    'estimated_amount', round(greatest(0, g.gross_units - p.penalty_units) * v_amount_per_session, 2),
    'total_sessions', g.total_sessions,
    'prepared_sessions', g.prepared_sessions,
    'homework_sessions', g.homework_sessions,
    'fully_documented_sessions', g.fully_documented_sessions,
    'incomplete_sessions', g.incomplete_sessions
  )
  into v_summary
  from gross g, penalties p;

  return jsonb_build_object(
    'ok', true,
    'month', to_char(v_month,'YYYY-MM'),
    'teacher_id', v_uid,
    'teacher_name', coalesce(v_teacher.name, '—'),
    'today_sessions', v_today_sessions,
    'lateness_progress', v_lateness_progress,
    'monthly_summary', v_summary
  );
end;
$$;

grant execute on function public.get_my_teacher_payroll_tracking(text) to authenticated;

notify pgrst, 'reload schema';

select 'teacher_self_payroll_tracking_ready' as status;

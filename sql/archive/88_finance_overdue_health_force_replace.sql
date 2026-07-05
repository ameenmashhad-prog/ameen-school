-- =============================================================
-- مدارس أمين الرضا (ع) — Force Replace لفحص تذكيرات التحصيل المالي
-- إذا بقيت نتيجة health_check القديمة تظهر preview_all:null، شغّل هذا الملف.
-- =============================================================

create extension if not exists pgcrypto;

-- دوال صلاحية أساسية
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

-- ملخص تشخيصي لا يعتمد على auth.uid، مناسب لـ SQL Editor
create or replace function public.finance_overdue_reminders_debug_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  result jsonb;
begin
  with overdue_students as (
    select
      sf.id as student_fee_id,
      s.id as student_id,
      s.name as student_name,
      s.user_id as student_user_id,
      s.parent_id,
      c.name as class_name,
      coalesce(ov.overdue_amount,0) as overdue_amount,
      coalesce(ov.overdue_installments,0) as overdue_installments,
      case when ov.oldest_due_date is not null then current_date - ov.oldest_due_date else 0 end as max_days_late
    from public.student_fees sf
    join public.students s on s.id = sf.student_id
    left join public.classes c on c.id = s.class_id
    left join lateral (
      select
        count(*) as overdue_installments,
        coalesce(sum(greatest(coalesce(si.amount_due,0)-coalesce(si.amount_paid,0),0)),0) as overdue_amount,
        min(si.due_date) as oldest_due_date
      from public.student_installments si
      where si.student_fee_id = sf.id
        and coalesce(si.amount_paid,0) < coalesce(si.amount_due,0)
        and si.due_date < current_date
    ) ov on true
    where coalesce(ov.overdue_amount,0) > 0
  )
  select jsonb_build_object(
    'matched_students', count(*),
    'with_parent_recipient', count(*) filter (where parent_id is not null),
    'with_student_recipient', count(*) filter (where student_user_id is not null),
    'without_any_recipient', count(*) filter (where parent_id is null and student_user_id is null),
    'parent_already_sent_today', count(*) filter (where exists(
      select 1 from public.school_notifications n
      where n.recipient_user_id = overdue_students.parent_id
        and n.notification_type = 'finance_overdue'
        and n.entity_id = overdue_students.student_fee_id
        and n.created_at::date = current_date
    )),
    'student_already_sent_today', count(*) filter (where exists(
      select 1 from public.school_notifications n
      where n.recipient_user_id = overdue_students.student_user_id
        and n.notification_type = 'finance_overdue'
        and n.entity_id = overdue_students.student_fee_id
        and n.created_at::date = current_date
    )),
    'total_overdue_amount', coalesce(sum(overdue_amount),0),
    'sample', coalesce(jsonb_agg(jsonb_build_object(
      'student_name', student_name,
      'class_name', class_name,
      'overdue_amount', overdue_amount,
      'overdue_installments', overdue_installments,
      'max_days_late', max_days_late,
      'has_parent', parent_id is not null,
      'has_student_user', student_user_id is not null
    ) order by max_days_late desc, overdue_amount desc) filter (where true), '[]'::jsonb)
  )
  into result
  from overdue_students;

  return coalesce(result, jsonb_build_object(
    'matched_students',0,
    'with_parent_recipient',0,
    'with_student_recipient',0,
    'without_any_recipient',0,
    'parent_already_sent_today',0,
    'student_already_sent_today',0,
    'total_overdue_amount',0,
    'sample','[]'::jsonb
  ));
end;
$$;

grant execute on function public.finance_overdue_reminders_debug_summary() to authenticated;

-- حذف health_check القديم بالقوة ثم إعادة إنشائه
DROP FUNCTION IF EXISTS public.finance_overdue_reminders_health_check();

create function public.finance_overdue_reminders_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  preview_stats jsonb := null;
  debug_stats jsonb;
begin
  begin
    if to_regprocedure('public.preview_finance_overdue_reminders(uuid,uuid,int)') is not null then
      preview_stats := public.preview_finance_overdue_reminders(null,null,0)->'stats';
    end if;
  exception when others then
    preview_stats := null;
  end;

  debug_stats := public.finance_overdue_reminders_debug_summary();

  return jsonb_build_object(
    'version', 'force_replace_88',
    'checked_at', now(),
    'auth_uid', auth.uid(),
    'sql_editor_mode', auth.uid() is null,
    'preview_rpc', to_regprocedure('public.preview_finance_overdue_reminders(uuid,uuid,int)') is not null,
    'send_detailed_rpc', to_regprocedure('public.send_finance_overdue_reminders_detailed(uuid,uuid,int,boolean)') is not null,
    'send_legacy_rpc', to_regprocedure('public.send_finance_overdue_reminders(uuid,uuid,int)') is not null,
    'preview_all_with_current_session', preview_stats,
    'debug_summary_sql_editor_safe', debug_stats,
    'explanation', case when auth.uid() is null then 'SQL Editor بدون جلسة مستخدم؛ استخدمي debug_summary_sql_editor_safe للتشخيص، والواجهة للإرسال الفعلي.' else 'الفحص يعمل بجلسة مستخدم.' end
  );
end;
$$;

grant execute on function public.finance_overdue_reminders_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_overdue_health_force_replace_ready' as status;

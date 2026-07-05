-- =============================================================
-- مدارس أمين الرضا (ع) — Hotfix فحص الرصيد الدائن داخل SQL Editor
-- إذا ظهر executive_payload_credit = null فهذا غالباً لأن auth.uid() في SQL Editor = null.
-- هذا الملف يجعل الفحص يعرض direct_total_credit_balance بدون الاعتماد على جلسة مالية.
-- =============================================================

create extension if not exists pgcrypto;

alter table public.student_fees add column if not exists credit_balance numeric not null default 0;

create or replace function public.finance_credit_ui_support_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  payload_credit jsonb := null;
begin
  begin
    payload_credit := public.get_finance_executive_payload(date_trunc('month',current_date)::date,current_date)->'stats'->'total_credit_balance';
  exception when others then
    payload_credit := null;
  end;

  return jsonb_build_object(
    'checked_at', now(),
    'auth_uid', auth.uid(),
    'sql_editor_mode', auth.uid() is null,
    'credit_column', exists(select 1 from information_schema.columns where table_schema='public' and table_name='student_fees' and column_name='credit_balance'),
    'student_balances_has_credit', exists(select 1 from information_schema.columns where table_schema='public' and table_name='v_finance_exec_student_balances' and column_name='credit_balance'),
    'class_summary_has_credit', exists(select 1 from information_schema.columns where table_schema='public' and table_name='v_finance_exec_class_summary' and column_name='total_credit'),
    'collections_has_credit', exists(select 1 from information_schema.columns where table_schema='public' and table_name='v_finance_collection_students' and column_name='credit_balance'),
    'executive_payload_credit_with_current_session', payload_credit,
    'direct_total_credit_balance_sql_editor_safe', (select coalesce(sum(coalesce(credit_balance,0)),0) from public.student_fees),
    'credit_files', (select count(*) from public.student_fees where coalesce(credit_balance,0)>0),
    'credit_summary', coalesce((select jsonb_agg(to_jsonb(x) order by x.credit_balance desc) from (select * from public.v_finance_fee_credit_summary order by credit_balance desc) x), '[]'::jsonb),
    'explanation', case when auth.uid() is null then 'executive_payload_credit_with_current_session قد يكون null داخل SQL Editor لأن الدالة التنفيذية تحتاج جلسة مالية. استخدمي direct_total_credit_balance_sql_editor_safe للتأكد.' else 'الفحص يعمل بجلسة مستخدم.' end
  );
end;
$$;

grant execute on function public.finance_credit_ui_support_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_credit_health_sql_editor_fix_ready' as status;

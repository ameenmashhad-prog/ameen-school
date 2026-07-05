-- =============================================================
-- مدارس أمين الرضا (ع) — فحص الجاهزية النهائي للنظام
-- لا يغير البيانات، ولا يفعّل RLS جديد. تقرير فقط.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------
create or replace function public._safe_table_count(p_table text, p_where text default null)
returns int
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v int := 0;
  sql text;
begin
  if to_regclass('public.' || p_table) is null then
    return 0;
  end if;
  sql := format('select count(*)::int from public.%I', p_table);
  if p_where is not null and trim(p_where) <> '' then
    sql := sql || ' where ' || p_where;
  end if;
  execute sql into v;
  return coalesce(v,0);
exception when others then
  return 0;
end;
$$;

grant execute on function public._safe_table_count(text,text) to authenticated;

create or replace function public._object_exists(p_name text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select to_regclass('public.' || p_name) is not null;
$$;

grant execute on function public._object_exists(text) to authenticated;

create or replace function public._function_exists(p_name text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = p_name
  );
$$;

grant execute on function public._function_exists(text) to authenticated;

create or replace function public._rls_info(p_table text)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  enabled boolean;
  policies int;
begin
  select c.relrowsecurity into enabled
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname=p_table;

  select count(*) into policies
  from pg_policies
  where schemaname='public' and tablename=p_table;

  return jsonb_build_object('table',p_table,'exists',to_regclass('public.'||p_table) is not null,'rls_enabled',coalesce(enabled,false),'policies',coalesce(policies,0));
end;
$$;

grant execute on function public._rls_info(text) to authenticated;

-- -------------------------------------------------------------
-- Module status helper
-- -------------------------------------------------------------
create or replace function public._module_status(p_key text, p_label text, p_tables text[], p_functions text[] default array[]::text[], p_views text[] default array[]::text[])
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  missing_tables text[] := array[]::text[];
  missing_functions text[] := array[]::text[];
  missing_views text[] := array[]::text[];
  t text;
  f text;
  v text;
  state text;
begin
  foreach t in array coalesce(p_tables,array[]::text[]) loop
    if not public._object_exists(t) then missing_tables := missing_tables || t; end if;
  end loop;

  foreach f in array coalesce(p_functions,array[]::text[]) loop
    if not public._function_exists(f) then missing_functions := missing_functions || f; end if;
  end loop;

  foreach v in array coalesce(p_views,array[]::text[]) loop
    if not public._object_exists(v) then missing_views := missing_views || v; end if;
  end loop;

  state := case
    when array_length(missing_tables,1) is null and array_length(missing_functions,1) is null and array_length(missing_views,1) is null then 'ready'
    when array_length(missing_tables,1) is not null then 'missing'
    else 'warning'
  end;

  return jsonb_build_object(
    'key', p_key,
    'label', p_label,
    'status', state,
    'missing_tables', coalesce(to_jsonb(missing_tables),'[]'::jsonb),
    'missing_functions', coalesce(to_jsonb(missing_functions),'[]'::jsonb),
    'missing_views', coalesce(to_jsonb(missing_views),'[]'::jsonb)
  );
end;
$$;

grant execute on function public._module_status(text,text,text[],text[],text[]) to authenticated;

-- -------------------------------------------------------------
-- Final readiness report
-- -------------------------------------------------------------
create or replace function public.final_system_readiness_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  modules jsonb;
  module_ready int;
  module_warning int;
  module_missing int;
  core_counts jsonb;
  rls jsonb;
  functions jsonb;
  issues jsonb := '[]'::jsonb;
  old_health jsonb := null;
begin
  modules := jsonb_build_array(
    public._module_status('core','النواة والمستخدمون', array['users','students','classes','subjects'], array['get_my_portal_payload','get_my_permissions'], array[]::text[]),
    public._module_status('portal','البوابة الموحدة والصلاحيات', array['user_extra_permissions','school_notifications'], array['get_my_portal_payload','grant_user_permission','revoke_user_permission'], array['v_my_notifications']),
    public._module_status('registration','التسجيلات', array['registration_families','registration_students','registration_teachers'], array['registration_username_taken'], array['v_registration_family_students']),
    public._module_status('schedule','الجداول والشعب', array['weekly_schedule','class_sessions','sections','teacher_assignments','student_enrollments'], array['regenerate_class_sessions','schedule_validate_weekly_schedule'], array['v_teacher_schedule','v_teacher_students','v_section_roster']),
    public._module_status('teacher','لوحة المعلم', array['attendance','homeworks','lesson_plans','teacher_activity_log'], array['save_lesson_plan','create_session_homework'], array['v_teacher_students','v_teacher_schedule']),
    public._module_status('homework','الواجبات والتسليمات', array['homeworks','homework_attachments','homework_grades','homework_submissions','homework_submission_attachments'], array['save_homework_pro','save_homework_grade','save_homework_submission','review_homework_submission'], array['v_student_homeworks','v_teacher_homework_submissions']),
    public._module_status('exams','بنك الأسئلة والاختبارات', array['question_banks','questions','question_options','online_exams','exam_attempts','exam_answers'], array['get_online_exam_payload','submit_online_exam_attempt','upsert_question_advanced'], array['v_online_exam_analysis','v_online_exam_attempts_detailed']),
    public._module_status('exam_integrity','نزاهة الاختبارات', array['exam_reference_sources'], array['exam_ai_likelihood_score','exam_best_text_similarity'], array['v_exam_integrity_answer_flags','v_exam_answer_similarity_pairs']),
    public._module_status('finance','المالية الأساسية', array['student_fees','student_installments','fee_payments','fee_structures'], array['get_finance_executive_payload','save_homework_grade'], array['v_finance_exec_student_balances','v_finance_exec_payments']),
    public._module_status('cashbox','صندوق اليومية والمستلمين', array['finance_cashbox_closures'], array['get_finance_cashbox_payload','close_finance_cashbox','void_fee_payment'], array['v_finance_cashbox_daily','v_fee_payments_detailed','v_finance_receiver_monthly']),
    public._module_status('collections','التحصيل والمتابعة', array['finance_followups'], array['get_finance_collection_payload','send_finance_overdue_reminders','get_student_finance_statement'], array['v_finance_collection_students']),
    public._module_status('academic','الأكاديمي والدرجات', array['grade_weights','continuous_assessments','exams','exam_scores','academic_exemption_decisions','academic_flags'], array[]::text[], array['v_academic_subject_results','v_academic_student_summary']),
    public._module_status('calendar','التقويم الذكي والأجندة', array['countries','school_branches','academic_years','holiday_rules','holidays','exam_periods','calendar_events','completed_items'], array['smart_calendar_health_check','get_calendar_month','get_my_agenda','get_dashboard_home'], array[]::text[]),
    public._module_status('library','المكتبة', array['library_items','library_copies','library_loans','library_reservations'], array['library_health_check','library_checkout','library_return'], array['v_library_catalog','v_library_loans_detailed']),
    public._module_status('inventory','المخزون والمشتريات', array['suppliers','inventory_items','inventory_stock_movements','purchase_requests','purchase_request_items'], array['inventory_health_check','inventory_adjust_stock','purchase_request_receive'], array['v_inventory_stock','v_purchase_requests_detailed']),
    public._module_status('assets','الأصول والعهد', array['fixed_assets','asset_custody_records','asset_maintenance_tickets'], array['assets_health_check','asset_assign','asset_return'], array['v_fixed_assets_register','v_asset_custody_detailed']),
    public._module_status('hr','الموارد البشرية', array['hr_employee_profiles','hr_attendance','hr_leave_requests','hr_payroll_runs','hr_payroll_items'], array['hr_health_check','hr_generate_payroll'], array['v_hr_employees','v_hr_payroll_detailed']),
    public._module_status('transport','النقل المدرسي', array['transport_vehicles','transport_drivers','transport_routes','transport_student_assignments','transport_trips','transport_trip_attendance'], array['transport_health_check','transport_create_trip','transport_mark_attendance'], array['v_transport_routes_detailed','v_transport_trips_detailed']),
    public._module_status('labs_activities','المختبرات والأنشطة', array['lab_rooms','lab_equipment','lab_experiments','lab_incidents','school_activities','activity_participants'], array['labs_activities_health_check','activity_register_student'], array['v_lab_rooms_status','v_school_activities_detailed']),
    public._module_status('documents','الوثائق والأرشفة', array['document_categories','document_records','document_files','document_access_logs'], array['documents_health_check','get_documents_payload','document_create_record'], array['v_documents_detailed','v_document_files_detailed']),
    public._module_status('analytics','التحليلات والإعلانات', array['school_announcements','school_notifications'], array['get_enterprise_dashboard_payload','broadcast_school_announcement'], array['v_school_announcements_detailed'])
  );

  select count(*) into module_ready from jsonb_array_elements(modules) m where m->>'status'='ready';
  select count(*) into module_warning from jsonb_array_elements(modules) m where m->>'status'='warning';
  select count(*) into module_missing from jsonb_array_elements(modules) m where m->>'status'='missing';

  core_counts := jsonb_build_object(
    'users', public._safe_table_count('users'),
    'students', public._safe_table_count('students'),
    'teachers', public._safe_table_count('users','role=''teacher'''),
    'parents', public._safe_table_count('users','role=''parent'''),
    'classes', public._safe_table_count('classes'),
    'subjects', public._safe_table_count('subjects'),
    'homeworks', public._safe_table_count('homeworks'),
    'homework_submissions', public._safe_table_count('homework_submissions'),
    'online_exams', public._safe_table_count('online_exams'),
    'payments', public._safe_table_count('fee_payments'),
    'library_items', public._safe_table_count('library_items'),
    'inventory_items', public._safe_table_count('inventory_items'),
    'assets', public._safe_table_count('fixed_assets'),
    'hr_employees', public._safe_table_count('hr_employee_profiles'),
    'transport_routes', public._safe_table_count('transport_routes'),
    'documents', public._safe_table_count('document_records')
  );

  rls := jsonb_build_array(
    public._rls_info('students'), public._rls_info('attendance'), public._rls_info('homeworks'),
    public._rls_info('homework_submissions'), public._rls_info('fee_payments'), public._rls_info('student_fees'),
    public._rls_info('online_exams'), public._rls_info('exam_attempts'), public._rls_info('document_records'),
    public._rls_info('school_notifications'), public._rls_info('users')
  );

  functions := jsonb_build_object(
    'portal', public._function_exists('get_my_portal_payload'),
    'finance_executive', public._function_exists('get_finance_executive_payload'),
    'finance_cashbox', public._function_exists('get_finance_cashbox_payload'),
    'smart_calendar', public._function_exists('smart_calendar_health_check'),
    'homework', public._function_exists('save_homework_submission'),
    'documents', public._function_exists('get_documents_payload')
  );

  if exists(select 1 from jsonb_array_elements(rls) x where x->>'table'='users' and x->>'rls_enabled'='false') then
    issues := issues || jsonb_build_array(jsonb_build_object('level','warning','code','users_rls_disabled','message','RLS على جدول users غير مفعل. هذا مقصود غالباً أثناء الاختبار النهائي، ولا يتم تفعيله تلقائياً.'));
  end if;

  if module_missing > 0 then
    issues := issues || jsonb_build_array(jsonb_build_object('level','danger','code','missing_modules','message','توجد وحدات ناقصة تحتاج تشغيل SQL الخاص بها.'));
  end if;

  if public._function_exists('system_health_check') then
    begin
      execute 'select public.system_health_check()' into old_health;
    exception when others then
      old_health := jsonb_build_object('error','تعذر تشغيل system_health_check');
    end;
  end if;

  return jsonb_build_object(
    'ok', module_missing = 0,
    'checked_at', now(),
    'summary', jsonb_build_object('ready',module_ready,'warning',module_warning,'missing',module_missing,'total',module_ready+module_warning+module_missing),
    'core_counts', core_counts,
    'modules', modules,
    'rls', rls,
    'functions', functions,
    'issues', issues,
    'legacy_system_health', old_health,
    'next_recommendation', case when module_missing=0 then 'النظام جاهز للاختبار التشغيلي النهائي. راجعي تحذير RLS على users قبل الإنتاج الكامل.' else 'شغّلي SQL للوحدات الناقصة ثم أعيدي الفحص.' end
  );
end;
$$;

grant execute on function public.final_system_readiness_check() to authenticated;

notify pgrst, 'reload schema';

select 'final_system_readiness_check_ready' as status;

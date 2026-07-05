-- =============================================================
-- مدارس أمين الرضا (ع) — فحص الحوكمة والأمن المركزي
-- يجمع نتائج: RLS، صلاحيات الإرشاد، كلمات المرور، الدوال الحساسة.
-- تقرير فقط ولا يغير بيانات العمل.
-- =============================================================

create extension if not exists pgcrypto;

create or replace function public._security_table_count(p_table text, p_where text default null)
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

grant execute on function public._security_table_count(text,text) to authenticated;

create or replace function public._security_rls_table(p_table text)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  enabled boolean := false;
  policies int := 0;
begin
  select c.relrowsecurity
  into enabled
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public' and c.relname=p_table;

  select count(*)
  into policies
  from pg_policies
  where schemaname='public' and tablename=p_table;

  return jsonb_build_object(
    'table', p_table,
    'exists', to_regclass('public.' || p_table) is not null,
    'rls_enabled', coalesce(enabled,false),
    'policies', coalesce(policies,0)
  );
end;
$$;

grant execute on function public._security_rls_table(text) to authenticated;

create or replace function public._security_function_exists(p_name text)
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
    where n.nspname='public' and p.proname=p_name
  );
$$;

grant execute on function public._security_function_exists(text) to authenticated;

create or replace function public.security_governance_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  issues jsonb := '[]'::jsonb;
  critical_count int := 0;
  medium_count int := 0;
  low_count int := 0;
  weak_families int := 0;
  weak_students int := 0;
  weak_teachers int := 0;
  reg_constraints jsonb := '[]'::jsonb;
  counseling_rls jsonb := '[]'::jsonb;
  core_rls jsonb := '[]'::jsonb;
  functions jsonb := '{}'::jsonb;
  fn_src text := '';
  unvalidated_count int := 0;
  counseling_bad_rls int := 0;
  users_rls_enabled boolean := false;
begin
  weak_families := public._security_table_count('registration_families', 'initial_password ~ ''^[0-9]{6,10}$''');
  weak_students := public._security_table_count('registration_students', 'initial_password ~ ''^[0-9]{6,10}$''');
  weak_teachers := public._security_table_count('registration_teachers', 'initial_password ~ ''^[0-9]{6,10}$''');

  select coalesce(jsonb_agg(jsonb_build_object(
    'table', conrelid::regclass::text,
    'constraint', conname,
    'validated', convalidated
  ) order by conname), '[]'::jsonb)
  into reg_constraints
  from pg_constraint
  where conname in (
    'registration_families_initial_password_strength',
    'registration_students_initial_password_strength',
    'registration_teachers_initial_password_strength'
  );

  select count(*)
  into unvalidated_count
  from pg_constraint
  where conname in (
    'registration_families_initial_password_strength',
    'registration_students_initial_password_strength',
    'registration_teachers_initial_password_strength'
  )
  and convalidated = false;

  core_rls := jsonb_build_array(
    public._security_rls_table('users'),
    public._security_rls_table('students'),
    public._security_rls_table('school_notifications')
  );

  counseling_rls := jsonb_build_array(
    public._security_rls_table('counseling_cases'),
    public._security_rls_table('counseling_sessions'),
    public._security_rls_table('counseling_goals'),
    public._security_rls_table('counseling_assessments'),
    public._security_rls_table('counseling_referrals'),
    public._security_rls_table('counseling_access_logs')
  );

  select count(*)
  into counseling_bad_rls
  from jsonb_array_elements(counseling_rls) x
  where (x->>'exists')::boolean = true
    and ((x->>'rls_enabled')::boolean = false or (x->>'policies')::int = 0);

  select coalesce((public._security_rls_table('users')->>'rls_enabled')::boolean,false)
  into users_rls_enabled;

  functions := jsonb_build_object(
    'security_quick_hardening_health_check', public._security_function_exists('security_quick_hardening_health_check'),
    'registration_password_policy_health_check', public._security_function_exists('registration_password_policy_health_check'),
    'registration_weak_password_cleanup_health_check', public._security_function_exists('registration_weak_password_cleanup_health_check'),
    'get_counseling_admin_aggregate_report', public._security_function_exists('get_counseling_admin_aggregate_report'),
    'counseling_student_request_session', public._security_function_exists('counseling_student_request_session'),
    'counseling_quick_referral', public._security_function_exists('counseling_quick_referral'),
    'current_user_can_counseling', public._security_function_exists('current_user_can_counseling'),
    'portal_default_permissions', public._security_function_exists('portal_default_permissions')
  );

  select coalesce(p.prosrc,'')
  into fn_src
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='current_user_can_counseling'
  limit 1;

  if weak_families + weak_students + weak_teachers > 0 then
    critical_count := critical_count + 1;
    issues := issues || jsonb_build_array(jsonb_build_object(
      'level','critical',
      'code','weak_registration_passwords_remaining',
      'message','توجد كلمات مرور تسجيل رقمية ضعيفة متبقية. شغل sql/102 أو sql/103.'
    ));
  end if;

  if counseling_bad_rls > 0 then
    critical_count := critical_count + 1;
    issues := issues || jsonb_build_array(jsonb_build_object(
      'level','critical',
      'code','counseling_rls_issue',
      'message','بعض جداول الإرشاد النفسي بلا RLS أو بلا سياسات.'
    ));
  end if;

  if fn_src ilike '%academic%' or fn_src ilike '%u.role in (''admin''%' then
    critical_count := critical_count + 1;
    issues := issues || jsonb_build_array(jsonb_build_object(
      'level','critical',
      'code','counseling_full_access_too_broad',
      'message','دالة current_user_can_counseling تبدو واسعة جداً. شغل sql/100_security_quick_hardening.sql.'
    ));
  end if;

  if not users_rls_enabled then
    medium_count := medium_count + 1;
    issues := issues || jsonb_build_array(jsonb_build_object(
      'level','medium',
      'code','users_rls_disabled',
      'message','RLS على users غير مفعل.'
    ));
  end if;

  if unvalidated_count > 0 or jsonb_array_length(reg_constraints) < 3 then
    medium_count := medium_count + 1;
    issues := issues || jsonb_build_array(jsonb_build_object(
      'level','medium',
      'code','registration_password_constraints_not_validated',
      'message','قيود كلمات المرور المؤقتة غير مكتملة أو غير مفعلة بالكامل.'
    ));
  end if;

  if not (functions->>'get_counseling_admin_aggregate_report')::boolean then
    medium_count := medium_count + 1;
    issues := issues || jsonb_build_array(jsonb_build_object(
      'level','medium',
      'code','missing_anonymous_counseling_report',
      'message','تقرير الإرشاد المجهول غير موجود. شغل sql/100.'
    ));
  end if;

  if not (functions->>'counseling_student_request_session')::boolean then
    low_count := low_count + 1;
    issues := issues || jsonb_build_array(jsonb_build_object(
      'level','low',
      'code','missing_student_request_session',
      'message','طلب موعد الطالب للبرنامج غير مفعل. شغل sql/104.'
    ));
  end if;

  return jsonb_build_object(
    'ok', critical_count = 0,
    'checked_at', now(),
    'summary', jsonb_build_object(
      'critical', critical_count,
      'medium', medium_count,
      'low', low_count,
      'score_10', case
        when critical_count > 0 then greatest(4, 8 - critical_count*2 - medium_count)
        when medium_count > 0 then greatest(6, 9 - medium_count)
        else 10
      end
    ),
    'issues', issues,
    'registration_passwords', jsonb_build_object(
      'weak_remaining', jsonb_build_object('families',weak_families,'students',weak_students,'teachers',weak_teachers),
      'constraints', reg_constraints
    ),
    'rls', jsonb_build_object(
      'core', core_rls,
      'counseling', counseling_rls
    ),
    'functions', functions,
    'recommendations', jsonb_build_array(
      'استمر بتشغيل ملفات SQL من الحزمة وليس من نسخ المحادثة.',
      'استخدم صفحة security-governance.html لمراقبة الحالة بعد كل نشر.',
      'إذا ظهرت issues حرجة، عالجها قبل إدخال بيانات إنتاجية جديدة.'
    )
  );
end;
$$;

grant execute on function public.security_governance_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.security_governance_health_check() as security_governance_health;

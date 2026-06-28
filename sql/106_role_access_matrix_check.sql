-- =============================================================
-- مدارس أمين الرضا (ع) — فحص مصفوفة صلاحيات الأدوار
-- يتحقق أن الطالب/المعلم لا تظهر لهم وحدات غير مصرح بها،
-- وأن الإرشاد النفسي الكامل محصور بالمرشد/الأخصائي فقط.
-- تقرير فقط ولا يغير البيانات.
-- =============================================================

create extension if not exists pgcrypto;

create or replace function public._perm_has(p_perms text[], p_key text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(p_key = any(coalesce(p_perms,array[]::text[])), false);
$$;

grant execute on function public._perm_has(text[],text) to authenticated;

create or replace function public.security_role_access_matrix_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  roles text[] := array['admin','academic','teacher','student','parent','finance','counselor','staff'];
  r text;
  p text[];
  matrix jsonb := '[]'::jsonb;
  issues jsonb := '[]'::jsonb;
  critical_count int := 0;
  medium_count int := 0;
  low_count int := 0;
  has_counseling boolean;
  has_counseling_full boolean;
  has_counseling_report boolean;
  has_finance boolean;
  has_users boolean;
  has_admin boolean;
  has_teacher boolean;
  has_student boolean;
  has_calendar boolean;
  has_achievements boolean;
begin
  if to_regprocedure('public.portal_default_permissions(text,boolean)') is null then
    return jsonb_build_object(
      'ok', false,
      'summary', jsonb_build_object('critical',1,'medium',0,'low',0),
      'issues', jsonb_build_array(jsonb_build_object('level','critical','code','portal_default_permissions_missing','message','دالة صلاحيات البوابة غير موجودة'))
    );
  end if;

  foreach r in array roles loop
    p := public.portal_default_permissions(r, false);
    has_counseling := public._perm_has(p,'counseling');
    has_counseling_full := public._perm_has(p,'counseling.full');
    has_counseling_report := public._perm_has(p,'counseling.report');
    has_finance := public._perm_has(p,'finance');
    has_users := public._perm_has(p,'users');
    has_admin := public._perm_has(p,'admin');
    has_teacher := public._perm_has(p,'teacher');
    has_student := public._perm_has(p,'student');
    has_calendar := public._perm_has(p,'calendar');
    has_achievements := public._perm_has(p,'achievements');

    matrix := matrix || jsonb_build_array(jsonb_build_object(
      'role', r,
      'permissions_count', coalesce(array_length(p,1),0),
      'has_admin', has_admin,
      'has_users', has_users,
      'has_finance', has_finance,
      'has_teacher', has_teacher,
      'has_student', has_student,
      'has_calendar', has_calendar,
      'has_achievements', has_achievements,
      'has_counseling', has_counseling,
      'has_counseling_full', has_counseling_full,
      'has_counseling_report', has_counseling_report,
      'permissions', to_jsonb(coalesce(p,array[]::text[]))
    ));

    -- الطالب: لا إدارة، لا مالية عامة، لا إرشاد نفسي كامل/تقرير.
    if r = 'student' and (has_admin or has_users or has_finance or has_counseling or has_counseling_full or has_counseling_report) then
      critical_count := critical_count + 1;
      issues := issues || jsonb_build_array(jsonb_build_object('level','critical','role',r,'code','student_overprivileged','message','الطالب يملك صلاحيات لا يجب أن تظهر له.'));
    end if;

    -- المعلم: لا مالية عامة، لا إدارة مستخدمين، لا إرشاد نفسي كامل ولا تقرير مجهول.
    if r = 'teacher' and (has_finance or has_users or has_admin or has_counseling or has_counseling_full or has_counseling_report) then
      critical_count := critical_count + 1;
      issues := issues || jsonb_build_array(jsonb_build_object('level','critical','role',r,'code','teacher_overprivileged','message','المعلم يملك صلاحيات غير مناسبة مثل المالية/الإرشاد/المستخدمين.'));
    end if;

    -- ولي الأمر: مسموح المالية الخاصة، لكن لا إدارة ولا إرشاد نفسي.
    if r = 'parent' and (has_admin or has_users or has_counseling or has_counseling_full or has_counseling_report) then
      critical_count := critical_count + 1;
      issues := issues || jsonb_build_array(jsonb_build_object('level','critical','role',r,'code','parent_overprivileged','message','ولي الأمر يملك صلاحيات إدارية أو إرشادية غير مناسبة.'));
    end if;

    -- الأكاديمي: يرى تقريراً مجهولاً فقط وليس تفاصيل الإرشاد.
    if r = 'academic' and (has_counseling or has_counseling_full) then
      critical_count := critical_count + 1;
      issues := issues || jsonb_build_array(jsonb_build_object('level','critical','role',r,'code','academic_has_full_counseling','message','الأكاديمي يجب ألا يملك تفاصيل الإرشاد النفسي.'));
    end if;
    if r = 'academic' and not has_counseling_report then
      medium_count := medium_count + 1;
      issues := issues || jsonb_build_array(jsonb_build_object('level','medium','role',r,'code','academic_missing_anonymous_report','message','الأكاديمي لا يملك تقرير البرنامج المجهول.'));
    end if;

    -- الإدارة: لا تحصل على تفاصيل الإرشاد الكامل افتراضياً؛ لديها تقرير مجهول.
    if r = 'admin' and (has_counseling or has_counseling_full) then
      critical_count := critical_count + 1;
      issues := issues || jsonb_build_array(jsonb_build_object('level','critical','role',r,'code','admin_has_full_counseling_by_default','message','الإدارة لا يجب أن تملك تفاصيل الإرشاد افتراضياً. استخدم counseling.full كتفويض صريح فقط.'));
    end if;
    if r = 'admin' and not has_counseling_report then
      medium_count := medium_count + 1;
      issues := issues || jsonb_build_array(jsonb_build_object('level','medium','role',r,'code','admin_missing_anonymous_report','message','الإدارة لا تملك تقرير البرنامج المجهول.'));
    end if;

    -- المرشد/النفسي يجب أن يملك counseling و counseling.full.
    if r = 'counselor' and not (has_counseling and has_counseling_full) then
      critical_count := critical_count + 1;
      issues := issues || jsonb_build_array(jsonb_build_object('level','critical','role',r,'code','counselor_missing_full_access','message','المرشد لا يملك صلاحية الإرشاد الكاملة.'));
    end if;

    -- التقويم والشارات أساسية للطالب والمعلم والمرشد.
    if r in ('student','teacher','counselor') and not has_calendar then
      low_count := low_count + 1;
      issues := issues || jsonb_build_array(jsonb_build_object('level','low','role',r,'code','missing_calendar','message','هذا الدور لا يملك التقويم رغم أنه مركز العمل اليومي.'));
    end if;
    if r in ('student','teacher','counselor') and not has_achievements then
      low_count := low_count + 1;
      issues := issues || jsonb_build_array(jsonb_build_object('level','low','role',r,'code','missing_achievements','message','هذا الدور لا يملك الشارات رغم أنها جزء تحفيزي مهم.'));
    end if;
  end loop;

  return jsonb_build_object(
    'ok', critical_count = 0,
    'checked_at', now(),
    'summary', jsonb_build_object('critical',critical_count,'medium',medium_count,'low',low_count,'roles_checked',array_length(roles,1)),
    'issues', issues,
    'matrix', matrix,
    'notes', jsonb_build_array(
      'الإرشاد النفسي الكامل يجب أن يظهر فقط لصلاحية counseling/counseling.full.',
      'الإدارة والأكاديميون يستخدمون counseling.report فقط للتقرير المجهول.',
      'الطالب والمعلم لا يحصلون على روابط الإدارة أو تفاصيل الإرشاد.'
    )
  );
end;
$$;

grant execute on function public.security_role_access_matrix_check() to authenticated;

notify pgrst, 'reload schema';

select public.security_role_access_matrix_check() as security_role_access_matrix;

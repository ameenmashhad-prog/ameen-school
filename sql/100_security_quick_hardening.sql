-- =============================================================
-- مدارس أمين الرضا (ع) — دفعة تقوية أمنية سريعة
-- 1) تقييد الوصول الكامل للإرشاد النفسي للمرشد/النفسي/المسؤول الأعلى فقط.
-- 2) تقرير إداري مجمّع دون أسماء.
-- 3) تثبيت صلاحيات البوابة بعد التقييد.
-- آمن ويمكن تشغيله أكثر من مرة.
-- =============================================================

create extension if not exists pgcrypto;

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

create or replace function public.current_user_is_super_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(select 1 from public.users u where u.id=auth.uid() and coalesce(u.is_super_admin,false)=true);
$$;

grant execute on function public.current_user_is_super_admin() to authenticated;

create or replace function public.current_user_has_extra_permission(p_permission text)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  ok boolean := false;
begin
  if to_regclass('public.user_extra_permissions') is null then
    return false;
  end if;
  execute $q$
    select exists(
      select 1
      from public.user_extra_permissions ep
      where ep.user_id = auth.uid()
        and ep.permission_key = $1
        and ep.is_active = true
        and (ep.expires_at is null or ep.expires_at > now())
    )
  $q$ into ok using p_permission;
  return coalesce(ok,false);
end;
$$;

grant execute on function public.current_user_has_extra_permission(text) to authenticated;

-- الوصول الكامل لتفاصيل الإرشاد: المرشد/النفسي/المسؤول الأعلى أو تفويض صريح فقط.
create or replace function public.current_user_can_counseling()
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
        or u.role in ('counselor','psychologist')
        or public.current_user_has_extra_permission('counseling.full')
        or public.current_user_has_extra_permission('counseling')
      )
  );
$$;

grant execute on function public.current_user_can_counseling() to authenticated;

-- صلاحية تقرير مجمّع فقط: لا تعطي حق قراءة الجلسات أو أسماء الطلاب.
create or replace function public.current_user_can_counseling_aggregate()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.current_user_can_counseling()
    or exists(
      select 1 from public.users u
      where u.id = auth.uid()
        and (
          u.role in ('admin','academic','academic_admin','scientific','supervisor')
          or public.current_user_has_extra_permission('counseling.report')
        )
    );
$$;

grant execute on function public.current_user_can_counseling_aggregate() to authenticated;

-- شدّ صلاحيات الجداول الحساسة: الكتابة عبر RPC فقط.
do $$
begin
  if to_regclass('public.counseling_cases') is not null then
    revoke insert, update, delete on public.counseling_cases from authenticated, anon;
    grant select on public.counseling_cases to authenticated;
  end if;
  if to_regclass('public.counseling_sessions') is not null then
    revoke insert, update, delete on public.counseling_sessions from authenticated, anon;
    grant select on public.counseling_sessions to authenticated;
  end if;
  if to_regclass('public.counseling_goals') is not null then
    revoke insert, update, delete on public.counseling_goals from authenticated, anon;
    grant select on public.counseling_goals to authenticated;
  end if;
  if to_regclass('public.counseling_assessments') is not null then
    revoke insert, update, delete on public.counseling_assessments from authenticated, anon;
    grant select on public.counseling_assessments to authenticated;
  end if;
  if to_regclass('public.counseling_family_contacts') is not null then
    revoke insert, update, delete on public.counseling_family_contacts from authenticated, anon;
    grant select on public.counseling_family_contacts to authenticated;
  end if;
exception when others then
  raise notice 'counseling grants hardening notice: %', sqlerrm;
end $$;

-- تقرير إداري مجهول بالكامل.
create or replace function public.get_counseling_admin_aggregate_report()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  risk_distribution jsonb := '[]'::jsonb;
  monthly_sessions jsonb := '[]'::jsonb;
begin
  if not public.current_user_can_counseling_aggregate() then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية التقرير المجمع');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('risk_level', risk_level, 'count', cnt) order by sort_order), '[]'::jsonb)
  into risk_distribution
  from (
    select risk_level, count(*)::int cnt,
      case risk_level when 'crisis' then 1 when 'urgent' then 2 when 'high' then 3 when 'medium' then 4 when 'followup' then 5 when 'stable' then 6 else 7 end sort_order
    from public.counseling_cases
    where status in ('active','watch')
    group by risk_level
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object('month', month, 'sessions', sessions) order by month), '[]'::jsonb)
  into monthly_sessions
  from (
    select to_char(date_trunc('month', session_at), 'YYYY-MM') as month, count(*)::int sessions
    from public.counseling_sessions
    where session_at >= date_trunc('month', now()) - interval '5 months'
    group by date_trunc('month', session_at)
  ) m;

  return jsonb_build_object(
    'ok', true,
    'anonymous', true,
    'active_cases', coalesce((select count(*) from public.counseling_cases where status in ('active','watch')),0),
    'sessions_this_month', coalesce((select count(*) from public.counseling_sessions where session_at >= date_trunc('month', now())),0),
    'pending_referrals', coalesce((select count(*) from public.counseling_referrals where status='pending'),0),
    'open_goals', coalesce((select count(*) from public.counseling_goals where status='active'),0),
    'risk_distribution', risk_distribution,
    'monthly_sessions', monthly_sessions,
    'note', 'تقرير مجمّع لا يحتوي أسماء أو ملاحظات جلسات أو معرفات طلاب'
  );
end;
$$;

grant execute on function public.get_counseling_admin_aggregate_report() to authenticated;

-- تثبيت صلاحيات البوابة: counseling للمرشد فقط، وcounseling.report للإدارة كتقرير مجهول.
create or replace function public.portal_default_permissions(p_role text, p_is_super_admin boolean default false)
returns text[]
language plpgsql
stable
as $$
declare
  r text := lower(coalesce(p_role,''));
begin
  if coalesce(p_is_super_admin,false) or r = 'admin' then
    return array[
      'admin','staff.dashboard','finance','academic','schedule','sections','grades','attendance','behavior','users','reports','registrations','system','calendar','achievements','counseling.report',
      'teacher','student','parent','homework','homework.reports','homework.audit','question_bank','online_exams','exam_integrity',
      'library','inventory','assets','hr','transport','labs','activities','notifications'
    ];
  end if;

  if r = 'finance' then
    return array['staff.dashboard','finance','reports','homework.reports','library','inventory','assets','achievements','notifications'];
  end if;

  if r in ('academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor') then
    return array['staff.dashboard','academic','schedule','sections','grades','attendance','behavior','reports','registrations','question_bank','online_exams','exam_integrity','homework.reports','library','transport','labs','activities','calendar','achievements','counseling.report','notifications'];
  end if;

  if r in ('discipline') then
    return array['staff.dashboard','attendance','behavior','students','reports','transport','homework.reports','calendar','achievements','notifications'];
  end if;

  if r in ('counselor','psychologist') then
    return array['staff.dashboard','counseling','counseling.full','behavior','students','attendance','reports','calendar','achievements','notifications'];
  end if;

  if r = 'teacher' then
    return array['teacher','attendance','homework','homework.reports','homework.audit','grades','question_bank','online_exams','library','transport','labs','activities','calendar','achievements','notifications'];
  end if;

  if r = 'student' then
    return array['student','homework','online_exams','grades','attendance','behavior','library','transport','activities','calendar','achievements','notifications'];
  end if;

  if r = 'parent' then
    return array['parent','student','homework','online_exams','grades','attendance','behavior','finance','library','transport','activities','calendar','achievements','notifications'];
  end if;

  if r in ('staff') then
    return array['staff.dashboard','attendance','students','reports','library','inventory','assets','transport','activities','calendar','achievements','notifications'];
  end if;

  if r in ('hr') then return array['staff.dashboard','hr','reports','achievements','notifications']; end if;
  if r in ('inventory','procurement') then return array['staff.dashboard','inventory','reports','achievements','notifications']; end if;
  if r in ('transport','transport_manager') then return array['staff.dashboard','transport','reports','achievements','notifications']; end if;
  if r in ('librarian') then return array['library','reports','achievements','notifications']; end if;

  return array['calendar','achievements','notifications'];
end;
$$;

grant execute on function public.portal_default_permissions(text,boolean) to authenticated;

create or replace function public.security_quick_hardening_health_check()
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
    'counseling_full_access_current_user', public.current_user_can_counseling(),
    'counseling_aggregate_current_user', public.current_user_can_counseling_aggregate(),
    'aggregate_rpc', to_regprocedure('public.get_counseling_admin_aggregate_report()') is not null,
    'portal_permissions_rpc', to_regprocedure('public.portal_default_permissions(text,boolean)') is not null,
    'notes', jsonb_build_array(
      'تفاصيل الإرشاد للمرشد/النفسي/المسؤول الأعلى أو تفويض counseling.full فقط.',
      'الإدارة والأكاديميون يحصلون على counseling.report للتقارير المجمعة دون أسماء.',
      'الكتابة المباشرة على جداول الإرشاد مقيدة؛ استخدم RPC للحفظ.'
    )
  );
end;
$$;

grant execute on function public.security_quick_hardening_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.security_quick_hardening_health_check() as security_quick_hardening;

-- =============================================================
-- مدارس أمين الرضا (ع) — واجهة إدارة التفويضات والصلاحيات
-- يكمّل البوابة الموحدة: منح/إلغاء صلاحيات إضافية لكل مستخدم.
-- =============================================================

create extension if not exists pgcrypto;

create table if not exists public.user_extra_permissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  permission_key text not null,
  is_active boolean not null default true,
  granted_by uuid null references public.users(id),
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  notes text,
  unique(user_id, permission_key)
);

create index if not exists idx_user_extra_permissions_user_active on public.user_extra_permissions(user_id, is_active);

-- -------------------------------------------------------------
-- الصلاحيات الأساسية
-- -------------------------------------------------------------
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

-- إعادة تعريف آمنة إذا لم تكن موجودة من SQL 62.
create or replace function public.portal_default_permissions(p_role text, p_is_super_admin boolean default false)
returns text[]
language plpgsql
stable
as $$
declare r text := lower(coalesce(p_role,''));
begin
  if coalesce(p_is_super_admin,false) or r = 'admin' then
    return array['admin','staff.dashboard','finance','academic','schedule','sections','grades','attendance','behavior','counseling','users','reports','analytics','announcements','registrations','system','teacher','student','parent','homework','homework.reports','homework.audit','question_bank','online_exams','exam_integrity','library','inventory','assets','hr','transport','labs','activities','documents','notifications'];
  end if;
  if r='finance' then return array['staff.dashboard','finance','reports','analytics','homework.reports','library','inventory','assets','documents','notifications']; end if;
  if r in ('academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor') then return array['staff.dashboard','academic','schedule','sections','grades','attendance','behavior','reports','analytics','announcements','registrations','question_bank','online_exams','exam_integrity','homework.reports','library','transport','labs','activities','documents','notifications']; end if;
  if r='discipline' then return array['staff.dashboard','attendance','behavior','students','reports','analytics','transport','homework.reports','notifications']; end if;
  if r in ('counselor','psychologist') then return array['staff.dashboard','counseling','behavior','students','attendance','reports','analytics','notifications']; end if;
  if r='teacher' then return array['teacher','attendance','homework','homework.reports','homework.audit','grades','question_bank','online_exams','library','transport','labs','activities','documents','notifications']; end if;
  if r='student' then return array['student','homework','online_exams','grades','attendance','behavior','library','transport','activities','documents','notifications']; end if;
  if r='parent' then return array['parent','student','homework','online_exams','grades','attendance','behavior','finance','library','transport','activities','documents','notifications']; end if;
  if r='staff' then return array['staff.dashboard','attendance','students','reports','analytics','announcements','library','inventory','assets','transport','activities','documents','notifications']; end if;
  if r='hr' then return array['staff.dashboard','hr','reports','analytics','documents','notifications']; end if;
  if r in ('inventory','procurement') then return array['staff.dashboard','inventory','reports','analytics','documents','notifications']; end if;
  if r in ('transport','transport_manager') then return array['staff.dashboard','transport','reports','analytics','notifications']; end if;
  if r='librarian' then return array['library','reports','documents','notifications']; end if;
  return array['notifications'];
end;
$$;

grant execute on function public.portal_default_permissions(text,boolean) to authenticated;

create or replace function public.get_my_permissions()
returns text[]
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  u record;
  base text[];
  extra text[];
begin
  select * into u from public.users where id = auth.uid();
  if u.id is null then return array[]::text[]; end if;

  base := public.portal_default_permissions(u.role, coalesce(u.is_super_admin,false));

  select coalesce(array_agg(permission_key), array[]::text[])
  into extra
  from public.user_extra_permissions ep
  where ep.user_id = u.id
    and ep.is_active = true
    and (ep.expires_at is null or ep.expires_at > now());

  return array(select distinct unnest(coalesce(base,array[]::text[]) || coalesce(extra,array[]::text[])) order by 1);
end;
$$;

grant execute on function public.get_my_permissions() to authenticated;

-- -------------------------------------------------------------
-- إدارة الصلاحيات
-- -------------------------------------------------------------
alter table public.user_extra_permissions enable row level security;

drop policy if exists user_extra_permissions_admin_read_write on public.user_extra_permissions;
drop policy if exists user_extra_permissions_self_read on public.user_extra_permissions;

create policy user_extra_permissions_admin_read_write on public.user_extra_permissions
  for all to authenticated
  using (public.current_user_is_admin())
  with check (public.current_user_is_admin());

create policy user_extra_permissions_self_read on public.user_extra_permissions
  for select to authenticated
  using (user_id = auth.uid() and is_active = true and (expires_at is null or expires_at > now()));

grant select, insert, update on public.user_extra_permissions to authenticated;

create or replace function public.grant_user_permission(
  p_user_id uuid,
  p_permission text,
  p_expires_at timestamptz default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.current_user_is_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للمدير فقط');
  end if;

  if nullif(trim(coalesce(p_permission,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'مفتاح الصلاحية مطلوب');
  end if;

  insert into public.user_extra_permissions(user_id, permission_key, is_active, granted_by, expires_at, notes)
  values (p_user_id, trim(p_permission), true, auth.uid(), p_expires_at, p_notes)
  on conflict (user_id, permission_key) do update
  set is_active = true,
      granted_by = auth.uid(),
      granted_at = now(),
      expires_at = excluded.expires_at,
      notes = excluded.notes;

  return jsonb_build_object('ok', true, 'message', 'تم منح الصلاحية');
end;
$$;

grant execute on function public.grant_user_permission(uuid,text,timestamptz,text) to authenticated;

create or replace function public.revoke_user_permission(
  p_user_id uuid,
  p_permission text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.current_user_is_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للمدير فقط');
  end if;

  update public.user_extra_permissions
  set is_active = false
  where user_id = p_user_id
    and permission_key = p_permission;

  return jsonb_build_object('ok', true, 'message', 'تم إلغاء الصلاحية');
end;
$$;

grant execute on function public.revoke_user_permission(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- Catalog ثابت للصلاحيات في الواجهة
-- -------------------------------------------------------------
create or replace function public.portal_permissions_catalog()
returns jsonb
language sql
stable
as $$
  select jsonb_build_array(
    jsonb_build_object('key','admin','label','إدارة كاملة','group','إدارة'),
    jsonb_build_object('key','staff.dashboard','label','لوحة الإدارة التشغيلية','group','إدارة'),
    jsonb_build_object('key','finance','label','المالية','group','مالية'),
    jsonb_build_object('key','academic','label','الأكاديمي','group','أكاديمي'),
    jsonb_build_object('key','schedule','label','الجداول','group','أكاديمي'),
    jsonb_build_object('key','sections','label','الشعب والإسنادات','group','أكاديمي'),
    jsonb_build_object('key','grades','label','الدرجات','group','أكاديمي'),
    jsonb_build_object('key','attendance','label','الحضور','group','متابعة'),
    jsonb_build_object('key','behavior','label','السلوك والانضباط','group','متابعة'),
    jsonb_build_object('key','counseling','label','الإرشاد النفسي','group','متابعة'),
    jsonb_build_object('key','users','label','المستخدمون والصلاحيات','group','إدارة'),
    jsonb_build_object('key','reports','label','التقارير','group','تقارير'),
    jsonb_build_object('key','analytics','label','مركز التحليلات','group','تقارير'),
    jsonb_build_object('key','announcements','label','الإعلانات الجماعية','group','تواصل'),
    jsonb_build_object('key','registrations','label','مراجعة التسجيلات','group','تسجيل'),
    jsonb_build_object('key','system','label','صيانة النظام','group','إدارة'),
    jsonb_build_object('key','teacher','label','لوحة المعلم','group','تعليم'),
    jsonb_build_object('key','student','label','بوابة الطالب','group','تعليم'),
    jsonb_build_object('key','parent','label','ولي الأمر','group','تعليم'),
    jsonb_build_object('key','homework','label','الواجبات','group','تعليم'),
    jsonb_build_object('key','homework.reports','label','تقارير الواجبات','group','تعليم'),
    jsonb_build_object('key','homework.audit','label','سجل الواجبات','group','تعليم'),
    jsonb_build_object('key','question_bank','label','بنك الأسئلة','group','اختبارات'),
    jsonb_build_object('key','online_exams','label','الاختبارات الإلكترونية','group','اختبارات'),
    jsonb_build_object('key','exam_integrity','label','نزاهة الاختبارات','group','اختبارات'),
    jsonb_build_object('key','library','label','المكتبة','group','تشغيل'),
    jsonb_build_object('key','inventory','label','المخزون والمشتريات','group','تشغيل'),
    jsonb_build_object('key','assets','label','الأصول والعهد','group','تشغيل'),
    jsonb_build_object('key','hr','label','الموارد البشرية','group','تشغيل'),
    jsonb_build_object('key','transport','label','النقل المدرسي','group','تشغيل'),
    jsonb_build_object('key','labs','label','المختبرات','group','أنشطة'),
    jsonb_build_object('key','activities','label','الأنشطة','group','أنشطة'),
    jsonb_build_object('key','documents','label','الوثائق والأرشفة','group','إدارة'),
    jsonb_build_object('key','notifications','label','الإشعارات','group','تواصل')
  );
$$;

grant execute on function public.portal_permissions_catalog() to authenticated;

-- -------------------------------------------------------------
-- Payload للإدارة
-- -------------------------------------------------------------
create or replace function public.get_permissions_admin_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  users_json jsonb;
  perms_json jsonb;
begin
  if not public.current_user_is_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه الصفحة للمدير فقط');
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.name nulls last, x.email), '[]'::jsonb)
  into users_json
  from (
    select
      u.id,
      u.email,
      u.name,
      u.role,
      coalesce(u.is_super_admin,false) as is_super_admin,
      public.portal_default_permissions(u.role, coalesce(u.is_super_admin,false)) as base_permissions,
      coalesce(extra.extra_permissions, array[]::text[]) as extra_permissions,
      array(select distinct unnest(public.portal_default_permissions(u.role, coalesce(u.is_super_admin,false)) || coalesce(extra.extra_permissions, array[]::text[])) order by 1) as effective_permissions,
      coalesce(extra.extra_permissions_details,'[]'::jsonb) as extra_permissions_details
    from public.users u
    left join lateral (
      select
        array_agg(ep.permission_key order by ep.permission_key) filter (where ep.is_active=true and (ep.expires_at is null or ep.expires_at > now())) as extra_permissions,
        jsonb_agg(jsonb_build_object('permission_key', ep.permission_key, 'is_active', ep.is_active, 'granted_at', ep.granted_at, 'expires_at', ep.expires_at, 'notes', ep.notes) order by ep.permission_key) as extra_permissions_details
      from public.user_extra_permissions ep
      where ep.user_id = u.id
    ) extra on true
  ) x;

  perms_json := public.portal_permissions_catalog();

  return jsonb_build_object('ok', true, 'users', users_json, 'permissions_catalog', perms_json);
end;
$$;

grant execute on function public.get_permissions_admin_payload() to authenticated;

create or replace function public.permissions_management_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'extra_permissions_table', to_regclass('public.user_extra_permissions') is not null,
    'catalog_rpc', to_regprocedure('public.portal_permissions_catalog()') is not null,
    'payload_rpc', to_regprocedure('public.get_permissions_admin_payload()') is not null,
    'grant_rpc', to_regprocedure('public.grant_user_permission(uuid,text,timestamptz,text)') is not null,
    'revoke_rpc', to_regprocedure('public.revoke_user_permission(uuid,text)') is not null,
    'users_count', (select count(*) from public.users),
    'extra_permissions_active', (select count(*) from public.user_extra_permissions where is_active=true)
  );
end;
$$;

grant execute on function public.permissions_management_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'permissions_management_ui_ready' as status;

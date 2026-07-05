-- =============================================================
-- مدارس أمين الرضا (ع) — البوابة الموحدة والصلاحيات المفوضة
-- واجهة دخول واحدة، وبعدها كل مستخدم يرى ما فُوض إليه فقط.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) جدول صلاحيات إضافية اختيارية لكل مستخدم
-- -------------------------------------------------------------
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

-- -------------------------------------------------------------
-- 2) دوال الصلاحيات
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
      'admin','staff.dashboard','finance','academic','schedule','sections','grades','attendance','behavior','counseling','users','reports','registrations','system',
      'teacher','student','parent','homework','homework.reports','homework.audit','question_bank','online_exams','exam_integrity',
      'library','inventory','assets','hr','transport','labs','activities','notifications'
    ];
  end if;

  if r = 'finance' then
    return array['staff.dashboard','finance','reports','homework.reports','library','inventory','assets','notifications'];
  end if;

  if r in ('academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor') then
    return array['staff.dashboard','academic','schedule','sections','grades','attendance','behavior','reports','registrations','question_bank','online_exams','exam_integrity','homework.reports','library','transport','labs','activities','notifications'];
  end if;

  if r in ('discipline') then
    return array['staff.dashboard','attendance','behavior','students','reports','transport','homework.reports','notifications'];
  end if;

  if r in ('counselor','psychologist') then
    return array['staff.dashboard','counseling','behavior','students','attendance','reports','notifications'];
  end if;

  if r = 'teacher' then
    return array['teacher','attendance','homework','homework.reports','homework.audit','grades','question_bank','online_exams','library','transport','labs','activities','notifications'];
  end if;

  if r = 'student' then
    return array['student','homework','online_exams','grades','attendance','behavior','library','transport','activities','notifications'];
  end if;

  if r = 'parent' then
    return array['parent','student','homework','online_exams','grades','attendance','behavior','finance','library','transport','activities','notifications'];
  end if;

  if r in ('staff') then
    return array['staff.dashboard','attendance','students','reports','library','inventory','assets','transport','activities','notifications'];
  end if;

  if r in ('hr') then
    return array['staff.dashboard','hr','reports','notifications'];
  end if;

  if r in ('inventory','procurement') then
    return array['staff.dashboard','inventory','reports','notifications'];
  end if;

  if r in ('transport','transport_manager') then
    return array['staff.dashboard','transport','reports','notifications'];
  end if;

  if r in ('librarian') then
    return array['library','reports','notifications'];
  end if;

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
  if u.id is null then
    return array[]::text[];
  end if;

  base := public.portal_default_permissions(u.role, coalesce(u.is_super_admin,false));

  select coalesce(array_agg(permission_key), array[]::text[])
  into extra
  from public.user_extra_permissions ep
  where ep.user_id = u.id
    and ep.is_active = true
    and (ep.expires_at is null or ep.expires_at > now());

  return array(select distinct unnest(coalesce(base,array[]::text[]) || coalesce(extra,array[]::text[])));
end;
$$;

grant execute on function public.get_my_permissions() to authenticated;

create or replace function public.portal_has_permission(p_permission text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select p_permission = any(public.get_my_permissions()) or 'admin' = any(public.get_my_permissions());
$$;

grant execute on function public.portal_has_permission(text) to authenticated;

-- -------------------------------------------------------------
-- 3) إدارة صلاحية إضافية من المدير
-- -------------------------------------------------------------
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
-- 4) إشعارات المستخدم الخاصة به فقط
-- -------------------------------------------------------------
create table if not exists public.school_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid null references public.users(id) on delete cascade,
  recipient_role text,
  title text not null,
  body text,
  notification_type text not null default 'info',
  entity_table text,
  entity_id uuid,
  read_at timestamptz,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now()
);

alter table public.school_notifications enable row level security;

drop policy if exists school_notifications_select_own_admin on public.school_notifications;
drop policy if exists school_notifications_update_own_admin on public.school_notifications;
drop policy if exists school_notifications_insert_admin_teacher on public.school_notifications;

create policy school_notifications_select_own_admin on public.school_notifications
  for select to authenticated
  using (public.current_user_is_admin() or recipient_user_id = auth.uid() or created_by = auth.uid());

create policy school_notifications_update_own_admin on public.school_notifications
  for update to authenticated
  using (public.current_user_is_admin() or recipient_user_id = auth.uid() or created_by = auth.uid())
  with check (public.current_user_is_admin() or recipient_user_id = auth.uid() or created_by = auth.uid());

create policy school_notifications_insert_admin_teacher on public.school_notifications
  for insert to authenticated
  with check (public.current_user_is_admin() or created_by = auth.uid() or created_by is null);

grant select, insert, update on public.school_notifications to authenticated;

drop view if exists public.v_my_notifications;
create view public.v_my_notifications
with (security_invoker=true) as
select
  n.id,
  n.recipient_user_id,
  n.recipient_role,
  n.title,
  n.body,
  n.notification_type,
  n.entity_table,
  n.entity_id,
  n.read_at,
  n.created_by,
  u.name as created_by_name,
  n.created_at,
  case when n.read_at is null then true else false end as is_unread
from public.school_notifications n
left join public.users u on u.id = n.created_by
where public.current_user_is_admin()
   or n.recipient_user_id = auth.uid()
   or n.created_by = auth.uid();

grant select on public.v_my_notifications to authenticated;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.school_notifications
  set read_at = coalesce(read_at, now())
  where id = p_notification_id
    and (recipient_user_id = auth.uid() or created_by = auth.uid() or public.current_user_is_admin());

  if not found then
    return jsonb_build_object('ok', false, 'message', 'لا توجد صلاحية أو الإشعار غير موجود');
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم تعليم الإشعار كمقروء');
end;
$$;

grant execute on function public.mark_notification_read(uuid) to authenticated;

-- -------------------------------------------------------------
-- 5) Payload البوابة الموحدة
-- -------------------------------------------------------------
create or replace function public.get_my_portal_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  u record;
  perms text[];
  notifs jsonb;
  unread int := 0;
begin
  select id, email, name, role, is_super_admin
  into u
  from public.users
  where id = auth.uid();

  if u.id is null then
    return jsonb_build_object('ok', false, 'message', 'لم يتم العثور على ملف المستخدم');
  end if;

  perms := public.get_my_permissions();

  select count(*) into unread
  from public.school_notifications n
  where n.recipient_user_id = u.id
    and n.read_at is null;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into notifs
  from (
    select *
    from public.v_my_notifications
    order by created_at desc
    limit 20
  ) x;

  return jsonb_build_object(
    'ok', true,
    'profile', jsonb_build_object(
      'id', u.id,
      'email', u.email,
      'name', u.name,
      'role', u.role,
      'is_super_admin', coalesce(u.is_super_admin,false)
    ),
    'permissions', perms,
    'notifications', coalesce(notifs,'[]'::jsonb),
    'unread_notifications', unread
  );
end;
$$;

grant execute on function public.get_my_portal_payload() to authenticated;

-- -------------------------------------------------------------
-- 6) Health
-- -------------------------------------------------------------
create or replace function public.unified_portal_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'extra_permissions_table', to_regclass('public.user_extra_permissions') is not null,
    'portal_payload_rpc', to_regprocedure('public.get_my_portal_payload()') is not null,
    'permissions_rpc', to_regprocedure('public.get_my_permissions()') is not null,
    'has_permission_rpc', to_regprocedure('public.portal_has_permission(text)') is not null,
    'notifications_view', to_regclass('public.v_my_notifications') is not null,
    'notifications_table', to_regclass('public.school_notifications') is not null
  );
end;
$$;

grant execute on function public.unified_portal_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'unified_portal_permissions_ready' as status;

-- =============================================================
-- مدارس أمين الرضا (ع) — مركز التقارير والتحليلات + الإعلانات الجماعية
-- لوحة مؤسسية واحدة، مؤشرات ذكية محلية، وإرسال إعلانات كإشعارات.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) Helpers آمنة للعدّ والجمع حتى لو لم تُشغل بعض الوحدات بعد
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

create or replace function public._safe_numeric_sum(p_table text, p_col text, p_where text default null)
returns numeric
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v numeric := 0;
  sql text;
begin
  if to_regclass('public.' || p_table) is null then
    return 0;
  end if;
  sql := format('select coalesce(sum(%I)::numeric,0) from public.%I', p_col, p_table);
  if p_where is not null and trim(p_where) <> '' then
    sql := sql || ' where ' || p_where;
  end if;
  execute sql into v;
  return coalesce(v,0);
exception when others then
  return 0;
end;
$$;

grant execute on function public._safe_numeric_sum(text,text,text) to authenticated;

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

create or replace function public.announcements_can_manage()
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
        and u.role in ('staff','academic','academic_admin','scientific','supervisor','discipline','counselor','psychologist')
    );
$$;

grant execute on function public.announcements_can_manage() to authenticated;

-- -------------------------------------------------------------
-- 1) الإعلانات الجماعية
-- -------------------------------------------------------------
create table if not exists public.school_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text,
  target_roles text[] null,
  target_user_ids uuid[] null,
  status text not null default 'published' check (status in ('draft','published','archived','cancelled')),
  publish_at timestamptz not null default now(),
  expires_at timestamptz,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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

create index if not exists idx_school_announcements_status on public.school_announcements(status, publish_at desc);
create index if not exists idx_school_notifications_recipient on public.school_notifications(recipient_user_id, read_at, created_at desc);

alter table public.school_announcements enable row level security;
alter table public.school_notifications enable row level security;

drop policy if exists school_announcements_read on public.school_announcements;
drop policy if exists school_announcements_manage on public.school_announcements;

create policy school_announcements_read on public.school_announcements
  for select to authenticated
  using (
    public.announcements_can_manage()
    or (
      status = 'published'
      and publish_at <= now()
      and (expires_at is null or expires_at > now())
      and (
        target_roles is null
        or exists(select 1 from public.users u where u.id = auth.uid() and u.role = any(target_roles))
        or auth.uid() = any(coalesce(target_user_ids, array[]::uuid[]))
      )
    )
  );

create policy school_announcements_manage on public.school_announcements
  for all to authenticated
  using (public.announcements_can_manage())
  with check (public.announcements_can_manage());

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

grant select, insert, update on public.school_announcements to authenticated;
grant select, insert, update on public.school_notifications to authenticated;

create or replace view public.v_school_announcements_detailed
with (security_invoker=true) as
select
  a.id,
  a.title,
  a.body,
  a.target_roles,
  a.target_user_ids,
  a.status,
  a.publish_at,
  a.expires_at,
  a.created_by,
  u.name as created_by_name,
  a.created_at,
  a.updated_at,
  case when a.publish_at <= now() and (a.expires_at is null or a.expires_at > now()) and a.status='published' then true else false end as is_live
from public.school_announcements a
left join public.users u on u.id = a.created_by;

grant select on public.v_school_announcements_detailed to authenticated;

create or replace function public.broadcast_school_announcement(
  p_title text,
  p_body text default null,
  p_target_roles text[] default null,
  p_target_user_ids uuid[] default null,
  p_send_notifications boolean default true,
  p_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  ann_id uuid;
  inserted_count int := 0;
begin
  if not public.announcements_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إرسال إعلان');
  end if;

  if nullif(trim(coalesce(p_title,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'عنوان الإعلان مطلوب');
  end if;

  insert into public.school_announcements(title, body, target_roles, target_user_ids, status, publish_at, expires_at, created_by)
  values (trim(p_title), p_body, p_target_roles, p_target_user_ids, 'published', now(), p_expires_at, auth.uid())
  returning id into ann_id;

  if coalesce(p_send_notifications,true) then
    insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
    select u.id, u.role, trim(p_title), p_body, 'announcement', 'school_announcements', ann_id, auth.uid()
    from public.users u
    where (
      p_target_roles is null
      or u.role = any(p_target_roles)
    )
    and (
      p_target_user_ids is null
      or u.id = any(p_target_user_ids)
      or p_target_roles is not null
    );
    get diagnostics inserted_count = row_count;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم نشر الإعلان', 'announcement_id', ann_id, 'notifications', inserted_count);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.broadcast_school_announcement(text,text,text[],uuid[],boolean,timestamptz) to authenticated;

-- -------------------------------------------------------------
-- 2) لوحة التحليلات المؤسسية
-- -------------------------------------------------------------
create or replace function public.get_enterprise_dashboard_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  stats jsonb;
  insights jsonb := '[]'::jsonb;
begin
  if not (
    public.current_user_is_admin()
    or exists(select 1 from public.users u where u.id=auth.uid() and u.role in ('staff','finance','academic','academic_admin','scientific','supervisor','discipline','counselor','psychologist'))
    or auth.uid() is null
  ) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية عرض لوحة المؤسسة');
  end if;

  stats := jsonb_build_object(
    'students', public._safe_table_count('students', null),
    'users', public._safe_table_count('users', null),
    'teachers', public._safe_table_count('users', 'role = ''teacher'''),
    'parents', public._safe_table_count('users', 'role = ''parent'''),
    'attendance_today', public._safe_table_count('attendance', 'date = current_date'),
    'absences_today', public._safe_table_count('attendance', 'date = current_date and status = ''absent'''),
    'homeworks_published', public._safe_table_count('homeworks', 'status = ''published'''),
    'homework_submissions', public._safe_table_count('homework_submissions', null),
    'online_exams_published', public._safe_table_count('online_exams', 'status = ''published'''),
    'exam_attempts', public._safe_table_count('exam_attempts', null),
    'library_items', public._safe_table_count('library_items', 'is_active = true'),
    'library_active_loans', public._safe_table_count('library_loans', 'status = ''active'''),
    'inventory_items', public._safe_table_count('inventory_items', 'is_active = true'),
    'inventory_low_stock', public._safe_table_count('inventory_items', 'is_active = true and current_stock <= min_stock'),
    'assets_total', public._safe_table_count('fixed_assets', null),
    'assets_maintenance', public._safe_table_count('fixed_assets', 'status = ''maintenance'''),
    'hr_employees', public._safe_table_count('hr_employee_profiles', null),
    'hr_pending_leaves', public._safe_table_count('hr_leave_requests', 'status = ''pending'''),
    'transport_routes', public._safe_table_count('transport_routes', 'status = ''active'''),
    'transport_students', public._safe_table_count('transport_student_assignments', 'subscription_status = ''active'''),
    'documents', public._safe_table_count('document_records', 'status = ''active'''),
    'lab_incidents_open', public._safe_table_count('lab_incidents', 'status in (''open'',''reviewing'')'),
    'activities_published', public._safe_table_count('school_activities', 'status = ''published'''),
    'fees_total', public._safe_numeric_sum('student_fees', 'net_amount', null),
    'fees_paid', public._safe_numeric_sum('student_fees', 'total_paid', null)
  );

  insights := insights
    || case when (stats->>'inventory_low_stock')::int > 0 then jsonb_build_array(jsonb_build_object('level','warning','title','نواقص في المخزون','body','يوجد '||(stats->>'inventory_low_stock')||' صنف وصل إلى الحد الأدنى أو نفد.')) else '[]'::jsonb end
    || case when (stats->>'hr_pending_leaves')::int > 0 then jsonb_build_array(jsonb_build_object('level','info','title','إجازات بانتظار القرار','body','يوجد '||(stats->>'hr_pending_leaves')||' طلب إجازة معلق.')) else '[]'::jsonb end
    || case when (stats->>'lab_incidents_open')::int > 0 then jsonb_build_array(jsonb_build_object('level','danger','title','حوادث مختبر مفتوحة','body','يوجد '||(stats->>'lab_incidents_open')||' حادث/ملاحظة سلامة تحتاج متابعة.')) else '[]'::jsonb end
    || case when (stats->>'assets_maintenance')::int > 0 then jsonb_build_array(jsonb_build_object('level','warning','title','أصول تحت الصيانة','body','يوجد '||(stats->>'assets_maintenance')||' أصل تحت الصيانة.')) else '[]'::jsonb end;

  return jsonb_build_object('ok', true, 'stats', stats, 'insights', insights, 'checked_at', now());
end;
$$;

grant execute on function public.get_enterprise_dashboard_payload() to authenticated;

create or replace function public.enterprise_analytics_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'announcements_table', to_regclass('public.school_announcements') is not null,
    'announcements_view', to_regclass('public.v_school_announcements_detailed') is not null,
    'broadcast_rpc', to_regprocedure('public.broadcast_school_announcement(text,text,text[],uuid[],boolean,timestamptz)') is not null,
    'dashboard_rpc', to_regprocedure('public.get_enterprise_dashboard_payload()') is not null,
    'sample_stats', public.get_enterprise_dashboard_payload()->'stats'
  );
end;
$$;

grant execute on function public.enterprise_analytics_health_check() to authenticated;

-- -------------------------------------------------------------
-- إضافة صلاحيات analytics/announcements للبوابة إن كانت موجودة
-- -------------------------------------------------------------
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

notify pgrst, 'reload schema';

select 'enterprise_analytics_announcements_ready' as status;

-- =============================================================
-- مدارس أمين الرضا (ع) — إصلاح ظهور الإشعارات 404 + توليد إشعارات الواجبات السابقة
-- يحل: /rest/v1/v_my_notifications يرجع 404 لأن الـ View غير موجودة في schema cache.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) جدول الإشعارات إن لم يكن موجوداً
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

create index if not exists idx_school_notifications_recipient on public.school_notifications(recipient_user_id, read_at, created_at desc);
create index if not exists idx_school_notifications_entity on public.school_notifications(entity_table, entity_id);

alter table public.school_notifications enable row level security;

-- أعد إنشاء سياسات الإشعارات بأسماء ثابتة حتى لا تبقى سياسة ناقصة.
drop policy if exists school_notifications_select_own_admin on public.school_notifications;
drop policy if exists school_notifications_update_own_admin on public.school_notifications;
drop policy if exists school_notifications_insert_admin_teacher on public.school_notifications;
drop policy if exists school_notifications_own_or_admin on public.school_notifications;

create policy school_notifications_select_own_admin on public.school_notifications
  for select to authenticated
  using (
    public.current_user_is_admin()
    or recipient_user_id = auth.uid()
    or created_by = auth.uid()
  );

create policy school_notifications_update_own_admin on public.school_notifications
  for update to authenticated
  using (
    public.current_user_is_admin()
    or recipient_user_id = auth.uid()
    or created_by = auth.uid()
  )
  with check (
    public.current_user_is_admin()
    or recipient_user_id = auth.uid()
    or created_by = auth.uid()
  );

create policy school_notifications_insert_admin_teacher on public.school_notifications
  for insert to authenticated
  with check (
    public.current_user_is_admin()
    or created_by = auth.uid()
    or created_by is null
  );

grant select, insert, update on public.school_notifications to authenticated;

-- -------------------------------------------------------------
-- 2) View الإشعارات — سبب 404 هو غالباً عدم وجود هذا الـ View أو عدم تحديث schema cache
-- -------------------------------------------------------------
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

-- -------------------------------------------------------------
-- 3) دوال تعليم الإشعارات كمقروءة
-- -------------------------------------------------------------
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
    and (
      recipient_user_id = auth.uid()
      or created_by = auth.uid()
      or public.current_user_is_admin()
    );

  if not found then
    return jsonb_build_object('ok', false, 'message', 'لم يتم العثور على الإشعار أو لا توجد صلاحية');
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم تعليم الإشعار كمقروء');
end;
$$;

grant execute on function public.mark_notification_read(uuid) to authenticated;

create or replace function public.mark_all_notifications_read()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
begin
  update public.school_notifications
  set read_at = coalesce(read_at, now())
  where read_at is null
    and recipient_user_id = auth.uid();

  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'message', 'تم تعليم كل الإشعارات كمقروءة', 'count', v_count);
end;
$$;

grant execute on function public.mark_all_notifications_read() to authenticated;

-- -------------------------------------------------------------
-- 4) دالة إرسال إشعارات واجب، مع منع التكرار لنفس الطالب/ولي الأمر والواجب والنوع
-- -------------------------------------------------------------
create or replace function public.notify_homework_recipients(
  p_homework_id uuid,
  p_event text default 'published'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  title_text text;
  body_text text;
  inserted_students int := 0;
  inserted_parents int := 0;
begin
  select * into h from public.homeworks where id = p_homework_id;

  if h.id is null then
    return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود');
  end if;

  title_text := case p_event
    when 'published' then 'واجب جديد منشور'
    when 'updated' then 'تم تعديل واجب'
    when 'closed' then 'تم إغلاق واجب'
    else 'تنبيه واجب'
  end;

  body_text := coalesce(h.title,'واجب') || case when h.due_date is not null then ' — التسليم: ' || h.due_date::text else '' end;

  -- الطلاب
  insert into public.school_notifications(
    recipient_user_id,
    recipient_role,
    title,
    body,
    notification_type,
    entity_table,
    entity_id,
    created_by
  )
  select distinct
    s.user_id,
    'student',
    title_text,
    body_text,
    'homework_' || p_event,
    'homeworks',
    h.id,
    coalesce(auth.uid(), h.teacher_id)
  from public.students s
  left join public.student_enrollments se
    on se.student_id = s.id
   and se.enrollment_status = 'active'
  where s.user_id is not null
    and (
      (h.section_id is not null and (s.section_id = h.section_id or se.section_id = h.section_id))
      or
      (h.section_id is null and h.class_id is not null and (s.class_id = h.class_id or se.class_id = h.class_id))
    )
    and not exists(
      select 1 from public.school_notifications n
      where n.recipient_user_id = s.user_id
        and n.entity_table = 'homeworks'
        and n.entity_id = h.id
        and n.notification_type = 'homework_' || p_event
    );

  get diagnostics inserted_students = row_count;

  -- أولياء الأمور
  insert into public.school_notifications(
    recipient_user_id,
    recipient_role,
    title,
    body,
    notification_type,
    entity_table,
    entity_id,
    created_by
  )
  select distinct
    s.parent_id,
    'parent',
    title_text,
    body_text,
    'homework_' || p_event,
    'homeworks',
    h.id,
    coalesce(auth.uid(), h.teacher_id)
  from public.students s
  left join public.student_enrollments se
    on se.student_id = s.id
   and se.enrollment_status = 'active'
  where s.parent_id is not null
    and (
      (h.section_id is not null and (s.section_id = h.section_id or se.section_id = h.section_id))
      or
      (h.section_id is null and h.class_id is not null and (s.class_id = h.class_id or se.class_id = h.class_id))
    )
    and not exists(
      select 1 from public.school_notifications n
      where n.recipient_user_id = s.parent_id
        and n.entity_table = 'homeworks'
        and n.entity_id = h.id
        and n.notification_type = 'homework_' || p_event
    );

  get diagnostics inserted_parents = row_count;

  return jsonb_build_object(
    'ok', true,
    'message', 'تم إنشاء الإشعارات',
    'students', inserted_students,
    'parents', inserted_parents,
    'count', inserted_students + inserted_parents
  );
end;
$$;

grant execute on function public.notify_homework_recipients(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 5) توليد إشعارات للواجبات المنشورة الموجودة سابقاً
-- -------------------------------------------------------------
create or replace function public.backfill_homework_notifications()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  r jsonb;
  total int := 0;
  processed int := 0;
begin
  for h in
    select * from public.homeworks
    where status = 'published'
  loop
    r := public.notify_homework_recipients(h.id, 'published');
    total := total + coalesce((r->>'count')::int, 0);
    processed := processed + 1;
  end loop;

  return jsonb_build_object('ok', true, 'processed_homeworks', processed, 'inserted_notifications', total);
end;
$$;

grant execute on function public.backfill_homework_notifications() to authenticated;

-- نفذ backfill مرة واحدة الآن حتى تظهر الإشعارات الحالية مباشرة.
select public.backfill_homework_notifications();

-- -------------------------------------------------------------
-- 6) فحص صحة الإشعارات
-- -------------------------------------------------------------
create or replace function public.notifications_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'table_exists', to_regclass('public.school_notifications') is not null,
    'view_exists', to_regclass('public.v_my_notifications') is not null,
    'notifications_count', (select count(*) from public.school_notifications),
    'unread_count', (select count(*) from public.school_notifications where read_at is null),
    'homework_notifications_count', (select count(*) from public.school_notifications where entity_table='homeworks'),
    'published_homeworks', (select count(*) from public.homeworks where status='published'),
    'sample', coalesce((select jsonb_agg(jsonb_build_object('title', title, 'role', recipient_role, 'created_at', created_at) order by created_at desc) from (select * from public.school_notifications order by created_at desc limit 5) x), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.notifications_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'notifications_view_and_backfill_fix_ready' as status;

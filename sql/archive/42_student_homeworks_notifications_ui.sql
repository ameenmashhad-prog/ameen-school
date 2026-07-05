-- =============================================================
-- مدارس أمين الرضا (ع) — واجبات الطالب ومركز الإشعارات
-- يعرض الواجبات المنشورة للطلاب/الأهل، ويضيف تعليم/قراءة الإشعارات.
-- =============================================================

create extension if not exists pgcrypto;

-- تأكد من الجداول الأساسية حتى لو لم يشغل المستخدم SQL 39 سابقاً.
alter table public.homeworks add column if not exists section_id uuid null references public.sections(id) on delete set null;
alter table public.homeworks add column if not exists publish_at timestamptz;
alter table public.homeworks add column if not exists due_time time;
alter table public.homeworks add column if not exists max_score numeric not null default 10;
alter table public.homeworks add column if not exists updated_at timestamptz not null default now();

create table if not exists public.homework_attachments (
  id uuid primary key default gen_random_uuid(),
  homework_id uuid not null references public.homeworks(id) on delete cascade,
  file_name text not null,
  file_type text,
  file_size bigint,
  storage_path text not null,
  public_url text,
  sort_order int not null default 0,
  uploaded_by uuid null references public.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.homework_grades (
  id uuid primary key default gen_random_uuid(),
  homework_id uuid not null references public.homeworks(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  score numeric not null,
  max_score numeric not null default 10,
  feedback text,
  graded_by uuid null references public.users(id),
  graded_at timestamptz not null default now(),
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

create index if not exists idx_school_notifications_recipient on public.school_notifications(recipient_user_id, read_at, created_at desc);
create index if not exists idx_homework_attachments_homework on public.homework_attachments(homework_id, sort_order);
create index if not exists idx_homework_grades_student on public.homework_grades(student_id, homework_id);

-- -------------------------------------------------------------
-- دوال صلاحيات الواجبات، لتجنب أي لبس في سياسات RLS.
-- -------------------------------------------------------------
create or replace function public.can_read_homework(p_homework_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  h record;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return false; end if;
  if public.current_user_is_admin() or h.teacher_id = auth.uid() then return true; end if;
  if h.status not in ('published','closed') then return false; end if;
  return exists(
    select 1
    from public.students s
    where (s.user_id = auth.uid() or s.parent_id = auth.uid())
      and (
        (h.section_id is not null and (s.section_id = h.section_id or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.section_id=h.section_id and se.enrollment_status='active')))
        or
        (h.section_id is null and h.class_id is not null and (s.class_id = h.class_id or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.class_id=h.class_id and se.enrollment_status='active')))
      )
  );
end;
$$;

grant execute on function public.can_read_homework(uuid) to authenticated;

create or replace function public.can_write_homework(p_homework_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  h record;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return false; end if;
  return public.current_user_is_admin() or h.teacher_id = auth.uid();
end;
$$;

grant execute on function public.can_write_homework(uuid) to authenticated;

-- -------------------------------------------------------------
-- RLS للواجبات والمرفقات والإشعارات بشكل متوافق
-- -------------------------------------------------------------
alter table public.homeworks enable row level security;
alter table public.homework_attachments enable row level security;
alter table public.homework_grades enable row level security;
alter table public.school_notifications enable row level security;

-- أعد إنشاء سياساتنا حتى لا تبقى نسخة قديمة غير دقيقة.
drop policy if exists homeworks_teacher_admin_student_parent_read on public.homeworks;
drop policy if exists homeworks_teacher_admin_write on public.homeworks;
drop policy if exists homework_attachments_read_scoped on public.homework_attachments;
drop policy if exists homework_attachments_teacher_write_scoped on public.homework_attachments;
drop policy if exists homework_grades_read_scoped on public.homework_grades;
drop policy if exists homework_grades_teacher_write_scoped on public.homework_grades;
drop policy if exists school_notifications_select_own_admin on public.school_notifications;
drop policy if exists school_notifications_update_own_admin on public.school_notifications;
drop policy if exists school_notifications_insert_admin_teacher on public.school_notifications;

create policy homeworks_teacher_admin_student_parent_read on public.homeworks
  for select to authenticated
  using (public.can_read_homework(id));

create policy homeworks_teacher_admin_write on public.homeworks
  for all to authenticated
  using (public.current_user_is_admin() or teacher_id = auth.uid())
  with check (public.current_user_is_admin() or teacher_id = auth.uid());

create policy homework_attachments_read_scoped on public.homework_attachments
  for select to authenticated
  using (public.can_read_homework(homework_id));

create policy homework_attachments_teacher_write_scoped on public.homework_attachments
  for all to authenticated
  using (public.can_write_homework(homework_id))
  with check (public.can_write_homework(homework_id));

create policy homework_grades_read_scoped on public.homework_grades
  for select to authenticated
  using (
    public.current_user_is_admin()
    or exists(select 1 from public.homeworks h where h.id=homework_id and h.teacher_id=auth.uid())
    or exists(select 1 from public.students s where s.id=student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid()))
  );

create policy homework_grades_teacher_write_scoped on public.homework_grades
  for all to authenticated
  using (public.can_write_homework(homework_id))
  with check (public.can_write_homework(homework_id));

create policy school_notifications_select_own_admin on public.school_notifications
  for select to authenticated
  using (public.current_user_is_admin() or recipient_user_id = auth.uid() or created_by = auth.uid());

create policy school_notifications_update_own_admin on public.school_notifications
  for update to authenticated
  using (public.current_user_is_admin() or recipient_user_id = auth.uid() or created_by = auth.uid())
  with check (public.current_user_is_admin() or recipient_user_id = auth.uid() or created_by = auth.uid());

create policy school_notifications_insert_admin_teacher on public.school_notifications
  for insert to authenticated
  with check (public.current_user_is_admin() or created_by = auth.uid());

-- -------------------------------------------------------------
-- Views للواجهة
-- -------------------------------------------------------------
create or replace view public.v_my_notifications
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

create or replace view public.v_student_homeworks
with (security_invoker=true) as
select
  h.id as homework_id,
  h.title,
  h.description,
  h.status,
  h.publish_at,
  h.assigned_date,
  h.due_date,
  h.due_time,
  h.max_score,
  h.class_id,
  c.name as class_name,
  h.section_id,
  sec.code as section_code,
  h.subject_id,
  sub.name as subject_name,
  h.teacher_id,
  u.name as teacher_name,
  s.id as student_id,
  s.name as student_name,
  hg.score as grade_score,
  hg.max_score as grade_max_score,
  hg.feedback as grade_feedback,
  hg.graded_at,
  coalesce(att.attachment_count,0) as attachment_count,
  h.created_at,
  h.updated_at
from public.homeworks h
join public.students s
  on (s.user_id = auth.uid() or s.parent_id = auth.uid())
 and (
   (h.section_id is not null and (s.section_id = h.section_id or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.section_id=h.section_id and se.enrollment_status='active')))
   or
   (h.section_id is null and h.class_id is not null and (s.class_id = h.class_id or exists(select 1 from public.student_enrollments se where se.student_id=s.id and se.class_id=h.class_id and se.enrollment_status='active')))
 )
left join public.classes c on c.id = h.class_id
left join public.sections sec on sec.id = h.section_id
left join public.subjects sub on sub.id = h.subject_id
left join public.users u on u.id = h.teacher_id
left join public.homework_grades hg on hg.homework_id = h.id and hg.student_id = s.id
left join lateral (
  select count(*) as attachment_count from public.homework_attachments ha where ha.homework_id = h.id
) att on true
where h.public.homeworks.status in ('published','closed')
  and (h.publish_at is null or h.publish_at <= now());

grant select on public.v_student_homeworks to authenticated;

-- -------------------------------------------------------------
-- RPC تعليم الإشعارات كمقروءة
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
    and (recipient_user_id = auth.uid() or created_by = auth.uid() or public.current_user_is_admin());

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

notify pgrst, 'reload schema';

select 'student_homeworks_notifications_ui_ready' as status;

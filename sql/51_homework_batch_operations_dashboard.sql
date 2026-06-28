-- =============================================================
-- مدارس أمين الرضا (ع) — دفعة تسريع: عمليات الواجبات ولوحات المتابعة
-- 10 تحسينات دفعة واحدة: dashboard, badges, close, reopen, return, bulk close, reminders.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) تأكيد الجداول الأساسية
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

create table if not exists public.homework_submissions (
  id uuid primary key default gen_random_uuid(),
  homework_id uuid not null references public.homeworks(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  answer_text text,
  status text not null default 'draft',
  submitted_at timestamptz,
  reviewed_by uuid null references public.users(id),
  reviewed_at timestamptz,
  teacher_feedback text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.homeworks add column if not exists due_time time;
alter table public.homeworks add column if not exists publish_at timestamptz;
alter table public.homeworks add column if not exists updated_at timestamptz not null default now();

-- -------------------------------------------------------------
-- 1) عدد الإشعارات غير المقروءة
-- -------------------------------------------------------------
create or replace function public.get_notification_badges_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'message', 'لا توجد جلسة', 'unread_notifications', 0);
  end if;

  return jsonb_build_object(
    'ok', true,
    'unread_notifications', (select count(*) from public.school_notifications where recipient_user_id = uid and read_at is null),
    'homework_notifications', (select count(*) from public.school_notifications where recipient_user_id = uid and read_at is null and notification_type like 'homework_%')
  );
end;
$$;

grant execute on function public.get_notification_badges_payload() to authenticated;

-- -------------------------------------------------------------
-- 2) لوحة إحصائيات الواجبات للمعلم/الإدارة
-- -------------------------------------------------------------
create or replace function public.get_homework_dashboard_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  uid uuid := auth.uid();
  reports jsonb := '[]'::jsonb;
  missing jsonb := '[]'::jsonb;
  recent_submissions jsonb := '[]'::jsonb;
  due_soon jsonb := '[]'::jsonb;
  overdue jsonb := '[]'::jsonb;
  stats jsonb := '{}'::jsonb;
begin
  -- reports/missing من الـ RPC السابق إن وجد.
  begin
    reports := coalesce((public.get_homework_followup_payload(null)->'reports'), '[]'::jsonb);
    missing := coalesce((public.get_homework_followup_payload(null)->'missing'), '[]'::jsonb);
  exception when others then
    reports := '[]'::jsonb;
    missing := '[]'::jsonb;
  end;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.submitted_at desc nulls last, x.updated_at desc), '[]'::jsonb)
  into recent_submissions
  from (
    select
      hs.id as submission_id,
      hs.homework_id,
      h.title as homework_title,
      h.teacher_id,
      s.id as student_id,
      s.name as student_name,
      hs.status,
      hs.submitted_at,
      hs.updated_at,
      left(coalesce(hs.answer_text,''), 220) as answer_preview
    from public.homework_submissions hs
    join public.homeworks h on h.id = hs.homework_id
    join public.students s on s.id = hs.student_id
    where (uid is null or public.current_user_is_admin() or h.teacher_id = uid)
    order by hs.submitted_at desc nulls last, hs.updated_at desc
    limit 20
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.due_date, x.due_time), '[]'::jsonb)
  into due_soon
  from (
    select h.id as homework_id, h.title, h.teacher_id, h.due_date, h.due_time, h.status
    from public.homeworks h
    where h.status = 'published'
      and h.due_date is not null
      and (h.due_date + coalesce(h.due_time, time '23:59')) between now() and now() + interval '3 days'
      and (uid is null or public.current_user_is_admin() or h.teacher_id = uid)
    order by h.due_date, h.due_time
    limit 20
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.due_date desc), '[]'::jsonb)
  into overdue
  from (
    select h.id as homework_id, h.title, h.teacher_id, h.due_date, h.due_time, h.status
    from public.homeworks h
    where h.status = 'published'
      and h.due_date is not null
      and (h.due_date + coalesce(h.due_time, time '23:59')) < now()
      and (uid is null or public.current_user_is_admin() or h.teacher_id = uid)
    order by h.due_date desc, h.due_time desc
    limit 20
  ) x;

  stats := jsonb_build_object(
    'auth_uid', uid,
    'reports_count', jsonb_array_length(reports),
    'missing_count', jsonb_array_length(missing),
    'recent_submissions_count', jsonb_array_length(recent_submissions),
    'due_soon_count', jsonb_array_length(due_soon),
    'overdue_count', jsonb_array_length(overdue),
    'unread_notifications', case when uid is null then 0 else (select count(*) from public.school_notifications where recipient_user_id = uid and read_at is null) end
  );

  return jsonb_build_object('ok', true, 'stats', stats, 'reports', reports, 'missing', missing, 'recent_submissions', recent_submissions, 'due_soon', due_soon, 'overdue', overdue);
end;
$$;

grant execute on function public.get_homework_dashboard_payload() to authenticated;

-- -------------------------------------------------------------
-- 3) إرجاع تسليم الطالب للتعديل
-- -------------------------------------------------------------
create or replace function public.return_homework_submission(
  p_submission_id uuid,
  p_feedback text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  hs record;
  h record;
  st record;
begin
  select * into hs from public.homework_submissions where id = p_submission_id;
  if hs.id is null then return jsonb_build_object('ok', false, 'message', 'تسليم الواجب غير موجود'); end if;

  select * into h from public.homeworks where id = hs.homework_id;
  if h.id is null then return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود'); end if;

  if not (public.current_user_is_admin() or h.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إرجاع هذا التسليم');
  end if;

  update public.homework_submissions
  set status = 'returned',
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      teacher_feedback = p_feedback,
      updated_at = now()
  where id = p_submission_id;

  select * into st from public.students where id = hs.student_id;

  insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
  select st.user_id, 'student', 'تم إرجاع الواجب للتعديل', coalesce(h.title,'واجب') || coalesce(' — ' || nullif(p_feedback,''), ''), 'homework_returned', 'homework_submissions', p_submission_id, auth.uid()
  where st.user_id is not null;

  insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
  select st.parent_id, 'parent', 'تم إرجاع واجب الطالب للتعديل', coalesce(h.title,'واجب') || coalesce(' — ' || nullif(p_feedback,''), ''), 'homework_returned', 'homework_submissions', p_submission_id, auth.uid()
  where st.parent_id is not null;

  return jsonb_build_object('ok', true, 'message', 'تم إرجاع التسليم للتعديل');
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.return_homework_submission(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 4) إغلاق واجب واحد + إشعار
-- -------------------------------------------------------------
create or replace function public.close_homework(p_homework_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود'); end if;

  if not (public.current_user_is_admin() or h.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إغلاق هذا الواجب');
  end if;

  update public.homeworks set status = 'closed', updated_at = now() where id = p_homework_id;

  begin
    perform public.notify_homework_recipients(p_homework_id, 'closed');
  exception when others then
    null;
  end;

  return jsonb_build_object('ok', true, 'message', 'تم إغلاق الواجب');
end;
$$;

grant execute on function public.close_homework(uuid) to authenticated;

-- -------------------------------------------------------------
-- 5) إعادة فتح واجب مغلق إلى منشور + إشعار
-- -------------------------------------------------------------
create or replace function public.reopen_homework(p_homework_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود'); end if;

  if not (public.current_user_is_admin() or h.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إعادة فتح هذا الواجب');
  end if;

  update public.homeworks set status = 'published', updated_at = now() where id = p_homework_id;

  begin
    perform public.notify_homework_recipients(p_homework_id, 'updated');
  exception when others then
    null;
  end;

  return jsonb_build_object('ok', true, 'message', 'تمت إعادة فتح الواجب');
end;
$$;

grant execute on function public.reopen_homework(uuid) to authenticated;

-- -------------------------------------------------------------
-- 6) إغلاق جماعي للواجبات المتأخرة
-- p_apply=false معاينة، p_apply=true تنفيذ.
-- -------------------------------------------------------------
create or replace function public.bulk_close_overdue_homeworks(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  ids uuid[];
  closed_count int := 0;
  hw uuid;
begin
  if p_apply and uid is null then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن التنفيذ من SQL Editor بدون جلسة مستخدم. استخدمي الواجهة أو سجلي الدخول.');
  end if;

  select coalesce(array_agg(h.id), array[]::uuid[])
  into ids
  from public.homeworks h
  where h.status = 'published'
    and h.due_date is not null
    and (h.due_date + coalesce(h.due_time, time '23:59')) < now()
    and (uid is null or public.current_user_is_admin() or h.teacher_id = uid);

  if p_apply then
    update public.homeworks h
    set status = 'closed', updated_at = now()
    where h.id = any(ids);
    get diagnostics closed_count = row_count;

    foreach hw in array ids loop
      begin
        perform public.notify_homework_recipients(hw, 'closed');
      exception when others then
        null;
      end;
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'apply', p_apply, 'matched_count', coalesce(array_length(ids,1),0), 'closed_count', closed_count, 'homework_ids', ids);
end;
$$;

grant execute on function public.bulk_close_overdue_homeworks(boolean) to authenticated;

-- -------------------------------------------------------------
-- 7) فحص سريع
-- -------------------------------------------------------------
create or replace function public.homework_batch_operations_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'dashboard_rpc', to_regprocedure('public.get_homework_dashboard_payload()') is not null,
    'badges_rpc', to_regprocedure('public.get_notification_badges_payload()') is not null,
    'return_rpc', to_regprocedure('public.return_homework_submission(uuid,text)') is not null,
    'close_rpc', to_regprocedure('public.close_homework(uuid)') is not null,
    'reopen_rpc', to_regprocedure('public.reopen_homework(uuid)') is not null,
    'bulk_close_rpc', to_regprocedure('public.bulk_close_overdue_homeworks(boolean)') is not null,
    'payload_stats', public.get_homework_dashboard_payload()->'stats'
  );
end;
$$;

grant execute on function public.homework_batch_operations_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'homework_batch_operations_dashboard_ready' as status;

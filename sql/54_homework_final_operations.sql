-- =============================================================
-- مدارس أمين الرضا (ع) — إنهاء وحدة الواجبات: نسخ/أرشفة/حذف آمن/تشغيل نهائي
-- يعمل فوق SQL 39 إلى 53 ولا يكسر البيانات السابقة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) تأكيد الجداول الأساسية
-- -------------------------------------------------------------
create table if not exists public.homeworks (
  id uuid primary key default gen_random_uuid(),
  class_session_id uuid null references public.class_sessions(id) on delete set null,
  academic_period_id uuid null references public.academic_periods(id) on delete set null,
  class_id uuid null references public.classes(id),
  subject_id uuid null references public.subjects(id),
  teacher_id uuid null references public.users(id),
  title text not null,
  description text,
  assigned_date date not null default current_date,
  due_date date,
  status text not null default 'published',
  created_at timestamptz not null default now()
);

alter table public.homeworks add column if not exists section_id uuid null references public.sections(id) on delete set null;
alter table public.homeworks add column if not exists publish_at timestamptz;
alter table public.homeworks add column if not exists due_time time;
alter table public.homeworks add column if not exists max_score numeric not null default 10;
alter table public.homeworks add column if not exists updated_at timestamptz not null default now();
alter table public.homeworks add column if not exists created_by uuid null references public.users(id);

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

create table if not exists public.school_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid null references public.users(id),
  action text not null,
  entity_table text,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.teacher_error_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid null references public.users(id),
  module text,
  message text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.log_school_audit(
  p_action text,
  p_entity_table text,
  p_entity_id uuid,
  p_old_data jsonb default null,
  p_new_data jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.school_audit_logs(actor_id, action, entity_table, entity_id, old_data, new_data, metadata)
  values (auth.uid(), p_action, p_entity_table, p_entity_id, p_old_data, p_new_data, coalesce(p_metadata,'{}'::jsonb));
end;
$$;

grant execute on function public.log_school_audit(text,text,uuid,jsonb,jsonb,jsonb) to authenticated;

create or replace function public.log_teacher_error(
  p_module text,
  p_message text,
  p_details jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.teacher_error_logs(actor_id, module, message, details)
  values (auth.uid(), p_module, p_message, coalesce(p_details,'{}'::jsonb));
end;
$$;

grant execute on function public.log_teacher_error(text,text,jsonb) to authenticated;

-- -------------------------------------------------------------
-- 1) نسخ واجب مع المرفقات كمسودة/منشور
-- -------------------------------------------------------------
create or replace function public.clone_homework_pro(
  p_homework_id uuid,
  p_new_title text default null,
  p_status text default 'draft',
  p_copy_attachments boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  new_id uuid;
  v_status text := lower(coalesce(p_status,'draft'));
  att_count int := 0;
begin
  select * into h from public.homeworks where id = p_homework_id;

  if h.id is null then
    return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود');
  end if;

  if not (public.current_user_is_admin() or h.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية نسخ هذا الواجب');
  end if;

  if v_status not in ('draft','published','closed','archived') then
    v_status := 'draft';
  end if;

  insert into public.homeworks(
    class_session_id,
    academic_period_id,
    class_id,
    section_id,
    subject_id,
    teacher_id,
    title,
    description,
    assigned_date,
    publish_at,
    due_date,
    due_time,
    max_score,
    status,
    created_by
  ) values (
    null,
    h.academic_period_id,
    h.class_id,
    h.section_id,
    h.subject_id,
    h.teacher_id,
    coalesce(nullif(trim(p_new_title),''), h.title || ' — نسخة'),
    h.description,
    current_date,
    case when v_status = 'published' then now() else null end,
    h.due_date,
    h.due_time,
    h.max_score,
    v_status,
    auth.uid()
  ) returning id into new_id;

  if p_copy_attachments then
    insert into public.homework_attachments(
      homework_id,
      file_name,
      file_type,
      file_size,
      storage_path,
      public_url,
      sort_order,
      uploaded_by
    )
    select
      new_id,
      file_name,
      file_type,
      file_size,
      storage_path,
      public_url,
      sort_order,
      auth.uid()
    from public.homework_attachments
    where homework_id = p_homework_id;

    get diagnostics att_count = row_count;
  end if;

  perform public.log_school_audit('clone_homework', 'homeworks', new_id, to_jsonb(h), (select to_jsonb(x) from public.homeworks x where x.id = new_id), jsonb_build_object('source_homework_id', p_homework_id, 'copy_attachments', p_copy_attachments, 'attachments', att_count));

  if v_status = 'published' then
    begin
      perform public.notify_homework_recipients(new_id, 'published');
    exception when others then
      null;
    end;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم نسخ الواجب', 'homework_id', new_id, 'attachments_copied', att_count, 'status', v_status);
exception when others then
  perform public.log_teacher_error('clone_homework_pro', sqlerrm, jsonb_build_object('homework_id', p_homework_id));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.clone_homework_pro(uuid,text,text,boolean) to authenticated;

-- -------------------------------------------------------------
-- 2) حذف آمن: حذف إذا لا توجد درجات/تسليمات، وإلا أرشفة
-- -------------------------------------------------------------
create or replace function public.delete_homework_safely(p_homework_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  sub_count int := 0;
  grade_count int := 0;
begin
  select * into h from public.homeworks where id = p_homework_id;

  if h.id is null then
    return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود');
  end if;

  if not (public.current_user_is_admin() or h.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية حذف هذا الواجب');
  end if;

  select count(*) into sub_count from public.homework_submissions where homework_id = p_homework_id;
  select count(*) into grade_count from public.homework_grades where homework_id = p_homework_id;

  if sub_count = 0 and grade_count = 0 then
    delete from public.homeworks where id = p_homework_id;
    perform public.log_school_audit('delete_homework', 'homeworks', p_homework_id, to_jsonb(h), null, '{}'::jsonb);
    return jsonb_build_object('ok', true, 'message', 'تم حذف الواجب نهائياً لأنه لا يحتوي على تسليمات أو درجات', 'action', 'deleted');
  end if;

  update public.homeworks
  set status = 'archived',
      updated_at = now()
  where id = p_homework_id;

  perform public.log_school_audit('archive_homework_instead_of_delete', 'homeworks', p_homework_id, to_jsonb(h), (select to_jsonb(x) from public.homeworks x where x.id = p_homework_id), jsonb_build_object('submissions', sub_count, 'grades', grade_count));

  return jsonb_build_object('ok', true, 'message', 'تمت أرشفة الواجب بدل الحذف لأنه يحتوي على بيانات طلاب', 'action', 'archived', 'submissions', sub_count, 'grades', grade_count);
exception when others then
  perform public.log_teacher_error('delete_homework_safely', sqlerrm, jsonb_build_object('homework_id', p_homework_id));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.delete_homework_safely(uuid) to authenticated;

-- -------------------------------------------------------------
-- 3) أرشفة الواجبات المغلقة القديمة
-- -------------------------------------------------------------
create or replace function public.archive_closed_homeworks(
  p_before_date date default current_date,
  p_apply boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  ids uuid[];
  archived_count int := 0;
begin
  if p_apply and auth.uid() is null then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن التنفيذ من SQL Editor بدون جلسة مستخدم. استخدمي الواجهة.');
  end if;

  select coalesce(array_agg(h.id), array[]::uuid[])
  into ids
  from public.homeworks h
  where h.status = 'closed'
    and coalesce(h.due_date, h.assigned_date, h.created_at::date) <= coalesce(p_before_date, current_date)
    and (public.current_user_is_admin() or h.teacher_id = auth.uid() or auth.uid() is null);

  if p_apply then
    update public.homeworks h
    set status = 'archived', updated_at = now()
    where h.id = any(ids);
    get diagnostics archived_count = row_count;

    insert into public.school_audit_logs(actor_id, action, entity_table, entity_id, metadata)
    select auth.uid(), 'archive_closed_homework', 'homeworks', unnest(ids), jsonb_build_object('before_date', p_before_date);
  end if;

  return jsonb_build_object('ok', true, 'apply', p_apply, 'matched_count', coalesce(array_length(ids,1),0), 'archived_count', archived_count, 'homework_ids', ids);
end;
$$;

grant execute on function public.archive_closed_homeworks(date,boolean) to authenticated;

-- -------------------------------------------------------------
-- 4) لوحة نهائية مختصرة لوحدة الواجبات
-- -------------------------------------------------------------
create or replace function public.get_homework_final_dashboard_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  uid uuid := auth.uid();
  stats jsonb;
  recent jsonb;
  needs_action jsonb;
begin
  select jsonb_build_object(
    'homeworks_total', count(*),
    'draft', count(*) filter (where status='draft'),
    'published', count(*) filter (where status='published'),
    'closed', count(*) filter (where status='closed'),
    'archived', count(*) filter (where status='archived'),
    'overdue_published', count(*) filter (where status='published' and due_date is not null and (due_date + coalesce(due_time, time '23:59')) < now()),
    'submissions', (select count(*) from public.homework_submissions hs join public.homeworks h2 on h2.id=hs.homework_id where (uid is null or public.current_user_is_admin() or h2.teacher_id=uid)),
    'grades', (select count(*) from public.homework_grades hg join public.homeworks h3 on h3.id=hg.homework_id where (uid is null or public.current_user_is_admin() or h3.teacher_id=uid)),
    'comments', (select count(*) from public.homework_submission_comments c join public.homework_submissions hs on hs.id=c.submission_id join public.homeworks h4 on h4.id=hs.homework_id where (uid is null or public.current_user_is_admin() or h4.teacher_id=uid))
  )
  into stats
  from public.homeworks h
  where uid is null or public.current_user_is_admin() or h.teacher_id = uid;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into recent
  from (
    select id, title, status, due_date, due_time, created_at, updated_at
    from public.homeworks h
    where uid is null or public.current_user_is_admin() or h.teacher_id = uid
    order by created_at desc
    limit 12
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.due_date nulls last, x.created_at desc), '[]'::jsonb)
  into needs_action
  from (
    select id, title, status, due_date, due_time, created_at,
      case
        when status='draft' then 'مسودة تحتاج نشر'
        when status='published' and due_date is not null and (due_date + coalesce(due_time, time '23:59')) < now() then 'منشور متأخر يحتاج إغلاق/تصفير'
        when status='closed' then 'مغلق يمكن أرشفته'
        else 'متابعة'
      end as action_hint
    from public.homeworks h
    where (uid is null or public.current_user_is_admin() or h.teacher_id = uid)
      and (
        status='draft'
        or (status='published' and due_date is not null and (due_date + coalesce(due_time, time '23:59')) < now())
        or status='closed'
      )
    order by due_date nulls last, created_at desc
    limit 20
  ) x;

  return jsonb_build_object('ok', true, 'stats', stats, 'recent', recent, 'needs_action', needs_action);
end;
$$;

grant execute on function public.get_homework_final_dashboard_payload() to authenticated;

-- -------------------------------------------------------------
-- 5) فحص نهائي لوحدة الواجبات
-- -------------------------------------------------------------
create or replace function public.homework_final_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'homeworks', to_regclass('public.homeworks') is not null,
    'attachments', to_regclass('public.homework_attachments') is not null,
    'submissions', to_regclass('public.homework_submissions') is not null,
    'submission_attachments', to_regclass('public.homework_submission_attachments') is not null,
    'grades', to_regclass('public.homework_grades') is not null,
    'views', to_regclass('public.homework_views') is not null,
    'comments', to_regclass('public.homework_submission_comments') is not null,
    'notifications', to_regclass('public.school_notifications') is not null,
    'clone_rpc', to_regprocedure('public.clone_homework_pro(uuid,text,text,boolean)') is not null,
    'delete_safe_rpc', to_regprocedure('public.delete_homework_safely(uuid)') is not null,
    'archive_closed_rpc', to_regprocedure('public.archive_closed_homeworks(date,boolean)') is not null,
    'final_dashboard_rpc', to_regprocedure('public.get_homework_final_dashboard_payload()') is not null,
    'stats', public.get_homework_final_dashboard_payload()->'stats'
  );
end;
$$;

grant execute on function public.homework_final_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'homework_final_operations_ready' as status;

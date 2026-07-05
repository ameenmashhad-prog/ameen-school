-- =============================================================
-- مدارس أمين الرضا (ع) — تطوير الواجبات وربط الدرجات بالواجبات المنشورة
-- مرفقات، إشعارات، حفظ آمن للدرجات، Audit Log، ودوال واجهة المعلم
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) تطوير جدول الواجبات بشكل توافقي
-- -------------------------------------------------------------
alter table public.homeworks add column if not exists section_id uuid null references public.sections(id) on delete set null;
alter table public.homeworks add column if not exists publish_at timestamptz;
alter table public.homeworks add column if not exists due_time time;
alter table public.homeworks add column if not exists max_score numeric not null default 10;
alter table public.homeworks add column if not exists updated_at timestamptz not null default now();
alter table public.homeworks add column if not exists created_by uuid null references public.users(id);

update public.homeworks
set publish_at = coalesce(publish_at, assigned_date::timestamptz),
    updated_at = coalesce(updated_at, created_at, now())
where publish_at is null or updated_at is null;

-- لا نضيف CHECK قاسياً حتى لا نكسر بيانات قديمة، لكن الدوال أدناه تضبط القيم.
create index if not exists idx_homeworks_teacher_status on public.homeworks(teacher_id, status, created_at desc);
create index if not exists idx_homeworks_section_subject on public.homeworks(section_id, subject_id, status);

-- -------------------------------------------------------------
-- 2) مرفقات الواجبات
-- -------------------------------------------------------------
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

create index if not exists idx_homework_attachments_homework on public.homework_attachments(homework_id, sort_order);

-- -------------------------------------------------------------
-- 3) درجات الواجبات — لا تحفظ إلا لواجب منشور
-- -------------------------------------------------------------
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
  updated_at timestamptz not null default now(),
  unique(homework_id, student_id)
);

create index if not exists idx_homework_grades_student on public.homework_grades(student_id, homework_id);

-- ربط التقييم المستمر بالواجب لتظهر درجات الواجب في النظام الأكاديمي.
alter table public.continuous_assessments add column if not exists homework_id uuid null references public.homeworks(id) on delete set null;
create unique index if not exists uq_continuous_homework_student
  on public.continuous_assessments(homework_id, student_id)
  where homework_id is not null;

-- -------------------------------------------------------------
-- 4) إشعارات داخلية
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

-- -------------------------------------------------------------
-- 5) Audit Log + Error Logs
-- -------------------------------------------------------------
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

create index if not exists idx_school_audit_logs_entity on public.school_audit_logs(entity_table, entity_id, created_at desc);
create index if not exists idx_teacher_error_logs_actor on public.teacher_error_logs(actor_id, created_at desc);

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
-- 6) Storage bucket للمرفقات — آمن إذا لم تتوفر صلاحية storage في المشروع
-- -------------------------------------------------------------
do $$ begin
  begin
    insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
    values (
      'homework-attachments',
      'homework-attachments',
      false,
      26214400,
      array[
        'image/jpeg','image/png','image/webp','application/pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation'
      ]
    )
    on conflict (id) do update
    set public = false,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;
  exception when others then
    raise notice 'تعذر إنشاء bucket homework-attachments: %', sqlerrm;
  end;
end $$;

-- سياسات Storage للمرفقات، داخل كتلة آمنة حتى لا تفشل إن اختلفت صلاحيات storage.
do $$ begin
  begin
    if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='homework_attachments_storage_select') then
      create policy homework_attachments_storage_select on storage.objects
        for select to authenticated
        using (bucket_id = 'homework-attachments');
    end if;

    if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='homework_attachments_storage_insert') then
      create policy homework_attachments_storage_insert on storage.objects
        for insert to authenticated
        with check (bucket_id = 'homework-attachments');
    end if;

    if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='homework_attachments_storage_update_delete') then
      create policy homework_attachments_storage_update_delete on storage.objects
        for all to authenticated
        using (bucket_id = 'homework-attachments')
        with check (bucket_id = 'homework-attachments');
    end if;
  exception when others then
    raise notice 'تعذر إنشاء سياسات storage للمرفقات: %', sqlerrm;
  end;
end $$;

-- -------------------------------------------------------------
-- 7) إشعارات الواجب
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
  inserted_count int := 0;
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
  insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
  select distinct s.user_id, 'student', title_text, body_text, 'homework_' || p_event, 'homeworks', h.id, auth.uid()
  from public.students s
  left join public.student_enrollments se on se.student_id = s.id and se.enrollment_status = 'active'
  where s.user_id is not null
    and (
      (h.section_id is not null and se.section_id = h.section_id)
      or (h.section_id is null and h.class_id is not null and coalesce(se.class_id, s.class_id) = h.class_id)
    );

  get diagnostics inserted_count = row_count;

  -- أولياء الأمور
  insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
  select distinct s.parent_id, 'parent', title_text, body_text, 'homework_' || p_event, 'homeworks', h.id, auth.uid()
  from public.students s
  left join public.student_enrollments se on se.student_id = s.id and se.enrollment_status = 'active'
  where s.parent_id is not null
    and (
      (h.section_id is not null and se.section_id = h.section_id)
      or (h.section_id is null and h.class_id is not null and coalesce(se.class_id, s.class_id) = h.class_id)
    );

  get diagnostics inserted_parents = row_count;
  inserted_count := inserted_count + inserted_parents;

  return jsonb_build_object('ok', true, 'message', 'تم إنشاء الإشعارات', 'count', inserted_count);
end;
$$;

grant execute on function public.notify_homework_recipients(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 8) إنشاء/تعديل واجب احترافي
-- -------------------------------------------------------------
create or replace function public.save_homework_pro(
  p_homework_id uuid default null,
  p_session_id uuid default null,
  p_title text default null,
  p_description text default null,
  p_subject_id uuid default null,
  p_class_id uuid default null,
  p_section_id uuid default null,
  p_publish_at timestamptz default null,
  p_due_date date default null,
  p_due_time time default null,
  p_max_score numeric default 10,
  p_status text default 'draft'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s record;
  old_h record;
  hw_id uuid;
  v_teacher uuid := auth.uid();
  v_old_status text;
  v_status text := coalesce(nullif(p_status,''),'draft');
  v_class uuid := p_class_id;
  v_subject uuid := p_subject_id;
  v_section uuid := p_section_id;
  v_period uuid := null;
begin
  if v_status not in ('draft','published','closed','archived') then
    return jsonb_build_object('ok', false, 'message', 'حالة الواجب غير صحيحة');
  end if;

  if nullif(trim(coalesce(p_title,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'عنوان الواجب مطلوب');
  end if;

  if coalesce(p_max_score,0) <= 0 then
    return jsonb_build_object('ok', false, 'message', 'الدرجة الكاملة يجب أن تكون أكبر من صفر');
  end if;

  if p_session_id is not null then
    select * into s from public.class_sessions where id = p_session_id;
    if s.id is null then
      return jsonb_build_object('ok', false, 'message', 'الحصة غير موجودة');
    end if;
    if auth.uid() is not null and s.teacher_id <> auth.uid() and not public.current_user_is_admin() then
      return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إنشاء واجب لهذه الحصة');
    end if;
    v_teacher := s.teacher_id;
    v_period := s.academic_period_id;
    v_class := coalesce(v_class, s.class_id);
    v_subject := coalesce(v_subject, s.subject_id);
    v_section := coalesce(v_section, s.section_id);
  end if;

  if v_class is null or v_subject is null then
    return jsonb_build_object('ok', false, 'message', 'اختاري المادة والصف/الشعبة');
  end if;

  if p_homework_id is not null then
    select * into old_h from public.homeworks where id = p_homework_id;
    if old_h.id is null then
      return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود');
    end if;
    if auth.uid() is not null and old_h.teacher_id <> auth.uid() and not public.current_user_is_admin() then
      return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل هذا الواجب');
    end if;
    v_old_status := old_h.status;

    update public.homeworks
    set class_session_id = p_session_id,
        class_id = v_class,
        section_id = v_section,
        subject_id = v_subject,
        teacher_id = coalesce(old_h.teacher_id, v_teacher),
        title = trim(p_title),
        description = p_description,
        assigned_date = coalesce((p_publish_at at time zone 'UTC')::date, current_date),
        publish_at = p_publish_at,
        due_date = p_due_date,
        due_time = p_due_time,
        max_score = p_max_score,
        status = v_status,
        updated_at = now()
    where id = p_homework_id
    returning id into hw_id;

    perform public.log_school_audit('update_homework', 'homeworks', hw_id, to_jsonb(old_h), (select to_jsonb(h) from public.homeworks h where h.id = hw_id), '{}'::jsonb);
  else
    insert into public.homeworks(
      class_session_id, academic_period_id, class_id, section_id, subject_id, teacher_id,
      title, description, assigned_date, publish_at, due_date, due_time, max_score, status, created_by
    ) values (
      p_session_id, v_period, v_class, v_section, v_subject, v_teacher,
      trim(p_title), p_description, coalesce((p_publish_at at time zone 'UTC')::date, current_date), p_publish_at,
      p_due_date, p_due_time, p_max_score, v_status, auth.uid()
    ) returning id into hw_id;

    perform public.log_school_audit('create_homework', 'homeworks', hw_id, null, (select to_jsonb(h) from public.homeworks h where h.id = hw_id), '{}'::jsonb);
  end if;

  if v_status = 'published' and coalesce(v_old_status,'') <> 'published' then
    perform public.log_school_audit('publish_homework', 'homeworks', hw_id, null, (select to_jsonb(h) from public.homeworks h where h.id = hw_id), '{}'::jsonb);
    perform public.notify_homework_recipients(hw_id, 'published');
  elsif p_homework_id is not null and v_status = 'published' then
    perform public.notify_homework_recipients(hw_id, 'updated');
  elsif p_homework_id is not null and v_status = 'closed' and coalesce(v_old_status,'') <> 'closed' then
    perform public.log_school_audit('close_homework', 'homeworks', hw_id, to_jsonb(old_h), (select to_jsonb(h) from public.homeworks h where h.id = hw_id), '{}'::jsonb);
    perform public.notify_homework_recipients(hw_id, 'closed');
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ الواجب', 'homework_id', hw_id, 'status', v_status);
exception when others then
  perform public.log_teacher_error('save_homework_pro', sqlerrm, jsonb_build_object('homework_id', p_homework_id, 'title', p_title));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.save_homework_pro(uuid,uuid,text,text,uuid,uuid,uuid,timestamptz,date,time,numeric,text) to authenticated;

-- نسخة متوافقة مع الزر القديم من الحصة، تنشر مباشرة.
create or replace function public.create_session_homework(
  p_session_id uuid,
  p_title text,
  p_description text default null,
  p_due_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.save_homework_pro(
    null,
    p_session_id,
    p_title,
    p_description,
    null,
    null,
    null,
    now(),
    p_due_date,
    null,
    10,
    'published'
  );
end;
$$;

grant execute on function public.create_session_homework(uuid,text,text,date) to authenticated;

-- إضافة مرفق بعد رفعه إلى Storage
create or replace function public.add_homework_attachment(
  p_homework_id uuid,
  p_file_name text,
  p_file_type text,
  p_file_size bigint,
  p_storage_path text,
  p_public_url text default null,
  p_sort_order int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  att_id uuid;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود'); end if;
  if auth.uid() is not null and h.teacher_id <> auth.uid() and not public.current_user_is_admin() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إضافة مرفقات لهذا الواجب');
  end if;

  insert into public.homework_attachments(homework_id, file_name, file_type, file_size, storage_path, public_url, sort_order, uploaded_by)
  values (p_homework_id, p_file_name, p_file_type, p_file_size, p_storage_path, p_public_url, p_sort_order, auth.uid())
  returning id into att_id;

  perform public.log_school_audit('add_homework_attachment', 'homework_attachments', att_id, null, jsonb_build_object('homework_id', p_homework_id, 'file_name', p_file_name), '{}'::jsonb);
  return jsonb_build_object('ok', true, 'attachment_id', att_id);
exception when others then
  perform public.log_teacher_error('add_homework_attachment', sqlerrm, jsonb_build_object('homework_id', p_homework_id, 'file_name', p_file_name));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.add_homework_attachment(uuid,text,text,bigint,text,text,int) to authenticated;

-- -------------------------------------------------------------
-- 9) حماية درجات الواجبات: لا INSERT/UPDATE/DELETE إلا إذا الواجب منشور
-- -------------------------------------------------------------
create or replace function public.enforce_published_homework_grade()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  hw uuid;
begin
  hw := coalesce(new.homework_id, old.homework_id);
  select * into h from public.homeworks where id = hw;

  if h.id is null then
    raise exception 'الواجب غير موجود';
  end if;

  if h.status <> 'published' then
    raise exception 'لا يمكن إضافة أو تعديل أو حذف درجة إلا إذا كان الواجب منشوراً فعلياً. الحالة الحالية: %', h.status;
  end if;

  if tg_op in ('INSERT','UPDATE') then
    if new.score < 0 or new.score > coalesce(new.max_score, h.max_score, 10) then
      raise exception 'الدرجة يجب أن تكون بين 0 و %', coalesce(new.max_score, h.max_score, 10);
    end if;
    new.updated_at := now();
    new.graded_at := now();
    return new;
  end if;

  return old;
end;
$$;

drop trigger if exists trg_homework_grades_published_only on public.homework_grades;
create trigger trg_homework_grades_published_only
  before insert or update or delete on public.homework_grades
  for each row execute function public.enforce_published_homework_grade();

-- حفظ درجة واجب منشور + مزامنة التقييم المستمر
create or replace function public.save_homework_grade(
  p_homework_id uuid,
  p_student_id uuid,
  p_score numeric,
  p_feedback text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  old_g record;
  grade_id uuid;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود'); end if;
  if h.status <> 'published' then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن حفظ درجة إلا لواجب منشور. الواجب الحالي: ' || h.status);
  end if;
  if auth.uid() is not null and h.teacher_id <> auth.uid() and not public.current_user_is_admin() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدخال درجة لهذا الواجب');
  end if;
  if p_score is null or p_score < 0 or p_score > coalesce(h.max_score,10) then
    return jsonb_build_object('ok', false, 'message', 'الدرجة يجب أن تكون بين 0 و ' || coalesce(h.max_score,10));
  end if;

  select * into old_g from public.homework_grades where homework_id = p_homework_id and student_id = p_student_id;

  insert into public.homework_grades(homework_id, student_id, score, max_score, feedback, graded_by)
  values (p_homework_id, p_student_id, p_score, coalesce(h.max_score,10), p_feedback, auth.uid())
  on conflict (homework_id, student_id) do update
  set score = excluded.score,
      max_score = excluded.max_score,
      feedback = excluded.feedback,
      graded_by = excluded.graded_by,
      graded_at = now(),
      updated_at = now()
  returning id into grade_id;

  insert into public.continuous_assessments(
    homework_id, student_id, class_id, subject_id, teacher_id,
    component_type, score, max_score, notes, assessment_month, assessment_date, created_by
  ) values (
    p_homework_id, p_student_id, h.class_id, h.subject_id, h.teacher_id,
    'homework', p_score, coalesce(h.max_score,10), p_feedback, extract(month from current_date)::int, current_date, auth.uid()
  )
  on conflict (homework_id, student_id) do update
  set score = excluded.score,
      max_score = excluded.max_score,
      notes = excluded.notes,
      updated_at = now();

  perform public.log_school_audit(
    case when old_g.id is null then 'create_homework_grade' else 'update_homework_grade' end,
    'homework_grades', grade_id, to_jsonb(old_g),
    (select to_jsonb(g) from public.homework_grades g where g.id = grade_id),
    jsonb_build_object('homework_id', p_homework_id, 'student_id', p_student_id)
  );

  return jsonb_build_object('ok', true, 'message', 'تم حفظ درجة الواجب', 'grade_id', grade_id);
exception when others then
  perform public.log_teacher_error('save_homework_grade', sqlerrm, jsonb_build_object('homework_id', p_homework_id, 'student_id', p_student_id, 'score', p_score));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.save_homework_grade(uuid,uuid,numeric,text) to authenticated;

-- حفظ تقييم مستمر آمن عبر RPC لإصلاح مشاكل RLS/INSERT المباشر
create or replace function public.save_continuous_assessment_safe(
  p_student_id uuid,
  p_class_id uuid,
  p_subject_id uuid,
  p_component_type text,
  p_score numeric,
  p_max_score numeric default 10,
  p_notes text default null,
  p_class_session_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rec_id uuid;
begin
  if p_component_type not in ('participation','homework','activity','project','discipline','quiz','other') then
    return jsonb_build_object('ok', false, 'message', 'نوع التقييم غير صحيح');
  end if;
  if p_score is null or p_score < 0 or p_score > coalesce(p_max_score,10) then
    return jsonb_build_object('ok', false, 'message', 'الدرجة خارج المدى المسموح');
  end if;

  insert into public.continuous_assessments(
    student_id, class_id, subject_id, teacher_id, component_type,
    score, max_score, notes, assessment_month, assessment_date, class_session_id, created_by
  ) values (
    p_student_id, p_class_id, p_subject_id, auth.uid(), p_component_type,
    p_score, coalesce(p_max_score,10), p_notes, extract(month from current_date)::int, current_date, p_class_session_id, auth.uid()
  ) returning id into rec_id;

  perform public.log_school_audit('create_continuous_assessment', 'continuous_assessments', rec_id, null, jsonb_build_object('student_id', p_student_id, 'score', p_score), '{}'::jsonb);
  return jsonb_build_object('ok', true, 'message', 'تم حفظ التقييم', 'assessment_id', rec_id);
exception when others then
  perform public.log_teacher_error('save_continuous_assessment_safe', sqlerrm, jsonb_build_object('student_id', p_student_id, 'score', p_score));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.save_continuous_assessment_safe(uuid,uuid,uuid,text,numeric,numeric,text,uuid) to authenticated;

-- -------------------------------------------------------------
-- 10) RLS grants
-- -------------------------------------------------------------
alter table public.homework_attachments enable row level security;
alter table public.homework_grades enable row level security;
alter table public.school_notifications enable row level security;
alter table public.school_audit_logs enable row level security;
alter table public.teacher_error_logs enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='homework_attachments' and policyname='homework_attachments_teacher_student_read') then
    create policy homework_attachments_teacher_student_read on public.homework_attachments
      for select to authenticated
      using (
        exists(
          select 1 from public.homeworks h
          where h.id = homework_id
            and (
              public.current_user_is_admin()
              or h.teacher_id = auth.uid()
              or exists(select 1 from public.students s where s.user_id = auth.uid() and (s.class_id = h.class_id or s.section_id = h.section_id))
              or exists(select 1 from public.students s where s.parent_id = auth.uid() and (s.class_id = h.class_id or s.section_id = h.section_id))
            )
        )
      );
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='homework_attachments' and policyname='homework_attachments_teacher_write') then
    create policy homework_attachments_teacher_write on public.homework_attachments
      for all to authenticated
      using (exists(select 1 from public.homeworks h where h.id = homework_id and (public.current_user_is_admin() or h.teacher_id = auth.uid())))
      with check (exists(select 1 from public.homeworks h where h.id = homework_id and (public.current_user_is_admin() or h.teacher_id = auth.uid())));
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='homework_grades' and policyname='homework_grades_teacher_student_read') then
    create policy homework_grades_teacher_student_read on public.homework_grades
      for select to authenticated
      using (
        public.current_user_is_admin()
        or exists(select 1 from public.homeworks h where h.id = homework_id and h.teacher_id = auth.uid())
        or exists(select 1 from public.students s where s.id = student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
      );
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='homework_grades' and policyname='homework_grades_teacher_write') then
    create policy homework_grades_teacher_write on public.homework_grades
      for all to authenticated
      using (exists(select 1 from public.homeworks h where h.id = homework_id and (public.current_user_is_admin() or h.teacher_id = auth.uid())))
      with check (exists(select 1 from public.homeworks h where h.id = homework_id and (public.current_user_is_admin() or h.teacher_id = auth.uid())));
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='school_notifications' and policyname='school_notifications_own_or_admin') then
    create policy school_notifications_own_or_admin on public.school_notifications
      for select to authenticated
      using (public.current_user_is_admin() or recipient_user_id = auth.uid() or created_by = auth.uid());
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='school_audit_logs' and policyname='school_audit_logs_teacher_admin_read') then
    create policy school_audit_logs_teacher_admin_read on public.school_audit_logs
      for select to authenticated
      using (public.current_user_is_admin() or actor_id = auth.uid());
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='teacher_error_logs' and policyname='teacher_error_logs_own_admin') then
    create policy teacher_error_logs_own_admin on public.teacher_error_logs
      for select to authenticated
      using (public.current_user_is_admin() or actor_id = auth.uid());
  end if;
end $$;

grant select, insert, update on public.homeworks to authenticated;
grant select, insert, update, delete on public.homework_attachments to authenticated;
grant select, insert, update, delete on public.homework_grades to authenticated;
grant select, insert, update on public.school_notifications to authenticated;
grant select on public.school_audit_logs to authenticated;
grant select on public.teacher_error_logs to authenticated;

notify pgrst, 'reload schema';

select 'homework_grades_attachments_notifications_audit_ready' as status;

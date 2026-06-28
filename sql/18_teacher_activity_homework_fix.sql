-- =============================================================
-- مدارس أمين الرضا (ع) — إصلاح تثبيت الحصص والواجبات للمعلمات
-- يعتمد على class_sessions / homeworks / teacher_activity_log من SQL 08
-- =============================================================

create extension if not exists pgcrypto;

-- تأكد من وجود الأعمدة والجداول الأساسية
create table if not exists public.teacher_activity_log (
  id uuid primary key default gen_random_uuid(),
  class_session_id uuid null references public.class_sessions(id) on delete cascade,
  teacher_id uuid not null references public.users(id),
  activity_type text not null,
  evidence_table text,
  evidence_id uuid,
  activity_weight numeric not null default 1,
  notes text,
  occurred_at timestamptz not null default now(),
  created_by uuid null references public.users(id)
);

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

-- فهرس يمنع تكرار تثبيت نفس الحصة بنفس نوع النشاط من دون evidence.
do $$ begin
  begin
    create unique index if not exists uq_teacher_activity_manual_session
      on public.teacher_activity_log(class_session_id, teacher_id, activity_type)
      where evidence_id is null;
  exception when others then
    raise notice 'تعذر إنشاء unique index لنشاط المعلمة: %', sqlerrm;
  end;
end $$;

-- دالة تثبيت حصة
create or replace function public.confirm_teacher_session(
  p_session_id uuid,
  p_activity_type text default 'manual_confirm',
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s record;
  actor uuid := auth.uid();
begin
  select * into s
  from public.class_sessions
  where id = p_session_id;

  if s.id is null then
    return jsonb_build_object('ok', false, 'message', 'الحصة غير موجودة');
  end if;

  if s.teacher_id is null then
    return jsonb_build_object('ok', false, 'message', 'لا توجد معلمة مرتبطة بهذه الحصة');
  end if;

  if s.status = 'holiday' then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن تثبيت حصة في يوم عطلة');
  end if;

  insert into public.teacher_activity_log (
    class_session_id,
    teacher_id,
    activity_type,
    activity_weight,
    notes,
    created_by
  ) values (
    p_session_id,
    s.teacher_id,
    coalesce(p_activity_type,'manual_confirm'),
    1,
    coalesce(p_notes,'تثبيت حصة من الواجهة'),
    actor
  ) on conflict do nothing;

  update public.class_sessions
  set status = 'completed', updated_at = now()
  where id = p_session_id;

  return jsonb_build_object('ok', true, 'message', 'تم تثبيت الحصة');
end;
$$;

-- دالة إنشاء واجب مرتبط بحصة وتسجيل نشاط للمعلمة
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
declare
  s record;
  hw_id uuid;
  actor uuid := auth.uid();
begin
  select * into s
  from public.class_sessions
  where id = p_session_id;

  if s.id is null then
    return jsonb_build_object('ok', false, 'message', 'الحصة غير موجودة');
  end if;

  if s.teacher_id is null then
    return jsonb_build_object('ok', false, 'message', 'لا توجد معلمة مرتبطة بهذه الحصة');
  end if;

  if s.status = 'holiday' then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن إنشاء واجب في يوم عطلة');
  end if;

  insert into public.homeworks (
    class_session_id,
    academic_period_id,
    class_id,
    subject_id,
    teacher_id,
    title,
    description,
    assigned_date,
    due_date,
    status
  ) values (
    p_session_id,
    s.academic_period_id,
    s.class_id,
    s.subject_id,
    s.teacher_id,
    coalesce(nullif(trim(p_title),''),'واجب'),
    p_description,
    s.session_date,
    p_due_date,
    'published'
  ) returning id into hw_id;

  insert into public.teacher_activity_log (
    class_session_id,
    teacher_id,
    activity_type,
    evidence_table,
    evidence_id,
    activity_weight,
    notes,
    created_by
  ) values (
    p_session_id,
    s.teacher_id,
    'homework',
    'homeworks',
    hw_id,
    1,
    'تم تسجيل نشاط بسبب نشر واجب',
    actor
  ) on conflict do nothing;

  update public.class_sessions
  set status = 'completed', updated_at = now()
  where id = p_session_id;

  return jsonb_build_object('ok', true, 'message', 'تم نشر الواجب وتثبيت نشاط المعلمة', 'homework_id', hw_id);
end;
$$;

grant execute on function public.confirm_teacher_session(uuid,text,text) to authenticated;
grant execute on function public.create_session_homework(uuid,text,text,date) to authenticated;
grant select, insert, update on public.teacher_activity_log to authenticated;
grant select, insert, update on public.homeworks to authenticated;

notify pgrst, 'reload schema';

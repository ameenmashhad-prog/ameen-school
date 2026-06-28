-- =============================================================
-- مدارس أمين الرضا (ع) — إصلاح عاجل لحفظ درجات الواجبات
-- يحل: بقاء الواجهة على "جاري الحفظ التلقائي" أو فشل الحفظ بسبب trigger/ON CONFLICT.
-- =============================================================

create extension if not exists pgcrypto;

-- تأكد من الأعمدة المطلوبة
alter table public.homeworks add column if not exists section_id uuid null references public.sections(id) on delete set null;
alter table public.homeworks add column if not exists max_score numeric not null default 10;
alter table public.homeworks add column if not exists updated_at timestamptz not null default now();
alter table public.continuous_assessments add column if not exists homework_id uuid null references public.homeworks(id) on delete set null;

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

create table if not exists public.teacher_error_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid null references public.users(id),
  module text,
  message text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
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

-- -------------------------------------------------------------
-- 1) إصلاح Trigger الحماية: لا يستخدم NEW في DELETE ولا OLD في INSERT.
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
  v_score numeric;
  v_max numeric;
begin
  if tg_op = 'INSERT' or tg_op = 'UPDATE' then
    hw := new.homework_id;
    v_score := new.score;
    v_max := coalesce(new.max_score, 10);
  else
    hw := old.homework_id;
    v_score := old.score;
    v_max := coalesce(old.max_score, 10);
  end if;

  select * into h from public.homeworks where id = hw;

  if h.id is null then
    raise exception 'الواجب غير موجود';
  end if;

  if h.status <> 'published' then
    raise exception 'لا يمكن إضافة أو تعديل أو حذف درجة إلا إذا كان الواجب منشوراً فعلياً. الحالة الحالية: %', h.status;
  end if;

  if tg_op in ('INSERT','UPDATE') then
    new.max_score := coalesce(new.max_score, h.max_score, 10);

    if new.score is null or new.score < 0 or new.score > coalesce(new.max_score, h.max_score, 10) then
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

-- -------------------------------------------------------------
-- 2) حفظ درجة الواجب بدون ON CONFLICT على partial index في continuous_assessments.
-- -------------------------------------------------------------
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
  ca_id uuid;
begin
  select * into h from public.homeworks where id = p_homework_id;

  if h.id is null then
    return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود');
  end if;

  if h.status <> 'published' then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن حفظ درجة إلا لواجب منشور. حالة الواجب الحالية: ' || coalesce(h.status,'غير محددة'));
  end if;

  if auth.uid() is not null and h.teacher_id <> auth.uid() and not public.current_user_is_admin() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدخال درجة لهذا الواجب');
  end if;

  if p_score is null or p_score < 0 or p_score > coalesce(h.max_score,10) then
    return jsonb_build_object('ok', false, 'message', 'الدرجة يجب أن تكون بين 0 و ' || coalesce(h.max_score,10));
  end if;

  select * into old_g
  from public.homework_grades
  where homework_id = p_homework_id
    and student_id = p_student_id;

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

  -- مزامنة التقييم المستمر بطريقة update ثم insert لتجنب مشكلة partial unique index.
  update public.continuous_assessments
  set score = p_score,
      max_score = coalesce(h.max_score,10),
      notes = p_feedback,
      class_id = h.class_id,
      subject_id = h.subject_id,
      teacher_id = h.teacher_id,
      component_type = 'homework',
      assessment_month = extract(month from current_date)::int,
      assessment_date = current_date,
      updated_at = now()
  where homework_id = p_homework_id
    and student_id = p_student_id
  returning id into ca_id;

  if ca_id is null then
    insert into public.continuous_assessments(
      homework_id,
      student_id,
      class_id,
      subject_id,
      teacher_id,
      component_type,
      score,
      max_score,
      notes,
      assessment_month,
      assessment_date,
      created_by
    ) values (
      p_homework_id,
      p_student_id,
      h.class_id,
      h.subject_id,
      h.teacher_id,
      'homework',
      p_score,
      coalesce(h.max_score,10),
      p_feedback,
      extract(month from current_date)::int,
      current_date,
      auth.uid()
    ) returning id into ca_id;
  end if;

  perform public.log_school_audit(
    case when old_g.id is null then 'create_homework_grade' else 'update_homework_grade' end,
    'homework_grades',
    grade_id,
    to_jsonb(old_g),
    (select to_jsonb(g) from public.homework_grades g where g.id = grade_id),
    jsonb_build_object('homework_id', p_homework_id, 'student_id', p_student_id, 'continuous_assessment_id', ca_id)
  );

  return jsonb_build_object(
    'ok', true,
    'message', 'تم حفظ درجة الواجب',
    'grade_id', grade_id,
    'continuous_assessment_id', ca_id
  );
exception when others then
  perform public.log_teacher_error(
    'save_homework_grade',
    sqlerrm,
    jsonb_build_object('homework_id', p_homework_id, 'student_id', p_student_id, 'score', p_score)
  );
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.save_homework_grade(uuid,uuid,numeric,text) to authenticated;

-- -------------------------------------------------------------
-- 3) فحص سريع لتشخيص حفظ درجات الواجب
-- -------------------------------------------------------------
create or replace function public.homework_grade_save_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'homework_grades_exists', to_regclass('public.homework_grades') is not null,
    'homework_id_column_on_continuous', exists(select 1 from information_schema.columns where table_schema='public' and table_name='continuous_assessments' and column_name='homework_id'),
    'published_homeworks', (select count(*) from public.homeworks where status='published'),
    'homework_grades_count', (select count(*) from public.homework_grades),
    'recent_errors', coalesce((select jsonb_agg(jsonb_build_object('module', module, 'message', message, 'created_at', created_at) order by created_at desc) from (select * from public.teacher_error_logs order by created_at desc limit 5) e), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.homework_grade_save_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'homework_grade_save_hotfix_ready' as status;

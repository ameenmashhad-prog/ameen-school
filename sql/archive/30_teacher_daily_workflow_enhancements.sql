-- =============================================================
-- مدارس أمين الرضا (ع) — تحسين سير عمل المعلم اليومي
-- حضور سريع، تحضير درس، إثبات نشاط الحصة، تنبيهات الطلاب المتعثرين
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) ربط التقييمات والاختبارات بجلسة فعلية عند الإمكان
-- -------------------------------------------------------------
alter table public.continuous_assessments add column if not exists class_session_id uuid null references public.class_sessions(id) on delete set null;
alter table public.exams add column if not exists class_session_id uuid null references public.class_sessions(id) on delete set null;

-- -------------------------------------------------------------
-- 2) تحضير الدروس اليومي
-- -------------------------------------------------------------
create table if not exists public.lesson_plans (
  id uuid primary key default gen_random_uuid(),
  class_session_id uuid not null references public.class_sessions(id) on delete cascade,
  teacher_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  objectives text,
  lesson_summary text,
  resources text,
  homework_hint text,
  status text not null default 'prepared' check (status in ('draft','prepared','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(class_session_id, teacher_id)
);

create index if not exists idx_lesson_plans_teacher on public.lesson_plans(teacher_id, created_at desc);
create index if not exists idx_lesson_plans_session on public.lesson_plans(class_session_id);

-- -------------------------------------------------------------
-- 3) تأكيد حصة حسب التاريخ/الشعبة/الحصة
-- مفيد لتثبيت أخذ الحضور حتى لو كل الطلاب حاضرون ولا توجد سجلات غياب.
-- -------------------------------------------------------------
create or replace function public.confirm_teacher_session_by_slot(
  p_session_date date,
  p_section_id uuid,
  p_period_number int,
  p_activity_type text default 'attendance',
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s record;
  v_uid uuid := auth.uid();
begin
  select * into s
  from public.class_sessions cs
  where cs.session_date = p_session_date
    and cs.section_id = p_section_id
    and cs.period_number = p_period_number
    and (v_uid is null or cs.teacher_id = v_uid or public.current_user_is_admin())
  limit 1;

  if s.id is null then
    return jsonb_build_object('ok', false, 'message', 'لا توجد جلسة مطابقة للتاريخ والشعبة والحصة');
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
    s.id,
    s.teacher_id,
    coalesce(p_activity_type,'attendance'),
    1,
    coalesce(p_notes,'تثبيت نشاط من لوحة المعلم'),
    v_uid
  ) on conflict do nothing;

  update public.class_sessions
  set status = 'completed', updated_at = now()
  where id = s.id;

  return jsonb_build_object('ok', true, 'message', 'تم تثبيت نشاط الحصة', 'class_session_id', s.id);
end;
$$;

grant execute on function public.confirm_teacher_session_by_slot(date,uuid,int,text,text) to authenticated;

-- -------------------------------------------------------------
-- 4) حفظ تحضير درس وتثبيت نشاط المعلم
-- -------------------------------------------------------------
create or replace function public.save_lesson_plan(
  p_session_id uuid,
  p_title text,
  p_objectives text default null,
  p_lesson_summary text default null,
  p_resources text default null,
  p_homework_hint text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s record;
  plan_id uuid;
  v_uid uuid := auth.uid();
begin
  select * into s
  from public.class_sessions
  where id = p_session_id;

  if s.id is null then
    return jsonb_build_object('ok', false, 'message', 'الحصة غير موجودة');
  end if;

  if v_uid is not null and s.teacher_id <> v_uid and not public.current_user_is_admin() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تحضير هذه الحصة');
  end if;

  insert into public.lesson_plans (
    class_session_id,
    teacher_id,
    title,
    objectives,
    lesson_summary,
    resources,
    homework_hint,
    status
  ) values (
    s.id,
    s.teacher_id,
    coalesce(nullif(trim(p_title),''),'تحضير درس'),
    p_objectives,
    p_lesson_summary,
    p_resources,
    p_homework_hint,
    'prepared'
  )
  on conflict (class_session_id, teacher_id) do update
  set title = excluded.title,
      objectives = excluded.objectives,
      lesson_summary = excluded.lesson_summary,
      resources = excluded.resources,
      homework_hint = excluded.homework_hint,
      status = 'prepared',
      updated_at = now()
  returning id into plan_id;

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
    s.id,
    s.teacher_id,
    'lesson_note',
    'lesson_plans',
    plan_id,
    1,
    'تم تثبيت نشاط بسبب تحضير درس',
    v_uid
  ) on conflict do nothing;

  update public.class_sessions
  set status = 'completed', updated_at = now()
  where id = s.id;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ التحضير وتثبيت نشاط المعلم', 'lesson_plan_id', plan_id);
end;
$$;

grant execute on function public.save_lesson_plan(uuid,text,text,text,text,text) to authenticated;

-- -------------------------------------------------------------
-- 5) Trigger: إدخال تقييم مستمر يثبت نشاط grade_entry
-- -------------------------------------------------------------
create or replace function public.log_teacher_activity_from_continuous_assessment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cs_id uuid;
begin
  cs_id := new.class_session_id;

  if cs_id is null then
    select id into cs_id
    from public.class_sessions
    where teacher_id = new.teacher_id
      and class_id = new.class_id
      and subject_id = new.subject_id
      and session_date = new.assessment_date
    order by period_number
    limit 1;
  end if;

  if new.teacher_id is not null and cs_id is not null then
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
      cs_id,
      new.teacher_id,
      'grade_entry',
      'continuous_assessments',
      new.id,
      1,
      'تم تسجيل نشاط بسبب إدخال تقييم مستمر',
      new.created_by
    ) on conflict do nothing;

    update public.class_sessions
    set status = 'completed', updated_at = now()
    where id = cs_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_continuous_assessment_teacher_activity on public.continuous_assessments;
create trigger trg_continuous_assessment_teacher_activity
  after insert on public.continuous_assessments
  for each row execute function public.log_teacher_activity_from_continuous_assessment();

-- -------------------------------------------------------------
-- 6) Trigger: إدخال درجات اختبار يثبت نشاط grade_entry
-- -------------------------------------------------------------
create or replace function public.log_teacher_activity_from_exam_score()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  e record;
  cs_id uuid;
begin
  select * into e
  from public.exams
  where id = new.exam_id;

  cs_id := e.class_session_id;

  if cs_id is null then
    select id into cs_id
    from public.class_sessions
    where teacher_id = e.teacher_id
      and class_id = e.class_id
      and subject_id = e.subject_id
      and session_date = coalesce(e.exam_date, current_date)
    order by period_number
    limit 1;
  end if;

  if e.teacher_id is not null and cs_id is not null then
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
      cs_id,
      e.teacher_id,
      'grade_entry',
      'exam_scores',
      new.id,
      1,
      'تم تسجيل نشاط بسبب إدخال درجة اختبار',
      new.entered_by
    ) on conflict do nothing;

    update public.class_sessions
    set status = 'completed', updated_at = now()
    where id = cs_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_exam_score_teacher_activity on public.exam_scores;
create trigger trg_exam_score_teacher_activity
  after insert on public.exam_scores
  for each row execute function public.log_teacher_activity_from_exam_score();

-- -------------------------------------------------------------
-- 7) View تنبيهات الطلاب للمعلم
-- -------------------------------------------------------------
create or replace view public.v_teacher_student_risk
with (security_invoker=true) as
select
  vts.teacher_id,
  vts.student_id,
  vts.student_name,
  vts.class_name,
  vts.section_code,
  coalesce(absences.absence_count,0) as absence_count,
  coalesce(grades.avg_score,0) as avg_score,
  case
    when coalesce(absences.absence_count,0) >= 3 or coalesce(grades.avg_score,100) < 60 then 'high'
    when coalesce(absences.absence_count,0) >= 1 or coalesce(grades.avg_score,100) < 75 then 'medium'
    else 'normal'
  end as risk_level
from public.v_teacher_students vts
left join lateral (
  select count(*) as absence_count
  from public.attendance a
  where a.student_id = vts.student_id
    and a.status = 'absent'
) absences on true
left join lateral (
  select round(avg(coalesce(g.score,g.grade,g.mark,g.value)::numeric),2) as avg_score
  from public.grades g
  where g.student_id = vts.student_id
) grades on true;

grant select on public.lesson_plans to authenticated;
grant select, insert, update on public.lesson_plans to authenticated;
grant select on public.v_teacher_student_risk to authenticated;

-- -------------------------------------------------------------
-- 8) RLS للدرس والتحضير
-- -------------------------------------------------------------
alter table public.lesson_plans enable row level security;
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='lesson_plans' and policyname='lesson_plans_teacher_read_write') then
    create policy lesson_plans_teacher_read_write on public.lesson_plans
      for all to authenticated
      using (public.current_user_is_admin() or teacher_id = auth.uid())
      with check (public.current_user_is_admin() or teacher_id = auth.uid());
  end if;
end $$;

notify pgrst, 'reload schema';

select 'teacher_daily_workflow_enhanced' as status;

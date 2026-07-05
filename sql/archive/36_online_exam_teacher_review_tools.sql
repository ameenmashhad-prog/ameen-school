-- =============================================================
-- مدارس أمين الرضا (ع) — أدوات المعلم لمراجعة الاختبارات
-- نسخ النموذج، إعادة التصحيح، تغيير الحالة، وتفاصيل الإجابات
-- يكمل SQL 31 إلى 35
-- =============================================================

create extension if not exists pgcrypto;

alter table public.online_exams add column if not exists class_session_id uuid null references public.class_sessions(id) on delete set null;
alter table public.exam_attempts add column if not exists violations_count int not null default 0;
alter table public.exam_attempts add column if not exists last_saved_at timestamptz;
alter table public.exam_attempts add column if not exists client_info jsonb not null default '{}'::jsonb;
alter table public.exam_answers add column if not exists is_draft boolean not null default true;

-- -------------------------------------------------------------
-- 1) تفاصيل إجابات الطلاب للمعلم فقط
-- -------------------------------------------------------------
create or replace view public.v_online_exam_answers_detailed
with (security_invoker=true) as
select
  ans.id as answer_id,
  ans.attempt_id,
  att.exam_id,
  e.title as exam_title,
  e.teacher_id,
  e.class_id,
  c.name as class_name,
  e.section_id,
  sec.code as section_code,
  e.subject_id,
  sub.name as subject_name,
  att.student_id,
  st.name as student_name,
  att.status as attempt_status,
  att.started_at,
  att.submitted_at,
  att.violations_count,
  q.id as question_id,
  q.prompt,
  q.question_type,
  coalesce(oeq.points, q.points, 1) as max_points,
  ans.selected_option_id,
  selected_opt.option_text as selected_option_text,
  ans.answer_text,
  ans.answer_json,
  ans.is_correct,
  ans.score_awarded,
  ans.feedback,
  ans.is_draft,
  ans.answered_at,
  q.correct_answer,
  (
    select string_agg(qo.option_text, '، ' order by qo.sort_order)
    from public.question_options qo
    where qo.question_id = q.id
      and qo.is_correct = true
  ) as correct_option_text,
  q.explanation
from public.exam_answers ans
join public.exam_attempts att on att.id = ans.attempt_id
join public.online_exams e on e.id = att.exam_id
join public.questions q on q.id = ans.question_id
left join public.online_exam_questions oeq on oeq.exam_id = e.id and oeq.question_id = q.id
left join public.question_options selected_opt on selected_opt.id = ans.selected_option_id
left join public.students st on st.id = att.student_id
left join public.classes c on c.id = e.class_id
left join public.sections sec on sec.id = e.section_id
left join public.subjects sub on sub.id = e.subject_id
where public.current_user_is_admin()
   or e.teacher_id = auth.uid();

grant select on public.v_online_exam_answers_detailed to authenticated;

-- -------------------------------------------------------------
-- 2) تغيير حالة النموذج بسرعة: مسودة/منشور/مغلق/مؤرشف
-- -------------------------------------------------------------
create or replace function public.set_online_exam_status(
  p_exam_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  ex record;
begin
  select * into ex from public.online_exams where id = p_exam_id;

  if ex.id is null then
    return jsonb_build_object('ok', false, 'message', 'النموذج الامتحاني غير موجود');
  end if;

  if not (public.current_user_is_admin() or ex.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل هذا النموذج');
  end if;

  if p_status not in ('draft','published','closed','archived') then
    return jsonb_build_object('ok', false, 'message', 'حالة الاختبار غير صحيحة');
  end if;

  update public.online_exams
  set status = p_status,
      updated_at = now()
  where id = p_exam_id;

  return jsonb_build_object('ok', true, 'message', 'تم تغيير حالة النموذج', 'status', p_status);
end;
$$;

grant execute on function public.set_online_exam_status(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 3) نسخ النموذج الامتحاني بدون نسخ محاولات الطلاب
-- -------------------------------------------------------------
create or replace function public.clone_online_exam_model(
  p_exam_id uuid,
  p_new_title text default null,
  p_status text default 'draft'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  ex record;
  new_id uuid;
  q_count int := 0;
begin
  select * into ex from public.online_exams where id = p_exam_id;

  if ex.id is null then
    return jsonb_build_object('ok', false, 'message', 'النموذج الامتحاني غير موجود');
  end if;

  if not (public.current_user_is_admin() or ex.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية نسخ هذا النموذج');
  end if;

  if p_status not in ('draft','published','closed','archived') then
    p_status := 'draft';
  end if;

  insert into public.online_exams(
    academic_year,
    academic_period_id,
    linked_exam_id,
    title,
    description,
    teacher_id,
    class_id,
    section_id,
    subject_id,
    class_session_id,
    duration_minutes,
    start_at,
    end_at,
    status,
    shuffle_questions,
    shuffle_options,
    show_result,
    max_attempts,
    total_points
  ) values (
    ex.academic_year,
    ex.academic_period_id,
    null,
    coalesce(nullif(trim(p_new_title),''), ex.title || ' — نسخة'),
    ex.description,
    ex.teacher_id,
    ex.class_id,
    ex.section_id,
    ex.subject_id,
    ex.class_session_id,
    ex.duration_minutes,
    null,
    null,
    p_status,
    ex.shuffle_questions,
    ex.shuffle_options,
    ex.show_result,
    ex.max_attempts,
    ex.total_points
  ) returning id into new_id;

  insert into public.online_exam_questions(exam_id, question_id, points, sort_order)
  select new_id, question_id, points, sort_order
  from public.online_exam_questions
  where exam_id = p_exam_id
  order by sort_order;

  select count(*) into q_count
  from public.online_exam_questions
  where exam_id = new_id;

  return jsonb_build_object(
    'ok', true,
    'message', 'تم نسخ النموذج الامتحاني كمسودة جديدة',
    'exam_id', new_id,
    'questions_count', q_count
  );
end;
$$;

grant execute on function public.clone_online_exam_model(uuid,text,text) to authenticated;

-- -------------------------------------------------------------
-- 4) إعادة تصحيح محاولة أو نموذج كامل
-- -------------------------------------------------------------
create or replace function public.regrade_online_exam_attempt(
  p_attempt_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  att record;
  ex record;
  result jsonb;
begin
  select * into att from public.exam_attempts where id = p_attempt_id;
  if att.id is null then
    return jsonb_build_object('ok', false, 'message', 'المحاولة غير موجودة');
  end if;

  select * into ex from public.online_exams where id = att.exam_id;
  if ex.id is null then
    return jsonb_build_object('ok', false, 'message', 'النموذج غير موجود');
  end if;

  if not (public.current_user_is_admin() or ex.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إعادة التصحيح');
  end if;

  if att.status not in ('submitted','graded') then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن إعادة تصحيح محاولة غير مسلّمة');
  end if;

  result := public.grade_online_exam_attempt(p_attempt_id);
  return jsonb_build_object('ok', true, 'message', 'تمت إعادة تصحيح المحاولة', 'grading', result);
end;
$$;

grant execute on function public.regrade_online_exam_attempt(uuid) to authenticated;

create or replace function public.regrade_online_exam(
  p_exam_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  ex record;
  att record;
  v_count int := 0;
  v_last jsonb;
begin
  select * into ex from public.online_exams where id = p_exam_id;
  if ex.id is null then
    return jsonb_build_object('ok', false, 'message', 'النموذج الامتحاني غير موجود');
  end if;

  if not (public.current_user_is_admin() or ex.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إعادة التصحيح');
  end if;

  for att in
    select * from public.exam_attempts
    where exam_id = p_exam_id
      and status in ('submitted','graded')
  loop
    v_last := public.grade_online_exam_attempt(att.id);
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'message', 'تمت إعادة تصحيح النموذج',
    'attempts_count', v_count,
    'last_result', v_last
  );
end;
$$;

grant execute on function public.regrade_online_exam(uuid) to authenticated;

notify pgrst, 'reload schema';

select 'online_exam_teacher_review_tools_ready' as status;

-- =============================================================
-- مدارس أمين الرضا (ع) — تحسين الاختبارات الإلكترونية
-- حفظ تلقائي، ربط بالحصة، مخالفات بسيطة، تصحيح يدوي، تحليلات
-- =============================================================

create extension if not exists pgcrypto;

-- ربط الاختبار بحصة فعلية إن رغبت المعلمة.
alter table public.online_exams add column if not exists class_session_id uuid null references public.class_sessions(id) on delete set null;

-- بيانات محاولة الاختبار
alter table public.exam_attempts add column if not exists violations_count int not null default 0;
alter table public.exam_attempts add column if not exists last_saved_at timestamptz;
alter table public.exam_attempts add column if not exists client_info jsonb not null default '{}'::jsonb;

-- إجابات المسودة
alter table public.exam_answers add column if not exists is_draft boolean not null default true;

-- -------------------------------------------------------------
-- حفظ تلقائي لإجابة واحدة أثناء الاختبار
-- -------------------------------------------------------------
create or replace function public.save_exam_answer_draft(
  p_attempt_id uuid,
  p_question_id uuid,
  p_selected_option_id uuid default null,
  p_answer_text text default null,
  p_answer_json jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  att record;
  st record;
begin
  select * into att
  from public.exam_attempts
  where id = p_attempt_id;

  if att.id is null then
    return jsonb_build_object('ok', false, 'message', 'المحاولة غير موجودة');
  end if;

  if att.status <> 'in_progress' then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن تعديل محاولة منتهية');
  end if;

  select * into st
  from public.students
  where id = att.student_id;

  if st.user_id is distinct from auth.uid() and not public.current_user_is_admin() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية حفظ هذه الإجابة');
  end if;

  insert into public.exam_answers(
    attempt_id,
    question_id,
    selected_option_id,
    answer_text,
    answer_json,
    is_draft,
    answered_at
  ) values (
    p_attempt_id,
    p_question_id,
    p_selected_option_id,
    p_answer_text,
    coalesce(p_answer_json,'{}'::jsonb),
    true,
    now()
  )
  on conflict (attempt_id, question_id) do update
  set selected_option_id = excluded.selected_option_id,
      answer_text = excluded.answer_text,
      answer_json = excluded.answer_json,
      is_draft = true,
      answered_at = now();

  update public.exam_attempts
  set last_saved_at = now()
  where id = p_attempt_id;

  return jsonb_build_object('ok', true, 'message', 'تم الحفظ التلقائي');
end;
$$;

grant execute on function public.save_exam_answer_draft(uuid,uuid,uuid,text,jsonb) to authenticated;

-- -------------------------------------------------------------
-- تسجيل مخالفة بسيطة أثناء الاختبار، مثل مغادرة الصفحة.
-- -------------------------------------------------------------
create or replace function public.record_exam_attempt_violation(
  p_attempt_id uuid,
  p_reason text default 'visibility_change'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  att record;
  st record;
begin
  select * into att from public.exam_attempts where id = p_attempt_id;
  if att.id is null then
    return jsonb_build_object('ok', false, 'message', 'المحاولة غير موجودة');
  end if;

  select * into st from public.students where id = att.student_id;
  if st.user_id is distinct from auth.uid() and not public.current_user_is_admin() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تسجيل المخالفة');
  end if;

  update public.exam_attempts
  set violations_count = coalesce(violations_count,0) + 1,
      client_info = coalesce(client_info,'{}'::jsonb) || jsonb_build_object('last_violation', p_reason, 'last_violation_at', now())
  where id = p_attempt_id;

  return jsonb_build_object('ok', true, 'message', 'تم تسجيل المخالفة');
end;
$$;

grant execute on function public.record_exam_attempt_violation(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- تسليم الاختبار: يجعل الإجابات نهائية ثم يصحح.
-- -------------------------------------------------------------
create or replace function public.submit_online_exam_attempt(p_attempt_id uuid, p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  att record;
  ex record;
  st record;
  a jsonb;
  qid uuid;
  opt_id uuid;
  txt text;
  answer_json jsonb;
  grade_result jsonb;
begin
  select * into att from public.exam_attempts where id = p_attempt_id;
  if att.id is null then
    return jsonb_build_object('ok', false, 'message', 'المحاولة غير موجودة');
  end if;

  select * into ex from public.online_exams where id = att.exam_id;
  if ex.id is null then
    return jsonb_build_object('ok', false, 'message', 'الاختبار غير موجود');
  end if;

  select * into st from public.students where id = att.student_id;

  if not (
    public.current_user_is_admin()
    or ex.teacher_id = auth.uid()
    or st.user_id = auth.uid()
  ) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تسليم هذه المحاولة');
  end if;

  if att.status not in ('in_progress','submitted') then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن تعديل محاولة منتهية');
  end if;

  for a in select * from jsonb_array_elements(coalesce(p_answers, '[]'::jsonb)) loop
    qid := nullif(a->>'question_id','')::uuid;
    opt_id := nullif(a->>'selected_option_id','')::uuid;
    txt := a->>'answer_text';
    answer_json := coalesce(a->'answer_json','{}'::jsonb);

    if qid is not null then
      insert into public.exam_answers(
        attempt_id,
        question_id,
        selected_option_id,
        answer_text,
        answer_json,
        is_draft,
        answered_at
      ) values (
        p_attempt_id,
        qid,
        opt_id,
        txt,
        answer_json,
        false,
        now()
      )
      on conflict (attempt_id, question_id) do update
      set selected_option_id = excluded.selected_option_id,
          answer_text = excluded.answer_text,
          answer_json = excluded.answer_json,
          is_draft = false,
          answered_at = now();
    end if;
  end loop;

  update public.exam_answers
  set is_draft = false
  where attempt_id = p_attempt_id;

  update public.exam_attempts
  set status = 'submitted', submitted_at = now(), last_saved_at = now()
  where id = p_attempt_id;

  grade_result := public.grade_online_exam_attempt(p_attempt_id);

  return jsonb_build_object('ok', true, 'message', 'تم تسليم الاختبار', 'grading', grade_result);
end;
$$;

grant execute on function public.submit_online_exam_attempt(uuid,jsonb) to authenticated;

-- -------------------------------------------------------------
-- تصحيح يدوي لسؤال مقالي/صوري/صوتي أو أي إجابة
-- -------------------------------------------------------------
create or replace function public.manual_grade_exam_answer(
  p_answer_id uuid,
  p_score numeric,
  p_feedback text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  ans record;
  att record;
  ex record;
  grade_result jsonb;
begin
  select * into ans from public.exam_answers where id = p_answer_id;
  if ans.id is null then
    return jsonb_build_object('ok', false, 'message', 'الإجابة غير موجودة');
  end if;

  select * into att from public.exam_attempts where id = ans.attempt_id;
  select * into ex from public.online_exams where id = att.exam_id;

  if not (public.current_user_is_admin() or ex.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تصحيح هذه الإجابة');
  end if;

  update public.exam_answers
  set score_awarded = greatest(coalesce(p_score,0),0),
      feedback = p_feedback,
      is_correct = null
  where id = p_answer_id;

  grade_result := public.grade_online_exam_attempt(att.id);

  return jsonb_build_object('ok', true, 'message', 'تم التصحيح اليدوي', 'grading', grade_result);
end;
$$;

grant execute on function public.manual_grade_exam_answer(uuid,numeric,text) to authenticated;

-- -------------------------------------------------------------
-- Views للتحليل
-- -------------------------------------------------------------
create or replace view public.v_online_exam_analysis
with (security_invoker=true) as
select
  e.id as exam_id,
  e.title,
  e.teacher_id,
  u.name as teacher_name,
  e.class_id,
  c.name as class_name,
  e.section_id,
  sec.code as section_code,
  e.subject_id,
  sub.name as subject_name,
  count(a.id) as attempts_count,
  count(a.id) filter (where a.status in ('submitted','graded')) as submitted_count,
  round(avg(case when a.max_score > 0 then a.score / a.max_score * 100 end),2) as average_percent,
  max(case when a.max_score > 0 then a.score / a.max_score * 100 end) as highest_percent,
  min(case when a.max_score > 0 then a.score / a.max_score * 100 end) as lowest_percent,
  avg(a.violations_count) as avg_violations,
  e.status,
  e.created_at
from public.online_exams e
left join public.exam_attempts a on a.exam_id = e.id
left join public.users u on u.id = e.teacher_id
left join public.classes c on c.id = e.class_id
left join public.sections sec on sec.id = e.section_id
left join public.subjects sub on sub.id = e.subject_id
group by e.id, e.title, e.teacher_id, u.name, e.class_id, c.name, e.section_id, sec.code, e.subject_id, sub.name, e.status, e.created_at;

create or replace view public.v_online_exam_question_analysis
with (security_invoker=true) as
select
  e.id as exam_id,
  e.title as exam_title,
  q.id as question_id,
  q.prompt,
  q.question_type,
  count(ans.id) as answers_count,
  count(ans.id) filter (where ans.is_correct = true) as correct_count,
  round(100.0 * count(ans.id) filter (where ans.is_correct = true) / nullif(count(ans.id),0),2) as correct_percent,
  avg(ans.score_awarded) as average_score
from public.online_exams e
join public.online_exam_questions eq on eq.exam_id = e.id
join public.questions q on q.id = eq.question_id
left join public.exam_attempts att on att.exam_id = e.id
left join public.exam_answers ans on ans.attempt_id = att.id and ans.question_id = q.id
group by e.id, e.title, q.id, q.prompt, q.question_type;

grant select on public.v_online_exam_analysis to authenticated;
grant select on public.v_online_exam_question_analysis to authenticated;

notify pgrst, 'reload schema';

select 'online_exam_enhancements_ready' as status;

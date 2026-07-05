-- =============================================================
-- مدارس أمين الرضا (ع) — متابعة الاختبار واسترجاع المسودات والتقارير
-- يكمل SQL 31/32/33/34
-- =============================================================

create extension if not exists pgcrypto;

alter table public.exam_attempts add column if not exists violations_count int not null default 0;
alter table public.exam_attempts add column if not exists last_saved_at timestamptz;
alter table public.exam_attempts add column if not exists client_info jsonb not null default '{}'::jsonb;
alter table public.exam_answers add column if not exists is_draft boolean not null default true;
alter table public.online_exams add column if not exists class_session_id uuid null references public.class_sessions(id) on delete set null;

-- -------------------------------------------------------------
-- تحديد الطالب الحالي: طالب مباشر أو أول ابن مرتبط بولي الأمر.
-- -------------------------------------------------------------
create or replace function public.online_exam_current_student_id()
returns uuid
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_student_id uuid;
begin
  select s.id into v_student_id
  from public.students s
  where s.user_id = auth.uid()
  limit 1;

  if v_student_id is null then
    select s.id into v_student_id
    from public.students s
    where s.parent_id = auth.uid()
    limit 1;
  end if;

  return v_student_id;
end;
$$;

grant execute on function public.online_exam_current_student_id() to authenticated;

-- -------------------------------------------------------------
-- سياسة قراءة إضافية لولي الأمر، بدون تغيير السياسات القديمة.
-- -------------------------------------------------------------
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='online_exams' and policyname='online_exams_parent_child_select') then
    create policy online_exams_parent_child_select on public.online_exams
      for select to authenticated
      using (
        exists(
          select 1
          from public.students s
          where s.parent_id = auth.uid()
            and public.online_exam_student_can_access(id, s.id)
        )
      );
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='exam_attempts' and policyname='exam_attempts_parent_child_read') then
    create policy exam_attempts_parent_child_read on public.exam_attempts
      for select to authenticated
      using (exists(select 1 from public.students s where s.id = student_id and s.parent_id = auth.uid()));
  end if;
end $$;

-- -------------------------------------------------------------
-- بدء/متابعة محاولة الاختبار
-- إذا توجد محاولة in_progress ضمن المدة، يرجع نفس المحاولة بدل إنشاء محاولة جديدة.
-- -------------------------------------------------------------
create or replace function public.start_online_exam_attempt(p_exam_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_attempt public.exam_attempts%rowtype;
  attempts_count int;
  max_allowed int;
  ex public.online_exams%rowtype;
  v_attempt_id uuid;
  v_question_order jsonb := '[]'::jsonb;
  v_now timestamptz := now();
begin
  v_student_id := public.online_exam_current_student_id();

  if v_student_id is null then
    return jsonb_build_object('ok',false,'message','لم يتم العثور على طالب مرتبط بهذا الحساب');
  end if;

  select * into ex from public.online_exams where id = p_exam_id;
  if ex.id is null then
    return jsonb_build_object('ok',false,'message','الاختبار غير موجود');
  end if;

  if not public.online_exam_student_can_access(p_exam_id, v_student_id) then
    return jsonb_build_object('ok',false,'message','الاختبار غير متاح لهذا الطالب أو خارج وقت الاختبار');
  end if;

  -- هل توجد محاولة مفتوحة؟
  select * into v_attempt
  from public.exam_attempts
  where exam_id = p_exam_id
    and student_id = v_student_id
    and status = 'in_progress'
  order by started_at desc
  limit 1;

  if v_attempt.id is not null then
    if v_now > v_attempt.started_at + (coalesce(ex.duration_minutes,30)::text || ' minutes')::interval then
      update public.exam_attempts
      set status = 'expired', submitted_at = coalesce(submitted_at, now())
      where id = v_attempt.id;
      return jsonb_build_object('ok',false,'message','انتهت مدة هذه المحاولة');
    end if;

    -- جهّز ترتيب الأسئلة للمحاولات القديمة التي لا تملك ترتيباً محفوظاً.
    if coalesce(v_attempt.client_info,'{}'::jsonb)->'question_order' is null then
      select coalesce(jsonb_agg(qid), '[]'::jsonb) into v_question_order
      from (
        select oeq.question_id::text as qid
        from public.online_exam_questions oeq
        join public.questions q on q.id = oeq.question_id
        where oeq.exam_id = p_exam_id
          and q.is_active = true
        order by oeq.sort_order, q.created_at
      ) x;

      update public.exam_attempts
      set client_info = coalesce(client_info,'{}'::jsonb) || jsonb_build_object('question_order', v_question_order)
      where id = v_attempt.id;
    end if;

    return jsonb_build_object('ok',true,'attempt_id',v_attempt.id,'resumed',true,'message','تمت متابعة المحاولة السابقة');
  end if;

  select max_attempts into max_allowed from public.online_exams where id = p_exam_id;
  select count(*) into attempts_count
  from public.exam_attempts
  where exam_id = p_exam_id
    and student_id = v_student_id
    and status in ('submitted','graded','expired');

  if attempts_count >= coalesce(max_allowed,1) then
    return jsonb_build_object('ok',false,'message','تم استنفاد عدد المحاولات المسموح');
  end if;

  select coalesce(jsonb_agg(qid), '[]'::jsonb) into v_question_order
  from (
    select oeq.question_id::text as qid
    from public.online_exam_questions oeq
    join public.questions q on q.id = oeq.question_id
    where oeq.exam_id = p_exam_id
      and q.is_active = true
    order by case when coalesce(ex.shuffle_questions,true) then random() else oeq.sort_order end, oeq.sort_order, q.created_at
  ) x;

  insert into public.exam_attempts(exam_id, student_id, client_info)
  values (p_exam_id, v_student_id, jsonb_build_object('question_order', v_question_order))
  returning id into v_attempt_id;

  return jsonb_build_object('ok',true,'attempt_id',v_attempt_id,'resumed',false,'message','تم بدء الاختبار');
end;
$$;

grant execute on function public.start_online_exam_attempt(uuid) to authenticated;

-- -------------------------------------------------------------
-- تحميل الاختبار مع إجابات المسودة بدون كشف الإجابات الصحيحة.
-- -------------------------------------------------------------
create or replace function public.get_online_exam_payload(p_exam_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  ex public.online_exams%rowtype;
  st_id uuid;
  can_access boolean := false;
  q record;
  opt jsonb;
  qs jsonb := '[]'::jsonb;
  current_attempt public.exam_attempts%rowtype;
  draft_answers jsonb := '[]'::jsonb;
  question_order jsonb := '[]'::jsonb;
begin
  select * into ex from public.online_exams where id = p_exam_id;
  if ex.id is null then
    return jsonb_build_object('ok', false, 'message', 'الاختبار غير موجود');
  end if;

  st_id := public.online_exam_current_student_id();

  can_access := public.current_user_is_admin()
    or ex.teacher_id = auth.uid()
    or (st_id is not null and public.online_exam_student_can_access(p_exam_id, st_id));

  if not can_access then
    return jsonb_build_object('ok', false, 'message', 'الاختبار غير متاح لهذا الحساب');
  end if;

  if st_id is not null then
    select * into current_attempt
    from public.exam_attempts
    where exam_id = p_exam_id
      and student_id = st_id
      and status = 'in_progress'
    order by started_at desc
    limit 1;
  end if;

  question_order := coalesce(current_attempt.client_info->'question_order','[]'::jsonb);

  if current_attempt.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'question_id', ea.question_id,
      'selected_option_id', ea.selected_option_id,
      'answer_text', ea.answer_text,
      'answer_json', ea.answer_json,
      'is_draft', ea.is_draft,
      'answered_at', ea.answered_at
    ) order by ea.answered_at), '[]'::jsonb)
    into draft_answers
    from public.exam_answers ea
    where ea.attempt_id = current_attempt.id;
  end if;

  for q in
    select q.*, oeq.points as exam_points, oeq.sort_order, qo.ord as saved_order
    from public.online_exam_questions oeq
    join public.questions q on q.id = oeq.question_id
    left join lateral (
      select j.ord::int
      from jsonb_array_elements_text(question_order) with ordinality as j(qid, ord)
      where j.qid = q.id::text
      limit 1
    ) qo on true
    where oeq.exam_id = p_exam_id
      and q.is_active = true
    order by coalesce(qo.ord, 999999), oeq.sort_order, q.created_at
  loop
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'text', option_text, 'sort_order', sort_order) order by sort_order), '[]'::jsonb)
    into opt
    from public.question_options
    where question_id = q.id;

    qs := qs || jsonb_build_array(jsonb_build_object(
      'id', q.id,
      'question_type', q.question_type,
      'prompt', q.prompt,
      'media_type', q.media_type,
      'media_url', q.media_url,
      'points', coalesce(q.exam_points, q.points, 1),
      'difficulty', q.difficulty,
      'auto_grade', q.auto_grade,
      'options', opt
    ));
  end loop;

  return jsonb_build_object(
    'ok', true,
    'exam', jsonb_build_object(
      'id', ex.id,
      'title', ex.title,
      'description', ex.description,
      'duration_minutes', ex.duration_minutes,
      'start_at', ex.start_at,
      'end_at', ex.end_at,
      'show_result', ex.show_result,
      'status', ex.status,
      'total_points', ex.total_points
    ),
    'attempt', case when current_attempt.id is not null then jsonb_build_object(
      'id', current_attempt.id,
      'started_at', current_attempt.started_at,
      'status', current_attempt.status,
      'last_saved_at', current_attempt.last_saved_at,
      'violations_count', current_attempt.violations_count
    ) else null end,
    'draft_answers', draft_answers,
    'questions', qs
  );
end;
$$;

grant execute on function public.get_online_exam_payload(uuid) to authenticated;

-- -------------------------------------------------------------
-- تقرير تفصيلي لمحاولات الطلاب للمعلم.
-- -------------------------------------------------------------
create or replace view public.v_online_exam_attempts_detailed
with (security_invoker=true) as
select
  a.id as attempt_id,
  a.exam_id,
  e.title as exam_title,
  e.teacher_id,
  e.class_id,
  c.name as class_name,
  e.section_id,
  sec.code as section_code,
  e.subject_id,
  sub.name as subject_name,
  a.student_id,
  s.name as student_name,
  a.started_at,
  a.submitted_at,
  a.status,
  a.score,
  a.max_score,
  case when a.max_score > 0 then round(a.score / a.max_score * 100,2) end as percent,
  a.violations_count,
  a.last_saved_at,
  count(ans.id) as answered_count
from public.exam_attempts a
join public.online_exams e on e.id = a.exam_id
left join public.students s on s.id = a.student_id
left join public.classes c on c.id = e.class_id
left join public.sections sec on sec.id = e.section_id
left join public.subjects sub on sub.id = e.subject_id
left join public.exam_answers ans on ans.attempt_id = a.id
group by a.id, e.id, e.title, e.teacher_id, e.class_id, c.name, e.section_id, sec.code, e.subject_id, sub.name, a.student_id, s.name, a.started_at, a.submitted_at, a.status, a.score, a.max_score, a.violations_count, a.last_saved_at;

grant select on public.v_online_exam_attempts_detailed to authenticated;

notify pgrst, 'reload schema';

select 'online_exam_resume_drafts_reports_ready' as status;

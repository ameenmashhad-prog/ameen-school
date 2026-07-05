-- =============================================================
-- مدارس أمين الرضا (ع) — دوال واجهة الاختبارات الإلكترونية
-- get_online_exam_payload: يجلب الاختبار بدون كشف الإجابات الصحيحة للطالب
-- submit_online_exam_attempt: يحفظ الإجابات ويصحح تلقائياً ما يمكن تصحيحه
-- =============================================================

create extension if not exists pgcrypto;

create or replace function public.get_online_exam_payload(p_exam_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  ex record;
  st_id uuid;
  can_access boolean := false;
  q record;
  opt jsonb;
  qs jsonb := '[]'::jsonb;
  current_attempt record;
begin
  select * into ex from public.online_exams where id = p_exam_id;
  if ex.id is null then
    return jsonb_build_object('ok', false, 'message', 'الاختبار غير موجود');
  end if;

  select id into st_id from public.students where user_id = auth.uid() limit 1;

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

  for q in
    select q.*, oeq.points as exam_points, oeq.sort_order
    from public.online_exam_questions oeq
    join public.questions q on q.id = oeq.question_id
    where oeq.exam_id = p_exam_id
      and q.is_active = true
    order by case when ex.shuffle_questions then random() else oeq.sort_order end, q.created_at
  loop
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'text', option_text, 'sort_order', sort_order) order by case when ex.shuffle_options then random() else sort_order end), '[]'::jsonb)
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
    'attempt', case when current_attempt.id is not null then jsonb_build_object('id', current_attempt.id, 'started_at', current_attempt.started_at, 'status', current_attempt.status) else null end,
    'questions', qs
  );
end;
$$;

grant execute on function public.get_online_exam_payload(uuid) to authenticated;

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
        answer_json
      ) values (
        p_attempt_id,
        qid,
        opt_id,
        txt,
        answer_json
      )
      on conflict (attempt_id, question_id) do update
      set selected_option_id = excluded.selected_option_id,
          answer_text = excluded.answer_text,
          answer_json = excluded.answer_json,
          answered_at = now();
    end if;
  end loop;

  update public.exam_attempts
  set status = 'submitted', submitted_at = now()
  where id = p_attempt_id;

  grade_result := public.grade_online_exam_attempt(p_attempt_id);

  return jsonb_build_object('ok', true, 'message', 'تم تسليم الاختبار', 'grading', grade_result);
end;
$$;

grant execute on function public.submit_online_exam_attempt(uuid,jsonb) to authenticated;

notify pgrst, 'reload schema';

select 'online_exam_payload_submit_ready' as status;

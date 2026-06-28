-- =============================================================
-- مدارس أمين الرضا (ع) — أنواع الأسئلة المتقدمة والتصحيح الآلي
-- يدعم: متعدد الإجابات، المطابقة، الترتيب، تحديد الخطأ، الفراغات المرنة
-- يكمل SQL 31 إلى 36
-- =============================================================

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

alter table public.exam_answers add column if not exists is_draft boolean not null default true;
alter table public.exam_attempts add column if not exists client_info jsonb not null default '{}'::jsonb;
alter table public.exam_attempts add column if not exists last_saved_at timestamptz;
alter table public.exam_attempts add column if not exists violations_count int not null default 0;

-- -------------------------------------------------------------
-- 1) توسيع أنواع الأسئلة
-- -------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'questions'
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) like '%question_type%'
  loop
    execute format('alter table public.questions drop constraint if exists %I', r.conname);
  end loop;
end $$;

alter table public.questions
  add constraint questions_question_type_check
  check (question_type in (
    'mcq',
    'true_false',
    'fill_blank',
    'matching',
    'essay',
    'image',
    'audio',
    'multi_select',
    'ordering',
    'identify_error',
    'reading_comprehension',
    'dialog_completion',
    'grammar_correction',
    'problem_solving',
    'comparison',
    'cause_effect',
    'scenario'
  )) not valid;

alter table public.questions validate constraint questions_question_type_check;

-- -------------------------------------------------------------
-- 2) تطبيع النص للمقارنة المرنة في الفراغات والتصحيح النصي
-- -------------------------------------------------------------
create or replace function public.exam_norm_text(p_text text)
returns text
language plpgsql
immutable
as $$
declare
  v text := coalesce(p_text,'');
begin
  v := lower(v);
  v := translate(v, 'ًٌٍَُِّْـ', '');
  v := replace(v, 'أ', 'ا');
  v := replace(v, 'إ', 'ا');
  v := replace(v, 'آ', 'ا');
  v := replace(v, 'ٱ', 'ا');
  v := replace(v, 'ى', 'ي');
  v := replace(v, 'ة', 'ه');
  v := replace(v, 'ؤ', 'و');
  v := replace(v, 'ئ', 'ي');
  v := replace(v, '،', ' ');
  v := replace(v, '؛', ' ');
  v := replace(v, '؟', ' ');
  v := regexp_replace(v, '[[:punct:]]+', ' ', 'g');
  v := regexp_replace(v, '[[:space:]]+', ' ', 'g');
  return btrim(v);
end;
$$;

grant execute on function public.exam_norm_text(text) to authenticated;

create or replace function public.exam_text_matches(
  p_answer text,
  p_correct text,
  p_alternatives jsonb default '[]'::jsonb
)
returns boolean
language plpgsql
immutable
as $$
declare
  a text := public.exam_norm_text(p_answer);
  c text;
  alt text;
begin
  if a = '' then
    return false;
  end if;

  c := public.exam_norm_text(p_correct);
  if c <> '' and (a = c or similarity(a,c) >= 0.72) then
    return true;
  end if;

  if p_alternatives is not null and jsonb_typeof(p_alternatives) = 'array' then
    for alt in select value from jsonb_array_elements_text(p_alternatives) loop
      c := public.exam_norm_text(alt);
      if c <> '' and (a = c or similarity(a,c) >= 0.72) then
        return true;
      end if;
    end loop;
  end if;

  return false;
end;
$$;

grant execute on function public.exam_text_matches(text,text,jsonb) to authenticated;

-- -------------------------------------------------------------
-- 3) إنشاء/تعديل سؤال متقدم مع خيارات أو JSON للإجابة الصحيحة
-- -------------------------------------------------------------
create or replace function public.upsert_question_advanced(
  p_question_id uuid,
  p_bank_id uuid,
  p_question_type text,
  p_prompt text,
  p_points numeric,
  p_correct_answer text,
  p_explanation text,
  p_options jsonb default '[]'::jsonb,
  p_correct_answer_json jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b record;
  q record;
  opt jsonb;
  v_question_id uuid;
  v_attempts_count int := 0;
  v_correct_count int := 0;
  v_order int := 0;
  option_types text[] := array['mcq','true_false','multi_select','identify_error'];
begin
  if p_bank_id is null then
    return jsonb_build_object('ok', false, 'message', 'اختاري بنك الأسئلة');
  end if;

  select * into b from public.question_banks where id = p_bank_id;
  if b.id is null then
    return jsonb_build_object('ok', false, 'message', 'بنك الأسئلة غير موجود');
  end if;

  if not (public.current_user_is_admin() or b.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية على هذا البنك');
  end if;

  if p_question_type not in (
    'mcq','true_false','fill_blank','matching','essay','image','audio','multi_select','ordering','identify_error',
    'reading_comprehension','dialog_completion','grammar_correction','problem_solving','comparison','cause_effect','scenario'
  ) then
    return jsonb_build_object('ok', false, 'message', 'نوع السؤال غير صحيح');
  end if;

  if nullif(trim(coalesce(p_prompt,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'نص السؤال مطلوب');
  end if;

  if coalesce(p_points,0) <= 0 then
    return jsonb_build_object('ok', false, 'message', 'درجة السؤال يجب أن تكون أكبر من صفر');
  end if;

  if p_question_type = any(option_types) then
    if jsonb_array_length(coalesce(p_options,'[]'::jsonb)) < 2 then
      return jsonb_build_object('ok', false, 'message', 'يجب إدخال خيارين على الأقل');
    end if;

    select count(*) into v_correct_count
    from jsonb_array_elements(coalesce(p_options,'[]'::jsonb)) as x(value)
    where coalesce((x.value->>'is_correct')::boolean, false) = true;

    if v_correct_count = 0 then
      return jsonb_build_object('ok', false, 'message', 'حددي إجابة صحيحة بعلامة *');
    end if;
  end if;

  if p_question_type = 'matching'
     and jsonb_array_length(coalesce(p_correct_answer_json->'pairs','[]'::jsonb)) = 0 then
    return jsonb_build_object('ok', false, 'message', 'أدخلي أزواج المطابقة بصيغة: عنصر = مقابل');
  end if;

  if p_question_type = 'ordering'
     and jsonb_array_length(coalesce(p_correct_answer_json->'items','[]'::jsonb)) = 0 then
    return jsonb_build_object('ok', false, 'message', 'أدخلي عناصر الترتيب كل عنصر في سطر');
  end if;

  if p_question_id is not null then
    select * into q from public.questions where id = p_question_id;

    if q.id is null then
      return jsonb_build_object('ok', false, 'message', 'السؤال غير موجود');
    end if;

    if not (public.current_user_is_admin() or q.teacher_id = auth.uid()) then
      return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل هذا السؤال');
    end if;

    select count(*) into v_attempts_count
    from public.online_exam_questions oeq
    join public.exam_attempts ea on ea.exam_id = oeq.exam_id
    where oeq.question_id = p_question_id;

    if v_attempts_count > 0 then
      return jsonb_build_object(
        'ok', false,
        'message', 'لا يمكن تعديل هذا السؤال لأنه مستخدم في محاولات طلاب. أنشئي سؤالاً جديداً أو انسخي النموذج.',
        'locked_attempts', v_attempts_count
      );
    end if;

    update public.questions
    set bank_id = b.id,
        class_id = b.class_id,
        section_id = b.section_id,
        subject_id = b.subject_id,
        question_type = p_question_type,
        prompt = trim(p_prompt),
        points = p_points,
        correct_answer = nullif(p_correct_answer,''),
        correct_answer_json = coalesce(p_correct_answer_json,'{}'::jsonb),
        explanation = nullif(p_explanation,''),
        auto_grade = p_question_type not in ('essay','reading_comprehension','dialog_completion','grammar_correction','problem_solving','comparison','cause_effect','scenario','image','audio'),
        is_active = true,
        updated_at = now()
    where id = p_question_id
    returning id into v_question_id;

    delete from public.question_options where question_id = v_question_id;
  else
    insert into public.questions(
      bank_id, teacher_id, class_id, section_id, subject_id,
      question_type, prompt, points, correct_answer, correct_answer_json, explanation, auto_grade, is_active
    ) values (
      b.id, b.teacher_id, b.class_id, b.section_id, b.subject_id,
      p_question_type, trim(p_prompt), p_points, nullif(p_correct_answer,''), coalesce(p_correct_answer_json,'{}'::jsonb), nullif(p_explanation,''),
      p_question_type not in ('essay','reading_comprehension','dialog_completion','grammar_correction','problem_solving','comparison','cause_effect','scenario','image','audio'),
      true
    ) returning id into v_question_id;
  end if;

  if p_question_type = any(option_types) then
    v_order := 0;
    for opt in select value from jsonb_array_elements(coalesce(p_options,'[]'::jsonb)) as x(value) loop
      if nullif(trim(coalesce(opt->>'text','')), '') is not null then
        insert into public.question_options(question_id, option_text, is_correct, sort_order)
        values (
          v_question_id,
          trim(opt->>'text'),
          coalesce((opt->>'is_correct')::boolean, false),
          coalesce((opt->>'sort_order')::int, v_order)
        );
        v_order := v_order + 1;
      end if;
    end loop;
  end if;

  update public.online_exam_questions oeq
  set points = p_points
  where oeq.question_id = v_question_id
    and not exists(select 1 from public.exam_attempts ea where ea.exam_id = oeq.exam_id);

  update public.online_exams e
  set total_points = coalesce((select sum(points) from public.online_exam_questions where exam_id = e.id),0),
      updated_at = now()
  where exists(select 1 from public.online_exam_questions oeq where oeq.exam_id = e.id and oeq.question_id = v_question_id)
    and not exists(select 1 from public.exam_attempts ea where ea.exam_id = e.id);

  return jsonb_build_object('ok', true, 'message', case when p_question_id is null then 'تم إنشاء السؤال' else 'تم تعديل السؤال' end, 'question_id', v_question_id);
end;
$$;

grant execute on function public.upsert_question_advanced(uuid,uuid,text,text,numeric,text,text,jsonb,jsonb) to authenticated;

-- -------------------------------------------------------------
-- 4) تحميل الاختبار بدون كشف الإجابات الصحيحة، مع بيانات التفاعل للأسئلة المتقدمة
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
  interaction jsonb;
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
    opt := '[]'::jsonb;
    interaction := '{}'::jsonb;

    if q.question_type in ('mcq','true_false','multi_select','identify_error') then
      select coalesce(jsonb_agg(jsonb_build_object('id', id, 'text', option_text, 'sort_order', sort_order) order by case when ex.shuffle_options then random() else sort_order end), '[]'::jsonb)
      into opt
      from public.question_options
      where question_id = q.id;
    elsif q.question_type = 'matching' then
      interaction := jsonb_build_object(
        'left_items', coalesce((select jsonb_agg(value->>'left' order by ord) from jsonb_array_elements(coalesce(q.correct_answer_json->'pairs','[]'::jsonb)) with ordinality as p(value,ord)), '[]'::jsonb),
        'right_options', coalesce((select jsonb_agg(value->>'right' order by random()) from jsonb_array_elements(coalesce(q.correct_answer_json->'pairs','[]'::jsonb)) as p(value)), '[]'::jsonb)
      );
    elsif q.question_type = 'ordering' then
      interaction := jsonb_build_object(
        'items', coalesce((select jsonb_agg(value order by random()) from jsonb_array_elements_text(coalesce(q.correct_answer_json->'items','[]'::jsonb)) as p(value)), '[]'::jsonb)
      );
    end if;

    qs := qs || jsonb_build_array(jsonb_build_object(
      'id', q.id,
      'question_type', q.question_type,
      'prompt', q.prompt,
      'media_type', q.media_type,
      'media_url', q.media_url,
      'points', coalesce(q.exam_points, q.points, 1),
      'difficulty', q.difficulty,
      'auto_grade', q.auto_grade,
      'options', opt,
      'interaction', interaction
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
-- 5) تصحيح متقدم
-- -------------------------------------------------------------
create or replace function public.grade_online_exam_attempt(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  att record;
  ex record;
  q record;
  ans record;
  v_score numeric := 0;
  v_max numeric := 0;
  awarded numeric := 0;
  max_points numeric := 0;
  linked uuid;
  correct_count int := 0;
  total_count int := 0;
  selected_ids text[];
  correct_ids text[];
begin
  select * into att from public.exam_attempts where id = p_attempt_id;
  if att.id is null then
    return jsonb_build_object('ok',false,'message','المحاولة غير موجودة');
  end if;

  select * into ex from public.online_exams where id = att.exam_id;
  if ex.id is null then
    return jsonb_build_object('ok',false,'message','الاختبار غير موجود');
  end if;

  for q in
    select q.*, oeq.points as exam_points
    from public.online_exam_questions oeq
    join public.questions q on q.id = oeq.question_id
    where oeq.exam_id = ex.id
  loop
    max_points := coalesce(q.exam_points, q.points, 1);
    v_max := v_max + max_points;
    awarded := 0;

    select * into ans
    from public.exam_answers
    where attempt_id = p_attempt_id
      and question_id = q.id;

    if ans.id is not null then
      if q.question_type in ('mcq','true_false','identify_error') then
        if exists(select 1 from public.question_options qo where qo.id = ans.selected_option_id and qo.is_correct = true) then
          awarded := max_points;
        end if;

      elsif q.question_type = 'multi_select' then
        select coalesce(array_agg(id::text order by id::text), array[]::text[]) into correct_ids
        from public.question_options
        where question_id = q.id
          and is_correct = true;

        select coalesce(array_agg(value order by value), array[]::text[]) into selected_ids
        from jsonb_array_elements_text(coalesce(ans.answer_json->'selected_option_ids','[]'::jsonb)) as x(value);

        if correct_ids = selected_ids and array_length(correct_ids,1) is not null then
          awarded := max_points;
        end if;

      elsif q.question_type = 'fill_blank' then
        if public.exam_text_matches(ans.answer_text, q.correct_answer, q.correct_answer_json->'acceptable_answers') then
          awarded := max_points;
        end if;

      elsif q.question_type = 'matching' then
        select count(*) into total_count
        from jsonb_array_elements(coalesce(q.correct_answer_json->'pairs','[]'::jsonb));

        with c as (
          select public.exam_norm_text(value->>'left') as l, public.exam_norm_text(value->>'right') as r
          from jsonb_array_elements(coalesce(q.correct_answer_json->'pairs','[]'::jsonb))
        ),
        s as (
          select public.exam_norm_text(value->>'left') as l, public.exam_norm_text(value->>'right') as r
          from jsonb_array_elements(coalesce(ans.answer_json->'pairs','[]'::jsonb))
        )
        select count(*) into correct_count
        from c join s on c.l = s.l and c.r = s.r;

        if total_count > 0 then
          awarded := round(max_points * correct_count::numeric / total_count::numeric, 2);
        end if;

      elsif q.question_type = 'ordering' then
        select count(*) into total_count
        from jsonb_array_elements_text(coalesce(q.correct_answer_json->'items','[]'::jsonb));

        with c as (
          select ord::int as pos, public.exam_norm_text(value) as item
          from jsonb_array_elements_text(coalesce(q.correct_answer_json->'items','[]'::jsonb)) with ordinality as x(value,ord)
        ),
        s as (
          select ord::int as pos, public.exam_norm_text(value) as item
          from jsonb_array_elements_text(coalesce(ans.answer_json->'items','[]'::jsonb)) with ordinality as x(value,ord)
        )
        select count(*) into correct_count
        from c join s on c.pos = s.pos and c.item = s.item;

        if total_count > 0 then
          awarded := round(max_points * correct_count::numeric / total_count::numeric, 2);
        end if;

      else
        -- الأسئلة التطبيقية/المقالية تصحح يدوياً.
        awarded := coalesce(ans.score_awarded, 0);
      end if;

      update public.exam_answers
      set score_awarded = awarded,
          is_correct = (awarded >= max_points)
      where id = ans.id;
    end if;

    v_score := v_score + awarded;
  end loop;

  update public.exam_attempts
  set status = 'graded',
      submitted_at = coalesce(submitted_at, now()),
      score = v_score,
      max_score = v_max
  where id = p_attempt_id;

  linked := ex.linked_exam_id;
  if linked is null then
    insert into public.exams(
      academic_year,
      academic_period_id,
      class_id,
      subject_id,
      teacher_id,
      exam_name,
      exam_type,
      max_score,
      exam_date,
      class_session_id,
      created_by
    ) values (
      ex.academic_year,
      ex.academic_period_id,
      ex.class_id,
      ex.subject_id,
      ex.teacher_id,
      ex.title,
      'monthly',
      coalesce(v_max,100),
      current_date,
      null,
      ex.teacher_id
    ) returning id into linked;

    update public.online_exams set linked_exam_id = linked where id = ex.id;
  end if;

  insert into public.exam_scores(exam_id, student_id, score, entered_by)
  values (linked, att.student_id, case when v_max > 0 then round(v_score / v_max * 100,2) else 0 end, ex.teacher_id)
  on conflict (exam_id, student_id) do update
  set score = excluded.score,
      entered_by = excluded.entered_by,
      updated_at = now();

  return jsonb_build_object('ok',true,'score',v_score,'max_score',v_max,'percent',case when v_max > 0 then round(v_score / v_max * 100,2) else 0 end);
end;
$$;

grant execute on function public.grade_online_exam_attempt(uuid) to authenticated;

notify pgrst, 'reload schema';

select 'advanced_exam_question_types_ready' as status;

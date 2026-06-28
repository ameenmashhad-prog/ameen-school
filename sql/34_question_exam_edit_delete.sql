-- =============================================================
-- مدارس أمين الرضا (ع) — تعديل/حذف الأسئلة والنماذج الامتحانية
-- آمن: يمنع حذف/تغيير الأسئلة أو بنية الاختبار إذا وجدت محاولات طلاب.
-- =============================================================

create extension if not exists pgcrypto;

alter table public.online_exams add column if not exists class_session_id uuid null references public.class_sessions(id) on delete set null;

-- -------------------------------------------------------------
-- 1) إنشاء/تعديل سؤال مع خياراته
-- -------------------------------------------------------------
create or replace function public.upsert_question_with_options(
  p_question_id uuid,
  p_bank_id uuid,
  p_question_type text,
  p_prompt text,
  p_points numeric,
  p_correct_answer text,
  p_explanation text,
  p_options jsonb default '[]'::jsonb
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
begin
  if p_bank_id is null then
    return jsonb_build_object('ok', false, 'message', 'اختاري بنك الأسئلة');
  end if;

  select * into b
  from public.question_banks
  where id = p_bank_id;

  if b.id is null then
    return jsonb_build_object('ok', false, 'message', 'بنك الأسئلة غير موجود');
  end if;

  if not (public.current_user_is_admin() or b.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية على هذا البنك');
  end if;

  if p_question_type not in ('mcq','true_false','fill_blank','matching','essay','image','audio') then
    return jsonb_build_object('ok', false, 'message', 'نوع السؤال غير صحيح');
  end if;

  if nullif(trim(coalesce(p_prompt,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'نص السؤال مطلوب');
  end if;

  if coalesce(p_points,0) <= 0 then
    return jsonb_build_object('ok', false, 'message', 'درجة السؤال يجب أن تكون أكبر من صفر');
  end if;

  if p_question_type in ('mcq','true_false') then
    if jsonb_array_length(coalesce(p_options,'[]'::jsonb)) < 2 then
      return jsonb_build_object('ok', false, 'message', 'يجب إدخال خيارين على الأقل');
    end if;

    select count(*) into v_correct_count
    from jsonb_array_elements(coalesce(p_options,'[]'::jsonb)) as x(value)
    where coalesce((x.value->>'is_correct')::boolean, false) = true;

    if v_correct_count = 0 then
      return jsonb_build_object('ok', false, 'message', 'حددي خياراً صحيحاً بعلامة *');
    end if;
  end if;

  if p_question_id is not null then
    select * into q
    from public.questions
    where id = p_question_id;

    if q.id is null then
      return jsonb_build_object('ok', false, 'message', 'السؤال غير موجود');
    end if;

    if not (public.current_user_is_admin() or q.teacher_id = auth.uid()) then
      return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل هذا السؤال');
    end if;

    -- إذا دخل السؤال في محاولة طالب، نمنع تغيير بنيته حتى لا تتلف النتائج القديمة.
    select count(*) into v_attempts_count
    from public.online_exam_questions oeq
    join public.exam_attempts ea on ea.exam_id = oeq.exam_id
    where oeq.question_id = p_question_id;

    if v_attempts_count > 0 then
      return jsonb_build_object(
        'ok', false,
        'message', 'لا يمكن تعديل هذا السؤال لأنه مستخدم في محاولات طلاب. أنشئي سؤالاً جديداً أو احذفي الاختبار إذا لم يعد مطلوباً.',
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
        explanation = nullif(p_explanation,''),
        auto_grade = (p_question_type <> 'essay'),
        is_active = true,
        updated_at = now()
    where id = p_question_id
    returning id into v_question_id;

    delete from public.question_options where question_id = v_question_id;
  else
    insert into public.questions(
      bank_id,
      teacher_id,
      class_id,
      section_id,
      subject_id,
      question_type,
      prompt,
      points,
      correct_answer,
      explanation,
      auto_grade,
      is_active
    ) values (
      b.id,
      b.teacher_id,
      b.class_id,
      b.section_id,
      b.subject_id,
      p_question_type,
      trim(p_prompt),
      p_points,
      nullif(p_correct_answer,''),
      nullif(p_explanation,''),
      (p_question_type <> 'essay'),
      true
    ) returning id into v_question_id;
  end if;

  if p_question_type in ('mcq','true_false') then
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

  -- حدّث درجة السؤال داخل النماذج التي لم يدخلها الطلاب بعد.
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

grant execute on function public.upsert_question_with_options(uuid,uuid,text,text,numeric,text,text,jsonb) to authenticated;

-- -------------------------------------------------------------
-- 2) حذف سؤال بأمان
--    يحذف السؤال نهائياً إذا لم يدخل أي طالب اختباراً يحتويه.
--    إذا وُجدت محاولات، يمنع الحذف حفاظاً على النتائج.
-- -------------------------------------------------------------
create or replace function public.delete_question_safely(p_question_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  q record;
  v_attempts_count int := 0;
  affected uuid[];
begin
  select * into q from public.questions where id = p_question_id;

  if q.id is null then
    return jsonb_build_object('ok', false, 'message', 'السؤال غير موجود');
  end if;

  if not (public.current_user_is_admin() or q.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية حذف هذا السؤال');
  end if;

  select count(*) into v_attempts_count
  from public.online_exam_questions oeq
  join public.exam_attempts ea on ea.exam_id = oeq.exam_id
  where oeq.question_id = p_question_id;

  if v_attempts_count > 0 then
    return jsonb_build_object(
      'ok', false,
      'message', 'لا يمكن حذف السؤال لأنه مستخدم في محاولات طلاب. حفاظاً على النتائج، أغلقي النموذج أو أنشئي نسخة جديدة بدلاً من الحذف.',
      'locked_attempts', v_attempts_count
    );
  end if;

  select array_agg(distinct exam_id) into affected
  from public.online_exam_questions
  where question_id = p_question_id;

  delete from public.questions where id = p_question_id;

  if affected is not null then
    update public.online_exams e
    set total_points = coalesce((select sum(points) from public.online_exam_questions where exam_id = e.id),0),
        updated_at = now()
    where e.id = any(affected);
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حذف السؤال', 'action', 'deleted');
end;
$$;

grant execute on function public.delete_question_safely(uuid) to authenticated;

-- -------------------------------------------------------------
-- 3) تعديل النموذج الامتحاني والأسئلة المختارة
--    إذا توجد محاولات، يسمح بتعديل البيانات العامة فقط ويقفل تغيير الأسئلة.
-- -------------------------------------------------------------
create or replace function public.update_online_exam_model(
  p_exam_id uuid,
  p_bank_id uuid,
  p_title text,
  p_description text,
  p_duration_minutes int,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_status text,
  p_class_session_id uuid,
  p_question_ids jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  ex record;
  b record;
  v_attempts_count int := 0;
  qid uuid;
  q record;
  v_order int := 0;
  v_total numeric := 0;
  v_question_count int := 0;
  v_locked boolean := false;
begin
  select * into ex from public.online_exams where id = p_exam_id;

  if ex.id is null then
    return jsonb_build_object('ok', false, 'message', 'النموذج الامتحاني غير موجود');
  end if;

  if not (public.current_user_is_admin() or ex.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل هذا النموذج');
  end if;

  if nullif(trim(coalesce(p_title,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'عنوان الاختبار مطلوب');
  end if;

  if coalesce(p_duration_minutes,0) <= 0 then
    return jsonb_build_object('ok', false, 'message', 'مدة الاختبار يجب أن تكون أكبر من صفر');
  end if;

  if p_status not in ('draft','published','closed','archived') then
    return jsonb_build_object('ok', false, 'message', 'حالة الاختبار غير صحيحة');
  end if;

  select count(*) into v_attempts_count
  from public.exam_attempts
  where exam_id = p_exam_id;

  v_locked := v_attempts_count > 0;

  if not v_locked then
    if p_bank_id is null then
      return jsonb_build_object('ok', false, 'message', 'اختاري بنك الأسئلة');
    end if;

    select * into b from public.question_banks where id = p_bank_id;

    if b.id is null then
      return jsonb_build_object('ok', false, 'message', 'بنك الأسئلة غير موجود');
    end if;

    if not (public.current_user_is_admin() or b.teacher_id = auth.uid()) then
      return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية على بنك الأسئلة');
    end if;

    if jsonb_array_length(coalesce(p_question_ids,'[]'::jsonb)) = 0 then
      return jsonb_build_object('ok', false, 'message', 'اختاري سؤالاً واحداً على الأقل');
    end if;

    -- تحقق قبل حذف أسئلة النموذج القديم حتى لا نترك النموذج فارغاً إذا كانت القائمة غير صالحة.
    select count(*) into v_question_count
    from jsonb_array_elements_text(coalesce(p_question_ids,'[]'::jsonb)) as t(value)
    join public.questions qq on qq.id = t.value::uuid
    where qq.bank_id = b.id
      and qq.is_active = true
      and (public.current_user_is_admin() or qq.teacher_id = auth.uid());

    if v_question_count = 0 then
      return jsonb_build_object('ok', false, 'message', 'لم يتم العثور على أسئلة صالحة داخل البنك المختار');
    end if;
  end if;

  update public.online_exams
  set title = trim(p_title),
      description = nullif(p_description,''),
      duration_minutes = p_duration_minutes,
      start_at = p_start_at,
      end_at = p_end_at,
      status = p_status,
      class_session_id = p_class_session_id,
      updated_at = now()
  where id = p_exam_id;

  if not v_locked then
    update public.online_exams
    set class_id = b.class_id,
        section_id = b.section_id,
        subject_id = b.subject_id,
        updated_at = now()
    where id = p_exam_id;

    delete from public.online_exam_questions where exam_id = p_exam_id;

    v_order := 0;
    v_total := 0;
    v_question_count := 0;
    for qid in select value::uuid from jsonb_array_elements_text(coalesce(p_question_ids,'[]'::jsonb)) as t(value) loop
      select * into q
      from public.questions
      where id = qid
        and bank_id = b.id
        and is_active = true;

      if q.id is not null and (public.current_user_is_admin() or q.teacher_id = auth.uid()) then
        insert into public.online_exam_questions(exam_id, question_id, points, sort_order)
        values (p_exam_id, q.id, coalesce(q.points,1), v_order)
        on conflict (exam_id, question_id) do update
        set points = excluded.points,
            sort_order = excluded.sort_order;

        v_total := v_total + coalesce(q.points,1);
        v_question_count := v_question_count + 1;
        v_order := v_order + 1;
      end if;
    end loop;

    if v_question_count = 0 then
      return jsonb_build_object('ok', false, 'message', 'لم يتم العثور على أسئلة صالحة داخل البنك المختار');
    end if;

    update public.online_exams
    set total_points = v_total,
        updated_at = now()
    where id = p_exam_id;
  else
    select count(*) into v_question_count from public.online_exam_questions where exam_id = p_exam_id;
    select coalesce(sum(points),0) into v_total from public.online_exam_questions where exam_id = p_exam_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'message', case when v_locked then 'تم تعديل بيانات النموذج، ولم يتم تغيير الأسئلة لوجود محاولات طلاب' else 'تم تعديل النموذج الامتحاني' end,
    'locked_questions', v_locked,
    'attempts_count', v_attempts_count,
    'questions_count', v_question_count,
    'total_points', v_total
  );
end;
$$;

grant execute on function public.update_online_exam_model(uuid,uuid,text,text,int,timestamptz,timestamptz,text,uuid,jsonb) to authenticated;

-- -------------------------------------------------------------
-- 4) حذف النموذج الامتحاني بأمان
--    إذا لا توجد محاولات: حذف نهائي.
--    إذا توجد محاولات: أرشفة فقط حفاظاً على النتائج.
-- -------------------------------------------------------------
create or replace function public.delete_online_exam_safely(p_exam_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  ex record;
  v_attempts_count int := 0;
begin
  select * into ex from public.online_exams where id = p_exam_id;

  if ex.id is null then
    return jsonb_build_object('ok', false, 'message', 'النموذج الامتحاني غير موجود');
  end if;

  if not (public.current_user_is_admin() or ex.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية حذف هذا النموذج');
  end if;

  select count(*) into v_attempts_count
  from public.exam_attempts
  where exam_id = p_exam_id;

  if v_attempts_count = 0 then
    delete from public.online_exams where id = p_exam_id;
    return jsonb_build_object('ok', true, 'message', 'تم حذف النموذج الامتحاني', 'action', 'deleted');
  end if;

  update public.online_exams
  set status = 'archived',
      updated_at = now()
  where id = p_exam_id;

  return jsonb_build_object(
    'ok', true,
    'message', 'تمت أرشفة النموذج بدل الحذف لأنه يحتوي على محاولات طلاب',
    'action', 'archived',
    'attempts_count', v_attempts_count
  );
end;
$$;

grant execute on function public.delete_online_exam_safely(uuid) to authenticated;

notify pgrst, 'reload schema';

select 'question_exam_edit_delete_ready' as status;

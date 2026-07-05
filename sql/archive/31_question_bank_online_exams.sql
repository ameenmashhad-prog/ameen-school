-- =============================================================
-- مدارس أمين الرضا (ع) — بنك الأسئلة والاختبارات الإلكترونية
-- يدعم: اختيار من متعدد، صح/خطأ، فراغ، مطابقة، مقالي، وسائط.
-- يربط النتيجة تلقائياً مع exams/exam_scores عند التسليم.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) بنوك الأسئلة
-- -------------------------------------------------------------
create table if not exists public.question_banks (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  title text not null,
  description text,
  teacher_id uuid not null references public.users(id) on delete cascade,
  class_id uuid null references public.classes(id) on delete set null,
  section_id uuid null references public.sections(id) on delete set null,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  visibility text not null default 'private' check (visibility in ('private','school','shared')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  bank_id uuid not null references public.question_banks(id) on delete cascade,
  teacher_id uuid not null references public.users(id) on delete cascade,
  class_id uuid null references public.classes(id) on delete set null,
  section_id uuid null references public.sections(id) on delete set null,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  question_type text not null check (question_type in ('mcq','true_false','fill_blank','matching','essay','image','audio')),
  prompt text not null,
  media_type text check (media_type in ('image','audio','video','file') or media_type is null),
  media_url text,
  correct_answer text,
  correct_answer_json jsonb not null default '{}'::jsonb,
  explanation text,
  points numeric not null default 1,
  difficulty text not null default 'medium' check (difficulty in ('easy','medium','hard')),
  tags jsonb not null default '[]'::jsonb,
  auto_grade boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.question_options (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questions(id) on delete cascade,
  option_text text not null,
  is_correct boolean not null default false,
  match_key text,
  sort_order int default 0,
  created_at timestamptz not null default now()
);

-- -------------------------------------------------------------
-- 2) الاختبارات الإلكترونية
-- -------------------------------------------------------------
create table if not exists public.online_exams (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  academic_period_id uuid null references public.academic_periods(id) on delete set null,
  linked_exam_id uuid null references public.exams(id) on delete set null,
  title text not null,
  description text,
  teacher_id uuid not null references public.users(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  section_id uuid null references public.sections(id) on delete set null,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  duration_minutes int not null default 30,
  start_at timestamptz,
  end_at timestamptz,
  status text not null default 'draft' check (status in ('draft','published','closed','archived')),
  shuffle_questions boolean not null default true,
  shuffle_options boolean not null default true,
  show_result boolean not null default true,
  max_attempts int not null default 1,
  total_points numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.online_exam_questions (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.online_exams(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  points numeric not null default 1,
  sort_order int default 0,
  unique(exam_id, question_id)
);

create table if not exists public.exam_attempts (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.online_exams(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  status text not null default 'in_progress' check (status in ('in_progress','submitted','graded','expired','cancelled')),
  score numeric,
  max_score numeric,
  graded_by uuid null references public.users(id),
  grading_notes text,
  created_at timestamptz not null default now(),
  unique(exam_id, student_id, started_at)
);

create table if not exists public.exam_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.exam_attempts(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  selected_option_id uuid null references public.question_options(id) on delete set null,
  answer_text text,
  answer_json jsonb not null default '{}'::jsonb,
  is_correct boolean,
  score_awarded numeric,
  feedback text,
  answered_at timestamptz not null default now(),
  unique(attempt_id, question_id)
);

create index if not exists idx_question_banks_teacher_subject on public.question_banks(teacher_id, subject_id);
create index if not exists idx_questions_bank_type on public.questions(bank_id, question_type);
create index if not exists idx_online_exams_section_subject on public.online_exams(section_id, subject_id, status);
create index if not exists idx_exam_attempts_student_exam on public.exam_attempts(student_id, exam_id);
create index if not exists idx_exam_answers_attempt on public.exam_answers(attempt_id);

-- -------------------------------------------------------------
-- 3) دوال مساعدة للصلاحيات
-- -------------------------------------------------------------
create or replace function public.online_exam_student_can_access(p_exam_id uuid, p_student_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1
    from public.online_exams oe
    join public.student_enrollments se
      on se.student_id = p_student_id
     and se.enrollment_status = 'active'
     and se.academic_year = oe.academic_year
     and (
       (oe.section_id is not null and se.section_id = oe.section_id)
       or (oe.section_id is null and se.class_id = oe.class_id)
     )
    where oe.id = p_exam_id
      and oe.status = 'published'
      and (oe.start_at is null or now() >= oe.start_at)
      and (oe.end_at is null or now() <= oe.end_at)
  );
$$;

grant execute on function public.online_exam_student_can_access(uuid,uuid) to authenticated;

-- -------------------------------------------------------------
-- 4) دالة بدء محاولة اختبار
-- -------------------------------------------------------------
create or replace function public.start_online_exam_attempt(p_exam_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_attempt_id uuid;
  attempts_count int;
  max_allowed int;
begin
  select s.id into v_student_id
  from public.students s
  where s.user_id = auth.uid()
  limit 1;

  if v_student_id is null then
    return jsonb_build_object('ok',false,'message','لم يتم العثور على طالب مرتبط بهذا الحساب');
  end if;

  if not public.online_exam_student_can_access(p_exam_id, v_student_id) then
    return jsonb_build_object('ok',false,'message','الاختبار غير متاح لهذا الطالب أو خارج وقت الاختبار');
  end if;

  select max_attempts into max_allowed from public.online_exams where id = p_exam_id;
  select count(*) into attempts_count
  from public.exam_attempts
  where exam_id = p_exam_id
    and student_id = v_student_id
    and status in ('submitted','graded','in_progress');

  if attempts_count >= coalesce(max_allowed,1) then
    return jsonb_build_object('ok',false,'message','تم استنفاد عدد المحاولات المسموح');
  end if;

  insert into public.exam_attempts(exam_id, student_id)
  values (p_exam_id, v_student_id)
  returning id into v_attempt_id;

  return jsonb_build_object('ok',true,'attempt_id',v_attempt_id);
end;
$$;

grant execute on function public.start_online_exam_attempt(uuid) to authenticated;

-- -------------------------------------------------------------
-- 5) دالة تصحيح محاولة الاختبار وترحيلها إلى exams/exam_scores
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
  linked uuid;
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
    v_max := v_max + coalesce(q.exam_points, q.points, 1);
    awarded := 0;

    select * into ans
    from public.exam_answers
    where attempt_id = p_attempt_id
      and question_id = q.id;

    if ans.id is not null then
      if q.question_type in ('mcq','true_false') then
        if exists(select 1 from public.question_options qo where qo.id = ans.selected_option_id and qo.is_correct = true) then
          awarded := coalesce(q.exam_points, q.points, 1);
        end if;
      elsif q.question_type = 'fill_blank' then
        if public.schedule_norm_ar(ans.answer_text) = public.schedule_norm_ar(q.correct_answer) then
          awarded := coalesce(q.exam_points, q.points, 1);
        end if;
      elsif q.question_type in ('matching') then
        -- matching يحتاج تصحيحاً أوسع لاحقاً. حالياً لا يصحح تلقائياً إلا إذا answer_json يساوي correct_answer_json.
        if ans.answer_json = q.correct_answer_json then
          awarded := coalesce(q.exam_points, q.points, 1);
        end if;
      else
        -- essay/image/audio يحتاج تصحيح يدوي.
        awarded := coalesce(ans.score_awarded, 0);
      end if;

      update public.exam_answers
      set score_awarded = awarded,
          is_correct = (awarded >= coalesce(q.exam_points, q.points, 1))
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

  -- ربط النتيجة بالنظام الأكاديمي القديم/الحالي
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

-- -------------------------------------------------------------
-- 6) RLS
-- -------------------------------------------------------------
alter table public.question_banks enable row level security;
alter table public.questions enable row level security;
alter table public.question_options enable row level security;
alter table public.online_exams enable row level security;
alter table public.online_exam_questions enable row level security;
alter table public.exam_attempts enable row level security;
alter table public.exam_answers enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='question_banks' and policyname='question_banks_teacher_admin') then
    create policy question_banks_teacher_admin on public.question_banks
      for all to authenticated
      using (public.current_user_is_admin() or teacher_id = auth.uid())
      with check (public.current_user_is_admin() or teacher_id = auth.uid());
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='questions' and policyname='questions_teacher_admin') then
    create policy questions_teacher_admin on public.questions
      for all to authenticated
      using (public.current_user_is_admin() or teacher_id = auth.uid())
      with check (public.current_user_is_admin() or teacher_id = auth.uid());
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='question_options' and policyname='question_options_teacher_admin') then
    create policy question_options_teacher_admin on public.question_options
      for all to authenticated
      using (public.current_user_is_admin() or exists(select 1 from public.questions q where q.id = question_id and q.teacher_id = auth.uid()))
      with check (public.current_user_is_admin() or exists(select 1 from public.questions q where q.id = question_id and q.teacher_id = auth.uid()));
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='online_exams' and policyname='online_exams_teacher_student') then
    create policy online_exams_teacher_student on public.online_exams
      for select to authenticated
      using (
        public.current_user_is_admin()
        or teacher_id = auth.uid()
        or exists(select 1 from public.students s where s.user_id = auth.uid() and public.online_exam_student_can_access(id, s.id))
      );
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='online_exams' and policyname='online_exams_teacher_write') then
    create policy online_exams_teacher_write on public.online_exams
      for all to authenticated
      using (public.current_user_is_admin() or teacher_id = auth.uid())
      with check (public.current_user_is_admin() or teacher_id = auth.uid());
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='online_exam_questions' and policyname='online_exam_questions_teacher_student') then
    create policy online_exam_questions_teacher_student on public.online_exam_questions
      for select to authenticated
      using (exists(select 1 from public.online_exams e where e.id = exam_id and (public.current_user_is_admin() or e.teacher_id = auth.uid() or exists(select 1 from public.students s where s.user_id=auth.uid() and public.online_exam_student_can_access(e.id,s.id)))));
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='online_exam_questions' and policyname='online_exam_questions_teacher_write') then
    create policy online_exam_questions_teacher_write on public.online_exam_questions
      for all to authenticated
      using (exists(select 1 from public.online_exams e where e.id = exam_id and (public.current_user_is_admin() or e.teacher_id = auth.uid())))
      with check (exists(select 1 from public.online_exams e where e.id = exam_id and (public.current_user_is_admin() or e.teacher_id = auth.uid())));
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='exam_attempts' and policyname='exam_attempts_student_teacher') then
    create policy exam_attempts_student_teacher on public.exam_attempts
      for all to authenticated
      using (
        public.current_user_is_admin()
        or exists(select 1 from public.students s where s.id = student_id and s.user_id = auth.uid())
        or exists(select 1 from public.online_exams e where e.id = exam_id and e.teacher_id = auth.uid())
      )
      with check (
        public.current_user_is_admin()
        or exists(select 1 from public.students s where s.id = student_id and s.user_id = auth.uid())
        or exists(select 1 from public.online_exams e where e.id = exam_id and e.teacher_id = auth.uid())
      );
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='exam_answers' and policyname='exam_answers_student_teacher') then
    create policy exam_answers_student_teacher on public.exam_answers
      for all to authenticated
      using (
        public.current_user_is_admin()
        or exists(select 1 from public.exam_attempts a join public.students s on s.id=a.student_id where a.id = attempt_id and s.user_id = auth.uid())
        or exists(select 1 from public.exam_attempts a join public.online_exams e on e.id=a.exam_id where a.id = attempt_id and e.teacher_id = auth.uid())
      )
      with check (
        public.current_user_is_admin()
        or exists(select 1 from public.exam_attempts a join public.students s on s.id=a.student_id where a.id = attempt_id and s.user_id = auth.uid())
        or exists(select 1 from public.exam_attempts a join public.online_exams e on e.id=a.exam_id where a.id = attempt_id and e.teacher_id = auth.uid())
      );
  end if;
end $$;

notify pgrst, 'reload schema';

select 'question_bank_online_exams_ready' as status;

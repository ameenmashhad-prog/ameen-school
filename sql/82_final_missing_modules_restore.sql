-- =============================================================
-- مدارس أمين الرضا (ع) — ترميم نهائي للوحدات الناقصة في فحص الجاهزية
-- يعالج:
-- 1) exam_integrity missing
-- 2) cashbox warning: v_finance_receiver_monthly + void_fee_payment
-- 3) academic warning: v_academic_subject_results + v_academic_student_summary
-- آمن وتراكمي ولا يحذف بيانات.
-- =============================================================

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

-- -------------------------------------------------------------
-- A) Academic views restore
-- -------------------------------------------------------------
create or replace function public.class_stage_type(p_class_id uuid)
returns text
language sql
stable
as $$
  select case
    when c.name ilike '%ابتدائي%' then 'primary'
    when c.name ilike '%متوسط%' then 'middle'
    else 'preparatory'
  end
  from public.classes c
  where c.id = p_class_id;
$$;

grant execute on function public.class_stage_type(uuid) to authenticated;

-- تأكيد أعمدة التوافق الأكاديمي
alter table public.exam_scores add column if not exists absent boolean not null default false;
alter table public.exam_scores add column if not exists excused boolean not null default false;
alter table public.exam_scores add column if not exists notes text;
alter table public.grades add column if not exists score numeric;
alter table public.grades add column if not exists grade numeric;
alter table public.grades add column if not exists mark numeric;
alter table public.grades add column if not exists value numeric;
alter table public.grades add column if not exists max_score numeric default 100;
alter table public.behavior_records add column if not exists points numeric default 0;
alter table public.behavior_records add column if not exists score numeric default 0;

-- تأكيد الجداول الأكاديمية إن كانت ناقصة
create table if not exists public.academic_flags (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  subject_id uuid null references public.subjects(id),
  flag_type text not null default 'academic_violation',
  blocks_exemption boolean not null default true,
  notes text,
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now()
);

-- إذا views قديمة موجودة بتعريف مكسور، احذفها ثم أنشئها
DROP VIEW IF EXISTS public.v_academic_student_summary;
DROP VIEW IF EXISTS public.v_academic_subject_results;

CREATE VIEW public.v_academic_subject_results
WITH (security_invoker=true) AS
with base_students as (
  select s.id as student_id, s.name as student_name, s.class_id, c.name as class_name, public.class_stage_type(s.class_id) as stage_type
  from public.students s
  left join public.classes c on c.id = s.class_id
),
subject_pairs as (
  select distinct student_id, subject_id from public.continuous_assessments where subject_id is not null
  union
  select distinct es.student_id, e.subject_id from public.exam_scores es join public.exams e on e.id = es.exam_id where e.subject_id is not null
  union
  select distinct student_id, subject_id from public.grades where subject_id is not null
),
cont as (
  select student_id, subject_id, round(avg(score / nullif(max_score,0) * 100),2) as continuous_avg
  from public.continuous_assessments
  where subject_id is not null
  group by student_id, subject_id
),
exam_avg as (
  select es.student_id, e.subject_id, round(avg(case when coalesce(es.absent,false) then 0 else es.score / nullif(e.max_score,0) * 100 end),2) as monthly_exam_avg
  from public.exam_scores es
  join public.exams e on e.id = es.exam_id
  where e.subject_id is not null
  group by es.student_id, e.subject_id
),
legacy_grades as (
  select student_id, subject_id, round(avg(coalesce(score, grade, mark, value)::numeric),2) as legacy_avg
  from public.grades
  where subject_id is not null and coalesce(score, grade, mark, value) is not null
  group by student_id, subject_id
),
att as (
  select student_id,
    round(100.0 * count(*) filter (where status in ('present','late','permission','external_activity')) / nullif(count(*),0),2) as attendance_rate
  from public.attendance
  group by student_id
),
beh as (
  select student_id, coalesce(sum(coalesce(points, score, 0)),0) as behavior_points
  from public.behavior_records
  group by student_id
),
flags as (
  select student_id, subject_id, bool_or(blocks_exemption) as blocks
  from public.academic_flags
  group by student_id, subject_id
),
weights as (
  select distinct on (stage_type)
    stage_type,
    coalesce(continuous_weight,20) as continuous_weight,
    coalesce(monthly_exam_weight,80) as monthly_exam_weight
  from public.grade_weights
  where coalesce(is_active,true)=true
  order by stage_type, updated_at desc nulls last
)
select
  bs.student_id,
  bs.student_name,
  bs.class_id,
  bs.class_name,
  bs.stage_type,
  sp.subject_id,
  sub.name as subject_name,
  coalesce(c.continuous_avg, lg.legacy_avg, 0) as continuous_avg,
  coalesce(e.monthly_exam_avg, lg.legacy_avg, 0) as monthly_exam_avg,
  coalesce(w.continuous_weight,20) as continuous_weight,
  coalesce(w.monthly_exam_weight,80) as monthly_exam_weight,
  round((coalesce(c.continuous_avg, lg.legacy_avg, 0) * coalesce(w.continuous_weight,20) + coalesce(e.monthly_exam_avg, lg.legacy_avg, 0) * coalesce(w.monthly_exam_weight,80)) / nullif(coalesce(w.continuous_weight,20)+coalesce(w.monthly_exam_weight,80),0),2) as final_average,
  coalesce(att.attendance_rate,100) as attendance_rate,
  coalesce(beh.behavior_points,0) as behavior_points,
  coalesce(flags.blocks,false) as has_blocking_flag,
  case
    when bs.stage_type='primary' then 'لا يوجد إعفاء'
    when round((coalesce(c.continuous_avg, lg.legacy_avg, 0) * coalesce(w.continuous_weight,20) + coalesce(e.monthly_exam_avg, lg.legacy_avg, 0) * coalesce(w.monthly_exam_weight,80)) / nullif(coalesce(w.continuous_weight,20)+coalesce(w.monthly_exam_weight,80),0),2) >= 90
      and coalesce(att.attendance_rate,100) >= 85
      and coalesce(flags.blocks,false)=false
      and coalesce(beh.behavior_points,0) >= -10
      then 'إعفاء مادة'
    when round((coalesce(c.continuous_avg, lg.legacy_avg, 0) * coalesce(w.continuous_weight,20) + coalesce(e.monthly_exam_avg, lg.legacy_avg, 0) * coalesce(w.monthly_exam_weight,80)) / nullif(coalesce(w.continuous_weight,20)+coalesce(w.monthly_exam_weight,80),0),2) >= 80
      then 'مرشح للإعفاء'
    else 'لا يوجد إعفاء'
  end as subject_exemption_status,
  greatest(90 - round((coalesce(c.continuous_avg, lg.legacy_avg, 0) * coalesce(w.continuous_weight,20) + coalesce(e.monthly_exam_avg, lg.legacy_avg, 0) * coalesce(w.monthly_exam_weight,80)) / nullif(coalesce(w.continuous_weight,20)+coalesce(w.monthly_exam_weight,80),0),2),0) as points_to_subject_exemption
from subject_pairs sp
join base_students bs on bs.student_id = sp.student_id
left join public.subjects sub on sub.id = sp.subject_id
left join cont c on c.student_id=sp.student_id and c.subject_id=sp.subject_id
left join exam_avg e on e.student_id=sp.student_id and e.subject_id=sp.subject_id
left join legacy_grades lg on lg.student_id=sp.student_id and lg.subject_id=sp.subject_id
left join att on att.student_id=sp.student_id
left join beh on beh.student_id=sp.student_id
left join flags on flags.student_id=sp.student_id and (flags.subject_id is not distinct from sp.subject_id)
left join weights w on w.stage_type = bs.stage_type;

CREATE VIEW public.v_academic_student_summary
WITH (security_invoker=true) AS
select
  r.student_id,
  r.student_name,
  r.class_id,
  r.class_name,
  r.stage_type,
  round(avg(r.final_average),2) as overall_average,
  count(*) as subjects_count,
  count(*) filter (where r.final_average < 85) as subjects_below_85,
  count(*) filter (where r.subject_exemption_status='إعفاء مادة') as subject_exemptions_count,
  min(r.attendance_rate) as attendance_rate,
  min(r.behavior_points) as behavior_points,
  bool_or(r.has_blocking_flag) as has_blocking_flag,
  case
    when r.stage_type='primary' then 'لا يوجد إعفاء'
    when count(*) > 0 and min(r.final_average) >= 85 and min(r.attendance_rate) >= 85 and bool_or(r.has_blocking_flag)=false and min(r.behavior_points) >= -10 then 'إعفاء عام'
    when avg(r.final_average) between 80 and 84.99 or count(*) filter (where r.final_average < 85) between 1 and 2 then 'مرشح للإعفاء'
    else 'لا يوجد إعفاء'
  end as general_exemption_status,
  case when min(r.final_average) < 85 then 85 - min(r.final_average) else 0 end as points_needed_general
from public.v_academic_subject_results r
group by r.student_id, r.student_name, r.class_id, r.class_name, r.stage_type;

grant select on public.v_academic_subject_results to authenticated;
grant select on public.v_academic_student_summary to authenticated;

-- -------------------------------------------------------------
-- B) Exam Integrity restore
-- -------------------------------------------------------------
create table if not exists public.exam_reference_sources (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  source_type text not null default 'internet_paste',
  source_url text,
  exam_id uuid null references public.online_exams(id) on delete cascade,
  question_id uuid null references public.questions(id) on delete cascade,
  content_text text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.exam_reference_sources enable row level security;
drop policy if exists exam_reference_sources_teacher_admin on public.exam_reference_sources;
create policy exam_reference_sources_teacher_admin on public.exam_reference_sources
  for all to authenticated
  using (public.current_user_is_admin() or teacher_id = auth.uid())
  with check (public.current_user_is_admin() or teacher_id = auth.uid());

grant select, insert, update, delete on public.exam_reference_sources to authenticated;

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
  v := regexp_replace(v, '[[:punct:]]+', ' ', 'g');
  v := regexp_replace(v, '[[:space:]]+', ' ', 'g');
  return btrim(v);
end;
$$;

grant execute on function public.exam_norm_text(text) to authenticated;

create or replace function public.exam_answer_plain_text(p_answer_text text, p_answer_json jsonb)
returns text
language plpgsql
immutable
as $$
declare
  v text;
begin
  if nullif(trim(coalesce(p_answer_text,'')), '') is not null then return p_answer_text; end if;
  if p_answer_json is null or p_answer_json = '{}'::jsonb then return ''; end if;
  if p_answer_json ? 'pairs' then
    select string_agg(coalesce(x.value->>'left','') || ' = ' || coalesce(x.value->>'right',''), ' | ' order by x.ord)
    into v
    from jsonb_array_elements(coalesce(p_answer_json->'pairs','[]'::jsonb)) with ordinality as x(value, ord);
    return coalesce(v,'');
  end if;
  if p_answer_json ? 'items' then
    select string_agg(x.value, ' > ' order by x.ord)
    into v
    from jsonb_array_elements_text(coalesce(p_answer_json->'items','[]'::jsonb)) with ordinality as x(value, ord);
    return coalesce(v,'');
  end if;
  return p_answer_json::text;
end;
$$;

grant execute on function public.exam_answer_plain_text(text,jsonb) to authenticated;

create or replace function public.exam_best_text_similarity(p_answer text, p_source text)
returns numeric
language sql
stable
as $$
  with a as (select public.exam_norm_text(p_answer) as txt),
  chunks as (
    select public.exam_norm_text(p_source) as txt
    union all
    select public.exam_norm_text(x.chunk) as txt
    from regexp_split_to_table(coalesce(p_source,''), '[\n\.\!\?؟؛،]+') as x(chunk)
  ),
  filtered as (select txt from chunks where char_length(txt) >= 35)
  select coalesce(max(similarity((select txt from a), filtered.txt)),0)::numeric from filtered;
$$;

grant execute on function public.exam_best_text_similarity(text,text) to authenticated;

create or replace function public.exam_ai_likelihood_score(p_text text)
returns int
language plpgsql
immutable
as $$
declare
  t text := lower(coalesce(p_text,''));
  n text := public.exam_norm_text(p_text);
  score int := 0;
  len int := char_length(n);
begin
  if len < 120 then return 0; end if;
  if len >= 300 then score := score + 10; end if;
  if len >= 700 then score := score + 12; end if;
  if t like '%في الختام%' or t like '%بشكل عام%' or t like '%بناء على ما سبق%' or t like '%بناءً على ما سبق%' then score := score + 18; end if;
  if t like '%علاوة على ذلك%' or t like '%بالإضافة إلى ذلك%' or t like '%من ناحية أخرى%' then score := score + 14; end if;
  if t ~ '(^|\n)\s*[-•*]\s+' then score := score + 8; end if;
  if len > 600 and t !~ '[0-9٠-٩]' then score := score + 6; end if;
  return least(score,100);
end;
$$;

grant execute on function public.exam_ai_likelihood_score(text) to authenticated;

create or replace function public.exam_ai_likelihood_reasons(p_text text)
returns text[]
language plpgsql
immutable
as $$
declare
  t text := lower(coalesce(p_text,''));
  n text := public.exam_norm_text(p_text);
  reasons text[] := array[]::text[];
  len int := char_length(n);
begin
  if len >= 700 then reasons := array_append(reasons, 'إجابة طويلة ومنظمة جداً'); end if;
  if t like '%في الختام%' or t like '%بشكل عام%' or t like '%بناء على ما سبق%' or t like '%بناءً على ما سبق%' then reasons := array_append(reasons, 'عبارات ختامية/انتقالية شائعة'); end if;
  if t ~ '(^|\n)\s*[-•*]\s+' then reasons := array_append(reasons, 'تنسيق نقاط منظم'); end if;
  return reasons;
end;
$$;

grant execute on function public.exam_ai_likelihood_reasons(text) to authenticated;

DROP VIEW IF EXISTS public.v_exam_integrity_answer_flags;
DROP VIEW IF EXISTS public.v_exam_answer_source_matches;
DROP VIEW IF EXISTS public.v_exam_answer_similarity_pairs;
DROP VIEW IF EXISTS public.v_exam_integrity_answer_texts;

CREATE VIEW public.v_exam_integrity_answer_texts
WITH (security_invoker=true) AS
select
  ans.id as answer_id,
  ans.attempt_id,
  att.exam_id,
  e.title as exam_title,
  e.teacher_id,
  att.student_id,
  st.name as student_name,
  e.class_id,
  c.name as class_name,
  e.section_id,
  sec.code as section_code,
  e.subject_id,
  sub.name as subject_name,
  ans.question_id,
  q.prompt,
  q.question_type,
  ans.answered_at,
  coalesce(ans.is_draft,false) as is_draft,
  public.exam_answer_plain_text(ans.answer_text, ans.answer_json) as answer_text,
  public.exam_norm_text(public.exam_answer_plain_text(ans.answer_text, ans.answer_json)) as norm_text,
  char_length(public.exam_norm_text(public.exam_answer_plain_text(ans.answer_text, ans.answer_json))) as norm_len,
  att.violations_count,
  case when att.started_at is not null and coalesce(att.submitted_at, ans.answered_at, now()) > att.started_at then
    round(char_length(public.exam_answer_plain_text(ans.answer_text, ans.answer_json))::numeric / greatest(extract(epoch from (coalesce(att.submitted_at, ans.answered_at, now()) - att.started_at))/60,1),2)
  else null end as chars_per_minute
from public.exam_answers ans
join public.exam_attempts att on att.id = ans.attempt_id
join public.online_exams e on e.id = att.exam_id
join public.questions q on q.id = ans.question_id
left join public.students st on st.id = att.student_id
left join public.classes c on c.id = e.class_id
left join public.sections sec on sec.id = e.section_id
left join public.subjects sub on sub.id = e.subject_id
where coalesce(ans.is_draft,false)=false
  and nullif(public.exam_norm_text(public.exam_answer_plain_text(ans.answer_text, ans.answer_json)), '') is not null
  and (public.current_user_is_admin() or e.teacher_id = auth.uid());

grant select on public.v_exam_integrity_answer_texts to authenticated;

CREATE VIEW public.v_exam_answer_similarity_pairs
WITH (security_invoker=true) AS
select
  a.exam_id,
  a.exam_title,
  a.teacher_id,
  a.question_id,
  a.prompt,
  a.question_type,
  a.answer_id as answer_a_id,
  b.answer_id as answer_b_id,
  a.student_id as student_a_id,
  a.student_name as student_a_name,
  b.student_id as student_b_id,
  b.student_name as student_b_name,
  round(similarity(a.norm_text, b.norm_text)::numeric,4) as similarity_score,
  round(similarity(a.norm_text, b.norm_text)::numeric*100,2) as similarity_percent,
  case when a.norm_text=b.norm_text then 'تطابق كامل تقريباً' when similarity(a.norm_text,b.norm_text)>=0.88 then 'تشابه عالٍ جداً' when similarity(a.norm_text,b.norm_text)>=0.74 then 'تشابه عالٍ' else 'تشابه متوسط' end as risk_label,
  left(a.answer_text,700) as answer_a_preview,
  left(b.answer_text,700) as answer_b_preview
from public.v_exam_integrity_answer_texts a
join public.v_exam_integrity_answer_texts b on b.exam_id=a.exam_id and b.question_id=a.question_id and b.answer_id>a.answer_id and b.student_id is distinct from a.student_id
where a.norm_len>=45 and b.norm_len>=45 and similarity(a.norm_text,b.norm_text)>=0.70;

grant select on public.v_exam_answer_similarity_pairs to authenticated;

CREATE VIEW public.v_exam_answer_source_matches
WITH (security_invoker=true) AS
select
  t.answer_id,
  t.attempt_id,
  t.exam_id,
  t.exam_title,
  t.teacher_id,
  t.question_id,
  t.prompt,
  t.question_type,
  t.student_id,
  t.student_name,
  t.class_name,
  t.section_code,
  t.subject_name,
  s.id as source_id,
  s.title as source_title,
  s.source_type,
  s.source_url,
  round(public.exam_best_text_similarity(t.answer_text, s.content_text),4) as source_similarity,
  round(public.exam_best_text_similarity(t.answer_text, s.content_text)*100,2) as source_similarity_percent,
  case when public.exam_best_text_similarity(t.answer_text, s.content_text)>=0.82 then 'مطابق لمصدر ملصق بدرجة عالية جداً' when public.exam_best_text_similarity(t.answer_text, s.content_text)>=0.68 then 'مطابق لمصدر ملصق بدرجة عالية' else 'تشابه محتمل مع مصدر ملصق' end as risk_label,
  left(t.answer_text,900) as answer_preview,
  left(s.content_text,900) as source_preview
from public.v_exam_integrity_answer_texts t
join public.exam_reference_sources s on (s.exam_id is null or s.exam_id=t.exam_id) and (s.question_id is null or s.question_id=t.question_id) and (public.current_user_is_admin() or s.teacher_id=auth.uid() or s.teacher_id=t.teacher_id)
where t.norm_len>=45 and char_length(public.exam_norm_text(s.content_text))>=45 and public.exam_best_text_similarity(t.answer_text, s.content_text)>=0.55;

grant select on public.v_exam_answer_source_matches to authenticated;

CREATE VIEW public.v_exam_integrity_answer_flags
WITH (security_invoker=true) AS
select
  t.*,
  coalesce((select max(p.similarity_score) from public.v_exam_answer_similarity_pairs p where p.answer_a_id=t.answer_id or p.answer_b_id=t.answer_id),0)::numeric as max_peer_similarity,
  coalesce((select max(sm.source_similarity) from public.v_exam_answer_source_matches sm where sm.answer_id=t.answer_id),0)::numeric as max_source_similarity,
  public.exam_ai_likelihood_score(t.answer_text) as ai_likelihood_score,
  public.exam_ai_likelihood_reasons(t.answer_text) as ai_likelihood_reasons,
  array_remove(array[
    case when coalesce((select max(p.similarity_score) from public.v_exam_answer_similarity_pairs p where p.answer_a_id=t.answer_id or p.answer_b_id=t.answer_id),0)>=0.88 then 'تطابق عالٍ جداً مع طالب آخر' end,
    case when coalesce((select max(p.similarity_score) from public.v_exam_answer_similarity_pairs p where p.answer_a_id=t.answer_id or p.answer_b_id=t.answer_id),0)>=0.70 then 'تشابه مع إجابة طالب آخر' end,
    case when coalesce((select max(sm.source_similarity) from public.v_exam_answer_source_matches sm where sm.answer_id=t.answer_id),0)>=0.68 then 'تشابه عالٍ مع مصدر ملصق' end,
    case when public.exam_ai_likelihood_score(t.answer_text)>=65 then 'مؤشرات توليد آلي محتملة' end,
    case when coalesce(t.violations_count,0)>0 then 'توجد تنبيهات أثناء الاختبار' end,
    case when coalesce(t.chars_per_minute,0)>=750 and t.norm_len>=250 then 'سرعة إدخال/تسليم غير طبيعية' end
  ]::text[], null) as flags,
  least(100,
    greatest(
      round(coalesce((select max(p.similarity_score) from public.v_exam_answer_similarity_pairs p where p.answer_a_id=t.answer_id or p.answer_b_id=t.answer_id),0)*100)::int,
      round(coalesce((select max(sm.source_similarity) from public.v_exam_answer_source_matches sm where sm.answer_id=t.answer_id),0)*100)::int,
      public.exam_ai_likelihood_score(t.answer_text)
    ) + least(coalesce(t.violations_count,0)*5,15) + case when coalesce(t.chars_per_minute,0)>=750 and t.norm_len>=250 then 10 else 0 end
  ) as risk_score
from public.v_exam_integrity_answer_texts t;

grant select on public.v_exam_integrity_answer_flags to authenticated;

-- -------------------------------------------------------------
-- C) Cashbox missing restore
-- -------------------------------------------------------------
alter table public.fee_payments add column if not exists received_by uuid null references public.users(id) on delete set null;
alter table public.fee_payments add column if not exists receiver_name text;
alter table public.fee_payments add column if not exists receiver_role text;
alter table public.fee_payments add column if not exists voided boolean not null default false;
alter table public.fee_payments add column if not exists void_reason text;
alter table public.fee_payments add column if not exists voided_by uuid null references public.users(id) on delete set null;
alter table public.fee_payments add column if not exists voided_at timestamptz;

DROP VIEW IF EXISTS public.v_finance_receiver_monthly;

CREATE VIEW public.v_finance_receiver_monthly
WITH (security_invoker=true) AS
select
  date_trunc('month', coalesce(p.payment_date, p.created_at::date)::timestamp)::date as month_start,
  p.received_by,
  coalesce(p.receiver_name, rb.name, p.created_by_name, 'غير محدد') as receiver_name,
  coalesce(rb.role, p.receiver_role) as receiver_role,
  count(*) filter (where coalesce(p.voided,false)=false) as payments_count,
  count(*) filter (where coalesce(p.voided,false)=true) as voided_count,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false),0) as total_usd,
  coalesce(sum(coalesce(p.amount_irr,0)) filter (where coalesce(p.voided,false)=false),0) as total_irr,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false and p.payment_method='cash'),0) as cash_usd,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false and p.payment_method='card'),0) as card_usd,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false and p.payment_method='transfer'),0) as transfer_usd,
  coalesce(sum(coalesce(p.amount_usd,p.amount,0)) filter (where coalesce(p.voided,false)=false and p.payment_method not in ('cash','card','transfer')),0) as other_usd
from public.fee_payments p
left join public.users rb on rb.id = p.received_by
where public.finance_can_manage()
group by date_trunc('month', coalesce(p.payment_date, p.created_at::date)::timestamp)::date, p.received_by, coalesce(p.receiver_name, rb.name, p.created_by_name, 'غير محدد'), coalesce(rb.role, p.receiver_role);

grant select on public.v_finance_receiver_monthly to authenticated;

create or replace function public.void_fee_payment(p_payment_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
  f record;
  inst record;
  usd numeric := 0;
  new_fee_paid numeric;
  new_inst_paid numeric;
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إلغاء الدفعة');
  end if;

  select * into p from public.fee_payments where id = p_payment_id;
  if p.id is null then return jsonb_build_object('ok', false, 'message', 'الدفعة غير موجودة'); end if;
  if coalesce(p.voided,false) then return jsonb_build_object('ok', true, 'message', 'الدفعة ملغاة مسبقاً'); end if;
  if nullif(trim(coalesce(p_reason,'')), '') is null then return jsonb_build_object('ok', false, 'message', 'سبب إلغاء الدفعة مطلوب'); end if;

  usd := coalesce(p.amount_usd, p.amount, 0);
  select * into f from public.student_fees where id = p.student_fee_id;

  if p.student_installment_id is not null then
    select * into inst from public.student_installments where id = p.student_installment_id;
    if inst.id is not null then
      new_inst_paid := greatest(coalesce(inst.amount_paid,0) - usd, 0);
      update public.student_installments
      set amount_paid = new_inst_paid,
          balance_remaining = greatest(coalesce(amount_due,0) - new_inst_paid, 0),
          status = case when new_inst_paid <= 0 then 'unpaid' when new_inst_paid < coalesce(amount_due,0) then 'partial' else 'paid' end,
          actual_payment_date = case when new_inst_paid <= 0 then null else actual_payment_date end,
          updated_at = now()
      where id = inst.id;
    end if;
  end if;

  if f.id is not null then
    new_fee_paid := greatest(coalesce(f.total_paid,0) - usd, 0);
    update public.student_fees
    set total_paid = new_fee_paid,
        status = case when new_fee_paid <= 0 then 'unpaid' when new_fee_paid < coalesce(net_amount,base_amount,0) then 'partial' else 'paid' end,
        updated_at = now()
    where id = f.id;
  end if;

  update public.fee_payments
  set voided = true,
      void_reason = trim(p_reason),
      voided_by = auth.uid(),
      voided_at = now(),
      updated_at = now()
  where id = p_payment_id;

  insert into public.finance_audit_logs(table_name, record_id, action, old_data, new_data, actor_id, actor_name)
  values ('fee_payments', p_payment_id, 'VOID', to_jsonb(p), (select to_jsonb(px) from public.fee_payments px where px.id=p_payment_id), auth.uid(), (select name from public.users where id=auth.uid()));

  return jsonb_build_object('ok', true, 'message', 'تم إلغاء الدفعة وعكس الأرصدة', 'amount_usd', usd);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.void_fee_payment(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- D) Health for restore
-- -------------------------------------------------------------
create or replace function public.final_missing_modules_restore_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'exam_integrity', jsonb_build_object(
      'table', to_regclass('public.exam_reference_sources') is not null,
      'ai_score', to_regprocedure('public.exam_ai_likelihood_score(text)') is not null,
      'similarity', to_regprocedure('public.exam_best_text_similarity(text,text)') is not null,
      'flags_view', to_regclass('public.v_exam_integrity_answer_flags') is not null,
      'pairs_view', to_regclass('public.v_exam_answer_similarity_pairs') is not null
    ),
    'cashbox', jsonb_build_object(
      'monthly_view', to_regclass('public.v_finance_receiver_monthly') is not null,
      'void_payment', to_regprocedure('public.void_fee_payment(uuid,text)') is not null
    ),
    'academic', jsonb_build_object(
      'subject_results', to_regclass('public.v_academic_subject_results') is not null,
      'student_summary', to_regclass('public.v_academic_student_summary') is not null
    )
  );
end;
$$;

grant execute on function public.final_missing_modules_restore_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'final_missing_modules_restore_ready' as status;

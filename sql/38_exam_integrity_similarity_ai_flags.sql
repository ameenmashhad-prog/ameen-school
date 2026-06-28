-- =============================================================
-- مدارس أمين الرضا (ع) — كشف تطابق الإجابات ومؤشرات النسخ/الذكاء الاصطناعي
-- يعمل محلياً داخل Supabase بدون أي اتصال خارجي.
-- ملاحظة: كشف الذكاء الاصطناعي مؤشرات احتمالية وليس حكماً قطعياً.
-- =============================================================

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

alter table public.exam_attempts add column if not exists violations_count int not null default 0;
alter table public.exam_attempts add column if not exists last_saved_at timestamptz;
alter table public.exam_attempts add column if not exists client_info jsonb not null default '{}'::jsonb;
alter table public.exam_answers add column if not exists is_draft boolean not null default true;

-- -------------------------------------------------------------
-- 1) تطبيع النص العربي/الإنجليزي للمقارنة
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

-- يحوّل answer_json إلى نص مفهوم للمطابقة/الترتيب/متعدد الاختيارات عند الحاجة.
create or replace function public.exam_answer_plain_text(p_answer_text text, p_answer_json jsonb)
returns text
language plpgsql
immutable
as $$
declare
  v text;
begin
  if nullif(trim(coalesce(p_answer_text,'')), '') is not null then
    return p_answer_text;
  end if;

  if p_answer_json is null or p_answer_json = '{}'::jsonb then
    return '';
  end if;

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

-- -------------------------------------------------------------
-- 2) مصادر محلية للمقارنة: نص من الإنترنت/كتاب/ذكاء اصطناعي يلصقه المعلم أو الإدارة
-- -------------------------------------------------------------
create table if not exists public.exam_reference_sources (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  source_type text not null default 'internet_paste' check (source_type in ('internet_paste','ai_sample','book','teacher_reference','other')),
  source_url text,
  exam_id uuid null references public.online_exams(id) on delete cascade,
  question_id uuid null references public.questions(id) on delete cascade,
  content_text text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.exam_reference_sources enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='exam_reference_sources' and policyname='exam_reference_sources_teacher_admin') then
    create policy exam_reference_sources_teacher_admin on public.exam_reference_sources
      for all to authenticated
      using (public.current_user_is_admin() or teacher_id = auth.uid())
      with check (public.current_user_is_admin() or teacher_id = auth.uid());
  end if;
end $$;

create index if not exists idx_exam_reference_sources_teacher on public.exam_reference_sources(teacher_id, source_type);
create index if not exists idx_exam_reference_sources_exam_question on public.exam_reference_sources(exam_id, question_id);

-- أفضل تشابه بين جواب الطالب ومصدر طويل عبر تقسيم المصدر إلى فقرات/جمل.
create or replace function public.exam_best_text_similarity(p_answer text, p_source text)
returns numeric
language sql
stable
as $$
  with a as (
    select public.exam_norm_text(p_answer) as txt
  ),
  chunks as (
    select public.exam_norm_text(p_source) as txt
    union all
    select public.exam_norm_text(x.chunk) as txt
    from regexp_split_to_table(coalesce(p_source,''), '[\n\.\!\?؟؛،]+') as x(chunk)
  ),
  filtered as (
    select txt from chunks where char_length(txt) >= 35
  )
  select coalesce(max(similarity((select txt from a), filtered.txt)),0)::numeric
  from filtered;
$$;

grant execute on function public.exam_best_text_similarity(text,text) to authenticated;

-- -------------------------------------------------------------
-- 3) مؤشرات احتمالية لتوليد الإجابة بالذكاء الاصطناعي
-- ليست دليلاً قطعياً، لكنها تعطي إنذاراً للمعلم/الإدارة.
-- -------------------------------------------------------------
create or replace function public.exam_ai_likelihood_score(p_text text)
returns int
language plpgsql
immutable
as $$
declare
  t text := lower(coalesce(p_text,''));
  n text := public.exam_norm_text(p_text);
  score int := 0;
  phrase_count int := 0;
  len int := 0;
begin
  len := char_length(n);

  if len < 120 then
    return 0;
  end if;

  if len >= 300 then score := score + 8; end if;
  if len >= 700 then score := score + 10; end if;
  if len >= 1200 then score := score + 8; end if;

  phrase_count := phrase_count
    + case when t like '%في الختام%' then 1 else 0 end
    + case when t like '%بشكل عام%' then 1 else 0 end
    + case when t like '%من ناحية أخرى%' then 1 else 0 end
    + case when t like '%علاوة على ذلك%' then 1 else 0 end
    + case when t like '%بالإضافة إلى ذلك%' then 1 else 0 end
    + case when t like '%بناءً على ما سبق%' or t like '%بناء على ما سبق%' then 1 else 0 end
    + case when t like '%يمكن القول%' then 1 else 0 end
    + case when t like '%لا شك أن%' then 1 else 0 end
    + case when t like '%من الجدير بالذكر%' then 1 else 0 end
    + case when t like '%in conclusion%' then 1 else 0 end
    + case when t like '%overall%' then 1 else 0 end
    + case when t like '%on the other hand%' then 1 else 0 end;

  if phrase_count >= 1 then score := score + 12; end if;
  if phrase_count >= 3 then score := score + 18; end if;
  if phrase_count >= 5 then score := score + 12; end if;

  -- تنسيق شائع في إجابات مولدات النصوص: عناوين/نقاط منظمة جداً.
  if t ~ '(^|\n)\s*[-•*]\s+' then score := score + 8; end if;
  if t ~ '(^|\n)\s*(اولا|أولا|ثانيا|ثالثا|first|second|third)[:：]' then score := score + 8; end if;

  -- إجابة طويلة جداً بدون أمثلة/أرقام/أسماء قد تكون عامة.
  if len > 600 and t !~ '[0-9٠-٩]' then score := score + 5; end if;

  -- تكرار عبارات ربط كثيرة مقارنة بطول النص.
  if (length(t) - length(replace(t, 'كما أن', ''))) / greatest(length('كما أن'),1) >= 2 then score := score + 6; end if;
  if (length(t) - length(replace(t, 'حيث إن', ''))) / greatest(length('حيث إن'),1) >= 2 then score := score + 6; end if;

  return least(score, 100);
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
  if t like '%في الختام%' or t like '%بشكل عام%' or t like '%بناء على ما سبق%' or t like '%بناءً على ما سبق%' then
    reasons := array_append(reasons, 'عبارات ختامية/انتقالية شائعة في النصوص المولدة');
  end if;
  if t like '%علاوة على ذلك%' or t like '%بالإضافة إلى ذلك%' or t like '%من ناحية أخرى%' then
    reasons := array_append(reasons, 'كثرة عبارات الربط الرسمية');
  end if;
  if t ~ '(^|\n)\s*[-•*]\s+' then reasons := array_append(reasons, 'تنسيق نقاط منظم بشكل غير معتاد'); end if;
  if len > 600 and t !~ '[0-9٠-٩]' then reasons := array_append(reasons, 'نص طويل عام بدون أمثلة رقمية أو تفاصيل محددة'); end if;
  return reasons;
end;
$$;

grant execute on function public.exam_ai_likelihood_reasons(text) to authenticated;

-- -------------------------------------------------------------
-- 4) النصوص المفحوصة
-- -------------------------------------------------------------
create or replace view public.v_exam_integrity_answer_texts
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
  att.started_at,
  att.submitted_at,
  att.status as attempt_status,
  att.violations_count,
  att.client_info,
  ans.question_id,
  q.prompt,
  q.question_type,
  ans.answered_at,
  ans.is_draft,
  ans.score_awarded,
  public.exam_answer_plain_text(ans.answer_text, ans.answer_json) as answer_text,
  public.exam_norm_text(public.exam_answer_plain_text(ans.answer_text, ans.answer_json)) as norm_text,
  char_length(public.exam_norm_text(public.exam_answer_plain_text(ans.answer_text, ans.answer_json))) as norm_len,
  case
    when att.started_at is not null and coalesce(att.submitted_at, ans.answered_at, now()) > att.started_at then
      round(char_length(public.exam_answer_plain_text(ans.answer_text, ans.answer_json))::numeric / greatest(extract(epoch from (coalesce(att.submitted_at, ans.answered_at, now()) - att.started_at))/60, 1), 2)
    else null
  end as chars_per_minute
from public.exam_answers ans
join public.exam_attempts att on att.id = ans.attempt_id
join public.online_exams e on e.id = att.exam_id
join public.questions q on q.id = ans.question_id
left join public.students st on st.id = att.student_id
left join public.classes c on c.id = e.class_id
left join public.sections sec on sec.id = e.section_id
left join public.subjects sub on sub.id = e.subject_id
where ans.is_draft = false
  and nullif(public.exam_norm_text(public.exam_answer_plain_text(ans.answer_text, ans.answer_json)), '') is not null
  and (
    public.current_user_is_admin()
    or e.teacher_id = auth.uid()
  );

grant select on public.v_exam_integrity_answer_texts to authenticated;

-- -------------------------------------------------------------
-- 5) تطابق إجابات الطلاب مع بعضهم
-- -------------------------------------------------------------
create or replace view public.v_exam_answer_similarity_pairs
with (security_invoker=true) as
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
  round(similarity(a.norm_text, b.norm_text)::numeric, 4) as similarity_score,
  round(similarity(a.norm_text, b.norm_text)::numeric * 100, 2) as similarity_percent,
  case
    when a.norm_text = b.norm_text then 'تطابق كامل تقريباً'
    when similarity(a.norm_text, b.norm_text) >= 0.88 then 'تشابه عالٍ جداً'
    when similarity(a.norm_text, b.norm_text) >= 0.74 then 'تشابه عالٍ'
    else 'تشابه متوسط'
  end as risk_label,
  left(a.answer_text, 700) as answer_a_preview,
  left(b.answer_text, 700) as answer_b_preview
from public.v_exam_integrity_answer_texts a
join public.v_exam_integrity_answer_texts b
  on b.exam_id = a.exam_id
 and b.question_id = a.question_id
 and b.answer_id > a.answer_id
 and b.student_id is distinct from a.student_id
where a.norm_len >= 45
  and b.norm_len >= 45
  and similarity(a.norm_text, b.norm_text) >= 0.70;

grant select on public.v_exam_answer_similarity_pairs to authenticated;

-- -------------------------------------------------------------
-- 6) تطابق جواب الطالب مع مصدر ملصق محلياً
-- -------------------------------------------------------------
create or replace view public.v_exam_answer_source_matches
with (security_invoker=true) as
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
  round(m.source_similarity, 4) as source_similarity,
  round(m.source_similarity * 100, 2) as source_similarity_percent,
  case
    when m.source_similarity >= 0.82 then 'مطابق لمصدر ملصق بدرجة عالية جداً'
    when m.source_similarity >= 0.68 then 'مطابق لمصدر ملصق بدرجة عالية'
    else 'تشابه محتمل مع مصدر ملصق'
  end as risk_label,
  left(t.answer_text, 900) as answer_preview,
  left(s.content_text, 900) as source_preview
from public.v_exam_integrity_answer_texts t
join public.exam_reference_sources s
  on (s.exam_id is null or s.exam_id = t.exam_id)
 and (s.question_id is null or s.question_id = t.question_id)
 and (public.current_user_is_admin() or s.teacher_id = auth.uid() or s.teacher_id = t.teacher_id)
cross join lateral (
  select public.exam_best_text_similarity(t.answer_text, s.content_text) as source_similarity
) m
where t.norm_len >= 45
  and char_length(public.exam_norm_text(s.content_text)) >= 45
  and m.source_similarity >= 0.55;

grant select on public.v_exam_answer_source_matches to authenticated;

-- -------------------------------------------------------------
-- 7) بطاقة خطر موحدة لكل إجابة
-- -------------------------------------------------------------
create or replace view public.v_exam_integrity_answer_flags
with (security_invoker=true) as
select
  t.*,
  coalesce((
    select max(p.similarity_score)
    from public.v_exam_answer_similarity_pairs p
    where p.answer_a_id = t.answer_id or p.answer_b_id = t.answer_id
  ),0)::numeric as max_peer_similarity,
  coalesce((
    select max(sm.source_similarity)
    from public.v_exam_answer_source_matches sm
    where sm.answer_id = t.answer_id
  ),0)::numeric as max_source_similarity,
  public.exam_ai_likelihood_score(t.answer_text) as ai_likelihood_score,
  public.exam_ai_likelihood_reasons(t.answer_text) as ai_likelihood_reasons,
  array_remove(array[
    case when coalesce((select max(p.similarity_score) from public.v_exam_answer_similarity_pairs p where p.answer_a_id = t.answer_id or p.answer_b_id = t.answer_id),0) >= 0.88 then 'تطابق عالٍ جداً مع طالب آخر' end,
    case when coalesce((select max(p.similarity_score) from public.v_exam_answer_similarity_pairs p where p.answer_a_id = t.answer_id or p.answer_b_id = t.answer_id),0) >= 0.70 then 'تشابه مع إجابة طالب آخر' end,
    case when coalesce((select max(sm.source_similarity) from public.v_exam_answer_source_matches sm where sm.answer_id = t.answer_id),0) >= 0.68 then 'تشابه عالٍ مع مصدر ملصق' end,
    case when public.exam_ai_likelihood_score(t.answer_text) >= 65 then 'مؤشرات توليد آلي محتملة' end,
    case when coalesce(t.violations_count,0) > 0 then 'توجد تنبيهات أثناء الاختبار' end,
    case when coalesce(t.chars_per_minute,0) >= 750 and t.norm_len >= 250 then 'سرعة إدخال/تسليم غير طبيعية' end
  ]::text[], null) as flags,
  least(100,
    greatest(
      round(coalesce((select max(p.similarity_score) from public.v_exam_answer_similarity_pairs p where p.answer_a_id = t.answer_id or p.answer_b_id = t.answer_id),0) * 100)::int,
      round(coalesce((select max(sm.source_similarity) from public.v_exam_answer_source_matches sm where sm.answer_id = t.answer_id),0) * 100)::int,
      public.exam_ai_likelihood_score(t.answer_text)
    )
    + least(coalesce(t.violations_count,0) * 5, 15)
    + case when coalesce(t.chars_per_minute,0) >= 750 and t.norm_len >= 250 then 10 else 0 end
  ) as risk_score
from public.v_exam_integrity_answer_texts t;

grant select on public.v_exam_integrity_answer_flags to authenticated;

notify pgrst, 'reload schema';

select 'exam_integrity_similarity_ai_flags_ready' as status;

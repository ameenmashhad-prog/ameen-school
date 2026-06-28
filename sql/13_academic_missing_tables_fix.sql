-- =============================================================
-- مدارس أمين الرضا (ع) — إصلاح الجداول الأكاديمية الناقصة
-- استخدميه إذا ظهرت continuous_assessments أو academic_exemption_decisions أو academic_flags = null
-- لا يحذف بيانات.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) تأكد من جدول الأوزان
-- -------------------------------------------------------------
create table if not exists public.grade_weights (
  id uuid primary key default gen_random_uuid()
);

-- جدول grade_weights كان موجوداً عندك بمخطط أقدم وفيه component إلزامي، لذلك نضيف/نضبط الأعمدة صراحة.
alter table public.grade_weights add column if not exists component text;
alter table public.grade_weights alter column component set default 'final_grade';
update public.grade_weights set component = 'final_grade' where component is null;

-- توافق مع المخطط القديم: عندك weight_percent إلزامي، لذلك نملؤه بقيمة 100 لأوزان الدرجة النهائية.
alter table public.grade_weights add column if not exists weight_percent numeric;
alter table public.grade_weights alter column weight_percent set default 100;
update public.grade_weights set weight_percent = 100 where weight_percent is null;

alter table public.grade_weights add column if not exists academic_year text not null default '2026-2027';
alter table public.grade_weights add column if not exists stage_type text;
alter table public.grade_weights add column if not exists continuous_weight numeric not null default 10;
alter table public.grade_weights add column if not exists monthly_exam_weight numeric not null default 90;
alter table public.grade_weights add column if not exists is_active boolean not null default true;
alter table public.grade_weights add column if not exists updated_by uuid null references public.users(id);
alter table public.grade_weights add column if not exists updated_at timestamptz not null default now();

-- قيود آمنة: نضيفها فقط إن لم تكن موجودة.
do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.grade_weights'::regclass and conname='grade_weights_stage_type_check') then
    alter table public.grade_weights
      add constraint grade_weights_stage_type_check
      check (stage_type in ('primary','middle','preparatory') or stage_type is null);
  end if;
exception when others then
  raise notice 'تعذر إضافة قيد stage_type مؤقتاً: %', sqlerrm;
end $$;

do $$ begin
  begin
    create unique index if not exists uq_grade_weights_year_stage_component
      on public.grade_weights(academic_year, stage_type, component)
      where stage_type is not null and component is not null;
  exception when others then
    raise notice 'تعذر إنشاء unique index على grade_weights بسبب تكرارات حالية: %', sqlerrm;
  end;
end $$;

-- إدخال أوزان 2026-2027 بدون الاعتماد على ON CONFLICT، مع component لتوافق الجدول القديم.
insert into public.grade_weights (component, weight_percent, academic_year, stage_type, continuous_weight, monthly_exam_weight, is_active)
select 'final_grade',100,'2026-2027','primary',20,80,true
where not exists (
  select 1 from public.grade_weights
  where academic_year='2026-2027' and stage_type='primary' and coalesce(component,'final_grade')='final_grade'
);

insert into public.grade_weights (component, weight_percent, academic_year, stage_type, continuous_weight, monthly_exam_weight, is_active)
select 'final_grade',100,'2026-2027','middle',10,90,true
where not exists (
  select 1 from public.grade_weights
  where academic_year='2026-2027' and stage_type='middle' and coalesce(component,'final_grade')='final_grade'
);

insert into public.grade_weights (component, weight_percent, academic_year, stage_type, continuous_weight, monthly_exam_weight, is_active)
select 'final_grade',100,'2026-2027','preparatory',10,90,true
where not exists (
  select 1 from public.grade_weights
  where academic_year='2026-2027' and stage_type='preparatory' and coalesce(component,'final_grade')='final_grade'
);

update public.grade_weights
set continuous_weight = case stage_type when 'primary' then 20 else 10 end,
    monthly_exam_weight = case stage_type when 'primary' then 80 else 90 end,
    component = coalesce(component,'final_grade'),
    weight_percent = coalesce(weight_percent, 100),
    is_active = true,
    updated_at = now()
where academic_year='2026-2027'
  and stage_type in ('primary','middle','preparatory')
  and coalesce(component,'final_grade')='final_grade'
  and (continuous_weight is null or monthly_exam_weight is null);

-- -------------------------------------------------------------
-- 2) إنشاء جدول التقييم المستمر المفقود
-- -------------------------------------------------------------
create table if not exists public.continuous_assessments (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  academic_period_id uuid null references public.academic_periods(id) on delete set null,
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid null references public.classes(id),
  subject_id uuid not null references public.subjects(id),
  teacher_id uuid null references public.users(id),
  assessment_month int check (assessment_month between 1 and 12),
  component_type text not null default 'participation' check (component_type in ('participation','homework','activity','project','discipline','quiz','other')),
  score numeric not null check (score >= 0 and score <= 100),
  max_score numeric not null default 100,
  assessment_date date not null default current_date,
  notes text,
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- -------------------------------------------------------------
-- 3) تأكد من جداول الاختبارات الشهرية
-- -------------------------------------------------------------
create table if not exists public.exams (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  academic_period_id uuid null references public.academic_periods(id) on delete set null,
  class_id uuid null references public.classes(id),
  subject_id uuid null references public.subjects(id),
  teacher_id uuid null references public.users(id),
  exam_name text not null default 'اختبار شهري',
  exam_type text not null default 'monthly',
  exam_order int,
  max_score numeric not null default 100,
  exam_date date,
  created_by uuid null default auth.uid(),
  created_at timestamptz not null default now()
);

alter table public.exams add column if not exists academic_year text not null default '2026-2027';
alter table public.exams add column if not exists academic_period_id uuid null references public.academic_periods(id) on delete set null;
alter table public.exams add column if not exists class_id uuid null references public.classes(id);
alter table public.exams add column if not exists subject_id uuid null references public.subjects(id);
alter table public.exams add column if not exists teacher_id uuid null references public.users(id);
alter table public.exams add column if not exists exam_name text not null default 'اختبار شهري';
alter table public.exams add column if not exists exam_type text not null default 'monthly';
alter table public.exams add column if not exists exam_order int;
alter table public.exams add column if not exists max_score numeric not null default 100;
alter table public.exams add column if not exists exam_date date;
alter table public.exams add column if not exists created_by uuid null default auth.uid();
alter table public.exams add column if not exists created_at timestamptz not null default now();

create table if not exists public.exam_scores (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exams(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  score numeric check (score >= 0 and score <= 100),
  absent boolean not null default false,
  excused boolean not null default false,
  notes text,
  entered_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(exam_id, student_id)
);

-- توافق مع مخطط سابق يستخدم is_absent / is_excused بدلاً من absent / excused.
alter table public.exam_scores add column if not exists absent boolean not null default false;
alter table public.exam_scores add column if not exists excused boolean not null default false;
alter table public.exam_scores add column if not exists notes text;
alter table public.exam_scores add column if not exists entered_by uuid null default auth.uid();
alter table public.exam_scores add column if not exists updated_at timestamptz not null default now();

do $$ begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='exam_scores' and column_name='is_absent') then
    execute 'update public.exam_scores set absent = coalesce(is_absent,false) where absent = false and is_absent is not null';
  end if;
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='exam_scores' and column_name='is_excused') then
    execute 'update public.exam_scores set excused = coalesce(is_excused,false) where excused = false and is_excused is not null';
  end if;
end $$;


alter table public.exam_scores add column if not exists absent boolean not null default false;
alter table public.exam_scores add column if not exists excused boolean not null default false;
alter table public.exam_scores add column if not exists notes text;
alter table public.exam_scores add column if not exists entered_by uuid null default auth.uid();
alter table public.exam_scores add column if not exists updated_at timestamptz not null default now();

-- -------------------------------------------------------------
-- 4) إنشاء قرارات الإعفاء والمخالفات الأكاديمية المفقودة
-- -------------------------------------------------------------
create table if not exists public.academic_exemption_decisions (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  academic_period_id uuid null references public.academic_periods(id) on delete set null,
  student_id uuid not null references public.students(id) on delete cascade,
  subject_id uuid null references public.subjects(id),
  exemption_kind text not null default 'review' check (exemption_kind in ('none','subject','general','candidate','review','cancelled')),
  status_ar text not null default 'إعفاء قيد المراجعة' check (status_ar in ('لا يوجد إعفاء','إعفاء مادة','إعفاء عام','مرشح للإعفاء','إعفاء قيد المراجعة','إعفاء ملغى')),
  calculated_average numeric,
  attendance_rate numeric,
  behavior_ok boolean,
  approved_by uuid null references public.users(id),
  approved_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);

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

-- -------------------------------------------------------------
-- 5) أعمدة توافق في الجداول القديمة
-- -------------------------------------------------------------
alter table public.students add column if not exists father_name text;
alter table public.students add column if not exists mother_name text;
alter table public.students add column if not exists last_name text;

alter table public.grades add column if not exists score numeric;
alter table public.grades add column if not exists grade numeric;
alter table public.grades add column if not exists mark numeric;
alter table public.grades add column if not exists value numeric;
alter table public.grades add column if not exists max_score numeric default 100;

alter table public.behavior_records add column if not exists points numeric default 0;
alter table public.behavior_records add column if not exists score numeric default 0;

-- -------------------------------------------------------------
-- 6) فهارس
-- -------------------------------------------------------------
create index if not exists idx_continuous_student_subject on public.continuous_assessments(student_id, subject_id);
create index if not exists idx_exam_scores_student on public.exam_scores(student_id);
create index if not exists idx_exams_subject_class on public.exams(subject_id, class_id);
create index if not exists idx_academic_decisions_student on public.academic_exemption_decisions(student_id);
create index if not exists idx_academic_flags_student on public.academic_flags(student_id);

-- -------------------------------------------------------------
-- 7) دالة المرحلة
-- -------------------------------------------------------------
create or replace function public.class_stage_type(p_class_id uuid)
returns text
language sql
stable
as $$
  select case
    when c.name ilike '%ابتدائي%' then 'primary'
    when c.name ilike '%متوسط%' then 'middle'
    when c.name ilike '%إعدادي%' or c.name ilike '%اعدادي%' then 'preparatory'
    else 'primary'
  end
  from public.classes c
  where c.id = p_class_id
  limit 1;
$$;


-- -------------------------------------------------------------
-- 7.5) قواعد المواد حسب المرحلة لمنع ظهور مواد غير مناسبة للصف
-- -------------------------------------------------------------
create or replace function public.academic_norm_ar(p_text text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    replace(replace(replace(replace(replace(replace(replace(lower(coalesce(p_text,'')),'إ','ا'),'أ','ا'),'آ','ا'),'ى','ي'),'ة','ه'),'ـ',''),' ',''),
    '[[:space:]]+', '', 'g'
  );
$$;

create or replace function public.academic_grade_number(p_class_name text)
returns int
language plpgsql
immutable
as $$
declare
  n text := public.academic_norm_ar(p_class_name);
begin
  if n like '%الاول%' or n like '%اول%' then return 1; end if;
  if n like '%الثاني%' or n like '%ثاني%' then return 2; end if;
  if n like '%الثالث%' or n like '%ثالث%' then return 3; end if;
  if n like '%الرابع%' or n like '%رابع%' then return 4; end if;
  if n like '%الخامس%' or n like '%خامس%' then return 5; end if;
  if n like '%السادس%' or n like '%سادس%' then return 6; end if;
  return 0;
end;
$$;

create or replace function public.academic_subject_allowed(p_stage_type text, p_class_name text, p_subject_name text)
returns boolean
language plpgsql
immutable
as $$
declare
  st text := coalesce(p_stage_type,'primary');
  g int := public.academic_grade_number(p_class_name);
  s text := public.academic_norm_ar(p_subject_name);
begin
  -- المواد المشتركة لكل المراحل
  if s like '%اسلام%' or s like '%قران%' then return true; end if;
  if s like '%عربي%' or s like '%العربيه%' then return true; end if;
  if s like '%انجليزي%' or s like '%انكليزي%' or s like '%english%' then return true; end if;
  if s like '%رياضيات%' then return true; end if;

  if st = 'primary' then
    if s like '%علوم%' then return true; end if;
    if s like '%فني%' or s like '%فن%' then return true; end if;
    if s like '%بدني%' or s like '%رياضه%' then return true; end if;
    if g between 4 and 6 and (s like '%اجتماع%') then return true; end if;
    return false;
  end if;

  if st = 'middle' then
    if s like '%فيزياء%' then return true; end if;
    if s like '%كيمياء%' then return true; end if;
    if s like '%احياء%' then return true; end if;
    if s like '%اجتماع%' then return true; end if;
    if s like '%فني%' or s like '%فن%' then return true; end if;
    if s like '%بدني%' or s like '%رياضه%' then return true; end if;
    return false;
  end if;

  if st = 'preparatory' then
    if s like '%فيزياء%' then return true; end if;
    if s like '%كيمياء%' then return true; end if;
    if s like '%احياء%' then return true; end if;
    if s like '%فني%' or s like '%فن%' then return true; end if;
    if s like '%بدني%' or s like '%رياضه%' then return true; end if;
    -- الاجتماعيات ليست من مواد الإعدادي حسب طلبك
    return false;
  end if;

  return false;
end;
$$;

-- -------------------------------------------------------------
-- 8) إعادة إنشاء Views الأكاديمية
-- -------------------------------------------------------------
drop view if exists public.v_academic_student_summary;
drop view if exists public.v_academic_subject_results;

create view public.v_academic_subject_results
with (security_invoker=true) as
with base_students as (
  select s.id as student_id, s.name as student_name, s.class_id, c.name as class_name, public.class_stage_type(s.class_id) as stage_type
  from public.students s
  left join public.classes c on c.id = s.class_id
),
subject_pairs as (
  select distinct student_id, subject_id from public.continuous_assessments
  union
  select distinct es.student_id, e.subject_id from public.exam_scores es join public.exams e on e.id = es.exam_id
  union
  select distinct student_id, subject_id from public.grades where subject_id is not null
),
cont as (
  select student_id, subject_id, round(avg(score / nullif(max_score,0) * 100),2) as continuous_avg
  from public.continuous_assessments
  group by student_id, subject_id
),
exam_avg as (
  select es.student_id, e.subject_id, round(avg(case when es.absent then 0 else es.score / nullif(e.max_score,0) * 100 end),2) as monthly_exam_avg
  from public.exam_scores es
  join public.exams e on e.id = es.exam_id
  where e.exam_type in ('monthly','extra')
  group by es.student_id, e.subject_id
),
legacy_grades as (
  select student_id, subject_id, round(avg(coalesce(score, grade, mark, value)::numeric),2) as legacy_avg
  from public.grades
  where subject_id is not null
  group by student_id, subject_id
),
att as (
  select student_id,
    round(100.0 * count(*) filter (where status in ('present','late')) / nullif(count(*),0),2) as attendance_rate
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
  gw.continuous_weight,
  gw.monthly_exam_weight,
  round((coalesce(c.continuous_avg, lg.legacy_avg, 0) * gw.continuous_weight + coalesce(e.monthly_exam_avg, lg.legacy_avg, 0) * gw.monthly_exam_weight) / nullif(gw.continuous_weight + gw.monthly_exam_weight,0),2) as final_average,
  coalesce(att.attendance_rate,100) as attendance_rate,
  coalesce(beh.behavior_points,0) as behavior_points,
  coalesce(flags.blocks,false) as has_blocking_flag,
  case
    when bs.stage_type='primary' then 'لا يوجد إعفاء'
    when round((coalesce(c.continuous_avg, lg.legacy_avg, 0) * gw.continuous_weight + coalesce(e.monthly_exam_avg, lg.legacy_avg, 0) * gw.monthly_exam_weight) / nullif(gw.continuous_weight + gw.monthly_exam_weight,0),2) >= 90
      and coalesce(att.attendance_rate,100) >= 85
      and coalesce(flags.blocks,false)=false
      and coalesce(beh.behavior_points,0) >= -10
      then 'إعفاء مادة'
    when round((coalesce(c.continuous_avg, lg.legacy_avg, 0) * gw.continuous_weight + coalesce(e.monthly_exam_avg, lg.legacy_avg, 0) * gw.monthly_exam_weight) / nullif(gw.continuous_weight + gw.monthly_exam_weight,0),2) >= 80
      then 'مرشح للإعفاء'
    else 'لا يوجد إعفاء'
  end as subject_exemption_status,
  greatest(90 - round((coalesce(c.continuous_avg, lg.legacy_avg, 0) * gw.continuous_weight + coalesce(e.monthly_exam_avg, lg.legacy_avg, 0) * gw.monthly_exam_weight) / nullif(gw.continuous_weight + gw.monthly_exam_weight,0),2),0) as points_to_subject_exemption
from subject_pairs sp
join base_students bs on bs.student_id = sp.student_id
left join public.subjects sub on sub.id = sp.subject_id
left join cont c on c.student_id = sp.student_id and c.subject_id = sp.subject_id
left join exam_avg e on e.student_id = sp.student_id and e.subject_id = sp.subject_id
left join legacy_grades lg on lg.student_id = sp.student_id and lg.subject_id = sp.subject_id
left join public.grade_weights gw on gw.stage_type = bs.stage_type and gw.academic_year='2026-2027' and gw.is_active=true and coalesce(gw.component,'final_grade')='final_grade'
left join att on att.student_id = sp.student_id
left join beh on beh.student_id = sp.student_id
left join flags on flags.student_id = sp.student_id and (flags.subject_id = sp.subject_id or flags.subject_id is null)
where public.academic_subject_allowed(bs.stage_type, bs.class_name, sub.name);

create view public.v_academic_student_summary
with (security_invoker=true) as
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
  case
    when min(r.final_average) < 85 then 85 - min(r.final_average)
    else 0
  end as points_needed_general
from public.v_academic_subject_results r
group by r.student_id, r.student_name, r.class_id, r.class_name, r.stage_type;

grant select on public.v_academic_subject_results to authenticated;
grant select on public.v_academic_student_summary to authenticated;
grant select, insert, update on public.grade_weights to authenticated;
grant select, insert, update on public.continuous_assessments to authenticated;
grant select, insert, update on public.exams to authenticated;
grant select, insert, update on public.exam_scores to authenticated;
grant select, insert, update on public.academic_exemption_decisions to authenticated;
grant select, insert, update on public.academic_flags to authenticated;

select
  to_regclass('public.grade_weights') as grade_weights,
  to_regclass('public.continuous_assessments') as continuous_assessments,
  to_regclass('public.exams') as exams,
  to_regclass('public.exam_scores') as exam_scores,
  to_regclass('public.academic_exemption_decisions') as academic_exemption_decisions,
  to_regclass('public.academic_flags') as academic_flags;

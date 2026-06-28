-- =============================================================
-- مدارس أمين الرضا (ع) — إصلاح فلترة المواد حسب المرحلة
-- يمنع ظهور الأحياء/الاجتماعيات للصف الأول الابتدائي ونحو ذلك.
-- شغليه بعد إنشاء جداول النظام الأكاديمي.
-- =============================================================

create extension if not exists pgcrypto;

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

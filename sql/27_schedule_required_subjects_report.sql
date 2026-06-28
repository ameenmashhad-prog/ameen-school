-- =============================================================
-- مدارس أمين الرضا (ع) — تقرير المواد الإلزامية الناقصة لكل صف/شعبة
-- يعتمد على قواعد المواد حسب المرحلة، ويقارنها مع weekly_schedule.
-- لا يحذف ولا يعدل بيانات.
-- =============================================================

create extension if not exists pgcrypto;

-- دوال تطبيع وقواعد المواد، مكررة هنا لجعل الملف مستقلاً إن لم يُشغل ملف 26.
create or replace function public.schedule_norm_ar(p_text text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    replace(replace(replace(replace(replace(replace(replace(lower(coalesce(p_text,'')),'إ','ا'),'أ','ا'),'آ','ا'),'ى','ي'),'ة','ه'),'ـ',''),' ',''),
    '[[:space:]]+', '', 'g'
  );
$$;

create or replace function public.schedule_stage_type(p_class_name text)
returns text
language plpgsql
immutable
as $$
declare
  n text := public.schedule_norm_ar(p_class_name);
begin
  if n like '%ابتدائي%' then return 'primary'; end if;
  if n like '%متوسط%' then return 'middle'; end if;
  if n like '%اعدادي%' then return 'preparatory'; end if;
  return 'primary';
end;
$$;

create or replace function public.schedule_grade_number(p_class_name text)
returns int
language plpgsql
immutable
as $$
declare
  n text := public.schedule_norm_ar(p_class_name);
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

create or replace function public.schedule_required_subjects_report(
  p_academic_period_id uuid default null
)
returns table(
  class_id uuid,
  class_name text,
  section_id uuid,
  section_code text,
  section_name text,
  academic_period_id uuid,
  stage_type text,
  required_subject text,
  matched_subject_id uuid,
  matched_subject_name text,
  status text
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  rec record;
  v_stage text;
  v_grade int;
begin
  for rec in
    select
      c.id as class_id,
      c.name as class_name,
      sec.id as section_id,
      sec.code as section_code,
      sec.name as section_name
    from public.classes c
    join public.sections sec on sec.class_id = c.id
    where coalesce(sec.is_active,true) = true
      and (
        exists (
          select 1
          from public.student_enrollments se
          where se.section_id = sec.id
            and se.enrollment_status = 'active'
        )
        or exists (
          select 1
          from public.weekly_schedule ws
          where ws.section_id = sec.id
            and (p_academic_period_id is null or ws.academic_period_id = p_academic_period_id)
        )
      )
    order by c.name, sec.code
  loop
    v_stage := public.schedule_stage_type(rec.class_name);
    v_grade := public.schedule_grade_number(rec.class_name);

    return query
    with req(label, aliases) as (
      values
        ('التربية الإسلامية'::text, array['التربية الاسلامية','التربية الإسلامية','الإسلامية','اسلامية','قرآن','القرآن']::text[]),
        ('اللغة العربية'::text, array['اللغة العربية','العربية','عربي']::text[]),
        ('اللغة الإنجليزية'::text, array['اللغة الانجليزية','اللغة الإنجليزية','الإنجليزية','انكليزي','انجليزي','english']::text[]),
        ('الرياضيات'::text, array['الرياضيات','رياضيات']::text[])
      union all
      select 'العلوم', array['العلوم','علوم']::text[] where v_stage = 'primary'
      union all
      select 'التربية الفنية', array['التربية الفنية','فنية','فن']::text[] where v_stage = 'primary'
      union all
      select 'التربية البدنية', array['التربية البدنية','البدنية','رياضة','التربية الرياضية']::text[] where v_stage = 'primary'
      union all
      select 'الاجتماعيات', array['الاجتماعيات','الاجتماعية','اجتماعيات','اجتماعية']::text[]
      where (v_stage = 'primary' and v_grade between 4 and 6) or v_stage = 'middle'
      union all
      select 'الأحياء', array['الأحياء','احياء']::text[] where v_stage in ('middle','preparatory')
      union all
      select 'الفيزياء', array['الفيزياء','فيزياء']::text[] where v_stage in ('middle','preparatory')
      union all
      select 'الكيمياء', array['الكيمياء','كيمياء']::text[] where v_stage in ('middle','preparatory')
    ), matched as (
      select
        req.label,
        sub.id as subject_id,
        sub.name as subject_name
      from req
      left join lateral (
        select s.id, s.name
        from public.subjects s
        where exists (
          select 1
          from unnest(req.aliases) a(alias)
          where public.schedule_norm_ar(s.name) like '%' || public.schedule_norm_ar(a.alias) || '%'
             or public.schedule_norm_ar(a.alias) like '%' || public.schedule_norm_ar(s.name) || '%'
        )
        order by s.name
        limit 1
      ) sub on true
    )
    select
      rec.class_id,
      rec.class_name,
      rec.section_id,
      rec.section_code,
      rec.section_name,
      p_academic_period_id,
      v_stage,
      m.label,
      m.subject_id,
      m.subject_name,
      case
        when m.subject_id is null then 'subject_not_in_db'
        when exists (
          select 1
          from public.weekly_schedule ws
          where ws.class_id = rec.class_id
            and ws.section_id = rec.section_id
            and ws.subject_id = m.subject_id
            and (p_academic_period_id is null or ws.academic_period_id = p_academic_period_id)
        ) then 'present'
        else 'missing'
      end as status
    from matched m;
  end loop;
end;
$$;

grant execute on function public.schedule_required_subjects_report(uuid) to authenticated;

notify pgrst, 'reload schema';

select 'schedule_required_subjects_report_ready' as status;

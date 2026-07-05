-- =============================================================
-- مدارس أمين الرضا (ع) — فحص وتنظيف الجدول حسب قواعد المواد والمرحلة
-- يعالج أمثلة مثل: الفيزياء أو الاجتماعيات في الأول الابتدائي.
-- ويمسح تكرار نفس الشعبة/الصف في نفس اليوم والحصة.
-- آمن افتراضياً: p_apply=false للتحليل فقط، p_apply=true للتنظيف.
-- =============================================================

create extension if not exists pgcrypto;

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

create or replace function public.schedule_subject_allowed(p_class_name text, p_subject_name text)
returns boolean
language plpgsql
immutable
as $$
declare
  st text := public.schedule_stage_type(p_class_name);
  g int := public.schedule_grade_number(p_class_name);
  s text := public.schedule_norm_ar(p_subject_name);
begin
  -- المواد الموحدة لكل الصفوف
  if s like '%اسلام%' or s like '%قران%' then return true; end if;
  if s like '%عربي%' or s like '%العربيه%' then return true; end if;
  if s like '%انجليزي%' or s like '%انكليزي%' or s like '%english%' then return true; end if;
  if s like '%رياضيات%' then return true; end if;

  if st = 'primary' then
    if s like '%علوم%' then return true; end if;
    if s like '%فني%' or s like '%فن%' then return true; end if;
    if s like '%بدني%' or s like '%رياضه%' then return true; end if;
    if g between 4 and 6 and s like '%اجتماع%' then return true; end if;
    return false;
  end if;

  if st = 'middle' then
    if s like '%فيزياء%' then return true; end if;
    if s like '%كيمياء%' then return true; end if;
    if s like '%احياء%' then return true; end if;
    if s like '%اجتماع%' then return true; end if;
    -- نشاط
    if s like '%فني%' or s like '%فن%' then return true; end if;
    if s like '%بدني%' or s like '%رياضه%' then return true; end if;
    return false;
  end if;

  if st = 'preparatory' then
    if s like '%فيزياء%' then return true; end if;
    if s like '%كيمياء%' then return true; end if;
    if s like '%احياء%' then return true; end if;
    -- نشاط فقط
    if s like '%فني%' or s like '%فن%' then return true; end if;
    if s like '%بدني%' or s like '%رياضه%' then return true; end if;
    -- الاجتماعيات ليست للإعدادي حسب القاعدة المطلوبة
    return false;
  end if;

  return false;
end;
$$;

create or replace function public.schedule_validate_weekly_schedule(
  p_academic_period_id uuid default null,
  p_apply boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  invalid_count int := 0;
  duplicate_count int := 0;
  deleted_invalid_sessions int := 0;
  deleted_invalid_schedule int := 0;
  deleted_duplicate_sessions int := 0;
  deleted_duplicate_schedule int := 0;
  protected_invalid int := 0;
  protected_duplicates int := 0;
  sample_invalid jsonb;
  sample_duplicates jsonb;
begin
  create temporary table if not exists tmp_invalid_schedule(id uuid primary key) on commit drop;
  truncate tmp_invalid_schedule;

  insert into tmp_invalid_schedule(id)
  select ws.id
  from public.weekly_schedule ws
  join public.classes c on c.id = ws.class_id
  join public.subjects s on s.id = ws.subject_id
  where (p_academic_period_id is null or ws.academic_period_id = p_academic_period_id)
    and public.schedule_subject_allowed(c.name, s.name) = false
  on conflict do nothing;

  select count(*) into invalid_count from tmp_invalid_schedule;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into sample_invalid
  from (
    select c.name as class_name, sec.code as section_code, sub.name as subject_name, u.name as teacher_name, ws.day, ws.period_number
    from public.weekly_schedule ws
    left join public.classes c on c.id = ws.class_id
    left join public.sections sec on sec.id = ws.section_id
    left join public.subjects sub on sub.id = ws.subject_id
    left join public.users u on u.id = ws.teacher_id
    where ws.id in (select id from tmp_invalid_schedule)
    order by c.name, ws.day, ws.period_number
    limit 20
  ) x;

  create temporary table if not exists tmp_duplicate_schedule(id uuid primary key) on commit drop;
  truncate tmp_duplicate_schedule;

  insert into tmp_duplicate_schedule(id)
  with ranked as (
    select
      ws.id,
      row_number() over (
        partition by ws.academic_period_id, coalesce(ws.section_id, '00000000-0000-0000-0000-000000000000'::uuid), ws.class_id, ws.day, ws.period_number
        order by
          case when ws.id in (select id from tmp_invalid_schedule) then 1 else 0 end,
          ws.updated_at nulls last,
          ws.created_at nulls last,
          ws.id
      ) as rn
    from public.weekly_schedule ws
    where (p_academic_period_id is null or ws.academic_period_id = p_academic_period_id)
  )
  select id from ranked where rn > 1
  on conflict do nothing;

  select count(*) into duplicate_count from tmp_duplicate_schedule;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into sample_duplicates
  from (
    select c.name as class_name, sec.code as section_code, ws.day, ws.period_number, count(*) as duplicates
    from public.weekly_schedule ws
    left join public.classes c on c.id = ws.class_id
    left join public.sections sec on sec.id = ws.section_id
    where (p_academic_period_id is null or ws.academic_period_id = p_academic_period_id)
    group by ws.academic_period_id, ws.section_id, ws.class_id, c.name, sec.code, ws.day, ws.period_number
    having count(*) > 1
    order by c.name, sec.code, ws.day, ws.period_number
    limit 20
  ) x;

  if p_apply then
    -- حذف جلسات الحصص غير الصالحة إن لم تكن عليها واجبات أو نشاط.
    delete from public.class_sessions cs
    using tmp_invalid_schedule inv
    where cs.weekly_schedule_id = inv.id
      and not exists(select 1 from public.teacher_activity_log tal where tal.class_session_id = cs.id)
      and not exists(select 1 from public.homeworks hw where hw.class_session_id = cs.id);
    get diagnostics deleted_invalid_sessions = row_count;

    delete from public.weekly_schedule ws
    using tmp_invalid_schedule inv
    where ws.id = inv.id
      and not exists(select 1 from public.class_sessions cs where cs.weekly_schedule_id = ws.id);
    get diagnostics deleted_invalid_schedule = row_count;

    select count(*) into protected_invalid
    from tmp_invalid_schedule inv
    join public.weekly_schedule ws on ws.id = inv.id;

    -- حذف جلسات التكرارات إن لم تكن عليها واجبات أو نشاط.
    delete from public.class_sessions cs
    using tmp_duplicate_schedule dup
    where cs.weekly_schedule_id = dup.id
      and not exists(select 1 from public.teacher_activity_log tal where tal.class_session_id = cs.id)
      and not exists(select 1 from public.homeworks hw where hw.class_session_id = cs.id);
    get diagnostics deleted_duplicate_sessions = row_count;

    delete from public.weekly_schedule ws
    using tmp_duplicate_schedule dup
    where ws.id = dup.id
      and not exists(select 1 from public.class_sessions cs where cs.weekly_schedule_id = ws.id);
    get diagnostics deleted_duplicate_schedule = row_count;

    select count(*) into protected_duplicates
    from tmp_duplicate_schedule dup
    join public.weekly_schedule ws on ws.id = dup.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'apply', p_apply,
    'invalid_subject_rows', invalid_count,
    'duplicate_slot_rows', duplicate_count,
    'deleted_invalid_sessions', deleted_invalid_sessions,
    'deleted_invalid_schedule_rows', deleted_invalid_schedule,
    'deleted_duplicate_sessions', deleted_duplicate_sessions,
    'deleted_duplicate_schedule_rows', deleted_duplicate_schedule,
    'protected_invalid_rows', protected_invalid,
    'protected_duplicate_rows', protected_duplicates,
    'sample_invalid', sample_invalid,
    'sample_duplicates', sample_duplicates
  );
end;
$$;

grant execute on function public.schedule_validate_weekly_schedule(uuid,boolean) to authenticated;
notify pgrst, 'reload schema';

select 'schedule_subject_rules_cleanup_ready' as status;

-- =============================================================
-- مدارس أمين الرضا (ع) — Runtime Fix للإنجازات ومخطط المنهج
-- يعالج:
-- 1) الصفحة الرئيسية الذكية إذا لم تُشغّل SQL 109.
-- 2) مخطط المنهج إذا كانت الجداول موجودة من محاولة سابقة ناقصة أعمدة مثل start_date.
-- 3) get_curriculum_planner_payload إذا كان academic_periods لا يحتوي start_date.
-- آمن ويمكن تشغيله أكثر من مرة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) تأكد من أعمدة curriculum_plans الأساسية إذا كان الجدول موجوداً مسبقاً
-- -------------------------------------------------------------
do $$
begin
  if to_regclass('public.curriculum_plans') is not null then
    alter table public.curriculum_plans add column if not exists source_id uuid null;
    alter table public.curriculum_plans add column if not exists teacher_id uuid null default auth.uid();
    alter table public.curriculum_plans add column if not exists class_id uuid null;
    alter table public.curriculum_plans add column if not exists section_id uuid null;
    alter table public.curriculum_plans add column if not exists subject_id uuid null;
    alter table public.curriculum_plans add column if not exists academic_period_id uuid null;
    alter table public.curriculum_plans add column if not exists title text;
    alter table public.curriculum_plans add column if not exists academic_year text not null default '2026-2027';
    alter table public.curriculum_plans add column if not exists lessons_per_week int not null default 4;
    alter table public.curriculum_plans add column if not exists start_date date not null default current_date;
    alter table public.curriculum_plans add column if not exists end_date date;
    alter table public.curriculum_plans add column if not exists status text not null default 'draft';
    alter table public.curriculum_plans add column if not exists auto_generated boolean not null default true;
    alter table public.curriculum_plans add column if not exists teacher_notes text;
    alter table public.curriculum_plans add column if not exists created_at timestamptz not null default now();
    alter table public.curriculum_plans add column if not exists updated_at timestamptz not null default now();
    update public.curriculum_plans set title = coalesce(title,'خطة منهج') where title is null;
  end if;

  if to_regclass('public.curriculum_plan_slots') is not null then
    alter table public.curriculum_plan_slots add column if not exists planned_date date;
    alter table public.curriculum_plan_slots add column if not exists month_index int not null default 1;
    alter table public.curriculum_plan_slots add column if not exists week_index int not null default 1;
    alter table public.curriculum_plan_slots add column if not exists day_index int;
    alter table public.curriculum_plan_slots add column if not exists slot_order int not null default 1;
    alter table public.curriculum_plan_slots add column if not exists planned_duration_minutes int not null default 45;
    alter table public.curriculum_plan_slots add column if not exists status text not null default 'planned';
    alter table public.curriculum_plan_slots add column if not exists progress_percent int not null default 0;
    alter table public.curriculum_plan_slots add column if not exists manual_override boolean not null default false;
    alter table public.curriculum_plan_slots add column if not exists teacher_notes text;
    alter table public.curriculum_plan_slots add column if not exists completed_at timestamptz;
    alter table public.curriculum_plan_slots add column if not exists updated_at timestamptz not null default now();
  end if;

  if to_regclass('public.curriculum_lessons') is not null then
    alter table public.curriculum_lessons add column if not exists sequence_no int not null default 1;
    alter table public.curriculum_lessons add column if not exists unit_title text;
    alter table public.curriculum_lessons add column if not exists lesson_title text;
    alter table public.curriculum_lessons add column if not exists page_start int;
    alter table public.curriculum_lessons add column if not exists page_end int;
    alter table public.curriculum_lessons add column if not exists estimated_sessions numeric not null default 1;
    alter table public.curriculum_lessons add column if not exists notes text;
    alter table public.curriculum_lessons add column if not exists is_custom boolean not null default false;
    alter table public.curriculum_lessons add column if not exists is_active boolean not null default true;
    update public.curriculum_lessons set lesson_title = coalesce(lesson_title,'درس') where lesson_title is null;
  end if;
end $$;

-- -------------------------------------------------------------
-- 2) إعادة إنشاء View التقدم بشكل متوافق
-- -------------------------------------------------------------
do $$
begin
  if to_regclass('public.curriculum_plans') is not null and to_regclass('public.curriculum_plan_slots') is not null then
    execute $v$
      create or replace view public.v_curriculum_plan_progress
      with (security_invoker=true) as
      select
        p.id as plan_id,
        p.title,
        p.teacher_id,
        p.class_id,
        c.name as class_name,
        p.subject_id,
        sub.name as subject_name,
        p.status,
        p.lessons_per_week,
        count(sl.id)::int as total_slots,
        count(sl.id) filter (where sl.status='completed')::int as completed_slots,
        count(sl.id) filter (where sl.status='in_progress')::int as in_progress_slots,
        count(sl.id) filter (where sl.status in ('planned','postponed'))::int as remaining_slots,
        count(sl.id) filter (where sl.manual_override)::int as manual_edits,
        case when count(sl.id)=0 then 0 else round(count(sl.id) filter (where sl.status='completed')::numeric / count(sl.id) * 100)::int end as progress_percent,
        max(sl.updated_at) as last_update
      from public.curriculum_plans p
      left join public.curriculum_plan_slots sl on sl.plan_id = p.id
      left join public.classes c on c.id = p.class_id
      left join public.subjects sub on sub.id = p.subject_id
      group by p.id, c.name, sub.name
    $v$;
    grant select on public.v_curriculum_plan_progress to authenticated;
  end if;
end $$;

-- -------------------------------------------------------------
-- 3) Payload متوافق لا يعتمد على academic_periods.start_date
-- -------------------------------------------------------------
create or replace function public.get_curriculum_planner_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  u record;
  plans jsonb := '[]'::jsonb;
  progress jsonb := '[]'::jsonb;
  slots jsonb := '[]'::jsonb;
  sources jsonb := '[]'::jsonb;
  classes jsonb := '[]'::jsonb;
  subjects jsonb := '[]'::jsonb;
  sections jsonb := '[]'::jsonb;
  periods jsonb := '[]'::jsonb;
  audit jsonb := '[]'::jsonb;
begin
  select id,name,email,role,is_super_admin into u from public.users where id=auth.uid();
  if u.id is null then return jsonb_build_object('ok',false,'message','يجب تسجيل الدخول'); end if;
  if to_regprocedure('public.current_user_can_curriculum()') is not null and not public.current_user_can_curriculum() then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية تخطيط المنهج');
  end if;

  if to_regclass('public.curriculum_plans') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    into plans
    from (select * from public.curriculum_plans where teacher_id=u.id or public.current_user_is_admin() order by created_at desc limit 100) x;
  end if;

  if to_regclass('public.v_curriculum_plan_progress') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.last_update desc nulls last), '[]'::jsonb)
    into progress
    from (select * from public.v_curriculum_plan_progress where teacher_id=u.id or public.current_user_is_admin() order by last_update desc nulls last limit 100) x;
  end if;

  if to_regclass('public.v_curriculum_plan_slots_detailed') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.month_index, x.week_index, x.slot_order), '[]'::jsonb)
    into slots
    from (select * from public.v_curriculum_plan_slots_detailed where teacher_id=u.id or public.current_user_is_admin() order by month_index, week_index, slot_order limit 1500) x;
  end if;

  if to_regclass('public.curriculum_sources') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    into sources
    from (select * from public.curriculum_sources where teacher_id=u.id or public.current_user_is_admin() order by created_at desc limit 100) x;
  end if;

  if to_regclass('public.classes') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name), '[]'::jsonb) into classes from public.classes;
  end if;
  if to_regclass('public.subjects') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name), '[]'::jsonb) into subjects from public.subjects;
  end if;
  if to_regclass('public.sections') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code,'class_id',class_id) order by name), '[]'::jsonb) into sections from public.sections;
  end if;
  if to_regclass('public.academic_periods') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name), '[]'::jsonb) into periods from public.academic_periods;
  end if;

  if to_regclass('public.curriculum_plan_audit') is not null and to_regclass('public.curriculum_plans') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    into audit
    from (
      select a.*
      from public.curriculum_plan_audit a
      left join public.curriculum_plans p on p.id=a.plan_id
      where p.teacher_id=u.id or public.current_user_is_admin()
      order by a.created_at desc
      limit 80
    ) x;
  end if;

  return jsonb_build_object('ok',true,'profile',to_jsonb(u),'plans',plans,'progress',progress,'slots',slots,'sources',sources,'classes',classes,'subjects',subjects,'sections',sections,'periods',periods,'audit',audit);
end;
$$;

grant execute on function public.get_curriculum_planner_payload() to authenticated;

-- -------------------------------------------------------------
-- 4) Health Check
-- -------------------------------------------------------------
create or replace function public.runtime_fix_achievements_curriculum_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'checked_at', now(),
    'achievements', jsonb_build_object(
      'achievement_badges', to_regclass('public.achievement_badges') is not null,
      'get_achievements_payload', to_regprocedure('public.get_achievements_payload(text)') is not null,
      'get_my_badge_progress', to_regprocedure('public.get_my_badge_progress()') is not null
    ),
    'curriculum', jsonb_build_object(
      'curriculum_plans', to_regclass('public.curriculum_plans') is not null,
      'start_date_column', exists(select 1 from information_schema.columns where table_schema='public' and table_name='curriculum_plans' and column_name='start_date'),
      'get_curriculum_planner_payload', to_regprocedure('public.get_curriculum_planner_payload()') is not null,
      'v_curriculum_plan_progress', to_regclass('public.v_curriculum_plan_progress') is not null
    )
  );
end;
$$;

grant execute on function public.runtime_fix_achievements_curriculum_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.runtime_fix_achievements_curriculum_health_check() as runtime_fix_achievements_curriculum;

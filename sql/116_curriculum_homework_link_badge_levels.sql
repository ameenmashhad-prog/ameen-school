-- =============================================================
-- مدارس أمين الرضا (ع) — ربط الخطة السنوية بالواجبات + مستويات الشارات
-- 1) اختيار درس من الخطة عند إنشاء واجب.
-- 2) تعليم الدرس كمُعطى تلقائياً عند نشر الواجب المرتبط.
-- 3) شارات بمستويات: برونزية/فضية/ذهبية/ماسية حسب الإنجاز التراكمي.
-- آمن ويمكن تشغيله أكثر من مرة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) أعمدة ربط الواجب بالخطة
-- -------------------------------------------------------------
do $$
begin
  if to_regclass('public.homeworks') is not null then
    alter table public.homeworks add column if not exists curriculum_plan_id uuid null references public.curriculum_plans(id) on delete set null;
    alter table public.homeworks add column if not exists curriculum_slot_id uuid null references public.curriculum_plan_slots(id) on delete set null;
    alter table public.homeworks add column if not exists curriculum_lesson_id uuid null references public.curriculum_lessons(id) on delete set null;
    alter table public.homeworks add column if not exists curriculum_lesson_title text;
  end if;

  if to_regclass('public.lesson_plans') is not null then
    alter table public.lesson_plans add column if not exists curriculum_plan_id uuid null references public.curriculum_plans(id) on delete set null;
    alter table public.lesson_plans add column if not exists curriculum_slot_id uuid null references public.curriculum_plan_slots(id) on delete set null;
    alter table public.lesson_plans add column if not exists curriculum_lesson_id uuid null references public.curriculum_lessons(id) on delete set null;
  end if;
end $$;

create index if not exists idx_homeworks_curriculum_slot on public.homeworks(curriculum_slot_id) where curriculum_slot_id is not null;

-- -------------------------------------------------------------
-- 2) مواضيع الخطة المتاحة للمعلم
-- -------------------------------------------------------------
create or replace function public.get_teacher_curriculum_topics(
  p_section_id uuid default null,
  p_class_id uuid default null,
  p_subject_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  items jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok',false,'message','يجب تسجيل الدخول','items','[]'::jsonb);
  end if;

  if to_regclass('public.v_curriculum_plan_slots_detailed') is null then
    return jsonb_build_object('ok',true,'items','[]'::jsonb,'message','مخطط المنهج غير مفعل');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'slot_id', s.id,
    'plan_id', s.plan_id,
    'lesson_id', s.lesson_id,
    'lesson_title', s.lesson_title,
    'unit_title', s.unit_title,
    'subject_id', s.subject_id,
    'subject_name', s.subject_name,
    'class_id', s.class_id,
    'class_name', s.class_name,
    'section_id', s.section_id,
    'section_name', s.section_name,
    'week_index', s.week_index,
    'month_index', s.month_index,
    'planned_date', s.planned_date,
    'status', s.status,
    'progress_percent', s.progress_percent,
    'page_start', s.page_start,
    'page_end', s.page_end
  ) order by s.status='completed', s.month_index, s.week_index, s.slot_order), '[]'::jsonb)
  into items
  from public.v_curriculum_plan_slots_detailed s
  where (s.teacher_id = auth.uid() or public.current_user_is_admin())
    and s.status not in ('cancelled')
    and (p_subject_id is null or s.subject_id = p_subject_id)
    and (p_class_id is null or s.class_id = p_class_id)
    and (p_section_id is null or s.section_id is null or s.section_id = p_section_id)
  limit 300;

  return jsonb_build_object('ok',true,'items',coalesce(items,'[]'::jsonb));
end;
$$;

grant execute on function public.get_teacher_curriculum_topics(uuid,uuid,uuid) to authenticated;

-- -------------------------------------------------------------
-- 3) ربط واجب بدرس من الخطة وتعليم الدرس كمُعطى عند النشر
-- -------------------------------------------------------------
create or replace function public.link_homework_to_curriculum(
  p_homework_id uuid,
  p_slot_id uuid default null,
  p_custom_title text default null,
  p_mark_given boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  sl record;
  before_slot jsonb;
  lesson_title text;
begin
  if p_homework_id is null then
    return jsonb_build_object('ok',false,'message','homework_id مطلوب');
  end if;

  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then
    return jsonb_build_object('ok',false,'message','الواجب غير موجود');
  end if;

  if not (h.teacher_id = auth.uid() or public.current_user_is_admin()) then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية ربط هذا الواجب بالخطة');
  end if;

  lesson_title := nullif(trim(coalesce(p_custom_title,'')), '');

  if p_slot_id is not null then
    select * into sl from public.v_curriculum_plan_slots_detailed where id = p_slot_id;
    if sl.id is null then
      return jsonb_build_object('ok',false,'message','درس الخطة غير موجود');
    end if;
    if not (sl.teacher_id = auth.uid() or public.current_user_is_admin()) then
      return jsonb_build_object('ok',false,'message','لا تملك صلاحية على درس الخطة');
    end if;
    lesson_title := coalesce(lesson_title, sl.lesson_title);

    update public.homeworks
    set curriculum_plan_id = sl.plan_id,
        curriculum_slot_id = sl.id,
        curriculum_lesson_id = sl.lesson_id,
        curriculum_lesson_title = lesson_title
    where id = p_homework_id;

    if p_mark_given then
      select to_jsonb(x) into before_slot from public.curriculum_plan_slots x where x.id = p_slot_id;
      update public.curriculum_plan_slots
      set status = 'completed',
          progress_percent = 100,
          completed_at = coalesce(completed_at, now()),
          manual_override = true,
          teacher_notes = coalesce(teacher_notes,'') || case when teacher_notes is null or teacher_notes='' then '' else E'\n' end || 'تم تعليم الدرس كمُعطى تلقائياً عند نشر واجب مرتبط: ' || coalesce(h.title,''),
          updated_at = now()
      where id = p_slot_id;
      perform public.curriculum_log(sl.plan_id, p_slot_id, 'mark_given_from_homework', before_slot, (select to_jsonb(x) from public.curriculum_plan_slots x where x.id=p_slot_id));
    end if;
  else
    update public.homeworks
    set curriculum_plan_id = null,
        curriculum_slot_id = null,
        curriculum_lesson_id = null,
        curriculum_lesson_title = lesson_title
    where id = p_homework_id;
  end if;

  return jsonb_build_object('ok',true,'message','تم ربط الواجب بالخطة','lesson_title',lesson_title,'marked_given',p_mark_given and p_slot_id is not null);
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.link_homework_to_curriculum(uuid,uuid,text,boolean) to authenticated;

-- -------------------------------------------------------------
-- 4) مستويات الشارات
-- -------------------------------------------------------------
create or replace function public._achievement_level_info(p_code text, p_current numeric, p_target numeric)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  thresholds numeric[];
  labels text[] := array['برونزية','فضية','ذهبية','ماسية'];
  level text := 'غير مكتملة';
  next_level text := 'برونزية';
  next_target numeric;
  idx int;
  pct int := 0;
begin
  if p_code in ('teacher_lesson_prep_streak','teacher_homework_followup','teacher_grades_uploader','teacher_attendance_followup') then
    thresholds := array[30,60,90,120];
  elsif p_code in ('student_homework_complete') then
    thresholds := array[25,50,75,100];
  elsif p_code in ('student_perfect_attendance_30') then
    thresholds := array[30,60,90,120];
  elsif p_code in ('teacher_digital_exam_builder','student_exam_ready') then
    thresholds := array[3,6,10,15];
  else
    thresholds := array[coalesce(nullif(p_target,0),10), coalesce(nullif(p_target,0),10)*2, coalesce(nullif(p_target,0),10)*3, coalesce(nullif(p_target,0),10)*4];
  end if;

  for idx in 1..array_length(thresholds,1) loop
    if coalesce(p_current,0) >= thresholds[idx] then
      level := labels[idx];
    elsif next_target is null then
      next_level := labels[idx];
      next_target := thresholds[idx];
    end if;
  end loop;

  if next_target is null then
    next_level := 'مكتملة بالكامل';
    next_target := thresholds[array_length(thresholds,1)];
    pct := 100;
  else
    pct := least(100, greatest(0, round(coalesce(p_current,0) / nullif(next_target,0) * 100)::int));
  end if;

  return jsonb_build_object(
    'levels', jsonb_build_array(
      jsonb_build_object('name','برونزية','target',thresholds[1]),
      jsonb_build_object('name','فضية','target',thresholds[2]),
      jsonb_build_object('name','ذهبية','target',thresholds[3]),
      jsonb_build_object('name','ماسية','target',thresholds[4])
    ),
    'current_level', level,
    'next_level', next_level,
    'next_target', next_target,
    'level_progress_percent', pct
  );
end;
$$;

grant execute on function public._achievement_level_info(text,numeric,numeric) to authenticated;

create or replace function public._badge_progress_card(
  p_code text,
  p_title text,
  p_desc text,
  p_role text,
  p_category text,
  p_icon text,
  p_color text,
  p_level text,
  p_points int,
  p_current numeric,
  p_target numeric,
  p_metric_label text,
  p_owner_name text default null,
  p_cta_url text default 'achievements.html?lite=1'
)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  lvl jsonb;
  target numeric := coalesce(nullif(p_target,0),1);
begin
  lvl := public._achievement_level_info(p_code, coalesce(p_current,0), target);
  return jsonb_build_object(
    'code', p_code,
    'title', p_title,
    'description', p_desc,
    'target_role', p_role,
    'category', p_category,
    'icon_key', p_icon,
    'color', p_color,
    'level', p_level,
    'points', coalesce(p_points,0),
    'current_value', coalesce(p_current,0),
    'target_value', target,
    'progress_percent', least(100, greatest(0, round(coalesce(p_current,0) / target * 100)::int)),
    'is_earned', coalesce(p_current,0) >= target,
    'metric_label', p_metric_label,
    'owner_name', p_owner_name,
    'cta_url', coalesce(p_cta_url,'achievements.html?lite=1'),
    'levels', lvl->'levels',
    'current_level', lvl->>'current_level',
    'next_level', lvl->>'next_level',
    'next_target', (lvl->>'next_target')::numeric,
    'level_progress_percent', (lvl->>'level_progress_percent')::int
  );
end;
$$;

grant execute on function public._badge_progress_card(text,text,text,text,text,text,text,text,int,numeric,numeric,text,text,text) to authenticated;

-- -------------------------------------------------------------
-- 5) Health Check
-- -------------------------------------------------------------
create or replace function public.curriculum_homework_badge_levels_health_check()
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
    'homework_columns', jsonb_build_object(
      'curriculum_slot_id', exists(select 1 from information_schema.columns where table_schema='public' and table_name='homeworks' and column_name='curriculum_slot_id'),
      'curriculum_lesson_title', exists(select 1 from information_schema.columns where table_schema='public' and table_name='homeworks' and column_name='curriculum_lesson_title')
    ),
    'functions', jsonb_build_object(
      'get_teacher_curriculum_topics', to_regprocedure('public.get_teacher_curriculum_topics(uuid,uuid,uuid)') is not null,
      'link_homework_to_curriculum', to_regprocedure('public.link_homework_to_curriculum(uuid,uuid,text,boolean)') is not null,
      'achievement_level_info', to_regprocedure('public._achievement_level_info(text,numeric,numeric)') is not null,
      'badge_progress_card', to_regprocedure('public._badge_progress_card(text,text,text,text,text,text,text,text,int,numeric,numeric,text,text,text)') is not null
    ),
    'note', 'الواجبات يمكن ربطها بدروس الخطة، ونشر الواجب يعلّم الدرس كمُعطى. الشارات تدعم مستويات تراكمية.'
  );
end;
$$;

grant execute on function public.curriculum_homework_badge_levels_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.curriculum_homework_badge_levels_health_check() as curriculum_homework_badge_levels_health;

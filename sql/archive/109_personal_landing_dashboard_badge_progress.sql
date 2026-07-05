-- =============================================================
-- مدارس أمين الرضا (ع) — الصفحة الرئيسية الذكية + تقدم الشارات
-- تعرض: أهم المهام، الجدول، التقويم الثلاثي، الساعة، شارات الإنجاز المحسوبة.
-- آمن ويمكن تشغيله أكثر من مرة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) زرع/تحديث شارات إلكترونية ومحسوبة
-- -------------------------------------------------------------
do $$
begin
  if to_regclass('public.achievement_badges') is not null then
    insert into public.achievement_badges
      (code,title_ar,title_fa,title_en,description_ar,description_fa,description_en,target_role,category,icon_key,color,level,points,trigger_type,trigger_metric,threshold,sort_order,is_active)
    values
      ('student_perfect_attendance_30','دوام متواصل','حضور پیوسته','Perfect Attendance','لا يوجد أي يوم غياب خلال آخر 30 يوماً.','بدون غیبت در ۳۰ روز اخیر.','No absence during the last 30 days.','student','attendance','star','emerald','gold',50,'auto','absence_count_30',0,11,true),
      ('student_homework_complete','واجبات متكاملة','تکالیف کامل','Complete Homework','إكمال وتسليم الواجبات المنشورة.','تکمیل و ارسال تکالیف منتشرشده.','Complete and submit published assignments.','student','homework','book','orange','gold',45,'auto','homework_completion_rate',100,12,true),
      ('student_exam_ready','جاهز للاختبارات الإلكترونية','آماده آزمون آنلاین','E-Exam Ready','المشاركة في الاختبارات الإلكترونية المتاحة.','شرکت در آزمون‌های آنلاین.','Participating in available online exams.','student','exams','exam','cyan','silver',30,'auto','online_exam_attempts',3,13,true),
      ('student_growth_path','مسار التطور','مسیر پیشرفت','Growth Path','تحسن في الدرجات أو انتظام في المهام.','پیشرفت در نمرات یا نظم در کارها.','Improvement in grades or task consistency.','student','growth','sparkle','violet','silver',35,'auto','grade_average',80,14,true),
      ('student_calendar_achiever','منجز التقويم','دستاورد تقویم','Calendar Achiever','تسجيل إنجازات من أجندة التقويم الذكي.','ثبت دستاوردها از دستورکار تقویم.','Completing smart-calendar agenda items.','student','calendar','calendar','gold','bronze',20,'auto','completed_items_count',5,15,true),

      ('teacher_lesson_prep_streak','تحضير مستمر','آمادگی پیوسته درس','Continuous Lesson Prep','تحضير دروس مستمر بدون انقطاع.','آماده‌سازی پیوسته درس‌ها.','Continuous lesson preparation.','teacher','planning','book','emerald','gold',55,'auto','lesson_plans_30',12,211,true),
      ('teacher_homework_followup','متابعة الواجبات','پیگیری تکالیف','Homework Follow-up','إنشاء الواجبات ومتابعة تصحيحها.','ایجاد و پیگیری تصحیح تکالیف.','Creating and grading assignments.','teacher','homework','check','orange','gold',50,'auto','homework_grades_30',30,212,true),
      ('teacher_grades_uploader','تنزيل الدرجات','ثبت نمرات','Grades Uploader','تنزيل درجات الاختبارات والتقييمات باستمرار.','ثبت مستمر نمرات و ارزیابی‌ها.','Consistent grade entry.','teacher','grades','chart','indigo','silver',40,'auto','grade_entries_30',40,213,true),
      ('teacher_digital_exam_builder','باني الاختبارات الإلكترونية','سازنده آزمون آنلاین','Digital Exam Builder','إنشاء اختبارات إلكترونية للطلاب.','ایجاد آزمون‌های آنلاین.','Creating online exams.','teacher','exams','exam','cyan','silver',35,'auto','online_exams_created',2,214,true),
      ('teacher_attendance_followup','متابعة الحضور','پیگیری حضور','Attendance Follow-up','متابعة الحضور والغياب بشكل منتظم.','پیگیری منظم حضور و غیاب.','Regular attendance follow-up.','teacher','attendance','check','teal','bronze',25,'auto','attendance_records_30',10,215,true),
      ('teacher_calendar_achiever','منجز أجندة المعلم','دستاورد دستورکار معلم','Teacher Agenda Achiever','إنجاز مهام التقويم والأجندة.','انجام وظایف تقویم و دستورکار.','Completing calendar agenda tasks.','teacher','calendar','calendar','gold','bronze',20,'auto','completed_items_count',5,216,true)
    on conflict (code) do update set
      title_ar=excluded.title_ar,
      title_fa=excluded.title_fa,
      title_en=excluded.title_en,
      description_ar=excluded.description_ar,
      description_fa=excluded.description_fa,
      description_en=excluded.description_en,
      target_role=excluded.target_role,
      category=excluded.category,
      icon_key=excluded.icon_key,
      color=excluded.color,
      level=excluded.level,
      points=excluded.points,
      trigger_type=excluded.trigger_type,
      trigger_metric=excluded.trigger_metric,
      threshold=excluded.threshold,
      sort_order=excluded.sort_order,
      is_active=true,
      updated_at=now();
  end if;
end $$;

-- -------------------------------------------------------------
-- 2) دوال مساعدة
-- -------------------------------------------------------------
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
language sql
security definer
set search_path = public
stable
as $$
  select jsonb_build_object(
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
    'target_value', coalesce(nullif(p_target,0),1),
    'progress_percent', least(100, greatest(0, round(coalesce(p_current,0) / coalesce(nullif(p_target,0),1) * 100)::int)),
    'is_earned', coalesce(p_current,0) >= coalesce(nullif(p_target,0),1),
    'metric_label', p_metric_label,
    'owner_name', p_owner_name,
    'cta_url', coalesce(p_cta_url,'achievements.html?lite=1')
  );
$$;

grant execute on function public._badge_progress_card(text,text,text,text,text,text,text,text,int,numeric,numeric,text,text,text) to authenticated;

-- -------------------------------------------------------------
-- 3) تقدم الشارات حسب المستخدم الحالي
-- -------------------------------------------------------------
create or replace function public.get_my_badge_progress()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  u record;
  cards jsonb := '[]'::jsonb;
  sid uuid;
  sname text;
  absence_count int := 0;
  hw_total int := 0;
  hw_done int := 0;
  exam_attempts int := 0;
  grade_avg numeric := 0;
  completed_count int := 0;
  lesson_plans_30 int := 0;
  homeworks_created_30 int := 0;
  homework_grades_30 int := 0;
  grade_entries_30 int := 0;
  online_exams_created int := 0;
  attendance_records_30 int := 0;
begin
  select id,name,email,role,is_super_admin into u from public.users where id = auth.uid();
  if u.id is null then
    return jsonb_build_object('ok',false,'message','يجب تسجيل الدخول','cards','[]'::jsonb);
  end if;

  if to_regclass('public.completed_items') is not null then
    select count(*) into completed_count
    from public.completed_items c
    where c.user_id = u.id and c.status = 'completed' and c.date_gregorian >= current_date - 30;
  end if;

  -- الطالب أو ولي الأمر: احسب لكل طالب مرتبط.
  if u.role in ('student','parent') then
    for sid, sname in
      select s.id, coalesce(public._counseling_student_name(s.id), s.name, 'طالب')
      from public.students s
      where s.user_id = u.id or s.parent_id = u.id
      order by s.name
    loop
      absence_count := 0; hw_total := 0; hw_done := 0; exam_attempts := 0; grade_avg := 0;

      if to_regclass('public.attendance') is not null then
        select count(*) into absence_count
        from public.attendance a
        where a.student_id = sid
          and a.date >= current_date - 30
          and a.status in ('absent','غائب');
      end if;

      if to_regclass('public.homeworks') is not null and to_regprocedure('public.student_matches_homework(uuid,uuid)') is not null then
        select count(*) into hw_total
        from public.homeworks h
        where h.status in ('published','closed')
          and (h.publish_at is null or h.publish_at <= now())
          and coalesce(h.due_date, h.assigned_date, h.created_at::date) >= current_date - 90
          and public.student_matches_homework(sid,h.id);

        select count(*) into hw_done
        from public.homeworks h
        where h.status in ('published','closed')
          and (h.publish_at is null or h.publish_at <= now())
          and coalesce(h.due_date, h.assigned_date, h.created_at::date) >= current_date - 90
          and public.student_matches_homework(sid,h.id)
          and (
            exists(select 1 from public.homework_grades g where g.homework_id=h.id and g.student_id=sid)
            or exists(select 1 from public.homework_submissions sub where sub.homework_id=h.id and sub.student_id=sid and sub.status in ('submitted','late','graded'))
          );
      end if;

      if to_regclass('public.exam_attempts') is not null then
        select count(*) into exam_attempts
        from public.exam_attempts ea
        where ea.student_id = sid;
      end if;

      if to_regclass('public.exam_scores') is not null then
        select coalesce(round(avg(score)::numeric,2),0) into grade_avg
        from public.exam_scores es
        where es.student_id = sid and es.score is not null;
      end if;

      cards := cards || jsonb_build_array(
        public._badge_progress_card('student_perfect_attendance_30','دوام متواصل','لا يوجد أي يوم غياب خلال آخر 30 يوماً','student','attendance','star','emerald','gold',50,case when absence_count=0 then 30 else greatest(0,30-absence_count*7) end,30,'غيابات: '||absence_count::text,sname,'smart-calendar.html?lite=1'),
        public._badge_progress_card('student_homework_complete','واجبات متكاملة','إكمال وتسليم الواجبات المنشورة','student','homework','book','orange','gold',45,hw_done,greatest(hw_total,1),'واجبات: '||hw_done::text||'/'||hw_total::text,sname,'student-homeworks.html?lite=1'),
        public._badge_progress_card('student_exam_ready','جاهز للاختبارات الإلكترونية','المشاركة في الاختبارات الإلكترونية','student','exams','exam','cyan','silver',30,exam_attempts,3,'محاولات: '||exam_attempts::text,sname,'online-exams.html?lite=1'),
        public._badge_progress_card('student_growth_path','مسار التطور','متوسط درجات وتقدم أكاديمي','student','growth','sparkle','violet','silver',35,grade_avg,80,'متوسط: '||grade_avg::text||'%',sname,'academic-pro.html?lite=1'),
        public._badge_progress_card('student_calendar_achiever','منجز التقويم','إنجاز مهام الأجندة والتقويم','student','calendar','calendar','gold','bronze',20,completed_count,5,'إنجازات: '||completed_count::text,sname,'smart-calendar.html?lite=1')
      );
    end loop;
  end if;

  -- المعلم: احسب إنجازات مهنية إلكترونية.
  if u.role = 'teacher' then
    if to_regclass('public.lesson_plans') is not null then
      select count(*) into lesson_plans_30 from public.lesson_plans where teacher_id=u.id and created_at >= now() - interval '30 days';
    end if;
    if to_regclass('public.homeworks') is not null then
      select count(*) into homeworks_created_30 from public.homeworks where teacher_id=u.id and created_at >= now() - interval '30 days';
    end if;
    if to_regclass('public.homework_grades') is not null then
      select count(*) into homework_grades_30 from public.homework_grades where graded_by=u.id and graded_at >= now() - interval '30 days';
    end if;
    if to_regclass('public.exam_scores') is not null then
      select count(*) into grade_entries_30 from public.exam_scores where entered_by=u.id and created_at >= now() - interval '30 days';
    end if;
    if to_regclass('public.continuous_assessments') is not null then
      select grade_entries_30 + count(*)::int into grade_entries_30
      from public.continuous_assessments
      where (teacher_id=u.id or created_by=u.id) and created_at >= now() - interval '30 days';
    end if;
    if to_regclass('public.online_exams') is not null then
      select count(*) into online_exams_created from public.online_exams where teacher_id=u.id;
    end if;
    if to_regclass('public.attendance') is not null then
      select count(*) into attendance_records_30 from public.attendance where recorded_by=u.id and date >= current_date - 30;
    end if;

    cards := cards || jsonb_build_array(
      public._badge_progress_card('teacher_lesson_prep_streak','تحضير مستمر','تحضير دروس مستمر بدون انقطاع','teacher','planning','book','emerald','gold',55,lesson_plans_30,12,'تحاضير: '||lesson_plans_30::text,coalesce(u.name,u.email),'teacher.html?lite=1'),
      public._badge_progress_card('teacher_homework_followup','متابعة الواجبات','متابعة مستمرة من خلال تصحيح الواجبات','teacher','homework','check','orange','gold',50,homework_grades_30,30,'تصحيحات: '||homework_grades_30::text,coalesce(u.name,u.email),'homework-reports.html?lite=1'),
      public._badge_progress_card('teacher_grades_uploader','تنزيل الدرجات','تنزيل الدرجات والتقييمات باستمرار','teacher','grades','chart','indigo','silver',40,grade_entries_30,40,'درجات: '||grade_entries_30::text,coalesce(u.name,u.email),'teacher.html?lite=1'),
      public._badge_progress_card('teacher_digital_exam_builder','باني الاختبارات الإلكترونية','إنشاء اختبارات إلكترونية للطلاب','teacher','exams','exam','cyan','silver',35,online_exams_created,2,'اختبارات: '||online_exams_created::text,coalesce(u.name,u.email),'teacher-exams.html?lite=1'),
      public._badge_progress_card('teacher_attendance_followup','متابعة الحضور','متابعة الحضور والغياب بشكل منتظم','teacher','attendance','check','teal','bronze',25,attendance_records_30,10,'سجلات: '||attendance_records_30::text,coalesce(u.name,u.email),'teacher.html?lite=1'),
      public._badge_progress_card('teacher_calendar_achiever','منجز أجندة المعلم','إنجاز مهام التقويم والأجندة','teacher','calendar','calendar','gold','bronze',20,completed_count,5,'إنجازات: '||completed_count::text,coalesce(u.name,u.email),'smart-calendar.html?lite=1')
    );
  end if;

  -- المرشد/الإدارة: أظهر إنجازات التقويم فقط حتى لا تختلط بيانات الطلاب.
  if u.role not in ('student','parent','teacher') then
    cards := cards || jsonb_build_array(
      public._badge_progress_card('calendar_achiever','منجز الأجندة','إنجاز مهام التقويم والأجندة','all','calendar','calendar','gold','bronze',20,completed_count,5,'إنجازات: '||completed_count::text,coalesce(u.name,u.email),'smart-calendar.html?lite=1')
    );
  end if;

  return jsonb_build_object('ok',true,'role',u.role,'cards',cards,'count',jsonb_array_length(cards));
end;
$$;

grant execute on function public.get_my_badge_progress() to authenticated;

-- -------------------------------------------------------------
-- 4) الصفحة الرئيسية الشخصية بعد تسجيل الدخول
-- -------------------------------------------------------------
create or replace function public.get_my_landing_home()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  u record;
  agenda jsonb := jsonb_build_object('items','[]'::jsonb);
  completed jsonb := jsonb_build_object('items','[]'::jsonb);
  badges jsonb := jsonb_build_object('cards','[]'::jsonb);
  schedule_json jsonb := '[]'::jsonb;
  st_ids uuid[] := array[]::uuid[];
  class_ids uuid[] := array[]::uuid[];
  triple jsonb;
begin
  select id,name,email,role,is_super_admin into u from public.users where id = auth.uid();
  if u.id is null then
    return jsonb_build_object('ok',false,'message','يجب تسجيل الدخول');
  end if;

  if to_regprocedure('public.get_my_agenda(text)') is not null then
    agenda := public.get_my_agenda('week');
  end if;
  if to_regprocedure('public.get_my_completed_items(text)') is not null then
    completed := public.get_my_completed_items('week');
  end if;
  if to_regprocedure('public.get_my_badge_progress()') is not null then
    badges := public.get_my_badge_progress();
  end if;
  if to_regprocedure('public.calendar_format_triple(date)') is not null then
    triple := public.calendar_format_triple(current_date);
  else
    triple := jsonb_build_object('gregorian', current_date::text, 'display', current_date::text);
  end if;

  if u.role='teacher' and to_regclass('public.v_teacher_schedule') is not null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.day, x.period_number), '[]'::jsonb)
    into schedule_json
    from (
      select day, period_number, class_name, section_name, subject_name, teacher_name
      from public.v_teacher_schedule
      where teacher_id = u.id
      order by day, period_number
      limit 12
    ) x;
  elsif u.role in ('student','parent') and to_regclass('public.weekly_schedule') is not null then
    select coalesce(array_agg(s.id),array[]::uuid[]), coalesce(array_agg(distinct s.class_id),array[]::uuid[])
    into st_ids, class_ids
    from public.students s
    where s.user_id = u.id or s.parent_id = u.id;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.day, x.period_number), '[]'::jsonb)
    into schedule_json
    from (
      select ws.day, ws.period_number, c.name as class_name, sec.name as section_name, sub.name as subject_name, tu.name as teacher_name
      from public.weekly_schedule ws
      left join public.classes c on c.id=ws.class_id
      left join public.sections sec on sec.id=ws.section_id
      left join public.subjects sub on sub.id=ws.subject_id
      left join public.users tu on tu.id=ws.teacher_id
      where ws.class_id = any(class_ids)
      order by ws.day, ws.period_number
      limit 12
    ) x;
  else
    schedule_json := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'ok', true,
    'profile', to_jsonb(u),
    'server_now', now(),
    'triple_date', triple,
    'agenda', coalesce(agenda, jsonb_build_object('items','[]'::jsonb)),
    'completed', coalesce(completed, jsonb_build_object('items','[]'::jsonb)),
    'badges', coalesce(badges, jsonb_build_object('cards','[]'::jsonb)),
    'schedule', coalesce(schedule_json,'[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_my_landing_home() to authenticated;

-- -------------------------------------------------------------
-- 5) Health Check
-- -------------------------------------------------------------
create or replace function public.personal_landing_home_health_check()
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
    'functions', jsonb_build_object(
      'get_my_badge_progress', to_regprocedure('public.get_my_badge_progress()') is not null,
      'get_my_landing_home', to_regprocedure('public.get_my_landing_home()') is not null,
      'get_my_agenda', to_regprocedure('public.get_my_agenda(text)') is not null
    ),
    'badges_available', case when to_regclass('public.achievement_badges') is null then 0 else (select count(*) from public.achievement_badges where is_active=true) end,
    'new_computed_badges', case when to_regclass('public.achievement_badges') is null then 0 else (select count(*) from public.achievement_badges where code in ('student_perfect_attendance_30','student_homework_complete','teacher_lesson_prep_streak','teacher_homework_followup','teacher_grades_uploader')) end
  );
end;
$$;

grant execute on function public.personal_landing_home_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.personal_landing_home_health_check() as personal_landing_home_health;

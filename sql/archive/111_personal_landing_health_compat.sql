-- =============================================================
-- مدارس أمين الرضا (ع) — Hotfix توافق للصفحة الرئيسية والشارات
-- يعالج اختلاف أسماء أعمدة due_date_gregorian / exam_date_gregorian في بعض المخططات.
-- شغّله إذا ظهر خطأ عند تشغيل SQL 109 أو عند فتح portal.html.
-- =============================================================

create extension if not exists pgcrypto;

-- دالة agenda متوافقة لا تشير إلا لأعمدة موجودة في أغلب المخططات.
create or replace function public.get_my_agenda(p_range text default 'today')
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  uid uuid := auth.uid();
  role_text text;
  from_d date := current_date;
  to_d date := current_date;
  agenda jsonb := '[]'::jsonb;
  st_ids uuid[] := array[]::uuid[];
begin
  select role into role_text from public.users where id=uid;
  if p_range='week' then
    to_d := current_date + 6;
  elsif p_range='tomorrow' then
    from_d := current_date + 1; to_d := current_date + 1;
  elsif p_range='overdue' then
    from_d := current_date - 365; to_d := current_date - 1;
  end if;

  select coalesce(array_agg(id),array[]::uuid[]) into st_ids
  from public.students
  where user_id=uid or parent_id=uid;

  -- واجبات الطالب/ولي الأمر
  if role_text in ('student','parent') and to_regclass('public.homeworks') is not null then
    agenda := agenda || coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',hw.id,'source_table','homeworks','source_id',hw.id,
        'title',hw.title,'agenda_type','assignment','role_scope',role_text,
        'date_gregorian',hw.due_date,
        'priority',case when hw.due_date<current_date then 'high' else 'normal' end,
        'status',case when hw.due_date<current_date then 'overdue' else 'pending' end,
        'action_label','عرض الواجب','action_url','student-homeworks.html','color','#0A6EDC','icon','assignment'
      ))
      from public.homeworks hw
      where hw.due_date between from_d and to_d
        and (
          to_regprocedure('public.student_matches_homework(uuid,uuid)') is null
          or exists(select 1 from unnest(st_ids) as sid(student_id) where public.student_matches_homework(sid.student_id,hw.id))
        )
    ), '[]'::jsonb);
  end if;

  -- واجبات المعلم
  if role_text='teacher' and to_regclass('public.homeworks') is not null then
    agenda := agenda || coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',hw.id,'source_table','homeworks','source_id',hw.id,
        'title','واجب: '||hw.title,'agenda_type','assignment','role_scope','teacher',
        'date_gregorian',hw.due_date,'priority','normal','status','pending',
        'action_label','فتح الواجبات','action_url','teacher.html','color','#0A6EDC','icon','assignment'
      ))
      from public.homeworks hw
      where hw.teacher_id=uid and hw.due_date between from_d and to_d
    ), '[]'::jsonb);
  end if;

  -- الاختبارات الأكاديمية من exams إن وجدت
  if to_regclass('public.exams') is not null then
    agenda := agenda || coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',e.id,'source_table','exams','source_id',e.id,
        'title',e.exam_name,'agenda_type','exam','role_scope','all',
        'date_gregorian',e.exam_date,'priority','high','status','pending',
        'action_label','عرض الاختبارات','action_url','online-exams.html','color','#D32F2F','icon','exam'
      ))
      from public.exams e
      where e.exam_date between from_d and to_d
        and (
          role_text in ('admin','academic','academic_admin','scientific','supervisor')
          or e.teacher_id=uid
          or e.class_id in (select class_id from public.students where id=any(st_ids))
        )
    ), '[]'::jsonb);
  end if;

  -- الاختبارات الإلكترونية من online_exams إن وجدت
  if to_regclass('public.online_exams') is not null then
    agenda := agenda || coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',oe.id,'source_table','online_exams','source_id',oe.id,
        'title',oe.title,'agenda_type','exam','role_scope','all',
        'date_gregorian',coalesce(oe.start_at::date, current_date),
        'priority','high','status','pending',
        'action_label','فتح الاختبار','action_url','online-exams.html','color','#D32F2F','icon','exam'
      ))
      from public.online_exams oe
      where coalesce(oe.start_at::date,current_date) between from_d and to_d
        and (
          role_text in ('admin','academic','academic_admin','scientific','supervisor')
          or oe.teacher_id=uid
          or oe.class_id in (select class_id from public.students where id=any(st_ids))
        )
    ), '[]'::jsonb);
  end if;

  -- الإشعارات
  if to_regclass('public.school_notifications') is not null then
    agenda := agenda || coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',n.id,'source_table','school_notifications','source_id',n.id,
        'title',n.title,'description',n.body,'agenda_type','notification','role_scope','all',
        'date_gregorian',n.created_at::date,'priority','normal',
        'status',case when n.read_at is null then 'pending' else 'done' end,
        'action_label','فتح الإشعارات','action_url','notifications.html','color','#D4AF37','icon','bell'
      ))
      from public.school_notifications n
      where n.recipient_user_id=uid and n.created_at::date between from_d and to_d and n.read_at is null
    ), '[]'::jsonb);
  end if;

  return jsonb_build_object('ok',true,'range',p_range,'items',coalesce(agenda,'[]'::jsonb));
end;
$$;

grant execute on function public.get_my_agenda(text) to authenticated;

notify pgrst, 'reload schema';

select 'personal_landing_health_compat_ready' as status;

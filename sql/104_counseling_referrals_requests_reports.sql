-- =============================================================
-- مدارس أمين الرضا (ع) — إحالات المعلم وطلب الطالب للتواصل + تقرير مجهول
-- يعتمد على SQL 98 و100. آمن ويمكن تشغيله أكثر من مرة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) دالة مساعدة لإشعار المرشدين/الأخصائيين
-- -------------------------------------------------------------
create or replace function public._notify_counselors(p_title text, p_body text, p_type text, p_entity_table text, p_entity_id uuid, p_created_by uuid default auth.uid())
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted int := 0;
begin
  if to_regclass('public.school_notifications') is null then
    return 0;
  end if;

  insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
  select u.id, u.role, p_title, p_body, coalesce(p_type,'counseling_referral'), p_entity_table, p_entity_id, p_created_by
  from public.users u
  where u.role in ('counselor','psychologist')
     or coalesce(u.is_super_admin,false)=true;

  get diagnostics inserted = row_count;
  return coalesce(inserted,0);
exception when others then
  return 0;
end;
$$;

revoke all on function public._notify_counselors(text,text,text,text,uuid,uuid) from public;

-- -------------------------------------------------------------
-- 2) تحديث إحالة المدرسة/المعلم: تضيف إشعاراً للمرشدين
-- -------------------------------------------------------------
create or replace function public.counseling_quick_referral(p_student_id uuid, p_urgency text, p_concern text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rid uuid;
  urgency text := case when p_urgency in ('stable','followup','medium','high','urgent','crisis') then p_urgency else 'followup' end;
  student_name text := 'طالب';
  notifier_count int := 0;
begin
  if not public.current_user_can_create_referral() then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية إرسال إحالة');
  end if;

  select public._counseling_student_name(p_student_id) into student_name;

  insert into public.counseling_referrals(student_id,referred_by,urgency,concern,source,status)
  values(p_student_id, auth.uid(), urgency, coalesce(nullif(trim(p_concern),''),'إحالة إلى برنامج تطوير المهارات والمتابعة التربوية'), 'school', 'pending')
  returning id into rid;

  notifier_count := public._notify_counselors(
    'إحالة جديدة للبرنامج التربوي',
    'تم إرسال إحالة جديدة بخصوص ' || coalesce(student_name,'طالب') || ' — مستوى المتابعة: ' || urgency,
    'counseling_referral',
    'counseling_referrals',
    rid,
    auth.uid()
  );

  return jsonb_build_object('ok',true,'referral_id',rid,'notified',notifier_count,'message','تم إرسال الإحالة للمرشد');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.counseling_quick_referral(uuid,text,text) to authenticated;

-- -------------------------------------------------------------
-- 3) طلب الطالب/ولي الأمر موعداً بصياغة محايدة
-- -------------------------------------------------------------
create or replace function public.counseling_student_request_session(p_student_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s record;
  rid uuid;
  source_text text := 'student_request';
  notifier_count int := 0;
  clean_reason text := nullif(trim(coalesce(p_reason,'')), '');
begin
  if auth.uid() is null then
    return jsonb_build_object('ok',false,'message','يجب تسجيل الدخول');
  end if;

  select * into s from public.students where id = p_student_id;
  if s.id is null then
    return jsonb_build_object('ok',false,'message','الطالب غير موجود');
  end if;

  if not (s.user_id = auth.uid() or s.parent_id = auth.uid() or public.current_user_can_create_referral()) then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية طلب موعد لهذا الطالب');
  end if;

  if s.parent_id = auth.uid() then
    source_text := 'parent_request';
  end if;

  insert into public.counseling_referrals(student_id,referred_by,urgency,concern,source,status)
  values(
    s.id,
    auth.uid(),
    'followup',
    coalesce(clean_reason, 'طلب موعد ضمن برنامج تطوير المهارات والمتابعة التربوية'),
    source_text,
    'pending'
  )
  returning id into rid;

  notifier_count := public._notify_counselors(
    'طلب موعد للبرنامج التربوي',
    coalesce(public._counseling_student_name(s.id),'طالب') || ' طلب موعداً ضمن برنامج تطوير المهارات والمتابعة التربوية.',
    'counseling_student_request',
    'counseling_referrals',
    rid,
    auth.uid()
  );

  return jsonb_build_object('ok',true,'referral_id',rid,'notified',notifier_count,'message','تم إرسال طلب الموعد للمرشد');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.counseling_student_request_session(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 4) Health Check
-- -------------------------------------------------------------
create or replace function public.counseling_referrals_requests_health_check()
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
    'teacher_referral_rpc', to_regprocedure('public.counseling_quick_referral(uuid,text,text)') is not null,
    'student_request_rpc', to_regprocedure('public.counseling_student_request_session(uuid,text)') is not null,
    'aggregate_report_rpc', to_regprocedure('public.get_counseling_admin_aggregate_report()') is not null,
    'pending_referrals', case when to_regclass('public.counseling_referrals') is null then 0 else (select count(*) from public.counseling_referrals where status='pending') end,
    'counselor_users', case when to_regclass('public.users') is null then 0 else (select count(*) from public.users where role in ('counselor','psychologist') or coalesce(is_super_admin,false)=true) end
  );
end;
$$;

grant execute on function public.counseling_referrals_requests_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.counseling_referrals_requests_health_check() as counseling_referrals_requests_health;

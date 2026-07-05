-- =============================================================
-- مدارس أمين الرضا (ع) — إصلاح/تشخيص تذكيرات المتأخرات المالية
-- يحل حالة: "تم إرسال التذكيرات — عدد الإشعارات: 0"
-- الأسباب غالباً: سبق إرسال التذكير اليوم، أو لا يوجد ولي أمر/طالب مرتبط، أو لا توجد متأخرات حسب الفلتر.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) صلاحيات مالية
-- -------------------------------------------------------------
create or replace function public.current_user_is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (u.role = 'admin' or coalesce(u.is_super_admin,false)=true)
  );
$$;

grant execute on function public.current_user_is_admin() to authenticated;

create or replace function public.finance_can_manage()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.current_user_is_admin()
    or exists(
      select 1 from public.users u
      where u.id = auth.uid()
        and u.role in ('finance','staff','accountant','cashier')
    );
$$;

grant execute on function public.finance_can_manage() to authenticated;

-- -------------------------------------------------------------
-- 1) Preview للطلاب الذين سيصلهم التذكير أو سيتم تخطيهم
-- -------------------------------------------------------------
create or replace function public.preview_finance_overdue_reminders(
  p_student_id uuid default null,
  p_class_id uuid default null,
  p_min_days_late int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  rows_json jsonb;
  stats_json jsonb;
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية معاينة التذكيرات المالية');
  end if;

  with rows as (
    select
      v.student_id,
      v.student_name,
      v.class_name,
      v.parent_id,
      v.parent_name,
      s.user_id as student_user_id,
      v.student_fee_id,
      v.overdue_amount,
      v.remaining_amount,
      v.overdue_installments,
      v.max_days_late,
      exists(
        select 1
        from public.school_notifications n
        where n.recipient_user_id = v.parent_id
          and n.notification_type = 'finance_overdue'
          and n.entity_id = v.student_fee_id
          and n.created_at::date = current_date
      ) as parent_already_sent_today,
      exists(
        select 1
        from public.school_notifications n
        where n.recipient_user_id = s.user_id
          and n.notification_type = 'finance_overdue'
          and n.entity_id = v.student_fee_id
          and n.created_at::date = current_date
      ) as student_already_sent_today
    from public.v_finance_collection_students v
    join public.students s on s.id = v.student_id
    where v.overdue_amount > 0
      and (p_student_id is null or v.student_id = p_student_id)
      and (p_class_id is null or v.class_id = p_class_id)
      and v.max_days_late >= coalesce(p_min_days_late,0)
  )
  select coalesce(jsonb_agg(to_jsonb(rows) order by max_days_late desc, overdue_amount desc), '[]'::jsonb)
  into rows_json
  from rows;

  with rows as (
    select
      v.student_id,
      v.parent_id,
      s.user_id as student_user_id,
      v.student_fee_id,
      exists(select 1 from public.school_notifications n where n.recipient_user_id = v.parent_id and n.notification_type='finance_overdue' and n.entity_id=v.student_fee_id and n.created_at::date=current_date) as parent_dup,
      exists(select 1 from public.school_notifications n where n.recipient_user_id = s.user_id and n.notification_type='finance_overdue' and n.entity_id=v.student_fee_id and n.created_at::date=current_date) as student_dup
    from public.v_finance_collection_students v
    join public.students s on s.id = v.student_id
    where v.overdue_amount > 0
      and (p_student_id is null or v.student_id = p_student_id)
      and (p_class_id is null or v.class_id = p_class_id)
      and v.max_days_late >= coalesce(p_min_days_late,0)
  )
  select jsonb_build_object(
    'matched_students', count(*),
    'with_parent_recipient', count(*) filter (where parent_id is not null),
    'with_student_recipient', count(*) filter (where student_user_id is not null),
    'without_any_recipient', count(*) filter (where parent_id is null and student_user_id is null),
    'parent_already_sent_today', count(*) filter (where parent_dup),
    'student_already_sent_today', count(*) filter (where student_dup)
  ) into stats_json
  from rows;

  return jsonb_build_object('ok', true, 'stats', stats_json, 'rows', rows_json);
end;
$$;

grant execute on function public.preview_finance_overdue_reminders(uuid,uuid,int) to authenticated;

-- -------------------------------------------------------------
-- 2) دالة تفصيلية للإرسال، مع خيار force لإعادة الإرسال في نفس اليوم
-- -------------------------------------------------------------
create or replace function public.send_finance_overdue_reminders_detailed(
  p_student_id uuid default null,
  p_class_id uuid default null,
  p_min_days_late int default 0,
  p_force boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  inserted_parent int := 0;
  inserted_student int := 0;
  followups_created int := 0;
  matched_count int := 0;
  no_recipient_count int := 0;
  parent_duplicate_count int := 0;
  student_duplicate_count int := 0;
  details jsonb := '[]'::jsonb;
  parent_inserted boolean;
  student_inserted boolean;
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إرسال تذكيرات مالية');
  end if;

  for r in
    select
      v.*,
      s.user_id as student_user_id
    from public.v_finance_collection_students v
    join public.students s on s.id = v.student_id
    where v.overdue_amount > 0
      and (p_student_id is null or v.student_id = p_student_id)
      and (p_class_id is null or v.class_id = p_class_id)
      and v.max_days_late >= coalesce(p_min_days_late,0)
    order by v.max_days_late desc, v.overdue_amount desc
  loop
    matched_count := matched_count + 1;
    parent_inserted := false;
    student_inserted := false;

    if r.parent_id is null and r.student_user_id is null then
      no_recipient_count := no_recipient_count + 1;
    end if;

    -- ولي الأمر
    if r.parent_id is not null then
      if not coalesce(p_force,false) and exists(
        select 1
        from public.school_notifications n
        where n.recipient_user_id = r.parent_id
          and n.notification_type = 'finance_overdue'
          and n.entity_id = r.student_fee_id
          and n.created_at::date = current_date
      ) then
        parent_duplicate_count := parent_duplicate_count + 1;
      else
        insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
        values (
          r.parent_id,
          'parent',
          'تذكير مالي بمتأخرات الرسوم',
          'يوجد متأخرات على الطالب ' || coalesce(r.student_name,'') || ' بمبلغ ' || coalesce(r.overdue_amount,0)::text || ' دولار تقريباً. يرجى مراجعة الإدارة المالية.',
          'finance_overdue',
          'student_fees',
          r.student_fee_id,
          auth.uid()
        );
        inserted_parent := inserted_parent + 1;
        parent_inserted := true;
      end if;
    end if;

    -- الطالب أيضاً إذا لديه حساب طالب، حتى لا يبقى العدد صفر عند غياب parent_id أو وجود duplicate للأهل.
    if r.student_user_id is not null then
      if not coalesce(p_force,false) and exists(
        select 1
        from public.school_notifications n
        where n.recipient_user_id = r.student_user_id
          and n.notification_type = 'finance_overdue'
          and n.entity_id = r.student_fee_id
          and n.created_at::date = current_date
      ) then
        student_duplicate_count := student_duplicate_count + 1;
      else
        insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
        values (
          r.student_user_id,
          'student',
          'تذكير مالي',
          'يوجد متأخرات مالية على حسابك المدرسي بمبلغ ' || coalesce(r.overdue_amount,0)::text || ' دولار تقريباً. يرجى مراجعة ولي الأمر أو الإدارة المالية.',
          'finance_overdue',
          'student_fees',
          r.student_fee_id,
          auth.uid()
        );
        inserted_student := inserted_student + 1;
        student_inserted := true;
      end if;
    end if;

    insert into public.finance_followups(student_id, parent_id, followup_type, status, notes, created_by)
    values (
      r.student_id,
      r.parent_id,
      'message',
      'open',
      case
        when parent_inserted or student_inserted then 'تم إرسال تذكير مالي تلقائي'
        else 'محاولة تذكير مالي بدون إشعار جديد: مكرر اليوم أو لا يوجد مستلم'
      end,
      auth.uid()
    );
    followups_created := followups_created + 1;

    details := details || jsonb_build_array(jsonb_build_object(
      'student_id', r.student_id,
      'student_name', r.student_name,
      'overdue_amount', r.overdue_amount,
      'parent_id', r.parent_id,
      'student_user_id', r.student_user_id,
      'parent_inserted', parent_inserted,
      'student_inserted', student_inserted
    ));
  end loop;

  return jsonb_build_object(
    'ok', true,
    'message', 'تمت معالجة التذكيرات المالية',
    'matched_students', matched_count,
    'parent_notifications', inserted_parent,
    'student_notifications', inserted_student,
    'notifications', inserted_parent + inserted_student,
    'already_sent_today', parent_duplicate_count + student_duplicate_count,
    'parent_already_sent_today', parent_duplicate_count,
    'student_already_sent_today', student_duplicate_count,
    'without_recipient', no_recipient_count,
    'followups_created', followups_created,
    'force', coalesce(p_force,false),
    'details', details
  );
end;
$$;

grant execute on function public.send_finance_overdue_reminders_detailed(uuid,uuid,int,boolean) to authenticated;

-- -------------------------------------------------------------
-- 3) Wrapper باسم الدالة القديمة حتى لا تنكسر الواجهات القديمة
-- -------------------------------------------------------------
create or replace function public.send_finance_overdue_reminders(
  p_student_id uuid default null,
  p_class_id uuid default null,
  p_min_days_late int default 0
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.send_finance_overdue_reminders_detailed(p_student_id, p_class_id, p_min_days_late, false);
$$;

grant execute on function public.send_finance_overdue_reminders(uuid,uuid,int) to authenticated;

-- -------------------------------------------------------------
-- 4) فحص
-- -------------------------------------------------------------
create or replace function public.finance_overdue_reminders_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'preview_rpc', to_regprocedure('public.preview_finance_overdue_reminders(uuid,uuid,int)') is not null,
    'send_detailed_rpc', to_regprocedure('public.send_finance_overdue_reminders_detailed(uuid,uuid,int,boolean)') is not null,
    'send_legacy_rpc', to_regprocedure('public.send_finance_overdue_reminders(uuid,uuid,int)') is not null,
    'preview_all', public.preview_finance_overdue_reminders(null,null,0)->'stats'
  );
end;
$$;

grant execute on function public.finance_overdue_reminders_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_overdue_reminders_diagnostics_fix_ready' as status;

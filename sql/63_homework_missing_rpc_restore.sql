-- =============================================================
-- مدارس أمين الرضا (ع) — Hotfix: استرجاع دوال تقارير الواجبات المفقودة من schema cache
-- يحل: Could not find the function public.bulk_close_overdue_homeworks(p_apply)
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) دوال/جداول مساعدة آمنة
-- -------------------------------------------------------------
create or replace function public.current_user_is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1
    from public.users u
    where u.id = auth.uid()
      and (u.role = 'admin' or coalesce(u.is_super_admin,false)=true)
  );
$$;

grant execute on function public.current_user_is_admin() to authenticated;

create table if not exists public.teacher_error_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid null references public.users(id),
  module text,
  message text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.log_teacher_error(
  p_module text,
  p_message text,
  p_details jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.teacher_error_logs(actor_id, module, message, details)
  values (auth.uid(), p_module, p_message, coalesce(p_details,'{}'::jsonb));
end;
$$;

grant execute on function public.log_teacher_error(text,text,jsonb) to authenticated;

-- -------------------------------------------------------------
-- 1) دالة إغلاق الواجب الواحد إن كانت غير موجودة
-- -------------------------------------------------------------
create or replace function public.close_homework(p_homework_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
begin
  select * into h from public.homeworks where id = p_homework_id;

  if h.id is null then
    return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود');
  end if;

  if auth.uid() is not null and not (public.current_user_is_admin() or h.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إغلاق هذا الواجب');
  end if;

  update public.homeworks
  set status = 'closed',
      updated_at = now()
  where id = p_homework_id;

  begin
    perform public.notify_homework_recipients(p_homework_id, 'closed');
  exception when others then
    null;
  end;

  return jsonb_build_object('ok', true, 'message', 'تم إغلاق الواجب');
exception when others then
  perform public.log_teacher_error('close_homework', sqlerrm, jsonb_build_object('homework_id', p_homework_id));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.close_homework(uuid) to authenticated;

-- -------------------------------------------------------------
-- 2) الدالة المطلوبة بالاسم والوسيط p_apply بالضبط
-- -------------------------------------------------------------
create or replace function public.bulk_close_overdue_homeworks(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  ids uuid[] := array[]::uuid[];
  closed_count int := 0;
  hw uuid;
begin
  -- في SQL Editor يكون auth.uid() = null. نسمح بالمعاينة فقط، ونمنع التنفيذ حفاظاً على البيانات.
  if coalesce(p_apply,false) = true and uid is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'لا يمكن تنفيذ الإغلاق الجماعي من SQL Editor بدون جلسة مستخدم. استخدمي صفحة تقارير الواجبات من الموقع.',
      'apply', p_apply
    );
  end if;

  select coalesce(array_agg(h.id order by h.due_date, h.created_at), array[]::uuid[])
  into ids
  from public.homeworks h
  where h.status = 'published'
    and h.due_date is not null
    and (h.due_date + coalesce(h.due_time, time '23:59')) < now()
    and (
      uid is null
      or public.current_user_is_admin()
      or h.teacher_id = uid
    );

  if coalesce(p_apply,false) then
    update public.homeworks h
    set status = 'closed',
        updated_at = now()
    where h.id = any(ids);

    get diagnostics closed_count = row_count;

    foreach hw in array ids loop
      begin
        perform public.notify_homework_recipients(hw, 'closed');
      exception when others then
        null;
      end;
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true,
    'apply', coalesce(p_apply,false),
    'matched_count', coalesce(array_length(ids,1),0),
    'closed_count', closed_count,
    'homework_ids', ids
  );
exception when others then
  perform public.log_teacher_error('bulk_close_overdue_homeworks', sqlerrm, jsonb_build_object('apply', p_apply));
  return jsonb_build_object('ok', false, 'message', sqlerrm, 'apply', p_apply);
end;
$$;

grant execute on function public.bulk_close_overdue_homeworks(boolean) to authenticated;

-- overload بدون معاملات، لتسهيل الاستدعاء اليدوي إن لزم
create or replace function public.bulk_close_overdue_homeworks()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.bulk_close_overdue_homeworks(false);
$$;

grant execute on function public.bulk_close_overdue_homeworks() to authenticated;

-- -------------------------------------------------------------
-- 3) تصفير غير المسلّمين إذا كانت الدالة ناقصة أيضاً
-- -------------------------------------------------------------
create or replace function public.mark_missing_homework_zero(
  p_homework_id uuid,
  p_apply boolean default false,
  p_feedback text default 'لم يتم تسليم الواجب'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  m record;
  matched_count int := 0;
  graded_count int := 0;
  r jsonb;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود'); end if;

  if auth.uid() is not null and not (public.current_user_is_admin() or h.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية على هذا الواجب');
  end if;

  for m in
    select s.id as student_id
    from public.students s
    where public.student_matches_homework(s.id, p_homework_id)
      and not exists(
        select 1 from public.homework_submissions hs
        where hs.homework_id = p_homework_id
          and hs.student_id = s.id
          and hs.status in ('submitted','late','graded','returned')
      )
  loop
    matched_count := matched_count + 1;
    if coalesce(p_apply,false) then
      r := public.save_homework_grade(p_homework_id, m.student_id, 0, p_feedback);
      if r->>'ok' = 'true' then graded_count := graded_count + 1; end if;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'apply', coalesce(p_apply,false), 'matched_count', matched_count, 'graded_count', graded_count);
exception when others then
  perform public.log_teacher_error('mark_missing_homework_zero', sqlerrm, jsonb_build_object('homework_id', p_homework_id, 'apply', p_apply));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.mark_missing_homework_zero(uuid,boolean,text) to authenticated;

create or replace function public.bulk_mark_missing_homeworks_zero(
  p_apply boolean default false,
  p_feedback text default 'لم يتم تسليم الواجب'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
  r jsonb;
  total_homeworks int := 0;
  total_matched int := 0;
  total_graded int := 0;
begin
  if coalesce(p_apply,false) = true and auth.uid() is null then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن التنفيذ من SQL Editor بدون جلسة مستخدم. استخدمي الواجهة.');
  end if;

  for h in
    select *
    from public.homeworks hw
    where hw.status = 'published'
      and hw.due_date is not null
      and (hw.due_date + coalesce(hw.due_time, time '23:59')) < now()
      and (auth.uid() is null or public.current_user_is_admin() or hw.teacher_id = auth.uid())
  loop
    total_homeworks := total_homeworks + 1;
    r := public.mark_missing_homework_zero(h.id, p_apply, p_feedback);
    total_matched := total_matched + coalesce((r->>'matched_count')::int,0);
    total_graded := total_graded + coalesce((r->>'graded_count')::int,0);
  end loop;

  return jsonb_build_object('ok', true, 'apply', coalesce(p_apply,false), 'homeworks_count', total_homeworks, 'matched_count', total_matched, 'graded_count', total_graded);
exception when others then
  perform public.log_teacher_error('bulk_mark_missing_homeworks_zero', sqlerrm, jsonb_build_object('apply', p_apply));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.bulk_mark_missing_homeworks_zero(boolean,text) to authenticated;

-- -------------------------------------------------------------
-- 4) فحص سريع
-- -------------------------------------------------------------
create or replace function public.homework_rpc_restore_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'bulk_close_exists', to_regprocedure('public.bulk_close_overdue_homeworks(boolean)') is not null,
    'bulk_close_no_args_exists', to_regprocedure('public.bulk_close_overdue_homeworks()') is not null,
    'bulk_zero_exists', to_regprocedure('public.bulk_mark_missing_homeworks_zero(boolean,text)') is not null,
    'mark_zero_exists', to_regprocedure('public.mark_missing_homework_zero(uuid,boolean,text)') is not null,
    'published_homeworks', (select count(*) from public.homeworks where status='published'),
    'overdue_published', (select count(*) from public.homeworks where status='published' and due_date is not null and (due_date + coalesce(due_time, time '23:59')) < now()),
    'preview_bulk_close', public.bulk_close_overdue_homeworks(false)
  );
end;
$$;

grant execute on function public.homework_rpc_restore_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'homework_missing_rpc_restore_ready' as status;

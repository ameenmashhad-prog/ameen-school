-- =============================================================
-- مدارس أمين الرضا (ع) — دفعة تسريع 2: إجراءات جماعية، تصفير غير المسلّمين، Audit
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) جداول Logs إن لم تكن موجودة
-- -------------------------------------------------------------
create table if not exists public.school_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid null references public.users(id),
  action text not null,
  entity_table text,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.teacher_error_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid null references public.users(id),
  module text,
  message text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.log_school_audit(
  p_action text,
  p_entity_table text,
  p_entity_id uuid,
  p_old_data jsonb default null,
  p_new_data jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.school_audit_logs(actor_id, action, entity_table, entity_id, old_data, new_data, metadata)
  values (auth.uid(), p_action, p_entity_table, p_entity_id, p_old_data, p_new_data, coalesce(p_metadata,'{}'::jsonb));
end;
$$;

grant execute on function public.log_school_audit(text,text,uuid,jsonb,jsonb,jsonb) to authenticated;

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
-- 1) تغيير حالة الواجب بشكل موحد
-- -------------------------------------------------------------
create or replace function public.set_homework_status(
  p_homework_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h_old record;
  v_status text := lower(coalesce(p_status,''));
begin
  if v_status not in ('draft','published','closed','archived') then
    return jsonb_build_object('ok', false, 'message', 'حالة الواجب غير صحيحة');
  end if;

  select * into h_old from public.homeworks where id = p_homework_id;
  if h_old.id is null then
    return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود');
  end if;

  if not (public.current_user_is_admin() or h_old.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل هذا الواجب');
  end if;

  update public.homeworks
  set status = v_status,
      updated_at = now(),
      publish_at = case when v_status = 'published' and publish_at is null then now() else publish_at end
  where id = p_homework_id;

  perform public.log_school_audit(
    'set_homework_status',
    'homeworks',
    p_homework_id,
    to_jsonb(h_old),
    (select to_jsonb(h) from public.homeworks h where h.id = p_homework_id),
    jsonb_build_object('new_status', v_status)
  );

  if v_status = 'published' then
    begin perform public.notify_homework_recipients(p_homework_id, 'updated'); exception when others then null; end;
  elsif v_status = 'closed' then
    begin perform public.notify_homework_recipients(p_homework_id, 'closed'); exception when others then null; end;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم تغيير حالة الواجب', 'status', v_status);
exception when others then
  perform public.log_teacher_error('set_homework_status', sqlerrm, jsonb_build_object('homework_id', p_homework_id, 'status', p_status));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.set_homework_status(uuid,text) to authenticated;

-- wrappers متوافقة مع الدوال السابقة
create or replace function public.close_homework(p_homework_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$ select public.set_homework_status(p_homework_id, 'closed'); $$;

grant execute on function public.close_homework(uuid) to authenticated;

create or replace function public.reopen_homework(p_homework_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$ select public.set_homework_status(p_homework_id, 'published'); $$;

grant execute on function public.reopen_homework(uuid) to authenticated;

-- -------------------------------------------------------------
-- 2) تصفير غير المسلّمين لواجب واحد — معاينة أو تنفيذ
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
  students jsonb := '[]'::jsonb;
begin
  select * into h from public.homeworks where id = p_homework_id;
  if h.id is null then return jsonb_build_object('ok', false, 'message', 'الواجب غير موجود'); end if;

  if not (public.current_user_is_admin() or h.teacher_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية على هذا الواجب');
  end if;

  if h.status <> 'published' then
    return jsonb_build_object('ok', false, 'message', 'يمكن تصفير غير المسلّمين فقط لواجب منشور. الحالة الحالية: ' || h.status);
  end if;

  for m in
    select s.id as student_id, s.name as student_name
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
    students := students || jsonb_build_array(jsonb_build_object('student_id', m.student_id, 'student_name', m.student_name));

    if p_apply then
      r := public.save_homework_grade(p_homework_id, m.student_id, 0, p_feedback);
      if r->>'ok' = 'true' then
        graded_count := graded_count + 1;
      end if;
    end if;
  end loop;

  if p_apply then
    perform public.log_school_audit('mark_missing_homework_zero', 'homeworks', p_homework_id, null, null, jsonb_build_object('matched', matched_count, 'graded', graded_count));
  end if;

  return jsonb_build_object('ok', true, 'apply', p_apply, 'matched_count', matched_count, 'graded_count', graded_count, 'students', students);
exception when others then
  perform public.log_teacher_error('mark_missing_homework_zero', sqlerrm, jsonb_build_object('homework_id', p_homework_id));
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.mark_missing_homework_zero(uuid,boolean,text) to authenticated;

-- -------------------------------------------------------------
-- 3) تصفير غير المسلّمين لكل الواجبات المتأخرة ضمن صلاحية المعلم
-- -------------------------------------------------------------
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
  details jsonb := '[]'::jsonb;
begin
  if p_apply and auth.uid() is null then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن التنفيذ من SQL Editor بدون جلسة مستخدم. استخدمي الواجهة.');
  end if;

  for h in
    select * from public.homeworks hw
    where hw.status = 'published'
      and hw.due_date is not null
      and (hw.due_date + coalesce(hw.due_time, time '23:59')) < now()
      and (public.current_user_is_admin() or hw.teacher_id = auth.uid() or auth.uid() is null)
  loop
    total_homeworks := total_homeworks + 1;
    r := public.mark_missing_homework_zero(h.id, p_apply, p_feedback);
    total_matched := total_matched + coalesce((r->>'matched_count')::int,0);
    total_graded := total_graded + coalesce((r->>'graded_count')::int,0);
    details := details || jsonb_build_array(jsonb_build_object('homework_id', h.id, 'title', h.title, 'result', r));
  end loop;

  return jsonb_build_object('ok', true, 'apply', p_apply, 'homeworks_count', total_homeworks, 'matched_count', total_matched, 'graded_count', total_graded, 'details', details);
end;
$$;

grant execute on function public.bulk_mark_missing_homeworks_zero(boolean,text) to authenticated;

-- السماح بإدارة مرفقات التسليم عندما يكون التسليم معاداً للتعديل أيضاً.
create or replace function public.can_write_homework_submission_attachment(p_submission_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  hs record;
  h record;
begin
  select * into hs from public.homework_submissions where id = p_submission_id;
  if hs.id is null then return false; end if;

  select * into h from public.homeworks where id = hs.homework_id;
  if h.id is null then return false; end if;

  return public.current_user_is_admin()
    or h.teacher_id = auth.uid()
    or (
      hs.status in ('draft','submitted','late','returned')
      and exists(select 1 from public.students s where s.id = hs.student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
    );
end;
$$;

grant execute on function public.can_write_homework_submission_attachment(uuid) to authenticated;

-- -------------------------------------------------------------
-- 4) حذف metadata لمرفق تسليم إذا لم يكن مصححاً — لا يحذف object من Storage
-- -------------------------------------------------------------
create or replace function public.delete_homework_submission_attachment(p_attachment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
  hs record;
begin
  select * into a from public.homework_submission_attachments where id = p_attachment_id;
  if a.id is null then return jsonb_build_object('ok', false, 'message', 'المرفق غير موجود'); end if;

  select * into hs from public.homework_submissions where id = a.submission_id;
  if hs.id is null then return jsonb_build_object('ok', false, 'message', 'التسليم غير موجود'); end if;

  if hs.status = 'graded' then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن حذف مرفق بعد التصحيح');
  end if;

  if not public.can_write_homework_submission_attachment(a.submission_id) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية حذف هذا المرفق');
  end if;

  delete from public.homework_submission_attachments where id = p_attachment_id;
  perform public.log_school_audit('delete_homework_submission_attachment', 'homework_submission_attachments', p_attachment_id, to_jsonb(a), null, '{}'::jsonb);
  return jsonb_build_object('ok', true, 'message', 'تم حذف المرفق من السجل');
end;
$$;

grant execute on function public.delete_homework_submission_attachment(uuid) to authenticated;

-- -------------------------------------------------------------
-- 5) Audit payload للمعلم/الإدارة
-- -------------------------------------------------------------
create or replace function public.get_homework_audit_payload(p_limit int default 100)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  logs jsonb;
  errors jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into logs
  from (
    select l.*, u.name as actor_name
    from public.school_audit_logs l
    left join public.users u on u.id = l.actor_id
    where (public.current_user_is_admin() or l.actor_id = auth.uid() or auth.uid() is null)
      and (
        l.entity_table ilike '%homework%'
        or l.action ilike '%homework%'
      )
    order by l.created_at desc
    limit greatest(1, least(coalesce(p_limit,100), 500))
  ) x;

  select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at desc), '[]'::jsonb)
  into errors
  from (
    select *
    from public.teacher_error_logs e
    where (public.current_user_is_admin() or e.actor_id = auth.uid() or auth.uid() is null)
      and coalesce(e.module,'') ilike '%homework%'
    order by e.created_at desc
    limit greatest(1, least(coalesce(p_limit,100), 500))
  ) e;

  return jsonb_build_object('ok', true, 'logs', logs, 'errors', errors);
end;
$$;

grant execute on function public.get_homework_audit_payload(int) to authenticated;

-- -------------------------------------------------------------
-- 6) Health
-- -------------------------------------------------------------
create or replace function public.homework_fast_batch_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'set_status', to_regprocedure('public.set_homework_status(uuid,text)') is not null,
    'mark_zero', to_regprocedure('public.mark_missing_homework_zero(uuid,boolean,text)') is not null,
    'bulk_zero', to_regprocedure('public.bulk_mark_missing_homeworks_zero(boolean,text)') is not null,
    'delete_submission_attachment', to_regprocedure('public.delete_homework_submission_attachment(uuid)') is not null,
    'audit_payload', to_regprocedure('public.get_homework_audit_payload(int)') is not null,
    'published_homeworks', (select count(*) from public.homeworks where status='published'),
    'submissions', (select count(*) from public.homework_submissions),
    'submission_attachments', (select count(*) from public.homework_submission_attachments)
  );
end;
$$;

grant execute on function public.homework_fast_batch_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'homework_fast_batch_actions_audit_ready' as status;

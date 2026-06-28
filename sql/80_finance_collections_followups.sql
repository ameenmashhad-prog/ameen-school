-- =============================================================
-- مدارس أمين الرضا (ع) — مركز التحصيل والمتابعة المالية
-- متأخرات، إشعارات، وعود دفع، كشف حساب طالب.
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
-- 1) جدول متابعات التحصيل
-- -------------------------------------------------------------
create table if not exists public.finance_followups (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  parent_id uuid null references public.users(id) on delete set null,
  followup_type text not null default 'call' check (followup_type in ('call','message','meeting','promise','note','warning')),
  status text not null default 'open' check (status in ('open','done','cancelled')),
  promised_date date,
  promised_amount numeric,
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_finance_followups_student on public.finance_followups(student_id, status, created_at desc);
create index if not exists idx_finance_followups_parent on public.finance_followups(parent_id, status, created_at desc);

alter table public.finance_followups enable row level security;

drop policy if exists finance_followups_manage on public.finance_followups;
create policy finance_followups_manage on public.finance_followups
  for all to authenticated
  using (public.finance_can_manage() or parent_id = auth.uid())
  with check (public.finance_can_manage());

grant select, insert, update on public.finance_followups to authenticated;

-- -------------------------------------------------------------
-- 2) إشعارات عامة إن لم تكن موجودة
-- -------------------------------------------------------------
create table if not exists public.school_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid null references public.users(id) on delete cascade,
  recipient_role text,
  title text not null,
  body text,
  notification_type text not null default 'info',
  entity_table text,
  entity_id uuid,
  read_at timestamptz,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now()
);

grant select, insert, update on public.school_notifications to authenticated;

-- -------------------------------------------------------------
-- 3) View المتأخرات المجمعة حسب الطالب
-- -------------------------------------------------------------
drop view if exists public.v_finance_collection_students;

create view public.v_finance_collection_students
with (security_invoker=true) as
select
  s.id as student_id,
  s.name as student_name,
  s.father_name,
  s.last_name,
  s.parent_id,
  p.name as parent_name,
  p.email as parent_email,
  s.class_id,
  c.name as class_name,
  sf.id as student_fee_id,
  sf.academic_year,
  coalesce(sf.net_amount,sf.base_amount,0) as net_amount,
  coalesce(sf.total_paid,0) as total_paid,
  greatest(coalesce(sf.net_amount,sf.base_amount,0)-coalesce(sf.total_paid,0),0) as remaining_amount,
  coalesce(ov.overdue_amount,0) as overdue_amount,
  coalesce(ov.overdue_installments,0) as overdue_installments,
  ov.oldest_due_date,
  case when ov.oldest_due_date is not null then current_date - ov.oldest_due_date else 0 end as max_days_late,
  coalesce(fu.open_followups,0) as open_followups,
  fu.last_followup_at,
  fu.next_promised_date
from public.student_fees sf
join public.students s on s.id = sf.student_id
left join public.users p on p.id = s.parent_id
left join public.classes c on c.id = s.class_id
left join lateral (
  select
    count(*) as overdue_installments,
    coalesce(sum(greatest(coalesce(si.amount_due,0)-coalesce(si.amount_paid,0),0)),0) as overdue_amount,
    min(si.due_date) as oldest_due_date
  from public.student_installments si
  where si.student_fee_id = sf.id
    and coalesce(si.amount_paid,0) < coalesce(si.amount_due,0)
    and si.due_date < current_date
) ov on true
left join lateral (
  select
    count(*) filter (where ff.status='open') as open_followups,
    max(ff.created_at) as last_followup_at,
    min(ff.promised_date) filter (where ff.status='open' and ff.promised_date >= current_date) as next_promised_date
  from public.finance_followups ff
  where ff.student_id = s.id
) fu on true
where (public.finance_can_manage() or s.user_id = auth.uid() or s.parent_id = auth.uid());

grant select on public.v_finance_collection_students to authenticated;

-- -------------------------------------------------------------
-- 4) Payload مركز التحصيل
-- -------------------------------------------------------------
create or replace function public.get_finance_collection_payload(
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
  followups_json jsonb;
  stats_json jsonb;
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية عرض مركز التحصيل');
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.max_days_late desc, x.overdue_amount desc), '[]'::jsonb)
  into rows_json
  from (
    select *
    from public.v_finance_collection_students
    where remaining_amount > 0
      and (p_class_id is null or class_id = p_class_id)
      and max_days_late >= coalesce(p_min_days_late,0)
    limit 300
  ) x;

  select coalesce(jsonb_agg(to_jsonb(f) order by f.created_at desc), '[]'::jsonb)
  into followups_json
  from (
    select
      ff.*,
      s.name as student_name,
      c.name as class_name,
      u.name as created_by_name
    from public.finance_followups ff
    join public.students s on s.id = ff.student_id
    left join public.classes c on c.id = s.class_id
    left join public.users u on u.id = ff.created_by
    where public.finance_can_manage()
    order by ff.created_at desc
    limit 200
  ) f;

  stats_json := jsonb_build_object(
    'students_with_remaining', (select count(*) from public.v_finance_collection_students where remaining_amount > 0 and (p_class_id is null or class_id=p_class_id)),
    'students_overdue', (select count(*) from public.v_finance_collection_students where overdue_amount > 0 and (p_class_id is null or class_id=p_class_id)),
    'total_remaining', (select coalesce(sum(remaining_amount),0) from public.v_finance_collection_students where (p_class_id is null or class_id=p_class_id)),
    'total_overdue', (select coalesce(sum(overdue_amount),0) from public.v_finance_collection_students where (p_class_id is null or class_id=p_class_id)),
    'open_followups', (select count(*) from public.finance_followups where status='open'),
    'promises_due_today', (select count(*) from public.finance_followups where status='open' and promised_date = current_date)
  );

  return jsonb_build_object('ok', true, 'stats', stats_json, 'students', rows_json, 'followups', followups_json);
end;
$$;

grant execute on function public.get_finance_collection_payload(uuid,int) to authenticated;

-- -------------------------------------------------------------
-- 5) إرسال تذكير مالي للمتأخرين
-- -------------------------------------------------------------
create or replace function public.send_finance_overdue_reminders(
  p_student_id uuid default null,
  p_class_id uuid default null,
  p_min_days_late int default 0
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
  total int := 0;
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إرسال تذكيرات مالية');
  end if;

  for r in
    select *
    from public.v_finance_collection_students
    where overdue_amount > 0
      and (p_student_id is null or student_id = p_student_id)
      and (p_class_id is null or class_id = p_class_id)
      and max_days_late >= coalesce(p_min_days_late,0)
  loop
    if r.parent_id is not null then
      insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
      select r.parent_id, 'parent', 'تذكير مالي بمتأخرات الرسوم', 'يوجد متأخرات على الطالب ' || coalesce(r.student_name,'') || ' بمبلغ ' || r.overdue_amount::text || ' دولار تقريباً.', 'finance_overdue', 'student_fees', r.student_fee_id, auth.uid()
      where not exists(
        select 1 from public.school_notifications n
        where n.recipient_user_id = r.parent_id
          and n.notification_type='finance_overdue'
          and n.entity_id = r.student_fee_id
          and n.created_at::date = current_date
      );
      get diagnostics inserted_parent = row_count;
      total := total + inserted_parent;
    end if;

    insert into public.finance_followups(student_id, parent_id, followup_type, status, notes, created_by)
    values (r.student_id, r.parent_id, 'message', 'open', 'تم إرسال تذكير مالي تلقائي', auth.uid());
  end loop;

  return jsonb_build_object('ok', true, 'message', 'تم إرسال التذكيرات المالية', 'notifications', total);
end;
$$;

grant execute on function public.send_finance_overdue_reminders(uuid,uuid,int) to authenticated;

-- -------------------------------------------------------------
-- 6) إضافة متابعة/وعد دفع
-- -------------------------------------------------------------
create or replace function public.add_finance_followup(
  p_student_id uuid,
  p_followup_type text default 'call',
  p_promised_date date default null,
  p_promised_amount numeric default null,
  p_notes text default null,
  p_status text default 'open'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s record;
  fid uuid;
begin
  if not public.finance_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إضافة متابعة مالية');
  end if;

  select * into s from public.students where id = p_student_id;
  if s.id is null then
    return jsonb_build_object('ok', false, 'message', 'الطالب غير موجود');
  end if;

  if p_followup_type not in ('call','message','meeting','promise','note','warning') then p_followup_type := 'note'; end if;
  if p_status not in ('open','done','cancelled') then p_status := 'open'; end if;

  insert into public.finance_followups(student_id, parent_id, followup_type, status, promised_date, promised_amount, notes, created_by)
  values (p_student_id, s.parent_id, p_followup_type, p_status, p_promised_date, p_promised_amount, p_notes, auth.uid())
  returning id into fid;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ المتابعة المالية', 'followup_id', fid);
end;
$$;

grant execute on function public.add_finance_followup(uuid,text,date,numeric,text,text) to authenticated;

-- -------------------------------------------------------------
-- 7) كشف حساب طالب Payload
-- -------------------------------------------------------------
create or replace function public.get_student_finance_statement(p_student_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  s record;
  fees jsonb;
  installments jsonb;
  payments jsonb;
  followups jsonb;
begin
  select * into s from public.students where id = p_student_id;
  if s.id is null then return jsonb_build_object('ok', false, 'message', 'الطالب غير موجود'); end if;

  if not (public.finance_can_manage() or s.user_id = auth.uid() or s.parent_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية عرض كشف الطالب المالي');
  end if;

  select coalesce(jsonb_agg(to_jsonb(f) order by f.created_at desc), '[]'::jsonb) into fees
  from public.v_finance_exec_student_balances f
  where f.student_id = p_student_id;

  select coalesce(jsonb_agg(to_jsonb(i) order by i.due_date), '[]'::jsonb) into installments
  from public.student_installments i
  join public.student_fees sf on sf.id = i.student_fee_id
  where sf.student_id = p_student_id;

  select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc), '[]'::jsonb) into payments
  from public.v_finance_exec_payments p
  where p.student_id = p_student_id;

  select coalesce(jsonb_agg(to_jsonb(fu) order by fu.created_at desc), '[]'::jsonb) into followups
  from public.finance_followups fu
  where fu.student_id = p_student_id;

  return jsonb_build_object('ok', true, 'student', to_jsonb(s), 'fees', fees, 'installments', installments, 'payments', payments, 'followups', followups);
end;
$$;

grant execute on function public.get_student_finance_statement(uuid) to authenticated;

-- -------------------------------------------------------------
-- 8) فحص
-- -------------------------------------------------------------
create or replace function public.finance_collection_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'followups_table', to_regclass('public.finance_followups') is not null,
    'collection_view', to_regclass('public.v_finance_collection_students') is not null,
    'payload_rpc', to_regprocedure('public.get_finance_collection_payload(uuid,int)') is not null,
    'reminders_rpc', to_regprocedure('public.send_finance_overdue_reminders(uuid,uuid,int)') is not null,
    'followup_rpc', to_regprocedure('public.add_finance_followup(uuid,text,date,numeric,text,text)') is not null,
    'statement_rpc', to_regprocedure('public.get_student_finance_statement(uuid)') is not null,
    'stats', case when public.finance_can_manage() then public.get_finance_collection_payload(null,0)->'stats' else '{}'::jsonb end
  );
end;
$$;

grant execute on function public.finance_collection_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'finance_collections_followups_ready' as status;

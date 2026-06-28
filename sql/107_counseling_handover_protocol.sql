-- =============================================================
-- مدارس أمين الرضا (ع) — بروتوكول تسليم حالات الإرشاد النفسي
-- يضيف تسليم موثق بين مرشد وآخر مع قبول رسمي وتحديث مالك الحالة.
-- آمن ويمكن تشغيله أكثر من مرة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) دوال صلاحيات احتياطية
-- -------------------------------------------------------------
create or replace function public.current_user_is_super_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(select 1 from public.users u where u.id = auth.uid() and coalesce(u.is_super_admin,false)=true);
$$;

grant execute on function public.current_user_is_super_admin() to authenticated;

-- -------------------------------------------------------------
-- 1) جدول تسليم الحالات
-- -------------------------------------------------------------
create table if not exists public.counseling_handover_notes (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.counseling_cases(id) on delete cascade,
  from_counselor_id uuid not null references public.users(id) on delete cascade default auth.uid(),
  to_counselor_id uuid not null references public.users(id) on delete cascade,
  urgency text not null default 'within_week' check (urgency in ('immediate','within_week','stable')),
  current_status text,
  key_points text,
  unfinished_work text,
  recommendation text,
  status text not null default 'submitted' check (status in ('draft','submitted','accepted','cancelled')),
  submitted_at timestamptz not null default now(),
  accepted_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.counseling_handover_notes add column if not exists urgency text not null default 'within_week';
alter table public.counseling_handover_notes add column if not exists current_status text;
alter table public.counseling_handover_notes add column if not exists key_points text;
alter table public.counseling_handover_notes add column if not exists unfinished_work text;
alter table public.counseling_handover_notes add column if not exists recommendation text;
alter table public.counseling_handover_notes add column if not exists status text not null default 'submitted';
alter table public.counseling_handover_notes add column if not exists accepted_at timestamptz;
alter table public.counseling_handover_notes add column if not exists cancelled_at timestamptz;
alter table public.counseling_handover_notes add column if not exists updated_at timestamptz not null default now();

create index if not exists idx_counseling_handover_from on public.counseling_handover_notes(from_counselor_id, status, created_at desc);
create index if not exists idx_counseling_handover_to on public.counseling_handover_notes(to_counselor_id, status, created_at desc);
create index if not exists idx_counseling_handover_case on public.counseling_handover_notes(case_id, status);

alter table public.counseling_handover_notes enable row level security;

drop policy if exists counseling_handover_select_scoped on public.counseling_handover_notes;
drop policy if exists counseling_handover_insert_scoped on public.counseling_handover_notes;
drop policy if exists counseling_handover_update_scoped on public.counseling_handover_notes;

create policy counseling_handover_select_scoped
on public.counseling_handover_notes
for select
to authenticated
using (
  public.current_user_can_counseling()
  and (
    from_counselor_id = auth.uid()
    or to_counselor_id = auth.uid()
    or public.current_user_is_super_admin()
  )
);

create policy counseling_handover_insert_scoped
on public.counseling_handover_notes
for insert
to authenticated
with check (
  public.current_user_can_counseling()
  and (from_counselor_id = auth.uid() or public.current_user_is_super_admin())
);

create policy counseling_handover_update_scoped
on public.counseling_handover_notes
for update
to authenticated
using (
  public.current_user_can_counseling()
  and (
    from_counselor_id = auth.uid()
    or to_counselor_id = auth.uid()
    or public.current_user_is_super_admin()
  )
)
with check (
  public.current_user_can_counseling()
  and (
    from_counselor_id = auth.uid()
    or to_counselor_id = auth.uid()
    or public.current_user_is_super_admin()
  )
);

revoke insert, update, delete on public.counseling_handover_notes from authenticated, anon;
grant select on public.counseling_handover_notes to authenticated;

-- -------------------------------------------------------------
-- 2) View تفصيلي
-- -------------------------------------------------------------
create or replace view public.v_counseling_handover_detailed
with (security_invoker=true) as
select
  h.id,
  h.case_id,
  public._counseling_student_name(c.student_id) as student_name,
  c.student_id,
  cl.name as class_name,
  h.from_counselor_id,
  coalesce(fu.name, fu.email) as from_counselor_name,
  h.to_counselor_id,
  coalesce(tu.name, tu.email) as to_counselor_name,
  h.urgency,
  h.current_status,
  h.key_points,
  h.unfinished_work,
  h.recommendation,
  h.status,
  h.submitted_at,
  h.accepted_at,
  h.cancelled_at,
  h.created_at,
  h.updated_at
from public.counseling_handover_notes h
join public.counseling_cases c on c.id = h.case_id
join public.students s on s.id = c.student_id
left join public.classes cl on cl.id = s.class_id
left join public.users fu on fu.id = h.from_counselor_id
left join public.users tu on tu.id = h.to_counselor_id;

grant select on public.v_counseling_handover_detailed to authenticated;

-- -------------------------------------------------------------
-- 3) Payload للواجهة
-- -------------------------------------------------------------
create or replace function public.get_counseling_handover_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  u record;
  incoming jsonb := '[]'::jsonb;
  outgoing jsonb := '[]'::jsonb;
  counselors jsonb := '[]'::jsonb;
  cases_json jsonb := '[]'::jsonb;
begin
  select id, name, email, role, is_super_admin into u from public.users where id = auth.uid();
  if u.id is null then
    return jsonb_build_object('ok',false,'message','يجب تسجيل الدخول');
  end if;

  if not public.current_user_can_counseling() then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية تسليم الحالات');
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into incoming
  from (
    select * from public.v_counseling_handover_detailed
    where status = 'submitted'
      and (to_counselor_id = auth.uid() or public.current_user_is_super_admin())
    order by created_at desc
    limit 100
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into outgoing
  from (
    select * from public.v_counseling_handover_detailed
    where from_counselor_id = auth.uid() or public.current_user_is_super_admin()
    order by created_at desc
    limit 100
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'role',q.role) order by q.name), '[]'::jsonb)
  into counselors
  from (
    select id, coalesce(name,email,'مرشد') as name, role
    from public.users
    where (role in ('counselor','psychologist') or coalesce(is_super_admin,false)=true)
      and id <> auth.uid()
    order by coalesce(name,email,'مرشد')
  ) q;

  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'student_name',q.student_name,'class_name',q.class_name,'risk_level',q.risk_level,'progress_percent',q.progress_percent) order by q.student_name), '[]'::jsonb)
  into cases_json
  from (
    select id, student_name, class_name, risk_level, progress_percent
    from public.v_counseling_cases_detailed
    where status in ('active','watch')
      and (counselor_id = auth.uid() or public.current_user_is_super_admin())
    order by student_name
    limit 500
  ) q;

  return jsonb_build_object(
    'ok', true,
    'profile', jsonb_build_object('id',u.id,'name',u.name,'email',u.email,'role',u.role,'is_super_admin',u.is_super_admin),
    'incoming', incoming,
    'outgoing', outgoing,
    'counselors', counselors,
    'cases', cases_json,
    'summary', jsonb_build_object(
      'incoming_pending', jsonb_array_length(incoming),
      'outgoing_total', jsonb_array_length(outgoing),
      'available_counselors', jsonb_array_length(counselors),
      'cases_available', jsonb_array_length(cases_json)
    )
  );
end;
$$;

grant execute on function public.get_counseling_handover_payload() to authenticated;

-- -------------------------------------------------------------
-- 4) إنشاء/قبول/إلغاء التسليم
-- -------------------------------------------------------------
create or replace function public.create_counseling_handover(p_case_id uuid, p_to_counselor_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c record;
  hid uuid;
  urgency text;
  student_name text := 'طالب';
begin
  if not public.current_user_can_counseling() then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية تسليم الحالات');
  end if;

  select * into c from public.counseling_cases where id = p_case_id;
  if c.id is null then
    return jsonb_build_object('ok',false,'message','الحالة غير موجودة');
  end if;

  if not (c.counselor_id = auth.uid() or public.current_user_is_super_admin()) then
    return jsonb_build_object('ok',false,'message','لا يمكنك تسليم حالة ليست ضمن مسؤوليتك');
  end if;

  if not exists(select 1 from public.users u where u.id = p_to_counselor_id and (u.role in ('counselor','psychologist') or coalesce(u.is_super_admin,false)=true)) then
    return jsonb_build_object('ok',false,'message','المرشد المستلم غير صالح');
  end if;

  urgency := coalesce(nullif(p_payload->>'urgency',''),'within_week');
  if urgency not in ('immediate','within_week','stable') then urgency := 'within_week'; end if;
  select public._counseling_student_name(c.student_id) into student_name;

  insert into public.counseling_handover_notes(
    case_id, from_counselor_id, to_counselor_id, urgency,
    current_status, key_points, unfinished_work, recommendation, status
  ) values (
    c.id, auth.uid(), p_to_counselor_id, urgency,
    nullif(p_payload->>'current_status',''),
    nullif(p_payload->>'key_points',''),
    nullif(p_payload->>'unfinished_work',''),
    nullif(p_payload->>'recommendation',''),
    'submitted'
  ) returning id into hid;

  if to_regclass('public.school_notifications') is not null then
    insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
    values(p_to_counselor_id, 'counselor', 'تسليم حالة إرشادية', 'تم تسليم حالة ' || coalesce(student_name,'طالب') || ' لك للمراجعة والاستلام.', 'counseling_handover', 'counseling_handover_notes', hid, auth.uid());
  end if;

  perform public.counseling_log_access('handover_create','counseling_handover_notes',hid,jsonb_build_object('case_id',c.id,'to',p_to_counselor_id));

  return jsonb_build_object('ok',true,'handover_id',hid,'message','تم إنشاء تسليم الحالة');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.create_counseling_handover(uuid,uuid,jsonb) to authenticated;

create or replace function public.accept_counseling_handover(p_handover_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
begin
  if not public.current_user_can_counseling() then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية استلام الحالات');
  end if;

  select * into h from public.counseling_handover_notes where id = p_handover_id and status='submitted';
  if h.id is null then
    return jsonb_build_object('ok',false,'message','طلب التسليم غير موجود أو تمت معالجته');
  end if;

  if not (h.to_counselor_id = auth.uid() or public.current_user_is_super_admin()) then
    return jsonb_build_object('ok',false,'message','هذه الحالة ليست مسندة لك للاستلام');
  end if;

  update public.counseling_handover_notes
  set status='accepted', accepted_at=now(), updated_at=now()
  where id = h.id;

  update public.counseling_cases
  set counselor_id = auth.uid(), updated_at = now()
  where id = h.case_id;

  perform public.counseling_log_access('handover_accept','counseling_handover_notes',h.id,jsonb_build_object('case_id',h.case_id));

  return jsonb_build_object('ok',true,'case_id',h.case_id,'message','تم استلام الحالة وتحديث المرشد المسؤول');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.accept_counseling_handover(uuid) to authenticated;

create or replace function public.cancel_counseling_handover(p_handover_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
begin
  select * into h from public.counseling_handover_notes where id=p_handover_id and status='submitted';
  if h.id is null then return jsonb_build_object('ok',false,'message','طلب التسليم غير موجود أو تمت معالجته'); end if;
  if not (h.from_counselor_id = auth.uid() or public.current_user_is_super_admin()) then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية إلغاء هذا التسليم');
  end if;
  update public.counseling_handover_notes set status='cancelled', cancelled_at=now(), updated_at=now() where id=h.id;
  perform public.counseling_log_access('handover_cancel','counseling_handover_notes',h.id,jsonb_build_object('case_id',h.case_id));
  return jsonb_build_object('ok',true,'message','تم إلغاء التسليم');
end;
$$;

grant execute on function public.cancel_counseling_handover(uuid) to authenticated;

-- -------------------------------------------------------------
-- 5) Health Check
-- -------------------------------------------------------------
create or replace function public.counseling_handover_health_check()
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
    'tables', jsonb_build_object('counseling_handover_notes', to_regclass('public.counseling_handover_notes') is not null),
    'views', jsonb_build_object('v_counseling_handover_detailed', to_regclass('public.v_counseling_handover_detailed') is not null),
    'functions', jsonb_build_object(
      'get_counseling_handover_payload', to_regprocedure('public.get_counseling_handover_payload()') is not null,
      'create_counseling_handover', to_regprocedure('public.create_counseling_handover(uuid,uuid,jsonb)') is not null,
      'accept_counseling_handover', to_regprocedure('public.accept_counseling_handover(uuid)') is not null,
      'cancel_counseling_handover', to_regprocedure('public.cancel_counseling_handover(uuid)') is not null
    ),
    'stats', jsonb_build_object(
      'submitted', coalesce((select count(*) from public.counseling_handover_notes where status='submitted'),0),
      'accepted', coalesce((select count(*) from public.counseling_handover_notes where status='accepted'),0),
      'cancelled', coalesce((select count(*) from public.counseling_handover_notes where status='cancelled'),0)
    ),
    'rls', public._security_rls_table('counseling_handover_notes')
  );
end;
$$;

grant execute on function public.counseling_handover_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.counseling_handover_health_check() as counseling_handover_health;

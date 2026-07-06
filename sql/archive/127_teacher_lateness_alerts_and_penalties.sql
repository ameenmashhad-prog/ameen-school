-- ============================================================================
-- 127) تنبيهات تأخير المعلمين وخصومات الحصص المرتبطة بالتأخير
-- مدارس أمين الرضا (ع)
--
-- السياسة الافتراضية:
-- - تأخير من 5 إلى 9 دقائق: كل 5 مرات = خصم حصة واحدة
-- - تأخير 10 دقائق فأكثر: كل 3 مرات = خصم حصة واحدة
--
-- ملاحظة:
-- هذا الملف يكمل SQL 126 الخاص بربط الراتب بالحصة (تحضير + واجب)
-- ويضيف طبقة الانضباط الزمني + تنبيهات الإدارة/المعاون العلمي.
-- ============================================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) صلاحية إدارة هذا الملف
-- -------------------------------------------------------------
create or replace function public.current_user_can_manage_teacher_lateness()
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
      and (
        coalesce(u.is_super_admin,false) = true
        or u.role in ('admin','academic','academic_admin','scientific','supervisor')
      )
  );
$$;

grant execute on function public.current_user_can_manage_teacher_lateness() to authenticated;

-- -------------------------------------------------------------
-- 2) قواعد التأخير والخصم
-- -------------------------------------------------------------
create table if not exists public.teacher_lateness_rules (
  id uuid primary key default gen_random_uuid(),
  rule_name text not null,
  min_late_minutes int not null,
  max_late_minutes int null,
  repeat_count int not null default 1,
  penalty_session_units numeric not null default 1,
  is_active boolean not null default true,
  sort_order int not null default 100,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

with ranked as (
  select id,
         row_number() over (
           partition by min_late_minutes, coalesce(max_late_minutes,-1), repeat_count, penalty_session_units
           order by created_at asc, id asc
         ) as rn
  from public.teacher_lateness_rules
)
delete from public.teacher_lateness_rules t
using ranked r
where t.id = r.id and r.rn > 1;

create unique index if not exists uq_teacher_lateness_rules_logic
  on public.teacher_lateness_rules(min_late_minutes, coalesce(max_late_minutes,-1), repeat_count, penalty_session_units);

insert into public.teacher_lateness_rules(rule_name,min_late_minutes,max_late_minutes,repeat_count,penalty_session_units,is_active,sort_order,notes)
values
  ('تأخير 5 إلى 9 دقائق',5,9,5,1,true,10,'كل 5 مرات = خصم حصة واحدة'),
  ('تأخير 10 دقائق فأكثر',10,null,3,1,true,20,'كل 3 مرات = خصم حصة واحدة')
on conflict do nothing;

alter table public.teacher_lateness_rules enable row level security;

drop policy if exists teacher_lateness_rules_manage on public.teacher_lateness_rules;
create policy teacher_lateness_rules_manage on public.teacher_lateness_rules
  for all to authenticated
  using (public.current_user_can_manage_teacher_lateness())
  with check (public.current_user_can_manage_teacher_lateness());

grant select, insert, update on public.teacher_lateness_rules to authenticated;

-- -------------------------------------------------------------
-- 3) تسجيل دخول المعلم للحصة + حساب التأخير
-- -------------------------------------------------------------
create table if not exists public.teacher_session_checkins (
  id uuid primary key default gen_random_uuid(),
  class_session_id uuid not null unique references public.class_sessions(id) on delete cascade,
  teacher_id uuid not null references public.users(id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  late_minutes int not null default 0,
  late_status text not null default 'on_time' check (late_status in ('on_time','late')),
  notes text,
  recorded_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_teacher_session_checkins_teacher_date on public.teacher_session_checkins(teacher_id, checked_in_at desc);

alter table public.teacher_session_checkins enable row level security;

drop policy if exists teacher_session_checkins_manage on public.teacher_session_checkins;
create policy teacher_session_checkins_manage on public.teacher_session_checkins
  for all to authenticated
  using (
    public.current_user_can_manage_teacher_lateness()
    or teacher_id = auth.uid()
  )
  with check (
    public.current_user_can_manage_teacher_lateness()
    or teacher_id = auth.uid()
  );

grant select, insert, update on public.teacher_session_checkins to authenticated;

-- -------------------------------------------------------------
-- 4) دالة تسجيل الدخول للحصة والتنبيه على التأخير
-- -------------------------------------------------------------
create or replace function public.teacher_check_in_session(
  p_session_id uuid,
  p_checked_in_at timestamptz default now(),
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s record;
  v_uid uuid := auth.uid();
  scheduled_ts timestamp;
  actual_ts timestamp;
  late_mins int := 0;
  status_text text := 'on_time';
  checkin_id uuid;
  rec record;
begin
  select * into s from public.class_sessions where id = p_session_id;
  if s.id is null then
    return jsonb_build_object('ok', false, 'message', 'الحصة غير موجودة');
  end if;

  if s.start_time is null then
    return jsonb_build_object('ok', false, 'message', 'لا يوجد وقت بداية مضبوط لهذه الحصة');
  end if;

  if v_uid is not null and s.teacher_id <> v_uid and not public.current_user_can_manage_teacher_lateness() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تسجيل دخول هذه الحصة');
  end if;

  scheduled_ts := (s.session_date::timestamp + s.start_time);
  actual_ts := (coalesce(p_checked_in_at, now()) at time zone 'Asia/Tehran');
  late_mins := greatest(0, floor(extract(epoch from (actual_ts - scheduled_ts)) / 60)::int);
  status_text := case when late_mins >= 5 then 'late' else 'on_time' end;

  insert into public.teacher_session_checkins(
    class_session_id, teacher_id, checked_in_at, late_minutes, late_status, notes, recorded_by
  ) values (
    s.id, s.teacher_id, coalesce(p_checked_in_at, now()), late_mins, status_text, p_notes, v_uid
  )
  on conflict (class_session_id) do update set
    checked_in_at = excluded.checked_in_at,
    late_minutes = excluded.late_minutes,
    late_status = excluded.late_status,
    notes = excluded.notes,
    recorded_by = excluded.recorded_by,
    updated_at = now()
  returning id into checkin_id;

  if status_text = 'late' then
    for rec in
      select id, role, name
      from public.users
      where coalesce(is_super_admin,false) = true
         or role in ('admin','academic','academic_admin','scientific','supervisor')
    loop
      if not exists(
        select 1 from public.school_notifications n
        where n.recipient_user_id = rec.id
          and n.entity_table = 'teacher_session_checkins'
          and n.entity_id = checkin_id
          and n.notification_type = 'teacher_lateness'
      ) then
        insert into public.school_notifications(
          recipient_user_id,
          recipient_role,
          title,
          body,
          notification_type,
          entity_table,
          entity_id,
          created_by
        ) values (
          rec.id,
          rec.role,
          'تنبيه تأخير معلم',
          'تم تسجيل تأخير للمعلم/ة في الحصة رقم '||coalesce(s.period_number::text,'—')||' بمقدار '||late_mins||' دقيقة.',
          'teacher_lateness',
          'teacher_session_checkins',
          checkin_id,
          v_uid
        );
      end if;
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true,
    'message', case when status_text='late' then 'تم تسجيل الدخول مع تأخير' else 'تم تسجيل الدخول في الوقت' end,
    'checkin_id', checkin_id,
    'late_minutes', late_mins,
    'late_status', status_text
  );
end;
$$;

grant execute on function public.teacher_check_in_session(uuid,timestamptz,text) to authenticated;

-- -------------------------------------------------------------
-- 5) Views للتنبيهات والخصومات
-- -------------------------------------------------------------
create or replace view public.v_teacher_lateness_events
with (security_invoker=true) as
select
  tsc.id,
  tsc.class_session_id,
  cs.session_date,
  cs.period_number,
  cs.start_time,
  tsc.teacher_id,
  u.name as teacher_name,
  cs.class_id,
  c.name as class_name,
  cs.subject_id,
  s.name as subject_name,
  tsc.checked_in_at,
  tsc.late_minutes,
  tsc.late_status,
  case
    when tsc.late_minutes >= 10 then '10_plus'
    when tsc.late_minutes >= 5 then '5_to_9'
    else 'on_time'
  end as lateness_band,
  tsc.notes,
  tsc.created_at,
  tsc.updated_at
from public.teacher_session_checkins tsc
join public.class_sessions cs on cs.id = tsc.class_session_id
left join public.users u on u.id = tsc.teacher_id
left join public.classes c on c.id = cs.class_id
left join public.subjects s on s.id = cs.subject_id;

grant select on public.v_teacher_lateness_events to authenticated;

create or replace view public.v_teacher_lateness_penalties_monthly
with (security_invoker=true) as
with matched as (
  select
    e.teacher_id,
    e.teacher_name,
    date_trunc('month', e.session_date)::date as month,
    r.id as rule_id,
    r.rule_name,
    r.repeat_count,
    r.penalty_session_units,
    count(*) as late_events
  from public.v_teacher_lateness_events e
  join public.teacher_lateness_rules r
    on r.is_active = true
   and e.late_status = 'late'
   and e.late_minutes >= r.min_late_minutes
   and (r.max_late_minutes is null or e.late_minutes <= r.max_late_minutes)
  group by e.teacher_id, e.teacher_name, date_trunc('month', e.session_date)::date, r.id, r.rule_name, r.repeat_count, r.penalty_session_units
)
select
  teacher_id,
  teacher_name,
  month,
  rule_id,
  rule_name,
  repeat_count,
  penalty_session_units,
  late_events,
  floor(late_events::numeric / nullif(repeat_count,0))::int as penalty_batches,
  round(floor(late_events::numeric / nullif(repeat_count,0)) * penalty_session_units, 2) as penalty_session_units_total
from matched;

grant select on public.v_teacher_lateness_penalties_monthly to authenticated;

create or replace view public.v_teacher_lateness_today
with (security_invoker=true) as
select *
from public.v_teacher_lateness_events
where session_date = current_date and late_status = 'late'
order by late_minutes desc, checked_in_at asc;

grant select on public.v_teacher_lateness_today to authenticated;

-- -------------------------------------------------------------
-- 6) تحديث كشف الراتب الشهري إذا كانت طبقة الحصص اليومية موجودة
-- -------------------------------------------------------------
do $$
begin
  if to_regclass('public.v_teacher_payroll_daily') is not null then
    execute 'drop view if exists public.v_teacher_payroll_preview';
    execute $sql$
      create or replace view public.v_teacher_payroll_preview
      with (security_invoker=true) as
      with monthly as (
        select
          d.teacher_id,
          d.teacher_name,
          date_trunc('month', d.session_date)::date as month,
          sum(d.total_sessions) as total_sessions,
          sum(d.prepared_sessions) as prepared_sessions,
          sum(d.homework_sessions) as homework_sessions,
          round(sum(d.earned_session_units), 2) as gross_verified_sessions,
          sum(d.fully_documented_sessions) as fully_documented_sessions,
          sum(d.incomplete_sessions) as incomplete_sessions,
          coalesce(r.amount_per_verified_session, gr.amount_per_verified_session, 0) as amount_per_session,
          coalesce(r.currency, gr.currency, 'USD') as currency
        from public.v_teacher_payroll_daily d
        left join public.teacher_payroll_rules r
          on r.teacher_id = d.teacher_id and r.active = true
        left join public.teacher_payroll_rules gr
          on gr.teacher_id is null and gr.active = true
        group by d.teacher_id, d.teacher_name, date_trunc('month', d.session_date)::date, r.amount_per_verified_session, gr.amount_per_verified_session, r.currency, gr.currency
      ), penalties as (
        select teacher_id, month, round(sum(penalty_session_units_total),2) as penalty_session_units
        from public.v_teacher_lateness_penalties_monthly
        group by teacher_id, month
      )
      select
        m.teacher_id,
        m.teacher_name,
        m.month,
        m.total_sessions,
        m.prepared_sessions,
        m.homework_sessions,
        m.gross_verified_sessions,
        coalesce(p.penalty_session_units,0) as penalty_session_units,
        greatest(0, round(m.gross_verified_sessions - coalesce(p.penalty_session_units,0), 2)) as verified_sessions,
        m.amount_per_session,
        m.currency,
        round(greatest(0, m.gross_verified_sessions - coalesce(p.penalty_session_units,0)) * m.amount_per_session, 2) as estimated_amount,
        m.fully_documented_sessions,
        m.incomplete_sessions
      from monthly m
      left join penalties p on p.teacher_id = m.teacher_id and p.month = m.month
    $sql$;
  end if;
end $$;

grant select on public.v_teacher_payroll_preview to authenticated;

-- -------------------------------------------------------------
-- 7) Health Check
-- -------------------------------------------------------------
create or replace function public.teacher_lateness_rules_health_check()
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
    'rules_table', to_regclass('public.teacher_lateness_rules') is not null,
    'checkins_table', to_regclass('public.teacher_session_checkins') is not null,
    'events_view', to_regclass('public.v_teacher_lateness_events') is not null,
    'penalties_view', to_regclass('public.v_teacher_lateness_penalties_monthly') is not null,
    'today_view', to_regclass('public.v_teacher_lateness_today') is not null,
    'teacher_checkin_rpc', to_regprocedure('public.teacher_check_in_session(uuid,timestamptz,text)') is not null,
    'rules_count', (select count(*) from public.teacher_lateness_rules)
  );
end;
$$;

grant execute on function public.teacher_lateness_rules_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.teacher_lateness_rules_health_check() as teacher_lateness_rules_health;

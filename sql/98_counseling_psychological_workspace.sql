-- =============================================================
-- مدارس أمين الرضا (ع) — الجانب النفسي / صفحة المرشد النفسي
-- School Counselor Workspace: حالات، جلسات SOAP، أهداف، إحالات، مهام، خصوصية.
-- آمن وإضافي ويمكن تشغيله أكثر من مرة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) دوال صلاحيات
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

create or replace function public.current_user_is_super_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.users u where u.id = auth.uid() and coalesce(u.is_super_admin,false)=true
  );
$$;

grant execute on function public.current_user_is_super_admin() to authenticated;

create or replace function public.current_user_can_counseling()
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
        coalesce(u.is_super_admin,false)=true
        or u.role in ('admin','counselor','psychologist','academic','academic_admin','scientific','supervisor')
      )
  );
$$;

grant execute on function public.current_user_can_counseling() to authenticated;

create or replace function public.current_user_can_create_referral()
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
        coalesce(u.is_super_admin,false)=true
        or u.role in ('admin','teacher','staff','academic','academic_admin','scientific','supervisor','discipline','counselor','psychologist')
      )
  );
$$;

grant execute on function public.current_user_can_create_referral() to authenticated;

-- -------------------------------------------------------------
-- 1) الجداول المعزولة للجانب النفسي
-- -------------------------------------------------------------
create table if not exists public.counseling_cases (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  counselor_id uuid null references public.users(id) on delete set null,
  status text not null default 'active' check (status in ('active','watch','closed','archived')),
  risk_level text not null default 'new' check (risk_level in ('new','stable','followup','medium','high','urgent','crisis')),
  concern_tags text[] not null default array[]::text[],
  intake_source text,
  summary text,
  strengths text,
  risk_flags text,
  progress_percent int not null default 0 check (progress_percent between 0 and 100),
  opened_at timestamptz not null default now(),
  next_session_at timestamptz,
  closed_at timestamptz,
  created_by uuid null references public.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.counseling_cases add column if not exists counselor_id uuid null references public.users(id) on delete set null;
alter table public.counseling_cases add column if not exists status text not null default 'active';
alter table public.counseling_cases add column if not exists risk_level text not null default 'new';
alter table public.counseling_cases add column if not exists concern_tags text[] not null default array[]::text[];
alter table public.counseling_cases add column if not exists intake_source text;
alter table public.counseling_cases add column if not exists summary text;
alter table public.counseling_cases add column if not exists strengths text;
alter table public.counseling_cases add column if not exists risk_flags text;
alter table public.counseling_cases add column if not exists progress_percent int not null default 0;
alter table public.counseling_cases add column if not exists next_session_at timestamptz;
alter table public.counseling_cases add column if not exists closed_at timestamptz;
alter table public.counseling_cases add column if not exists updated_at timestamptz not null default now();

create unique index if not exists uq_counseling_active_case_student on public.counseling_cases(student_id) where status in ('active','watch');
create index if not exists idx_counseling_cases_counselor on public.counseling_cases(counselor_id, status, risk_level, next_session_at);
create index if not exists idx_counseling_cases_student on public.counseling_cases(student_id, status);

create table if not exists public.counseling_sessions (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.counseling_cases(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  counselor_id uuid null references public.users(id) on delete set null,
  session_at timestamptz not null default now(),
  duration_minutes int not null default 45 check (duration_minutes between 5 and 240),
  session_type text not null default 'individual' check (session_type in ('individual','group','family','crisis','followup','teacher_consult','parent_call')),
  location text,
  session_protocol text not null default 'open_door' check (session_protocol in ('open_door','guardian_nearby','group','remote_guardian','not_applicable')),
  internal_label text,
  external_label text not null default 'برنامج تطوير المهارات والمتابعة التربوية',
  live_themes text[] not null default array[]::text[],
  subjective text,
  objective text,
  assessment text,
  plan text,
  mood_before int check (mood_before between 1 and 10),
  mood_after int check (mood_after between 1 and 10),
  risk_level text not null default 'stable' check (risk_level in ('stable','followup','medium','high','urgent','crisis')),
  progress_percent int not null default 0 check (progress_percent between 0 and 100),
  next_session_at timestamptz,
  status text not null default 'completed' check (status in ('scheduled','started','completed','cancelled')),
  confidential boolean not null default true,
  created_by uuid null references public.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.counseling_sessions add column if not exists session_protocol text not null default 'open_door';
alter table public.counseling_sessions add column if not exists internal_label text;
alter table public.counseling_sessions add column if not exists external_label text not null default 'برنامج تطوير المهارات والمتابعة التربوية';
alter table public.counseling_sessions add column if not exists live_themes text[] not null default array[]::text[];
alter table public.counseling_cases add column if not exists external_label text not null default 'برنامج تطوير المهارات والمتابعة التربوية';
alter table public.counseling_cases add column if not exists family_context jsonb not null default '{}'::jsonb;

create index if not exists idx_counseling_sessions_case on public.counseling_sessions(case_id, session_at desc);
create index if not exists idx_counseling_sessions_counselor_date on public.counseling_sessions(counselor_id, session_at desc);

create table if not exists public.counseling_goals (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.counseling_cases(id) on delete cascade,
  title text not null,
  category text not null default 'social_emotional' check (category in ('academic','social_emotional','behavior','career','family','wellbeing','other')),
  indicator text,
  target_date date,
  progress_percent int not null default 0 check (progress_percent between 0 and 100),
  status text not null default 'active' check (status in ('active','completed','paused','cancelled')),
  created_by uuid null references public.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_counseling_goals_case on public.counseling_goals(case_id, status, target_date);

create table if not exists public.counseling_assessments (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.counseling_cases(id) on delete cascade,
  tool text not null default 'risk_custom' check (tool in ('gad7','cdi','swemwbs','risk_custom','teacher_rating','family_climate','other')),
  score numeric,
  max_score numeric,
  risk_level text default 'stable' check (risk_level in ('stable','followup','medium','high','urgent','crisis')),
  answers jsonb not null default '{}'::jsonb,
  notes text,
  assessed_at timestamptz not null default now(),
  created_by uuid null references public.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists idx_counseling_assessments_case on public.counseling_assessments(case_id, assessed_at desc);

create table if not exists public.counseling_family_contacts (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.counseling_cases(id) on delete cascade,
  contact_name text,
  relationship text,
  method text not null default 'phone' check (method in ('phone','message','meeting','whatsapp','email','other')),
  contact_at timestamptz not null default now(),
  duration_minutes int,
  summary text,
  outcome text,
  created_by uuid null references public.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists idx_counseling_family_contacts_case on public.counseling_family_contacts(case_id, contact_at desc);

create table if not exists public.counseling_referrals (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  referred_by uuid null references public.users(id) on delete set null default auth.uid(),
  assigned_counselor_id uuid null references public.users(id) on delete set null,
  urgency text not null default 'followup' check (urgency in ('stable','followup','medium','high','urgent','crisis')),
  concern text not null,
  source text default 'teacher',
  status text not null default 'pending' check (status in ('pending','accepted','deferred','rejected','closed')),
  counselor_note text,
  handled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_counseling_referrals_status on public.counseling_referrals(status, urgency, created_at desc);
create index if not exists idx_counseling_referrals_student on public.counseling_referrals(student_id, status);

create table if not exists public.counseling_tasks (
  id uuid primary key default gen_random_uuid(),
  case_id uuid null references public.counseling_cases(id) on delete cascade,
  counselor_id uuid null references public.users(id) on delete cascade default auth.uid(),
  title text not null,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  due_at timestamptz,
  status text not null default 'open' check (status in ('open','done','snoozed','cancelled')),
  created_by uuid null references public.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists idx_counseling_tasks_counselor on public.counseling_tasks(counselor_id, status, due_at);

create table if not exists public.counseling_access_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid null references public.users(id) on delete set null default auth.uid(),
  action text not null,
  entity_table text,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_counseling_access_logs_actor on public.counseling_access_logs(actor_user_id, created_at desc);

-- -------------------------------------------------------------
-- 2) RLS: تفاصيل الإرشاد لا يراها إلا المرشد/المصرح
-- -------------------------------------------------------------
alter table public.counseling_cases enable row level security;
alter table public.counseling_sessions enable row level security;
alter table public.counseling_goals enable row level security;
alter table public.counseling_assessments enable row level security;
alter table public.counseling_family_contacts enable row level security;
alter table public.counseling_referrals enable row level security;
alter table public.counseling_tasks enable row level security;
alter table public.counseling_access_logs enable row level security;

drop policy if exists counseling_cases_full_access on public.counseling_cases;
drop policy if exists counseling_sessions_full_access on public.counseling_sessions;
drop policy if exists counseling_goals_full_access on public.counseling_goals;
drop policy if exists counseling_assessments_full_access on public.counseling_assessments;
drop policy if exists counseling_family_contacts_full_access on public.counseling_family_contacts;
drop policy if exists counseling_referrals_select_scoped on public.counseling_referrals;
drop policy if exists counseling_referrals_insert_allowed on public.counseling_referrals;
drop policy if exists counseling_referrals_update_counselor on public.counseling_referrals;
drop policy if exists counseling_tasks_full_access on public.counseling_tasks;
drop policy if exists counseling_access_logs_own_insert on public.counseling_access_logs;
drop policy if exists counseling_access_logs_admin_select on public.counseling_access_logs;

create policy counseling_cases_full_access on public.counseling_cases
for all to authenticated
using (public.current_user_can_counseling() and (public.current_user_is_admin() or counselor_id = auth.uid() or counselor_id is null))
with check (public.current_user_can_counseling());

create policy counseling_sessions_full_access on public.counseling_sessions
for all to authenticated
using (public.current_user_can_counseling() and exists(select 1 from public.counseling_cases c where c.id=case_id and (public.current_user_is_admin() or c.counselor_id=auth.uid() or c.counselor_id is null)))
with check (public.current_user_can_counseling());

create policy counseling_goals_full_access on public.counseling_goals
for all to authenticated
using (public.current_user_can_counseling() and exists(select 1 from public.counseling_cases c where c.id=case_id and (public.current_user_is_admin() or c.counselor_id=auth.uid() or c.counselor_id is null)))
with check (public.current_user_can_counseling());

create policy counseling_assessments_full_access on public.counseling_assessments
for all to authenticated
using (public.current_user_can_counseling() and exists(select 1 from public.counseling_cases c where c.id=case_id and (public.current_user_is_admin() or c.counselor_id=auth.uid() or c.counselor_id is null)))
with check (public.current_user_can_counseling());

create policy counseling_family_contacts_full_access on public.counseling_family_contacts
for all to authenticated
using (public.current_user_can_counseling() and exists(select 1 from public.counseling_cases c where c.id=case_id and (public.current_user_is_admin() or c.counselor_id=auth.uid() or c.counselor_id is null)))
with check (public.current_user_can_counseling());

create policy counseling_referrals_select_scoped on public.counseling_referrals
for select to authenticated
using (public.current_user_can_counseling() or referred_by=auth.uid());

create policy counseling_referrals_insert_allowed on public.counseling_referrals
for insert to authenticated
with check (public.current_user_can_create_referral());

create policy counseling_referrals_update_counselor on public.counseling_referrals
for update to authenticated
using (public.current_user_can_counseling())
with check (public.current_user_can_counseling());

create policy counseling_tasks_full_access on public.counseling_tasks
for all to authenticated
using (public.current_user_can_counseling() and (public.current_user_is_admin() or counselor_id=auth.uid()))
with check (public.current_user_can_counseling());

create policy counseling_access_logs_own_insert on public.counseling_access_logs
for insert to authenticated
with check (actor_user_id = auth.uid() or actor_user_id is null);

create policy counseling_access_logs_admin_select on public.counseling_access_logs
for select to authenticated
using (public.current_user_is_admin());

grant select, insert, update on public.counseling_cases to authenticated;
grant select, insert, update on public.counseling_sessions to authenticated;
grant select, insert, update on public.counseling_goals to authenticated;
grant select, insert, update on public.counseling_assessments to authenticated;
grant select, insert, update on public.counseling_family_contacts to authenticated;
grant select, insert, update on public.counseling_referrals to authenticated;
grant select, insert, update on public.counseling_tasks to authenticated;
grant select, insert on public.counseling_access_logs to authenticated;

-- -------------------------------------------------------------
-- 3) Views آمنة ومختصرة
-- -------------------------------------------------------------
create or replace function public._counseling_student_name(p_student_id uuid)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(nullif(trim(concat_ws(' ', s.name, s.last_name)),''), s.name, 'طالب')
  from public.students s
  where s.id = p_student_id;
$$;

grant execute on function public._counseling_student_name(uuid) to authenticated;

create or replace view public.v_counseling_cases_detailed
with (security_invoker=true) as
select
  c.id,
  c.student_id,
  public._counseling_student_name(c.student_id) as student_name,
  s.gender,
  s.user_id as student_user_id,
  s.parent_id,
  s.class_id,
  cl.name as class_name,
  c.counselor_id,
  coalesce(u.name,u.email) as counselor_name,
  c.status,
  c.risk_level,
  c.concern_tags,
  c.intake_source,
  c.summary,
  c.strengths,
  c.risk_flags,
  c.progress_percent,
  c.opened_at,
  c.next_session_at,
  c.updated_at,
  (select count(*) from public.counseling_sessions cs where cs.case_id=c.id)::int as sessions_count,
  (select max(cs.session_at) from public.counseling_sessions cs where cs.case_id=c.id) as last_session_at,
  (select count(*) from public.counseling_goals g where g.case_id=c.id and g.status='active')::int as active_goals,
  (select count(*) from public.counseling_tasks t where t.case_id=c.id and t.status='open')::int as open_tasks
from public.counseling_cases c
join public.students s on s.id = c.student_id
left join public.classes cl on cl.id = s.class_id
left join public.users u on u.id = c.counselor_id;

grant select on public.v_counseling_cases_detailed to authenticated;

-- -------------------------------------------------------------
-- 4) RPC Payload
-- -------------------------------------------------------------
create or replace function public.counseling_log_access(p_action text, p_entity_table text default null, p_entity_id uuid default null, p_details jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.counseling_access_logs(actor_user_id, action, entity_table, entity_id, details)
  values(auth.uid(), coalesce(nullif(trim(p_action),''),'view'), p_entity_table, p_entity_id, coalesce(p_details,'{}'::jsonb));
  return jsonb_build_object('ok',true);
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.counseling_log_access(text,text,uuid,jsonb) to authenticated;

create or replace function public.get_counselor_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u record;
  can_access boolean := false;
  cases_json jsonb := '[]'::jsonb;
  sessions_json jsonb := '[]'::jsonb;
  goals_json jsonb := '[]'::jsonb;
  assessments_json jsonb := '[]'::jsonb;
  family_json jsonb := '[]'::jsonb;
  referrals_json jsonb := '[]'::jsonb;
  tasks_json jsonb := '[]'::jsonb;
  students_json jsonb := '[]'::jsonb;
  kpis jsonb := '{}'::jsonb;
begin
  select id,name,email,role,is_super_admin into u from public.users where id = auth.uid();
  if u.id is null then
    return jsonb_build_object('ok',false,'message','يجب تسجيل الدخول');
  end if;

  can_access := public.current_user_can_counseling();
  if not can_access then
    return jsonb_build_object('ok',false,'message','هذه الصفحة خاصة بالمرشد النفسي/الإدارة المخولة فقط');
  end if;

  perform public.counseling_log_access('payload','counseling_cases',null,jsonb_build_object('role',u.role));

  select coalesce(jsonb_agg(to_jsonb(x) order by
    case x.risk_level when 'crisis' then 1 when 'urgent' then 2 when 'high' then 3 when 'medium' then 4 when 'followup' then 5 when 'stable' then 6 else 7 end,
    x.next_session_at nulls last,
    x.updated_at desc
  ), '[]'::jsonb)
  into cases_json
  from (
    select *
    from public.v_counseling_cases_detailed v
    where v.status in ('active','watch')
      and (public.current_user_is_admin() or v.counselor_id = auth.uid() or v.counselor_id is null)
    limit 500
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.session_at desc), '[]'::jsonb)
  into sessions_json
  from (
    select cs.*
    from public.counseling_sessions cs
    join public.counseling_cases c on c.id = cs.case_id
    where (public.current_user_is_admin() or c.counselor_id = auth.uid() or c.counselor_id is null)
    order by cs.session_at desc
    limit 300
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into goals_json
  from (
    select g.*
    from public.counseling_goals g
    join public.counseling_cases c on c.id = g.case_id
    where (public.current_user_is_admin() or c.counselor_id = auth.uid() or c.counselor_id is null)
    order by g.created_at desc
    limit 300
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.assessed_at desc), '[]'::jsonb)
  into assessments_json
  from (
    select a.*
    from public.counseling_assessments a
    join public.counseling_cases c on c.id = a.case_id
    where (public.current_user_is_admin() or c.counselor_id = auth.uid() or c.counselor_id is null)
    order by a.assessed_at desc
    limit 300
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.contact_at desc), '[]'::jsonb)
  into family_json
  from (
    select fc.*
    from public.counseling_family_contacts fc
    join public.counseling_cases c on c.id = fc.case_id
    where (public.current_user_is_admin() or c.counselor_id = auth.uid() or c.counselor_id is null)
    order by fc.contact_at desc
    limit 300
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into referrals_json
  from (
    select r.*, public._counseling_student_name(r.student_id) as student_name, cl.name as class_name, coalesce(u2.name,u2.email) as referred_by_name
    from public.counseling_referrals r
    join public.students s on s.id=r.student_id
    left join public.classes cl on cl.id=s.class_id
    left join public.users u2 on u2.id=r.referred_by
    where r.status in ('pending','accepted','deferred')
      and (public.current_user_is_admin() or r.assigned_counselor_id=auth.uid() or r.assigned_counselor_id is null)
    order by r.created_at desc
    limit 100
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.due_at nulls last, x.created_at desc), '[]'::jsonb)
  into tasks_json
  from (
    select t.*, public._counseling_student_name(c.student_id) as student_name
    from public.counseling_tasks t
    left join public.counseling_cases c on c.id=t.case_id
    where t.status='open' and (public.current_user_is_admin() or t.counselor_id=auth.uid() or t.counselor_id is null)
    order by t.due_at nulls last, t.created_at desc
    limit 100
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'class_name',q.class_name) order by q.name), '[]'::jsonb)
  into students_json
  from (
    select s.id, public._counseling_student_name(s.id) as name, cl.name as class_name
    from public.students s
    left join public.classes cl on cl.id=s.class_id
    order by name
    limit 800
  ) q;

  kpis := jsonb_build_object(
    'active_cases', (select count(*) from public.counseling_cases where status in ('active','watch')),
    'urgent_cases', (select count(*) from public.counseling_cases where status in ('active','watch') and risk_level in ('urgent','crisis')),
    'sessions_month', (select count(*) from public.counseling_sessions where session_at >= date_trunc('month', now())),
    'pending_referrals', (select count(*) from public.counseling_referrals where status='pending'),
    'avg_progress', coalesce((select round(avg(progress_percent))::int from public.counseling_cases where status in ('active','watch')),0),
    'open_tasks', (select count(*) from public.counseling_tasks where status='open')
  );

  return jsonb_build_object(
    'ok', true,
    'profile', jsonb_build_object('id',u.id,'name',u.name,'email',u.email,'role',u.role,'is_super_admin',u.is_super_admin),
    'can_access', can_access,
    'can_manage', can_access,
    'cases', cases_json,
    'sessions', sessions_json,
    'goals', goals_json,
    'assessments', assessments_json,
    'family_contacts', family_json,
    'referrals', referrals_json,
    'tasks', tasks_json,
    'students', students_json,
    'kpis', kpis
  );
end;
$$;

grant execute on function public.get_counselor_payload() to authenticated;

-- -------------------------------------------------------------
-- 5) RPCs للعمليات السريعة
-- -------------------------------------------------------------
create or replace function public.counseling_upsert_case(
  p_student_id uuid,
  p_risk_level text default 'new',
  p_summary text default null,
  p_concern_tags text[] default array[]::text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid;
  risk text := case when p_risk_level in ('new','stable','followup','medium','high','urgent','crisis') then p_risk_level else 'new' end;
begin
  if not public.current_user_can_counseling() then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية فتح حالة إرشادية');
  end if;

  insert into public.counseling_cases(student_id, counselor_id, risk_level, summary, concern_tags, created_by)
  values(p_student_id, auth.uid(), risk, nullif(trim(coalesce(p_summary,'')),''), coalesce(p_concern_tags,array[]::text[]), auth.uid())
  on conflict (student_id) where status in ('active','watch') do update set
    counselor_id = coalesce(public.counseling_cases.counselor_id, auth.uid()),
    risk_level = excluded.risk_level,
    summary = coalesce(excluded.summary, public.counseling_cases.summary),
    concern_tags = case when array_length(excluded.concern_tags,1) is null then public.counseling_cases.concern_tags else excluded.concern_tags end,
    updated_at = now()
  returning id into cid;

  perform public.counseling_log_access('case_upsert','counseling_cases',cid,jsonb_build_object('student_id',p_student_id));
  return jsonb_build_object('ok',true,'case_id',cid,'message','تم فتح/تحديث الحالة');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.counseling_upsert_case(uuid,text,text,text[]) to authenticated;

create or replace function public.counseling_save_session(p_case_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c record;
  sid uuid;
  risk text;
  next_at timestamptz;
  prog int;
begin
  select * into c from public.counseling_cases where id = p_case_id;
  if c.id is null then return jsonb_build_object('ok',false,'message','الحالة غير موجودة'); end if;
  if not (public.current_user_can_counseling() and (public.current_user_is_admin() or c.counselor_id=auth.uid() or c.counselor_id is null)) then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية حفظ جلسة لهذه الحالة');
  end if;

  risk := coalesce(p_payload->>'risk_level','stable');
  if risk not in ('stable','followup','medium','high','urgent','crisis') then risk := 'stable'; end if;
  prog := greatest(0, least(100, coalesce((p_payload->>'progress_percent')::int, c.progress_percent, 0)));
  next_at := nullif(p_payload->>'next_session_at','')::timestamptz;

  insert into public.counseling_sessions(
    case_id, student_id, counselor_id, session_at, duration_minutes, session_type, location, session_protocol, internal_label, external_label, live_themes,
    subjective, objective, assessment, plan, mood_before, mood_after, risk_level, progress_percent, next_session_at, status, created_by
  ) values (
    c.id, c.student_id, coalesce(c.counselor_id,auth.uid()), coalesce(nullif(p_payload->>'session_at','')::timestamptz, now()),
    greatest(5, least(240, coalesce((p_payload->>'duration_minutes')::int,45))), coalesce(nullif(p_payload->>'session_type',''),'individual'),
    nullif(p_payload->>'location',''),
    coalesce(nullif(p_payload->>'session_protocol',''),'open_door'),
    nullif(p_payload->>'internal_label',''),
    coalesce(nullif(p_payload->>'external_label',''),'برنامج تطوير المهارات والمتابعة التربوية'),
    coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'live_themes','[]'::jsonb))), array[]::text[]),
    nullif(p_payload->>'subjective',''), nullif(p_payload->>'objective',''),
    nullif(p_payload->>'assessment',''), nullif(p_payload->>'plan',''), nullif(p_payload->>'mood_before','')::int,
    nullif(p_payload->>'mood_after','')::int, risk, prog, next_at, 'completed', auth.uid()
  ) returning id into sid;

  update public.counseling_cases
  set counselor_id = coalesce(counselor_id, auth.uid()), risk_level = risk, progress_percent = prog, next_session_at = next_at, updated_at = now()
  where id = c.id;

  if risk in ('urgent','crisis') then
    insert into public.counseling_tasks(case_id,counselor_id,title,priority,due_at,created_by)
    values(c.id, coalesce(c.counselor_id,auth.uid()), 'متابعة عاجلة بعد جلسة عالية الخطورة', 'urgent', now() + interval '1 day', auth.uid());
  end if;

  if to_regclass('public.completed_items') is not null then
    begin
      insert into public.completed_items(user_id, role, title, description, completion_type, source_table, source_id, date_gregorian, priority)
      values(auth.uid(), 'counselor', 'جلسة إرشادية مكتملة', 'تم توثيق جلسة إرشادية بصيغة SOAP', 'counseling_session', 'counseling_sessions', sid, current_date, case when risk in ('urgent','crisis') then 'urgent' else 'normal' end);
    exception when others then
      null;
    end;
  end if;

  perform public.counseling_log_access('session_create','counseling_sessions',sid,jsonb_build_object('case_id',c.id,'risk',risk));
  return jsonb_build_object('ok',true,'session_id',sid,'message','تم حفظ الجلسة');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.counseling_save_session(uuid,jsonb) to authenticated;

create or replace function public.counseling_save_goal(p_case_id uuid, p_goal jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c record;
  gid uuid;
begin
  select * into c from public.counseling_cases where id = p_case_id;
  if c.id is null then return jsonb_build_object('ok',false,'message','الحالة غير موجودة'); end if;
  if not (public.current_user_can_counseling() and (public.current_user_is_admin() or c.counselor_id=auth.uid() or c.counselor_id is null)) then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية إضافة هدف');
  end if;

  insert into public.counseling_goals(case_id,title,category,indicator,target_date,progress_percent,status,created_by)
  values(
    c.id,
    coalesce(nullif(p_goal->>'title',''),'هدف إرشادي'),
    coalesce(nullif(p_goal->>'category',''),'social_emotional'),
    nullif(p_goal->>'indicator',''),
    nullif(p_goal->>'target_date','')::date,
    greatest(0, least(100, coalesce((p_goal->>'progress_percent')::int,0))),
    coalesce(nullif(p_goal->>'status',''),'active'),
    auth.uid()
  ) returning id into gid;

  perform public.counseling_log_access('goal_create','counseling_goals',gid,jsonb_build_object('case_id',c.id));
  return jsonb_build_object('ok',true,'goal_id',gid,'message','تم حفظ الهدف');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.counseling_save_goal(uuid,jsonb) to authenticated;

create or replace function public.counseling_quick_referral(p_student_id uuid, p_urgency text, p_concern text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rid uuid;
  urgency text := case when p_urgency in ('stable','followup','medium','high','urgent','crisis') then p_urgency else 'followup' end;
begin
  if not public.current_user_can_create_referral() then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية إرسال إحالة');
  end if;

  insert into public.counseling_referrals(student_id,referred_by,urgency,concern,source,status)
  values(p_student_id, auth.uid(), urgency, coalesce(nullif(trim(p_concern),''),'إحالة للمتابعة النفسية'), 'school', 'pending')
  returning id into rid;

  return jsonb_build_object('ok',true,'referral_id',rid,'message','تم إرسال الإحالة للمرشد النفسي');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.counseling_quick_referral(uuid,text,text) to authenticated;

create or replace function public.counseling_handle_referral(p_referral_id uuid, p_action text default 'accepted', p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  case_id uuid;
  action text := case when p_action in ('accepted','deferred','rejected','closed') then p_action else 'accepted' end;
begin
  if not public.current_user_can_counseling() then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية معالجة الإحالات');
  end if;

  select * into r from public.counseling_referrals where id = p_referral_id;
  if r.id is null then return jsonb_build_object('ok',false,'message','الإحالة غير موجودة'); end if;

  update public.counseling_referrals
  set status=action, assigned_counselor_id=auth.uid(), counselor_note=p_note, handled_at=now(), updated_at=now()
  where id=r.id;

  if action = 'accepted' then
    insert into public.counseling_cases(student_id,counselor_id,risk_level,summary,intake_source,created_by)
    values(r.student_id, auth.uid(), r.urgency, r.concern, 'referral', auth.uid())
    on conflict (student_id) where status in ('active','watch') do update set
      counselor_id = coalesce(public.counseling_cases.counselor_id, auth.uid()),
      risk_level = excluded.risk_level,
      summary = coalesce(public.counseling_cases.summary, excluded.summary),
      updated_at=now()
    returning id into case_id;
  end if;

  perform public.counseling_log_access('referral_'||action,'counseling_referrals',r.id,jsonb_build_object('case_id',case_id));
  return jsonb_build_object('ok',true,'case_id',case_id,'message','تم تحديث الإحالة');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.counseling_handle_referral(uuid,text,text) to authenticated;

-- -------------------------------------------------------------
-- 6) صلاحية البوابة
-- -------------------------------------------------------------
create or replace function public.portal_default_permissions(p_role text, p_is_super_admin boolean default false)
returns text[]
language plpgsql
stable
as $$
declare
  r text := lower(coalesce(p_role,''));
begin
  if coalesce(p_is_super_admin,false) or r = 'admin' then
    return array[
      'admin','staff.dashboard','finance','academic','schedule','sections','grades','attendance','behavior','counseling','users','reports','registrations','system','calendar','achievements',
      'teacher','student','parent','homework','homework.reports','homework.audit','question_bank','online_exams','exam_integrity',
      'library','inventory','assets','hr','transport','labs','activities','notifications'
    ];
  end if;

  if r = 'finance' then
    return array['staff.dashboard','finance','reports','homework.reports','library','inventory','assets','achievements','notifications'];
  end if;

  if r in ('academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor') then
    return array['staff.dashboard','academic','schedule','sections','grades','attendance','behavior','reports','registrations','question_bank','online_exams','exam_integrity','homework.reports','library','transport','labs','activities','calendar','counseling','achievements','notifications'];
  end if;

  if r in ('discipline') then
    return array['staff.dashboard','attendance','behavior','students','reports','transport','homework.reports','calendar','counseling','achievements','notifications'];
  end if;

  if r in ('counselor','psychologist') then
    return array['staff.dashboard','counseling','behavior','students','attendance','reports','calendar','achievements','notifications'];
  end if;

  if r = 'teacher' then
    return array['teacher','attendance','homework','homework.reports','homework.audit','grades','question_bank','online_exams','library','transport','labs','activities','calendar','achievements','notifications'];
  end if;

  if r = 'student' then
    return array['student','homework','online_exams','grades','attendance','behavior','library','transport','activities','calendar','achievements','notifications'];
  end if;

  if r = 'parent' then
    return array['parent','student','homework','online_exams','grades','attendance','behavior','finance','library','transport','activities','calendar','achievements','notifications'];
  end if;

  if r in ('staff') then
    return array['staff.dashboard','attendance','students','reports','library','inventory','assets','transport','activities','calendar','achievements','notifications'];
  end if;

  if r in ('hr') then
    return array['staff.dashboard','hr','reports','achievements','notifications'];
  end if;

  if r in ('inventory','procurement') then
    return array['staff.dashboard','inventory','reports','achievements','notifications'];
  end if;

  if r in ('transport','transport_manager') then
    return array['staff.dashboard','transport','reports','achievements','notifications'];
  end if;

  if r in ('librarian') then
    return array['library','reports','achievements','notifications'];
  end if;

  return array['calendar','achievements','notifications'];
end;
$$;

grant execute on function public.portal_default_permissions(text,boolean) to authenticated;

-- -------------------------------------------------------------
-- 7) Health Check
-- -------------------------------------------------------------
create or replace function public.counseling_health_check()
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
    'tables', jsonb_build_object(
      'counseling_cases', to_regclass('public.counseling_cases') is not null,
      'counseling_sessions', to_regclass('public.counseling_sessions') is not null,
      'counseling_goals', to_regclass('public.counseling_goals') is not null,
      'counseling_assessments', to_regclass('public.counseling_assessments') is not null,
      'counseling_referrals', to_regclass('public.counseling_referrals') is not null,
      'counseling_access_logs', to_regclass('public.counseling_access_logs') is not null
    ),
    'functions', jsonb_build_object(
      'get_counselor_payload', to_regprocedure('public.get_counselor_payload()') is not null,
      'counseling_save_session', to_regprocedure('public.counseling_save_session(uuid,jsonb)') is not null,
      'counseling_upsert_case', to_regprocedure('public.counseling_upsert_case(uuid,text,text,text[])') is not null,
      'counseling_quick_referral', to_regprocedure('public.counseling_quick_referral(uuid,text,text)') is not null
    ),
    'stats', jsonb_build_object(
      'active_cases', (select count(*) from public.counseling_cases where status in ('active','watch')),
      'sessions', (select count(*) from public.counseling_sessions),
      'open_goals', (select count(*) from public.counseling_goals where status='active'),
      'pending_referrals', (select count(*) from public.counseling_referrals where status='pending'),
      'open_tasks', (select count(*) from public.counseling_tasks where status='open')
    ),
    'rls', jsonb_build_object(
      'cases', (select jsonb_build_object('enabled',c.relrowsecurity,'policies',(select count(*) from pg_policies where schemaname='public' and tablename='counseling_cases')) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='counseling_cases'),
      'sessions', (select jsonb_build_object('enabled',c.relrowsecurity,'policies',(select count(*) from pg_policies where schemaname='public' and tablename='counseling_sessions')) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='counseling_sessions')
    )
  );
end;
$$;

grant execute on function public.counseling_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.counseling_health_check() as counseling_health;

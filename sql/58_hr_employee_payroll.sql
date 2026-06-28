-- =============================================================
-- مدارس أمين الرضا (ع) — وحدة الموارد البشرية HR والرواتب
-- موظفون، ملفات وظيفية، حضور موظفين، إجازات، رواتب مبسطة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) صلاحيات
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

create or replace function public.hr_can_manage()
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
        and u.role in ('hr','staff','finance','academic','academic_admin','scientific','supervisor')
    );
$$;

grant execute on function public.hr_can_manage() to authenticated;

-- -------------------------------------------------------------
-- 1) Tables
-- -------------------------------------------------------------
create table if not exists public.hr_departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.hr_employee_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid null references public.users(id) on delete set null,
  employee_code text unique,
  full_name text not null,
  department_id uuid null references public.hr_departments(id) on delete set null,
  job_title text,
  employment_type text not null default 'full_time' check (employment_type in ('full_time','part_time','contract','temporary')),
  hire_date date,
  base_salary numeric not null default 0,
  phone text,
  address text,
  national_id text,
  status text not null default 'active' check (status in ('active','on_leave','suspended','terminated')),
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.hr_attendance (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.hr_employee_profiles(id) on delete cascade,
  work_date date not null default current_date,
  check_in time,
  check_out time,
  status text not null default 'present' check (status in ('present','absent','late','leave','mission','holiday')),
  notes text,
  recorded_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(employee_id, work_date)
);

create table if not exists public.hr_leave_requests (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.hr_employee_profiles(id) on delete cascade,
  leave_type text not null default 'annual' check (leave_type in ('annual','sick','unpaid','emergency','maternity','other')),
  start_date date not null,
  end_date date not null,
  days_count numeric not null default 1,
  reason text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  requested_by uuid null references public.users(id),
  approved_by uuid null references public.users(id),
  approved_at timestamptz,
  decision_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.hr_payroll_runs (
  id uuid primary key default gen_random_uuid(),
  payroll_year int not null,
  payroll_month int not null check (payroll_month between 1 and 12),
  title text not null,
  status text not null default 'draft' check (status in ('draft','approved','paid','cancelled')),
  generated_by uuid null references public.users(id),
  approved_by uuid null references public.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(payroll_year, payroll_month)
);

create table if not exists public.hr_payroll_items (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references public.hr_payroll_runs(id) on delete cascade,
  employee_id uuid not null references public.hr_employee_profiles(id) on delete cascade,
  base_salary numeric not null default 0,
  allowances numeric not null default 0,
  deductions numeric not null default 0,
  net_salary numeric not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(payroll_run_id, employee_id)
);

create index if not exists idx_hr_profiles_status_department on public.hr_employee_profiles(status, department_id);
create index if not exists idx_hr_attendance_date on public.hr_attendance(work_date, status);
create index if not exists idx_hr_leave_employee_status on public.hr_leave_requests(employee_id, status);
create index if not exists idx_hr_payroll_items_run on public.hr_payroll_items(payroll_run_id);

-- -------------------------------------------------------------
-- 2) RLS
-- -------------------------------------------------------------
alter table public.hr_departments enable row level security;
alter table public.hr_employee_profiles enable row level security;
alter table public.hr_attendance enable row level security;
alter table public.hr_leave_requests enable row level security;
alter table public.hr_payroll_runs enable row level security;
alter table public.hr_payroll_items enable row level security;

drop policy if exists hr_departments_manage on public.hr_departments;
drop policy if exists hr_profiles_read_write on public.hr_employee_profiles;
drop policy if exists hr_attendance_read_write on public.hr_attendance;
drop policy if exists hr_leave_read_write on public.hr_leave_requests;
drop policy if exists hr_payroll_runs_manage on public.hr_payroll_runs;
drop policy if exists hr_payroll_items_manage on public.hr_payroll_items;

create policy hr_departments_manage on public.hr_departments
  for all to authenticated
  using (public.hr_can_manage())
  with check (public.hr_can_manage());

create policy hr_profiles_read_write on public.hr_employee_profiles
  for all to authenticated
  using (public.hr_can_manage() or user_id = auth.uid())
  with check (public.hr_can_manage() or user_id = auth.uid());

create policy hr_attendance_read_write on public.hr_attendance
  for all to authenticated
  using (public.hr_can_manage() or exists(select 1 from public.hr_employee_profiles e where e.id=employee_id and e.user_id=auth.uid()))
  with check (public.hr_can_manage());

create policy hr_leave_read_write on public.hr_leave_requests
  for all to authenticated
  using (public.hr_can_manage() or exists(select 1 from public.hr_employee_profiles e where e.id=employee_id and e.user_id=auth.uid()))
  with check (public.hr_can_manage() or exists(select 1 from public.hr_employee_profiles e where e.id=employee_id and e.user_id=auth.uid()));

create policy hr_payroll_runs_manage on public.hr_payroll_runs
  for all to authenticated
  using (public.hr_can_manage())
  with check (public.hr_can_manage());

create policy hr_payroll_items_manage on public.hr_payroll_items
  for all to authenticated
  using (public.hr_can_manage() or exists(select 1 from public.hr_employee_profiles e where e.id=employee_id and e.user_id=auth.uid()))
  with check (public.hr_can_manage());

grant select, insert, update on public.hr_departments to authenticated;
grant select, insert, update on public.hr_employee_profiles to authenticated;
grant select, insert, update on public.hr_attendance to authenticated;
grant select, insert, update on public.hr_leave_requests to authenticated;
grant select, insert, update on public.hr_payroll_runs to authenticated;
grant select, insert, update on public.hr_payroll_items to authenticated;

-- -------------------------------------------------------------
-- 3) Views
-- -------------------------------------------------------------
create or replace view public.v_hr_employees
with (security_invoker=true) as
select
  e.id,
  e.user_id,
  u.email,
  u.role,
  e.employee_code,
  e.full_name,
  e.department_id,
  d.name as department_name,
  e.job_title,
  e.employment_type,
  e.hire_date,
  e.base_salary,
  e.phone,
  e.address,
  e.national_id,
  e.status,
  e.notes,
  coalesce(att.month_attendance_count,0) as month_attendance_count,
  coalesce(lv.pending_leave_count,0) as pending_leave_count,
  e.created_at,
  e.updated_at
from public.hr_employee_profiles e
left join public.users u on u.id = e.user_id
left join public.hr_departments d on d.id = e.department_id
left join lateral (
  select count(*) as month_attendance_count
  from public.hr_attendance a
  where a.employee_id = e.id
    and date_trunc('month', a.work_date::timestamp) = date_trunc('month', current_date::timestamp)
) att on true
left join lateral (
  select count(*) as pending_leave_count
  from public.hr_leave_requests l
  where l.employee_id = e.id
    and l.status='pending'
) lv on true
where public.hr_can_manage() or e.user_id = auth.uid();

grant select on public.v_hr_employees to authenticated;

create or replace view public.v_hr_leave_requests_detailed
with (security_invoker=true) as
select
  l.id,
  l.employee_id,
  e.full_name,
  e.employee_code,
  e.department_id,
  d.name as department_name,
  l.leave_type,
  l.start_date,
  l.end_date,
  l.days_count,
  l.reason,
  l.status,
  l.requested_by,
  rb.name as requested_by_name,
  l.approved_by,
  ab.name as approved_by_name,
  l.approved_at,
  l.decision_notes,
  l.created_at,
  l.updated_at
from public.hr_leave_requests l
join public.hr_employee_profiles e on e.id = l.employee_id
left join public.hr_departments d on d.id = e.department_id
left join public.users rb on rb.id = l.requested_by
left join public.users ab on ab.id = l.approved_by
where public.hr_can_manage() or e.user_id = auth.uid();

grant select on public.v_hr_leave_requests_detailed to authenticated;

create or replace view public.v_hr_payroll_detailed
with (security_invoker=true) as
select
  r.id as payroll_run_id,
  r.payroll_year,
  r.payroll_month,
  r.title,
  r.status as run_status,
  r.generated_by,
  gu.name as generated_by_name,
  r.approved_by,
  au.name as approved_by_name,
  r.approved_at,
  i.id as payroll_item_id,
  i.employee_id,
  e.full_name,
  e.employee_code,
  d.name as department_name,
  i.base_salary,
  i.allowances,
  i.deductions,
  i.net_salary,
  i.notes,
  r.created_at,
  r.updated_at
from public.hr_payroll_runs r
left join public.users gu on gu.id = r.generated_by
left join public.users au on au.id = r.approved_by
left join public.hr_payroll_items i on i.payroll_run_id = r.id
left join public.hr_employee_profiles e on e.id = i.employee_id
left join public.hr_departments d on d.id = e.department_id
where public.hr_can_manage() or e.user_id = auth.uid();

grant select on public.v_hr_payroll_detailed to authenticated;

-- -------------------------------------------------------------
-- 4) Functions
-- -------------------------------------------------------------
create or replace function public.hr_seed_defaults()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted int := 0;
begin
  if not public.hr_can_manage() and auth.uid() is not null then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تهيئة HR');
  end if;

  insert into public.hr_departments(name, description)
  values
    ('الإدارة', 'إدارة وتشغيل المدرسة'),
    ('التعليم', 'المعلمون والشؤون الأكاديمية'),
    ('المالية', 'المالية والمحاسبة'),
    ('الخدمات', 'الخدمات والصيانة')
  on conflict (name) do nothing;

  get diagnostics inserted = row_count;

  return jsonb_build_object('ok', true, 'message', 'تمت تهيئة أقسام HR', 'inserted_departments', inserted);
end;
$$;

grant execute on function public.hr_seed_defaults() to authenticated;

create or replace function public.hr_upsert_employee(
  p_employee_id uuid default null,
  p_user_id uuid default null,
  p_full_name text default null,
  p_department text default null,
  p_job_title text default null,
  p_base_salary numeric default 0,
  p_phone text default null,
  p_status text default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  dept_id uuid;
  emp_id uuid;
  code text;
begin
  if not public.hr_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدارة الموظفين');
  end if;

  if nullif(trim(coalesce(p_full_name,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'اسم الموظف مطلوب');
  end if;

  if nullif(trim(coalesce(p_department,'')), '') is not null then
    insert into public.hr_departments(name)
    values (trim(p_department))
    on conflict (name) do update set name=excluded.name
    returning id into dept_id;
  end if;

  if p_employee_id is not null then
    update public.hr_employee_profiles
    set user_id=p_user_id,
        full_name=trim(p_full_name),
        department_id=dept_id,
        job_title=p_job_title,
        base_salary=coalesce(p_base_salary,0),
        phone=p_phone,
        status=case when p_status in ('active','on_leave','suspended','terminated') then p_status else 'active' end,
        updated_at=now()
    where id=p_employee_id
    returning id into emp_id;
  else
    code := 'EMP-' || to_char(now(),'YYYYMMDD-HH24MISS') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,4);
    insert into public.hr_employee_profiles(user_id, employee_code, full_name, department_id, job_title, base_salary, phone, status, created_by)
    values (p_user_id, code, trim(p_full_name), dept_id, p_job_title, coalesce(p_base_salary,0), p_phone, case when p_status in ('active','on_leave','suspended','terminated') then p_status else 'active' end, auth.uid())
    returning id into emp_id;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ الموظف', 'employee_id', emp_id);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.hr_upsert_employee(uuid,uuid,text,text,text,numeric,text,text) to authenticated;

create or replace function public.hr_record_attendance(
  p_employee_id uuid,
  p_work_date date default current_date,
  p_status text default 'present',
  p_check_in time default null,
  p_check_out time default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  att_id uuid;
begin
  if not public.hr_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تسجيل حضور الموظفين');
  end if;

  if p_status not in ('present','absent','late','leave','mission','holiday') then p_status := 'present'; end if;

  update public.hr_attendance
  set status=p_status, check_in=p_check_in, check_out=p_check_out, notes=p_notes, recorded_by=auth.uid(), updated_at=now()
  where employee_id=p_employee_id and work_date=coalesce(p_work_date,current_date)
  returning id into att_id;

  if att_id is null then
    insert into public.hr_attendance(employee_id, work_date, status, check_in, check_out, notes, recorded_by)
    values (p_employee_id, coalesce(p_work_date,current_date), p_status, p_check_in, p_check_out, p_notes, auth.uid())
    returning id into att_id;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ حضور الموظف', 'attendance_id', att_id);
end;
$$;

grant execute on function public.hr_record_attendance(uuid,date,text,time,time,text) to authenticated;

create or replace function public.hr_request_leave(
  p_employee_id uuid,
  p_leave_type text,
  p_start_date date,
  p_end_date date,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  e record;
  leave_id uuid;
  days numeric;
begin
  select * into e from public.hr_employee_profiles where id=p_employee_id;
  if e.id is null then return jsonb_build_object('ok', false, 'message', 'الموظف غير موجود'); end if;

  if not (public.hr_can_manage() or e.user_id = auth.uid()) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية طلب إجازة لهذا الموظف');
  end if;

  if p_end_date < p_start_date then
    return jsonb_build_object('ok', false, 'message', 'تاريخ النهاية قبل البداية');
  end if;

  if p_leave_type not in ('annual','sick','unpaid','emergency','maternity','other') then p_leave_type := 'annual'; end if;
  days := (p_end_date - p_start_date) + 1;

  insert into public.hr_leave_requests(employee_id, leave_type, start_date, end_date, days_count, reason, requested_by)
  values (p_employee_id, p_leave_type, p_start_date, p_end_date, days, p_reason, auth.uid())
  returning id into leave_id;

  return jsonb_build_object('ok', true, 'message', 'تم إرسال طلب الإجازة', 'leave_id', leave_id);
end;
$$;

grant execute on function public.hr_request_leave(uuid,text,date,date,text) to authenticated;

create or replace function public.hr_set_leave_status(
  p_leave_id uuid,
  p_status text,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  l record;
begin
  if not public.hr_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية اعتماد الإجازات');
  end if;

  select * into l from public.hr_leave_requests where id=p_leave_id;
  if l.id is null then return jsonb_build_object('ok', false, 'message', 'طلب الإجازة غير موجود'); end if;

  if p_status not in ('pending','approved','rejected','cancelled') then p_status := 'pending'; end if;

  update public.hr_leave_requests
  set status=p_status,
      approved_by=case when p_status in ('approved','rejected') then auth.uid() else approved_by end,
      approved_at=case when p_status in ('approved','rejected') then now() else approved_at end,
      decision_notes=p_notes,
      updated_at=now()
  where id=p_leave_id;

  update public.hr_employee_profiles
  set status=case when p_status='approved' then 'on_leave' else status end,
      updated_at=now()
  where id=l.employee_id;

  return jsonb_build_object('ok', true, 'message', 'تم تحديث طلب الإجازة', 'status', p_status);
end;
$$;

grant execute on function public.hr_set_leave_status(uuid,text,text) to authenticated;

create or replace function public.hr_generate_payroll(
  p_year int,
  p_month int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  run_id uuid;
  e record;
  inserted int := 0;
  title_text text;
  leave_days numeric;
  deduction numeric;
begin
  if not public.hr_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية توليد الرواتب');
  end if;

  if p_month < 1 or p_month > 12 then
    return jsonb_build_object('ok', false, 'message', 'الشهر غير صحيح');
  end if;

  title_text := 'رواتب ' || p_month || '/' || p_year;

  select id into run_id from public.hr_payroll_runs where payroll_year=p_year and payroll_month=p_month;
  if run_id is null then
    insert into public.hr_payroll_runs(payroll_year, payroll_month, title, generated_by)
    values (p_year, p_month, title_text, auth.uid())
    returning id into run_id;
  end if;

  for e in select * from public.hr_employee_profiles where status in ('active','on_leave') loop
    select coalesce(sum(days_count),0) into leave_days
    from public.hr_leave_requests
    where employee_id=e.id
      and status='approved'
      and leave_type='unpaid'
      and extract(year from start_date)=p_year
      and extract(month from start_date)=p_month;

    deduction := round(coalesce(e.base_salary,0) / 30 * coalesce(leave_days,0), 2);

    update public.hr_payroll_items
    set base_salary=e.base_salary,
        deductions=deduction,
        net_salary=coalesce(e.base_salary,0)-deduction,
        updated_at=now()
    where payroll_run_id=run_id and employee_id=e.id;

    if not found then
      insert into public.hr_payroll_items(payroll_run_id, employee_id, base_salary, deductions, net_salary, notes)
      values (run_id, e.id, coalesce(e.base_salary,0), deduction, coalesce(e.base_salary,0)-deduction, case when deduction>0 then 'خصم إجازة غير مدفوعة' else null end);
      inserted := inserted + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'message', 'تم توليد الرواتب', 'payroll_run_id', run_id, 'inserted_items', inserted);
end;
$$;

grant execute on function public.hr_generate_payroll(int,int) to authenticated;

create or replace function public.hr_set_payroll_status(
  p_run_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.hr_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية الرواتب');
  end if;
  if p_status not in ('draft','approved','paid','cancelled') then p_status := 'draft'; end if;

  update public.hr_payroll_runs
  set status=p_status,
      approved_by=case when p_status='approved' then auth.uid() else approved_by end,
      approved_at=case when p_status='approved' then now() else approved_at end,
      updated_at=now()
  where id=p_run_id;

  return jsonb_build_object('ok', true, 'message', 'تم تحديث حالة الرواتب', 'status', p_status);
end;
$$;

grant execute on function public.hr_set_payroll_status(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 5) Dashboard + Health
-- -------------------------------------------------------------
create or replace function public.get_hr_dashboard_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if not public.hr_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية عرض HR');
  end if;

  return jsonb_build_object(
    'ok', true,
    'stats', jsonb_build_object(
      'employees', (select count(*) from public.hr_employee_profiles),
      'active', (select count(*) from public.hr_employee_profiles where status='active'),
      'on_leave', (select count(*) from public.hr_employee_profiles where status='on_leave'),
      'pending_leaves', (select count(*) from public.hr_leave_requests where status='pending'),
      'attendance_today', (select count(*) from public.hr_attendance where work_date=current_date),
      'payroll_runs', (select count(*) from public.hr_payroll_runs)
    ),
    'recent_leaves', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from public.v_hr_leave_requests_detailed order by created_at desc limit 10) x), '[]'::jsonb),
    'recent_payroll', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select payroll_run_id, payroll_year, payroll_month, title, run_status, sum(net_salary) as total_net from public.v_hr_payroll_detailed group by payroll_run_id, payroll_year, payroll_month, title, run_status, created_at order by created_at desc limit 8) x), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_hr_dashboard_payload() to authenticated;

create or replace function public.hr_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'departments', to_regclass('public.hr_departments') is not null,
    'employees', to_regclass('public.hr_employee_profiles') is not null,
    'attendance', to_regclass('public.hr_attendance') is not null,
    'leaves', to_regclass('public.hr_leave_requests') is not null,
    'payroll_runs', to_regclass('public.hr_payroll_runs') is not null,
    'payroll_items', to_regclass('public.hr_payroll_items') is not null,
    'employees_view', to_regclass('public.v_hr_employees') is not null,
    'leaves_view', to_regclass('public.v_hr_leave_requests_detailed') is not null,
    'payroll_view', to_regclass('public.v_hr_payroll_detailed') is not null,
    'dashboard_rpc', to_regprocedure('public.get_hr_dashboard_payload()') is not null,
    'upsert_employee_rpc', to_regprocedure('public.hr_upsert_employee(uuid,uuid,text,text,text,numeric,text,text)') is not null,
    'attendance_rpc', to_regprocedure('public.hr_record_attendance(uuid,date,text,time,time,text)') is not null,
    'leave_rpc', to_regprocedure('public.hr_request_leave(uuid,text,date,date,text)') is not null,
    'payroll_rpc', to_regprocedure('public.hr_generate_payroll(int,int)') is not null,
    'stats', case when public.hr_can_manage() then public.get_hr_dashboard_payload()->'stats' else '{}'::jsonb end
  );
end;
$$;

grant execute on function public.hr_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'hr_employee_payroll_ready' as status;

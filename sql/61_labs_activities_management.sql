-- =============================================================
-- مدارس أمين الرضا (ع) — وحدة المختبرات والأنشطة المدرسية
-- مختبرات، تجهيزات، تجارب، حوادث سلامة، أنشطة، تسجيل الطلاب، حضور النشاط.
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

create or replace function public.labs_activities_can_manage()
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
        and u.role in ('teacher','academic','academic_admin','scientific','supervisor','staff','activity_manager','lab_manager','discipline')
    );
$$;

grant execute on function public.labs_activities_can_manage() to authenticated;

create or replace function public.current_student_id_for_activities()
returns uuid
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  sid uuid;
begin
  select s.id into sid from public.students s where s.user_id = auth.uid() limit 1;
  if sid is null then
    select s.id into sid from public.students s where s.parent_id = auth.uid() order by s.name limit 1;
  end if;
  return sid;
end;
$$;

grant execute on function public.current_student_id_for_activities() to authenticated;

-- -------------------------------------------------------------
-- 1) الجداول
-- -------------------------------------------------------------
create table if not exists public.lab_rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  location text,
  capacity int not null default 24,
  supervisor_id uuid null references public.users(id) on delete set null,
  status text not null default 'active' check (status in ('active','maintenance','inactive')),
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lab_equipment (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid null references public.lab_rooms(id) on delete set null,
  name text not null,
  serial_no text,
  quantity numeric not null default 1,
  unit text not null default 'قطعة',
  status text not null default 'available' check (status in ('available','in_use','maintenance','damaged','lost')),
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lab_experiments (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  lab_id uuid null references public.lab_rooms(id) on delete set null,
  class_id uuid null references public.classes(id) on delete set null,
  section_id uuid null references public.sections(id) on delete set null,
  subject_id uuid null references public.subjects(id) on delete set null,
  teacher_id uuid null references public.users(id) on delete set null,
  scheduled_at timestamptz,
  duration_minutes int not null default 45,
  status text not null default 'planned' check (status in ('planned','in_progress','completed','cancelled')),
  objectives text,
  materials text,
  safety_notes text,
  result_notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lab_incidents (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid null references public.lab_rooms(id) on delete set null,
  experiment_id uuid null references public.lab_experiments(id) on delete set null,
  title text not null,
  description text,
  severity text not null default 'low' check (severity in ('low','medium','high','critical')),
  status text not null default 'open' check (status in ('open','reviewing','closed','cancelled')),
  reported_by uuid null references public.users(id) on delete set null,
  resolved_by uuid null references public.users(id) on delete set null,
  resolved_at timestamptz,
  resolution_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.activity_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.school_activities (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category_id uuid null references public.activity_categories(id) on delete set null,
  description text,
  organizer_id uuid null references public.users(id) on delete set null,
  location text,
  start_at timestamptz,
  end_at timestamptz,
  max_participants int,
  status text not null default 'draft' check (status in ('draft','published','closed','archived','cancelled')),
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.activity_participants (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.school_activities(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  status text not null default 'registered' check (status in ('registered','approved','waitlisted','rejected','cancelled')),
  attendance_status text not null default 'not_marked' check (attendance_status in ('not_marked','present','absent','excused')),
  registered_at timestamptz not null default now(),
  approved_by uuid null references public.users(id),
  approved_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(activity_id, student_id)
);

create index if not exists idx_lab_rooms_status on public.lab_rooms(status);
create index if not exists idx_lab_equipment_lab_status on public.lab_equipment(lab_id, status);
create index if not exists idx_lab_experiments_schedule on public.lab_experiments(scheduled_at, status);
create index if not exists idx_lab_incidents_status on public.lab_incidents(status, severity);
create index if not exists idx_school_activities_status_start on public.school_activities(status, start_at);
create index if not exists idx_activity_participants_activity on public.activity_participants(activity_id, status);

-- -------------------------------------------------------------
-- 2) RLS
-- -------------------------------------------------------------
alter table public.lab_rooms enable row level security;
alter table public.lab_equipment enable row level security;
alter table public.lab_experiments enable row level security;
alter table public.lab_incidents enable row level security;
alter table public.activity_categories enable row level security;
alter table public.school_activities enable row level security;
alter table public.activity_participants enable row level security;

drop policy if exists lab_rooms_manage on public.lab_rooms;
drop policy if exists lab_equipment_manage on public.lab_equipment;
drop policy if exists lab_experiments_manage on public.lab_experiments;
drop policy if exists lab_incidents_manage on public.lab_incidents;
drop policy if exists activity_categories_manage on public.activity_categories;
drop policy if exists school_activities_read_write on public.school_activities;
drop policy if exists activity_participants_scoped on public.activity_participants;

create policy lab_rooms_manage on public.lab_rooms
  for all to authenticated
  using (public.labs_activities_can_manage())
  with check (public.labs_activities_can_manage());

create policy lab_equipment_manage on public.lab_equipment
  for all to authenticated
  using (public.labs_activities_can_manage())
  with check (public.labs_activities_can_manage());

create policy lab_experiments_manage on public.lab_experiments
  for all to authenticated
  using (public.labs_activities_can_manage() or teacher_id = auth.uid())
  with check (public.labs_activities_can_manage() or teacher_id = auth.uid());

create policy lab_incidents_manage on public.lab_incidents
  for all to authenticated
  using (public.labs_activities_can_manage() or reported_by = auth.uid())
  with check (public.labs_activities_can_manage() or reported_by = auth.uid());

create policy activity_categories_manage on public.activity_categories
  for all to authenticated
  using (public.labs_activities_can_manage())
  with check (public.labs_activities_can_manage());

create policy school_activities_read_write on public.school_activities
  for all to authenticated
  using (public.labs_activities_can_manage() or status='published' or organizer_id=auth.uid())
  with check (public.labs_activities_can_manage() or organizer_id=auth.uid());

create policy activity_participants_scoped on public.activity_participants
  for all to authenticated
  using (
    public.labs_activities_can_manage()
    or exists(select 1 from public.students s where s.id=student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid()))
    or exists(select 1 from public.school_activities a where a.id=activity_id and a.organizer_id=auth.uid())
  )
  with check (
    public.labs_activities_can_manage()
    or exists(select 1 from public.students s where s.id=student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid()))
    or exists(select 1 from public.school_activities a where a.id=activity_id and a.organizer_id=auth.uid())
  );

grant select, insert, update on public.lab_rooms to authenticated;
grant select, insert, update on public.lab_equipment to authenticated;
grant select, insert, update on public.lab_experiments to authenticated;
grant select, insert, update on public.lab_incidents to authenticated;
grant select, insert, update on public.activity_categories to authenticated;
grant select, insert, update on public.school_activities to authenticated;
grant select, insert, update on public.activity_participants to authenticated;

-- -------------------------------------------------------------
-- 3) Views
-- -------------------------------------------------------------
create or replace view public.v_lab_rooms_status
with (security_invoker=true) as
select
  r.id as lab_id,
  r.name,
  r.location,
  r.capacity,
  r.supervisor_id,
  u.name as supervisor_name,
  r.status,
  r.notes,
  count(e.id) as equipment_count,
  count(e.id) filter (where e.status='available') as available_equipment,
  count(x.id) filter (where x.status in ('planned','in_progress') and x.scheduled_at >= now() - interval '1 day') as active_experiments,
  count(i.id) filter (where i.status in ('open','reviewing')) as open_incidents,
  r.created_at,
  r.updated_at
from public.lab_rooms r
left join public.users u on u.id = r.supervisor_id
left join public.lab_equipment e on e.lab_id = r.id
left join public.lab_experiments x on x.lab_id = r.id
left join public.lab_incidents i on i.lab_id = r.id
group by r.id, u.name;

grant select on public.v_lab_rooms_status to authenticated;

create or replace view public.v_lab_experiments_detailed
with (security_invoker=true) as
select
  e.id as experiment_id,
  e.title,
  e.lab_id,
  l.name as lab_name,
  e.class_id,
  c.name as class_name,
  e.section_id,
  sec.code as section_code,
  e.subject_id,
  sub.name as subject_name,
  e.teacher_id,
  u.name as teacher_name,
  e.scheduled_at,
  e.duration_minutes,
  e.status,
  e.objectives,
  e.materials,
  e.safety_notes,
  e.result_notes,
  e.created_by,
  e.created_at,
  e.updated_at
from public.lab_experiments e
left join public.lab_rooms l on l.id = e.lab_id
left join public.classes c on c.id = e.class_id
left join public.sections sec on sec.id = e.section_id
left join public.subjects sub on sub.id = e.subject_id
left join public.users u on u.id = e.teacher_id
where public.labs_activities_can_manage() or e.teacher_id = auth.uid();

grant select on public.v_lab_experiments_detailed to authenticated;

create or replace view public.v_lab_incidents_detailed
with (security_invoker=true) as
select
  i.id as incident_id,
  i.lab_id,
  l.name as lab_name,
  i.experiment_id,
  e.title as experiment_title,
  i.title,
  i.description,
  i.severity,
  i.status,
  i.reported_by,
  ru.name as reported_by_name,
  i.resolved_by,
  su.name as resolved_by_name,
  i.resolved_at,
  i.resolution_notes,
  i.created_at,
  i.updated_at
from public.lab_incidents i
left join public.lab_rooms l on l.id = i.lab_id
left join public.lab_experiments e on e.id = i.experiment_id
left join public.users ru on ru.id = i.reported_by
left join public.users su on su.id = i.resolved_by
where public.labs_activities_can_manage() or i.reported_by = auth.uid();

grant select on public.v_lab_incidents_detailed to authenticated;

create or replace view public.v_school_activities_detailed
with (security_invoker=true) as
select
  a.id as activity_id,
  a.title,
  a.category_id,
  cat.name as category_name,
  a.description,
  a.organizer_id,
  u.name as organizer_name,
  a.location,
  a.start_at,
  a.end_at,
  a.max_participants,
  a.status,
  count(p.id) as participants_count,
  count(p.id) filter (where p.status in ('registered','approved')) as active_participants,
  count(p.id) filter (where p.attendance_status='present') as present_count,
  a.created_by,
  a.created_at,
  a.updated_at
from public.school_activities a
left join public.activity_categories cat on cat.id = a.category_id
left join public.users u on u.id = a.organizer_id
left join public.activity_participants p on p.activity_id = a.id
where public.labs_activities_can_manage() or a.status='published' or a.organizer_id=auth.uid()
group by a.id, cat.name, u.name;

grant select on public.v_school_activities_detailed to authenticated;

create or replace view public.v_activity_participants_detailed
with (security_invoker=true) as
select
  p.id as participant_id,
  p.activity_id,
  a.title as activity_title,
  a.organizer_id,
  p.student_id,
  s.name as student_name,
  s.class_id,
  c.name as class_name,
  s.section_id,
  sec.code as section_code,
  p.status,
  p.attendance_status,
  p.registered_at,
  p.approved_by,
  au.name as approved_by_name,
  p.approved_at,
  p.notes,
  p.created_at,
  p.updated_at
from public.activity_participants p
join public.school_activities a on a.id = p.activity_id
join public.students s on s.id = p.student_id
left join public.classes c on c.id = s.class_id
left join public.sections sec on sec.id = s.section_id
left join public.users au on au.id = p.approved_by
where public.labs_activities_can_manage()
   or a.organizer_id = auth.uid()
   or s.user_id = auth.uid()
   or s.parent_id = auth.uid();

grant select on public.v_activity_participants_detailed to authenticated;

-- -------------------------------------------------------------
-- 4) Functions
-- -------------------------------------------------------------
create or replace function public.lab_activity_seed_defaults()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  lab_id uuid;
  cat_sport uuid;
  cat_culture uuid;
  inserted_equipment int := 0;
begin
  if not public.labs_activities_can_manage() and auth.uid() is not null then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية التهيئة');
  end if;

  insert into public.lab_rooms(name, location, capacity, supervisor_id, created_by)
  values ('مختبر العلوم الرئيسي', 'الطابق الأول', 24, auth.uid(), auth.uid())
  returning id into lab_id;

  insert into public.lab_equipment(lab_id, name, quantity, unit, created_by)
  values
    (lab_id, 'مجهر تعليمي', 8, 'قطعة', auth.uid()),
    (lab_id, 'أدوات قياس', 12, 'طقم', auth.uid()),
    (lab_id, 'نظارات سلامة', 24, 'قطعة', auth.uid());
  get diagnostics inserted_equipment = row_count;

  insert into public.activity_categories(name, description)
  values ('رياضة', 'أنشطة رياضية'), ('ثقافة', 'أنشطة ثقافية ومسابقات')
  on conflict (name) do nothing;

  select id into cat_sport from public.activity_categories where name='رياضة';
  select id into cat_culture from public.activity_categories where name='ثقافة';

  insert into public.school_activities(title, category_id, description, organizer_id, location, start_at, end_at, max_participants, status, created_by)
  values
    ('نادي كرة القدم', cat_sport, 'تدريب أسبوعي للطلاب', auth.uid(), 'الساحة', now()+interval '7 days', now()+interval '7 days 2 hours', 30, 'published', auth.uid()),
    ('مسابقة القراءة', cat_culture, 'مسابقة قراءة شهرية', auth.uid(), 'المكتبة', now()+interval '10 days', now()+interval '10 days 2 hours', 40, 'published', auth.uid());

  return jsonb_build_object('ok', true, 'message', 'تمت تهيئة المختبرات والأنشطة', 'lab_id', lab_id, 'equipment', inserted_equipment);
end;
$$;

grant execute on function public.lab_activity_seed_defaults() to authenticated;

create or replace function public.lab_upsert_room(
  p_lab_id uuid default null,
  p_name text default null,
  p_location text default null,
  p_capacity int default 24,
  p_status text default 'active',
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rid uuid;
begin
  if not public.labs_activities_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدارة المختبرات');
  end if;

  if nullif(trim(coalesce(p_name,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'اسم المختبر مطلوب');
  end if;

  if p_status not in ('active','maintenance','inactive') then p_status := 'active'; end if;

  if p_lab_id is not null then
    update public.lab_rooms set name=trim(p_name), location=p_location, capacity=coalesce(p_capacity,24), status=p_status, notes=p_notes, updated_at=now()
    where id=p_lab_id returning id into rid;
  else
    insert into public.lab_rooms(name, location, capacity, status, notes, supervisor_id, created_by)
    values (trim(p_name), p_location, coalesce(p_capacity,24), p_status, p_notes, auth.uid(), auth.uid())
    returning id into rid;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ المختبر', 'lab_id', rid);
end;
$$;

grant execute on function public.lab_upsert_room(uuid,text,text,int,text,text) to authenticated;

create or replace function public.lab_add_equipment(
  p_lab_id uuid,
  p_name text,
  p_quantity numeric default 1,
  p_unit text default 'قطعة'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  eid uuid;
begin
  if not public.labs_activities_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدارة التجهيزات');
  end if;
  if nullif(trim(coalesce(p_name,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'اسم التجهيز مطلوب');
  end if;

  insert into public.lab_equipment(lab_id, name, quantity, unit, created_by)
  values (p_lab_id, trim(p_name), coalesce(p_quantity,1), coalesce(nullif(trim(p_unit),''),'قطعة'), auth.uid())
  returning id into eid;

  return jsonb_build_object('ok', true, 'message', 'تمت إضافة التجهيز', 'equipment_id', eid);
end;
$$;

grant execute on function public.lab_add_equipment(uuid,text,numeric,text) to authenticated;

create or replace function public.lab_schedule_experiment(
  p_experiment_id uuid default null,
  p_title text default null,
  p_lab_id uuid default null,
  p_class_id uuid default null,
  p_section_id uuid default null,
  p_subject_id uuid default null,
  p_scheduled_at timestamptz default null,
  p_duration_minutes int default 45,
  p_objectives text default null,
  p_materials text default null,
  p_safety_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  eid uuid;
begin
  if not public.labs_activities_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية جدولة التجارب');
  end if;
  if nullif(trim(coalesce(p_title,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'عنوان التجربة مطلوب');
  end if;

  if p_experiment_id is not null then
    update public.lab_experiments
    set title=trim(p_title), lab_id=p_lab_id, class_id=p_class_id, section_id=p_section_id, subject_id=p_subject_id, teacher_id=auth.uid(), scheduled_at=p_scheduled_at, duration_minutes=coalesce(p_duration_minutes,45), objectives=p_objectives, materials=p_materials, safety_notes=p_safety_notes, updated_at=now()
    where id=p_experiment_id
    returning id into eid;
  else
    insert into public.lab_experiments(title, lab_id, class_id, section_id, subject_id, teacher_id, scheduled_at, duration_minutes, objectives, materials, safety_notes, created_by)
    values (trim(p_title), p_lab_id, p_class_id, p_section_id, p_subject_id, auth.uid(), p_scheduled_at, coalesce(p_duration_minutes,45), p_objectives, p_materials, p_safety_notes, auth.uid())
    returning id into eid;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ التجربة', 'experiment_id', eid);
end;
$$;

grant execute on function public.lab_schedule_experiment(uuid,text,uuid,uuid,uuid,uuid,timestamptz,int,text,text,text) to authenticated;

create or replace function public.lab_set_experiment_status(
  p_experiment_id uuid,
  p_status text,
  p_result_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.labs_activities_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل حالة التجربة');
  end if;
  if p_status not in ('planned','in_progress','completed','cancelled') then p_status := 'planned'; end if;

  update public.lab_experiments set status=p_status, result_notes=coalesce(p_result_notes,result_notes), updated_at=now() where id=p_experiment_id;
  return jsonb_build_object('ok', true, 'message', 'تم تحديث حالة التجربة', 'status', p_status);
end;
$$;

grant execute on function public.lab_set_experiment_status(uuid,text,text) to authenticated;

create or replace function public.lab_report_incident(
  p_lab_id uuid,
  p_experiment_id uuid default null,
  p_title text default null,
  p_description text default null,
  p_severity text default 'low'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  iid uuid;
begin
  if not public.labs_activities_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تسجيل حادث مختبر');
  end if;
  if nullif(trim(coalesce(p_title,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'عنوان الحادث مطلوب');
  end if;
  if p_severity not in ('low','medium','high','critical') then p_severity := 'low'; end if;

  insert into public.lab_incidents(lab_id, experiment_id, title, description, severity, reported_by)
  values (p_lab_id, p_experiment_id, trim(p_title), p_description, p_severity, auth.uid())
  returning id into iid;

  return jsonb_build_object('ok', true, 'message', 'تم تسجيل حادث المختبر', 'incident_id', iid);
end;
$$;

grant execute on function public.lab_report_incident(uuid,uuid,text,text,text) to authenticated;

create or replace function public.activity_upsert(
  p_activity_id uuid default null,
  p_title text default null,
  p_category text default null,
  p_description text default null,
  p_location text default null,
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_max_participants int default null,
  p_status text default 'published'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cat_id uuid;
  aid uuid;
begin
  if not public.labs_activities_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدارة الأنشطة');
  end if;
  if nullif(trim(coalesce(p_title,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'عنوان النشاط مطلوب');
  end if;
  if p_status not in ('draft','published','closed','archived','cancelled') then p_status := 'published'; end if;

  if nullif(trim(coalesce(p_category,'')), '') is not null then
    insert into public.activity_categories(name)
    values (trim(p_category))
    on conflict (name) do update set name=excluded.name
    returning id into cat_id;
  end if;

  if p_activity_id is not null then
    update public.school_activities
    set title=trim(p_title), category_id=cat_id, description=p_description, location=p_location, start_at=p_start_at, end_at=p_end_at, max_participants=p_max_participants, status=p_status, organizer_id=auth.uid(), updated_at=now()
    where id=p_activity_id returning id into aid;
  else
    insert into public.school_activities(title, category_id, description, organizer_id, location, start_at, end_at, max_participants, status, created_by)
    values (trim(p_title), cat_id, p_description, auth.uid(), p_location, p_start_at, p_end_at, p_max_participants, p_status, auth.uid())
    returning id into aid;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ النشاط', 'activity_id', aid);
end;
$$;

grant execute on function public.activity_upsert(uuid,text,text,text,text,timestamptz,timestamptz,int,text) to authenticated;

create or replace function public.activity_register_student(
  p_activity_id uuid,
  p_student_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
  sid uuid;
  cnt int;
  pid uuid;
  st_status text := 'registered';
begin
  select * into a from public.school_activities where id=p_activity_id;
  if a.id is null then return jsonb_build_object('ok', false, 'message', 'النشاط غير موجود'); end if;
  if a.status <> 'published' then return jsonb_build_object('ok', false, 'message', 'التسجيل غير متاح لهذا النشاط'); end if;

  sid := coalesce(p_student_id, public.current_student_id_for_activities());
  if sid is null then return jsonb_build_object('ok', false, 'message', 'لا يوجد طالب مرتبط بالحساب'); end if;

  if not (public.labs_activities_can_manage() or exists(select 1 from public.students s where s.id=sid and (s.user_id=auth.uid() or s.parent_id=auth.uid()))) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تسجيل هذا الطالب');
  end if;

  select count(*) into cnt from public.activity_participants where activity_id=p_activity_id and status in ('registered','approved');
  if a.max_participants is not null and cnt >= a.max_participants then
    st_status := 'waitlisted';
  end if;

  update public.activity_participants
  set status=st_status, updated_at=now()
  where activity_id=p_activity_id and student_id=sid
  returning id into pid;

  if pid is null then
    insert into public.activity_participants(activity_id, student_id, status)
    values (p_activity_id, sid, st_status)
    returning id into pid;
  end if;

  return jsonb_build_object('ok', true, 'message', case when st_status='waitlisted' then 'تم وضع الطالب على قائمة الانتظار' else 'تم تسجيل الطالب في النشاط' end, 'participant_id', pid, 'status', st_status);
end;
$$;

grant execute on function public.activity_register_student(uuid,uuid) to authenticated;

create or replace function public.activity_set_participation_status(
  p_participant_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.labs_activities_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تحديث المشاركات');
  end if;
  if p_status not in ('registered','approved','waitlisted','rejected','cancelled') then p_status := 'registered'; end if;

  update public.activity_participants
  set status=p_status,
      approved_by=case when p_status='approved' then auth.uid() else approved_by end,
      approved_at=case when p_status='approved' then now() else approved_at end,
      updated_at=now()
  where id=p_participant_id;

  return jsonb_build_object('ok', true, 'message', 'تم تحديث حالة المشاركة', 'status', p_status);
end;
$$;

grant execute on function public.activity_set_participation_status(uuid,text) to authenticated;

create or replace function public.activity_mark_attendance(
  p_participant_id uuid,
  p_attendance_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.labs_activities_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تحضير النشاط');
  end if;
  if p_attendance_status not in ('not_marked','present','absent','excused') then p_attendance_status := 'not_marked'; end if;

  update public.activity_participants
  set attendance_status=p_attendance_status, updated_at=now()
  where id=p_participant_id;

  return jsonb_build_object('ok', true, 'message', 'تم تحديث حضور النشاط', 'attendance_status', p_attendance_status);
end;
$$;

grant execute on function public.activity_mark_attendance(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 5) Dashboard + Health
-- -------------------------------------------------------------
create or replace function public.get_labs_activities_dashboard_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'stats', jsonb_build_object(
      'labs', (select count(*) from public.lab_rooms where status='active'),
      'equipment', (select count(*) from public.lab_equipment),
      'experiments_planned', (select count(*) from public.lab_experiments where status in ('planned','in_progress')),
      'incidents_open', (select count(*) from public.lab_incidents where status in ('open','reviewing')),
      'activities_published', (select count(*) from public.school_activities where status='published'),
      'activity_participants', (select count(*) from public.activity_participants where status in ('registered','approved'))
    ),
    'upcoming_experiments', coalesce((select jsonb_agg(to_jsonb(x) order by x.scheduled_at) from (select * from public.v_lab_experiments_detailed where status in ('planned','in_progress') order by scheduled_at nulls last limit 10) x), '[]'::jsonb),
    'upcoming_activities', coalesce((select jsonb_agg(to_jsonb(x) order by x.start_at) from (select * from public.v_school_activities_detailed where status='published' order by start_at nulls last limit 10) x), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_labs_activities_dashboard_payload() to authenticated;

create or replace function public.labs_activities_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'lab_rooms', to_regclass('public.lab_rooms') is not null,
    'lab_equipment', to_regclass('public.lab_equipment') is not null,
    'lab_experiments', to_regclass('public.lab_experiments') is not null,
    'lab_incidents', to_regclass('public.lab_incidents') is not null,
    'activity_categories', to_regclass('public.activity_categories') is not null,
    'school_activities', to_regclass('public.school_activities') is not null,
    'activity_participants', to_regclass('public.activity_participants') is not null,
    'rooms_view', to_regclass('public.v_lab_rooms_status') is not null,
    'experiments_view', to_regclass('public.v_lab_experiments_detailed') is not null,
    'activities_view', to_regclass('public.v_school_activities_detailed') is not null,
    'dashboard_rpc', to_regprocedure('public.get_labs_activities_dashboard_payload()') is not null,
    'seed_rpc', to_regprocedure('public.lab_activity_seed_defaults()') is not null,
    'activity_register_rpc', to_regprocedure('public.activity_register_student(uuid,uuid)') is not null,
    'stats', public.get_labs_activities_dashboard_payload()->'stats'
  );
end;
$$;

grant execute on function public.labs_activities_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'labs_activities_management_ready' as status;

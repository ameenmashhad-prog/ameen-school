-- =============================================================
-- مدارس أمين الرضا (ع) — وحدة النقل المدرسي
-- حافلات، سائقون، مسارات، مواقف، اشتراكات الطلاب، رحلات، حضور صعود/نزول.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) صلاحيات مساعدة
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

create or replace function public.transport_can_manage()
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
        and u.role in ('transport','transport_manager','staff','discipline','academic','academic_admin','scientific','supervisor')
    );
$$;

grant execute on function public.transport_can_manage() to authenticated;

-- -------------------------------------------------------------
-- 1) الجداول
-- -------------------------------------------------------------
create table if not exists public.transport_vehicles (
  id uuid primary key default gen_random_uuid(),
  plate_number text not null unique,
  vehicle_name text not null,
  capacity int not null default 20,
  model text,
  status text not null default 'active' check (status in ('active','maintenance','inactive','retired')),
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.transport_drivers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid null references public.users(id) on delete set null,
  full_name text not null,
  phone text,
  license_no text,
  status text not null default 'active' check (status in ('active','inactive','on_leave')),
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.transport_routes (
  id uuid primary key default gen_random_uuid(),
  route_name text not null,
  direction text not null default 'morning' check (direction in ('morning','afternoon','both')),
  vehicle_id uuid null references public.transport_vehicles(id) on delete set null,
  driver_id uuid null references public.transport_drivers(id) on delete set null,
  start_time time,
  end_time time,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.transport_route_stops (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.transport_routes(id) on delete cascade,
  stop_name text not null,
  stop_order int not null default 0,
  planned_time time,
  address text,
  lat numeric,
  lng numeric,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.transport_student_assignments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  route_id uuid not null references public.transport_routes(id) on delete cascade,
  pickup_stop_id uuid null references public.transport_route_stops(id) on delete set null,
  dropoff_stop_id uuid null references public.transport_route_stops(id) on delete set null,
  subscription_status text not null default 'active' check (subscription_status in ('active','paused','cancelled','pending')),
  start_date date not null default current_date,
  end_date date,
  monthly_fee numeric not null default 0,
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(student_id, route_id, subscription_status)
);

create table if not exists public.transport_trips (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.transport_routes(id) on delete cascade,
  vehicle_id uuid null references public.transport_vehicles(id) on delete set null,
  driver_id uuid null references public.transport_drivers(id) on delete set null,
  trip_date date not null default current_date,
  trip_direction text not null default 'morning' check (trip_direction in ('morning','afternoon')),
  status text not null default 'planned' check (status in ('planned','started','completed','cancelled')),
  started_at timestamptz,
  completed_at timestamptz,
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(route_id, trip_date, trip_direction)
);

create table if not exists public.transport_trip_attendance (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.transport_trips(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  status text not null default 'not_marked' check (status in ('not_marked','boarded','absent','dropped','parent_pickup')),
  boarded_at timestamptz,
  dropped_at timestamptz,
  stop_id uuid null references public.transport_route_stops(id) on delete set null,
  note text,
  recorded_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(trip_id, student_id)
);

create index if not exists idx_transport_routes_status on public.transport_routes(status, direction);
create index if not exists idx_transport_assignments_student on public.transport_student_assignments(student_id, subscription_status);
create index if not exists idx_transport_trips_date on public.transport_trips(trip_date, status);
create index if not exists idx_transport_trip_att_trip on public.transport_trip_attendance(trip_id, status);

-- -------------------------------------------------------------
-- 2) RLS
-- -------------------------------------------------------------
alter table public.transport_vehicles enable row level security;
alter table public.transport_drivers enable row level security;
alter table public.transport_routes enable row level security;
alter table public.transport_route_stops enable row level security;
alter table public.transport_student_assignments enable row level security;
alter table public.transport_trips enable row level security;
alter table public.transport_trip_attendance enable row level security;

drop policy if exists transport_vehicles_manage on public.transport_vehicles;
drop policy if exists transport_drivers_manage on public.transport_drivers;
drop policy if exists transport_routes_read_manage on public.transport_routes;
drop policy if exists transport_stops_read_manage on public.transport_route_stops;
drop policy if exists transport_assignments_scoped on public.transport_student_assignments;
drop policy if exists transport_trips_manage on public.transport_trips;
drop policy if exists transport_trip_attendance_scoped on public.transport_trip_attendance;

create policy transport_vehicles_manage on public.transport_vehicles
  for all to authenticated
  using (public.transport_can_manage())
  with check (public.transport_can_manage());

create policy transport_drivers_manage on public.transport_drivers
  for all to authenticated
  using (public.transport_can_manage() or user_id = auth.uid())
  with check (public.transport_can_manage());

create policy transport_routes_read_manage on public.transport_routes
  for all to authenticated
  using (public.transport_can_manage() or exists(select 1 from public.transport_student_assignments a join public.students s on s.id=a.student_id where a.route_id=id and a.subscription_status='active' and (s.user_id=auth.uid() or s.parent_id=auth.uid())))
  with check (public.transport_can_manage());

create policy transport_stops_read_manage on public.transport_route_stops
  for all to authenticated
  using (public.transport_can_manage() or exists(select 1 from public.transport_student_assignments a join public.students s on s.id=a.student_id where a.route_id=transport_route_stops.route_id and a.subscription_status='active' and (s.user_id=auth.uid() or s.parent_id=auth.uid())))
  with check (public.transport_can_manage());

create policy transport_assignments_scoped on public.transport_student_assignments
  for all to authenticated
  using (public.transport_can_manage() or exists(select 1 from public.students s where s.id=student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid())))
  with check (public.transport_can_manage());

create policy transport_trips_manage on public.transport_trips
  for all to authenticated
  using (public.transport_can_manage() or exists(select 1 from public.transport_student_assignments a join public.students s on s.id=a.student_id where a.route_id=transport_trips.route_id and a.subscription_status='active' and (s.user_id=auth.uid() or s.parent_id=auth.uid())))
  with check (public.transport_can_manage());

create policy transport_trip_attendance_scoped on public.transport_trip_attendance
  for all to authenticated
  using (public.transport_can_manage() or exists(select 1 from public.students s where s.id=student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid())))
  with check (public.transport_can_manage());

grant select, insert, update on public.transport_vehicles to authenticated;
grant select, insert, update on public.transport_drivers to authenticated;
grant select, insert, update on public.transport_routes to authenticated;
grant select, insert, update on public.transport_route_stops to authenticated;
grant select, insert, update on public.transport_student_assignments to authenticated;
grant select, insert, update on public.transport_trips to authenticated;
grant select, insert, update on public.transport_trip_attendance to authenticated;

-- -------------------------------------------------------------
-- 3) Views
-- -------------------------------------------------------------
create or replace view public.v_transport_routes_detailed
with (security_invoker=true) as
select
  r.id as route_id,
  r.route_name,
  r.direction,
  r.vehicle_id,
  v.plate_number,
  v.vehicle_name,
  v.capacity,
  r.driver_id,
  d.full_name as driver_name,
  d.phone as driver_phone,
  r.start_time,
  r.end_time,
  r.status,
  count(distinct a.student_id) filter (where a.subscription_status='active') as active_students,
  count(distinct s.id) as stops_count,
  coalesce(jsonb_agg(jsonb_build_object('stop_id',s.id,'stop_name',s.stop_name,'stop_order',s.stop_order,'planned_time',s.planned_time,'address',s.address) order by s.stop_order) filter (where s.id is not null), '[]'::jsonb) as stops,
  r.notes,
  r.created_at,
  r.updated_at
from public.transport_routes r
left join public.transport_vehicles v on v.id = r.vehicle_id
left join public.transport_drivers d on d.id = r.driver_id
left join public.transport_student_assignments a on a.route_id = r.id and a.subscription_status='active'
left join public.transport_route_stops s on s.route_id = r.id
group by r.id, v.id, d.id;

grant select on public.v_transport_routes_detailed to authenticated;

create or replace view public.v_transport_assignments_detailed
with (security_invoker=true) as
select
  a.id as assignment_id,
  a.student_id,
  st.name as student_name,
  st.class_id,
  c.name as class_name,
  st.section_id,
  sec.code as section_code,
  a.route_id,
  r.route_name,
  r.direction,
  a.pickup_stop_id,
  ps.stop_name as pickup_stop_name,
  a.dropoff_stop_id,
  ds.stop_name as dropoff_stop_name,
  a.subscription_status,
  a.start_date,
  a.end_date,
  a.monthly_fee,
  a.notes,
  a.created_at,
  a.updated_at
from public.transport_student_assignments a
join public.students st on st.id = a.student_id
left join public.classes c on c.id = st.class_id
left join public.sections sec on sec.id = st.section_id
join public.transport_routes r on r.id = a.route_id
left join public.transport_route_stops ps on ps.id = a.pickup_stop_id
left join public.transport_route_stops ds on ds.id = a.dropoff_stop_id
where public.transport_can_manage() or st.user_id = auth.uid() or st.parent_id = auth.uid();

grant select on public.v_transport_assignments_detailed to authenticated;

create or replace view public.v_transport_trips_detailed
with (security_invoker=true) as
select
  t.id as trip_id,
  t.route_id,
  r.route_name,
  t.vehicle_id,
  v.plate_number,
  v.vehicle_name,
  t.driver_id,
  d.full_name as driver_name,
  t.trip_date,
  t.trip_direction,
  t.status,
  t.started_at,
  t.completed_at,
  count(a.id) as attendance_rows,
  count(a.id) filter (where a.status='boarded') as boarded_count,
  count(a.id) filter (where a.status='absent') as absent_count,
  count(a.id) filter (where a.status='dropped') as dropped_count,
  t.notes,
  t.created_at,
  t.updated_at
from public.transport_trips t
join public.transport_routes r on r.id = t.route_id
left join public.transport_vehicles v on v.id = t.vehicle_id
left join public.transport_drivers d on d.id = t.driver_id
left join public.transport_trip_attendance a on a.trip_id = t.id
where public.transport_can_manage() or exists(select 1 from public.transport_student_assignments sa join public.students s on s.id=sa.student_id where sa.route_id=t.route_id and (s.user_id=auth.uid() or s.parent_id=auth.uid()))
group by t.id, r.id, v.id, d.id;

grant select on public.v_transport_trips_detailed to authenticated;

create or replace view public.v_transport_trip_attendance_detailed
with (security_invoker=true) as
select
  a.id as attendance_id,
  a.trip_id,
  t.route_id,
  r.route_name,
  t.trip_date,
  t.trip_direction,
  a.student_id,
  s.name as student_name,
  s.class_id,
  c.name as class_name,
  s.section_id,
  sec.code as section_code,
  a.status,
  a.boarded_at,
  a.dropped_at,
  a.stop_id,
  stp.stop_name,
  a.note,
  a.recorded_by,
  u.name as recorded_by_name,
  a.created_at,
  a.updated_at
from public.transport_trip_attendance a
join public.transport_trips t on t.id = a.trip_id
join public.transport_routes r on r.id = t.route_id
join public.students s on s.id = a.student_id
left join public.classes c on c.id = s.class_id
left join public.sections sec on sec.id = s.section_id
left join public.transport_route_stops stp on stp.id = a.stop_id
left join public.users u on u.id = a.recorded_by
where public.transport_can_manage() or s.user_id = auth.uid() or s.parent_id = auth.uid();

grant select on public.v_transport_trip_attendance_detailed to authenticated;

-- -------------------------------------------------------------
-- 4) Functions
-- -------------------------------------------------------------
create or replace function public.transport_seed_defaults()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  vehicle_id uuid;
  driver_id uuid;
  route_id uuid;
  inserted int := 0;
begin
  if not public.transport_can_manage() and auth.uid() is not null then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تهيئة النقل');
  end if;

  insert into public.transport_vehicles(plate_number, vehicle_name, capacity, model, created_by)
  values ('BUS-001', 'حافلة رقم 1', 24, 'مدرسي', auth.uid())
  on conflict (plate_number) do update set vehicle_name=excluded.vehicle_name
  returning id into vehicle_id;

  insert into public.transport_drivers(full_name, phone, license_no, created_by)
  values ('سائق تجريبي', '0000000000', 'LIC-001', auth.uid())
  returning id into driver_id;

  insert into public.transport_routes(route_name, direction, vehicle_id, driver_id, start_time, end_time, created_by)
  values ('مسار الصباح الرئيسي', 'morning', vehicle_id, driver_id, time '07:00', time '07:45', auth.uid())
  returning id into route_id;

  insert into public.transport_route_stops(route_id, stop_name, stop_order, planned_time, address)
  values
    (route_id, 'الموقف الأول', 1, time '07:00', 'نقطة تجمع 1'),
    (route_id, 'الموقف الثاني', 2, time '07:15', 'نقطة تجمع 2'),
    (route_id, 'المدرسة', 3, time '07:45', 'بوابة المدرسة');

  get diagnostics inserted = row_count;

  return jsonb_build_object('ok', true, 'message', 'تمت تهيئة النقل بعينة', 'route_id', route_id, 'stops', inserted);
end;
$$;

grant execute on function public.transport_seed_defaults() to authenticated;

create or replace function public.transport_upsert_vehicle(
  p_vehicle_id uuid default null,
  p_plate_number text default null,
  p_vehicle_name text default null,
  p_capacity int default 20,
  p_model text default null,
  p_status text default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  vid uuid;
begin
  if not public.transport_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدارة الحافلات');
  end if;

  if nullif(trim(coalesce(p_plate_number,'')), '') is null or nullif(trim(coalesce(p_vehicle_name,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'رقم اللوحة واسم الحافلة مطلوبان');
  end if;

  if p_status not in ('active','maintenance','inactive','retired') then p_status := 'active'; end if;

  if p_vehicle_id is not null then
    update public.transport_vehicles
    set plate_number=trim(p_plate_number), vehicle_name=trim(p_vehicle_name), capacity=coalesce(p_capacity,20), model=p_model, status=p_status, updated_at=now()
    where id=p_vehicle_id
    returning id into vid;
  else
    insert into public.transport_vehicles(plate_number, vehicle_name, capacity, model, status, created_by)
    values (trim(p_plate_number), trim(p_vehicle_name), coalesce(p_capacity,20), p_model, p_status, auth.uid())
    returning id into vid;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ الحافلة', 'vehicle_id', vid);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.transport_upsert_vehicle(uuid,text,text,int,text,text) to authenticated;

create or replace function public.transport_upsert_driver(
  p_driver_id uuid default null,
  p_full_name text default null,
  p_phone text default null,
  p_license_no text default null,
  p_user_id uuid default null,
  p_status text default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  did uuid;
begin
  if not public.transport_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدارة السائقين');
  end if;

  if nullif(trim(coalesce(p_full_name,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'اسم السائق مطلوب');
  end if;

  if p_status not in ('active','inactive','on_leave') then p_status := 'active'; end if;

  if p_driver_id is not null then
    update public.transport_drivers
    set full_name=trim(p_full_name), phone=p_phone, license_no=p_license_no, user_id=p_user_id, status=p_status, updated_at=now()
    where id=p_driver_id
    returning id into did;
  else
    insert into public.transport_drivers(full_name, phone, license_no, user_id, status, created_by)
    values (trim(p_full_name), p_phone, p_license_no, p_user_id, p_status, auth.uid())
    returning id into did;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ السائق', 'driver_id', did);
end;
$$;

grant execute on function public.transport_upsert_driver(uuid,text,text,text,uuid,text) to authenticated;

create or replace function public.transport_upsert_route(
  p_route_id uuid default null,
  p_route_name text default null,
  p_direction text default 'morning',
  p_vehicle_id uuid default null,
  p_driver_id uuid default null,
  p_start_time time default null,
  p_end_time time default null,
  p_status text default 'active',
  p_stops jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rid uuid;
  st jsonb;
  ord int := 1;
begin
  if not public.transport_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدارة المسارات');
  end if;

  if nullif(trim(coalesce(p_route_name,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'اسم المسار مطلوب');
  end if;

  if p_direction not in ('morning','afternoon','both') then p_direction := 'morning'; end if;
  if p_status not in ('active','inactive','archived') then p_status := 'active'; end if;

  if p_route_id is not null then
    update public.transport_routes
    set route_name=trim(p_route_name), direction=p_direction, vehicle_id=p_vehicle_id, driver_id=p_driver_id, start_time=p_start_time, end_time=p_end_time, status=p_status, updated_at=now()
    where id=p_route_id
    returning id into rid;
  else
    insert into public.transport_routes(route_name, direction, vehicle_id, driver_id, start_time, end_time, status, created_by)
    values (trim(p_route_name), p_direction, p_vehicle_id, p_driver_id, p_start_time, p_end_time, p_status, auth.uid())
    returning id into rid;
  end if;

  if jsonb_typeof(coalesce(p_stops,'[]'::jsonb)) = 'array' and jsonb_array_length(coalesce(p_stops,'[]'::jsonb)) > 0 then
    delete from public.transport_route_stops where route_id = rid;
    ord := 1;
    for st in select * from jsonb_array_elements(p_stops) loop
      if nullif(trim(coalesce(st->>'stop_name','')), '') is not null then
        insert into public.transport_route_stops(route_id, stop_name, stop_order, planned_time, address, notes)
        values (rid, trim(st->>'stop_name'), coalesce((st->>'stop_order')::int, ord), nullif(st->>'planned_time','')::time, st->>'address', st->>'notes');
        ord := ord + 1;
      end if;
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ المسار', 'route_id', rid);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.transport_upsert_route(uuid,text,text,uuid,uuid,time,time,text,jsonb) to authenticated;

create or replace function public.transport_assign_student(
  p_student_id uuid,
  p_route_id uuid,
  p_pickup_stop_id uuid default null,
  p_dropoff_stop_id uuid default null,
  p_monthly_fee numeric default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  assignment_id uuid;
begin
  if not public.transport_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تسجيل الطلاب في النقل');
  end if;

  update public.transport_student_assignments
  set subscription_status='cancelled', updated_at=now()
  where student_id=p_student_id and subscription_status='active';

  insert into public.transport_student_assignments(student_id, route_id, pickup_stop_id, dropoff_stop_id, monthly_fee, created_by)
  values (p_student_id, p_route_id, p_pickup_stop_id, p_dropoff_stop_id, coalesce(p_monthly_fee,0), auth.uid())
  returning id into assignment_id;

  return jsonb_build_object('ok', true, 'message', 'تم تسجيل الطالب في مسار النقل', 'assignment_id', assignment_id);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.transport_assign_student(uuid,uuid,uuid,uuid,numeric) to authenticated;

create or replace function public.transport_create_trip(
  p_route_id uuid,
  p_trip_date date default current_date,
  p_trip_direction text default 'morning'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  trip_id uuid;
  a record;
begin
  if not public.transport_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إنشاء الرحلات');
  end if;

  select * into r from public.transport_routes where id=p_route_id;
  if r.id is null then return jsonb_build_object('ok', false, 'message', 'المسار غير موجود'); end if;
  if p_trip_direction not in ('morning','afternoon') then p_trip_direction := 'morning'; end if;

  select id into trip_id from public.transport_trips where route_id=p_route_id and trip_date=coalesce(p_trip_date,current_date) and trip_direction=p_trip_direction;
  if trip_id is null then
    insert into public.transport_trips(route_id, vehicle_id, driver_id, trip_date, trip_direction, status, created_by)
    values (p_route_id, r.vehicle_id, r.driver_id, coalesce(p_trip_date,current_date), p_trip_direction, 'planned', auth.uid())
    returning id into trip_id;
  end if;

  for a in select * from public.transport_student_assignments where route_id=p_route_id and subscription_status='active' loop
    insert into public.transport_trip_attendance(trip_id, student_id, status, stop_id, recorded_by)
    values (trip_id, a.student_id, 'not_marked', case when p_trip_direction='morning' then a.pickup_stop_id else a.dropoff_stop_id end, auth.uid())
    on conflict (trip_id, student_id) do nothing;
  end loop;

  return jsonb_build_object('ok', true, 'message', 'تم إنشاء الرحلة وتجهيز قائمة الطلاب', 'trip_id', trip_id);
end;
$$;

grant execute on function public.transport_create_trip(uuid,date,text) to authenticated;

create or replace function public.transport_mark_attendance(
  p_trip_id uuid,
  p_student_id uuid,
  p_status text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  att_id uuid;
begin
  if not public.transport_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تحضير النقل');
  end if;

  if p_status not in ('not_marked','boarded','absent','dropped','parent_pickup') then p_status := 'not_marked'; end if;

  update public.transport_trip_attendance
  set status=p_status,
      boarded_at=case when p_status='boarded' then now() else boarded_at end,
      dropped_at=case when p_status in ('dropped','parent_pickup') then now() else dropped_at end,
      note=p_note,
      recorded_by=auth.uid(),
      updated_at=now()
  where trip_id=p_trip_id and student_id=p_student_id
  returning id into att_id;

  if att_id is null then
    insert into public.transport_trip_attendance(trip_id, student_id, status, note, recorded_by)
    values (p_trip_id, p_student_id, p_status, p_note, auth.uid())
    returning id into att_id;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم تحديث حالة الطالب في الرحلة', 'attendance_id', att_id);
end;
$$;

grant execute on function public.transport_mark_attendance(uuid,uuid,text,text) to authenticated;

create or replace function public.transport_set_trip_status(
  p_trip_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.transport_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تحديث الرحلة');
  end if;

  if p_status not in ('planned','started','completed','cancelled') then p_status := 'planned'; end if;

  update public.transport_trips
  set status=p_status,
      started_at=case when p_status='started' and started_at is null then now() else started_at end,
      completed_at=case when p_status='completed' then now() else completed_at end,
      updated_at=now()
  where id=p_trip_id;

  return jsonb_build_object('ok', true, 'message', 'تم تحديث حالة الرحلة', 'status', p_status);
end;
$$;

grant execute on function public.transport_set_trip_status(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 5) Dashboard + Health
-- -------------------------------------------------------------
create or replace function public.get_transport_dashboard_payload()
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
      'vehicles', (select count(*) from public.transport_vehicles where status='active'),
      'drivers', (select count(*) from public.transport_drivers where status='active'),
      'routes', (select count(*) from public.transport_routes where status='active'),
      'active_students', (select count(*) from public.transport_student_assignments where subscription_status='active'),
      'today_trips', (select count(*) from public.transport_trips where trip_date=current_date),
      'today_boarded', (select count(*) from public.transport_trip_attendance a join public.transport_trips t on t.id=a.trip_id where t.trip_date=current_date and a.status='boarded'),
      'today_absent', (select count(*) from public.transport_trip_attendance a join public.transport_trips t on t.id=a.trip_id where t.trip_date=current_date and a.status='absent')
    ),
    'today_trips', coalesce((select jsonb_agg(to_jsonb(x) order by x.trip_date desc) from (select * from public.v_transport_trips_detailed where trip_date=current_date order by created_at desc) x), '[]'::jsonb),
    'routes', coalesce((select jsonb_agg(to_jsonb(x) order by x.route_name) from (select * from public.v_transport_routes_detailed where status='active') x), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_transport_dashboard_payload() to authenticated;

create or replace function public.transport_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'vehicles_table', to_regclass('public.transport_vehicles') is not null,
    'drivers_table', to_regclass('public.transport_drivers') is not null,
    'routes_table', to_regclass('public.transport_routes') is not null,
    'stops_table', to_regclass('public.transport_route_stops') is not null,
    'assignments_table', to_regclass('public.transport_student_assignments') is not null,
    'trips_table', to_regclass('public.transport_trips') is not null,
    'attendance_table', to_regclass('public.transport_trip_attendance') is not null,
    'routes_view', to_regclass('public.v_transport_routes_detailed') is not null,
    'assignments_view', to_regclass('public.v_transport_assignments_detailed') is not null,
    'trips_view', to_regclass('public.v_transport_trips_detailed') is not null,
    'dashboard_rpc', to_regprocedure('public.get_transport_dashboard_payload()') is not null,
    'seed_rpc', to_regprocedure('public.transport_seed_defaults()') is not null,
    'vehicle_rpc', to_regprocedure('public.transport_upsert_vehicle(uuid,text,text,int,text,text)') is not null,
    'driver_rpc', to_regprocedure('public.transport_upsert_driver(uuid,text,text,text,uuid,text)') is not null,
    'route_rpc', to_regprocedure('public.transport_upsert_route(uuid,text,text,uuid,uuid,time,time,text,jsonb)') is not null,
    'assign_rpc', to_regprocedure('public.transport_assign_student(uuid,uuid,uuid,uuid,numeric)') is not null,
    'trip_rpc', to_regprocedure('public.transport_create_trip(uuid,date,text)') is not null,
    'stats', public.get_transport_dashboard_payload()->'stats'
  );
end;
$$;

grant execute on function public.transport_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'transportation_management_ready' as status;

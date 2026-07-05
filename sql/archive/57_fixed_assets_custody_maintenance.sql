-- =============================================================
-- مدارس أمين الرضا (ع) — وحدة الأصول الثابتة والعُهد والصيانة
-- أصول، تسليم عهدة، إرجاع، صيانة، إهلاك، لوحة تقارير.
-- =============================================================

create extension if not exists pgcrypto;

-- جداول مشتركة مع المخزون، ننشئها إن لم تكن موجودة حتى يعمل الملف مستقلاً.
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_name text,
  phone text,
  email text,
  address text,
  notes text,
  is_active boolean not null default true,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inventory_locations (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  created_at timestamptz not null default now()
);

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

create or replace function public.assets_can_manage()
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
        and u.role in ('finance','staff','inventory','procurement','maintenance','asset_manager','academic','academic_admin','scientific','supervisor')
    );
$$;

grant execute on function public.assets_can_manage() to authenticated;

-- -------------------------------------------------------------
-- 1) الجداول
-- -------------------------------------------------------------
create table if not exists public.fixed_asset_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  default_useful_life_months int not null default 60,
  created_at timestamptz not null default now()
);

create table if not exists public.fixed_assets (
  id uuid primary key default gen_random_uuid(),
  asset_code text not null unique,
  name text not null,
  category_id uuid null references public.fixed_asset_categories(id) on delete set null,
  serial_number text,
  supplier_id uuid null references public.suppliers(id) on delete set null,
  location_id uuid null references public.inventory_locations(id) on delete set null,
  purchase_date date,
  purchase_cost numeric not null default 0,
  salvage_value numeric not null default 0,
  useful_life_months int not null default 60,
  status text not null default 'available' check (status in ('available','assigned','maintenance','lost','disposed','retired')),
  condition_status text not null default 'good' check (condition_status in ('new','good','fair','poor','damaged')),
  notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.asset_custody_records (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.fixed_assets(id) on delete cascade,
  assigned_to_user_id uuid null references public.users(id) on delete set null,
  assigned_to_student_id uuid null references public.students(id) on delete set null,
  assigned_to_text text,
  assigned_by uuid null references public.users(id),
  assigned_at timestamptz not null default now(),
  due_at timestamptz,
  returned_at timestamptz,
  returned_by uuid null references public.users(id),
  status text not null default 'active' check (status in ('active','returned','lost','cancelled')),
  notes text,
  return_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_asset_active_custody
  on public.asset_custody_records(asset_id)
  where status = 'active';

create table if not exists public.asset_maintenance_tickets (
  id uuid primary key default gen_random_uuid(),
  ticket_no text unique,
  asset_id uuid not null references public.fixed_assets(id) on delete cascade,
  title text not null,
  description text,
  priority text not null default 'medium' check (priority in ('low','medium','high','urgent')),
  status text not null default 'open' check (status in ('open','in_progress','completed','cancelled')),
  reported_by uuid null references public.users(id),
  assigned_to uuid null references public.users(id),
  cost numeric not null default 0,
  opened_at timestamptz not null default now(),
  completed_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_fixed_assets_status on public.fixed_assets(status, category_id);
create index if not exists idx_asset_custody_asset_status on public.asset_custody_records(asset_id, status);
create index if not exists idx_asset_maintenance_asset_status on public.asset_maintenance_tickets(asset_id, status);

-- -------------------------------------------------------------
-- 2) RLS
-- -------------------------------------------------------------
alter table public.fixed_asset_categories enable row level security;
alter table public.fixed_assets enable row level security;
alter table public.asset_custody_records enable row level security;
alter table public.asset_maintenance_tickets enable row level security;

drop policy if exists fixed_asset_categories_manage on public.fixed_asset_categories;
drop policy if exists fixed_assets_manage on public.fixed_assets;
drop policy if exists asset_custody_manage on public.asset_custody_records;
drop policy if exists asset_maintenance_manage on public.asset_maintenance_tickets;

create policy fixed_asset_categories_manage on public.fixed_asset_categories
  for all to authenticated
  using (public.assets_can_manage())
  with check (public.assets_can_manage());

create policy fixed_assets_manage on public.fixed_assets
  for all to authenticated
  using (public.assets_can_manage())
  with check (public.assets_can_manage());

create policy asset_custody_manage on public.asset_custody_records
  for all to authenticated
  using (public.assets_can_manage() or assigned_to_user_id = auth.uid() or exists(select 1 from public.students s where s.id=assigned_to_student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid())))
  with check (public.assets_can_manage());

create policy asset_maintenance_manage on public.asset_maintenance_tickets
  for all to authenticated
  using (public.assets_can_manage() or reported_by = auth.uid() or assigned_to = auth.uid())
  with check (public.assets_can_manage() or reported_by = auth.uid());

grant select, insert, update on public.fixed_asset_categories to authenticated;
grant select, insert, update on public.fixed_assets to authenticated;
grant select, insert, update on public.asset_custody_records to authenticated;
grant select, insert, update on public.asset_maintenance_tickets to authenticated;

-- -------------------------------------------------------------
-- 3) Views
-- -------------------------------------------------------------
create or replace view public.v_fixed_assets_register
with (security_invoker=true) as
select
  a.id,
  a.asset_code,
  a.name,
  a.category_id,
  cat.name as category_name,
  a.serial_number,
  a.supplier_id,
  sup.name as supplier_name,
  a.location_id,
  loc.name as location_name,
  a.purchase_date,
  a.purchase_cost,
  a.salvage_value,
  a.useful_life_months,
  a.status,
  a.condition_status,
  a.notes,
  greatest(0, extract(year from age(current_date, coalesce(a.purchase_date,current_date)))::int * 12 + extract(month from age(current_date, coalesce(a.purchase_date,current_date)))::int) as age_months,
  case
    when a.purchase_cost <= 0 then 0
    when a.useful_life_months <= 0 then a.purchase_cost
    else greatest(a.salvage_value, round(a.purchase_cost - ((a.purchase_cost - a.salvage_value) * least(greatest(0, extract(year from age(current_date, coalesce(a.purchase_date,current_date)))::int * 12 + extract(month from age(current_date, coalesce(a.purchase_date,current_date)))::int), a.useful_life_months) / a.useful_life_months),2))
  end as book_value,
  c.id as custody_id,
  c.assigned_to_user_id,
  u.name as assigned_to_user_name,
  c.assigned_to_student_id,
  s.name as assigned_to_student_name,
  c.assigned_to_text,
  c.assigned_at,
  c.due_at,
  mt.open_maintenance_count,
  a.created_at,
  a.updated_at
from public.fixed_assets a
left join public.fixed_asset_categories cat on cat.id = a.category_id
left join public.suppliers sup on sup.id = a.supplier_id
left join public.inventory_locations loc on loc.id = a.location_id
left join public.asset_custody_records c on c.asset_id = a.id and c.status='active'
left join public.users u on u.id = c.assigned_to_user_id
left join public.students s on s.id = c.assigned_to_student_id
left join lateral (
  select count(*) as open_maintenance_count
  from public.asset_maintenance_tickets t
  where t.asset_id = a.id and t.status in ('open','in_progress')
) mt on true
where public.assets_can_manage();

grant select on public.v_fixed_assets_register to authenticated;

create or replace view public.v_asset_custody_detailed
with (security_invoker=true) as
select
  c.id as custody_id,
  c.asset_id,
  a.asset_code,
  a.name as asset_name,
  a.category_id,
  cat.name as category_name,
  c.assigned_to_user_id,
  u.name as assigned_to_user_name,
  c.assigned_to_student_id,
  s.name as assigned_to_student_name,
  c.assigned_to_text,
  c.assigned_by,
  byu.name as assigned_by_name,
  c.assigned_at,
  c.due_at,
  c.returned_at,
  c.returned_by,
  c.status,
  c.notes,
  c.return_notes,
  c.created_at,
  c.updated_at
from public.asset_custody_records c
join public.fixed_assets a on a.id = c.asset_id
left join public.fixed_asset_categories cat on cat.id = a.category_id
left join public.users u on u.id = c.assigned_to_user_id
left join public.students s on s.id = c.assigned_to_student_id
left join public.users byu on byu.id = c.assigned_by
where public.assets_can_manage()
   or c.assigned_to_user_id = auth.uid()
   or exists(select 1 from public.students st where st.id=c.assigned_to_student_id and (st.user_id=auth.uid() or st.parent_id=auth.uid()));

grant select on public.v_asset_custody_detailed to authenticated;

create or replace view public.v_asset_maintenance_detailed
with (security_invoker=true) as
select
  t.id as ticket_id,
  t.ticket_no,
  t.asset_id,
  a.asset_code,
  a.name as asset_name,
  t.title,
  t.description,
  t.priority,
  t.status,
  t.reported_by,
  ru.name as reported_by_name,
  t.assigned_to,
  au.name as assigned_to_name,
  t.cost,
  t.opened_at,
  t.completed_at,
  t.notes,
  t.created_at,
  t.updated_at
from public.asset_maintenance_tickets t
join public.fixed_assets a on a.id = t.asset_id
left join public.users ru on ru.id = t.reported_by
left join public.users au on au.id = t.assigned_to
where public.assets_can_manage() or t.reported_by=auth.uid() or t.assigned_to=auth.uid();

grant select on public.v_asset_maintenance_detailed to authenticated;

-- -------------------------------------------------------------
-- 4) دوال التشغيل
-- -------------------------------------------------------------
create or replace function public.asset_seed_defaults()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cat_it uuid;
  cat_furniture uuid;
  loc_id uuid;
  inserted_assets int := 0;
begin
  if not public.assets_can_manage() and auth.uid() is not null then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تهيئة الأصول');
  end if;

  insert into public.fixed_asset_categories(name, description, default_useful_life_months)
  values ('تقنية ومختبرات', 'أجهزة حاسوب ووسائل تعليمية', 48)
  on conflict (name) do update set description=excluded.description
  returning id into cat_it;

  insert into public.fixed_asset_categories(name, description, default_useful_life_months)
  values ('أثاث مدرسي', 'طاولات وكراسي وخزائن', 84)
  on conflict (name) do update set description=excluded.description
  returning id into cat_furniture;

  insert into public.inventory_locations(name, description)
  values ('مبنى المدرسة الرئيسي', 'موقع افتراضي للأصول')
  on conflict (name) do update set description=excluded.description
  returning id into loc_id;

  insert into public.fixed_assets(asset_code, name, category_id, location_id, purchase_date, purchase_cost, useful_life_months, status, condition_status, created_by)
  values
    ('AST-LAP-001', 'حاسوب محمول إداري', cat_it, loc_id, current_date - 120, 700, 48, 'available', 'good', auth.uid()),
    ('AST-PROJ-001', 'جهاز عرض صفّي', cat_it, loc_id, current_date - 60, 450, 48, 'available', 'good', auth.uid()),
    ('AST-DESK-001', 'مكتب إداري', cat_furniture, loc_id, current_date - 300, 250, 84, 'available', 'good', auth.uid())
  on conflict (asset_code) do nothing;

  get diagnostics inserted_assets = row_count;

  return jsonb_build_object('ok', true, 'message', 'تمت تهيئة أصول عينة', 'inserted_assets', inserted_assets);
end;
$$;

grant execute on function public.asset_seed_defaults() to authenticated;

create or replace function public.asset_upsert(
  p_asset_id uuid default null,
  p_name text default null,
  p_asset_code text default null,
  p_category text default null,
  p_serial_number text default null,
  p_location text default null,
  p_purchase_date date default null,
  p_purchase_cost numeric default 0,
  p_useful_life_months int default 60,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cat_id uuid;
  loc_id uuid;
  asset_id uuid;
  code text;
begin
  if not public.assets_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدارة الأصول');
  end if;

  if nullif(trim(coalesce(p_name,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'اسم الأصل مطلوب');
  end if;

  if nullif(trim(coalesce(p_category,'')), '') is not null then
    insert into public.fixed_asset_categories(name)
    values (trim(p_category))
    on conflict (name) do update set name=excluded.name
    returning id into cat_id;
  end if;

  if nullif(trim(coalesce(p_location,'')), '') is not null then
    insert into public.inventory_locations(name)
    values (trim(p_location))
    on conflict (name) do update set name=excluded.name
    returning id into loc_id;
  end if;

  code := nullif(trim(coalesce(p_asset_code,'')), '');

  if p_asset_id is not null then
    update public.fixed_assets
    set name=trim(p_name),
        asset_code=coalesce(code, asset_code),
        category_id=cat_id,
        serial_number=nullif(trim(coalesce(p_serial_number,'')), ''),
        location_id=loc_id,
        purchase_date=p_purchase_date,
        purchase_cost=coalesce(p_purchase_cost,0),
        useful_life_months=coalesce(p_useful_life_months,60),
        notes=p_notes,
        updated_at=now()
    where id=p_asset_id
    returning id into asset_id;
  else
    code := coalesce(code, 'AST-' || to_char(now(),'YYYYMMDD-HH24MISS') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,4));
    insert into public.fixed_assets(asset_code, name, category_id, serial_number, location_id, purchase_date, purchase_cost, useful_life_months, notes, created_by)
    values (code, trim(p_name), cat_id, nullif(trim(coalesce(p_serial_number,'')), ''), loc_id, p_purchase_date, coalesce(p_purchase_cost,0), coalesce(p_useful_life_months,60), p_notes, auth.uid())
    returning id into asset_id;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ الأصل', 'asset_id', asset_id);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.asset_upsert(uuid,text,text,text,text,text,date,numeric,int,text) to authenticated;

create or replace function public.asset_assign(
  p_asset_id uuid,
  p_user_id uuid default null,
  p_student_id uuid default null,
  p_assigned_to_text text default null,
  p_due_at timestamptz default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
  custody_id uuid;
begin
  if not public.assets_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تسليم العهد');
  end if;

  select * into a from public.fixed_assets where id=p_asset_id;
  if a.id is null then return jsonb_build_object('ok', false, 'message', 'الأصل غير موجود'); end if;
  if a.status in ('lost','disposed','retired') then return jsonb_build_object('ok', false, 'message', 'لا يمكن تسليم أصل مفقود/مستبعد'); end if;

  update public.asset_custody_records
  set status='returned', returned_at=now(), returned_by=auth.uid(), return_notes='إغلاق عهدة تلقائي بسبب تسليم جديد', updated_at=now()
  where asset_id=p_asset_id and status='active';

  insert into public.asset_custody_records(asset_id, assigned_to_user_id, assigned_to_student_id, assigned_to_text, assigned_by, due_at, notes)
  values (p_asset_id, p_user_id, p_student_id, p_assigned_to_text, auth.uid(), p_due_at, p_notes)
  returning id into custody_id;

  update public.fixed_assets set status='assigned', updated_at=now() where id=p_asset_id;

  return jsonb_build_object('ok', true, 'message', 'تم تسليم العهدة', 'custody_id', custody_id);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.asset_assign(uuid,uuid,uuid,text,timestamptz,text) to authenticated;

create or replace function public.asset_return(
  p_custody_id uuid,
  p_condition_status text default 'good',
  p_return_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c record;
begin
  if not public.assets_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إرجاع العهدة');
  end if;

  select * into c from public.asset_custody_records where id=p_custody_id;
  if c.id is null then return jsonb_build_object('ok', false, 'message', 'سجل العهدة غير موجود'); end if;

  update public.asset_custody_records
  set status='returned', returned_at=now(), returned_by=auth.uid(), return_notes=p_return_notes, updated_at=now()
  where id=p_custody_id;

  update public.fixed_assets
  set status='available', condition_status=case when p_condition_status in ('new','good','fair','poor','damaged') then p_condition_status else condition_status end, updated_at=now()
  where id=c.asset_id;

  return jsonb_build_object('ok', true, 'message', 'تم إرجاع العهدة');
end;
$$;

grant execute on function public.asset_return(uuid,text,text) to authenticated;

create or replace function public.asset_maintenance_ticket_save(
  p_asset_id uuid,
  p_title text,
  p_description text default null,
  p_priority text default 'medium',
  p_assigned_to uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
  ticket_id uuid;
  no text;
begin
  if not public.assets_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إنشاء صيانة');
  end if;

  select * into a from public.fixed_assets where id=p_asset_id;
  if a.id is null then return jsonb_build_object('ok', false, 'message', 'الأصل غير موجود'); end if;

  if nullif(trim(coalesce(p_title,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'عنوان الصيانة مطلوب');
  end if;

  no := 'MT-' || to_char(now(),'YYYYMMDD-HH24MISS') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,4);

  insert into public.asset_maintenance_tickets(ticket_no, asset_id, title, description, priority, reported_by, assigned_to)
  values (no, p_asset_id, trim(p_title), p_description, case when p_priority in ('low','medium','high','urgent') then p_priority else 'medium' end, auth.uid(), p_assigned_to)
  returning id into ticket_id;

  update public.fixed_assets set status='maintenance', updated_at=now() where id=p_asset_id;

  return jsonb_build_object('ok', true, 'message', 'تم فتح طلب الصيانة', 'ticket_id', ticket_id, 'ticket_no', no);
end;
$$;

grant execute on function public.asset_maintenance_ticket_save(uuid,text,text,text,uuid) to authenticated;

create or replace function public.asset_maintenance_close(
  p_ticket_id uuid,
  p_cost numeric default 0,
  p_notes text default null,
  p_condition_status text default 'good'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  t record;
begin
  if not public.assets_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إغلاق الصيانة');
  end if;

  select * into t from public.asset_maintenance_tickets where id=p_ticket_id;
  if t.id is null then return jsonb_build_object('ok', false, 'message', 'طلب الصيانة غير موجود'); end if;

  update public.asset_maintenance_tickets
  set status='completed', completed_at=now(), cost=coalesce(p_cost,0), notes=p_notes, updated_at=now()
  where id=p_ticket_id;

  update public.fixed_assets
  set status=case when exists(select 1 from public.asset_custody_records c where c.asset_id=t.asset_id and c.status='active') then 'assigned' else 'available' end,
      condition_status=case when p_condition_status in ('new','good','fair','poor','damaged') then p_condition_status else condition_status end,
      updated_at=now()
  where id=t.asset_id;

  return jsonb_build_object('ok', true, 'message', 'تم إغلاق الصيانة');
end;
$$;

grant execute on function public.asset_maintenance_close(uuid,numeric,text,text) to authenticated;

-- -------------------------------------------------------------
-- 5) Dashboard + Health
-- -------------------------------------------------------------
create or replace function public.get_assets_dashboard_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if not public.assets_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية عرض الأصول');
  end if;

  return jsonb_build_object(
    'ok', true,
    'stats', jsonb_build_object(
      'assets_total', (select count(*) from public.fixed_assets),
      'available', (select count(*) from public.fixed_assets where status='available'),
      'assigned', (select count(*) from public.fixed_assets where status='assigned'),
      'maintenance', (select count(*) from public.fixed_assets where status='maintenance'),
      'lost', (select count(*) from public.fixed_assets where status='lost'),
      'disposed', (select count(*) from public.fixed_assets where status in ('disposed','retired')),
      'purchase_cost_total', (select coalesce(sum(purchase_cost),0) from public.fixed_assets),
      'book_value_total', (select coalesce(sum(book_value),0) from public.v_fixed_assets_register),
      'active_custody', (select count(*) from public.asset_custody_records where status='active'),
      'open_maintenance', (select count(*) from public.asset_maintenance_tickets where status in ('open','in_progress'))
    ),
    'recent_assets', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from public.v_fixed_assets_register order by created_at desc limit 12) x), '[]'::jsonb),
    'open_maintenance', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from public.v_asset_maintenance_detailed where status in ('open','in_progress') order by created_at desc limit 12) x), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_assets_dashboard_payload() to authenticated;

create or replace function public.assets_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'categories_table', to_regclass('public.fixed_asset_categories') is not null,
    'assets_table', to_regclass('public.fixed_assets') is not null,
    'custody_table', to_regclass('public.asset_custody_records') is not null,
    'maintenance_table', to_regclass('public.asset_maintenance_tickets') is not null,
    'assets_view', to_regclass('public.v_fixed_assets_register') is not null,
    'custody_view', to_regclass('public.v_asset_custody_detailed') is not null,
    'maintenance_view', to_regclass('public.v_asset_maintenance_detailed') is not null,
    'dashboard_rpc', to_regprocedure('public.get_assets_dashboard_payload()') is not null,
    'upsert_rpc', to_regprocedure('public.asset_upsert(uuid,text,text,text,text,text,date,numeric,int,text)') is not null,
    'assign_rpc', to_regprocedure('public.asset_assign(uuid,uuid,uuid,text,timestamptz,text)') is not null,
    'return_rpc', to_regprocedure('public.asset_return(uuid,text,text)') is not null,
    'maintenance_rpc', to_regprocedure('public.asset_maintenance_ticket_save(uuid,text,text,text,uuid)') is not null,
    'stats', case when public.assets_can_manage() then public.get_assets_dashboard_payload()->'stats' else '{}'::jsonb end
  );
end;
$$;

grant execute on function public.assets_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'fixed_assets_custody_maintenance_ready' as status;

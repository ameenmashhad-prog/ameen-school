-- =============================================================
-- مدارس أمين الرضا (ع) — Mega Batch ERP: المخزون والمشتريات + تجهيز عينة للمكتبة
-- Vanilla/Supabase compatible, no external services.
-- =============================================================

create extension if not exists pgcrypto;

-- =============================================================
-- A) Library seed/import helpers
-- =============================================================

create or replace function public.library_seed_sample_books()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_count int := 0;
  item_id uuid;
  inserted_items int := 0;
  inserted_copies int := 0;
  rec record;
  i int;
  code text;
begin
  select count(*) into existing_count from public.library_items;
  if existing_count > 0 then
    return jsonb_build_object('ok', true, 'message', 'المكتبة تحتوي كتباً مسبقاً؛ لم تتم إضافة عينة', 'existing_count', existing_count);
  end if;

  for rec in
    select * from (values
      ('القراءة العربية المبسطة', 'قسم اللغة العربية', 'لغة عربية', 'ar', 'book', 'نصوص قصيرة مناسبة للمرحلة الابتدائية', 3),
      ('قصص الأنبياء للأطفال', 'دار المعرفة', 'تربية إسلامية', 'ar', 'book', 'قصص مبسطة مع قيم تربوية', 2),
      ('مبادئ الرياضيات الممتعة', 'فريق الرياضيات', 'رياضيات', 'ar', 'book', 'أنشطة وتمارين في الأعداد والعمليات', 3),
      ('علوم من حولنا', 'قسم العلوم', 'علوم', 'ar', 'book', 'مدخل مبسط للبيئة والحيوانات والنباتات', 2),
      ('English Short Stories A1', 'School English Dept.', 'English', 'en', 'book', 'Simple English stories for beginners', 2)
    ) as t(title, author, category, language, item_type, description, copies)
  loop
    insert into public.library_items(title, author, category, language, item_type, description, created_by)
    values (rec.title, rec.author, rec.category, rec.language, rec.item_type, rec.description, auth.uid())
    returning id into item_id;
    inserted_items := inserted_items + 1;

    for i in 1..rec.copies loop
      code := upper(substr(replace(item_id::text,'-',''),1,8)) || '-' || lpad(i::text,3,'0');
      insert into public.library_copies(item_id, copy_code, barcode, location, status)
      values (item_id, code, code, 'الرف الرئيسي', 'available')
      on conflict (copy_code) do nothing;
      inserted_copies := inserted_copies + 1;
    end loop;
  end loop;

  return jsonb_build_object('ok', true, 'message', 'تمت إضافة كتب عينة للمكتبة', 'items', inserted_items, 'copies', inserted_copies);
end;
$$;

grant execute on function public.library_seed_sample_books() to authenticated;

-- =============================================================
-- B) Inventory & Procurement
-- =============================================================

create or replace function public.inventory_can_manage()
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
        and u.role in ('finance','staff','inventory','procurement','academic','academic_admin','scientific','supervisor')
    );
$$;

grant execute on function public.inventory_can_manage() to authenticated;

-- -------------------------------------------------------------
-- 1) Tables
-- -------------------------------------------------------------
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

create table if not exists public.inventory_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.inventory_locations (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  sku text unique,
  name text not null,
  description text,
  category_id uuid null references public.inventory_categories(id) on delete set null,
  default_location_id uuid null references public.inventory_locations(id) on delete set null,
  unit text not null default 'قطعة',
  min_stock numeric not null default 0,
  current_stock numeric not null default 0,
  average_cost numeric not null default 0,
  is_consumable boolean not null default true,
  is_active boolean not null default true,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inventory_stock_movements (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.inventory_items(id) on delete cascade,
  movement_type text not null check (movement_type in ('in','out','adjustment','transfer','receive','issue','return')),
  quantity numeric not null,
  unit_cost numeric,
  from_location_id uuid null references public.inventory_locations(id) on delete set null,
  to_location_id uuid null references public.inventory_locations(id) on delete set null,
  reference_table text,
  reference_id uuid,
  reason text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.purchase_requests (
  id uuid primary key default gen_random_uuid(),
  request_no text unique,
  title text not null,
  requester_id uuid null references public.users(id),
  supplier_id uuid null references public.suppliers(id) on delete set null,
  status text not null default 'draft' check (status in ('draft','submitted','approved','rejected','ordered','received','cancelled')),
  needed_by date,
  notes text,
  total_estimated numeric not null default 0,
  approved_by uuid null references public.users(id),
  approved_at timestamptz,
  received_by uuid null references public.users(id),
  received_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.purchase_request_items (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.purchase_requests(id) on delete cascade,
  inventory_item_id uuid null references public.inventory_items(id) on delete set null,
  item_name text not null,
  quantity numeric not null default 1,
  estimated_unit_cost numeric not null default 0,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists idx_inventory_items_category_stock on public.inventory_items(category_id, current_stock);
create index if not exists idx_inventory_movements_item_created on public.inventory_stock_movements(item_id, created_at desc);
create index if not exists idx_purchase_requests_status on public.purchase_requests(status, created_at desc);
create index if not exists idx_purchase_request_items_request on public.purchase_request_items(request_id);

-- -------------------------------------------------------------
-- 2) RLS
-- -------------------------------------------------------------
alter table public.suppliers enable row level security;
alter table public.inventory_categories enable row level security;
alter table public.inventory_locations enable row level security;
alter table public.inventory_items enable row level security;
alter table public.inventory_stock_movements enable row level security;
alter table public.purchase_requests enable row level security;
alter table public.purchase_request_items enable row level security;

drop policy if exists suppliers_manage on public.suppliers;
drop policy if exists inventory_categories_manage on public.inventory_categories;
drop policy if exists inventory_locations_manage on public.inventory_locations;
drop policy if exists inventory_items_manage on public.inventory_items;
drop policy if exists inventory_movements_manage on public.inventory_stock_movements;
drop policy if exists purchase_requests_manage on public.purchase_requests;
drop policy if exists purchase_request_items_manage on public.purchase_request_items;

create policy suppliers_manage on public.suppliers for all to authenticated using (public.inventory_can_manage()) with check (public.inventory_can_manage());
create policy inventory_categories_manage on public.inventory_categories for all to authenticated using (public.inventory_can_manage()) with check (public.inventory_can_manage());
create policy inventory_locations_manage on public.inventory_locations for all to authenticated using (public.inventory_can_manage()) with check (public.inventory_can_manage());
create policy inventory_items_manage on public.inventory_items for all to authenticated using (public.inventory_can_manage()) with check (public.inventory_can_manage());
create policy inventory_movements_manage on public.inventory_stock_movements for all to authenticated using (public.inventory_can_manage()) with check (public.inventory_can_manage());
create policy purchase_requests_manage on public.purchase_requests for all to authenticated using (public.inventory_can_manage() or requester_id = auth.uid()) with check (public.inventory_can_manage() or requester_id = auth.uid());
create policy purchase_request_items_manage on public.purchase_request_items for all to authenticated using (exists(select 1 from public.purchase_requests pr where pr.id=request_id and (public.inventory_can_manage() or pr.requester_id=auth.uid()))) with check (exists(select 1 from public.purchase_requests pr where pr.id=request_id and (public.inventory_can_manage() or pr.requester_id=auth.uid())));

grant select, insert, update on public.suppliers to authenticated;
grant select, insert, update on public.inventory_categories to authenticated;
grant select, insert, update on public.inventory_locations to authenticated;
grant select, insert, update on public.inventory_items to authenticated;
grant select, insert on public.inventory_stock_movements to authenticated;
grant select, insert, update on public.purchase_requests to authenticated;
grant select, insert, update on public.purchase_request_items to authenticated;

-- -------------------------------------------------------------
-- 3) Views
-- -------------------------------------------------------------
create or replace view public.v_inventory_stock
with (security_invoker=true) as
select
  i.id,
  i.sku,
  i.name,
  i.description,
  i.category_id,
  cat.name as category_name,
  i.default_location_id,
  loc.name as location_name,
  i.unit,
  i.min_stock,
  i.current_stock,
  i.average_cost,
  i.is_consumable,
  i.is_active,
  case
    when i.current_stock <= 0 then 'out'
    when i.current_stock <= i.min_stock then 'low'
    else 'ok'
  end as stock_status,
  i.created_at,
  i.updated_at
from public.inventory_items i
left join public.inventory_categories cat on cat.id = i.category_id
left join public.inventory_locations loc on loc.id = i.default_location_id
where public.inventory_can_manage();

grant select on public.v_inventory_stock to authenticated;

create or replace view public.v_purchase_requests_detailed
with (security_invoker=true) as
select
  pr.id,
  pr.request_no,
  pr.title,
  pr.requester_id,
  ru.name as requester_name,
  pr.supplier_id,
  s.name as supplier_name,
  pr.status,
  pr.needed_by,
  pr.notes,
  pr.total_estimated,
  pr.approved_by,
  au.name as approved_by_name,
  pr.approved_at,
  pr.received_by,
  recu.name as received_by_name,
  pr.received_at,
  count(ri.id) as items_count,
  coalesce(jsonb_agg(jsonb_build_object('id',ri.id,'inventory_item_id',ri.inventory_item_id,'item_name',ri.item_name,'quantity',ri.quantity,'estimated_unit_cost',ri.estimated_unit_cost,'notes',ri.notes) order by ri.created_at) filter (where ri.id is not null), '[]'::jsonb) as items,
  pr.created_at,
  pr.updated_at
from public.purchase_requests pr
left join public.users ru on ru.id = pr.requester_id
left join public.suppliers s on s.id = pr.supplier_id
left join public.users au on au.id = pr.approved_by
left join public.users recu on recu.id = pr.received_by
left join public.purchase_request_items ri on ri.request_id = pr.id
where public.inventory_can_manage() or pr.requester_id = auth.uid()
group by pr.id, ru.name, s.name, au.name, recu.name;

grant select on public.v_purchase_requests_detailed to authenticated;

create or replace view public.v_inventory_movements_detailed
with (security_invoker=true) as
select
  m.id,
  m.item_id,
  i.name as item_name,
  i.sku,
  m.movement_type,
  m.quantity,
  m.unit_cost,
  m.from_location_id,
  fl.name as from_location_name,
  m.to_location_id,
  tl.name as to_location_name,
  m.reference_table,
  m.reference_id,
  m.reason,
  m.created_by,
  u.name as created_by_name,
  m.created_at
from public.inventory_stock_movements m
join public.inventory_items i on i.id = m.item_id
left join public.inventory_locations fl on fl.id = m.from_location_id
left join public.inventory_locations tl on tl.id = m.to_location_id
left join public.users u on u.id = m.created_by
where public.inventory_can_manage();

grant select on public.v_inventory_movements_detailed to authenticated;

-- -------------------------------------------------------------
-- 4) Functions
-- -------------------------------------------------------------
create or replace function public.inventory_seed_defaults()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cat_id uuid;
  loc_id uuid;
  inserted_items int := 0;
begin
  if not public.inventory_can_manage() and auth.uid() is not null then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تهيئة المخزون');
  end if;

  insert into public.inventory_categories(name, description)
  values ('قرطاسية', 'أقلام ودفاتر ولوازم مكتبية')
  on conflict (name) do update set description=excluded.description
  returning id into cat_id;

  insert into public.inventory_locations(name, description)
  values ('المستودع الرئيسي', 'الموقع الافتراضي للمخزون')
  on conflict (name) do update set description=excluded.description
  returning id into loc_id;

  insert into public.inventory_items(sku, name, category_id, default_location_id, unit, min_stock, current_stock, average_cost, created_by)
  values
    ('PEN-BLUE', 'قلم أزرق', cat_id, loc_id, 'قطعة', 50, 100, 0, auth.uid()),
    ('NOTE-A5', 'دفتر A5', cat_id, loc_id, 'قطعة', 30, 60, 0, auth.uid()),
    ('BOARD-MARKER', 'قلم سبورة', cat_id, loc_id, 'قطعة', 20, 40, 0, auth.uid())
  on conflict (sku) do nothing;

  get diagnostics inserted_items = row_count;

  return jsonb_build_object('ok', true, 'message', 'تمت تهيئة بيانات مخزون عينة', 'inserted_items', inserted_items);
end;
$$;

grant execute on function public.inventory_seed_defaults() to authenticated;

create or replace function public.inventory_upsert_item(
  p_item_id uuid default null,
  p_name text default null,
  p_sku text default null,
  p_category text default null,
  p_location text default 'المستودع الرئيسي',
  p_unit text default 'قطعة',
  p_min_stock numeric default 0,
  p_initial_stock numeric default 0,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cat_id uuid;
  loc_id uuid;
  item_id uuid;
  old_stock numeric := 0;
  diff numeric := 0;
begin
  if not public.inventory_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدارة المخزون');
  end if;

  if nullif(trim(coalesce(p_name,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'اسم الصنف مطلوب');
  end if;

  if nullif(trim(coalesce(p_category,'')), '') is not null then
    insert into public.inventory_categories(name)
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

  if p_item_id is not null then
    select current_stock into old_stock from public.inventory_items where id=p_item_id;
    if old_stock is null then return jsonb_build_object('ok', false, 'message', 'الصنف غير موجود'); end if;

    update public.inventory_items
    set name=trim(p_name),
        sku=nullif(trim(coalesce(p_sku,'')), ''),
        category_id=cat_id,
        default_location_id=loc_id,
        unit=coalesce(nullif(trim(p_unit),''),'قطعة'),
        min_stock=coalesce(p_min_stock,0),
        description=p_description,
        updated_at=now()
    where id=p_item_id
    returning id into item_id;
  else
    insert into public.inventory_items(sku, name, category_id, default_location_id, unit, min_stock, current_stock, description, created_by)
    values (nullif(trim(coalesce(p_sku,'')), ''), trim(p_name), cat_id, loc_id, coalesce(nullif(trim(p_unit),''),'قطعة'), coalesce(p_min_stock,0), coalesce(p_initial_stock,0), p_description, auth.uid())
    returning id into item_id;

    if coalesce(p_initial_stock,0) <> 0 then
      insert into public.inventory_stock_movements(item_id, movement_type, quantity, to_location_id, reason, created_by)
      values (item_id, 'in', p_initial_stock, loc_id, 'رصيد افتتاحي', auth.uid());
    end if;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ الصنف', 'item_id', item_id);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.inventory_upsert_item(uuid,text,text,text,text,text,numeric,numeric,text) to authenticated;

create or replace function public.inventory_adjust_stock(
  p_item_id uuid,
  p_quantity numeric,
  p_movement_type text default 'adjustment',
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item record;
  delta numeric;
begin
  if not public.inventory_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل المخزون');
  end if;

  select * into item from public.inventory_items where id=p_item_id;
  if item.id is null then return jsonb_build_object('ok', false, 'message', 'الصنف غير موجود'); end if;

  if p_quantity is null or p_quantity = 0 then
    return jsonb_build_object('ok', false, 'message', 'الكمية يجب ألا تكون صفراً');
  end if;

  if p_movement_type not in ('in','out','adjustment','transfer','receive','issue','return') then
    p_movement_type := 'adjustment';
  end if;

  delta := case when p_movement_type in ('out','issue') then -abs(p_quantity) else p_quantity end;

  if item.current_stock + delta < 0 then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن أن يصبح الرصيد سالباً');
  end if;

  update public.inventory_items
  set current_stock = current_stock + delta,
      updated_at = now()
  where id=p_item_id;

  insert into public.inventory_stock_movements(item_id, movement_type, quantity, to_location_id, reason, created_by)
  values (p_item_id, p_movement_type, delta, item.default_location_id, p_reason, auth.uid());

  return jsonb_build_object('ok', true, 'message', 'تم تحديث المخزون', 'new_stock', item.current_stock + delta);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.inventory_adjust_stock(uuid,numeric,text,text) to authenticated;

create or replace function public.supplier_upsert(
  p_supplier_id uuid default null,
  p_name text default null,
  p_phone text default null,
  p_contact_name text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  sid uuid;
begin
  if not public.inventory_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدارة الموردين');
  end if;

  if nullif(trim(coalesce(p_name,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'اسم المورد مطلوب');
  end if;

  if p_supplier_id is not null then
    update public.suppliers
    set name=trim(p_name), phone=p_phone, contact_name=p_contact_name, notes=p_notes, updated_at=now()
    where id=p_supplier_id
    returning id into sid;
  else
    insert into public.suppliers(name, phone, contact_name, notes, created_by)
    values (trim(p_name), p_phone, p_contact_name, p_notes, auth.uid())
    returning id into sid;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ المورد', 'supplier_id', sid);
end;
$$;

grant execute on function public.supplier_upsert(uuid,text,text,text,text) to authenticated;

create or replace function public.purchase_request_create(
  p_title text,
  p_supplier_id uuid default null,
  p_needed_by date default null,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb,
  p_submit boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  req_id uuid;
  req_no text;
  it jsonb;
  total numeric := 0;
  qty numeric;
  cost numeric;
begin
  if not public.inventory_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إنشاء طلب شراء');
  end if;

  if nullif(trim(coalesce(p_title,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'عنوان طلب الشراء مطلوب');
  end if;

  req_no := 'PR-' || to_char(now(),'YYYYMMDD-HH24MISS') || '-' || substr(replace(gen_random_uuid()::text,'-',''),1,4);

  insert into public.purchase_requests(request_no, title, requester_id, supplier_id, status, needed_by, notes)
  values (req_no, trim(p_title), auth.uid(), p_supplier_id, case when p_submit then 'submitted' else 'draft' end, p_needed_by, p_notes)
  returning id into req_id;

  for it in select * from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    qty := greatest(coalesce((it->>'quantity')::numeric,1),0);
    cost := greatest(coalesce((it->>'estimated_unit_cost')::numeric,0),0);
    if nullif(trim(coalesce(it->>'item_name','')), '') is not null and qty > 0 then
      insert into public.purchase_request_items(request_id, inventory_item_id, item_name, quantity, estimated_unit_cost, notes)
      values (req_id, nullif(it->>'inventory_item_id','')::uuid, trim(it->>'item_name'), qty, cost, it->>'notes');
      total := total + qty*cost;
    end if;
  end loop;

  update public.purchase_requests set total_estimated=total where id=req_id;

  return jsonb_build_object('ok', true, 'message', 'تم إنشاء طلب الشراء', 'request_id', req_id, 'request_no', req_no, 'total', total);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.purchase_request_create(text,uuid,date,text,jsonb,boolean) to authenticated;

create or replace function public.purchase_request_set_status(
  p_request_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  pr record;
  st text := lower(coalesce(p_status,''));
begin
  if not public.inventory_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل طلب الشراء');
  end if;

  select * into pr from public.purchase_requests where id=p_request_id;
  if pr.id is null then return jsonb_build_object('ok', false, 'message', 'طلب الشراء غير موجود'); end if;

  if st not in ('draft','submitted','approved','rejected','ordered','received','cancelled') then
    return jsonb_build_object('ok', false, 'message', 'حالة الطلب غير صحيحة');
  end if;

  update public.purchase_requests
  set status=st,
      approved_by=case when st='approved' then auth.uid() else approved_by end,
      approved_at=case when st='approved' then now() else approved_at end,
      updated_at=now()
  where id=p_request_id;

  return jsonb_build_object('ok', true, 'message', 'تم تحديث حالة طلب الشراء', 'status', st);
end;
$$;

grant execute on function public.purchase_request_set_status(uuid,text) to authenticated;

create or replace function public.purchase_request_receive(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  pr record;
  it record;
  received_items int := 0;
begin
  if not public.inventory_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية استلام المشتريات');
  end if;

  select * into pr from public.purchase_requests where id=p_request_id;
  if pr.id is null then return jsonb_build_object('ok', false, 'message', 'طلب الشراء غير موجود'); end if;
  if pr.status not in ('approved','ordered','submitted') then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن الاستلام قبل اعتماد/طلب الشراء');
  end if;

  for it in select * from public.purchase_request_items where request_id=p_request_id loop
    if it.inventory_item_id is not null then
      update public.inventory_items
      set current_stock = current_stock + it.quantity,
          average_cost = case when it.estimated_unit_cost > 0 then it.estimated_unit_cost else average_cost end,
          updated_at = now()
      where id=it.inventory_item_id;

      insert into public.inventory_stock_movements(item_id, movement_type, quantity, unit_cost, reference_table, reference_id, reason, created_by)
      values (it.inventory_item_id, 'receive', it.quantity, it.estimated_unit_cost, 'purchase_requests', p_request_id, 'استلام مشتريات', auth.uid());
      received_items := received_items + 1;
    end if;
  end loop;

  update public.purchase_requests
  set status='received', received_by=auth.uid(), received_at=now(), updated_at=now()
  where id=p_request_id;

  return jsonb_build_object('ok', true, 'message', 'تم استلام طلب الشراء وتحديث المخزون', 'received_items', received_items);
end;
$$;

grant execute on function public.purchase_request_receive(uuid) to authenticated;

-- -------------------------------------------------------------
-- 5) Dashboard + Health
-- -------------------------------------------------------------
create or replace function public.get_inventory_dashboard_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if not public.inventory_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية عرض المخزون');
  end if;

  return jsonb_build_object(
    'ok', true,
    'stats', jsonb_build_object(
      'items', (select count(*) from public.inventory_items where is_active=true),
      'low_stock', (select count(*) from public.inventory_items where is_active=true and current_stock <= min_stock),
      'out_stock', (select count(*) from public.inventory_items where is_active=true and current_stock <= 0),
      'movements', (select count(*) from public.inventory_stock_movements),
      'suppliers', (select count(*) from public.suppliers where is_active=true),
      'purchase_requests_open', (select count(*) from public.purchase_requests where status in ('draft','submitted','approved','ordered')),
      'purchase_requests_received', (select count(*) from public.purchase_requests where status='received')
    ),
    'low_items', coalesce((select jsonb_agg(to_jsonb(x) order by x.current_stock) from (select * from public.v_inventory_stock where stock_status in ('low','out') limit 20) x), '[]'::jsonb),
    'recent_movements', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from public.v_inventory_movements_detailed order by created_at desc limit 20) x), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_inventory_dashboard_payload() to authenticated;

create or replace function public.inventory_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'suppliers', to_regclass('public.suppliers') is not null,
    'categories', to_regclass('public.inventory_categories') is not null,
    'locations', to_regclass('public.inventory_locations') is not null,
    'items', to_regclass('public.inventory_items') is not null,
    'movements', to_regclass('public.inventory_stock_movements') is not null,
    'purchase_requests', to_regclass('public.purchase_requests') is not null,
    'purchase_request_items', to_regclass('public.purchase_request_items') is not null,
    'stock_view', to_regclass('public.v_inventory_stock') is not null,
    'requests_view', to_regclass('public.v_purchase_requests_detailed') is not null,
    'movements_view', to_regclass('public.v_inventory_movements_detailed') is not null,
    'dashboard_rpc', to_regprocedure('public.get_inventory_dashboard_payload()') is not null,
    'upsert_item_rpc', to_regprocedure('public.inventory_upsert_item(uuid,text,text,text,text,text,numeric,numeric,text)') is not null,
    'adjust_stock_rpc', to_regprocedure('public.inventory_adjust_stock(uuid,numeric,text,text)') is not null,
    'purchase_create_rpc', to_regprocedure('public.purchase_request_create(text,uuid,date,text,jsonb,boolean)') is not null,
    'purchase_receive_rpc', to_regprocedure('public.purchase_request_receive(uuid)') is not null,
    'stats', case when public.inventory_can_manage() then public.get_inventory_dashboard_payload()->'stats' else '{}'::jsonb end
  );
end;
$$;

grant execute on function public.inventory_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'inventory_procurement_ready' as status;

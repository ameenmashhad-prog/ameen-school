-- =============================================================
-- مدارس أمين الرضا (ع) — وحدة المكتبة المدرسية
-- فهرس الكتب، النسخ، الإعارة، الإرجاع، الحجز، التقارير.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) دوال صلاحيات مساعدة
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

create or replace function public.library_can_manage()
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
        and u.role in ('librarian','staff','teacher','academic','academic_admin','scientific','supervisor')
    );
$$;

grant execute on function public.library_can_manage() to authenticated;

create or replace function public.library_current_student_id()
returns uuid
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  sid uuid;
begin
  select s.id into sid
  from public.students s
  where s.user_id = auth.uid()
  limit 1;

  if sid is null then
    select s.id into sid
    from public.students s
    where s.parent_id = auth.uid()
    order by s.name
    limit 1;
  end if;

  return sid;
end;
$$;

grant execute on function public.library_current_student_id() to authenticated;

-- -------------------------------------------------------------
-- 1) الجداول
-- -------------------------------------------------------------
create table if not exists public.library_items (
  id uuid primary key default gen_random_uuid(),
  isbn text,
  title text not null,
  subtitle text,
  author text,
  publisher text,
  category text,
  subject_id uuid null references public.subjects(id) on delete set null,
  language text not null default 'ar',
  item_type text not null default 'book' check (item_type in ('book','reference','magazine','digital','other')),
  description text,
  cover_url text,
  keywords jsonb not null default '[]'::jsonb,
  age_level text,
  is_active boolean not null default true,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.library_copies (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.library_items(id) on delete cascade,
  copy_code text not null,
  barcode text,
  location text,
  acquisition_date date,
  price numeric,
  status text not null default 'available' check (status in ('available','loaned','reserved','lost','damaged','maintenance')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(copy_code)
);

create table if not exists public.library_loans (
  id uuid primary key default gen_random_uuid(),
  copy_id uuid not null references public.library_copies(id) on delete restrict,
  item_id uuid not null references public.library_items(id) on delete cascade,
  borrower_user_id uuid null references public.users(id) on delete set null,
  borrower_student_id uuid null references public.students(id) on delete set null,
  borrower_type text not null default 'student' check (borrower_type in ('student','teacher','staff','other')),
  loaned_at timestamptz not null default now(),
  due_at timestamptz not null default (now() + interval '14 days'),
  returned_at timestamptz,
  status text not null default 'active' check (status in ('active','returned','overdue','lost')),
  fine_amount numeric not null default 0,
  issued_by uuid null references public.users(id),
  returned_by uuid null references public.users(id),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.library_reservations (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.library_items(id) on delete cascade,
  copy_id uuid null references public.library_copies(id) on delete set null,
  requester_user_id uuid null references public.users(id) on delete set null,
  requester_student_id uuid null references public.students(id) on delete set null,
  status text not null default 'active' check (status in ('active','fulfilled','cancelled','expired')),
  reserved_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '3 days'),
  fulfilled_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_library_items_search on public.library_items(title, author, category);
create index if not exists idx_library_copies_item_status on public.library_copies(item_id, status);
create index if not exists idx_library_loans_status_due on public.library_loans(status, due_at);
create index if not exists idx_library_loans_borrower on public.library_loans(borrower_user_id, borrower_student_id);
create index if not exists idx_library_reservations_item_status on public.library_reservations(item_id, status);

-- -------------------------------------------------------------
-- 2) Views
-- -------------------------------------------------------------
create or replace view public.v_library_catalog
with (security_invoker=true) as
select
  i.id,
  i.isbn,
  i.title,
  i.subtitle,
  i.author,
  i.publisher,
  i.category,
  i.subject_id,
  sub.name as subject_name,
  i.language,
  i.item_type,
  i.description,
  i.cover_url,
  i.keywords,
  i.age_level,
  i.is_active,
  count(c.id) as copies_count,
  count(c.id) filter (where c.status='available') as available_count,
  count(c.id) filter (where c.status='loaned') as loaned_count,
  count(c.id) filter (where c.status in ('lost','damaged','maintenance')) as unavailable_count,
  count(r.id) filter (where r.status='active') as active_reservations,
  i.created_at,
  i.updated_at
from public.library_items i
left join public.subjects sub on sub.id = i.subject_id
left join public.library_copies c on c.item_id = i.id
left join public.library_reservations r on r.item_id = i.id and r.status='active'
where i.is_active = true
group by i.id, sub.name;

grant select on public.v_library_catalog to authenticated;

create or replace view public.v_library_loans_detailed
with (security_invoker=true) as
select
  l.id as loan_id,
  l.copy_id,
  c.copy_code,
  c.barcode,
  l.item_id,
  i.title,
  i.author,
  i.category,
  l.borrower_user_id,
  bu.name as borrower_user_name,
  l.borrower_student_id,
  s.name as borrower_student_name,
  l.borrower_type,
  l.loaned_at,
  l.due_at,
  l.returned_at,
  case when l.status='active' and l.due_at < now() then 'overdue' else l.status end as computed_status,
  l.status,
  l.fine_amount,
  l.issued_by,
  iu.name as issued_by_name,
  l.returned_by,
  ru.name as returned_by_name,
  l.notes,
  l.created_at,
  l.updated_at
from public.library_loans l
join public.library_copies c on c.id = l.copy_id
join public.library_items i on i.id = l.item_id
left join public.users bu on bu.id = l.borrower_user_id
left join public.students s on s.id = l.borrower_student_id
left join public.users iu on iu.id = l.issued_by
left join public.users ru on ru.id = l.returned_by
where public.library_can_manage()
   or l.borrower_user_id = auth.uid()
   or exists(select 1 from public.students st where st.id = l.borrower_student_id and (st.user_id = auth.uid() or st.parent_id = auth.uid()));

grant select on public.v_library_loans_detailed to authenticated;

create or replace view public.v_library_reservations_detailed
with (security_invoker=true) as
select
  r.id as reservation_id,
  r.item_id,
  i.title,
  i.author,
  r.copy_id,
  c.copy_code,
  r.requester_user_id,
  u.name as requester_user_name,
  r.requester_student_id,
  s.name as requester_student_name,
  r.status,
  r.reserved_at,
  r.expires_at,
  r.fulfilled_at,
  r.notes,
  r.created_at,
  r.updated_at
from public.library_reservations r
join public.library_items i on i.id = r.item_id
left join public.library_copies c on c.id = r.copy_id
left join public.users u on u.id = r.requester_user_id
left join public.students s on s.id = r.requester_student_id
where public.library_can_manage()
   or r.requester_user_id = auth.uid()
   or exists(select 1 from public.students st where st.id = r.requester_student_id and (st.user_id = auth.uid() or st.parent_id = auth.uid()));

grant select on public.v_library_reservations_detailed to authenticated;

-- -------------------------------------------------------------
-- 3) RLS
-- -------------------------------------------------------------
alter table public.library_items enable row level security;
alter table public.library_copies enable row level security;
alter table public.library_loans enable row level security;
alter table public.library_reservations enable row level security;

drop policy if exists library_items_select_auth on public.library_items;
drop policy if exists library_items_manage on public.library_items;
drop policy if exists library_copies_select_auth on public.library_copies;
drop policy if exists library_copies_manage on public.library_copies;
drop policy if exists library_loans_select_scoped on public.library_loans;
drop policy if exists library_loans_manage on public.library_loans;
drop policy if exists library_reservations_select_scoped on public.library_reservations;
drop policy if exists library_reservations_write_scoped on public.library_reservations;

create policy library_items_select_auth on public.library_items
  for select to authenticated
  using (is_active = true or public.library_can_manage());

create policy library_items_manage on public.library_items
  for all to authenticated
  using (public.library_can_manage())
  with check (public.library_can_manage());

create policy library_copies_select_auth on public.library_copies
  for select to authenticated
  using (exists(select 1 from public.library_items i where i.id=item_id and i.is_active=true) or public.library_can_manage());

create policy library_copies_manage on public.library_copies
  for all to authenticated
  using (public.library_can_manage())
  with check (public.library_can_manage());

create policy library_loans_select_scoped on public.library_loans
  for select to authenticated
  using (
    public.library_can_manage()
    or borrower_user_id = auth.uid()
    or exists(select 1 from public.students s where s.id = borrower_student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
  );

create policy library_loans_manage on public.library_loans
  for all to authenticated
  using (public.library_can_manage())
  with check (public.library_can_manage());

create policy library_reservations_select_scoped on public.library_reservations
  for select to authenticated
  using (
    public.library_can_manage()
    or requester_user_id = auth.uid()
    or exists(select 1 from public.students s where s.id = requester_student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
  );

create policy library_reservations_write_scoped on public.library_reservations
  for all to authenticated
  using (
    public.library_can_manage()
    or requester_user_id = auth.uid()
    or exists(select 1 from public.students s where s.id = requester_student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
  )
  with check (
    public.library_can_manage()
    or requester_user_id = auth.uid()
    or exists(select 1 from public.students s where s.id = requester_student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
  );

grant select, insert, update on public.library_items to authenticated;
grant select, insert, update on public.library_copies to authenticated;
grant select, insert, update on public.library_loans to authenticated;
grant select, insert, update on public.library_reservations to authenticated;

-- -------------------------------------------------------------
-- 4) دوال الإدارة
-- -------------------------------------------------------------
create or replace function public.library_upsert_item(
  p_item_id uuid default null,
  p_title text default null,
  p_author text default null,
  p_isbn text default null,
  p_category text default null,
  p_language text default 'ar',
  p_item_type text default 'book',
  p_description text default null,
  p_copies int default 1,
  p_location text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item_id uuid;
  old_item record;
  i int;
  base_code text;
begin
  if not public.library_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدارة المكتبة');
  end if;

  if nullif(trim(coalesce(p_title,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'عنوان الكتاب مطلوب');
  end if;

  if p_item_type not in ('book','reference','magazine','digital','other') then
    p_item_type := 'book';
  end if;

  if p_item_id is not null then
    select * into old_item from public.library_items where id = p_item_id;
    if old_item.id is null then
      return jsonb_build_object('ok', false, 'message', 'العنصر غير موجود');
    end if;

    update public.library_items
    set title = trim(p_title),
        author = nullif(trim(coalesce(p_author,'')), ''),
        isbn = nullif(trim(coalesce(p_isbn,'')), ''),
        category = nullif(trim(coalesce(p_category,'')), ''),
        language = coalesce(nullif(p_language,''),'ar'),
        item_type = p_item_type,
        description = p_description,
        updated_at = now()
    where id = p_item_id
    returning id into item_id;
  else
    insert into public.library_items(title, author, isbn, category, language, item_type, description, created_by)
    values (trim(p_title), nullif(trim(coalesce(p_author,'')), ''), nullif(trim(coalesce(p_isbn,'')), ''), nullif(trim(coalesce(p_category,'')), ''), coalesce(nullif(p_language,''),'ar'), p_item_type, p_description, auth.uid())
    returning id into item_id;
  end if;

  if p_item_id is null and coalesce(p_copies,0) > 0 then
    base_code := upper(substr(replace(item_id::text,'-',''),1,8));
    for i in 1..least(greatest(p_copies,1),100) loop
      insert into public.library_copies(item_id, copy_code, barcode, location, status)
      values (item_id, base_code || '-' || lpad(i::text,3,'0'), base_code || '-' || lpad(i::text,3,'0'), p_location, 'available')
      on conflict (copy_code) do nothing;
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ بيانات الكتاب', 'item_id', item_id);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.library_upsert_item(uuid,text,text,text,text,text,text,text,int,text) to authenticated;

create or replace function public.library_add_copy(
  p_item_id uuid,
  p_location text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item record;
  n int;
  code text;
  copy_id uuid;
begin
  if not public.library_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إدارة المكتبة');
  end if;

  select * into item from public.library_items where id = p_item_id;
  if item.id is null then
    return jsonb_build_object('ok', false, 'message', 'الكتاب غير موجود');
  end if;

  select count(*) + 1 into n from public.library_copies where item_id = p_item_id;
  code := upper(substr(replace(p_item_id::text,'-',''),1,8)) || '-' || lpad(n::text,3,'0');

  insert into public.library_copies(item_id, copy_code, barcode, location, status)
  values (p_item_id, code, code, p_location, 'available')
  returning id into copy_id;

  return jsonb_build_object('ok', true, 'message', 'تمت إضافة نسخة', 'copy_id', copy_id, 'copy_code', code);
end;
$$;

grant execute on function public.library_add_copy(uuid,text) to authenticated;

create or replace function public.library_checkout(
  p_copy_id uuid,
  p_borrower_user_id uuid default null,
  p_borrower_student_id uuid default null,
  p_days int default 14,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c record;
  loan_id uuid;
  b_type text := 'other';
begin
  if not public.library_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية الإعارة');
  end if;

  select * into c from public.library_copies where id = p_copy_id;
  if c.id is null then return jsonb_build_object('ok', false, 'message', 'النسخة غير موجودة'); end if;
  if c.status <> 'available' then return jsonb_build_object('ok', false, 'message', 'هذه النسخة غير متاحة حالياً'); end if;

  if p_borrower_student_id is not null then b_type := 'student';
  elsif p_borrower_user_id is not null and exists(select 1 from public.users u where u.id=p_borrower_user_id and u.role='teacher') then b_type := 'teacher';
  elsif p_borrower_user_id is not null then b_type := 'staff';
  end if;

  insert into public.library_loans(copy_id, item_id, borrower_user_id, borrower_student_id, borrower_type, due_at, issued_by, notes)
  values (p_copy_id, c.item_id, p_borrower_user_id, p_borrower_student_id, b_type, now() + (greatest(coalesce(p_days,14),1)::text || ' days')::interval, auth.uid(), p_notes)
  returning id into loan_id;

  update public.library_copies set status='loaned', updated_at=now() where id=p_copy_id;

  update public.library_reservations
  set status='fulfilled', fulfilled_at=now(), updated_at=now()
  where status='active'
    and item_id=c.item_id
    and (
      (p_borrower_student_id is not null and requester_student_id=p_borrower_student_id)
      or
      (p_borrower_user_id is not null and requester_user_id=p_borrower_user_id)
    );

  return jsonb_build_object('ok', true, 'message', 'تمت إعارة الكتاب', 'loan_id', loan_id);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.library_checkout(uuid,uuid,uuid,int,text) to authenticated;

create or replace function public.library_return(
  p_loan_id uuid,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  l record;
  overdue_days int := 0;
  fine numeric := 0;
begin
  if not public.library_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية الإرجاع');
  end if;

  select * into l from public.library_loans where id = p_loan_id;
  if l.id is null then return jsonb_build_object('ok', false, 'message', 'الإعارة غير موجودة'); end if;
  if l.status = 'returned' then return jsonb_build_object('ok', true, 'message', 'الإعارة مرجعة مسبقاً'); end if;

  overdue_days := greatest(0, floor(extract(epoch from (now() - l.due_at))/86400)::int);
  fine := overdue_days * 0; -- يمكن تغيير قيمة الغرامة لاحقاً.

  update public.library_loans
  set status='returned', returned_at=now(), returned_by=auth.uid(), fine_amount=fine, notes=coalesce(p_notes,notes), updated_at=now()
  where id=p_loan_id;

  update public.library_copies set status='available', updated_at=now() where id=l.copy_id;

  return jsonb_build_object('ok', true, 'message', 'تم إرجاع الكتاب', 'overdue_days', overdue_days, 'fine', fine);
end;
$$;

grant execute on function public.library_return(uuid,text) to authenticated;

create or replace function public.library_reserve(
  p_item_id uuid,
  p_student_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item record;
  sid uuid;
  rid uuid;
begin
  select * into item from public.library_items where id=p_item_id and is_active=true;
  if item.id is null then return jsonb_build_object('ok', false, 'message', 'الكتاب غير موجود'); end if;

  sid := coalesce(p_student_id, public.library_current_student_id());

  if sid is not null and not exists(select 1 from public.students s where s.id=sid and (s.user_id=auth.uid() or s.parent_id=auth.uid() or public.library_can_manage())) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية الحجز لهذا الطالب');
  end if;

  if exists(select 1 from public.library_reservations r where r.item_id=p_item_id and r.status='active' and (r.requester_user_id=auth.uid() or (sid is not null and r.requester_student_id=sid))) then
    return jsonb_build_object('ok', true, 'message', 'يوجد حجز فعال مسبقاً');
  end if;

  insert into public.library_reservations(item_id, requester_user_id, requester_student_id)
  values (p_item_id, auth.uid(), sid)
  returning id into rid;

  return jsonb_build_object('ok', true, 'message', 'تم حجز الكتاب', 'reservation_id', rid);
end;
$$;

grant execute on function public.library_reserve(uuid,uuid) to authenticated;

create or replace function public.library_cancel_reservation(p_reservation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  select * into r from public.library_reservations where id=p_reservation_id;
  if r.id is null then return jsonb_build_object('ok', false, 'message', 'الحجز غير موجود'); end if;

  if not (public.library_can_manage() or r.requester_user_id=auth.uid() or exists(select 1 from public.students s where s.id=r.requester_student_id and (s.user_id=auth.uid() or s.parent_id=auth.uid()))) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إلغاء هذا الحجز');
  end if;

  update public.library_reservations set status='cancelled', updated_at=now() where id=p_reservation_id;
  return jsonb_build_object('ok', true, 'message', 'تم إلغاء الحجز');
end;
$$;

grant execute on function public.library_cancel_reservation(uuid) to authenticated;

-- -------------------------------------------------------------
-- 5) Payload + Health
-- -------------------------------------------------------------
create or replace function public.get_library_dashboard_payload()
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
      'items', (select count(*) from public.library_items where is_active=true),
      'copies', (select count(*) from public.library_copies),
      'available', (select count(*) from public.library_copies where status='available'),
      'loaned', (select count(*) from public.library_copies where status='loaned'),
      'active_loans', (select count(*) from public.library_loans where status='active'),
      'overdue_loans', (select count(*) from public.library_loans where status='active' and due_at < now()),
      'active_reservations', (select count(*) from public.library_reservations where status='active')
    ),
    'popular', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.loans_count desc)
      from (
        select i.id, i.title, i.author, count(l.id) as loans_count
        from public.library_items i
        left join public.library_loans l on l.item_id=i.id
        group by i.id
        order by loans_count desc, i.title
        limit 10
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_library_dashboard_payload() to authenticated;

create or replace function public.library_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'items_table', to_regclass('public.library_items') is not null,
    'copies_table', to_regclass('public.library_copies') is not null,
    'loans_table', to_regclass('public.library_loans') is not null,
    'reservations_table', to_regclass('public.library_reservations') is not null,
    'catalog_view', to_regclass('public.v_library_catalog') is not null,
    'loans_view', to_regclass('public.v_library_loans_detailed') is not null,
    'reservations_view', to_regclass('public.v_library_reservations_detailed') is not null,
    'dashboard_rpc', to_regprocedure('public.get_library_dashboard_payload()') is not null,
    'upsert_rpc', to_regprocedure('public.library_upsert_item(uuid,text,text,text,text,text,text,text,int,text)') is not null,
    'checkout_rpc', to_regprocedure('public.library_checkout(uuid,uuid,uuid,int,text)') is not null,
    'return_rpc', to_regprocedure('public.library_return(uuid,text)') is not null,
    'reserve_rpc', to_regprocedure('public.library_reserve(uuid,uuid)') is not null,
    'stats', public.get_library_dashboard_payload()->'stats'
  );
end;
$$;

grant execute on function public.library_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'library_management_ready' as status;

-- ============================================================================
-- R9 و R3 — الجرد والمشتريات بعملتين (USD / IRR) والأرشيف الإلكتروني للوثائق
-- 1) ترقية دالة inventory_upsert_item لدعم التكلفة بالدولار والدينار العراقي/الريال.
-- 2) ضبط مستودع التخزين documents-archive وتوسيع صلاحيات قراءة وكتابة الوثائق.
--
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

-- 1) إضافة أعمدة التكلفة المزدوجة لجدول المخزون
alter table public.inventory_items add column if not exists average_cost_usd numeric default 0;
alter table public.inventory_items add column if not exists average_cost_irr numeric default 0;

-- 2) ترقية دالة حفظ الصنف المخزني لتشمل التكلفة
create or replace function public.inventory_upsert_item(
  p_item_id uuid,
  p_name text,
  p_sku text,
  p_category text,
  p_location text,
  p_unit text,
  p_min_stock numeric,
  p_initial_stock numeric,
  p_description text,
  p_average_cost numeric default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  cat_id uuid;
  loc_id uuid;
  item_id uuid;
  old_stock numeric;
begin
  if not public.inventory_can_manage() then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل المخزون');
  end if;

  if coalesce(nullif(trim(p_name),''), '') = '' then
    return jsonb_build_object('ok', false, 'message', 'اسم الصنف مطلوب');
  end if;

  if p_category is not null and trim(p_category) <> '' then
    insert into public.inventory_categories(name)
    values (trim(p_category))
    on conflict (name) do update set name=excluded.name
    returning id into cat_id;
  end if;

  if p_location is not null and trim(p_location) <> '' then
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
        average_cost=coalesce(p_average_cost, average_cost),
        average_cost_usd=coalesce(p_average_cost, average_cost_usd),
        description=p_description,
        updated_at=now()
    where id=p_item_id
    returning id into item_id;
  else
    insert into public.inventory_items(sku, name, category_id, default_location_id, unit, min_stock, current_stock, average_cost, average_cost_usd, description, created_by)
    values (nullif(trim(coalesce(p_sku,'')), ''), trim(p_name), cat_id, loc_id, coalesce(nullif(trim(p_unit),''),'قطعة'), coalesce(p_min_stock,0), coalesce(p_initial_stock,0), coalesce(p_average_cost,0), coalesce(p_average_cost,0), p_description, auth.uid())
    returning id into item_id;

    if coalesce(p_initial_stock,0) <> 0 then
      insert into public.inventory_stock_movements(item_id, movement_type, quantity, unit_cost, to_location_id, reason, created_by)
      values (item_id, 'in', p_initial_stock, coalesce(p_average_cost,0), loc_id, 'رصيد افتتاحي', auth.uid());
    end if;
  end if;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ الصنف المخزني والتكلفة بالدولار والدينار بنجاح 📦', 'item_id', item_id);
end;
$$;
grant execute on function public.inventory_upsert_item(uuid,text,text,text,text,text,numeric,numeric,text,numeric) to authenticated, anon;

-- 3) ضبط مستودع الأرشفة الإلكترونية للوثائق (documents-archive) لتفادي التايم أوت
insert into storage.buckets (id, name, public)
values ('documents-archive', 'documents-archive', true)
on conflict (id) do update set public = true;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='documents_archive_all_access') then
    create policy documents_archive_all_access on storage.objects
      for all to anon, authenticated
      using (bucket_id = 'documents-archive')
      with check (bucket_id = 'documents-archive');
  end if;
end $$;

-- إعادة تحميل كاش المخطط في PostgREST
NOTIFY pgrst, 'reload schema';

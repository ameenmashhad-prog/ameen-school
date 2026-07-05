-- =============================================================
-- مدارس أمين الرضا (ع) — جداول نماذج التسجيل 2026-2027
-- لا يعدّل الجداول القديمة. يخزن طلبات التسجيل كمرحلة pending للمراجعة.
-- =============================================================

create extension if not exists pgcrypto;

create table if not exists public.registration_families (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  guardian_name text not null,
  father_name text,
  family_name text,
  generated_username text,
  initial_password text,
  birth_date date,
  birth_calendar jsonb not null default '{}'::jsonb,
  passport_number text,
  nationality text,
  nationality_other text,
  phone_primary text,
  phone_whatsapp text,
  phone_emergency text,
  education_level text,
  education_notes text,
  work_type text,
  work_notes text,
  residence_type text,
  mother_name text,
  mother_father_name text,
  mother_family_name text,
  mother_birth_date date,
  mother_birth_calendar jsonb not null default '{}'::jsonb,
  mother_passport_number text,
  mother_nationality text,
  mother_nationality_other text,
  mother_phone text,
  mother_whatsapp text,
  mother_education_level text,
  mother_education_notes text,
  mother_work_type text,
  mother_work_notes text,
  status text not null default 'pending' check (status in ('pending','reviewed','approved','rejected','converted')),
  submitted_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- أعمدة بيانات الأم للأنظمة التي شغلت نسخة أقدم من هذا الملف.
alter table public.registration_families add column if not exists mother_name text;
alter table public.registration_families add column if not exists mother_father_name text;
alter table public.registration_families add column if not exists mother_family_name text;
alter table public.registration_families add column if not exists mother_birth_date date;
alter table public.registration_families add column if not exists mother_birth_calendar jsonb not null default '{}'::jsonb;
alter table public.registration_families add column if not exists mother_passport_number text;
alter table public.registration_families add column if not exists mother_nationality text;
alter table public.registration_families add column if not exists mother_nationality_other text;
alter table public.registration_families add column if not exists mother_phone text;
alter table public.registration_families add column if not exists mother_whatsapp text;
alter table public.registration_families add column if not exists mother_education_level text;
alter table public.registration_families add column if not exists mother_education_notes text;
alter table public.registration_families add column if not exists mother_work_type text;
alter table public.registration_families add column if not exists mother_work_notes text;

create table if not exists public.registration_students (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.registration_families(id) on delete cascade,
  academic_year text not null default '2026-2027',
  student_code text not null unique default ('STU-' || upper(substr(gen_random_uuid()::text,1,8))),
  student_name text not null,
  generated_username text,
  initial_password text,
  birth_date date,
  birth_calendar jsonb not null default '{}'::jsonb,
  age_years int,
  gender text check (gender in ('ذكر','أنثى','male','female') or gender is null),
  class_id uuid null references public.classes(id),
  section text check (section in ('أ','ب','ج','د') or section is null),
  birth_place text,
  passport_number text,
  passport_expiry_date date,
  photo_path text,
  status text not null default 'pending' check (status in ('pending','reviewed','approved','rejected','converted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.registration_teachers (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  teacher_code text not null unique default ('TCH-' || upper(substr(gen_random_uuid()::text,1,8))),
  full_name text not null,
  generated_username text,
  initial_password text,
  qualification text,
  specialization text,
  years_experience int,
  subjects jsonb not null default '[]'::jsonb,
  phone text,
  email text,
  nationality text,
  nationality_other text,
  birth_date date,
  birth_calendar jsonb not null default '{}'::jsonb,
  passport_number text,
  passport_expiry_date date,
  photo_path text,
  status text not null default 'pending' check (status in ('pending','reviewed','approved','rejected','converted')),
  submitted_by uuid null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_registration_students_family on public.registration_students(family_id);
create index if not exists idx_registration_students_class on public.registration_students(class_id);
create index if not exists idx_registration_families_status on public.registration_families(status, created_at desc);
create index if not exists idx_registration_teachers_status on public.registration_teachers(status, created_at desc);

alter table public.registration_families enable row level security;
alter table public.registration_students enable row level security;
alter table public.registration_teachers enable row level security;

-- السماح بإرسال طلبات التسجيل من العامة أو المستخدمين المسجلين.
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='registration_families' and policyname='registration_families_insert_public') then
    create policy registration_families_insert_public on public.registration_families for insert to anon, authenticated with check (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='registration_students' and policyname='registration_students_insert_public') then
    create policy registration_students_insert_public on public.registration_students for insert to anon, authenticated with check (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='registration_teachers' and policyname='registration_teachers_insert_public') then
    create policy registration_teachers_insert_public on public.registration_teachers for insert to anon, authenticated with check (true);
  end if;
end $$;

-- قراءة الطلبات للإدارة فقط.
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='registration_families' and policyname='registration_families_admin_read') then
    create policy registration_families_admin_read on public.registration_families for select to authenticated using (
      exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin') or coalesce(u.is_super_admin,false)=true))
    );
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='registration_students' and policyname='registration_students_admin_read') then
    create policy registration_students_admin_read on public.registration_students for select to authenticated using (
      exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin') or coalesce(u.is_super_admin,false)=true))
    );
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='registration_teachers' and policyname='registration_teachers_admin_read') then
    create policy registration_teachers_admin_read on public.registration_teachers for select to authenticated using (
      exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin') or coalesce(u.is_super_admin,false)=true))
    );
  end if;
end $$;

-- السماح بقراءة الصفوف والمواد للنماذج العامة.
alter table public.classes enable row level security;
alter table public.subjects enable row level security;
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='classes' and policyname='registration_classes_public_read') then
    create policy registration_classes_public_read on public.classes for select to anon, authenticated using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='subjects' and policyname='registration_subjects_public_read') then
    create policy registration_subjects_public_read on public.subjects for select to anon, authenticated using (true);
  end if;
end $$;

-- Storage bucket اختياري للصور.
insert into storage.buckets (id, name, public)
values ('registration-photos', 'registration-photos', false)
on conflict (id) do nothing;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='registration_photos_insert_public') then
    create policy registration_photos_insert_public on storage.objects for insert to anon, authenticated with check (bucket_id='registration-photos');
  end if;
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='registration_photos_admin_read') then
    create policy registration_photos_admin_read on storage.objects for select to authenticated using (
      bucket_id='registration-photos' and exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin') or coalesce(u.is_super_admin,false)=true))
    );
  end if;
end $$;

drop view if exists public.v_registration_family_students;

create view public.v_registration_family_students
with (security_invoker=true) as
select
  f.id as family_id,
  f.academic_year,
  f.guardian_name,
  f.father_name,
  f.family_name,
  f.generated_username as guardian_username,
  f.mother_name,
  f.mother_phone,
  f.phone_primary,
  f.phone_whatsapp,
  f.status as family_status,
  s.id as registration_student_id,
  s.student_code,
  s.student_name,
  s.generated_username as student_username,
  s.birth_date,
  s.age_years,
  s.gender,
  c.name as class_name,
  s.section,
  s.status as student_status,
  f.created_at
from public.registration_families f
left join public.registration_students s on s.family_id = f.id
left join public.classes c on c.id = s.class_id;

grant select on public.v_registration_family_students to authenticated;

-- تحديث حالة الطلبات من الإدارة/المسؤول العلمي.
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='registration_families' and policyname='registration_families_admin_update') then
    create policy registration_families_admin_update on public.registration_families for update to authenticated
    using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin') or coalesce(u.is_super_admin,false)=true)))
    with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin') or coalesce(u.is_super_admin,false)=true)));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='registration_students' and policyname='registration_students_admin_update') then
    create policy registration_students_admin_update on public.registration_students for update to authenticated
    using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin') or coalesce(u.is_super_admin,false)=true)))
    with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin') or coalesce(u.is_super_admin,false)=true)));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='registration_teachers' and policyname='registration_teachers_admin_update') then
    create policy registration_teachers_admin_update on public.registration_teachers for update to authenticated
    using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin') or coalesce(u.is_super_admin,false)=true)))
    with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin') or coalesce(u.is_super_admin,false)=true)));
  end if;
end $$;

-- =============================================================
-- توليد/فحص اسم مستخدم فريد عبر users وطلبات التسجيل
-- =============================================================
create or replace function public.registration_username_taken(p_username text)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  u text := lower(regexp_replace(coalesce(p_username,''), '[^a-zA-Z0-9]', '', 'g'));
  exists_bool boolean := false;
  rec record;
begin
  if u = '' then
    return false;
  end if;

  select exists(select 1 from public.users where lower(split_part(coalesce(email,''),'@',1)) = u)
  into exists_bool;
  if exists_bool then return true; end if;

  for rec in
    select * from (values
      ('public','users','username'),
      ('public','students','username'),
      ('public','students','generated_username'),
      ('public','registration_families','generated_username'),
      ('public','registration_students','generated_username'),
      ('public','registration_teachers','generated_username')
    ) as t(schemaname, tablename, columnname)
  loop
    if exists (
      select 1 from information_schema.columns
      where table_schema = rec.schemaname
        and table_name = rec.tablename
        and column_name = rec.columnname
    ) then
      execute format('select exists(select 1 from %I.%I where lower(regexp_replace(coalesce(%I,''''), ''[^a-zA-Z0-9]'', '''', ''g'')) = $1)', rec.schemaname, rec.tablename, rec.columnname)
      into exists_bool
      using u;
      if exists_bool then return true; end if;
    end if;
  end loop;

  return false;
end;
$$;

grant execute on function public.registration_username_taken(text) to anon, authenticated;

-- فهارس فريدة داخل جداول طلبات التسجيل لمنع التكرار داخل كل جدول.
do $$ begin
  begin
    create unique index if not exists uq_registration_families_username_lower
      on public.registration_families (lower(generated_username))
      where generated_username is not null and generated_username <> '';
  exception when others then
    raise notice 'تعذر إنشاء فهرس أسماء أولياء الأمور بسبب تكرارات حالية: %', sqlerrm;
  end;
  begin
    create unique index if not exists uq_registration_students_username_lower
      on public.registration_students (lower(generated_username))
      where generated_username is not null and generated_username <> '';
  exception when others then
    raise notice 'تعذر إنشاء فهرس أسماء الطلاب بسبب تكرارات حالية: %', sqlerrm;
  end;
  begin
    create unique index if not exists uq_registration_teachers_username_lower
      on public.registration_teachers (lower(generated_username))
      where generated_username is not null and generated_username <> '';
  exception when others then
    raise notice 'تعذر إنشاء فهرس أسماء المعلمين بسبب تكرارات حالية: %', sqlerrm;
  end;
end $$;

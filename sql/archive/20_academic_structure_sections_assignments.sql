-- =============================================================
-- مدارس أمين الرضا (ع) — بنية الشعب والربط الأكاديمي
-- Academic Year → Term → Class → Section → Subject → Session → Teacher → Student
-- Additive migration: لا يحذف بيانات.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) الأعوام الدراسية
-- -------------------------------------------------------------
create table if not exists public.academic_years (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  start_date date,
  end_date date,
  is_current boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.academic_years (name, start_date, end_date, is_current)
values ('2026-2027', date '2026-09-01', date '2027-05-31', true)
on conflict (name) do update
set start_date = excluded.start_date,
    end_date = excluded.end_date,
    is_current = true;

-- ربط academic_periods بالعام الدراسي إن أمكن
alter table public.academic_periods add column if not exists academic_year_id uuid null references public.academic_years(id) on delete set null;
alter table public.academic_periods add column if not exists academic_year text not null default '2026-2027';

update public.academic_periods ap
set academic_year_id = ay.id,
    academic_year = ay.name
from public.academic_years ay
where ay.name = '2026-2027'
  and (ap.name like '%2026/2027%' or ap.academic_year = '2026-2027')
  and (ap.academic_year_id is null or ap.academic_year is distinct from ay.name);

-- -------------------------------------------------------------
-- 2) الشعب الدراسية Sections
-- -------------------------------------------------------------
create table if not exists public.sections (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  class_id uuid not null references public.classes(id) on delete cascade,
  code text not null, -- أ / ب / ج / د
  name text not null,
  capacity int,
  gender_policy text default 'mixed' check (gender_policy in ('mixed','male','female')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(academic_year, class_id, code)
);

-- إنشاء شعب أ، ب، ج، د لكل صف للسنة الحالية إن لم تكن موجودة.
insert into public.sections (academic_year, class_id, code, name)
select '2026-2027', c.id, x.code, c.name || ' — شعبة ' || x.code
from public.classes c
cross join (values ('أ'),('ب'),('ج'),('د')) as x(code)
on conflict (academic_year, class_id, code) do nothing;

-- -------------------------------------------------------------
-- 3) ربط الطلاب بالشعب Enrollments
-- -------------------------------------------------------------
alter table public.students add column if not exists section_id uuid null references public.sections(id) on delete set null;
alter table public.students add column if not exists academic_year text not null default '2026-2027';

create table if not exists public.student_enrollments (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  section_id uuid not null references public.sections(id) on delete cascade,
  enrollment_status text not null default 'active' check (enrollment_status in ('active','transferred','withdrawn','graduated','pending')),
  enrollment_date date not null default current_date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(academic_year, student_id)
);

-- وضع الطلاب الحاليين في شعبة أ افتراضياً حسب صفهم.
update public.students s
set section_id = sec.id,
    academic_year = '2026-2027'
from public.sections sec
where sec.academic_year = '2026-2027'
  and sec.code = 'أ'
  and sec.class_id = s.class_id
  and s.section_id is null
  and s.class_id is not null;

insert into public.student_enrollments (academic_year, student_id, class_id, section_id, enrollment_status)
select '2026-2027', s.id, s.class_id, s.section_id, 'active'
from public.students s
where s.class_id is not null
  and s.section_id is not null
on conflict (academic_year, student_id) do update
set class_id = excluded.class_id,
    section_id = excluded.section_id,
    enrollment_status = 'active',
    updated_at = now();

-- -------------------------------------------------------------
-- 4) إسناد المعلمين Teacher Assignments
-- -------------------------------------------------------------
create table if not exists public.teacher_assignments (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  academic_period_id uuid null references public.academic_periods(id) on delete set null,
  teacher_id uuid not null references public.users(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  section_id uuid not null references public.sections(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  weekly_hours numeric default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(academic_year, academic_period_id, teacher_id, section_id, subject_id)
);

alter table public.weekly_schedule add column if not exists section_id uuid null references public.sections(id) on delete set null;
alter table public.weekly_schedule add column if not exists teacher_assignment_id uuid null references public.teacher_assignments(id) on delete set null;

-- ربط كل حصة حالية بشعبة أ إذا لم تكن محددة.
update public.weekly_schedule ws
set section_id = sec.id
from public.sections sec
where sec.academic_year = '2026-2027'
  and sec.code = 'أ'
  and sec.class_id = ws.class_id
  and ws.section_id is null
  and ws.class_id is not null;

-- توليد إسنادات المعلمين من الجدول الأسبوعي الحالي.
insert into public.teacher_assignments (
  academic_year,
  academic_period_id,
  teacher_id,
  class_id,
  section_id,
  subject_id,
  weekly_hours
)
select
  '2026-2027',
  ws.academic_period_id,
  ws.teacher_id,
  ws.class_id,
  ws.section_id,
  ws.subject_id,
  count(*)::numeric as weekly_hours
from public.weekly_schedule ws
where ws.teacher_id is not null
  and ws.class_id is not null
  and ws.section_id is not null
  and ws.subject_id is not null
group by ws.academic_period_id, ws.teacher_id, ws.class_id, ws.section_id, ws.subject_id
on conflict (academic_year, academic_period_id, teacher_id, section_id, subject_id) do update
set class_id = excluded.class_id,
    weekly_hours = excluded.weekly_hours,
    is_active = true,
    updated_at = now();

-- ربط weekly_schedule بالإسناد المناسب.
update public.weekly_schedule ws
set teacher_assignment_id = ta.id
from public.teacher_assignments ta
where ta.academic_year = '2026-2027'
  and ta.teacher_id = ws.teacher_id
  and ta.section_id = ws.section_id
  and ta.subject_id = ws.subject_id
  and (ta.academic_period_id is not distinct from ws.academic_period_id)
  and ws.teacher_assignment_id is null;

-- -------------------------------------------------------------
-- 5) دوال الصلاحيات بالنطاق Scope Access
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

create or replace function public.teacher_can_access_section_subject(p_section_id uuid, p_subject_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.current_user_is_admin()
    or exists(
      select 1
      from public.teacher_assignments ta
      where ta.teacher_id = auth.uid()
        and ta.section_id = p_section_id
        and (p_subject_id is null or ta.subject_id = p_subject_id)
        and ta.is_active = true
    );
$$;

create or replace function public.teacher_can_access_student(p_student_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.current_user_is_admin()
    or exists(
      select 1
      from public.student_enrollments se
      join public.teacher_assignments ta
        on ta.section_id = se.section_id
       and ta.academic_year = se.academic_year
       and ta.is_active = true
      where se.student_id = p_student_id
        and se.enrollment_status = 'active'
        and ta.teacher_id = auth.uid()
    );
$$;

grant execute on function public.current_user_is_admin() to authenticated;
grant execute on function public.teacher_can_access_section_subject(uuid,uuid) to authenticated;
grant execute on function public.teacher_can_access_student(uuid) to authenticated;

-- -------------------------------------------------------------
-- 6) Views عملية للمعلم والإدارة
-- -------------------------------------------------------------
create or replace view public.v_teacher_assignments
with (security_invoker=true) as
select
  ta.id as teacher_assignment_id,
  ta.academic_year,
  ta.academic_period_id,
  ap.name as academic_period_name,
  ta.teacher_id,
  u.name as teacher_name,
  ta.class_id,
  c.name as class_name,
  ta.section_id,
  sec.code as section_code,
  sec.name as section_name,
  ta.subject_id,
  sub.name as subject_name,
  ta.weekly_hours,
  ta.is_active
from public.teacher_assignments ta
left join public.users u on u.id = ta.teacher_id
left join public.classes c on c.id = ta.class_id
left join public.sections sec on sec.id = ta.section_id
left join public.subjects sub on sub.id = ta.subject_id
left join public.academic_periods ap on ap.id = ta.academic_period_id
where public.current_user_is_admin()
   or ta.teacher_id = auth.uid();

create or replace view public.v_teacher_students
with (security_invoker=true) as
select distinct
  s.id as student_id,
  s.name as student_name,
  s.gender,
  s.father_name,
  s.mother_name,
  s.last_name,
  se.academic_year,
  se.class_id,
  c.name as class_name,
  se.section_id,
  sec.code as section_code,
  sec.name as section_name,
  ta.teacher_id
from public.student_enrollments se
join public.students s on s.id = se.student_id
left join public.classes c on c.id = se.class_id
left join public.sections sec on sec.id = se.section_id
join public.teacher_assignments ta
  on ta.section_id = se.section_id
 and ta.academic_year = se.academic_year
 and ta.is_active = true
where se.enrollment_status = 'active'
  and (public.current_user_is_admin() or ta.teacher_id = auth.uid());

create or replace view public.v_teacher_schedule
with (security_invoker=true) as
select
  ws.id,
  ws.academic_period_id,
  ap.name as academic_period_name,
  ws.class_id,
  c.name as class_name,
  ws.section_id,
  sec.code as section_code,
  sec.name as section_name,
  ws.subject_id,
  sub.name as subject_name,
  ws.teacher_id,
  u.name as teacher_name,
  ws.day,
  ws.period_number,
  ws.teacher_assignment_id
from public.weekly_schedule ws
left join public.academic_periods ap on ap.id = ws.academic_period_id
left join public.classes c on c.id = ws.class_id
left join public.sections sec on sec.id = ws.section_id
left join public.subjects sub on sub.id = ws.subject_id
left join public.users u on u.id = ws.teacher_id
where public.current_user_is_admin()
   or ws.teacher_id = auth.uid()
   or exists(
     select 1 from public.teacher_assignments ta
     where ta.id = ws.teacher_assignment_id
       and ta.teacher_id = auth.uid()
   );

create or replace view public.v_section_roster
with (security_invoker=true) as
select
  se.academic_year,
  se.class_id,
  c.name as class_name,
  se.section_id,
  sec.code as section_code,
  sec.name as section_name,
  s.id as student_id,
  s.name as student_name,
  s.gender,
  se.enrollment_status
from public.student_enrollments se
join public.students s on s.id = se.student_id
left join public.classes c on c.id = se.class_id
left join public.sections sec on sec.id = se.section_id;

grant select on public.v_teacher_assignments to authenticated;
grant select on public.v_teacher_students to authenticated;
grant select on public.v_teacher_schedule to authenticated;
grant select on public.v_section_roster to authenticated;
grant select, insert, update on public.sections to authenticated;
grant select, insert, update on public.student_enrollments to authenticated;
grant select, insert, update on public.teacher_assignments to authenticated;

-- -------------------------------------------------------------
-- 7) RLS إضافي آمن حسب الإسناد
-- -------------------------------------------------------------
alter table public.sections enable row level security;
alter table public.student_enrollments enable row level security;
alter table public.teacher_assignments enable row level security;
alter table public.students enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='sections' and policyname='sections_read_authenticated') then
    create policy sections_read_authenticated on public.sections for select to authenticated using (true);
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='student_enrollments' and policyname='student_enrollments_read_scope') then
    create policy student_enrollments_read_scope on public.student_enrollments
      for select to authenticated
      using (
        public.current_user_is_admin()
        or exists(
          select 1 from public.teacher_assignments ta
          where ta.section_id = student_enrollments.section_id
            and ta.academic_year = student_enrollments.academic_year
            and ta.teacher_id = auth.uid()
            and ta.is_active = true
        )
        or exists(
          select 1 from public.students s
          where s.id = student_enrollments.student_id
            and (s.user_id = auth.uid() or s.parent_id = auth.uid())
        )
      );
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='teacher_assignments' and policyname='teacher_assignments_read_scope') then
    create policy teacher_assignments_read_scope on public.teacher_assignments
      for select to authenticated
      using (public.current_user_is_admin() or teacher_id = auth.uid());
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='students' and policyname='students_read_assignment_scope') then
    create policy students_read_assignment_scope on public.students
      for select to authenticated
      using (
        public.current_user_is_admin()
        or public.teacher_can_access_student(id)
        or user_id = auth.uid()
        or parent_id = auth.uid()
      );
  end if;
end $$;

-- -------------------------------------------------------------
-- 8) تقرير نتيجة التنفيذ
-- -------------------------------------------------------------
select
  (select count(*) from public.sections where academic_year='2026-2027') as sections_count,
  (select count(*) from public.student_enrollments where academic_year='2026-2027') as enrollments_count,
  (select count(*) from public.teacher_assignments where academic_year='2026-2027') as teacher_assignments_count;

notify pgrst, 'reload schema';

-- =============================================================
-- مدارس أمين الرضا (ع) — إدارة الشعب وإسنادات المعلمين
-- يكمل بنية sections / student_enrollments / teacher_assignments
-- ويجعل weekly_schedule يعتمد على section_id عند وجود الشعب.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) ضمان الأعمدة الأساسية
-- -------------------------------------------------------------
alter table public.students add column if not exists section_id uuid null references public.sections(id) on delete set null;
alter table public.students add column if not exists academic_year text not null default '2026-2027';
alter table public.weekly_schedule add column if not exists section_id uuid null references public.sections(id) on delete set null;
alter table public.weekly_schedule add column if not exists teacher_assignment_id uuid null references public.teacher_assignments(id) on delete set null;

-- -------------------------------------------------------------
-- 2) تعديل قيود التكرار في weekly_schedule لتدعم الشعب
-- -------------------------------------------------------------
do $$
begin
  -- القيد القديم الذي كان يمنع شعبتين من نفس الصف أن يكون لهما نفس اليوم/الحصة.
  alter table public.weekly_schedule drop constraint if exists weekly_schedule_academic_period_id_class_id_day_period_numb_key;
exception when others then
  raise notice 'تعذر حذف قيد weekly_schedule القديم: %', sqlerrm;
end $$;

drop index if exists public.uniq_weekly_schedule_class_slot;
drop index if exists public.uniq_weekly_schedule_section_slot;
drop index if exists public.uniq_weekly_schedule_class_slot_no_section;

-- يمنع تكرار الحصة داخل نفس الشعبة.
do $$ begin
  begin
    create unique index uniq_weekly_schedule_section_slot
      on public.weekly_schedule(academic_period_id, section_id, day, period_number)
      where academic_period_id is not null
        and section_id is not null
        and day is not null
        and period_number is not null;
  exception when others then
    raise notice 'تعذر إنشاء unique للشعبة في weekly_schedule، قد توجد تكرارات: %', sqlerrm;
  end;
end $$;

-- fallback للحصص القديمة التي لا تملك section_id.
do $$ begin
  begin
    create unique index uniq_weekly_schedule_class_slot_no_section
      on public.weekly_schedule(academic_period_id, class_id, day, period_number)
      where academic_period_id is not null
        and section_id is null
        and class_id is not null
        and day is not null
        and period_number is not null;
  exception when others then
    raise notice 'تعذر إنشاء unique للصف دون شعبة في weekly_schedule: %', sqlerrm;
  end;
end $$;

-- -------------------------------------------------------------
-- 3) RLS للإدارة/المسؤول العلمي لإدارة الشعب والإسنادات
-- -------------------------------------------------------------
alter table public.sections enable row level security;
alter table public.student_enrollments enable row level security;
alter table public.teacher_assignments enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='sections' and policyname='sections_admin_write') then
    create policy sections_admin_write on public.sections
      for all to authenticated
      using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)))
      with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)));
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='student_enrollments' and policyname='student_enrollments_admin_write') then
    create policy student_enrollments_admin_write on public.student_enrollments
      for all to authenticated
      using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)))
      with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)));
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='teacher_assignments' and policyname='teacher_assignments_admin_write') then
    create policy teacher_assignments_admin_write on public.teacher_assignments
      for all to authenticated
      using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)))
      with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)));
  end if;
end $$;

-- -------------------------------------------------------------
-- 4) دالة نقل طالب بين الشعب
-- -------------------------------------------------------------
create or replace function public.move_student_to_section(
  p_student_id uuid,
  p_section_id uuid,
  p_academic_year text default '2026-2027'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  sec record;
begin
  if not exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)) then
    return jsonb_build_object('ok',false,'message','ليست لديك صلاحية نقل الطلاب بين الشعب');
  end if;

  select * into sec from public.sections where id = p_section_id;
  if sec.id is null then
    return jsonb_build_object('ok',false,'message','الشعبة غير موجودة');
  end if;

  update public.students
  set section_id = sec.id,
      class_id = sec.class_id,
      academic_year = p_academic_year
  where id = p_student_id;

  insert into public.student_enrollments (academic_year, student_id, class_id, section_id, enrollment_status)
  values (p_academic_year, p_student_id, sec.class_id, sec.id, 'active')
  on conflict (academic_year, student_id) do update
  set class_id = excluded.class_id,
      section_id = excluded.section_id,
      enrollment_status = 'active',
      updated_at = now();

  return jsonb_build_object('ok',true,'message','تم نقل الطالب إلى الشعبة');
end;
$$;

grant execute on function public.move_student_to_section(uuid,uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 5) دالة إسناد معلم إلى شعبة/مادة
-- -------------------------------------------------------------
create or replace function public.upsert_teacher_assignment(
  p_teacher_id uuid,
  p_section_id uuid,
  p_subject_id uuid,
  p_academic_period_id uuid default null,
  p_academic_year text default '2026-2027'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  sec record;
  assignment_id uuid;
begin
  if not exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)) then
    return jsonb_build_object('ok',false,'message','ليست لديك صلاحية إسناد المعلمين');
  end if;

  select * into sec from public.sections where id = p_section_id;
  if sec.id is null then
    return jsonb_build_object('ok',false,'message','الشعبة غير موجودة');
  end if;

  insert into public.teacher_assignments (
    academic_year,
    academic_period_id,
    teacher_id,
    class_id,
    section_id,
    subject_id,
    weekly_hours,
    is_active
  ) values (
    p_academic_year,
    p_academic_period_id,
    p_teacher_id,
    sec.class_id,
    sec.id,
    p_subject_id,
    0,
    true
  )
  on conflict (academic_year, academic_period_id, teacher_id, section_id, subject_id) do update
  set is_active = true,
      updated_at = now()
  returning id into assignment_id;

  return jsonb_build_object('ok',true,'message','تم حفظ إسناد المعلم','teacher_assignment_id',assignment_id);
end;
$$;

grant execute on function public.upsert_teacher_assignment(uuid,uuid,uuid,uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 6) Views موسعة للإدارة
-- -------------------------------------------------------------
create or replace view public.v_sections_admin
with (security_invoker=true) as
select
  sec.id as section_id,
  sec.academic_year,
  sec.class_id,
  c.name as class_name,
  sec.code,
  sec.name as section_name,
  sec.capacity,
  sec.gender_policy,
  sec.is_active,
  count(se.student_id) filter (where se.enrollment_status='active') as students_count
from public.sections sec
left join public.classes c on c.id = sec.class_id
left join public.student_enrollments se on se.section_id = sec.id and se.academic_year = sec.academic_year
group by sec.id, sec.academic_year, sec.class_id, c.name, sec.code, sec.name, sec.capacity, sec.gender_policy, sec.is_active;

grant select on public.v_sections_admin to authenticated;

notify pgrst, 'reload schema';

select
  (select count(*) from public.sections where academic_year='2026-2027') as sections_count,
  (select count(*) from public.student_enrollments where academic_year='2026-2027') as enrollments_count,
  (select count(*) from public.teacher_assignments where academic_year='2026-2027') as teacher_assignments_count;

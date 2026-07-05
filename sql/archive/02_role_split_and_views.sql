-- =============================================================
-- مدارس أمين الرضا (ع) — تطوير قاعدة البيانات للواجهات النظيفة
-- الغرض:
-- 1) إضافة أدوار إدارية منفصلة مثل academic/counselor عند الحاجة.
-- 2) إضافة فهارس و Views مساعدة للأداء والتقارير.
-- 3) لا يحذف أي بيانات مدرسية.
--
-- شغّليه في Supabase SQL Editor بعد أخذ نسخة احتياطية من schema.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) توسيع قيد users.role ليقبل الأدوار الجديدة
-- ملاحظة: هذا الجزء يحذف فقط CHECK constraint الخاص بالدور إذا وجد، ثم يعيد إنشاءه.
-- لا يلمس بيانات users.
-- -------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.users'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%role%'
  loop
    execute format('alter table public.users drop constraint if exists %I', r.conname);
  end loop;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.users'::regclass
      and conname = 'users_role_clean_portals_check'
  ) then
    alter table public.users
      add constraint users_role_clean_portals_check
      check (
        role in (
          'admin',
          'finance',
          'discipline',
          'counselor',
          'psychologist',
          'academic',
          'scientific',
          'academic_supervisor',
          'academic_admin',
          'educational',
          'education',
          'supervisor',
          'teacher',
          'parent',
          'student'
        )
      );
  end if;
end $$;

-- -------------------------------------------------------------
-- 2) فهارس أداء مفيدة للواجهات
-- -------------------------------------------------------------
create index if not exists idx_students_class_id on public.students(class_id);
create index if not exists idx_students_parent_id on public.students(parent_id);
create index if not exists idx_students_user_id on public.students(user_id);
create index if not exists idx_student_fees_student_id on public.student_fees(student_id);
create index if not exists idx_student_installments_fee_id on public.student_installments(student_fee_id);
create index if not exists idx_fee_payments_fee_id on public.fee_payments(student_fee_id);
do $$ begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='fee_payments' and column_name='student_installment_id') then
    create index if not exists idx_fee_payments_installment_id on public.fee_payments(student_installment_id);
  end if;
end $$;
create index if not exists idx_attendance_student_date on public.attendance(student_id, date);
create index if not exists idx_behavior_records_student_id on public.behavior_records(student_id);
create index if not exists idx_grades_student_id on public.grades(student_id);
create index if not exists idx_exemptions_student_id on public.exemptions(student_id);
create index if not exists idx_weekly_schedule_class on public.weekly_schedule(class_id);
create index if not exists idx_weekly_schedule_teacher on public.weekly_schedule(teacher_id);

-- قيد فريد اختياري لمنع تكرار حضور اليوم لنفس الطالب ونوع الحضور.
-- إذا عندك تكرارات حالية، قد يفشل. وقتها أرسلي الخطأ وننظف التكرارات أولاً.
do $$
begin
  if not exists (
    select 1 from pg_indexes
    where schemaname='public'
      and indexname='uniq_attendance_student_date_type'
  ) then
    create unique index uniq_attendance_student_date_type
      on public.attendance(student_id, date, attendance_type)
      where student_id is not null and date is not null and attendance_type is not null;
  end if;
exception when others then
  raise notice 'تعذر إنشاء unique index للحضور بسبب وجود تكرارات غالباً: %', sqlerrm;
end $$;

-- -------------------------------------------------------------
-- 3) Views مساعدة للواجهات والتقارير
-- -------------------------------------------------------------

create or replace view public.v_clean_student_overview
with (security_invoker = true) as
select
  s.id as student_id,
  s.name as student_name,
  s.gender,
  s.class_id,
  c.name as class_name,
  s.parent_id,
  s.user_id,
  coalesce(sf.net_amount, sf.base_amount, 0) as fee_net_amount,
  coalesce(sf.total_paid, 0) as fee_total_paid,
  greatest(coalesce(sf.net_amount, sf.base_amount, 0) - coalesce(sf.total_paid, 0), 0) as fee_remaining,
  sf.status as fee_status,
  (
    select count(*)
    from public.attendance a
    where a.student_id = s.id
      and a.status = 'absent'
  ) as absence_count,
  (
    select round(avg(coalesce(g.score, g.grade, g.mark, g.value)::numeric), 2)
    from public.grades g
    where g.student_id = s.id
  ) as grade_average,
  exists (
    select 1
    from public.exemptions e
    where e.student_id = s.id
      and coalesce(e.is_active, true) = true
  ) as has_active_exemption
from public.students s
left join public.classes c on c.id = s.class_id
left join public.student_fees sf on sf.student_id = s.id;

create or replace view public.v_clean_finance_summary
with (security_invoker = true) as
select
  count(*) as fee_records,
  coalesce(sum(coalesce(net_amount, base_amount, 0)), 0) as total_net,
  coalesce(sum(coalesce(total_paid, 0)), 0) as total_paid,
  greatest(coalesce(sum(coalesce(net_amount, base_amount, 0)), 0) - coalesce(sum(coalesce(total_paid, 0)), 0), 0) as total_remaining,
  count(*) filter (where coalesce(total_paid,0) >= coalesce(net_amount, base_amount, 0) and coalesce(net_amount, base_amount, 0) > 0) as paid_count,
  count(*) filter (where coalesce(total_paid,0) > 0 and coalesce(total_paid,0) < coalesce(net_amount, base_amount, 0)) as partial_count,
  count(*) filter (where coalesce(total_paid,0) = 0) as unpaid_count
from public.student_fees;

create or replace view public.v_clean_attendance_today
with (security_invoker = true) as
select
  a.date,
  count(*) as records,
  count(*) filter (where a.status = 'present') as present_count,
  count(*) filter (where a.status = 'absent') as absent_count,
  count(*) filter (where a.status = 'late') as late_count
from public.attendance a
where a.date = current_date
group by a.date;

create or replace view public.v_clean_academic_summary
with (security_invoker = true) as
select
  s.id as student_id,
  s.name as student_name,
  c.name as class_name,
  round(avg(coalesce(g.score, g.grade, g.mark, g.value)::numeric), 2) as grade_average,
  count(g.id) as grade_records,
  count(a.id) filter (where a.status = 'absent') as absence_count,
  count(br.id) as behavior_records,
  exists (
    select 1
    from public.exemptions e
    where e.student_id = s.id
      and coalesce(e.is_active, true) = true
  ) as has_active_exemption
from public.students s
left join public.classes c on c.id = s.class_id
left join public.grades g on g.student_id = s.id
left join public.attendance a on a.student_id = s.id
left join public.behavior_records br on br.student_id = s.id
group by s.id, s.name, c.name;

grant select on public.v_clean_student_overview to authenticated;
grant select on public.v_clean_finance_summary to authenticated;
grant select on public.v_clean_attendance_today to authenticated;
grant select on public.v_clean_academic_summary to authenticated;

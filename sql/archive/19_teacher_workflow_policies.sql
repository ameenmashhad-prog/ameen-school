-- =============================================================
-- مدارس أمين الرضا (ع) — صلاحيات لوحة المعلم وسير العمل العملي
-- الحضور الافتراضي: الطالب حاضر ما لم يثبت غيابه أو تأخيره.
-- الغياب: مبرر / غير مبرر.
-- المعلم يرى/يدخل فقط للصفوف والمواد المرتبطة به في weekly_schedule.
-- =============================================================

create extension if not exists pgcrypto;

-- أعمدة الحضور الحصة-بحصة
alter table public.attendance add column if not exists absence_type text check (absence_type in ('excused','unexcused') or absence_type is null);
alter table public.attendance add column if not exists period_number int;
alter table public.attendance add column if not exists subject_id uuid null references public.subjects(id);
alter table public.attendance add column if not exists attendance_type text not null default 'daily';

-- تعديل فهرس الحضور ليقبل الحضور الحصة-بحصة
-- الفهرس القديم إن وجد كان يمنع تعدد الحصص في نفس اليوم.
drop index if exists public.uniq_attendance_student_date_type;
do $$ begin
  begin
    create unique index if not exists uniq_attendance_student_date_period_type
      on public.attendance(student_id, date, coalesce(period_number,0), attendance_type)
      where student_id is not null and date is not null and attendance_type is not null;
  exception when others then
    raise notice 'تعذر إنشاء فهرس الحضور الجديد بسبب تكرارات حالية: %', sqlerrm;
  end;
end $$;

-- دوال مساعدة للصلاحيات
create or replace function public.is_admin_user()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (u.role = 'admin' or coalesce(u.is_super_admin,false) = true)
  );
$$;

create or replace function public.teacher_has_class_subject(p_class_id uuid, p_subject_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.is_admin_user()
    or exists(
      select 1
      from public.weekly_schedule ws
      where ws.teacher_id = auth.uid()
        and ws.class_id = p_class_id
        and (p_subject_id is null or ws.subject_id = p_subject_id)
    );
$$;

create or replace function public.teacher_has_student(p_student_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.is_admin_user()
    or exists(
      select 1
      from public.students s
      join public.weekly_schedule ws on ws.class_id = s.class_id
      where s.id = p_student_id
        and ws.teacher_id = auth.uid()
    );
$$;

grant execute on function public.is_admin_user() to authenticated;
grant execute on function public.teacher_has_class_subject(uuid,uuid) to authenticated;
grant execute on function public.teacher_has_student(uuid) to authenticated;

-- تفعيل RLS للجداول ذات العلاقة
alter table public.attendance enable row level security;
alter table public.continuous_assessments enable row level security;
alter table public.exams enable row level security;
alter table public.exam_scores enable row level security;
alter table public.homeworks enable row level security;
alter table public.class_sessions enable row level security;
alter table public.weekly_schedule enable row level security;
alter table public.students enable row level security;

-- قراءة الطلاب للمعلم حسب جدوله
-- لا ننشئ policy إذا كانت موجودة بنفس الاسم.
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='students' and policyname='teacher_students_read_by_schedule') then
    create policy teacher_students_read_by_schedule on public.students
      for select to authenticated
      using (public.is_admin_user() or public.teacher_has_student(id) or parent_id = auth.uid() or user_id = auth.uid());
  end if;
end $$;

-- weekly_schedule قراءة للمعلم لجدوله
-- الإدارة تقرأ الكل.
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='weekly_schedule' and policyname='teacher_schedule_read_own') then
    create policy teacher_schedule_read_own on public.weekly_schedule
      for select to authenticated
      using (public.is_admin_user() or teacher_id = auth.uid());
  end if;
end $$;

-- class_sessions قراءة للمعلم لجلساته
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='class_sessions' and policyname='teacher_sessions_read_own') then
    create policy teacher_sessions_read_own on public.class_sessions
      for select to authenticated
      using (public.is_admin_user() or teacher_id = auth.uid());
  end if;
end $$;

-- attendance: قراءة/إدخال/تعديل/حذف للمعلم لطلابه فقط
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='attendance' and policyname='teacher_attendance_read_students') then
    create policy teacher_attendance_read_students on public.attendance
      for select to authenticated
      using (public.is_admin_user() or public.teacher_has_student(student_id));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='attendance' and policyname='teacher_attendance_insert_students') then
    create policy teacher_attendance_insert_students on public.attendance
      for insert to authenticated
      with check (public.is_admin_user() or public.teacher_has_student(student_id));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='attendance' and policyname='teacher_attendance_update_students') then
    create policy teacher_attendance_update_students on public.attendance
      for update to authenticated
      using (public.is_admin_user() or public.teacher_has_student(student_id))
      with check (public.is_admin_user() or public.teacher_has_student(student_id));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='attendance' and policyname='teacher_attendance_delete_students') then
    create policy teacher_attendance_delete_students on public.attendance
      for delete to authenticated
      using (public.is_admin_user() or public.teacher_has_student(student_id));
  end if;
end $$;

-- continuous_assessments: المعلم يكتب فقط لطلابه ومادته
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='continuous_assessments' and policyname='teacher_continuous_read_write') then
    create policy teacher_continuous_read_write on public.continuous_assessments
      for all to authenticated
      using (public.is_admin_user() or public.teacher_has_student(student_id))
      with check (public.is_admin_user() or (public.teacher_has_student(student_id) and public.teacher_has_class_subject(class_id, subject_id)));
  end if;
end $$;

-- exams: المعلم ينشئ اختبارات لمادته وصفوفه
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='exams' and policyname='teacher_exams_read_write') then
    create policy teacher_exams_read_write on public.exams
      for all to authenticated
      using (public.is_admin_user() or teacher_id = auth.uid() or public.teacher_has_class_subject(class_id, subject_id))
      with check (public.is_admin_user() or (teacher_id = auth.uid() and public.teacher_has_class_subject(class_id, subject_id)));
  end if;
end $$;

-- exam_scores: المعلم يدخل درجات الاختبارات التي أنشأها أو تخص مادته
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='exam_scores' and policyname='teacher_exam_scores_read_write') then
    create policy teacher_exam_scores_read_write on public.exam_scores
      for all to authenticated
      using (
        public.is_admin_user()
        or public.teacher_has_student(student_id)
      )
      with check (
        public.is_admin_user()
        or (
          public.teacher_has_student(student_id)
          and exists(select 1 from public.exams e where e.id = exam_id and (e.teacher_id = auth.uid() or public.teacher_has_class_subject(e.class_id, e.subject_id)))
        )
      );
  end if;
end $$;

-- homeworks: المعلم لصفوفه ومواده
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='homeworks' and policyname='teacher_homeworks_read_write') then
    create policy teacher_homeworks_read_write on public.homeworks
      for all to authenticated
      using (public.is_admin_user() or teacher_id = auth.uid() or public.teacher_has_class_subject(class_id, subject_id))
      with check (public.is_admin_user() or (teacher_id = auth.uid() and public.teacher_has_class_subject(class_id, subject_id)));
  end if;
end $$;

notify pgrst, 'reload schema';
select 'teacher_workflow_policies_ok' as status;

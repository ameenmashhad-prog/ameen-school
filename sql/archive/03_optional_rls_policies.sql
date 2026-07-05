-- =============================================================
-- مدارس أمين الرضا (ع) — RLS اختياري حسب تقسيم الواجهات
-- مهم: شغّلي هذا الملف فقط بعد التأكد أن الأدوار في users.role صحيحة.
-- هذا الملف يضيف Policies ولا يحذف بيانات.
-- =============================================================

-- دوال مساعدة آمنة للصلاحيات
create or replace function public.clean_portal_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
  select u.role
  from public.users u
  where u.id = auth.uid()
  limit 1;
$$;

create or replace function public.clean_portal_is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and (u.role = 'admin' or coalesce(u.is_super_admin,false) = true)
  );
$$;

create or replace function public.clean_portal_has_role(roles text[])
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.clean_portal_is_admin()
    or exists (
      select 1
      from public.users u
      where u.id = auth.uid()
        and u.role = any(roles)
    );
$$;

grant execute on function public.clean_portal_role() to authenticated;
grant execute on function public.clean_portal_is_admin() to authenticated;
grant execute on function public.clean_portal_has_role(text[]) to authenticated;

-- Helper لإنشاء policy إذا لم تكن موجودة
-- لا يمكن تعريف CREATE POLICY كدالة بسهولة، لذلك نستخدم DO blocks.

alter table public.students enable row level security;
alter table public.student_fees enable row level security;
alter table public.student_installments enable row level security;
alter table public.fee_payments enable row level security;
alter table public.attendance enable row level security;
alter table public.behavior_records enable row level security;
alter table public.grades enable row level security;
alter table public.exemptions enable row level security;
alter table public.classes enable row level security;
alter table public.subjects enable row level security;
alter table public.weekly_schedule enable row level security;

-- الجداول العامة الأكاديمية: قراءة لكل مستخدم مسجل
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='classes' and policyname='clean_classes_read') then
    create policy clean_classes_read on public.classes for select to authenticated using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='subjects' and policyname='clean_subjects_read') then
    create policy clean_subjects_read on public.subjects for select to authenticated using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='weekly_schedule' and policyname='clean_schedule_read') then
    create policy clean_schedule_read on public.weekly_schedule for select to authenticated using (true);
  end if;
end $$;

-- الطلاب
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='students' and policyname='clean_students_read_by_role') then
    create policy clean_students_read_by_role on public.students
      for select to authenticated
      using (
        public.clean_portal_has_role(array['finance','discipline','counselor','psychologist','academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor','teacher'])
        or parent_id = auth.uid()
        or user_id = auth.uid()
      );
  end if;
end $$;

-- المالية: المسؤول الأعلى والمالي فقط، والطالب/ولي الأمر لبياناته فقط
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='student_fees' and policyname='clean_fees_read_by_role') then
    create policy clean_fees_read_by_role on public.student_fees
      for select to authenticated
      using (
        public.clean_portal_has_role(array['finance'])
        or exists(select 1 from public.students s where s.id = student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
      );
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='student_fees' and policyname='clean_fees_write_finance') then
    create policy clean_fees_write_finance on public.student_fees
      for all to authenticated
      using (public.clean_portal_has_role(array['finance']))
      with check (public.clean_portal_has_role(array['finance']));
  end if;
end $$;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='student_installments' and policyname='clean_installments_read_by_role') then
    create policy clean_installments_read_by_role on public.student_installments
      for select to authenticated
      using (
        public.clean_portal_has_role(array['finance'])
        or exists(
          select 1
          from public.student_fees sf
          join public.students s on s.id = sf.student_id
          where sf.id = student_fee_id
            and (s.user_id = auth.uid() or s.parent_id = auth.uid())
        )
      );
  end if;
end $$;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='fee_payments' and policyname='clean_payments_read_by_role') then
    create policy clean_payments_read_by_role on public.fee_payments
      for select to authenticated
      using (
        public.clean_portal_has_role(array['finance'])
        or exists(
          select 1
          from public.student_fees sf
          join public.students s on s.id = sf.student_id
          where sf.id = student_fee_id
            and (s.user_id = auth.uid() or s.parent_id = auth.uid())
        )
      );
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='fee_payments' and policyname='clean_payments_insert_finance') then
    create policy clean_payments_insert_finance on public.fee_payments
      for insert to authenticated
      with check (public.clean_portal_has_role(array['finance']));
  end if;
end $$;

-- الحضور والسلوك: انضباط/إرشاد/علمي/معلم + الطالب/ولي الأمر قراءة ذاتية
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='attendance' and policyname='clean_attendance_read_by_role') then
    create policy clean_attendance_read_by_role on public.attendance
      for select to authenticated
      using (
        public.clean_portal_has_role(array['discipline','counselor','psychologist','academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor','teacher'])
        or exists(select 1 from public.students s where s.id = student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
      );
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='attendance' and policyname='clean_attendance_write_by_role') then
    create policy clean_attendance_write_by_role on public.attendance
      for all to authenticated
      using (public.clean_portal_has_role(array['discipline','teacher']))
      with check (public.clean_portal_has_role(array['discipline','teacher']));
  end if;
end $$;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='behavior_records' and policyname='clean_behavior_read_by_role') then
    create policy clean_behavior_read_by_role on public.behavior_records
      for select to authenticated
      using (
        public.clean_portal_has_role(array['discipline','counselor','psychologist','academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor','teacher'])
        or exists(select 1 from public.students s where s.id = student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
      );
  end if;
end $$;

-- الدرجات والإعفاءات: علمي/معلم + الطالب/ولي الأمر قراءة ذاتية، والمالية لا ترى شيئاً
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='grades' and policyname='clean_grades_read_by_role') then
    create policy clean_grades_read_by_role on public.grades
      for select to authenticated
      using (
        public.clean_portal_has_role(array['academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor','teacher'])
        or exists(select 1 from public.students s where s.id = student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
      );
  end if;
end $$;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='exemptions' and policyname='clean_exemptions_read_by_role') then
    create policy clean_exemptions_read_by_role on public.exemptions
      for select to authenticated
      using (
        public.clean_portal_has_role(array['academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor','teacher'])
        or exists(select 1 from public.students s where s.id = student_id and (s.user_id = auth.uid() or s.parent_id = auth.uid()))
      );
  end if;
end $$;

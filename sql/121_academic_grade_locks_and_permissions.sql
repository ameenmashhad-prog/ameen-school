-- ============================================================================
-- R6 و R14 — قفل الدرجات وصلاحيات الرصد الأكاديمي (Grade Locks & Permissions)
-- ينشئ جدول academic_grade_locks ودالة فحص القفل check_grade_lock، ويضيف
-- زناد (Trigger) لحماية جداول التقييم من الرصد أو التعديل أثناء فترة القفل.
--
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

-- 1) جدول قفل الفترات الدراسية
create table if not exists public.academic_grade_locks (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null default '2026-2027',
  period_name text not null check (period_name in ('m1','m2','midterm','m3','m4','final')),
  stage_type text not null default 'all' check (stage_type in ('all','primary','middle','preparatory')),
  class_id uuid null references public.classes(id) on delete cascade,
  is_locked boolean not null default false,
  locked_by uuid null references public.users(id) on delete set null,
  locked_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- إنشاء فهرس فريد لمنع تكرار نفس قفل الفترة لنفس المرحلة/الصف
create unique index if not exists uq_academic_grade_locks_target
  on public.academic_grade_locks (academic_year, period_name, stage_type, coalesce(class_id, '00000000-0000-0000-0000-000000000000'::uuid));

alter table public.academic_grade_locks enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='academic_grade_locks' and policyname='grade_locks_read_all') then
    create policy grade_locks_read_all on public.academic_grade_locks
      for select to authenticated, anon
      using (true);
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='academic_grade_locks' and policyname='grade_locks_manage_admin') then
    create policy grade_locks_manage_admin on public.academic_grade_locks
      for all to authenticated
      using (exists(select 1 from public.users u where u.id=auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin'))))
      with check (exists(select 1 from public.users u where u.id=auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin'))));
  end if;
end $$;

grant select, insert, update, delete on public.academic_grade_locks to authenticated, anon;

-- 2) دالة فحص قفل الرصد الأكاديمي
create or replace function public.check_grade_lock(p_period text, p_class_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_stage text := 'all';
  v_locked boolean := false;
begin
  -- إذا كان المستخدم مديراً أو مشرفاً أكاديمياً عاماً، يسمح له دائماً بالتجاوز
  if exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin'))) then
    return false;
  end if;

  if p_class_id is not null then
    select case
      when name like '%ابتدائي%' then 'primary'
      when name like '%متوسط%' then 'middle'
      when name like '%إعدادي%' or name like '%اعدادي%' then 'preparatory'
      else 'all'
    end into v_stage from public.classes where id = p_class_id;
  end if;

  select is_locked into v_locked
  from public.academic_grade_locks
  where period_name = p_period
    and (class_id = p_class_id or class_id is null)
    and (stage_type in ('all', v_stage))
  order by class_id nulls last, stage_type desc
  limit 1;

  return coalesce(v_locked, false);
end;
$$;

grant execute on function public.check_grade_lock(text, uuid) to authenticated, anon;

-- 3) دالة إدارة قفل الرصد من شاشة المشرف الأكاديمي
create or replace function public.academic_set_grade_lock(
  p_period text,
  p_stage text default 'all',
  p_class_id uuid default null,
  p_is_locked boolean default true,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_id uuid;
begin
  if not exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin','principal'))) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تعديل قفل الدرجات');
  end if;

  insert into public.academic_grade_locks (
    period_name, stage_type, class_id, is_locked, locked_by, locked_at, notes
  ) values (
    p_period, coalesce(p_stage, 'all'), p_class_id, p_is_locked, auth.uid(), now(), p_notes
  )
  on conflict (academic_year, period_name, stage_type, coalesce(class_id, '00000000-0000-0000-0000-000000000000'::uuid))
  do update set
    is_locked = excluded.is_locked,
    locked_by = auth.uid(),
    locked_at = now(),
    notes = coalesce(excluded.notes, public.academic_grade_locks.notes),
    updated_at = now()
  returning id into v_id;

  return jsonb_build_object('ok', true, 'message', case when p_is_locked then 'تم قفل رصد الدرجات لهذه الفترة بنجاح 🔒' else 'تم فتح رصد الدرجات لهذه الفترة بنجاح 🔓' end, 'lock_id', v_id);
end;
$$;

grant execute on function public.academic_set_grade_lock(text,text,uuid,boolean,text) to authenticated, anon;

-- 4) زناد حماية قاعدة البيانات عند إدخال أو تعديل الدرجات في continuous_assessments و exam_scores
create or replace function public.trg_enforce_grade_lock()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_locked boolean := false;
  v_period text := 'm1';
  v_class_id uuid := coalesce(new.class_id, old.class_id);
begin
  if exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin'))) then
    return coalesce(new, old);
  end if;

  if tg_table_name = 'continuous_assessments' then
    v_period := case coalesce(new.assessment_month, old.assessment_month, 10)
      when 10 then 'm1' when 11 then 'm2' when 12 then 'midterm' when 1 then 'midterm'
      when 2 then 'm3' when 3 then 'm4' when 4 then 'm4' else 'final'
    end;
  elsif tg_table_name = 'exam_scores' then
    v_period := 'm1';
    if coalesce(new.exam_id, old.exam_id) is not null then
      select case when exam_name like '%ثاني%' then 'm2' when exam_name like '%نصف%' or exam_name like '%أول%' then 'midterm' when exam_name like '%ثالث%' then 'm3' when exam_name like '%رابع%' then 'm4' when exam_name like '%نهائ%' or exam_name like '%ثاني%' then 'final' else 'm1' end
      into v_period from public.exams where id = coalesce(new.exam_id, old.exam_id);
      select class_id into v_class_id from public.exams where id = coalesce(new.exam_id, old.exam_id);
    end if;
  end if;

  v_locked := public.check_grade_lock(v_period, v_class_id);
  if v_locked then
    raise exception 'الفترة الدراسية (%) مقفلة حالياً من الإدارة الأكاديمية ولا يمكن رصد أو تعديل الدرجات فيها.', v_period;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_lock_continuous on public.continuous_assessments;
create trigger trg_lock_continuous
  before insert or update or delete on public.continuous_assessments
  for each row execute function public.trg_enforce_grade_lock();

drop trigger if exists trg_lock_exam_scores on public.exam_scores;
create trigger trg_lock_exam_scores
  before insert or update or delete on public.exam_scores
  for each row execute function public.trg_enforce_grade_lock();

-- إعادة تحميل كاش المخطط في PostgREST
NOTIFY pgrst, 'reload schema';

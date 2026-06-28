-- =============================================================
-- مدارس أمين الرضا (ع) — تطوير إدارة الجدول المدرسي
-- دعم استيراد aSc Timetables + التعديل اليدوي + الربط المستقبلي
-- =============================================================

create extension if not exists pgcrypto;

-- تتبع عمليات الاستيراد من aSc أو CSV
create table if not exists public.schedule_import_batches (
  id uuid primary key default gen_random_uuid(),
  academic_period_id uuid null references public.academic_periods(id),
  file_name text,
  file_type text default 'asc_xml',
  import_mode text default 'upsert' check (import_mode in ('upsert','replace_period','replace_classes')),
  stats jsonb not null default '{}'::jsonb,
  errors jsonb not null default '[]'::jsonb,
  imported_by uuid null references public.users(id),
  created_at timestamptz not null default now()
);

-- أعمدة اختيارية على weekly_schedule للربط المستقبلي والتتبع.
alter table public.weekly_schedule add column if not exists import_batch_id uuid null references public.schedule_import_batches(id) on delete set null;
alter table public.weekly_schedule add column if not exists asc_lesson_id text;
alter table public.weekly_schedule add column if not exists asc_card_key text;
alter table public.weekly_schedule add column if not exists room text;
alter table public.weekly_schedule add column if not exists source text default 'manual';
alter table public.weekly_schedule add column if not exists updated_at timestamptz default now();

create index if not exists idx_schedule_import_batches_period on public.schedule_import_batches(academic_period_id, created_at desc);
create index if not exists idx_weekly_schedule_period_class_slot on public.weekly_schedule(academic_period_id, class_id, day, period_number);
create index if not exists idx_weekly_schedule_period_teacher_slot on public.weekly_schedule(academic_period_id, teacher_id, day, period_number);
create index if not exists idx_weekly_schedule_asc_card_key on public.weekly_schedule(asc_card_key) where asc_card_key is not null;

-- منع تكرار حصة الصف في نفس الوقت داخل نفس الفصل.
do $$ begin
  begin
    create unique index if not exists uniq_weekly_schedule_class_slot
      on public.weekly_schedule(academic_period_id, class_id, day, period_number)
      where academic_period_id is not null and class_id is not null and day is not null and period_number is not null;
  exception when others then
    raise notice 'تعذر إنشاء قيد فريد للصف بسبب وجود تكرارات حالية: %', sqlerrm;
  end;
end $$;

-- Views للعرض السريع
create or replace view public.v_schedule_detailed
with (security_invoker=true) as
select
  ws.id,
  ws.academic_period_id,
  ap.name as academic_period_name,
  ws.class_id,
  c.name as class_name,
  ws.subject_id,
  sub.name as subject_name,
  ws.teacher_id,
  u.name as teacher_name,
  ws.day,
  case ws.day
    when 0 then 'السبت'
    when 1 then 'الأحد'
    when 2 then 'الاثنين'
    when 3 then 'الثلاثاء'
    when 4 then 'الأربعاء'
    when 5 then 'الخميس'
    when 6 then 'الجمعة'
    else ws.day::text
  end as day_name,
  ws.period_number,
  ws.room,
  ws.source,
  ws.import_batch_id,
  ws.created_at,
  ws.updated_at
from public.weekly_schedule ws
left join public.academic_periods ap on ap.id = ws.academic_period_id
left join public.classes c on c.id = ws.class_id
left join public.subjects sub on sub.id = ws.subject_id
left join public.users u on u.id = ws.teacher_id;

create or replace view public.v_teacher_load_summary
with (security_invoker=true) as
select
  ws.academic_period_id,
  ws.teacher_id,
  u.name as teacher_name,
  count(*) as weekly_lessons,
  count(distinct ws.class_id) as classes_count,
  count(distinct ws.subject_id) as subjects_count
from public.weekly_schedule ws
left join public.users u on u.id = ws.teacher_id
group by ws.academic_period_id, ws.teacher_id, u.name;

grant select on public.v_schedule_detailed to authenticated;
grant select on public.v_teacher_load_summary to authenticated;
grant select, insert on public.schedule_import_batches to authenticated;

-- RLS اختياري للجداول الجديدة
alter table public.schedule_import_batches enable row level security;
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='schedule_import_batches' and policyname='schedule_import_batches_admin_read') then
    create policy schedule_import_batches_admin_read on public.schedule_import_batches
      for select to authenticated
      using (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='schedule_import_batches' and policyname='schedule_import_batches_admin_insert') then
    create policy schedule_import_batches_admin_insert on public.schedule_import_batches
      for insert to authenticated
      with check (exists(select 1 from public.users u where u.id=auth.uid() and (u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor') or coalesce(u.is_super_admin,false)=true)));
  end if;
end $$;

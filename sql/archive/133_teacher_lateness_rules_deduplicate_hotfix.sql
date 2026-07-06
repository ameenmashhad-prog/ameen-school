-- ============================================================================
-- 133) Hotfix: تنظيف تكرار قواعد تأخير المعلمين
-- يعالج حالة ظهور نفس القاعدة أكثر من مرة عند إعادة تشغيل SQL 127.
-- ============================================================================

create extension if not exists pgcrypto;

create table if not exists public.teacher_lateness_rules (
  id uuid primary key default gen_random_uuid(),
  rule_name text not null,
  min_late_minutes int not null,
  max_late_minutes int null,
  repeat_count int not null default 1,
  penalty_session_units numeric not null default 1,
  is_active boolean not null default true,
  sort_order int not null default 100,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

with ranked as (
  select id,
         row_number() over (
           partition by min_late_minutes, coalesce(max_late_minutes,-1), repeat_count, penalty_session_units
           order by created_at asc, id asc
         ) as rn
  from public.teacher_lateness_rules
)
delete from public.teacher_lateness_rules t
using ranked r
where t.id = r.id and r.rn > 1;

create unique index if not exists uq_teacher_lateness_rules_logic
  on public.teacher_lateness_rules(min_late_minutes, coalesce(max_late_minutes,-1), repeat_count, penalty_session_units);

notify pgrst, 'reload schema';

select 'teacher_lateness_rules_deduplicate_hotfix_ready' as status;

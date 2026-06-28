-- =============================================================
-- مدارس أمين الرضا (ع) — فحص صحة النظام والتنظيف المرحلي
-- Additive only: لا يحذف ولا يعدل بيانات المدرسة.
-- ينشئ دالة Health Check تقرأ حالة الجداول، الأعمدة، التكرارات، والأيتام.
-- =============================================================

create extension if not exists pgcrypto;

create table if not exists public.system_migration_log (
  id uuid primary key default gen_random_uuid(),
  migration_key text not null unique,
  title text not null,
  applied_by uuid null default auth.uid(),
  applied_at timestamptz not null default now(),
  notes text
);

insert into public.system_migration_log (migration_key, title, notes)
values ('16_system_health_and_maintenance', 'فحص صحة النظام والتنظيف المرحلي', 'تم إنشاء دالة system_health_check')
on conflict (migration_key) do nothing;

create or replace function public._table_count(p_table text)
returns bigint
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  n bigint := 0;
begin
  if to_regclass('public.' || p_table) is null then
    return 0;
  end if;
  execute format('select count(*) from public.%I', p_table) into n;
  return coalesce(n,0);
exception when others then
  return 0;
end;
$$;

create or replace function public._missing_columns(p_table text, p_cols text[])
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(jsonb_agg(c), '[]'::jsonb)
  from unnest(p_cols) as c
  where not exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name=p_table
      and column_name=c
  );
$$;

create or replace function public.system_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  result jsonb;
  table_counts jsonb;
  role_counts jsonb;
  missing jsonb;
  rls jsonb;
  academic_periods_json jsonb;
  duplicate_period_names bigint := 0;
  duplicate_schedule_slots bigint := 0;
  orphan_fees bigint := 0;
  orphan_installments bigint := 0;
  orphan_payments bigint := 0;
  orphan_schedule_class bigint := 0;
  orphan_schedule_subject bigint := 0;
  orphan_schedule_teacher bigint := 0;
begin
  select jsonb_object_agg(t, public._table_count(t)) into table_counts
  from unnest(array[
    'users','students','classes','subjects','academic_periods',
    'student_fees','student_installments','fee_payments','fee_structures',
    'attendance','behavior_records','grades','grade_weights','continuous_assessments','exams','exam_scores',
    'registration_families','registration_students','registration_teachers',
    'weekly_schedule','class_sessions','homeworks','teacher_activity_log',
    'exchange_rates','finance_audit_logs'
  ]) as t;

  if to_regclass('public.users') is not null then
    select coalesce(jsonb_object_agg(coalesce(role,'unknown'), cnt), '{}'::jsonb)
    into role_counts
    from (
      select role, count(*) cnt
      from public.users
      group by role
    ) x;
  else
    role_counts := '{}'::jsonb;
  end if;

  select jsonb_build_object(
    'students', public._missing_columns('students', array['id','name','father_name','mother_name','last_name','parent_id','user_id','class_id']),
    'fee_payments', public._missing_columns('fee_payments', array['id','student_fee_id','student_installment_id','amount','payment_method','payment_date','currency','amount_usd','amount_irr','receipt_number']),
    'student_fees', public._missing_columns('student_fees', array['id','student_id','class_id','academic_year','base_amount','gross_amount','discount_amount','net_amount','total_paid','status']),
    'student_installments', public._missing_columns('student_installments', array['id','student_fee_id','installment_number','due_date','amount_due','amount_paid','balance_remaining','status']),
    'grade_weights', public._missing_columns('grade_weights', array['id','component','weight_percent','academic_year','stage_type','continuous_weight','monthly_exam_weight','is_active']),
    'registration_families', public._missing_columns('registration_families', array['id','guardian_name','mother_name','mother_phone','generated_username']),
    'weekly_schedule', public._missing_columns('weekly_schedule', array['id','academic_period_id','class_id','subject_id','teacher_id','day','period_number'])
  ) into missing;

  select coalesce(jsonb_agg(jsonb_build_object('table', tablename, 'rls_enabled', rowsecurity) order by tablename), '[]'::jsonb)
  into rls
  from pg_tables
  where schemaname='public'
    and tablename in (
      'users','students','student_fees','student_installments','fee_payments','attendance','grades','weekly_schedule',
      'registration_families','registration_students','registration_teachers'
    );

  if to_regclass('public.academic_periods') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]'::jsonb)
    into academic_periods_json
    from public.academic_periods;

    select count(*) into duplicate_period_names
    from (
      select name
      from public.academic_periods
      group by name
      having count(*) > 1
    ) d;
  else
    academic_periods_json := '[]'::jsonb;
  end if;

  if to_regclass('public.weekly_schedule') is not null then
    select count(*) into duplicate_schedule_slots
    from (
      select academic_period_id, class_id, day, period_number
      from public.weekly_schedule
      group by academic_period_id, class_id, day, period_number
      having count(*) > 1
    ) d;

    select count(*) into orphan_schedule_class
    from public.weekly_schedule ws
    left join public.classes c on c.id=ws.class_id
    where ws.class_id is not null and c.id is null;

    select count(*) into orphan_schedule_subject
    from public.weekly_schedule ws
    left join public.subjects s on s.id=ws.subject_id
    where ws.subject_id is not null and s.id is null;

    select count(*) into orphan_schedule_teacher
    from public.weekly_schedule ws
    left join public.users u on u.id=ws.teacher_id
    where ws.teacher_id is not null and u.id is null;
  end if;

  if to_regclass('public.student_fees') is not null then
    select count(*) into orphan_fees
    from public.student_fees sf
    left join public.students s on s.id=sf.student_id
    where sf.student_id is not null and s.id is null;
  end if;

  if to_regclass('public.student_installments') is not null then
    select count(*) into orphan_installments
    from public.student_installments si
    left join public.student_fees sf on sf.id=si.student_fee_id
    where si.student_fee_id is not null and sf.id is null;
  end if;

  if to_regclass('public.fee_payments') is not null then
    select count(*) into orphan_payments
    from public.fee_payments fp
    left join public.student_fees sf on sf.id=fp.student_fee_id
    where fp.student_fee_id is not null and sf.id is null;
  end if;

  result := jsonb_build_object(
    'checked_at', now(),
    'table_counts', coalesce(table_counts,'{}'::jsonb),
    'role_counts', coalesce(role_counts,'{}'::jsonb),
    'missing_columns', missing,
    'rls', rls,
    'academic_periods', academic_periods_json,
    'issues', jsonb_build_object(
      'duplicate_academic_period_names', duplicate_period_names,
      'duplicate_schedule_slots', duplicate_schedule_slots,
      'orphan_student_fees', orphan_fees,
      'orphan_installments', orphan_installments,
      'orphan_payments', orphan_payments,
      'orphan_schedule_class', orphan_schedule_class,
      'orphan_schedule_subject', orphan_schedule_subject,
      'orphan_schedule_teacher', orphan_schedule_teacher
    ),
    'recommendations', jsonb_build_array(
      'شغّلي ملفات SQL بالترتيب من 12 ثم 09 ثم 10 ثم 13/14 حسب الحاجة.',
      'لا تفعّلي RLS النهائي قبل اكتمال اختبار كل الواجهات.',
      'راجعي duplicate_schedule_slots قبل استيراد جدول جديد.',
      'راجعي missing_columns إذا ظهرت أخطاء schema cache أو أعمدة ناقصة.'
    )
  );

  return result;
end;
$$;

grant execute on function public.system_health_check() to authenticated;
grant select, insert on public.system_migration_log to authenticated;

notify pgrst, 'reload schema';

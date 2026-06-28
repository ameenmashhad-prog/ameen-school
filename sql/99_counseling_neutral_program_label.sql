-- =============================================================
-- مدارس أمين الرضا (ع) — تثبيت التسمية المحايدة للجانب النفسي
-- التسمية الخارجية المعتمدة:
-- برنامج تطوير المهارات والمتابعة التربوية
-- آمن ويمكن تشغيله أكثر من مرة.
-- =============================================================

alter table if exists public.counseling_cases
  add column if not exists external_label text not null default 'برنامج تطوير المهارات والمتابعة التربوية';

alter table if exists public.counseling_sessions
  add column if not exists external_label text not null default 'برنامج تطوير المهارات والمتابعة التربوية';

alter table if exists public.counseling_sessions
  add column if not exists internal_label text;

-- تحديث القيم الافتراضية للأعمدة الموجودة مسبقاً
alter table if exists public.counseling_cases
  alter column external_label set default 'برنامج تطوير المهارات والمتابعة التربوية';

alter table if exists public.counseling_sessions
  alter column external_label set default 'برنامج تطوير المهارات والمتابعة التربوية';

-- تحديث السجلات الحالية ذات التسميات القديمة/الفارغة فقط
update public.counseling_cases
set external_label = 'برنامج تطوير المهارات والمتابعة التربوية'
where external_label is null
   or trim(external_label) = ''
   or external_label in ('ملف متابعة أكاديمية وتنموية','متابعة تطوير المهارات');

update public.counseling_sessions
set external_label = 'برنامج تطوير المهارات والمتابعة التربوية'
where external_label is null
   or trim(external_label) = ''
   or external_label in ('ملف متابعة أكاديمية وتنموية','متابعة تطوير المهارات');

create or replace function public.counseling_neutral_label_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'label', 'برنامج تطوير المهارات والمتابعة التربوية',
    'cases_label_count', coalesce((select count(*) from public.counseling_cases where external_label='برنامج تطوير المهارات والمتابعة التربوية'),0),
    'sessions_label_count', coalesce((select count(*) from public.counseling_sessions where external_label='برنامج تطوير المهارات والمتابعة التربوية'),0),
    'checked_at', now()
  );
end;
$$;

grant execute on function public.counseling_neutral_label_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.counseling_neutral_label_health_check() as neutral_label_health;

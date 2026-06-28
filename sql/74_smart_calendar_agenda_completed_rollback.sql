-- =============================================================
-- Rollback اختياري لوحدة التقويم الذكي
-- تحذير: هذا الملف يحذف الجداول الجديدة الخاصة بالتقويم الذكي وقد يحذف بياناتها.
-- لا تشغله إلا إذا قررت الإدارة التراجع عن الوحدة بالكامل.
-- =============================================================

-- حذف Views/Functions أولاً
drop function if exists public.get_dashboard_home();
drop function if exists public.get_my_agenda(text);
drop function if exists public.get_my_completed_items(text);
drop function if exists public.revert_completed_item(uuid);
drop function if exists public.mark_completed(text,text,text,uuid,text,text);
drop function if exists public.get_calendar_month(int,int,uuid);
drop function if exists public.get_calendar_day_details(date,uuid);
drop function if exists public.generate_holidays_for_academic_year(uuid,text);
drop function if exists public.import_holiday_package(jsonb);
drop function if exists public.exam_period_upsert(uuid,text,text,date,date,uuid,text);
drop function if exists public.suggest_exam_schedule(uuid);
drop function if exists public.smart_calendar_health_check();
drop function if exists public.calendar_count_working_days(date,date,uuid);
drop function if exists public.calendar_is_school_day(date,uuid);
drop function if exists public.calendar_is_holiday(date,uuid);
drop function if exists public.calendar_is_weekend(date,uuid);
drop function if exists public.calendar_format_triple(date);
drop function if exists public.calendar_gregorian_to_solar(date);
drop function if exists public.calendar_solar_to_gregorian(int,int,int);
drop function if exists public.calendar_gregorian_to_lunar(date);
drop function if exists public.calendar_lunar_to_gregorian_approx(int,int,int);
drop function if exists public.calendar_gregorian_to_jdn(date);
drop function if exists public.calendar_jdn_to_gregorian(int);

-- حذف الجداول الجديدة فقط
drop table if exists public.completed_items cascade;
drop table if exists public.calendar_events cascade;
drop table if exists public.exam_periods cascade;
drop table if exists public.holidays cascade;
drop table if exists public.holiday_rules cascade;
drop table if exists public.academic_years cascade;
drop table if exists public.school_branches cascade;
drop table if exists public.countries cascade;

notify pgrst, 'reload schema';
select 'smart_calendar_rollback_done' as status;

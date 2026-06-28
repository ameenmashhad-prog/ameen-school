-- =============================================================
-- مدارس أمين الرضا (ع) — إعادة توليد جلسات الفصل الدراسي
-- الهدف: تحديث class_sessions بعد تعديل الجدول أو إسنادات المعلمين.
-- يحافظ افتراضياً على الجلسات التي عليها نشاط فعلي أو واجبات.
-- =============================================================

create extension if not exists pgcrypto;

create or replace function public.regenerate_class_sessions(
  p_start date,
  p_end date,
  p_academic_period_id uuid,
  p_preserve_activity boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count int := 0;
  generated_count int := 0;
begin
  if p_start is null or p_end is null then
    return jsonb_build_object('ok', false, 'message', 'يجب تحديد تاريخ البداية والنهاية');
  end if;

  if p_end < p_start then
    return jsonb_build_object('ok', false, 'message', 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية');
  end if;

  if not exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (
        u.role in ('admin','academic','academic_admin','scientific','academic_supervisor','supervisor')
        or coalesce(u.is_super_admin,false)=true
      )
  ) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية إعادة توليد الجلسات');
  end if;

  -- حذف الجلسات غير المثبتة فقط، مع الحفاظ على أي جلسة عليها نشاط/واجب إذا p_preserve_activity=true.
  delete from public.class_sessions cs
  where cs.session_date between p_start and p_end
    and (p_academic_period_id is null or cs.academic_period_id = p_academic_period_id)
    and (
      p_preserve_activity = false
      or (
        not exists(select 1 from public.teacher_activity_log tal where tal.class_session_id = cs.id)
        and not exists(select 1 from public.homeworks hw where hw.class_session_id = cs.id)
      )
    );

  get diagnostics deleted_count = row_count;

  generated_count := public.generate_class_sessions(p_start, p_end, p_academic_period_id);

  return jsonb_build_object(
    'ok', true,
    'message', 'تمت إعادة توليد جلسات الفصل',
    'deleted_sessions', deleted_count,
    'generated_or_updated_sessions', generated_count,
    'preserved_activity', p_preserve_activity
  );
end;
$$;

grant execute on function public.regenerate_class_sessions(date,date,uuid,boolean) to authenticated;

notify pgrst, 'reload schema';

select 'regenerate_class_sessions_ready' as status;

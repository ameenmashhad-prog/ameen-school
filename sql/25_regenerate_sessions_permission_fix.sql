-- =============================================================
-- مدارس أمين الرضا (ع) — إصلاح صلاحية إعادة توليد الجلسات
-- السبب: عند التشغيل من Supabase SQL Editor تكون auth.uid() = null.
-- الحل: السماح بالتشغيل من SQL Editor، مع منع anon/public من استدعاء الدالة عبر API.
-- =============================================================

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
  v_uid uuid := auth.uid();
begin
  if p_start is null or p_end is null then
    return jsonb_build_object('ok', false, 'message', 'يجب تحديد تاريخ البداية والنهاية');
  end if;

  if p_end < p_start then
    return jsonb_build_object('ok', false, 'message', 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية');
  end if;

  -- عند التشغيل من Supabase SQL Editor تكون auth.uid() = null.
  -- عبر الواجهة يجب أن يكون المستخدم مديراً أو مسؤولاً علمياً.
  if v_uid is not null and not exists(
    select 1
    from public.users u
    where u.id = v_uid
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

-- تأمين الاستدعاء عبر API: لا نعطيها لـ public أو anon.
revoke all on function public.regenerate_class_sessions(date,date,uuid,boolean) from public;
revoke all on function public.regenerate_class_sessions(date,date,uuid,boolean) from anon;
grant execute on function public.regenerate_class_sessions(date,date,uuid,boolean) to authenticated;

notify pgrst, 'reload schema';

select 'regenerate_sessions_permission_fixed' as status;

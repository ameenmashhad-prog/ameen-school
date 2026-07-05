-- =============================================================
-- مدارس أمين الرضا (ع) — إنشاء/ترقية حساب مرشد بسرعة
-- الاستخدام السريع بعد إنشاء مستخدم في Supabase Auth أو وجوده مسبقاً:
-- select public.bootstrap_counselor_by_email('email@example.com','اسم المرشد');
-- ثم يسجل المستخدم الدخول ويفتح counselor.html
-- =============================================================

create extension if not exists pgcrypto;

create or replace function public.bootstrap_counselor_by_email(p_email text, p_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text := lower(trim(coalesce(p_email,'')));
  v_auth_id uuid;
  v_name text := nullif(trim(coalesce(p_name,'')), '');
  inserted_profile boolean := false;
begin
  if v_email = '' then
    return jsonb_build_object('ok',false,'message','أدخلي البريد الإلكتروني');
  end if;

  select au.id
  into v_auth_id
  from auth.users au
  where lower(au.email) = v_email
  order by au.created_at desc
  limit 1;

  if v_auth_id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'لا يوجد مستخدم Auth بهذا البريد. أنشئيه أولاً من Supabase Authentication > Add user ثم أعيدي تشغيل الدالة.',
      'email', v_email
    );
  end if;

  if not exists(select 1 from public.users u where u.id = v_auth_id) then
    insert into public.users(id, name, email, role, is_super_admin)
    values(v_auth_id, coalesce(v_name, v_email), v_email, 'counselor', false);
    inserted_profile := true;
  else
    update public.users
    set
      name = coalesce(v_name, nullif(name,''), v_email),
      email = coalesce(nullif(email,''), v_email),
      role = 'counselor',
      is_super_admin = coalesce(is_super_admin,false)
    where id = v_auth_id;
  end if;

  -- تفويضات صريحة احتياطية، حتى لو تغيرت دالة الصلاحيات لاحقاً.
  if to_regclass('public.user_extra_permissions') is not null then
    insert into public.user_extra_permissions(user_id, permission_key, is_active, notes)
    values
      (v_auth_id, 'counseling', true, 'bootstrap counselor'),
      (v_auth_id, 'counseling.full', true, 'bootstrap counselor'),
      (v_auth_id, 'calendar', true, 'bootstrap counselor'),
      (v_auth_id, 'achievements', true, 'bootstrap counselor'),
      (v_auth_id, 'notifications', true, 'bootstrap counselor'),
      (v_auth_id, 'staff.dashboard', true, 'bootstrap counselor')
    on conflict (user_id, permission_key) do update
      set is_active = true,
          expires_at = null,
          notes = excluded.notes,
          granted_at = now();
  end if;

  notify pgrst, 'reload schema';

  return jsonb_build_object(
    'ok', true,
    'message', 'تم تجهيز حساب المرشد. سجلي الدخول بهذا الحساب وافتحي counselor.html',
    'auth_user_id', v_auth_id,
    'email', v_email,
    'profile_inserted', inserted_profile,
    'role', 'counselor',
    'permissions', jsonb_build_array('counseling','counseling.full','calendar','achievements','notifications','staff.dashboard')
  );
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm,'email',v_email);
end;
$$;

grant execute on function public.bootstrap_counselor_by_email(text,text) to authenticated;

grant execute on function public.bootstrap_counselor_by_email(text,text) to service_role;

create or replace function public.counselor_account_bootstrap_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'checked_at', now(),
    'bootstrap_rpc', to_regprocedure('public.bootstrap_counselor_by_email(text,text)') is not null,
    'counselor_profiles', coalesce((select count(*) from public.users where role in ('counselor','psychologist')),0),
    'counselors_with_full_permission', case when to_regclass('public.user_extra_permissions') is null then 0 else (
      select count(distinct user_id)
      from public.user_extra_permissions
      where permission_key in ('counseling','counseling.full')
        and is_active = true
        and (expires_at is null or expires_at > now())
    ) end,
    'note', 'إذا كان العدد صفر، أنشئي مستخدم Auth ثم شغلي bootstrap_counselor_by_email.'
  );
end;
$$;

grant execute on function public.counselor_account_bootstrap_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.counselor_account_bootstrap_health_check() as counselor_account_bootstrap_health;

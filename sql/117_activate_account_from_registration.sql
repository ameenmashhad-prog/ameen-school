-- ============================================================================
-- R15 — تفعيل حساب المستخدم مباشرة من طلب التسجيل (Activate Account from Registration)
-- ينشئ حساب Supabase Auth (auth.users + auth.identities) مع تأكيد البريد الإلكتروني،
-- وينشئ الملف الشخصي في public.users (وللطلاب في public.students)، ويحدث حالة الطلب إلى 'approved'.
--
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

create extension if not exists pgcrypto;

create or replace function public.activate_registered_user(p_reg_type text, p_reg_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_reg_type text := lower(trim(coalesce(p_reg_type, '')));
  v_tch record;
  v_fam record;
  v_stu record;
  
  v_username text;
  v_email text;
  v_password text;
  v_name text;
  
  v_user_id uuid;
  v_inst_id uuid;
  v_parent_id uuid;
  v_stu_user_id uuid;
  v_stu_username text;
  v_stu_email text;
  v_stu_password text;
  v_stu_name text;
  
  v_activated_count int := 0;
begin
  -- الحصول على معرف النسخة من auth.instances إذا وجد (العمود اسمه id وليس instance_id)
  select coalesce((select id from auth.instances limit 1), '00000000-0000-0000-0000-000000000000'::uuid) into v_inst_id;

  if v_reg_type = 'teacher' then
    select * into v_tch from public.registration_teachers where id = p_reg_id;
    if v_tch is null then
      return jsonb_build_object('ok', false, 'error', 'طلب تسجيل المعلم غير موجود');
    end if;
    
    -- تحديد اسم المستخدم والبريد الإلكتروني
    v_username := lower(trim(coalesce(v_tch.generated_username, '')));
    if v_username = '' then v_username := lower(trim(coalesce(v_tch.email, ''))); end if;
    if v_username = '' then v_username := lower(trim(coalesce(v_tch.teacher_code, 'tch_' || substr(p_reg_id::text, 1, 8)))); end if;
    if v_username not like '%@%' then
      v_email := v_username || '@ameen.iq';
    else
      v_email := v_username;
      v_username := split_part(v_email, '@', 1);
    end if;
    
    -- تحديد كلمة المرور (تاريخ الميلاد DDMMYYYY إن وجد، أو initial_password إن لم يكن مشفراً)
    if v_tch.birth_date is not null then
      v_password := to_char(v_tch.birth_date, 'DDMMYYYY');
    elsif v_tch.initial_password is not null and v_tch.initial_password not like '$2%' and length(trim(v_tch.initial_password)) >= 6 then
      v_password := trim(v_tch.initial_password);
    else
      v_password := '12345678';
    end if;
    
    v_name := coalesce(nullif(trim(v_tch.full_name), ''), v_username);
    
    -- البحث عن الحساب في auth.users أو إنشاء معرف جديد
    select id into v_user_id from auth.users where lower(email) = lower(v_email) limit 1;
    if v_user_id is not null then
      update auth.users set
        encrypted_password = crypt(v_password, gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('name', v_name, 'role', 'teacher'),
        updated_at = now()
      where id = v_user_id;
    else
      v_user_id := gen_random_uuid();
      insert into auth.users (
        id, instance_id, email, encrypted_password, email_confirmed_at, aud, role,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, email_change, email_change_token_new, recovery_token
      ) values (
        v_user_id, v_inst_id, v_email, crypt(v_password, gen_salt('bf')), now(), 'authenticated', 'authenticated',
        '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('name', v_name, 'role', 'teacher'),
        now(), now(), '', '', '', ''
      );
    end if;
    
    -- إنشاء رابط الهوية في auth.identities
    begin
      if not exists (select 1 from auth.identities where user_id = v_user_id and provider = 'email') then
        insert into auth.identities (id, user_id, identity_data, provider, created_at, updated_at)
        values (gen_random_uuid()::text, v_user_id, jsonb_build_object('sub', v_user_id::text, 'email', v_email), 'email', now(), now());
      end if;
    exception when others then
      raise notice 'تنبيه: تجاوز إدراج auth.identities: %', sqlerrm;
    end;
    
    -- إنشاء أو تحديث الملف الشخصي في public.users
    insert into public.users (
      id, name, email, phone, role, qualification, specialization,
      birth_date, nationality, avatar_url, active, is_super_admin, created_at
    ) values (
      v_user_id, v_name, v_email, v_tch.phone, 'teacher', v_tch.qualification, v_tch.specialization,
      v_tch.birth_date, v_tch.nationality, v_tch.photo_path, true, false, now()
    )
    on conflict (id) do update set
      name = excluded.name,
      email = excluded.email,
      phone = coalesce(excluded.phone, public.users.phone),
      role = 'teacher',
      qualification = coalesce(excluded.qualification, public.users.qualification),
      specialization = coalesce(excluded.specialization, public.users.specialization),
      birth_date = coalesce(excluded.birth_date, public.users.birth_date),
      nationality = coalesce(excluded.nationality, public.users.nationality),
      avatar_url = coalesce(excluded.avatar_url, public.users.avatar_url),
      active = true,
      updated_at = now();
      
    -- تحديث حالة طلب التسجيل
    update public.registration_teachers set status = 'approved', updated_at = now() where id = p_reg_id;
    
    return jsonb_build_object(
      'ok', true,
      'type', 'teacher',
      'id', v_user_id,
      'email', v_email,
      'name', v_name,
      'message', 'تم تفعيل حساب المعلم في Auth و users بنجاح'
    );
    
  elsif v_reg_type = 'family' then
    select * into v_fam from public.registration_families where id = p_reg_id;
    if v_fam is null then
      return jsonb_build_object('ok', false, 'error', 'طلب تسجيل الأسرة غير موجود');
    end if;
    
    -- 1) تفعيل حساب ولي الأمر
    v_username := lower(trim(coalesce(v_fam.generated_username, '')));
    if v_username = '' then v_username := lower(trim(coalesce(v_fam.phone_primary, ''))); end if;
    if v_username = '' then v_username := 'fam_' || substr(p_reg_id::text, 1, 8); end if;
    if v_username not like '%@%' then
      v_email := v_username || '@ameen.iq';
    else
      v_email := v_username;
      v_username := split_part(v_email, '@', 1);
    end if;
    
    if v_fam.birth_date is not null then
      v_password := to_char(v_fam.birth_date, 'DDMMYYYY');
    elsif v_fam.initial_password is not null and v_fam.initial_password not like '$2%' and length(trim(v_fam.initial_password)) >= 6 then
      v_password := trim(v_fam.initial_password);
    else
      v_password := '12345678';
    end if;
    
    v_name := coalesce(nullif(trim(v_fam.guardian_name), ''), v_username);
    
    select id into v_parent_id from auth.users where lower(email) = lower(v_email) limit 1;
    if v_parent_id is not null then
      update auth.users set
        encrypted_password = crypt(v_password, gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('name', v_name, 'role', 'parent'),
        updated_at = now()
      where id = v_parent_id;
    else
      v_parent_id := gen_random_uuid();
      insert into auth.users (
        id, instance_id, email, encrypted_password, email_confirmed_at, aud, role,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, email_change, email_change_token_new, recovery_token
      ) values (
        v_parent_id, v_inst_id, v_email, crypt(v_password, gen_salt('bf')), now(), 'authenticated', 'authenticated',
        '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('name', v_name, 'role', 'parent'),
        now(), now(), '', '', '', ''
      );
    end if;
    
    begin
      if not exists (select 1 from auth.identities where user_id = v_parent_id and provider = 'email') then
        insert into auth.identities (id, user_id, identity_data, provider, created_at, updated_at)
        values (gen_random_uuid()::text, v_parent_id, jsonb_build_object('sub', v_parent_id::text, 'email', v_email), 'email', now(), now());
      end if;
    exception when others then
      raise notice 'تنبيه: تجاوز إدراج auth.identities لولي الأمر: %', sqlerrm;
    end;
    
    insert into public.users (
      id, name, email, phone, role, birth_date, nationality, active, is_super_admin, created_at
    ) values (
      v_parent_id, v_name, v_email, v_fam.phone_primary, 'parent', v_fam.birth_date, v_fam.nationality, true, false, now()
    )
    on conflict (id) do update set
      name = excluded.name,
      email = excluded.email,
      phone = coalesce(excluded.phone, public.users.phone),
      role = 'parent',
      birth_date = coalesce(excluded.birth_date, public.users.birth_date),
      nationality = coalesce(excluded.nationality, public.users.nationality),
      active = true,
      updated_at = now();
      
    v_activated_count := 1;
    
    -- 2) تفعيل حسابات الطلاب التابعين لهذه الأسرة
    for v_stu in select * from public.registration_students where family_id = p_reg_id loop
      v_stu_username := lower(trim(coalesce(v_stu.generated_username, '')));
      if v_stu_username = '' then v_stu_username := lower(trim(coalesce(v_stu.student_code, 'stu_' || substr(v_stu.id::text, 1, 8)))); end if;
      if v_stu_username not like '%@%' then
        v_stu_email := v_stu_username || '@ameen.iq';
      else
        v_stu_email := v_stu_username;
        v_stu_username := split_part(v_stu_email, '@', 1);
      end if;
      
      if v_stu.birth_date is not null then
        v_stu_password := to_char(v_stu.birth_date, 'DDMMYYYY');
      elsif v_stu.initial_password is not null and v_stu.initial_password not like '$2%' and length(trim(v_stu.initial_password)) >= 6 then
        v_stu_password := trim(v_stu.initial_password);
      else
        v_stu_password := '12345678';
      end if;
      
      v_stu_name := coalesce(nullif(trim(v_stu.student_name), ''), v_stu_username);
      
      select id into v_stu_user_id from auth.users where lower(email) = lower(v_stu_email) limit 1;
      if v_stu_user_id is not null then
        update auth.users set
          encrypted_password = crypt(v_stu_password, gen_salt('bf')),
          email_confirmed_at = coalesce(email_confirmed_at, now()),
          raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('name', v_stu_name, 'role', 'student'),
          updated_at = now()
        where id = v_stu_user_id;
      else
        v_stu_user_id := gen_random_uuid();
        insert into auth.users (
          id, instance_id, email, encrypted_password, email_confirmed_at, aud, role,
          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
          confirmation_token, email_change, email_change_token_new, recovery_token
        ) values (
          v_stu_user_id, v_inst_id, v_stu_email, crypt(v_stu_password, gen_salt('bf')), now(), 'authenticated', 'authenticated',
          '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('name', v_stu_name, 'role', 'student'),
          now(), now(), '', '', '', ''
        );
      end if;
      
      begin
        if not exists (select 1 from auth.identities where user_id = v_stu_user_id and provider = 'email') then
          insert into auth.identities (id, user_id, identity_data, provider, created_at, updated_at)
          values (gen_random_uuid()::text, v_stu_user_id, jsonb_build_object('sub', v_stu_user_id::text, 'email', v_stu_email), 'email', now(), now());
        end if;
      exception when others then
        raise notice 'تنبيه: تجاوز إدراج auth.identities للطالب: %', sqlerrm;
      end;
      
      insert into public.users (
        id, name, email, role, birth_date, avatar_url, active, is_super_admin, created_at
      ) values (
        v_stu_user_id, v_stu_name, v_stu_email, 'student', v_stu.birth_date, v_stu.photo_path, true, false, now()
      )
      on conflict (id) do update set
        name = excluded.name,
        email = excluded.email,
        role = 'student',
        birth_date = coalesce(excluded.birth_date, public.users.birth_date),
        avatar_url = coalesce(excluded.avatar_url, public.users.avatar_url),
        active = true,
        updated_at = now();
        
      if not exists (select 1 from public.students where user_id = v_stu_user_id or id = v_stu_user_id) then
        insert into public.students (
          id, user_id, parent_id, student_name, student_code, class_id, gender, birth_date, created_at
        ) values (
          v_stu_user_id, v_stu_user_id, v_parent_id, v_stu_name, coalesce(v_stu.student_code, 'STU-' || substr(v_stu_user_id::text, 1, 8)),
          v_stu.class_id, v_stu.gender, v_stu.birth_date, now()
        );
      else
        update public.students set
          parent_id = coalesce(parent_id, v_parent_id),
          user_id = coalesce(user_id, v_stu_user_id),
          student_name = v_stu_name,
          class_id = coalesce(v_stu.class_id, public.students.class_id)
        where id = v_stu_user_id or user_id = v_stu_user_id;
      end if;
      
      update public.registration_students set status = 'approved', updated_at = now() where id = v_stu.id;
      v_activated_count := v_activated_count + 1;
    end loop;
    
    update public.registration_families set status = 'approved', updated_at = now() where id = p_reg_id;
    
    return jsonb_build_object(
      'ok', true,
      'type', 'family',
      'parent_id', v_parent_id,
      'parent_email', v_email,
      'activated_students', v_activated_count - 1,
      'message', 'تم تفعيل حساب ولي الأمر والطلاب التابعين بنجاح في Auth و users'
    );
    
  else
    return jsonb_build_object('ok', false, 'error', 'نوع التسجيل غير مدعوم: ' || coalesce(v_reg_type, 'null'));
  end if;
end;
$$;

grant execute on function public.activate_registered_user(text, uuid) to authenticated, anon;

-- ============================================================================
-- التفعيل الفوري لمعلم التجربة (سليمان معروف slyman) لحل مشكلة الدخول فوراً
-- ============================================================================
do $$
declare
  v_slyman_id uuid;
  v_res jsonb;
begin
  select id into v_slyman_id from public.registration_teachers
  where lower(generated_username) = 'slyman' or id = '31468aba-8340-47fd-b4b0-a1c9ddf0f73e' limit 1;
  
  if v_slyman_id is not null then
    v_res := public.activate_registered_user('teacher', v_slyman_id);
    raise notice '>> تم تفعيل المعلم slyman تلقائياً عبر دالة التفعيل: %', v_res;
  end if;
end $$;

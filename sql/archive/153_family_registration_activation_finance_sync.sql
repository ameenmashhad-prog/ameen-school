-- ============================================================================
-- Family registration activation → finance sync
-- الهدف:
-- - عند تفعيل طلب الأسرة، إذا كانت snapshot الرسوم موجودة في registration_students
--   يتم إنشاء الملف المالي وخطة الأقساط وجدول الأقساط داخل النظام المالي.
-- ============================================================================

create or replace function public.registration_sync_finance_after_family_activation(
  p_registration_student_id uuid,
  p_student_user_id uuid,
  p_operator_id uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reg public.registration_students%rowtype;
  v_fee_id uuid;
  v_plan_id uuid;
  v_item jsonb;
  v_net_amount numeric;
  v_installments_count int;
  v_start_date date;
  v_end_date date;
  v_created_installments int := 0;
begin
  select * into v_reg
  from public.registration_students
  where id = p_registration_student_id;

  if v_reg.id is null then
    return jsonb_build_object('ok', false, 'error', 'registration_student_not_found');
  end if;

  v_net_amount := coalesce(v_reg.annual_fee_snapshot, 0);
  if v_net_amount <= 0 then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_fee_snapshot');
  end if;

  v_installments_count := greatest(coalesce(v_reg.finance_installments_count, 1), 1);
  v_start_date := coalesce(v_reg.finance_plan_start_date, date '2026-09-10');
  v_end_date := coalesce(v_reg.finance_plan_end_date, (v_start_date + ((v_installments_count - 1) * interval '30 days'))::date);

  select id into v_fee_id
  from public.student_fees
  where student_id = p_student_user_id
    and academic_year = coalesce(v_reg.academic_year, '2026-2027')
  order by created_at desc
  limit 1;

  if v_fee_id is null then
    insert into public.student_fees(
      student_id,
      class_id,
      academic_year,
      fee_structure_id,
      gross_amount,
      base_amount,
      discount_amount,
      discount_reason,
      net_amount,
      total_paid,
      status,
      plan_type,
      installments_count,
      created_by,
      updated_by,
      notes,
      updated_at
    ) values (
      p_student_user_id,
      v_reg.class_id,
      coalesce(v_reg.academic_year, '2026-2027'),
      v_reg.fee_structure_id,
      v_net_amount,
      v_net_amount,
      0,
      null,
      v_net_amount,
      0,
      'unpaid',
      coalesce(nullif(v_reg.finance_plan_type, ''), 'monthly'),
      v_installments_count,
      p_operator_id,
      p_operator_id,
      'Created automatically from family-registration-v3 activation',
      now()
    ) returning id into v_fee_id;
  else
    update public.student_fees
      set class_id = coalesce(v_reg.class_id, class_id),
          fee_structure_id = coalesce(v_reg.fee_structure_id, fee_structure_id),
          gross_amount = coalesce(nullif(gross_amount, 0), v_net_amount),
          base_amount = coalesce(nullif(base_amount, 0), v_net_amount),
          net_amount = coalesce(nullif(net_amount, 0), v_net_amount),
          status = case when coalesce(total_paid,0) >= coalesce(nullif(net_amount,0), v_net_amount) then 'paid' else 'unpaid' end,
          plan_type = coalesce(nullif(v_reg.finance_plan_type, ''), plan_type),
          installments_count = coalesce(v_installments_count, installments_count),
          updated_by = p_operator_id,
          updated_at = now(),
          notes = coalesce(notes, 'Created automatically from family-registration-v3 activation')
    where id = v_fee_id;
  end if;

  select id into v_plan_id
  from public.finance_payment_plans
  where student_fee_id = v_fee_id
    and status = 'active'
  order by created_at desc
  limit 1;

  if v_plan_id is null then
    insert into public.finance_payment_plans(
      student_fee_id,
      plan_type,
      installments_count,
      start_date,
      end_date,
      status,
      created_by,
      notes
    ) values (
      v_fee_id,
      coalesce(nullif(v_reg.finance_plan_type, ''), 'monthly'),
      v_installments_count,
      v_start_date,
      v_end_date,
      'active',
      p_operator_id,
      'Created automatically from family-registration-v3 activation'
    ) returning id into v_plan_id;
  else
    update public.finance_payment_plans
      set plan_type = coalesce(nullif(v_reg.finance_plan_type, ''), plan_type),
          installments_count = v_installments_count,
          start_date = v_start_date,
          end_date = v_end_date,
          notes = coalesce(notes, 'Created automatically from family-registration-v3 activation')
    where id = v_plan_id;
  end if;

  delete from public.student_installments
  where student_fee_id = v_fee_id
    and coalesce(amount_paid, 0) = 0
    and coalesce(status, 'pending') in ('pending', 'unpaid', 'partial');

  for v_item in
    select * from jsonb_array_elements(coalesce(v_reg.finance_installment_schedule, '[]'::jsonb))
  loop
    insert into public.student_installments(
      student_fee_id,
      installment_number,
      installment_month,
      due_date,
      amount_due,
      amount_paid,
      balance_remaining,
      status,
      actual_payment_date,
      note,
      updated_at
    ) values (
      v_fee_id,
      greatest(coalesce((v_item->>'installment_number')::int, 1), 1),
      null,
      nullif(v_item->>'due_date', '')::date,
      coalesce((v_item->>'amount_due')::numeric, 0),
      0,
      coalesce((v_item->>'amount_due')::numeric, 0),
      'pending',
      null,
      'Created automatically from family-registration-v3 activation',
      now()
    );
    v_created_installments := v_created_installments + 1;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'student_fee_id', v_fee_id,
    'finance_plan_id', v_plan_id,
    'installments_created', v_created_installments
  );
end;
$$;

grant execute on function public.registration_sync_finance_after_family_activation(uuid,uuid,uuid) to authenticated, anon;

create or replace function public.activate_registered_user_rpc(
  p_reg_type text,
  p_reg_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_reg_type text := lower(trim(coalesce(p_reg_type, '')));
  v_fam record;
  v_stu record;

  v_username text;
  v_email text;
  v_password text;
  v_name text;

  v_parent_id uuid;
  v_stu_user_id uuid;
  v_stu_username text;
  v_stu_email text;
  v_stu_password text;
  v_stu_name text;

  v_inst_id uuid;
  v_activated_count int := 0;
  v_has_students_name boolean := false;
  v_finance_created int := 0;
begin
  if v_reg_type <> 'family' then
    return public.activate_registered_user(v_reg_type, p_reg_id);
  end if;

  select coalesce((select id from auth.instances limit 1), '00000000-0000-0000-0000-000000000000'::uuid)
    into v_inst_id;

  select * into v_fam
  from public.registration_families
  where id = p_reg_id;

  if v_fam is null then
    return jsonb_build_object('ok', false, 'error', 'طلب تسجيل الأسرة غير موجود');
  end if;

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

  select id into v_parent_id
  from auth.users
  where lower(email) = lower(v_email)
  limit 1;

  if v_parent_id is not null then
    update auth.users
    set encrypted_password = crypt(v_password, gen_salt('bf')),
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
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('name', v_name, 'role', 'parent'),
      now(), now(), '', '', '', ''
    );
  end if;

  begin
    if not exists (
      select 1 from auth.identities where user_id = v_parent_id and provider = 'email'
    ) then
      insert into auth.identities (id, user_id, identity_data, provider, created_at, updated_at)
      values (
        gen_random_uuid()::text,
        v_parent_id,
        jsonb_build_object('sub', v_parent_id::text, 'email', v_email),
        'email', now(), now()
      );
    end if;
  exception when others then
    raise notice 'تنبيه: تجاوز إدراج auth.identities لولي الأمر: %', sqlerrm;
  end;

  insert into public.users (
    id, name, email, phone, role, birth_date, nationality, active, is_super_admin, created_at, updated_at
  ) values (
    v_parent_id, v_name, v_email, v_fam.phone_primary, 'parent', v_fam.birth_date, v_fam.nationality, true, false, now(), now()
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

  select exists(
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'students'
      and column_name = 'name'
  ) into v_has_students_name;

  for v_stu in
    select * from public.registration_students where family_id = p_reg_id
  loop
    v_stu_username := lower(trim(coalesce(v_stu.generated_username, '')));
    if v_stu_username = '' then
      v_stu_username := lower(trim(coalesce(v_stu.student_code, 'stu_' || substr(v_stu.id::text, 1, 8))));
    end if;

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

    select id into v_stu_user_id
    from auth.users
    where lower(email) = lower(v_stu_email)
    limit 1;

    if v_stu_user_id is not null then
      update auth.users
      set encrypted_password = crypt(v_stu_password, gen_salt('bf')),
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
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('name', v_stu_name, 'role', 'student'),
        now(), now(), '', '', '', ''
      );
    end if;

    begin
      if not exists (
        select 1 from auth.identities where user_id = v_stu_user_id and provider = 'email'
      ) then
        insert into auth.identities (id, user_id, identity_data, provider, created_at, updated_at)
        values (
          gen_random_uuid()::text,
          v_stu_user_id,
          jsonb_build_object('sub', v_stu_user_id::text, 'email', v_stu_email),
          'email', now(), now()
        );
      end if;
    exception when others then
      raise notice 'تنبيه: تجاوز إدراج auth.identities للطالب: %', sqlerrm;
    end;

    insert into public.users (
      id, name, email, role, birth_date, avatar_url, active, is_super_admin, created_at, updated_at
    ) values (
      v_stu_user_id, v_stu_name, v_stu_email, 'student', v_stu.birth_date, v_stu.photo_path, true, false, now(), now()
    )
    on conflict (id) do update set
      name = excluded.name,
      email = excluded.email,
      role = 'student',
      birth_date = coalesce(excluded.birth_date, public.users.birth_date),
      avatar_url = coalesce(excluded.avatar_url, public.users.avatar_url),
      active = true,
      updated_at = now();

    if not exists (
      select 1 from public.students where user_id = v_stu_user_id or id = v_stu_user_id
    ) then
      if v_has_students_name then
        insert into public.students (
          id, user_id, parent_id, name, student_name, student_code, class_id, gender, birth_date, created_at
        ) values (
          v_stu_user_id, v_stu_user_id, v_parent_id, v_stu_name, v_stu_name,
          coalesce(v_stu.student_code, 'STU-' || substr(v_stu_user_id::text, 1, 8)),
          v_stu.class_id, v_stu.gender, v_stu.birth_date, now()
        );
      else
        insert into public.students (
          id, user_id, parent_id, student_name, student_code, class_id, gender, birth_date, created_at
        ) values (
          v_stu_user_id, v_stu_user_id, v_parent_id, v_stu_name,
          coalesce(v_stu.student_code, 'STU-' || substr(v_stu_user_id::text, 1, 8)),
          v_stu.class_id, v_stu.gender, v_stu.birth_date, now()
        );
      end if;
    else
      if v_has_students_name then
        update public.students
        set parent_id = coalesce(parent_id, v_parent_id),
            user_id = coalesce(user_id, v_stu_user_id),
            name = v_stu_name,
            student_name = v_stu_name,
            class_id = coalesce(v_stu.class_id, public.students.class_id)
        where id = v_stu_user_id or user_id = v_stu_user_id;
      else
        update public.students
        set parent_id = coalesce(parent_id, v_parent_id),
            user_id = coalesce(user_id, v_stu_user_id),
            student_name = v_stu_name,
            class_id = coalesce(v_stu.class_id, public.students.class_id)
        where id = v_stu_user_id or user_id = v_stu_user_id;
      end if;
    end if;

    if public.registration_sync_finance_after_family_activation(v_stu.id, v_stu_user_id, auth.uid())->>'ok' = 'true' then
      v_finance_created := v_finance_created + 1;
    end if;

    update public.registration_students
    set status = 'approved', updated_at = now()
    where id = v_stu.id;

    v_activated_count := v_activated_count + 1;
  end loop;

  update public.registration_families
  set status = 'approved', updated_at = now()
  where id = p_reg_id;

  return jsonb_build_object(
    'ok', true,
    'type', 'family',
    'parent_id', v_parent_id,
    'parent_email', v_email,
    'activated_students', v_activated_count - 1,
    'finance_synced_students', v_finance_created,
    'message', 'تم تفعيل حساب ولي الأمر والطلاب وإنشاء الملفات المالية المرتبطة بنجاح'
  );
end;
$$;

grant execute on function public.activate_registered_user_rpc(text, uuid) to authenticated, anon;

notify pgrst, 'reload schema';

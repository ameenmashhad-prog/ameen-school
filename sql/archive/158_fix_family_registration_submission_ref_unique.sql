-- ============================================================================
-- Fix: forms_submit_family_registration_v3 upsert on registration_families
--
-- المشكلة:
-- الدالة forms_submit_family_registration_v3 تستخدم:
--   on conflict (forms_v3_submission_ref)
-- لكن بعض البيئات لا تحتوي constraint / unique index مطابق لهذا العمود.
--
-- النتيجة:
--   there is no unique or exclusion constraint matching the ON CONFLICT specification
--
-- الحل:
-- 1) تنظيف أي تكرار محتمل على forms_v3_submission_ref مع الإبقاء على أحدث سجل
-- 2) إنشاء unique index غير مشروط على العمود
-- 3) إعادة تعريف الدالة كما هي بعد ضمان الـ conflict target
-- ============================================================================

alter table public.registration_families
  add column if not exists forms_v3_submission_ref text;

with ranked as (
  select id,
         forms_v3_submission_ref,
         row_number() over (
           partition by forms_v3_submission_ref
           order by updated_at desc nulls last, created_at desc nulls last, id desc
         ) as rn
  from public.registration_families
  where forms_v3_submission_ref is not null
)
update public.registration_families f
set forms_v3_submission_ref = null
from ranked r
where f.id = r.id
  and r.rn > 1;

create unique index if not exists uq_registration_families_forms_v3_submission_ref
  on public.registration_families(forms_v3_submission_ref);

create or replace function public.forms_submit_family_registration_v3(
  p_form_slug text,
  p_locale text,
  p_visibility text,
  p_submission_ref text,
  p_schema jsonb,
  p_values jsonb,
  p_upload_ticket_id uuid default null,
  p_uploaded_attachment jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_slug text := trim(coalesce(p_form_slug, ''));
  v_locale text := lower(trim(coalesce(p_locale, 'ar')));
  v_visibility text := lower(trim(coalesce(p_visibility, 'public')));
  v_ref text := trim(coalesce(p_submission_ref, ''));
  v_guardian jsonb := coalesce(p_values->'guardian', '{}'::jsonb);
  v_mother jsonb := coalesce(p_values->'mother', '{}'::jsonb);
  v_context jsonb := coalesce(p_values->'family_context', '{}'::jsonb);
  v_documents jsonb := coalesce(p_values->'documents', '{}'::jsonb);
  v_students jsonb := coalesce(p_values->'students', '[]'::jsonb);
  v_family_id uuid;
  v_student jsonb;
  v_class_text text;
  v_class_id uuid;
  v_section text;
  v_students_count int := 0;
  v_guardian_birth date;
  v_mother_birth date;
begin
  if v_slug = '' then
    return jsonb_build_object('ok', false, 'error', 'form_slug_required');
  end if;
  if v_ref = '' then
    return jsonb_build_object('ok', false, 'error', 'submission_ref_required');
  end if;
  if v_locale not in ('ar','fa','en') then
    v_locale := 'ar';
  end if;
  if v_visibility not in ('public','administrative','finance_admin') then
    v_visibility := 'public';
  end if;

  insert into public.forms_v3_submissions(
    form_slug, locale, visibility, submission_ref, schema_snapshot, submission_values,
    upload_ticket_id, uploaded_attachment, status, created_by
  ) values (
    v_slug,
    v_locale,
    v_visibility,
    v_ref,
    coalesce(p_schema, '{}'::jsonb),
    coalesce(p_values, '{}'::jsonb),
    p_upload_ticket_id,
    p_uploaded_attachment,
    'received',
    auth.uid()
  ) returning id into v_id;

  if p_upload_ticket_id is not null then
    update public.forms_v3_upload_tickets
      set submission_ref = v_ref
    where id = p_upload_ticket_id;
  end if;

  begin
    v_guardian_birth := nullif(v_guardian->>'guardian_birth_date', '')::date;
  exception when others then
    v_guardian_birth := null;
  end;

  begin
    v_mother_birth := nullif(v_mother->>'mother_birth_date', '')::date;
  exception when others then
    v_mother_birth := null;
  end;

  insert into public.registration_families(
    academic_year,
    guardian_name,
    father_name,
    family_name,
    generated_username,
    initial_password,
    birth_date,
    passport_number,
    nationality,
    phone_primary,
    phone_whatsapp,
    phone_emergency,
    education_level,
    education_notes,
    work_type,
    work_notes,
    residence_type,
    mother_name,
    mother_father_name,
    mother_family_name,
    mother_birth_date,
    mother_passport_number,
    mother_nationality,
    mother_phone,
    mother_whatsapp,
    mother_education_level,
    mother_education_notes,
    mother_work_type,
    mother_work_notes,
    general_family_health_notes,
    document_notes,
    finance_payment_entries,
    family_attachment,
    forms_v3_submission_ref,
    status,
    submitted_by,
    updated_at
  ) values (
    coalesce(v_guardian->>'finance_academic_year', '2026-2027'),
    coalesce(nullif(p_values->>'guardian_full_name', ''), nullif(p_values->>'guardian_name', ''), concat_ws(' ', v_guardian->>'guardian_given_name', v_guardian->>'guardian_father_name', p_values->>'family_name')),
    nullif(v_guardian->>'guardian_father_name', ''),
    nullif(p_values->>'family_name', ''),
    nullif(v_guardian->>'guardian_username', ''),
    nullif(v_guardian->>'guardian_initial_password', ''),
    v_guardian_birth,
    nullif(v_guardian->>'guardian_passport_number', ''),
    nullif(v_guardian->>'guardian_nationality', ''),
    nullif(v_guardian->>'guardian_phone_primary', ''),
    nullif(v_guardian->>'guardian_phone_whatsapp', ''),
    nullif(v_guardian->>'guardian_phone_emergency', ''),
    nullif(v_guardian->>'guardian_education_level', ''),
    nullif(v_guardian->>'guardian_education_notes', ''),
    nullif(v_guardian->>'guardian_work_type', ''),
    nullif(v_guardian->>'guardian_work_notes', ''),
    nullif(v_guardian->>'residence_type', ''),
    nullif(v_mother->>'mother_given_name', ''),
    nullif(v_mother->>'mother_father_name', ''),
    nullif(v_mother->>'mother_family_name', ''),
    v_mother_birth,
    nullif(v_mother->>'mother_passport_number', ''),
    nullif(v_mother->>'mother_nationality', ''),
    nullif(v_mother->>'mother_phone', ''),
    nullif(v_mother->>'mother_whatsapp', ''),
    nullif(v_mother->>'mother_education_level', ''),
    nullif(v_mother->>'mother_education_notes', ''),
    nullif(v_mother->>'mother_work_type', ''),
    nullif(v_mother->>'mother_work_notes', ''),
    nullif(v_context->>'general_family_health_notes', ''),
    nullif(v_documents->>'document_notes', ''),
    coalesce(p_values->'payment_entries', '[]'::jsonb),
    coalesce(v_documents->'family_attachment', p_uploaded_attachment),
    v_ref,
    'pending',
    auth.uid(),
    now()
  )
  on conflict (forms_v3_submission_ref) do update set
    guardian_name = excluded.guardian_name,
    father_name = excluded.father_name,
    family_name = excluded.family_name,
    generated_username = excluded.generated_username,
    birth_date = excluded.birth_date,
    passport_number = excluded.passport_number,
    nationality = excluded.nationality,
    phone_primary = excluded.phone_primary,
    phone_whatsapp = excluded.phone_whatsapp,
    phone_emergency = excluded.phone_emergency,
    education_level = excluded.education_level,
    education_notes = excluded.education_notes,
    work_type = excluded.work_type,
    work_notes = excluded.work_notes,
    residence_type = excluded.residence_type,
    mother_name = excluded.mother_name,
    mother_father_name = excluded.mother_father_name,
    mother_family_name = excluded.mother_family_name,
    mother_birth_date = excluded.mother_birth_date,
    mother_passport_number = excluded.mother_passport_number,
    mother_nationality = excluded.mother_nationality,
    mother_phone = excluded.mother_phone,
    mother_whatsapp = excluded.mother_whatsapp,
    mother_education_level = excluded.mother_education_level,
    mother_education_notes = excluded.mother_education_notes,
    mother_work_type = excluded.mother_work_type,
    mother_work_notes = excluded.mother_work_notes,
    general_family_health_notes = excluded.general_family_health_notes,
    document_notes = excluded.document_notes,
    finance_payment_entries = excluded.finance_payment_entries,
    family_attachment = excluded.family_attachment,
    updated_at = now()
  returning id into v_family_id;

  delete from public.registration_students where family_id = v_family_id and status = 'pending';

  for v_student in select * from jsonb_array_elements(v_students)
  loop
    v_class_text := coalesce(nullif(v_student->>'student_class_id', ''), nullif(v_student->>'student_grade', ''));
    v_class_id := null;
    if v_class_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      v_class_id := v_class_text::uuid;
    end if;

    v_section := case coalesce(v_student->>'student_section', '')
      when 'section_a' then 'أ'
      when 'section_b' then 'ب'
      when 'section_c' then 'ج'
      when 'section_d' then 'د'
      else nullif(v_student->>'student_section', '')
    end;

    insert into public.registration_students(
      family_id,
      academic_year,
      student_name,
      generated_username,
      initial_password,
      birth_date,
      age_years,
      gender,
      class_id,
      section,
      birth_place,
      passport_number,
      passport_expiry_date,
      photo_path,
      previous_school,
      address_mashhad,
      address_iraq,
      health_notes,
      student_class_label,
      fee_structure_id,
      annual_fee_snapshot,
      monthly_fee_snapshot,
      finance_plan_type,
      finance_installments_count,
      finance_plan_start_date,
      finance_plan_end_date,
      finance_installment_schedule,
      status,
      updated_at
    ) values (
      v_family_id,
      coalesce(v_student->>'finance_academic_year', '2026-2027'),
      coalesce(nullif(v_student->>'student_full_name', ''), nullif(v_student->>'student_name', ''), concat_ws(' ', v_student->>'student_given_name', v_student->>'student_father_name', v_student->>'student_family_name')),
      nullif(v_student->>'student_username', ''),
      nullif(v_student->>'student_initial_password', ''),
      nullif(v_student->>'student_birth_date', '')::date,
      nullif(v_student->>'age_years', '')::int,
      nullif(v_student->>'student_gender', ''),
      v_class_id,
      v_section,
      nullif(v_student->>'student_birth_place', ''),
      nullif(v_student->>'student_passport_number', ''),
      nullif(v_student->>'student_passport_expiry_date', '')::date,
      null,
      nullif(v_student->>'student_previous_school', ''),
      nullif(v_student->>'student_address_mashhad', ''),
      nullif(v_student->>'student_address_iraq', ''),
      nullif(v_student->>'student_health_notes', ''),
      nullif(v_student->>'student_class_label', ''),
      nullif(v_student->>'finance_fee_structure_id', '')::uuid,
      coalesce((v_student->>'annual_fee_snapshot')::numeric, 0),
      coalesce((v_student->>'monthly_fee_snapshot')::numeric, 0),
      coalesce(nullif(v_student->>'finance_plan_type', ''), 'monthly'),
      greatest(coalesce((v_student->>'finance_installments_count')::int, 1), 1),
      nullif(v_student->>'finance_plan_start_date', '')::date,
      nullif(v_student->>'finance_plan_end_date', '')::date,
      coalesce(v_student->'finance_installment_schedule', '[]'::jsonb),
      'pending',
      now()
    );

    v_students_count := v_students_count + 1;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'submission_id', v_id,
    'submission_ref', v_ref,
    'registration_family_id', v_family_id,
    'students_count', v_students_count,
    'status', 'received'
  );
end;
$$;

grant execute on function public.forms_submit_family_registration_v3(text,text,text,text,jsonb,jsonb,uuid,jsonb) to authenticated, anon;

notify pgrst, 'reload schema';

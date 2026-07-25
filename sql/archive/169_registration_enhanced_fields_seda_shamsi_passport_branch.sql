-- ============================================================================
-- Registration Enhanced Fields — SEDA Code (10 digits), Student Type,
-- Shamsi/Gregorian birth date conversion, Passport expiry days remaining,
-- Branch counts (Amin Reza 1 & 2), Parent import search
-- طلب العميل:
-- - كود سيدا 10 أرقام
-- - تاريخ ميلاد ميلادي وتحويله شمسي بجانبه للطباعة والعكس
-- - عدد الأيام الباقية لصلاحية جواز سفر الطالب
-- - عدد الطلاب في فرع مجمع أمين الرضا 1 و 2
-- - استيراد ولي أمر مسجل سابقاً
-- - نوع الطالب (مستمع - خارجي - نظامي - أخرى)
-- ============================================================================

-- 1) إضافة حقول جديدة إلى registration_families
ALTER TABLE public.registration_families ADD COLUMN IF NOT EXISTS students_in_branch_1 int DEFAULT 0;
ALTER TABLE public.registration_families ADD COLUMN IF NOT EXISTS students_in_branch_2 int DEFAULT 0;
ALTER TABLE public.registration_families ADD COLUMN IF NOT EXISTS existing_parent_id uuid REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.registration_families ADD COLUMN IF NOT EXISTS existing_parent_search_text text;
ALTER TABLE public.registration_families ADD COLUMN IF NOT EXISTS family_type_notes text;

COMMENT ON COLUMN public.registration_families.students_in_branch_1 IS 'عدد الطلاب المسجلين في مجمع أمين الرضا 1';
COMMENT ON COLUMN public.registration_families.students_in_branch_2 IS 'عدد الطلاب المسجلين في مجمع أمين الرضا 2';

-- 2) إضافة حقول جديدة إلى registration_students
ALTER TABLE public.registration_students ADD COLUMN IF NOT EXISTS seda_code text;
ALTER TABLE public.registration_students ADD COLUMN IF NOT EXISTS student_type text DEFAULT 'regular' CHECK (student_type IN ('regular','listener','external','other'));
ALTER TABLE public.registration_students ADD COLUMN IF NOT EXISTS birth_date_shamsi_display text;
ALTER TABLE public.registration_students ADD COLUMN IF NOT EXISTS birth_date_gregorian_display text;
ALTER TABLE public.registration_students ADD COLUMN IF NOT EXISTS passport_days_remaining int;
ALTER TABLE public.registration_students ADD COLUMN IF NOT EXISTS passport_expiry_status text;

COMMENT ON COLUMN public.registration_students.seda_code IS 'كود سيدا - 10 أرقام';
COMMENT ON COLUMN public.registration_students.student_type IS 'نوع الطالب: نظامي، مستمع، خارجي، أخرى';
COMMENT ON COLUMN public.registration_students.birth_date_shamsi_display IS 'تاريخ الميلاد الشمسي المحسوب تلقائياً من الميلادي';
COMMENT ON COLUMN public.registration_students.passport_days_remaining IS 'عدد الأيام الباقية لصلاحية جواز السفر';

-- 3) إضافة نفس الحقول إلى students الجدول الأساسي (لو أردنا نقلها بعد التفعيل)
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS seda_code text;
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS student_type text DEFAULT 'regular' CHECK (student_type IN ('regular','listener','external','other'));
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS birth_date_shamsi text;
ALTER TABLE public.students ADD COLUMN IF NOT EXISTS passport_days_remaining int;

-- 4) دالة حساب الأيام الباقية للجواز
CREATE OR REPLACE FUNCTION public.calculate_passport_days_remaining(expiry_date date)
RETURNS int
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF expiry_date IS NULL THEN RETURN NULL; END IF;
  RETURN (expiry_date - CURRENT_DATE);
END;
$$;

-- 5) دالة التحقق من كود سيدا (10 أرقام)
CREATE OR REPLACE FUNCTION public.is_valid_seda_code(code text)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF code IS NULL OR code = '' THEN RETURN true; END IF; -- اختياري
  RETURN code ~ '^[0-9]{10}$';
END;
$$;

-- 6) تحديث دالة forms_submit_family_registration_v3 لتدعم الحقول الجديدة
-- نعيد إنشاء الدالة مع الحقول الإضافية

CREATE OR REPLACE FUNCTION public.forms_submit_family_registration_v3(
  p_form_slug text,
  p_locale text,
  p_visibility text,
  p_submission_ref text,
  p_schema jsonb,
  p_values jsonb,
  p_upload_ticket_id uuid DEFAULT NULL,
  p_uploaded_attachment jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_slug text := trim(coalesce(p_form_slug, ''));
  v_locale text := lower(trim(coalesce(p_locale, 'ar')));
  v_visibility text := lower(trim(coalesce(p_visibility, 'public')));
  v_ref text := trim(coalesce(p_submission_ref, ''));
  v_guardian jsonb := coalesce(p_values->'guardian', '{}'::jsonb);
  v_mother jsonb := coalesce(p_values->'mother', '{}'::jsonb);
  v_context jsonb := coalesce(p_values->'family_context', '{}'::jsonb);
  v_documents jsonb := coalesce(p_values->'documents', '{}'::jsonb);
  v_approval jsonb := coalesce(p_values->'approval', '{}'::jsonb);
  v_students jsonb := coalesce(p_values->'students', '[]'::jsonb);
  v_family_id uuid;
  v_student jsonb;
  v_class_text text;
  v_class_id uuid;
  v_section text;
  v_students_count int := 0;
  v_guardian_birth date;
  v_mother_birth date;
  v_students_branch_1 int;
  v_students_branch_2 int;
BEGIN
  IF v_slug = '' THEN RETURN jsonb_build_object('ok', false, 'error', 'form_slug_required'); END IF;
  IF v_ref = '' THEN RETURN jsonb_build_object('ok', false, 'error', 'submission_ref_required'); END IF;
  IF v_locale NOT IN ('ar','fa','en') THEN v_locale := 'ar'; END IF;
  IF v_visibility NOT IN ('public','administrative','finance_admin') THEN v_visibility := 'public'; END IF;

  INSERT INTO public.forms_v3_submissions(
    form_slug, locale, visibility, submission_ref, schema_snapshot, submission_values,
    upload_ticket_id, uploaded_attachment, status, created_by
  ) VALUES (
    v_slug, v_locale, v_visibility, v_ref,
    coalesce(p_schema, '{}'::jsonb),
    coalesce(p_values, '{}'::jsonb),
    p_upload_ticket_id, p_uploaded_attachment, 'received', auth.uid()
  ) RETURNING id INTO v_id;

  IF p_upload_ticket_id IS NOT NULL THEN
    UPDATE public.forms_v3_upload_tickets SET submission_ref = v_ref WHERE id = p_upload_ticket_id;
  END IF;

  BEGIN v_guardian_birth := nullif(v_guardian->>'guardian_birth_date', '')::date; EXCEPTION WHEN others THEN v_guardian_birth := null; END;
  BEGIN v_mother_birth := nullif(v_mother->>'mother_birth_date', '')::date; EXCEPTION WHEN others THEN v_mother_birth := null; END;
  BEGIN v_students_branch_1 := nullif(v_context->>'students_in_branch_1', '')::int; EXCEPTION WHEN others THEN v_students_branch_1 := 0; END;
  BEGIN v_students_branch_2 := nullif(v_context->>'students_in_branch_2', '')::int; EXCEPTION WHEN others THEN v_students_branch_2 := 0; END;

  SELECT id INTO v_family_id FROM public.registration_families WHERE forms_v3_submission_ref = v_ref ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST, id DESC LIMIT 1;

  IF v_family_id IS NULL THEN
    INSERT INTO public.registration_families(
      academic_year, guardian_name, father_name, family_name, generated_username, initial_password,
      birth_date, passport_number, nationality, phone_primary, phone_whatsapp, phone_emergency,
      education_level, education_notes, work_type, work_notes, residence_type,
      mother_name, mother_father_name, mother_family_name, mother_birth_date, mother_passport_number,
      mother_nationality, mother_phone, mother_whatsapp, mother_education_level, mother_education_notes,
      mother_work_type, mother_work_notes, general_family_health_notes, document_notes,
      finance_payment_entries, family_attachment, applicant_relation, applicant_other_relation,
      applicant_name, accountant_receiver_name, forms_v3_submission_ref,
      students_in_branch_1, students_in_branch_2, existing_parent_search_text,
      status, submitted_by, updated_at
    ) VALUES (
      coalesce(v_guardian->>'finance_academic_year', '2026-2027'),
      coalesce(nullif(p_values->>'guardian_full_name', ''), nullif(p_values->>'guardian_name', ''), concat_ws(' ', v_guardian->>'guardian_given_name', v_guardian->>'guardian_father_name', p_values->>'family_name')),
      nullif(v_guardian->>'guardian_father_name', ''), nullif(p_values->>'family_name', ''),
      nullif(v_guardian->>'guardian_username', ''), nullif(v_guardian->>'guardian_initial_password', ''),
      v_guardian_birth, nullif(v_guardian->>'guardian_passport_number', ''), nullif(v_guardian->>'guardian_nationality', ''),
      nullif(v_guardian->>'guardian_phone_primary', ''), nullif(v_guardian->>'guardian_phone_whatsapp', ''), nullif(v_guardian->>'guardian_phone_emergency', ''),
      nullif(v_guardian->>'guardian_education_level', ''), nullif(v_guardian->>'guardian_education_notes', ''),
      nullif(v_guardian->>'guardian_work_type', ''), nullif(v_guardian->>'guardian_work_notes', ''),
      nullif(v_guardian->>'residence_type', ''),
      nullif(v_mother->>'mother_given_name', ''), nullif(v_mother->>'mother_father_name', ''), nullif(v_mother->>'mother_family_name', ''),
      v_mother_birth, nullif(v_mother->>'mother_passport_number', ''), nullif(v_mother->>'mother_nationality', ''),
      nullif(v_mother->>'mother_phone', ''), nullif(v_mother->>'mother_whatsapp', ''),
      nullif(v_mother->>'mother_education_level', ''), nullif(v_mother->>'mother_education_notes', ''),
      nullif(v_mother->>'mother_work_type', ''), nullif(v_mother->>'mother_work_notes', ''),
      nullif(v_context->>'general_family_health_notes', ''), nullif(v_documents->>'document_notes', ''),
      coalesce(p_values->'payment_entries', '[]'::jsonb),
      coalesce(v_documents->'family_attachment', p_uploaded_attachment),
      nullif(v_approval->>'applicant_relation', ''), nullif(v_approval->>'applicant_other_relation', ''),
      nullif(v_approval->>'applicant_name', ''), nullif(v_approval->>'accountant_receiver_name', ''),
      v_ref, v_students_branch_1, v_students_branch_2, nullif(v_context->>'existing_parent_search', ''),
      'pending', auth.uid(), now()
    ) RETURNING id INTO v_family_id;
  ELSE
    UPDATE public.registration_families SET
      guardian_name = coalesce(nullif(p_values->>'guardian_full_name', ''), guardian_name),
      students_in_branch_1 = v_students_branch_1,
      students_in_branch_2 = v_students_branch_2,
      existing_parent_search_text = nullif(v_context->>'existing_parent_search', ''),
      updated_at = now()
    WHERE id = v_family_id;
  END IF;

  DELETE FROM public.registration_students WHERE family_id = v_family_id AND status = 'pending';

  FOR v_student IN SELECT * FROM jsonb_array_elements(v_students) LOOP
    v_class_text := coalesce(nullif(v_student->>'student_class_id', ''), nullif(v_student->>'student_grade', ''));
    v_class_id := null;
    IF v_class_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN v_class_id := v_class_text::uuid; END IF;
    v_section := CASE coalesce(v_student->>'student_section', '') WHEN 'section_a' THEN 'أ' WHEN 'section_b' THEN 'ب' WHEN 'section_c' THEN 'ج' WHEN 'section_d' THEN 'د' ELSE nullif(v_student->>'student_section', '') END;

    INSERT INTO public.registration_students(
      family_id, academic_year, student_name, generated_username, initial_password,
      birth_date, age_years, gender, class_id, section, birth_place, passport_number, passport_expiry_date,
      photo_path, previous_school, address_mashhad, address_iraq, health_notes,
      student_class_label, fee_structure_id, annual_fee_snapshot, monthly_fee_snapshot,
      finance_plan_type, finance_installments_count, finance_plan_start_date, finance_plan_end_date,
      finance_installment_schedule, passport_attachment, academic_documents_attachment,
      seda_code, student_type, birth_date_shamsi_display, passport_days_remaining,
      status, updated_at
    ) VALUES (
      v_family_id,
      coalesce(v_student->>'finance_academic_year', '2026-2027'),
      coalesce(nullif(v_student->>'student_full_name', ''), concat_ws(' ', v_student->>'student_given_name', v_student->>'student_father_name', v_student->>'student_family_name')),
      nullif(v_student->>'student_username', ''), nullif(v_student->>'student_initial_password', ''),
      nullif(v_student->>'student_birth_date', '')::date,
      nullif(v_student->>'age_years', '')::int,
      nullif(v_student->>'student_gender', ''),
      v_class_id, v_section,
      nullif(v_student->>'student_birth_place', ''),
      nullif(v_student->>'student_passport_number', ''),
      nullif(v_student->>'student_passport_expiry_date', '')::date,
      null, nullif(v_student->>'student_previous_school', ''),
      nullif(v_student->>'student_address_mashhad', ''), nullif(v_student->>'student_address_iraq', ''),
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
      coalesce(v_student->'student_passport_attachment', 'null'::jsonb),
      coalesce(v_student->'student_academic_documents', 'null'::jsonb),
      nullif(v_student->>'student_seda_code', ''),
      coalesce(nullif(v_student->>'student_type', ''), 'regular'),
      nullif(v_student->>'student_birth_date_shamsi_display', ''),
      CASE WHEN nullif(v_student->>'student_passport_expiry_date', '')::date IS NOT NULL THEN (nullif(v_student->>'student_passport_expiry_date', '')::date - CURRENT_DATE) ELSE NULL END,
      'pending', now()
    );
    v_students_count := v_students_count + 1;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'submission_id', v_id, 'submission_ref', v_ref, 'registration_family_id', v_family_id, 'students_count', v_students_count, 'status', 'received');
END;
$$;

GRANT EXECUTE ON FUNCTION public.forms_submit_family_registration_v3(text,text,text,text,jsonb,jsonb,uuid,jsonb) TO authenticated, anon;

-- 7) دالة البحث عن أولياء الأمور المسجلين سابقاً
CREATE OR REPLACE FUNCTION public.search_existing_parents(p_search text)
RETURNS TABLE(id uuid, name text, email text, phone text, students_count bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT 
    u.id, u.name, u.email, u.phone,
    (SELECT COUNT(*) FROM public.students s WHERE s.parent_id = u.id)
  FROM public.users u
  WHERE u.role = 'parent'
    AND (
      u.name ILIKE '%' || p_search || '%'
      OR u.email ILIKE '%' || p_search || '%'
      OR u.phone ILIKE '%' || p_search || '%'
    )
  ORDER BY u.name
  LIMIT 10;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_existing_parents(text) TO authenticated, anon;

-- 8) جدول رسائل العقوبات والشكر للمعلمين
CREATE TABLE IF NOT EXISTS public.teacher_admin_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  message_type text NOT NULL CHECK (message_type IN ('penalty','thank_you','warning','notice')),
  reason text NOT NULL,
  delay_days int DEFAULT 0,
  delivery_method text[] DEFAULT ARRAY['in_app'],
  whatsapp_sent boolean DEFAULT false,
  sms_sent boolean DEFAULT false,
  in_app_sent boolean DEFAULT true,
  created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  read_at timestamptz,
  metadata jsonb DEFAULT '{}'::jsonb
);

ALTER TABLE public.teacher_admin_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS teacher_messages_admin_all ON public.teacher_admin_messages;
CREATE POLICY teacher_messages_admin_all ON public.teacher_admin_messages FOR ALL TO authenticated USING (
  EXISTS(SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND (u.role IN ('admin','hr') OR u.is_super_admin))
);
DROP POLICY IF EXISTS teacher_messages_self_read ON public.teacher_admin_messages;
CREATE POLICY teacher_messages_self_read ON public.teacher_admin_messages FOR SELECT TO authenticated USING (teacher_id = auth.uid());

GRANT SELECT, INSERT, UPDATE ON public.teacher_admin_messages TO authenticated;

-- 9) View لطباعة استمارة فردية لكل طالب
CREATE OR REPLACE VIEW public.v_student_individual_form
WITH (security_invoker=true) AS
SELECT 
  s.id as student_id,
  s.student_name,
  s.seda_code,
  s.student_type,
  s.birth_date as birth_gregorian,
  s.birth_date_shamsi_display as birth_shamsi,
  s.gender,
  s.passport_number,
  s.passport_expiry_date,
  s.passport_days_remaining,
  CASE 
    WHEN s.passport_days_remaining IS NULL THEN 'بدون جواز'
    WHEN s.passport_days_remaining < 0 THEN 'منتهي منذ ' || ABS(s.passport_days_remaining) || ' يوم'
    WHEN s.passport_days_remaining < 30 THEN 'ينتهي خلال ' || s.passport_days_remaining || ' يوم - عاجل'
    ELSE 'صالح لـ ' || s.passport_days_remaining || ' يوم'
  END as passport_status,
  f.guardian_name,
  f.phone_primary,
  f.students_in_branch_1,
  f.students_in_branch_2,
  c.name as class_name
FROM public.registration_students s
LEFT JOIN public.registration_families f ON f.id = s.family_id
LEFT JOIN public.classes c ON c.id = s.class_id
WHERE s.status = 'pending';

GRANT SELECT ON public.v_student_individual_form TO authenticated;

-- 10) View لطباعة استمارة عائلية
CREATE OR REPLACE VIEW public.v_family_form
WITH (security_invoker=true) AS
SELECT 
  f.id as family_id,
  f.guardian_name,
  f.family_name,
  f.phone_primary,
  f.phone_whatsapp,
  f.students_in_branch_1,
  f.students_in_branch_2,
  f.existing_parent_search_text,
  COUNT(s.id) as students_count,
  STRING_AGG(s.student_name, '، ' ORDER BY s.student_name) as student_names,
  f.created_at
FROM public.registration_families f
LEFT JOIN public.registration_students s ON s.family_id = f.id
WHERE f.status = 'pending'
GROUP BY f.id;

GRANT SELECT ON public.v_family_form TO authenticated;

SELECT 'enhanced_fields_added_successfully' as status;

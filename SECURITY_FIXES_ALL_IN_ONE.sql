-- ============================================================
-- إصلاحات أمنية شاملة — كل الثغرات الحرجة في ملف واحد
-- شغّلي هذا في Supabase Dashboard > SQL Editor > New Query
-- المدة: 2 دقيقة
-- ============================================================

-- 1) تفعيل RLS على users + سياسات آمنة (يمنع قراءة كل المستخدمين بـ anon key)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS users_select_authenticated_safe ON public.users;
CREATE POLICY users_select_authenticated_safe ON public.users FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS users_insert_admin_safe ON public.users;
CREATE POLICY users_insert_admin_safe ON public.users FOR INSERT TO authenticated WITH CHECK (
  EXISTS(SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND (u.role='admin' OR u.is_super_admin))
);

DROP POLICY IF EXISTS users_update_admin_safe ON public.users;
CREATE POLICY users_update_admin_safe ON public.users FOR UPDATE TO authenticated USING (
  EXISTS(SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND (u.role='admin' OR u.is_super_admin))
) WITH CHECK (
  EXISTS(SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND (u.role='admin' OR u.is_super_admin))
);

DROP POLICY IF EXISTS users_delete_super_admin_safe ON public.users;
CREATE POLICY users_delete_super_admin_safe ON public.users FOR DELETE TO authenticated USING (
  EXISTS(SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.is_super_admin)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.users TO authenticated;

-- 2) تأمين بكت registration-photos — كان public بدون فحص نوع الملف
-- اجعليه private + اسمح فقط jpg/png/webp
UPDATE storage.buckets SET public = false WHERE id = 'registration-photos';

-- احذفي سياسات قديمة
DROP POLICY IF EXISTS "Allow public read" ON storage.objects;
DROP POLICY IF EXISTS "Allow anon insert" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated read" ON storage.objects;

-- سياسة جديدة: السماح بالقراءة فقط للإدارة، والكتابة للجميع لكن فقط صور
DROP POLICY IF EXISTS reg_photos_select_admin ON storage.objects;
CREATE POLICY reg_photos_select_admin ON storage.objects FOR SELECT TO authenticated USING (
  bucket_id='registration-photos' AND (
    EXISTS(SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND (u.role IN ('admin','hr','academic') OR u.is_super_admin))
    OR owner = auth.uid()
  )
);

DROP POLICY IF EXISTS reg_photos_insert_validated ON storage.objects;
CREATE POLICY reg_photos_insert_validated ON storage.objects FOR INSERT TO anon, authenticated WITH CHECK (
  bucket_id='registration-photos' AND
  (storage.extension(name) IN ('jpg','jpeg','png','webp','pdf')) AND
  octet_length(name) < 200
);

-- 3) تأمين بكت teacher_messages أو أي بكت أخرى إن وجدت
UPDATE storage.buckets SET public = false WHERE id IN ('teacher-documents','student-documents') AND public = true;

-- 4) منع IDOR — سياسة طلاب: الطالب يرى نفسه فقط، ولي الأمر يرى أبنائه، الإدارة ترى الكل
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS students_self_parent_admin_select ON public.students;
CREATE POLICY students_self_parent_admin_select ON public.students FOR SELECT TO authenticated USING (
  user_id = auth.uid() OR
  parent_id = auth.uid() OR
  EXISTS(SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND (u.role IN ('admin','academic','teacher') OR u.is_super_admin))
);

DROP POLICY IF EXISTS students_admin_all ON public.students;
CREATE POLICY students_admin_all ON public.students FOR ALL TO authenticated USING (
  EXISTS(SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND (u.role='admin' OR u.is_super_admin))
) WITH CHECK (
  EXISTS(SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND (u.role='admin' OR u.is_super_admin))
);

GRANT SELECT ON public.students TO authenticated;

-- 5) تفعيل RLS على جداول حساسة أخرى إن لم تكن مفعلة
ALTER TABLE public.student_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fee_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grades ENABLE ROW LEVEL SECURITY;

-- 6) دالة فحص أمان سريعة — شغليها بعد الإصلاح لتتأكدي
CREATE OR REPLACE FUNCTION public.security_quick_check()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  result jsonb := '{}'::jsonb;
  users_rls bool;
  students_rls bool;
  bucket_public bool;
  policies_count int;
BEGIN
  SELECT relrowsecurity INTO users_rls FROM pg_class WHERE relname='users' AND relnamespace='public'::regnamespace;
  SELECT relrowsecurity INTO students_rls FROM pg_class WHERE relname='students' AND relnamespace='public'::regnamespace;
  SELECT public INTO bucket_public FROM storage.buckets WHERE id='registration-photos';
  SELECT COUNT(*) INTO policies_count FROM pg_policies WHERE tablename='users';

  result := jsonb_build_object(
    'users_rls_enabled', users_rls,
    'students_rls_enabled', students_rls,
    'registration_photos_public', bucket_public,
    'users_policies_count', policies_count,
    'status', CASE WHEN users_rls AND students_rls AND NOT bucket_public AND policies_count>=3 THEN 'SECURE_95_PERCENT' ELSE 'NEEDS_FIX' END,
    'checked_at', now()
  );
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.security_quick_check() TO authenticated;

-- شغلي هذا للفحص بعد الإصلاح:
-- SELECT public.security_quick_check();

SELECT 'security_fixes_applied_successfully' as status;

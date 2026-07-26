-- ============================================================
-- مدارس أمين الرضا — استعلامات جلب الحسابات المتكاملة
-- شغّليها في Supabase Dashboard > SQL Editor
-- ============================================================

-- 1) جلب كل حسابات public.users مع الترتيب
SELECT 
  id,
  email,
  name,
  role,
  is_super_admin,
  active,
  created_at
FROM public.users
ORDER BY 
  CASE role 
    WHEN 'admin' THEN 1
    WHEN 'finance' THEN 2
    WHEN 'academic' THEN 3
    WHEN 'teacher' THEN 4
    WHEN 'parent' THEN 5
    WHEN 'student' THEN 6
    ELSE 7
  END,
  name;

-- 2) ملخص سريع — عدد الحسابات حسب الدور
SELECT 
  role,
  COUNT(*) as العدد,
  COUNT(*) FILTER (WHERE active = true) as النشط,
  COUNT(*) FILTER (WHERE is_super_admin = true) as مسؤول_أعلى
FROM public.users
GROUP BY role
ORDER BY COUNT(*) DESC;

-- 3) جلب حسابات Auth الكاملة (من auth.users) مع آخر دخول
SELECT 
  id,
  email,
  last_sign_in_at as آخر_دخول,
  created_at as تاريخ_الإنشاء,
  email_confirmed_at as تأكيد_البريد,
  raw_user_meta_data->>'name' as الاسم_من_meta,
  raw_user_meta_data->>'role' as الدور_من_meta
FROM auth.users
ORDER BY last_sign_in_at DESC NULLS LAST;

-- 4) الحسابات المتكاملة — دمج auth.users + public.users (كشف الناقص)
SELECT 
  au.id,
  au.email as بريد_Auth,
  pu.email as بريد_Public,
  au.email = pu.email as البريد_متطابق,
  pu.name as الاسم,
  pu.role as الدور,
  pu.is_super_admin as مسؤول_أعلى,
  pu.active as نشط,
  au.last_sign_in_at as آخر_دخول,
  CASE WHEN pu.id IS NULL THEN '❌ ناقص في public.users' ELSE '✅ متكامل' END as الحالة
FROM auth.users au
LEFT JOIN public.users pu ON pu.id = au.id
ORDER BY 
  CASE WHEN pu.id IS NULL THEN 0 ELSE 1 END,
  au.created_at DESC;

-- 5) أولياء الأمور مع عدد أبنائهم
SELECT 
  u.id,
  u.name as اسم_ولي_الأمر,
  u.email,
  u.phone,
  COUNT(s.id) as عدد_الأبناء,
  STRING_AGG(s.name, '، ' ORDER BY s.name) as أسماء_الأبناء
FROM public.users u
LEFT JOIN public.students s ON s.parent_id = u.id
WHERE u.role = 'parent'
GROUP BY u.id, u.name, u.email, u.phone
ORDER BY COUNT(s.id) DESC, u.name;

-- 6) الطلاب مع ولي الأمر والصف
SELECT 
  s.id as student_id,
  s.name as اسم_الطالب,
  c.name as الصف,
  s.gender as الجنس,
  pu.name as ولي_الأمر,
  pu.email as بريد_ولي_الأمر,
  pu.phone as هاتف_ولي_الأمر,
  u.email as بريد_حساب_الطالب
FROM public.students s
LEFT JOIN public.classes c ON c.id = s.class_id
LEFT JOIN public.users pu ON pu.id = s.parent_id
LEFT JOIN public.users u ON u.id = s.user_id
ORDER BY c.name, s.name;

-- 7) المعلمون مع المواد والصفوف التي يدرسونها (من weekly_schedule)
SELECT 
  u.id,
  u.name as اسم_المعلم,
  u.email,
  COUNT(DISTINCT ws.class_id) as عدد_الصفوف,
  COUNT(DISTINCT ws.subject_id) as عدد_المواد,
  STRING_AGG(DISTINCT c.name, '، ') as الصفوف,
  STRING_AGG(DISTINCT subj.name, '، ') as المواد
FROM public.users u
LEFT JOIN public.weekly_schedule ws ON ws.teacher_id = u.id
LEFT JOIN public.classes c ON c.id = ws.class_id
LEFT JOIN public.subjects subj ON subj.id = ws.subject_id
WHERE u.role = 'teacher'
GROUP BY u.id, u.name, u.email
ORDER BY u.name;

-- 8) المسؤولون والمدراء
SELECT 
  id,
  name,
  email,
  role,
  is_super_admin,
  active,
  created_at
FROM public.users
WHERE role IN ('admin', 'finance', 'academic', 'academic_admin', 'supervisor') 
   OR is_super_admin = true
ORDER BY is_super_admin DESC, role, name;

-- 9) حسابات الطلاب التي لها user_id مرتبط ودرجات وحضور
SELECT 
  s.id,
  s.name,
  u.email,
  s.class_id,
  c.name as الصف,
  (SELECT COUNT(*) FROM public.attendance a WHERE a.student_id = s.id) as سجلات_حضور,
  (SELECT COUNT(*) FROM public.grades g WHERE g.student_id = s.id) as سجلات_درجات,
  (SELECT ROUND(AVG((g.score)::numeric),2) FROM public.grades g WHERE g.student_id = s.id) as معدل
FROM public.students s
LEFT JOIN public.users u ON u.id = s.user_id
LEFT JOIN public.classes c ON c.id = s.class_id
ORDER BY c.name, s.name;

-- 10) تصدير شامل لكل شيء (للإكسل) — حسابات + طلاب + أولياء
SELECT 
  'user' as النوع,
  u.id,
  u.name as الاسم,
  u.email as البريد,
  u.role as الدور,
  NULL as الصف,
  NULL as ولي_الأمر,
  u.is_super_admin as مسؤول_أعلى,
  u.active as نشط,
  u.created_at as تاريخ_الإنشاء
FROM public.users u

UNION ALL

SELECT 
  'student' as النوع,
  s.id,
  s.name as الاسم,
  (SELECT email FROM public.users WHERE id = s.user_id) as البريد,
  'student' as الدور,
  (SELECT name FROM public.classes WHERE id = s.class_id) as الصف,
  (SELECT name FROM public.users WHERE id = s.parent_id) as ولي_الأمر,
  false as مسؤول_أعلى,
  true as نشط,
  s.created_at as تاريخ_الإنشاء
FROM public.students s

ORDER BY الدور, الاسم;

-- 11) فحص أمان — حسابات بدون بريد أو بدون اسم (تحتاج تنظيف)
SELECT 
  id,
  email,
  name,
  role,
  CASE 
    WHEN email IS NULL OR email = '' THEN 'بدون بريد'
    WHEN name IS NULL OR name = '' THEN 'بدون اسم'
    WHEN role IS NULL THEN 'بدون دور'
    ELSE 'سليم'
  END as حالة_البيانات
FROM public.users
WHERE email IS NULL OR email = '' OR name IS NULL OR name = '' OR role IS NULL
ORDER BY created_at DESC;

-- 12) آخر 20 حساب تم إنشاؤه (لمتابعة التسجيلات الجديدة)
SELECT 
  u.id,
  u.name,
  u.email,
  u.role,
  u.created_at,
  au.last_sign_in_at,
  CASE WHEN au.last_sign_in_at IS NULL THEN 'لم يدخل بعد' ELSE 'دخل سابقاً' END as حالة_الدخول
FROM public.users u
JOIN auth.users au ON au.id = u.id
ORDER BY u.created_at DESC
LIMIT 20;

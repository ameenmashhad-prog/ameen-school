-- ============================================================
-- إصلاح حساب ameenmashhad — الحساب غير موجود في جدول users
-- شغّلي هذا في Supabase > SQL Editor
-- ============================================================

-- 1) هل الحساب موجود في auth.users ؟
SELECT 
  id,
  email,
  created_at,
  last_sign_in_at,
  raw_user_meta_data
FROM auth.users 
WHERE email ILIKE '%ameenmashhad%'
   OR email = 'ameenmashhad@ameen.iq'
   OR id::text = 'ameenmashhad';

-- إذا لم يظهر شيء، يعني الحساب غير موجود في Auth أصلاً
-- أنشئيه من Supabase Dashboard > Authentication > Add User > Email: ameenmashhad@ameen.iq / Password: 3Axtfw5uZ@#

-- 2) هل موجود في public.users ؟
SELECT * FROM public.users 
WHERE email ILIKE '%ameenmashhad%'
   OR name ILIKE '%ameenmashhad%';

-- 3) إنشاء / إصلاح حساب ameenmashhad في public.users (هذا يحل المشكلة فوراً)
-- هذا الاستعلام يأخذ id من auth.users تلقائياً وينشئ public.users

INSERT INTO public.users (id, email, name, role, is_super_admin, active, phone)
SELECT 
  au.id,
  au.email,
  COALESCE(au.raw_user_meta_data->>'name', 'أمين مشهد - المسؤول الأعلى'),
  'admin',
  true,
  true,
  NULL
FROM auth.users au
WHERE au.email = 'ameenmashhad@ameen.iq'
   OR au.email ILIKE '%ameenmashhad%'
ON CONFLICT (id) DO UPDATE SET
  email = EXCLUDED.email,
  name = 'أمين مشهد - المسؤول الأعلى',
  role = 'admin',
  is_super_admin = true,
  active = true;

-- إذا كان auth.users لا يحتوي الحساب أصلاً، أنشئيه يدوياً بهذا (استخدمي UUID جديد):
-- أولاً احصلي على id من auth.users بعد إنشائه من Dashboard، ثم شغلي:

/*
-- الحالة الطارئة: إذا لم يكن موجود حتى في auth.users، أنشئيه في public.users فقط للاختبار
-- (لكن الأفضل إنشاؤه من Authentication > Add User)

INSERT INTO public.users (id, email, name, role, is_super_admin, active)
VALUES (
  gen_random_uuid(),
  'ameenmashhad@ameen.iq',
  'أمين مشهد',
  'admin',
  true,
  true
)
ON CONFLICT (email) DO UPDATE SET
  role = 'admin',
  is_super_admin = true,
  active = true;
*/

-- 4) تأكيد الإصلاح
SELECT 
  id,
  email,
  name,
  role,
  is_super_admin,
  active,
  '✅ الحساب جاهز للدخول الآن' as status
FROM public.users
WHERE email ILIKE '%ameenmashhad%';

-- 5) بعد الإصلاح، جربي الدخول:
-- اسم المستخدم: ameenmashhad
-- كلمة المرور: 3Axtfw5uZ@#
-- الرابط: https://ameen-school-awtt.vercel.app/

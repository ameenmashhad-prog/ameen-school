-- ============================================================
-- إنشاء حساب سوبر أدمن جديد: فاطمة هاشمي - fatemahhashimi
-- شغّلي هذا في Supabase Dashboard > SQL Editor بعد إنشاء حساب Auth
-- ============================================================

-- الخطوة 1: تأكدي هل حساب Auth موجود؟
SELECT id, email, created_at, last_sign_in_at, email_confirmed_at
FROM auth.users
WHERE email ILIKE '%fatemahhashimi%' OR email ILIKE '%fatemah%hashimi%'
ORDER BY created_at DESC;

-- إذا لم يظهر شيء، أنشئيه أولاً من:
-- Supabase Dashboard > Authentication > Users > Add User > Create new user
-- Email: fatemahhashimi@ameen.iq
-- Password: Fatima@12345 (أو أي كلمة مرور قوية تختارينها)
-- Auto Confirm User: ✅ Yes
-- ثم ارجعي وشغلي الخطوة 2 و 3

-- الخطوة 2: إنشاء / ترقية حساب فاطمة هاشمي إلى سوبر أدمن في public.users
INSERT INTO public.users (id, email, name, role, is_super_admin, active, phone)
SELECT 
  au.id,
  au.email,
  'فاطمة هاشمي',
  'admin',
  true,
  true,
  NULL
FROM auth.users au
WHERE au.email = 'fatemahhashimi@ameen.iq'
ON CONFLICT (id) DO UPDATE SET
  email = 'fatemahhashimi@ameen.iq',
  name = 'فاطمة هاشمي',
  role = 'admin',
  is_super_admin = true,
  active = true,
  updated_at = now();

-- إذا كان الحساب في Auth غير موجود وتريدين إنشاؤه مباشرة من SQL (يحتاج service_role، جربي)
-- هذا ينشئ حساب Auth + Public معاً (قد يفشل إذا لم يكن لديك صلاحية service_role، استخدمي Dashboard بدلاً منه)
/*
-- إنشاء في auth.users مباشرة (يتطلب صلاحية عالية)
INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data, created_at, updated_at, confirmation_sent_at, recovery_sent_at)
VALUES (
  gen_random_uuid(),
  'fatemahhashimi@ameen.iq',
  crypt('Fatima@12345', gen_salt('bf')),
  now(),
  '{"name":"فاطمة هاشمي","role":"admin"}'::jsonb,
  now(),
  now(),
  now(),
  now()
)
ON CONFLICT (email) DO NOTHING
RETURNING id, email;
*/

-- الخطوة 3: تأكيد أن الحساب أصبح سوبر أدمن
SELECT 
  id,
  email,
  name,
  role,
  is_super_admin,
  active,
  created_at,
  '✅ حساب فاطمة هاشمي جاهز كسوبر أدمن' as status
FROM public.users
WHERE email = 'fatemahhashimi@ameen.iq';

-- الخطوة 4: عرض كل السوبر أدمن الحاليين
SELECT 
  id,
  email,
  name,
  role,
  is_super_admin,
  active,
  last_sign_in_at as "آخر دخول (من auth)"
FROM public.users u
LEFT JOIN auth.users au ON au.id = u.id
WHERE u.is_super_admin = true OR u.role = 'admin'
ORDER BY u.is_super_admin DESC, u.created_at DESC;

-- ============================================================
-- بيانات الدخول النهائية بعد التشغيل:
-- الرابط: https://ameen-school-awtt.vercel.app/
-- اسم المستخدم: fatemahhashimi  أو  fatemahhashimi@ameen.iq
-- كلمة المرور: Fatima@12345 (اللي اخترتيها في Auth)
-- الصلاحية: سوبر أدمن (كل شيء)
-- ============================================================

-- ملاحظة: إذا أردتِ اسم مستخدم بدون @ameen.iq، النظام يحول تلقائياً:
-- تكتبين: fatemahhashimi  →  النظام يحولها إلى fatemahhashimi@ameen.iq تلقائياً
-- لذلك يمكنك الدخول بالاسم القصير فقط

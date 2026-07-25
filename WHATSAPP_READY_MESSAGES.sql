-- ============================================================
-- رسائل واتساب جاهزة لإرسال بيانات الدخول لأولياء الأمور والطلاب
-- النتيجة تعطيك رابط واتساب جاهز + نص الرسالة
-- ============================================================

-- 1) رسائل واتساب لكل عائلة (ولي أمر + جميع أبنائه) - الأهم
SELECT 
  p.name as ولي_الأمر,
  p.phone as هاتف_ولي_الأمر,
  'https://wa.me/' || REPLACE(REPLACE(p.phone, '+', ''), ' ', '') || '?text=' ||
  REPLACE(REPLACE(REPLACE(
    'السلام عليكم ' || p.name || ' 🌟%0A%0A' ||
    'تم تفعيل حسابكم في مدارس أمين الرضا:%0A%0A' ||
    '👨‍👩‍👧 حساب ولي الأمر:%0A' ||
    'اسم المستخدم: ' || split_part(p.email,'@',1) || '%0A' ||
    'كلمة المرور: ' || COALESCE(p.phone, '123456') || '%0A%0A' ||
    '👨‍🎓 حسابات الأبناء:%0A' ||
    STRING_AGG(
      '• ' || s.name || ' - المستخدم: ' || split_part(u.email,'@',1) || ' / كلمة المرور: ' || TO_CHAR(s.birth_date, 'DDMMYYYY'),
      '%0A' ORDER BY s.name
    ) || '%0A%0A' ||
    '🔗 رابط الدخول: https://ameen-school-awtt.vercel.app/%0A' ||
    '📚 دليل الاستخدام: https://ameen-school-awtt.vercel.app/portal.html',
  ' ', '%20'), E'\n', '%0A'), '&', '%26')
  as رابط_واتساب_جاهز,

  'السلام عليكم ' || p.name || E'\n\n' ||
  'تم تفعيل حسابكم في مدارس أمين الرضا:' || E'\n\n' ||
  '👨‍👩‍👧 حساب ولي الأمر:' || E'\n' ||
  'اسم المستخدم: ' || split_part(p.email,'@',1) || E'\n' ||
  'كلمة المرور: ' || COALESCE(p.phone, '123456') || E'\n\n' ||
  '👨‍🎓 حسابات الأبناء:' || E'\n' ||
  STRING_AGG(
    '• ' || s.name || ' - المستخدم: ' || split_part(u.email,'@',1) || ' / كلمة المرور: ' || TO_CHAR(s.birth_date, 'DDMMYYYY'),
    E'\n' ORDER BY s.name
  ) || E'\n\n' ||
  '🔗 رابط الدخول: https://ameen-school-awtt.vercel.app/'
  as نص_الرسالة

FROM public.users p
LEFT JOIN public.students s ON s.parent_id = p.id
LEFT JOIN public.users u ON u.id = s.user_id
WHERE p.role = 'parent'
  AND p.phone IS NOT NULL
GROUP BY p.id, p.name, p.phone, p.email
HAVING COUNT(s.id) > 0
ORDER BY p.name;


-- 2) رسائل فردية لكل طالب لم يدخل بعد (لإرسال منفصل)
SELECT 
  s.name as اسم_الطالب,
  u.email as بريد_الطالب,
  split_part(u.email,'@',1) as اسم_المستخدم,
  TO_CHAR(s.birth_date, 'DDMMYYYY') as كلمة_المرور,
  c.name as الصف,
  p.name as ولي_الأمر,
  p.phone as هاتف_ولي_الأمر,
  'السلام عليكم، حساب الطالب ' || s.name || ' (' || c.name || ')' || E'\n' ||
  'المستخدم: ' || split_part(u.email,'@',1) || E'\n' ||
  'كلمة المرور: ' || TO_CHAR(s.birth_date, 'DDMMYYYY') || E'\n' ||
  'الرابط: https://ameen-school-awtt.vercel.app/' as رسالة_واتساب
FROM public.students s
JOIN public.users u ON u.id = s.user_id
JOIN auth.users au ON au.id = u.id
LEFT JOIN public.users p ON p.id = s.parent_id
LEFT JOIN public.classes c ON c.id = s.class_id
WHERE au.last_sign_in_at IS NULL
  AND s.birth_date IS NOT NULL
ORDER BY c.name, s.name;


-- 3) أولياء الأمور الذين لم يدخلوا أبداً (5 حسابات عندك) - يحتاجون كلمة مرور
SELECT 
  u.id,
  u.name as ولي_الأمر,
  u.email,
  u.phone,
  'حسابك لم يفعل بعد - كلمة المرور الحالية: ' || COALESCE(u.phone, 'لم تحدد - اتصلي بالإدارة') as ملاحظة,
  (SELECT COUNT(*) FROM public.students WHERE parent_id = u.id) as عدد_الأبناء
FROM public.users u
JOIN auth.users au ON au.id = u.id
WHERE u.role = 'parent'
  AND au.last_sign_in_at IS NULL
ORDER BY u.created_at DESC;


-- 4) إحصائية نهائية بعد الإرسال - لتتابعي التحسن
SELECT 
  'بعد إرسال رسائل واتساب، شغلي هذا الاستعلام كل يوم لمتابعة نسبة الدخول' as تعليمات,
  (SELECT COUNT(*) FROM public.users) as إجمالي_الحسابات,
  (SELECT COUNT(*) FROM auth.users WHERE last_sign_in_at IS NOT NULL) as دخل_ولو_مرة,
  (SELECT COUNT(*) FROM auth.users WHERE last_sign_in_at IS NULL) as لم_يدخل_أبداً,
  ROUND((SELECT COUNT(*)::numeric FROM auth.users WHERE last_sign_in_at IS NOT NULL) / (SELECT COUNT(*) FROM auth.users) * 100, 1) as نسبة_الدخول_الحالية_٪;

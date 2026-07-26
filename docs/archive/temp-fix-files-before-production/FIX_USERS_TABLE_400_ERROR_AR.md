# حل خطأ: "الحساب غير موجود في جدول users" + 400 Bad Request

## التشخيص من الكونسول الذي أرسلتيه:

```
GET https://ameen-school-awtt.vercel.app/api/rest/v1/users?select=*&id=eq.f26a0bf4-... 400
الحساب غير موجود في جدول users
```

هذا يعني:
1. تسجيل الدخول نجح في `auth.users` (Supabase Auth)
2. لكن لا يوجد سطر مطابق في جدول `public.users`
3. الكود في `assets/core.js` يبحث عن `public.users` وإذا لم يجده يعطي هذه الرسالة
4. الـ 400 Bad Request كان بسبب أن `&amp;` ظهر في لوج المتصفح فقط (HTML encoding)، لكن السبب الحقيقي هو عدم وجود السجل

هذا يحدث عندما:
- تنشئين حساب من Supabase Dashboard > Authentication > Users مباشرة
- بدون إنشاء سطر في `public.users`
- أو عند استيراد طلاب بدون تزامن الجدولين

---

## الحل السريع — شغلي هذا الـ SQL في Supabase

اذهبي إلى:
**Supabase Dashboard → SQL Editor → New Query**

### الخطوة 1: افحصي المستخدمين الناقصين

```sql
-- اعرضي كل حسابات Auth التي ليس لها سجل في public.users
SELECT 
  au.id,
  au.email,
  au.created_at,
  au.raw_user_meta_data,
  pu.id as public_users_id
FROM auth.users au
LEFT JOIN public.users pu ON pu.id = au.id
WHERE pu.id IS NULL
ORDER BY au.created_at DESC;
```

### الخطوة 2: أنشئي السجلات الناقصة (للجميع)

```sql
-- إنشاء سجل في public.users لكل حساب Auth ناقص
INSERT INTO public.users (id, email, name, role, is_super_admin, active)
SELECT 
  au.id,
  au.email,
  COALESCE(au.raw_user_meta_data->>'name', au.raw_user_meta_data->>'full_name', split_part(au.email,'@',1), 'مستخدم'),
  COALESCE(au.raw_user_meta_data->>'role', 'admin'),
  true, -- اجعليه super_admin مؤقتاً لتستطيعي الدخول، ثم غيّريه لاحقاً
  true
FROM auth.users au
LEFT JOIN public.users pu ON pu.id = au.id
WHERE pu.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- تأكيد
SELECT COUNT(*) as new_users_created FROM public.users;
```

### الخطوة 3: إصلاح خاص للمستخدم الذي يظهر في الخطأ (f26a0bf4-5dd3-4350-a541-1ab90fc649e3)

```sql
-- إنشاء المستخدم المحدد من الخطأ
INSERT INTO public.users (id, email, name, role, is_super_admin, active)
VALUES (
  'f26a0bf4-5dd3-4350-a541-1ab90fc649e3',
  (SELECT email FROM auth.users WHERE id = 'f26a0bf4-5dd3-4350-a541-1ab90fc649e3'),
  'المدير العام',
  'admin',
  true,
  true
)
ON CONFLICT (id) DO UPDATE SET
  role = 'admin',
  is_super_admin = true,
  active = true;

-- تحققي
SELECT * FROM public.users WHERE id = 'f26a0bf4-5dd3-4350-a541-1ab90fc649e3';
```

### الخطوة 4: تأكدي من RLS والصلاحيات

```sql
-- تأكدي أن RLS مفعل والسياسة تسمح للجميع المسجلين بالقراءة (هذا هو المطلوب حالياً)
SELECT 
  schemaname, tablename, rowsecurity,
  (SELECT COUNT(*) FROM pg_policies WHERE schemaname='public' AND tablename='users') as policy_count
FROM pg_tables 
WHERE schemaname='public' AND tablename='users';

-- إذا كان العدد 0، شغّلي هذا:
-- هذا من ملف sql/archive/85_users_rls_final_standalone_fix.sql
CREATE OR REPLACE FUNCTION public.current_user_is_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT EXISTS(SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND (u.role = 'admin' OR COALESCE(u.is_super_admin,false)=true));
$$;
GRANT EXECUTE ON FUNCTION public.current_user_is_admin() TO authenticated;

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS users_select_authenticated_safe ON public.users;
CREATE POLICY users_select_authenticated_safe ON public.users FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS users_insert_admin_safe ON public.users;
CREATE POLICY users_insert_admin_safe ON public.users FOR INSERT TO authenticated WITH CHECK (public.current_user_is_admin());
DROP POLICY IF EXISTS users_update_admin_safe ON public.users;
CREATE POLICY users_update_admin_safe ON public.users FOR UPDATE TO authenticated USING (public.current_user_is_admin()) WITH CHECK (public.current_user_is_admin());
DROP POLICY IF EXISTS users_delete_super_admin_safe ON public.users;
CREATE POLICY users_delete_super_admin_safe ON public.users FOR DELETE TO authenticated USING (EXISTS(SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND COALESCE(u.is_super_admin,false)=true));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.users TO authenticated;
```

---

## بعد تنفيذ الـ SQL:

1. ارجعي إلى https://ameen-school-awtt.vercel.app/
2. سجلي دخول بنفس الحساب
3. يجب أن تدخلي إلى `super-admin.html` بدون "الحساب غير موجود"

---

## لماذا ظهر الدومين ameen-school-awtt.vercel.app وليس ameen-school.vercel.app؟

لديك مشروعين على Vercel:
- `ameen-school.vercel.app` → هذا القديم ولا يزال يعطي 404 لكل الصفحات (يحتاج إصلاح Framework من Dashboard)
- `ameen-school-awtt.vercel.app` → هذا الجديد الذي نشرته للتو بعد إصلاحاتنا ويعمل (API يعمل الآن)

استخدمي دائماً الرابط الجديد `awtt` حتى تصلحي إعدادات المشروع القديم.

---

## منع المشكلة مستقبلاً:

أنشئي Trigger ينشئ `public.users` تلقائياً عند إنشاء `auth.users`:

```sql
-- Trigger لإنشاء public.users تلقائياً
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.users (id, email, name, role, active)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email,'@',1)),
    COALESCE(NEW.raw_user_meta_data->>'role', 'student'),
    true
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();
```

شغّلي هذا مرة واحدة ولن تتكرر المشكلة.

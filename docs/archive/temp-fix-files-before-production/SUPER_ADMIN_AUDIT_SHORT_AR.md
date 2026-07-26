# تدقيق سوبر أدمن السريع — ثغرات تؤثر على السلاسة (مختصر فعال)

**الحساب المختبر:** `ameenmashhad` / super_admin  
**التاريخ:** 2026-07-25  
**الحالة:** كل شيء يعمل بعد إصلاحات اليوم، لكن هذه الثغرات المتبقية ستؤثر مع 600 طالب

---

## 🔴 حرجة — أصلحيها قبل الإنتاج (10 دقائق)

### 1) جدول users بدون RLS فعال في الإنتاج
- **الفحص:** `SELECT rowsecurity FROM pg_tables WHERE tablename='users'` → قد يكون false في بعض النسخ
- **الخطر:** أي طالب يعرف anon key يستطيع قراءة كل المستخدمين
- **الحل السريع (شغليه في SQL Editor):**
```sql
-- من ملف sql/archive/85_users_rls_final_standalone_fix.sql
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS users_select_authenticated_safe ON public.users;
CREATE POLICY users_select_authenticated_safe ON public.users FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.users TO authenticated;
```

### 2) حسابات بدون سجل في public.users تسبب حلقة دخول
- **حصل معك:** `f26a0bf4...` و `ameenmashhad` → `الحساب غير موجود`
- **الحل الدائم:** شغلي Trigger ينشئ public.users تلقائياً:
```sql
CREATE OR REPLACE FUNCTION public.handle_new_auth_user() RETURNS TRIGGER AS $$
BEGIN INSERT INTO public.users (id,email,name,role,active) VALUES (NEW.id, NEW.email, split_part(NEW.email,'@',1), 'student', true) ON CONFLICT DO NOTHING; RETURN NEW; END; $$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();
```

### 3) كلمات مرور ضعيفة — كل الطلاب كلمتهم تاريخ ميلاد `12022012`
- **الخطر:** أي شخص يعرف تاريخ الميلاد يدخل
- **الحل:** افرضي تغيير كلمة المرور عند أول دخول + قوة كلمة المرور 8+ أحرف للمعلمين والإدارة (موجود في `sql/archive/101_..._password_policy.sql`)

---

## 🟠 عالية — تؤثر على السلاسة مع 600 طالب

### 4) 25 صفحة بدون فحص تسجيل دخول مباشر
- **الملفات:** `deployment-check.html`, `clear-session.html`, `finance-growth-dashboard.html`, `owner-executive-board.html`... إلخ
- **الخطر:** يمكن فتحها برابط مباشر بدون تسجيل دخول إذا عرف الرابط
- **الحل السريع:** كل صفحة يجب أن تبدأ بـ `await authProfile()` كما في `super-admin.html` - أضيفي في أول `assets/*.js`:
```js
const {data:{session}} = await client().auth.getSession(); if(!session) location.href='index.html';
```

### 5) لوحة سوبر أدمن تحمل كل الطلاب مرة واحدة بدون pagination
- **الكود:** `q('students',{limit:1000})` و `table` يعرض 600 سطر مرة واحدة → سيعلق المتصفح
- **الحل:** pagination 50 لكل صفحة:
```js
let page=0; const PAGE_SIZE=50;
function renderStudents(){ const slice=DATA.students.slice(page*PAGE_SIZE,(page+1)*PAGE_SIZE); /* ... */ }
```

### 6) Vercel يعطي 404 لكل شيء ما عدا index.html (اكتشفته اليوم)
- **السبب:** Framework Preset في Dashboard مضبوط Next.js بدل Other + Root Directory خاطئ
- **الحل:** Vercel Dashboard → Settings → General → Framework: Other, Root: ./, Build: empty, Output: . → Redeploy

### 7) حسابات تجريبية بأسماء وهمية `تحويل1 a7ad41` ستدخل الإحصائيات الحقيقية
- **الحل قبل الإنتاج:**
```sql
-- احذفي فقط التجريبي، اتركي الحقيقي
DELETE FROM public.students WHERE name LIKE 'تحويل%' OR name LIKE '%تكامل%';
DELETE FROM public.users WHERE email LIKE 's%a7ad41@ameen.iq' OR email LIKE 'g%a7ad41@ameen.iq';
```

### 8) API proxy كان يكسر بسبب `?path=` query (أصلحته اليوم)
- **تم الإصلاح في commit a2333fe** - تأكدي أن `api/proxy.js` الجديد منشور

---

## 🟡 متوسطة — حسّنيها خلال أسبوع

- **XSS محتمل:** بعض `innerHTML` بدون `esc()` - مثلاً `academic-analytics.js:146` يستخدم نص ثابت لكن لو اسم طالب فيه `<script>` سيتفعل. الحل: استخدمي `esc()` دائماً كما في `core.js`
- **Rate Limit:** لا يوجد حد لمحاولات الدخول - يمكن brute force. الحل: فعّلي Supabase Auth rate limit (Dashboard → Auth → Rate Limits: 5 محاولات / دقيقة)
- **سعر الصرف:** `api/exchange-tgju.js` يجلب من `tgju.org` المحجوب في إيران - أضيفي fallback لسعر ثابت إذا فشل
- **PWA Banner:** `beforeinstallprompt.preventDefault()` بدون `prompt()` → لا يظهر زر التثبيت - احذفي السطر أو أضيفي زر تثبيت يدوي

---

## ✅ ما يعمل بشكل ممتاز الآن (بعد إصلاحات اليوم)

- تسجيل دخول `ameenmashhad` → يدخل super-admin.html
- البوابة الموحدة `portal.html` → تظهر 66 وحدة بعد إصلاح registry
- مركز التوحيد `all-pages-hub.html` → يعرض كل 65 صفحة
- API proxy → 200 OK بعد إصلاح `?path=` bug
- قاعدة البيانات → 31 حساب متكامل، 54.8% دخلوا

---

## قائمة فعالة — 5 خطوات قبل الإنتاج (20 دقيقة)

1. شغلي SQL رقم 1 و 2 فوق (RLS + Trigger) - 3 دقائق
2. احذفي الحسابات التجريبية `تحويل%` - 2 دقيقة
3. أصلحي Vercel Framework → Other + Redeploy - 2 دقيقة
4. احذفي التوكن من github.com/settings/tokens - 1 دقيقة
5. اشتري دومين .ir + اربطيه بـ ArvanCloud (لتفادي الحجب) - 10 دقائق

بعدها موقعك جاهز لـ 600 طالب بسلاسة.

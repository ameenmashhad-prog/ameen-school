# دفعة التصحيح الأمنية السريعة 01

تم تنفيذ أول دفعة من التصحيحات الحرجة والمتوسطة بسرعة وبدون تغيير جذري في بنية المشروع.

## 1) تأمين API Proxy

تم تحديث:

- `api/proxy.js`
- `api/exchange-tgju.js`
- `vercel.json`

التحسينات:

- إلغاء CORS المفتوح `*`.
- السماح فقط بنفس Origin أو Origins مضافة عبر متغير البيئة `ALLOWED_ORIGINS`.
- Whitelist لمسارات Supabase فقط:
  - `/rest/v1/`
  - `/auth/v1/`
  - `/storage/v1/`
- رفض Realtime عبر proxy.
- Timeout للطلبات.
- حد لحجم الطلب.
- تمرير headers الضرورية فقط.
- إضافة Security Headers في Vercel.

## 2) تقوية خصوصية الإرشاد النفسي

تم تحديث:

- `assets/platform-modules.js`
- `assets/unified-portal.js`
- `assets/ux-enhancements.js`
- `sql/archive/100_security_quick_hardening.sql`

التحسينات:

- تفاصيل الإرشاد النفسي أصبحت للمرشد/النفسي/المسؤول الأعلى فقط أو تفويض صريح.
- الإدارة والأكاديميون يحصلون على تقرير مجمع مجهول فقط.
- إضافة RPC:

```sql
select public.get_counseling_admin_aggregate_report();
```

- إضافة فحص:

```sql
select public.security_quick_hardening_health_check();
```

## 3) تحسين كلمات المرور المؤقتة للتسجيلات

تم تحديث:

- `assets/registration.js`
- `family-registration.html`
- `teacher-registration.html`
- `sql/archive/101_registration_password_policy.sql`

التحسينات:

- لم تعد كلمة المرور مبنية من تاريخ الميلاد.
- أصبحت كلمة المرور المؤقتة عشوائية.
- لم تعد تظهر في ملخص الطباعة للمستخدم.
- إضافة قيود مستقبلية تمنع كلمات المرور الرقمية الضعيفة.

فحص SQL:

```sql
select public.registration_password_policy_health_check();
```

## 4) حماية روابط التقويم

تم تحديث:

- `assets/smart-calendar.js`

التحسين:

- أي `action_url` قادم من قاعدة البيانات يتم فحصه كمسار داخلي فقط.
- يتم رفض `javascript:` أو الروابط الخارجية.

## ملفات SQL المطلوب تشغيلها

بعد رفع الحزمة، شغل بالترتيب:

```txt
sql/archive/100_security_quick_hardening.sql
sql/archive/101_registration_password_policy.sql
```

## فحوصات محلية نجحت

```txt
node --check api/proxy.js
node --check api/exchange-tgju.js
node --check assets/registration.js
node --check assets/counselor.js
node --check assets/smart-calendar.js
node --check assets/unified-portal.js
node --check assets/ux-enhancements.js
node --check assets/platform-modules.js
node tests/platform-modules.test.js
node tests/i18n.test.js
node tests/smart-calendar.test.js
```


## 5) تنظيف كلمات المرور الضعيفة القديمة

بعد ظهور `weak_existing_preview` أكبر من صفر، أضيف الملف:

```txt
sql/archive/102_registration_weak_password_cleanup.sql
```

وظيفته:

- تدوير كلمات المرور الرقمية الضعيفة القديمة إلى كلمات عشوائية قوية.
- إضافة حالة `password_policy_status` للتتبع.
- تفعيل/Validate القيود بعد التنظيف.

فحصه:

```sql
select public.registration_weak_password_cleanup_health_check();
```

المتوقع أن تكون:

```json
"weak_remaining": {"families":0,"students":0,"teachers":0}
```

ملاحظة مهمة: إذا كانت حسابات Supabase Auth قد أُنشئت سابقاً بكلمات المرور الضعيفة القديمة، يجب فرض إعادة تعيين كلمة المرور لهؤلاء المستخدمين من لوحة Auth أو Workflow إداري.

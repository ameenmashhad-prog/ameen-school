# إصلاح أمني حرج 170 — التسجيلات وForms v3

## لماذا هذا الإصلاح عاجل؟

أثبت الفحص الحي بتاريخ 2026-07-13 وجود المشكلات التالية:

1. كان المسار العام:
   - `/api/forms/rpc/list-submissions`
   يعيد قائمة طلبات التسجيل دون جلسة دخول.
2. مسارات مراجعة Forms v3 تستعمل `SUPABASE_SERVICE_ROLE_KEY` في الخادم، لكنها لم تتحقق من هوية المستخدم قبل تنفيذ الطلب.
3. دوال SQL حساسة من نوع `SECURITY DEFINER` كانت ممنوحة إلى `anon`، ومنها:
   - `forms_list_submissions_v3`
   - `forms_get_submission_v3`
   - `forms_update_submission_status_v3`
   - `activate_registered_user_rpc`
   - النسختان المحملتان من `activate_registered_user`
4. تفعيل الحساب كان يستخدم تاريخ الميلاد أو كلمة افتراضية ضعيفة ثم يعيد ضبط حساب موجود على الكلمة نفسها.
5. ملف SQL تاريخي احتوى حساب اختبار وكلمة مرور ثابتة معروفة.
6. حاوية `registration-photos` تحولت في ترحيل تاريخي إلى حاوية عامة مع سياسات قراءة/تعديل/حذف مفتوحة.
7. صفحة Forms v3 المنشورة كانت تتعطل في المتصفح بسبب استخدام `financeCatalogMap` قبل تهيئته.

## الترتيب الإلزامي للتطبيق

> طبّق SQL أولًا، ثم انشر الكود. نشر الكود قبل SQL يجعل محدد السرعة غير موجود وقد يعيد HTTP 503 للنماذج العامة.

### 1. خذ نسخة احتياطية

من Supabase خذ Backup/Snapshot قبل تنفيذ الترحيل.

### 2. شغّل SQL 170

في Supabase SQL Editor شغّل كامل الملف:

```text
sql/archive/170_critical_registration_and_forms_security_lockdown.sql
```

ثم افحص:

```sql
select public.forms_security_lockdown_health_check_v170();
```

المتوقع:

```json
{
  "ok": true,
  "anon_can_activate": false,
  "authenticated_can_activate": true,
  "anon_can_list_submissions": false,
  "registration_photos_private": true,
  "password_scrub_trigger": true,
  "rate_limit_rpc_exists": true
}
```

### 3. أضف متغير Vercel

داخل مشروع `next-forms-v3` في Vercel أضف:

```text
FORMS_RATE_LIMIT_SECRET=<قيمة عشوائية بطول 32 محرفًا على الأقل>
```

ويمكن إبقاء:

```text
FORMS_ADMIN_ROLES=admin,academic,academic_admin
```

تأكد من وجود المتغيرات الحالية وعدم كشفها للواجهة:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
FORMS_UPLOAD_BUCKET
```

`SUPABASE_SERVICE_ROLE_KEY` يجب ألا يبدأ بـ `NEXT_PUBLIC_`.

### 4. انشر الكود

انشر التغييرات على المشروعين:

- المشروع الرئيسي الذي جذره المستودع.
- مشروع `next-forms-v3` الذي Root Directory فيه هو `next-forms-v3`.

### 5. اختبارات ما بعد النشر

#### اختبار منع الوصول العام

من نافذة خاصة، يجب أن يعيد هذا المسار HTTP 401:

```text
POST https://next-forms-v3.vercel.app/api/forms/rpc/list-submissions
```

ويجب ألا يعيد أسماء أو معرفات طلبات.

#### اختبار صفحة الإدارة

1. افتح:
   - `https://ameen-school-h6cj.vercel.app/registrations-admin.html`
2. بدون جلسة: يجب التحويل إلى صفحة الدخول.
3. بحساب طالب/معلم: يجب رفض الوصول ولا يجب تحميل البيانات.
4. بحساب مدير/مسؤول علمي: يجب تحميل الطلبات.
5. عند تفعيل حساب:
   - تظهر بيانات الدخول المؤقتة في نافذة لمرة واحدة.
   - لا تظهر كلمة المرور في نسخة الطباعة.
   - لا تكون كلمة المرور تاريخ الميلاد.

#### اختبار Forms v3

افتح:

```text
https://next-forms-v3.vercel.app/ar/forms/family-registration-v3
```

يجب ألا تظهر رسالة `Application error`.

## ما تغير في الكود؟

- إضافة تحقق JWT ودور المستخدم لكل API إداري.
- حصر RPCات Forms v3 على `service_role` في SQL.
- إضافة محدد سرعة مخزن في قاعدة البيانات لمسارات الإرسال والرفع العامة.
- فرض نفس Origin وتحديد أحجام الطلبات.
- تقييد أنواع الملفات والتحقق من ترويسة الملف الفعلية.
- إيقاف حفظ مسودات الزائر داخل جداول الاستوديو؛ المسودة العامة تبقى محلية في المتصفح.
- حذف عرض/طباعة كلمات المرور من شاشة مراجعة التسجيلات.
- إصدار كلمة مرور عشوائية قوية عند التفعيل وعرضها للمشرف مرة واحدة.
- مسح حقول كلمات المرور من JSON التسجيلات القديمة والجديدة.
- إزالة كتلة حساب الاختبار ذات كلمة المرور الثابتة من ملفات SQL الحالية.

## ملاحظة مهمة عن الحساب التاريخي

يقوم SQL 170 بإبطال كلمة المرور المعروفة للحساب التاريخي `slyman@ameen.iq` إن كان موجودًا. أعد إصدار بيانات دخوله من واجهة التسجيلات أو من مسار إداري آمن، ولا تستخدم الكلمة القديمة مرة أخرى.

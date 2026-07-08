# تقرير QA حي كامل لمسار التسجيلات (End-to-End)

تاريخ التنفيذ: 2026-07-09
الوسم المستخدم: `QA-REG-20260709-LIVE3`

## الهدف
تنفيذ فحص حي كامل يشمل:
1. إنشاء طلب أسرة يدوي
2. إنشاء طلب معلم يدوي
3. إنشاء طلبات استيراد مكافئة لمسار import
4. مراجعة الطلبات وتغيير بعض الحالات
5. تفعيل الحسابات عبر RPC الحي
6. اختبار تسجيل الدخول للحسابات الناتجة
7. تنظيف كامل لكل بيانات QA

> تم التنفيذ بعد تشغيل ملفات الإصلاح:
> - `141_registration_qa_cleanup_rpc.sql`
> - `142_fix_activate_registered_user_rpc_ambiguity.sql`
> - `143_fix_registration_family_activation_students_name.sql`

---

## المراجع الحية المستخدمة
### الصفوف
- `الأول الابتدائي` → `d093738f-1f0c-440a-96d0-ab5234513580`
- `الثاني الابتدائي` → `84093754-0970-49b6-b764-9ee082a75445`
- `الثالث الابتدائي` → `94a38f02-1147-4519-9611-f5e7e43c5625`

### المادة المستخدمة في طلب المعلم
- `الأحياء`
- `id = e7ab0ff1-d0be-4c45-87df-3831e829e465`

---

## فحص RPCات قبل البدء
### تنظيف QA
- `registration_qa_cleanup_preview` → يعمل
- `registration_qa_cleanup_execute` → يعمل

### تفعيل الحسابات
- `activate_registered_user_rpc` → يعمل
- probe result:
  - `{"ok": false, "error": "نوع التسجيل غير مدعوم: invalid_probe"}`

وهذا يؤكد أن wrapper الجديد صار فعالاً ومقروءاً من PostgREST.

---

## تنظيف استباقي قبل الاختبار
تم تنفيذ cleanup استباقي لنفس الوسم قبل البدء.

### النتيجة قبل الإنشاء
- families = 0
- students = 0
- teachers = 0
- activated accounts = 0

---

## البيانات التي تم إنشاؤها حيًا
### 1) طلب أسرة يدوي
- أسرة واحدة
- طالبان

### 2) طلب معلم يدوي
- معلم واحد
- مادة واحدة مرتبطة

### 3) طلبات استيراد مكافئة
- أسرتان
- 3 طلاب

### الإجمالي قبل التفعيل
- الأسر: 3
- الطلاب: 5
- المعلمون: 1
- صفوف view المراجعة: 5

كل الحالات عند الإنشاء كانت:
- `pending`

---

## محاكاة إجراءات المراجعة
تم تغيير حالة:
- إحدى أسر الاستيراد إلى `reviewed`
- طلب المعلم إلى `reviewed`

الهدف:
- التحقق من أن مسار update للحالة يعمل قبل التفعيل

---

## التفعيل الحي
### تم تفعيل:
#### الأسرة اليدوية
- النتيجة: `ok = true`
- parent email: `qareg20260709live3pm@ameen.iq`
- activated_students = 2

#### المعلم اليدوي
- النتيجة: `ok = true`
- email: `qareg20260709live3t@ameen.iq`

#### أسرة الاستيراد الأولى
- النتيجة: `ok = true`
- parent email: `qareg20260709live3ip1@ameen.iq`
- activated_students = 2

---

## الحالة بعد التفعيل
### الأسر
- `approved`
- `approved`
- `reviewed`

### الطلاب
- 4 طلاب = `approved`
- 1 طالب = `pending`

> وهذا متوقع لأن أسرة الاستيراد الثانية لم يتم تفعيلها، فبقي طالبها pending.

### المعلم
- `approved`

---

## السجلات الناتجة في الجداول الحية
### public.users
تم إنشاء/تحديث 7 حسابات:
- 2 أولياء أمور
- 4 طلاب
- 1 معلم

### public.students
تم إنشاء 4 صفوف طلاب حية

### معاينة cleanup قبل الحذف النهائي
كانت تعرض:
- parent_users = 2
- student_users = 4
- teacher_users = 1
- public_students = 4
- auth_users_total = 7
- registration_families = 3
- registration_students = 5
- registration_teachers = 1

وهذا يؤكد أن QA المراد تنظيفه كان مرصودًا بالكامل.

---

## اختبار تسجيل الدخول للحسابات الناتجة
تم التحقق من تسجيل الدخول بنجاح للحسابات التالية:

### ولي أمر الأسرة اليدوية
- `qareg20260709live3pm@ameen.iq`
- كلمة المرور: `21031985`
- النتيجة: نجاح

### الطالب اليدوي الأول
- `qareg20260709live3s1@ameen.iq`
- كلمة المرور: `11022017`
- النتيجة: نجاح

### المعلم اليدوي
- `qareg20260709live3t@ameen.iq`
- كلمة المرور: `15011990`
- النتيجة: نجاح

### ولي أمر أسرة الاستيراد الأولى
- `qareg20260709live3ip1@ameen.iq`
- كلمة المرور: `05051984`
- النتيجة: نجاح

---

## التنظيف النهائي
تم تنفيذ:
- `registration_qa_cleanup_execute(TAG, true)`

### النتيجة
تم حذف:
- `registration_families = 3`
- `registration_students = 5`
- `registration_teachers = 1`
- `public_students = 4`
- `public_users = 7`
- `auth_users = 7`
- `storage_objects = 0`

### الفحص بعد التنظيف
عاد preview إلى:
- families = 0
- students = 0
- teachers = 0
- parent_users = 0
- student_users = 0
- teacher_users = 0
- public_students = 0
- auth_users_total = 0

وهذا يعني أن cleanup نجح بالكامل.

---

## الخلاصة النهائية
QA الحي الكامل نجح في المحاور التالية:
- إنشاء طلبات الأسرة والطلاب
- إنشاء طلب المعلم
- إنشاء بيانات استيراد متوافقة مع المسار الحديث
- مراجعة الحالات وتحديثها
- تفعيل الأسرة والمعلم حيًا
- إنشاء حسابات حقيقية قابلة لتسجيل الدخول
- إنشاء صفوف طلاب حيّة في `public.students`
- cleanup كامل وآمن بعد الاختبار

---

## المشاكل المكتشفة خلال الرحلة وتم إصلاحها
### 1) غموض RPC التفعيل
- عولج عبر: `142_fix_activate_registered_user_rpc_ambiguity.sql`

### 2) فشل تفعيل الأسرة بسبب `public.students.name`
- عولج عبر: `143_fix_registration_family_activation_students_name.sql`

---

## الحكم النهائي
**مسار التسجيلات الآن ناجح حيًا end-to-end** بعد تطبيق إصلاحي 142 و143، وتم التحقق منه مع cleanup كامل دون بقايا بيانات QA.

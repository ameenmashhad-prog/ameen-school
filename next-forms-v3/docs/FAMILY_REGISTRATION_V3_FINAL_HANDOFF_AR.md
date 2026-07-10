# التسليم النهائي — Family Registration v3

## 1) الهدف من هذا المسار
هذا المسار بُني ليكون البديل الصحيح والحديث لـ:
- `family-registration.html`

لكن بدون كسر منطق العمل القديم.

### ما الذي يحله؟
- إبقاء منطق **تسجيل الأسرة** بدل تحويله إلى فورم طالب منفرد
- إدخال بيانات ولي الأمر **مرة واحدة فقط**
- إدخال بيانات الأم **مرة واحدة فقط**
- إضافة عدة طلاب داخل نفس الطلب
- منع تكرار:
  - اسم الأب
  - اسم العائلة
  - بعض البيانات المشتركة
- دعم طباعة:
  - ورقة عائلية رئيسية
  - ملحق مستقل لكل طالب

---

## 2) الحالة الحالية
### منجز
- الواجهة مبنية داخل `next-forms-v3`
- المسار يعمل في البناء والتشغيل المحلي
- submit RPC الخاصة به مفعلة على القاعدة
- تم التحقق الحي من الإدراج والقراءة والأرشفة
- تم تحسين UX
- تم تجهيز Preview
- تم تجهيز UAT
- تم تجهيز Soft Launch
- تم تجهيز Hard Switch

### النتيجة العملية
`family-registration-v3` أصبح الآن **جاهزًا كمرشح فعلي** ليحل محل `family-registration.html` بعد النشر والاعتماد.

---

## 3) المسارات والملفات الأساسية
## الواجهة الجديدة
- `next-forms-v3/app/[locale]/forms/family-registration-v3/page.jsx`
- `next-forms-v3/app/[locale]/forms/family-registration-v3/success/page.jsx`
- `next-forms-v3/components/family-registration-v3-shell.jsx`

## RPC
- `next-forms-v3/app/api/forms/rpc/submit-family-registration-v3/route.js`
- `next-forms-v3/lib/rpc/forms-rpc.js`

## SQL
- `sql/archive/151_forms_v3_family_registration_submit.sql`

## الترجمة
- `next-forms-v3/locales/ar/forms.json`
- `next-forms-v3/locales/fa/forms.json`
- `next-forms-v3/locales/en/forms.json`

## التوثيق
- `next-forms-v3/docs/FAMILY_REGISTRATION_V3_IMPLEMENTATION_AR.md`
- `next-forms-v3/docs/FAMILY_REGISTRATION_V3_LIVE_VERIFICATION_AR.md`
- `next-forms-v3/docs/FAMILY_REGISTRATION_V3_UAT_CHECKLIST_AR.md`
- `next-forms-v3/docs/FAMILY_REGISTRATION_V3_UX_POLISH_AR.md`
- `next-forms-v3/docs/FAMILY_REGISTRATION_V3_NORMALIZED_HANDOFF_AR.md`
- `next-forms-v3/docs/FAMILY_REGISTRATION_V3_FIELD_MAPPING_AR.md`
- `next-forms-v3/docs/FAMILY_REGISTRATION_V3_SCHEMA.json`

## الربط والانتقال
- `docs/FAMILY_REGISTRATION_TO_FORMS_V3_MIGRATION_PLAN_AR.md`
- `docs/FAMILY_REGISTRATION_V3_SOFT_LAUNCH_READY_AR.md`
- `docs/FAMILY_REGISTRATION_V3_HARD_SWITCH_READY_AR.md`
- `assets/family-registration-soft-launch.js`
- `family-registration-v3-bridge.html`
- `family-registration-v3-hard-switch.template.html`
- `scripts/apply-family-registration-hard-switch.sh`

## المعاينات
- `SHOW_ME_FAMILY_REGISTRATION_V3.html`
- `next-forms-v3/previews/family-registration-v3-preview.html`
- `next-forms-v3/previews/family-registration-v3-live-preview.html`
- `next-forms-v3/previews/family-registration-v3-view-hub.html`

---

## 4) منطق البيانات المعتمد
## ولي الأمر
بدل حقل جامد مثل الاسم الثلاثي فقط، تم اعتماد تفكيك واضح:
- `guardian_given_name`
- `guardian_father_name`
- `family_name`

## الأم
- `mother_given_name`
- `mother_father_name`
- `mother_family_name`

## الطالب
كل طالب داخل نفس الطلب يملك بطاقة مستقلة فيها:
- `student_given_name`
- `student_father_name`
- `student_family_name`
- `student_full_name`
- بياناته الدراسية والشخصية

## التوريث الذكي
بشكل افتراضي:
- `student_father_name` يرث من `guardian_given_name`
- `student_family_name` يرث من `family_name`
- `student_full_name` يُحسب تلقائيًا

### الفائدة
هذا يحقق طلب العمل الحقيقي:
- لا نكرر بيانات الأب والعائلة مع كل ابن
- نحتفظ بإمكانية التعديل اليدوي عند وجود حالة خاصة

---

## 5) ما الذي يدعمه النموذج الآن؟
- بيانات ولي الأمر مرة واحدة
- بيانات الأم مرة واحدة
- عدة طلاب في نفس الطلب
- اسم كامل محسوب تلقائيًا لكل طالب
- اسم مستخدم مقترح لولي الأمر والطلاب
- كلمة مرور أولية مبنية من تاريخ الميلاد
- جدول دفعات عائلي
- مرفق عائلي مشترك عبر upload ticket
- حفظ draft
- submit عبر RPC
- ظهور الطلب في لوحة الطلبات المرسلة
- طباعة عائلية + ملحقات لكل طالب

---

## 6) التحقق الذي تم فعليًا
## تحقق محلي
- `npm install`
- `npm run build`
- تشغيل محلي ناجح
- الصفحة تستجيب وتظهر عناصر UX الجديدة

## تحقق حي على القاعدة
تم التحقق من:
- `forms_submit_family_registration_v3`
- `forms_list_submissions_v3`
- `forms_get_submission_v3`
- `forms_update_submission_status_v3`

### ماذا تم اختباره؟
- إنشاء طلب عائلي تجريبي
- إدخال ولي أمر + أم + طالبين + دفعات
- قراءة الطلب من submissions
- جلب التفاصيل
- أرشفة طلب التحقق بعد الاختبار

### النتيجة
- `guardian_name` ظهر صحيحًا
- `applicant_name` ظهر من أول طالب بشكل صحيح
- البنية المخزنة احتفظت بـ:
  - `guardian`
  - `mother`
  - `students[]`
  - `payment_entries[]`
  - `documents`
  - `approval`

---

## 7) تحسينات UX المنفذة
- Banner توضيحي أعلى الصفحة
- شريط انتقال سريع بين الأقسام
- إجراءات سريعة لتقليل التكرار
- مؤشرات جاهزية بطاقات الطلاب
- زر نسخ بطاقة الطالب
- مخرجات سريعة داخل كل بطاقة:
  - الاسم الكامل
  - اسم المستخدم
  - كلمة المرور

### النتيجة
أصبح النموذج أوضح وأسرع في تعبئة عدة أبناء ضمن نفس الأسرة.

---

## 8) الانتقال من القديم إلى الجديد
## Soft Launch
جاهز الآن عبر:
- `family-registration.html`
- `assets/family-registration-soft-launch.js`
- `assets/config.js`

### كيف يُفعّل؟
عند وضع:
- `familyRegistrationV3Url`

سيظهر Banner داخل الصفحة القديمة مع زر فتح النسخة الجديدة.

### ويمكن لاحقًا تفعيل redirect تلقائي عبر:
- `familyRegistrationV3AutoRedirect: true`

## Hard Switch
جاهز عبر:
- `family-registration-v3-hard-switch.template.html`
- `scripts/apply-family-registration-hard-switch.sh`

### ما الذي يفعله؟
- يأخذ backup من الصفحة القديمة
- يحقن رابط النشر الحقيقي
- يستبدل `family-registration.html` بصفحة تحويل نهائية

---

## 9) ما الذي ينقص قبل الإطلاق الفعلي العام؟
### 1) النشر
حتى الآن المشكلة الأساسية ليست في الكود، بل في **رابط النشر العام**.

### 2) تفعيل Soft Launch على الرابط القديم
بوضع الرابط النهائي في:
- `assets/config.js`

### 3) تنفيذ UAT نهائي بشري
باستخدام:
- `next-forms-v3/docs/FAMILY_REGISTRATION_V3_UAT_CHECKLIST_AR.md`

### 4) اتخاذ قرار التشغيل
إما:
- Soft Launch فقط
- أو Hard Switch كامل

---

## 10) قرار تشغيلي مقترح
## المرحلة الأولى
- انشر `next-forms-v3`
- تأكد من عمل:
  - `/ar/forms/family-registration-v3`
- فعّل Soft Launch
- راقب الاستخدام الحقيقي

## المرحلة الثانية
بعد التأكد من:
- submit
- print
- review
- وعدم وجود bugs blocking

نفذ Hard Switch عبر السكربت الجاهز.

---

## 11) Rollback
إذا احتجت الرجوع:
- استخدم backup من:
  - `migration_backups/`
- أو استرجع `family-registration.html` من Git

هذا يجعل التحويل آمنًا وقابلًا للعكس بسرعة.

---

## 12) الخلاصة النهائية
`family-registration-v3` لم يعد مجرد تصور أو mockup.

هو الآن:
- **مبني**
- **موثق**
- **متحقق منه محليًا**
- **متحقق منه حيًا على القاعدة**
- **محسن UX**
- **جاهز للانتقال المرحلي من القديم إلى الجديد**

والخطوة التشغيلية التالية الوحيدة المتبقية فعليًا هي:
## **الحصول على رابط نشر نهائي ثم تفعيل Soft Launch / Hard Switch**

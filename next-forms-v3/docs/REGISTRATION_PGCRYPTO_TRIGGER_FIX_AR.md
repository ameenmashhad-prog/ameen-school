# إصلاح خطأ `gen_salt` في submit التسجيل العائلي

## المشكلة
بعد تشغيل 159، ظهر أثناء submit:
```text
function gen_salt(unknown) does not exist
```

## السبب
هذا الخطأ لا يأتي من `forms_submit_family_registration_v3` نفسها، بل من trigger قديم على جداول التسجيل:
- `registration_families`
- `registration_students`
- `registration_teachers`

الـ trigger يحاول تشفير `initial_password` باستخدام:
- `crypt`
- `gen_salt`

لكن بدون search_path يضمن رؤية `pgcrypto` في البيئة الحالية.

## الحل
شغّل هذا الملف:
- `sql/archive/160_fix_registration_password_trigger_pgcrypto.sql`

## ماذا يفعل؟
1. يتأكد من وجود schema:
   - `extensions`
2. يتأكد من وجود extension:
   - `pgcrypto`
3. يعيد تعريف trigger function:
   - `public._hash_initial_password_trg()`
4. يعيد تركيب الـ triggers على جداول التسجيل الثلاثة

## بعد تشغيله
يرجع submit في `family-registration-v3` للعمل، ثم يمكننا متابعة التحقق من:
- snapshot داخل جداول التسجيل
- التفعيل
- إنشاء `student_fees`
- إنشاء `finance_payment_plans`
- إنشاء `student_installments`

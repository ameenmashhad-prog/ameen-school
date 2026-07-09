# خطة ربط `family-registration.html` بالفورم الجديد `next-forms-v3`

## الهدف
تحويل المستخدم من الصفحة القديمة:
- `family-registration.html`

إلى الفورم الجديد بعد النشر:
- `/<locale>/forms/student-registration-packet`

مع أقل مخاطرة، وإمكانية rollback سريعة إذا احتجنا.

---

## الوضع الحالي
### الصفحة القديمة
- المسار الحالي: `family-registration.html`
- تعمل داخل المشروع القديم `ameen-school`
- ما زالت تعرض UX قديم وlogic قديم

### الصفحة الجديدة
- موجودة داخل: `next-forms-v3`
- المسار المستهدف المقترح:
  - `/ar/forms/student-registration-packet`
- backend وRPC وSQL أصبحت مفعلة حتى `150`

### المانع الحالي فقط
- الفورم الجديد **غير منشور public بعد** على رابط حي نهائي
- حاولنا نشره لكن توقّفنا بسبب حد Vercel اليومي

---

# الاستراتيجية الموصى بها
أفضل ربط عملي وأقل مخاطرة يكون على **مرحلتين**:

## المرحلة 1 — Soft Launch
نبقي الصفحة القديمة موجودة، لكن نضيف لها:
- تنبيه واضح أن النسخة الجديدة جاهزة
- زر مباشر: `افتح النسخة الجديدة`
- اختياريًا: redirect تلقائي بعد عدة ثوانٍ

### لماذا؟
- يقلل الصدمة على المستخدمين
- يسمح باختبار حي محدود
- يسهّل rollback

## المرحلة 2 — Hard Switch
بعد التأكد من نجاح UAT والنشر:
- نستبدل `family-registration.html` بصفحة bridge بسيطة
- الصفحة تعمل redirect مباشر إلى الفورم الجديد
- مع رابط احتياطي يدوي إذا لم يعمل redirect التلقائي

---

# المسار النهائي المقترح
## الربط الأساسي
```text
family-registration.html
→ <NEXT_FORMS_V3_URL>/ar/forms/student-registration-packet
```

## مثال بعد النشر
إذا صار رابط التطبيق الجديد مثلًا:
```text
https://next-forms-v3.vercel.app
```

فالتحويل يكون إلى:
```text
https://next-forms-v3.vercel.app/ar/forms/student-registration-packet
```

---

# خطوات التنفيذ العملية

## الخطوة 1 — نشر `next-forms-v3`
نحتاج أولًا رابط حي للتطبيق الجديد.

### متغيرات البيئة المطلوبة في مشروع Vercel الجديد
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `FORMS_UPLOAD_BUCKET`

### روابط فحص بعد النشر
- `/ar`
- `/ar/forms/student-registration`
- `/ar/forms/student-registration-packet`
- `/ar/forms/submissions`

---

## الخطوة 2 — اعتماد رابط الإنتاج الجديد
بعد نجاح النشر، ثبّت قيمة واحدة مثل:
```text
NEXT_FORMS_V3_URL=https://next-forms-v3.vercel.app
```

أو أي domain تختارونه لاحقًا.

---

## الخطوة 3 — ربط الصفحة القديمة
### خيار A — Banner + زر (الأكثر أمانًا أولًا)
في `family-registration.html` نضيف في أعلى الصفحة:
- تنبيه: "تم إطلاق النسخة الجديدة من فورم التسجيل"
- زر: "فتح الفورم الجديد"
- زر ثانوي: "البقاء في النسخة القديمة"

### خيار B — Redirect Bridge (بعد التأكد)
نستبدل محتوى `family-registration.html` بصفحة تحويل بسيطة تنفذ:
- redirect تلقائي بعد 1–2 ثانية
- رابط يدوي احتياطي
- رسالة واضحة للمستخدم

---

# ما الذي سأربطه تحديدًا؟
## التوصية الحالية
أربط:
- `family-registration.html`

إلى:
- `student-registration-packet`

### لماذا هذا المسار تحديدًا؟
لأن المستخدم طلب فورم:
- يجمع البيانات والجانب المالي
- يمكن تعديله
- ثم طباعته لحفظه في ملفات الطلاب

وهذا هو بالضبط ما يحققه:
- `student-registration-packet`

---

# خطة Rollback
إذا ظهرت مشكلة بعد التحويل:

## rollback سريع
- نرجع `family-registration.html` إلى النسخة القديمة السابقة
- أو نلغي redirect ونُبقي فقط زر فتح النسخة الجديدة

## زمن الرجوع
- دقائق قليلة فقط إذا حفظنا الملف القديم أو اعتمدنا commit منفصل

---

# فحص القبول بعد الربط
بعد تفعيل الربط، تأكد من التالي:
- [ ] فتح `family-registration.html` ينقل إلى الفورم الجديد
- [ ] الفورم الجديد يفتح بالعربية مباشرة
- [ ] الحفظ يعمل
- [ ] الإرسال يعمل
- [ ] الطباعة تعمل
- [ ] صفحة النجاح تعمل
- [ ] الطلب يظهر في لوحة الطلبات
- [ ] اسم الطالب وولي الأمر يظهران بشكل صحيح

---

# القرار التنفيذي الموصى به
## الآن
1. ننتظر أول نافذة نشر متاحة أو نستخدم مشروع Vercel آخر
2. ننشر `next-forms-v3`
3. نختبر الرابط الحي
4. نفعّل **Soft Launch** أولًا

## بعد النجاح
5. نفعّل **Hard Switch** على `family-registration.html`

---

# ملفات جاهزة مرتبطة بهذه الخطة
- `docs/FAMILY_REGISTRATION_TO_FORMS_V3_MIGRATION_PLAN_AR.md`
- `family-registration-v3-bridge.html`

الملف الثاني هو صفحة bridge جاهزة تقريبًا، يكفي وضع رابط النشر الحقيقي داخلها ثم استخدامها بدل الصفحة القديمة عندما تقررون التحويل النهائي.

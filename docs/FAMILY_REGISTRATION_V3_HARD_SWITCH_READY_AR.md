# Hard Switch جاهز لـ `family-registration.html`

## الهدف
تجهيز استبدال نهائي للصفحة القديمة:
- `family-registration.html`

بحيث تصبح بوابة تحويل مباشرة إلى:
- `/ar/forms/family-registration-v3`

بعد توفر رابط النشر النهائي.

---

## الملفات الجاهزة
### 1) قالب التحويل النهائي
- `family-registration-v3-hard-switch.template.html`

هذا الملف هو نسخة redirect جاهزة لمرحلة Hard Switch، لكنه يحتوي placeholder:
- `__NEXT_FORMS_V3_URL__`

### 2) سكربت تطبيق التحويل
- `scripts/apply-family-registration-hard-switch.sh`

هذا السكربت يقوم بـ:
1. أخذ نسخة احتياطية من `family-registration.html`
2. حقن رابط النشر الحقيقي داخل القالب
3. استبدال `family-registration.html` تلقائيًا

---

## طريقة الاستخدام
بعد أن يصبح لديك رابط نشر فعلي للتطبيق الجديد، شغّل:

```bash
bash scripts/apply-family-registration-hard-switch.sh https://YOUR-NEXT-FORMS-V3-DOMAIN
```

### مثال
```bash
bash scripts/apply-family-registration-hard-switch.sh https://next-forms-v3.vercel.app
```

---

## ماذا يحدث بعد التشغيل؟
### 1) النسخة القديمة لا تضيع
يتم حفظها تلقائيًا داخل:
- `migration_backups/`

باسم مثل:
- `family-registration.20260710-123456.legacy.html`

### 2) الصفحة الحالية تُستبدل
يصبح `family-registration.html` نفسه عبارة عن:
- رسالة قصيرة
- redirect تلقائي
- زر فتح يدوي للنسخة الجديدة
- زر عودة مؤقتة إلى النسخة السابقة

---

## متى نستخدم Hard Switch؟
لا نفعله إلا بعد تحقق الشروط التالية:
- [ ] تم نشر `next-forms-v3` على رابط حي
- [ ] تم فحص `/ar/forms/family-registration-v3`
- [ ] تم تنفيذ UAT
- [ ] تم التأكد من submit / print / review
- [ ] تم اعتماد النسخة الجديدة رسميًا كبديل للقديمة

---

## Rollback
إذا احتجت الرجوع:
1. افتح مجلد:
   - `migration_backups/`
2. اختر آخر ملف backup
3. أعد تسميته إلى:
   - `family-registration.html`

أو ببساطة استرجعه من Git.

---

## التسلسل المقترح
### الآن
- Soft Launch مفعل وجاهز عند وضع الرابط في `assets/config.js`

### لاحقًا
- بعد نجاح الاستخدام التجريبي
- نفذ Hard Switch بهذا السكربت

---

## الفرق بين Soft Launch و Hard Switch
### Soft Launch
- Banner داخل الصفحة القديمة
- المستخدم يقرر الانتقال أو لا
- أقل مخاطرة

### Hard Switch
- الصفحة القديمة نفسها تصبح redirect
- الأنسب بعد اعتماد النسخة الجديدة نهائيًا

---

## الخلاصة
الآن صار عندك:
- **Soft Launch جاهز**
- **Hard Switch جاهز**
- **Rollback جاهز**

وما ينقص فقط هو:
- رابط النشر النهائي للتطبيق الجديد

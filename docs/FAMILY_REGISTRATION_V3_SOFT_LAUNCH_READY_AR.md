# Soft Launch جاهز لـ `family-registration.html`

## ما الذي تم تنفيذه
تم تجهيز الصفحة القديمة `family-registration.html` بحيث يمكنها عرض Banner انتقالية آمنة نحو النسخة الجديدة `family-registration-v3` بدون كسر الفورم القديم.

## الملفات المحدثة
- `family-registration.html`
- `assets/registration.css`
- `assets/config.js`
- `assets/family-registration-soft-launch.js`

## ماذا تفعل هذه التهيئة؟
### 1) تبقي الفورم القديم كما هو
- لا تغيّر منطق الإدخال القديم
- لا تعطل التسجيل الحالي
- لا تفرض redirect إذا لم يتم تحديد رابط النسخة الجديدة

### 2) تضيف Soft Launch Banner
إذا تم تعريف:
- `familyRegistrationV3Url`

داخل `window.AMIN_CONFIG`، فستظهر للمستخدم:
- رسالة أن النسخة الجديدة جاهزة
- زر: `افتح النسخة الجديدة`
- زر: `الاستمرار في النسخة الحالية`

### 3) تدعم Auto Redirect اختياري
إذا تم تفعيل:
- `familyRegistrationV3AutoRedirect: true`

فستقوم الصفحة بالتحويل التلقائي بعد عد تنازلي قصير.

## الإعداد المطلوب لاحقًا عند توفر رابط النشر
في `assets/config.js` غيّر:
```js
familyRegistrationV3Url: '',
familyRegistrationV3AutoRedirect: false
```

إلى شيء مثل:
```js
familyRegistrationV3Url: 'https://YOUR-NEXT-FORMS-V3-DOMAIN/ar/forms/family-registration-v3',
familyRegistrationV3AutoRedirect: false
```

## نمط الإطلاق المقترح
### المرحلة الأولى
```js
familyRegistrationV3AutoRedirect: false
```
- يظهر Banner فقط
- المستخدم يختار النسخة الجديدة يدويًا

### المرحلة الثانية
```js
familyRegistrationV3AutoRedirect: true
```
- يبدأ التحويل التلقائي
- مع بقاء زر الاستمرار في النسخة الحالية متاحًا للإلغاء

## ملاحظات
- هذا التنفيذ آمن لأنه لا يفعّل شيئًا ما لم يتم وضع الرابط فعليًا.
- يصلح كمرحلة Soft Launch قبل Hard Switch النهائي.

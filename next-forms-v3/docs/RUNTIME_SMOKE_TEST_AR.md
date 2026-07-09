# اختبار التشغيل السريع — next-forms-v3

## ما الذي تم اختباره
تم تنفيذ اختبار تشغيل محلي سريع على التطبيق الجديد `next-forms-v3` بعد بناء فورم التسجيل المطبوع.

## الخطوات المنفذة
```bash
cd next-forms-v3
npm install
NEXT_PUBLIC_SUPABASE_URL='https://example.supabase.co' \
SUPABASE_SERVICE_ROLE_KEY='test-service-role-key' \
FORMS_UPLOAD_BUCKET='forms-v3-uploads' \
npm run build
```

ثم تم تنفيذ Smoke Test على خادم محلي عبر `npm start` والتحقق من الصفحات التالية:
- `/ar`
- `/ar/forms/student-registration-packet`

## النتيجة
- **Build Pass**
- **Start Pass**
- **Smoke Test Pass**

## المشكلة التي ظهرت وتم إصلاحها
أثناء `next build` ظهرت مشكلة Syntax داخل الملف:
- `components/student-registration-shell.jsx`

السبب:
- وجود block نصّي زائد من أوامر shell تم حقنه سابقًا في نهاية الملف.

الإصلاح:
- إزالة الجزء الزائد وتنظيف نهاية الملف.

## مخرجات مهمة من البناء
تم توليد الصفحات الأساسية بنجاح، ومنها:
- `/${locale}/forms/builder`
- `/${locale}/forms/student-registration`
- `/${locale}/forms/student-registration-packet`
- `/${locale}/forms/leave-request`
- `/${locale}/forms/teacher-evaluation`
- `/${locale}/forms/financial-permission`
- `/${locale}/forms/submissions`

## ملاحظات
- تم الاختبار باستخدام متغيرات بيئة تجريبية فقط لغرض التحقق من البناء والتشغيل.
- هذا لا يعني أن الاتصال الفعلي بـ Supabase أو RPC live تم تفعيله بعد.
- SQL الخاصة بـ forms-v3 ما زالت تحتاج تطبيق فعلي على قاعدة البيانات.
- ظهرت ملاحظة من npm أن `next@15.0.0` لديه تنبيه أمني، لذا يُستحسن لاحقًا ترقيته إلى نسخة patched مناسبة بعد تثبيت البيئة الخلفية.

## التوصية التالية
الخطوة العملية التالية الأنسب:
1. تطبيق SQLs الخاصة بـ forms-v3 على قاعدة البيانات.
2. ضبط `.env` الفعلية.
3. إعادة اختبار submit / upload / review ضد backend الحقيقي.

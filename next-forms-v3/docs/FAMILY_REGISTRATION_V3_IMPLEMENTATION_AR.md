# Family Registration v3 — تنفيذ أولي عملي

## ما الذي تم بناؤه
- مسار جديد: `app/[locale]/forms/family-registration-v3/page.jsx`
- صفحة نجاح: `app/[locale]/forms/family-registration-v3/success/page.jsx`
- مكوّن رئيسي: `components/family-registration-v3-shell.jsx`
- Route RPC: `app/api/forms/rpc/submit-family-registration-v3/route.js`
- SQL submit مقترحة: `sql/archive/151_forms_v3_family_registration_submit.sql`

## الفكرة الأساسية
هذه النسخة لا تكرر بيانات الأب والعائلة عند إضافة أكثر من طالب.

## ما الذي يدعمه التنفيذ الحالي
- بيانات ولي الأمر مرة واحدة
- بيانات الأم مرة واحدة
- بطاقات متعددة للطلاب
- توريث اسم الأب واسم العائلة تلقائيًا
- اسم كامل محسوب لكل طالب
- اسم مستخدم مقترح لولي الأمر والطلاب
- كلمة مرور أولية من تاريخ الميلاد
- جدول دفعات عائلي
- مرفق عائلي واحد عبر upload ticket
- معاينة طباعة لورقة الأسرة + ملحق لكل طالب
- Draft عبر RPC
- Submit عبر RPC

## ملاحظات تنفيذية
- صور الطلاب في هذا الإصدار تحفظ وصفيًا داخل الطلب، بينما رفع المرفق الفعلي المربوط تم تفعيله للمرفق العائلي المشترك.
- هذا يحقق المطلوب الأساسي الخاص بتقليل التكرار وتنظيم البيانات العائلية قبل التوسع في multi-file uploads.

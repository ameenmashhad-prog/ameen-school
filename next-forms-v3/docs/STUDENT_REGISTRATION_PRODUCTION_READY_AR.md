# استمارة تسجيل الطالب — نسخة Production-ready أولية

## ما الذي تم بناؤه
تمت إضافة صفحة مستقلة داخل:
- `app/[locale]/forms/student-registration/page.jsx`

تعرض نسخة تشغيلية أولية من استمارة تسجيل الطالب، مبنية على القالب الجديد، وتدعم:
- العربية
- الفارسية
- الإنكليزية

## ما الذي تدعمه الصفحة الآن
- أقسام فعلية داخل النموذج
- حفظ محلي واستعادة تلقائية
- حفظ Draft عبر RPC
- إرسال Submit عبر RPC مستقل
- معاينة جانبية لبيانات ولي الأمر والطالب
- معاينة طباعة أقرب للإخراج النهائي
- عرض التواريخ حسب قاعدة اللغة النشطة
- حقول select وfile وsignature كمسار تشغيل أولي
- تحقق Validation أوضح للحقل الإلزامي والهاتف والبريد والملفات والتوقيع
- رقم مرجعي Tracking ID بعد الإرسال
- بطاقة نجاح قابلة للطباعة بعد Submit
- عدّاد جاهزية + عدد التنبيهات داخل الصفحة
- تهيئة أولية لمسار **signed upload** عبر RPC تذكرة رفع
- صفحة نجاح مستقلة بعد الإرسال مع رقم التتبع

## RPC المقترحة لهذه الصفحة
- `forms_submit_student_registration_v3`
- `forms_request_upload_ticket_v3`

## المسارات الجديدة المرتبطة بها
- `app/[locale]/forms/student-registration/page.jsx`
- `app/[locale]/forms/student-registration/success/page.jsx`
- `app/api/forms/rpc/submit-student-registration/route.js`
- `app/api/forms/rpc/request-upload-ticket/route.js`
- `app/api/forms/upload-file/route.js`

## ملاحظة مهمة
هذه الصفحة Production-ready من ناحية الواجهة وتدفق العمل، لكنها تحتاج لاحقًا:
1. ربط RPC الخلفية الفعلية في Supabase
2. تنفيذ upload binary الفعلي بعد إصدار تذكرة الرفع
3. اعتماد سياسة التوقيع الإلكتروني النهائية

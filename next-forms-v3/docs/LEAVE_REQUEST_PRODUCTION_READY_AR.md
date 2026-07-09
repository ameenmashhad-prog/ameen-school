# استمارة طلب الإجازة — نسخة Production-ready أولية

## ما الذي تم بناؤه
تمت إضافة صفحة مستقلة داخل:
- `app/[locale]/forms/leave-request/page.jsx`

تعرض نسخة تشغيلية أولية من استمارة طلب الإجازة، وتدعم:
- العربية
- الفارسية
- الإنكليزية

## ما الذي تدعمه الصفحة الآن
- أقسام فعلية داخل النموذج
- حفظ محلي + Draft عبر RPC
- تحقق Validation لتسلسل التواريخ والبريد والمرفق
- رفع مرفق داعم عبر upload ticket + upload transport
- Tracking ID بعد الإرسال
- صفحة نجاح مستقلة بعد submit
- معاينة للطباعة ولتفاصيل الموظف والإجازة

## RPC المقترحة لهذه الصفحة
- `forms_submit_leave_request_v3`
- `forms_request_upload_ticket_v3`

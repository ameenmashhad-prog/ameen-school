# استمارة الاستئذان المالي — نسخة Production-ready أولية

## ما الذي تم بناؤه
تمت إضافة صفحة مستقلة داخل:
- `app/[locale]/forms/financial-permission/page.jsx`

## ما الذي تدعمه الصفحة الآن
- أقسام فعلية لبيانات الجهة الطالبة والتفاصيل المالية والمرفقات والاعتماد
- حفظ محلي + Draft عبر RPC
- تحقق Validation للمبلغ والعملة والحقول الأساسية والمرفق والتوقيع
- رفع مرفق داعم عبر upload ticket + upload transport
- Tracking ID بعد الإرسال
- صفحة نجاح مستقلة بعد submit
- معاينة للطباعة وملخص مالي سريع

## RPC المقترحة لهذه الصفحة
- `forms_submit_financial_permission_v3`
- `forms_request_upload_ticket_v3`

# استمارة تقييم معلم — نسخة Production-ready أولية

## ما الذي تم بناؤه
تمت إضافة صفحة مستقلة داخل:
- `app/[locale]/forms/teacher-evaluation/page.jsx`

## ما الذي تدعمه الصفحة الآن
- أقسام فعلية لبيانات المعلم والتقييم والمرفقات والاعتماد
- حفظ محلي + Draft عبر RPC
- تحقق Validation للحقول الإلزامية والدرجة من 0 إلى 100 والمرفق والتوقيع
- رفع مرفق داعم عبر upload ticket + upload transport
- Tracking ID بعد الإرسال
- صفحة نجاح مستقلة بعد submit
- معاينة للطباعة وتفاصيل التقييم

## RPC المقترحة لهذه الصفحة
- `forms_submit_teacher_evaluation_v3`
- `forms_request_upload_ticket_v3`

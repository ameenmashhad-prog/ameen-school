# لوحة استعراض الطلبات المرسلة — Forms v3

## ما الذي تمت إضافته
تمت إضافة صفحة مراجعة مخصصة داخل:
- `app/[locale]/forms/submissions/page.jsx`

وتستخدم المكوّن:
- `components/forms-submissions-shell.jsx`

## القدرات الحالية
- قراءة قائمة الطلبات عبر RPC
- تصفية حسب:
  - form slug
  - visibility
  - status
- عرض KPI سريع
- عرض التفاصيل المنظمة حسب أقسام النموذج
- تحديث حالة الطلب عبر RPC
- دعم ثلاثي اللغة

## RPC المقترحة لهذه الصفحة
- `forms_list_submissions_v3`
- `forms_get_submission_v3`
- `forms_update_submission_status_v3`

## ملاحظة
الصفحة حالياً تعتمد على server routes التي تستدعي RPCات الخلفية. في الإنتاج النهائي، يفضّل ربطها بطبقة auth/session صريحة قبل الاستخدام الواسع.

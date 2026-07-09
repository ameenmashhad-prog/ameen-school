# التحقق الحي بعد تطبيق SQL 144 → 150

## الحالة
تم تنفيذ فحص حي على قاعدة البيانات بعد إبلاغ تشغيل الملفات:
- `144_forms_v3_engine_foundation.sql`
- `145_forms_v3_submissions_review.sql`
- `146_forms_v3_leave_request_submit.sql`
- `147_forms_v3_teacher_evaluation_submit.sql`
- `148_forms_v3_financial_permission_submit.sql`
- `149_forms_v3_student_registration_packet_submit.sql`
- `150_forms_v3_submission_name_fallbacks.sql`

## النتيجة العامة
### ناجح
- `forms_v3_health_check`
- `forms_save_draft_v3`
- `forms_list_versions_v3`
- `forms_request_upload_ticket_v3`
- `forms_resolve_upload_ticket_v3`
- `forms_finalize_upload_ticket_v3`
- `forms_submit_leave_request_v3`
- `forms_submit_teacher_evaluation_v3`
- `forms_submit_financial_permission_v3`
- `forms_submit_student_registration_packet_v3`
- `forms_list_submissions_v3`
- `forms_get_submission_v3`
- `forms_update_submission_status_v3`

## ما الذي تم التحقق منه عمليًا
### 1) Health check
أكد أن الجداول وRPCs الأساسية لمحرك الاستمارات موجودة فعليًا على البيئة الحية.

### 2) Draft smoke test
تم إنشاء form draft تجريبي وقراءة versions بنجاح.

### 3) Upload ticket flow
تم التحقق من:
- إنشاء تذكرة رفع
- Resolve للتذكرة
- Finalize للتذكرة

### 4) Submit smoke tests
تم إنشاء طلبات smoke test للنماذج التالية:
- Leave Request
- Teacher Evaluation
- Financial Permission
- Student Registration Packet

ثم تم:
- قراءتها من list submissions
- جلب التفاصيل عبر get submission
- أرشفتها عبر update submission status

## التحقق من Patch 150
بعد تشغيل `150_forms_v3_submission_name_fallbacks.sql` تم إجراء فحص حي إضافي على نموذجين كانا يحتاجان fallback أفضل:
- `financial-permission-v3`
- `student-registration-packet-v3`

### النتيجة
- في `financial-permission-v3` أصبح `applicant_name` يظهر من الحقل `requester_name`
- في `student-registration-packet-v3` أصبح:
  - `applicant_name` يظهر من الحقل `student_full_name`
  - `guardian_name` يظهر من الحقل `guardian_full_name`

وهذا يعني أن لوحة الطلبات المرسلة ستعرض الأسماء بشكل أوضح دون تعديل إضافي في الواجهة.

## التوصية التالية
الخطوة التالية المنطقية الآن:
1. إعادة فتح لوحة الطلبات المرسلة ومراجعة عرض الأسماء بصريًا
2. تنفيذ UAT بصري على:
   - تسجيل الطالب
   - فورم التسجيل المطبوع
   - طلب الإجازة
   - تقييم المعلم
   - الاستئذان المالي
3. بعدها الانتقال إلى نشر `next-forms-v3` أو ربطه ببيئة Vercel النهائية

## تنبيه مهم
التحقق الحالي أكد أن backend صار يعمل، لكنه لا يغني عن مراجعة RBAC الفعلية قبل الإطلاق العام الكامل، خصوصًا لمسارات review الإدارية.

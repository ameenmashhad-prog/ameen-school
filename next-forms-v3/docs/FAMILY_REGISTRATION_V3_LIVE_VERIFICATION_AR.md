# التحقق الحي — Family Registration v3 بعد تشغيل SQL 151

## الحالة
تم تشغيل:
- `sql/archive/151_forms_v3_family_registration_submit.sql`

ثم تم تنفيذ فحص حي مباشر على RPC الجديدة:
- `forms_submit_family_registration_v3`

## ما الذي تم التحقق منه عمليًا
### 1) Submit
تم إنشاء طلب عائلي تجريبي بنجاح يحتوي على:
- بيانات ولي الأمر
- بيانات الأم
- طالبين داخل نفس الطلب
- جدول دفعات عائلي
- حالة وثائق
- موافقة واعتماد

### 2) List submissions
ظهر الطلب في:
- `forms_list_submissions_v3`

مع القيم الصحيحة:
- `guardian_name = علي كاظم حسن`
- `applicant_name = محمد علي حسن`

### 3) Get submission
تم جلب الطلب من:
- `forms_get_submission_v3`

وتأكدنا أن البنية المخزنة تتضمن:
- `guardian`
- `mother`
- `students[]`
- `payment_entries[]`
- `documents`
- `approval`

### 4) Status update / cleanup
تم أرشفة طلب التحقق بنجاح عبر:
- `forms_update_submission_status_v3`

## النتيجة
### ناجح
- `forms_submit_family_registration_v3`
- الإدراج داخل `forms_v3_submissions`
- الظهور في لوحة الطلبات المرسلة
- fallback الأسماء يعمل بشكل صحيح مع `guardian_full_name` و `student_full_name`
- الأرشفة بعد الاختبار ناجحة

## الخلاصة التنفيذية
أصبح `family-registration-v3` الآن:
- **منفذًا في الواجهة**
- **مربوطًا بـ RPC فعلية**
- **صالحًا للاختبار الوظيفي/UAT**

## الخطوة التالية الموصى بها
1. تنفيذ UAT سريع على المسار:
   - `/ar/forms/family-registration-v3`
2. عند نجاحه:
   - اعتماد هذا المسار كبديل مستقبلي لـ `family-registration.html`
3. بعد أول deploy متاح:
   - تفعيل Soft Launch ثم Hard Switch

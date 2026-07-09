# تفعيل backend الحقيقي لـ Forms v3

## الهدف
هذه الوثيقة تحوّل `next-forms-v3` من كود جاهز محليًا إلى طبقة مربوطة فعليًا بقاعدة البيانات ورفع المرفقات وRPC.

## الحالة الحالية المؤكدة
### جاهز
- التطبيق يبني ويعمل محليًا بنجاح.
- المسارات الجديدة تعمل، ومنها فورم التسجيل المطبوع من الـPDF.
- مسارات API الداخلية موجودة لكل النماذج الحالية.

### غير مفعّل بعد على قاعدة البيانات live
تم التحقق من RPC التالية على Supabase live:
- `forms_v3_health_check`

### النتيجة الحالية
- **غير موجودة في schema cache**
- هذا يعني عمليًا أن SQL الخاصة بـ Forms v3 **لم تُطبَّق بعد** على البيئة الحية.

## ترتيب تطبيق SQL
طبّق الملفات بالترتيب التالي داخل SQL Editor أو أي مسار إدارة معتمد:

1. `sql/archive/144_forms_v3_engine_foundation.sql`
2. `sql/archive/145_forms_v3_submissions_review.sql`
3. `sql/archive/146_forms_v3_leave_request_submit.sql`
4. `sql/archive/147_forms_v3_teacher_evaluation_submit.sql`
5. `sql/archive/148_forms_v3_financial_permission_submit.sql`
6. `sql/archive/149_forms_v3_student_registration_packet_submit.sql`

## لماذا هذا الترتيب؟
- ملف 144 ينشئ الجداول الأساسية وRPCs العامة ورفع المرفقات وsubmit الأساسي لتسجيل الطالب.
- ملف 145 يضيف review workflow للطلبات المرسلة.
- الملفات 146 → 149 تضيف submit RPC لكل نموذج Production-ready إضافي.

## متطلبات Storage
أنشئ bucket باسم:
- `forms-v3-uploads`

### التوصية
- يكون bucket **خاصًا / private**
- يرفع الملف عبر server route فقط: `/api/forms/upload-file`
- لا تعتمد على رفع مباشر من العميل إلى الجداول أو التخزين دون ticket

## متغيرات البيئة المطلوبة
انسخ من:
- `.env.example`

### المتغيرات المطلوبة
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `FORMS_UPLOAD_BUCKET`

## التحقق بعد تطبيق SQL
### 1) فحص الصحة
```bash
cd next-forms-v3
npm run forms:health
```

المتوقع:
- `ok: true`
- وجود الجداول الأربع الأساسية
- وجود RPCs الأساسية في health check

### 2) فحص save draft + list versions
```bash
cd next-forms-v3
npm run forms:smoke
```

المتوقع:
- نجاح `forms_save_draft_v3`
- نجاح `forms_list_versions_v3`
- إرجاع نسخة واحدة على الأقل للفورم التجريبي

## فحوص وظيفية بعد الربط
بعد نجاح الصحة والـsmoke test:
1. افتح `/ar/forms/student-registration`
2. افتح `/ar/forms/student-registration-packet`
3. جهّز upload ticket
4. ارفع ملفًا تجريبيًا
5. أرسل الفورم
6. افتح `/ar/forms/submissions`
7. تأكد من ظهور الطلب وتغيير حالته

## ملاحظات أمان
- الواجهة لا تكتب مباشرة إلى الجداول.
- كل الكتابة تمر عبر RPC أو server route.
- لا تحفظ `SUPABASE_SERVICE_ROLE_KEY` داخل أي ملف client-side.

## نقطة قرار تالية
بعد تطبيق SQL ونجاح `forms:health` و`forms:smoke` تصبح الخطوة التالية الطبيعية:
- ربط env الفعلية في Vercel
- ثم نشر `next-forms-v3`
- ثم تنفيذ UAT نهائي على النماذج الأربعة + فورم التسجيل المطبوع

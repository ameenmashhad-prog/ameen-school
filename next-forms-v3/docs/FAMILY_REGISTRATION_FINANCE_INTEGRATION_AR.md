# تكامل الرسوم والأقساط بين `family-registration-v3` والنظام المالي

## ما الذي تم تنفيذه في الواجهة؟
### 1) ربط الصفوف بكتالوج الرسوم من قاعدة البيانات
تمت إضافة route قراءة جديدة:
- `app/api/forms/data/family-registration-finance/route.js`

هذه route تقرأ:
- `classes`
- `fee_structures`

ثم تعيد لكل صف:
- `class_id`
- `class_name`
- `fee_structure_id`
- `annual_fee`
- `monthly_fee`
- `currency`
- `academic_year`

### 2) الفورم يسحب الرسوم الفعلية بدل القيم الثابتة
داخل `family-registration-v3`:
- اختيار الصف لكل طالب أصبح قابلًا للربط مع الرسوم القادمة من `fee_structures`
- تظهر بطاقة ربط مالي داخل كل طالب توضح:
  - الرسوم السنوية للصف
  - الشهري التقريبي
  - حالة الربط من النظام المالي

### 3) خطة الأقساط داخل بطاقة الطالب
أُضيفت حقول:
- نوع الخطة
- عدد الأقساط
- تاريخ بداية الخطة

ثم يتم إنشاء preview حي للأقساط المتوقعة بنفس منطق قريب من الصفحة المالية.

### 4) الملخص المالي العائلي أصبح مرتبطًا بالرسوم الفعلية
أُضيفت مؤشرات جديدة مثل:
- إجمالي الرسوم المتوقعة من الصفوف المختارة
- المبلغ المتبقي المتوقع بعد الدفعات المدخلة

---

## ما الذي تم تجهيزه في قاعدة البيانات؟
### ملف SQL جديد
- `sql/archive/152_forms_v3_family_registration_finance_bridge.sql`

### دوره
- يوسّع `registration_families` و `registration_students`
- يحفظ داخل طلب التسجيل العائلي:
  - `fee_structure_id`
  - `annual_fee_snapshot`
  - `monthly_fee_snapshot`
  - `finance_plan_type`
  - `finance_installments_count`
  - `finance_plan_start_date`
  - `finance_plan_end_date`
  - `finance_installment_schedule`
- ويجعل `forms_submit_family_registration_v3` لا يكتفي بحفظ الطلب في `forms_v3_submissions`
  بل يكتب أيضًا في جداول التسجيل القديمة لكي لا ينفصل المسار الجديد عن مسار الإدارة القائم.

---

## كيف يتحقق التكامل مع الصفحة المالية؟
### ملف SQL إضافي
- `sql/archive/153_family_registration_activation_finance_sync.sql`

### دوره
عند تفعيل الأسرة عبر:
- `activate_registered_user_rpc`

يقوم أيضًا بـ:
- إنشاء `student_fees`
- إنشاء `finance_payment_plans`
- إنشاء `student_installments`

اعتمادًا على الـ snapshot المخزنة من `family-registration-v3`.

### النتيجة
بعد تفعيل الطالب من التسجيل:
- يظهر له ملف مالي فعلي
- تظهر له خطة الأقساط في النظام المالي
- يصبح المسار العائلي الجديد متصلًا فعليًا بالصفحة المالية القديمة

---

## ماذا تحتاج لتفعيل التكامل الكامل؟
شغّل بالترتيب:
1. `sql/archive/152_forms_v3_family_registration_finance_bridge.sql`
2. `sql/archive/153_family_registration_activation_finance_sync.sql`

بعدها يصبح التكامل المالي كاملًا على مستوى:
- سحب رسوم الصفوف من قاعدة البيانات
- حفظ snapshot داخل التسجيل
- تحويلها إلى ملفات مالية فعلية عند التفعيل

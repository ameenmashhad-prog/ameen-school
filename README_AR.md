# مدارس أمين الرضا (ع) — نسخة الواجهات النظيفة

هذه نسخة جديدة منظمة من الموقع، هدفها إزالة تكرار التبويبات والفوضى، وتقسيم النظام إلى واجهات واضحة حسب الدور.

## الواجهات

| الملف | الواجهة | الأدوار |
|---|---|---|
| `index.html` | دخول موحد وتوجيه تلقائي | كل المستخدمين |
| `super-admin.html` | واجهة المسؤول الأعلى | `admin` أو `is_super_admin=true` |
| `staff.html` | واجهة الإدارة التشغيلية | `finance`, `discipline`, `counselor`, `psychologist` |
| `teacher.html` | واجهة المعلم | `teacher` |
| `student.html` | واجهة الطالب / ولي الأمر | `student`, `parent` |

## ماذا تعرض كل واجهة؟

### 1) المسؤول الأعلى
- نظرة عامة شاملة.
- الطلاب.
- الأكاديمية والجداول.
- المالية.
- الحضور.
- الانضباط والإرشاد.
- التقييم والإعفاءات.
- المستخدمون والصلاحيات.
- التقارير.

### 2) الإدارة التشغيلية
واجهة واحدة تتكيف مع الدور:
- المسؤول المالي: الرسوم، المدفوعات، المتبقيات.
- مسؤول الانضباط: الحضور والغياب.
- المرشد النفسي: مؤشرات متابعة الطلاب من الغياب والسلوك والدرجات.

### 3) المعلم
- طلابي.
- تحضير الحضور.
- الدرجات.
- الجدول الأسبوعي.
- ملاحظات السلوك.

### 4) الطالب / ولي الأمر
- الملخص.
- الدرجات.
- الحضور.
- الأقساط.
- الجدول.
- السلوك.

## البنية

```txt
amin-clean-portals/
├── index.html
├── super-admin.html
├── staff.html
├── teacher.html
├── student.html
├── assets/
│   ├── config.js
│   ├── core.js
│   └── portal.css
├── libs/
│   ├── supabase.min.js
│   ├── papaparse.min.js
│   └── xlsx.full.min.js
├── api/
│   └── proxy.js
└── vercel.json
```

## ملاحظات مهمة

- لا توجد مكتبات خارجية أو CDN.
- الاتصال يتم عبر `/api` proxy لتجنب حظر Supabase.
- Realtime متوقف افتراضياً لأن Vercel proxy لا يدعم WebSocket.
- الواجهات تقرأ من الجداول الحالية نفسها: `students`, `classes`, `student_fees`, `student_installments`, `fee_payments`, `attendance`, `behavior_records`, `grades`, `exemptions`, `weekly_schedule`, `users`.

## طريقة الرفع

ارفعي محتويات مجلد `amin-clean-portals/` إلى جذر مشروع Vercel.

الشكل الصحيح:

```txt
project-root/
├── index.html
├── super-admin.html
├── staff.html
├── teacher.html
├── student.html
├── assets/
├── libs/
├── api/
└── vercel.json
```

## الاختبار بعد الرفع

1. افتحي `index.html`.
2. سجلي دخول بحسابك.
3. يجب أن يتم توجيهك تلقائياً حسب الدور.
4. افتحي Console وتحققي من عدم وجود أخطاء.
5. اختبري تحميل الطلاب والحضور والمالية.

## ملاحظة عن النظام القديم

هذه الحزمة لا تعتمد على الصفحات القديمة مثل `dashboard.html` و `finance.html` حتى لا تعود مشكلة تكرار التبويبات. يمكن نشرها كنسخة جديدة، وبعد التأكد منها يمكن استبدال القديم تدريجياً.

---

## تحديث تطوير الموقع وقاعدة البيانات

أضيفت ملفات SQL جديدة:

```txt
sql/archive/02_role_split_and_views.sql
sql/archive/03_optional_rls_policies.sql
```

### `02_role_split_and_views.sql`

- يضيف/يوسع أدوار المستخدمين مثل `academic`, `counselor`, `psychologist`.
- يضيف فهارس أداء للجداول الأساسية.
- يضيف Views للتقارير والواجهات:
  - `v_clean_student_overview`
  - `v_clean_finance_summary`
  - `v_clean_attendance_today`
  - `v_clean_academic_summary`

### `03_optional_rls_policies.sql`

ملف اختياري لتفعيل سياسات RLS حسب الدور:

- المسؤول المالي يرى المالية فقط.
- المسؤول العلمي يرى الطلاب، الحضور، السلوك، الدرجات، الإعفاءات، ولا يرى المالية.
- مسؤول الانضباط يرى الحضور والسلوك والطلاب ولا يرى المالية.
- الطالب/ولي الأمر يرى بياناته فقط.

لا تشغلي RLS إلا بعد اختبار النسخة الحالية وأخذ نسخة احتياطية من السياسات.

---

## نماذج التسجيل الإلكترونية 2026-2027

أضيفت صفحات جديدة:

```txt
family-registration.html      # تسجيل ولي أمر وطلاب متعددين لنفس الأسرة
teacher-registration.html     # تسجيل المعلمين
registrations-admin.html      # مراجعة طلبات التسجيل للإدارة
```

وأضيفت ملفات داعمة:

```txt
assets/registration.css
assets/registration.js
libs/calendar-lib.js
sql/archive/04_registration_forms_schema.sql
```

### قبل استخدام النماذج

شغّلي في Supabase SQL Editor محتوى الملف:

```txt
sql/archive/04_registration_forms_schema.sql
```

هذا ينشئ جداول طلبات التسجيل وسياسات الإدخال العامة، ولا يغيّر جداول الطلاب والمعلمين القديمة.

### الجداول الجديدة

```txt
registration_families
registration_students
registration_teachers
```

### الصور

يتم رفع الصور إلى bucket:

```txt
registration-photos
```

إذا لم تعمل الصور، سيبقى التسجيل محفوظاً، وستظهر رسالة أن صلاحية التخزين تحتاج مراجعة.

---

## إدارة الجدول المدرسي واستيراد aSc Timetables

أضيفت صفحة جديدة:

```txt
schedule-management.html
```

وتدعم:

- رفع ملف XML صادر من aSc Timetables بترميز Windows-1256.
- تحليل المواد والصفوف والمعلمات قبل الحفظ.
- كشف الأسماء غير المطابقة.
- كشف تعارض المعلمة أو الصف في نفس اليوم والحصة.
- حفظ الجدول في `weekly_schedule`.
- أوضاع الاستيراد:
  - تحديث الموجود وإضافة الجديد.
  - استبدال جدول الفصل بالكامل.
  - استبدال صفوف الملف فقط.
- تعديل يدوي للحصص بعد الاستيراد.
- عرض جدول الصف.
- عرض جدول المعلمة وعدد حصصها الأسبوعية.
- عرض جدول الطالب حسب صفه.
- تجهيز أفكار الربط اللاحق مع التقويم والرواتب والواجبات.

### SQL المطلوب للجدول

شغّلي:

```txt
sql/archive/05_schedule_management_schema.sql
```

هذا الملف يضيف:

- جدول تتبع عمليات الاستيراد `schedule_import_batches`.
- أعمدة اختيارية على `weekly_schedule` للتتبع والربط المستقبلي.
- Views:
  - `v_schedule_detailed`
  - `v_teacher_load_summary`

### رابط الصفحة

من واجهة المسؤول الأعلى يوجد رابط:

```txt
إدارة الجدول المدرسي
```

ومن واجهة المسؤول العلمي يظهر رابط إدارة الجدول أيضاً.

---

## تحديث تنظيم الفصول الدراسية والجدول

أضيف ملف SQL جديد:

```txt
sql/archive/07_cleanup_academic_periods_keep_two.sql
```

وظيفته:

- الإبقاء فقط على:
  - `الفصل الدراسي الأول 2026/2027`
  - `الفصل الدراسي الثاني 2026/2027`
- حذف أي فصول دراسية مكررة أو زائدة.
- إعادة ربط الجداول المرتبطة مثل `weekly_schedule`, `grades`, `exemptions` بالفصل المناسب قبل الحذف.

تم أيضاً تعديل صفحة `schedule-management.html` لتكون صفحة واحدة موحدة بدل تبويبات كثيرة، مع أقسام داخل الصفحة.

تم تعديل قواعد المواد:

- كل الصفوف: التربية الإسلامية، اللغة العربية، اللغة الإنجليزية، الرياضيات.
- الابتدائي فقط: العلوم، التربية الفنية، التربية البدنية.
- الرابع والخامس والسادس الابتدائي + الأول والثاني والثالث المتوسط: الاجتماعيات.
- المتوسطة والإعدادية: الأحياء، الفيزياء، الكيمياء.
- الفنية والبدنية في المتوسطة والإعدادية تظهر كمواد نشاط وليست مواد إلزامية.

---

## المرحلة المتقدمة: التقويم، الواجبات، ونشاط المعلمات والرواتب

أضيف ملف SQL جديد:

```txt
sql/archive/08_schedule_calendar_homework_payroll.sql
```

يشمل:

- تعريفات العطل الرسمية الإيرانية الثابتة بالشمسية.
- تعريفات العطل الهجرية المتحركة مثل تاسوعاء، عاشوراء، الأربعينية، عيد الفطر، عيد الأضحى.
- مقترحات شهرية للعطل تحتاج موافقة قبل النشر.
- جدول `class_sessions` لتوليد جلسات فعلية من الجدول الأسبوعي.
- جدول `homeworks` للواجبات المرتبطة بالحصة.
- جدول `teacher_activity_log` لتسجيل نشاط يثبت أن المعلمة أخذت الحصة.
- جدول `teacher_payroll_rules` وقاعدة حساب الرواتب حسب الحصص المثبتة بالنشاط.
- Views:
  - `v_teacher_verified_sessions`
  - `v_teacher_payroll_preview`

مبدأ الرواتب:
لا تُحتسب الحصة للمعلمة إلا إذا ظهر نشاط مرتبط بها مثل:
- تثبيت يدوي للحصة.
- نشر واجب.
- لاحقاً: تسجيل حضور أو إدخال درجات أو ملاحظة درس.

---

## إعدادات المدير السرية: أجور المعلمات ورسوم الصفوف

أضيفت صفحة جديدة:

```txt
admin-finance-rules.html
```

لا تفتح إلا للمدير `admin` أو `is_super_admin=true`.

تتحكم في:

- سعر حصة كل معلمة بشكل مستقل.
- قسط كل صف شهرياً، ويُحسب السنوي = الشهري × 9 أشهر.

أضيف ملف SQL:

```txt
sql/archive/09_admin_teacher_rates_and_class_fees.sql
```

يشمل:

- التأكد من وجود `fee_structures`.
- التأكد من وجود `teacher_payroll_rules`.
- RLS بحيث لا يقرأ أو يعدّل هذه الجداول إلا المدير.
- تحديث `v_teacher_payroll_preview` ليستخدم سعر المعلمة الخاص أولاً، ثم السعر العام إن وجد.

---

## النظام المالي الاحترافي

أضيفت صفحة جديدة:

```txt
finance-pro.html
```

وأضيف ملف SQL:

```txt
sql/archive/10_finance_professional_schema.sql
```

يشمل:

- إدارة ملفات الطلاب المالية.
- خطط أقساط مرنة.
- تسجيل مدفوعات بالدولار أو الريال الإيراني.
- أرشفة أسعار الصرف.
- إيصالات ونماذج طباعة.
- سجل تدقيق مالي Audit Trail.
- تقارير مالية حسب الطالب والصف والأقساط والمدفوعات.
- وضع طوارئ يحفظ مسودات محلية في المتصفح إذا فشل الاتصال.

ملاحظة صلاحيات:
- إعداد قسط كل صف وسعر حصة كل معلمة يبقى في `admin-finance-rules.html` للمدير فقط.
- المسؤول المالي يمكنه متابعة الأقساط وتسجيل الدفعات، أما إنشاء الرسوم من قسط الصف فهو للمدير فقط.

---

## نظام الدرجات والتقييم الأكاديمي الاحترافي

أضيفت صفحة جديدة:

```txt
academic-pro.html
```

وأضيف ملف SQL:

```txt
sql/archive/11_academic_grading_system.sql
```

يشمل:

- أوزان قابلة للتعديل حسب المرحلة:
  - الابتدائي: تقييم مستمر 20% + اختبارات شهرية 80%.
  - المتوسط: تقييم مستمر 10% + اختبارات شهرية 90%.
  - الإعدادي: تقييم مستمر 10% + اختبارات شهرية 90%.
- جدول `continuous_assessments` للتقييم المستمر.
- جدول `exams` و `exam_scores` للاختبارات الشهرية.
- حساب تلقائي للدرجة النهائية عبر `v_academic_subject_results`.
- حساب الإعفاء العام والمرشحين عبر `v_academic_student_summary`.
- قرارات إدارية للإعفاء عبر `academic_exemption_decisions`.
- دعم مرشحي الإعفاء والطلاب المتعثرين.

صلاحيات:
- المعلم: إدخال التقييم والاختبارات ومتابعة الأداء.
- الإدارة/المسؤول العلمي: تعديل الأوزان واعتماد الإعفاء وإصدار التقارير.

---

## إصلاح فلترة المواد حسب المرحلة

أضيف ملف:

```txt
sql/archive/14_academic_subject_stage_filter.sql
```

وظيفته منع ظهور مواد غير مناسبة للمرحلة في نتائج الطلاب، مثل:

- الأحياء في الصف الأول الابتدائي.
- الاجتماعيات في الصفوف الابتدائية الأولى.
- العلوم في المتوسط والإعدادي.

كما تم تعديل `academic-pro.html` ليعرض في إدخال الدرجات فقط المواد المناسبة للصف المختار.

---

## تحديث الرسوم السنوية ووظائف الأم وترتيب الصفوف

تم تعديل إعدادات المدير:

- `admin-finance-rules.html` أصبح يستخدم الرسوم السنوية لكل صف بدلاً من القسط الشهري.
- عند إنشاء ملف مالي للطالب يتم تحديد خطة الدفع لاحقاً: دفعة كاملة أو أقساط وعدد الأشهر.
- للحفاظ على توافق قاعدة البيانات، يتم حفظ:
  - `annual_fee` = الرسوم السنوية.
  - `amount` = الرسوم السنوية للتوافق مع النسخ القديمة.
  - `monthly_fee` = قيمة تقريبية annual / 9.

تم تعديل تسجيل ولي الأمر:

- وظائف الأم أصبحت مناسبة أكثر: ربة منزل، طالبة، موظفة، معلمة، طبيبة، مهندسة...
- ترتيب الصفوف في استمارة الطالب صار حسب المرحلة: الابتدائي ثم المتوسط ثم الإعدادي.

---

## تحديث النظام المالي الاحترافي — تبسيط الدفع وسعر الصرف

تم تعديل `finance-pro.html`:

- حذف تبويب سعر الصرف المستقل.
- دمج سعر الصرف مباشرة داخل قسم تسجيل دفعة.
- إضافة جلب سعر الدولار من TGJU:
  - `/api/exchange/tgju`
  - المصدر: `https://www.tgju.org/profile/price_dollar_rl`
- عند الدفع بالريال الإيراني يتم حساب القيمة بالدولار فوراً.
- يمكن إدخال سعر الصرف يدوياً إذا لم يعمل المصدر الإلكتروني.
- عند الدفع يختار المحاسب أولاً:
  - دفع كامل للرصيد.
  - أو دفع قسط محدد.
- قائمة الأقساط تعرض أسماء الأشهر وتاريخ الاستحقاق والمتبقي بدلاً من NULL وقيم مكررة.
- تم تحسين الإيصال ليظهر بشكل فاتورة احترافية منظمة.
- تم تبسيط سجل التدقيق المالي ليعرض ملخصات مفهومة بدلاً من JSON خام.

أضيف ملف SQL:

```txt
sql/archive/15_finance_runtime_hotfix.sql
```

شغليه إذا ظهر خطأ:

```txt
payment_method column not found
```

كما أضيف endpoint جديد:

```txt
api/exchange-tgju.js
```

وتم تحديث `vercel.json` بمسار:

```txt
/api/exchange/tgju
```

---

## تحديثات إصلاح النظام المالي والجدول

أضيفت ملفات SQL جديدة:

```txt
sql/archive/17_cleanup_duplicate_student_fees.sql
sql/archive/18_teacher_activity_homework_fix.sql
```

### `17_cleanup_duplicate_student_fees.sql`

ينظف ملفات الرسوم المكررة للطالب في نفس السنة الدراسية.
يحذف فقط النسخ المكررة الآمنة التي لا تحتوي مدفوعات ولا أقساطاً مدفوعة، ويبقي الملف الذي يحتوي أعلى مبلغ مدفوع.

### `18_teacher_activity_homework_fix.sql`

يصلح تثبيت الحصص ونشر الواجبات المرتبطة بالحصة.
يوفر دوال:

```txt
confirm_teacher_session
create_session_homework
```

تستخدمها صفحة `schedule-management.html` لتسجيل نشاط فعلي للمعلمة.

---

## تحديث لوحة المعلم العملية

أعيد بناء `teacher.html` كلوحة معلم مخصصة لا تعرض إلا الطلاب المرتبطين بصفوف جدول المعلم.

الميزات:

- الحضور الافتراضي: الجميع حاضر، ولا يُسجل إلا الغياب أو التأخير.
- الغياب نوعان: مبرر / غير مبرر.
- الابتدائي: الحضور للحصة الأولى والثانية فقط.
- المتوسط والإعدادي: الحضور حصة حصة.
- إدخال جماعي للتقييم المستمر والاختبارات الشهرية.
- ملء درجة واحدة لكل الطلاب ثم تعديل الحالات الفردية.
- إنشاء واجب من حصة فعلية لتثبيت نشاط المعلمة.
- تثبيت الحصة يضيف نشاطاً للمعلمة ويُحسب لاحقاً في الراتب.

أضيف ملف SQL:

```txt
sql/archive/19_teacher_workflow_policies.sql
```

يشمل:

- عمود `absence_type` في attendance.
- فهرس حضور جديد يدعم الحصة-بحصة.
- RLS policies للمعلم حسب جدول `weekly_schedule`.
- صلاحيات إدخال التقييم والاختبارات للصفوف والمواد المرتبطة بالمعلم فقط.

---

## بنية الشعب والربط الأكاديمي

أضيف ملف SQL جديد:

```txt
sql/archive/20_academic_structure_sections_assignments.sql
```

ينقل النظام تدريجياً إلى النموذج الصحيح:

```txt
العام الدراسي → الفصل الدراسي → الصف → الشعبة → المادة → الحصة → المعلم → الطالب
```

يشمل:

- `academic_years`
- `sections`
- `student_enrollments`
- `teacher_assignments`
- ربط `weekly_schedule` بالشعبة والإسناد.
- إنشاء شعب أ، ب، ج، د لكل صف في 2026-2027.
- نقل الطلاب الحاليين افتراضياً إلى شعبة أ.
- توليد إسنادات المعلمين من الجدول الأسبوعي الحالي.
- Views:
  - `v_teacher_assignments`
  - `v_teacher_students`
  - `v_teacher_schedule`
  - `v_section_roster`

بعد تشغيله يجب تعديل لوحة المعلم تدريجياً لتقرأ من هذه الـ Views بدلاً من الصف فقط.

---

## صفحة إدارة الشعب والإسنادات

أضيفت صفحة:

```txt
section-assignment-management.html
```

تتيح للإدارة أو المسؤول العلمي:

- عرض الشعب حسب الصف.
- إنشاء شعبة.
- تعديل السعة وسياسة الجنس.
- عرض طلاب كل شعبة.
- نقل طالب من شعبة إلى شعبة.
- إسناد معلم إلى شعبة + مادة + فصل دراسي.

تم أيضاً تعديل استيراد aSc والتعديل اليدوي في `schedule-management.html` لربط الحصص بـ:

```txt
section_id
teacher_assignment_id
```

بدلاً من الاعتماد على الصف فقط.

الملف المطلوب تشغيله:

```txt
sql/archive/21_sections_assignments_admin.sql
```

---

## تحديث إدارة الشعب والإسنادات — نقل جماعي وتعديل الإسنادات

أضيف ملف SQL جديد:

```txt
sql/archive/23_assignment_edit_and_bulk_ui.sql
```

ويضيف:

- تعديل إسناد معلم موجود.
- تفعيل/إيقاف إسناد معلم.
- خيار تحديث الحصص والجلسات المرتبطة عند تعديل الإسناد.
- تحسين Views `v_teacher_assignments` و `v_teacher_schedule` بحيث لا يرى المعلم إلا الإسنادات النشطة.

تم تطوير صفحة:

```txt
section-assignment-management.html
```

لتدعم:

- إنشاء شعبة من واجهة مباشرة دون إدخال ID يدوياً.
- تحديد سعة الشعبة وسياسة الجنس.
- عرض طلاب الشعبة مع checkboxes.
- نقل جماعي للطلاب بين الشعب.
- تعديل إسناد معلم.
- إيقاف/تفعيل الإسناد.

---

## تحسين استيراد aSc للشعب تلقائياً

تم تعديل `assets/schedule.js` و `schedule-management.html` بحيث أصبح استيراد aSc يدعم:

- اكتشاف الشعبة من اسم الصف تلقائياً إذا كان الاسم مثل:
  - `الأول الابتدائي أ`
  - `الأول الابتدائي - ب`
  - `الأول الابتدائي (ج)`
  - `الأول الابتدائي شعبة د`
- إذا لم يجد شعبة في اسم الصف يستخدم الشعبة الافتراضية المختارة.
- عند الاستيراد يتم حفظ:
  - `section_id`
  - `teacher_assignment_id`
- في وضع استبدال صفوف الملف، إذا كانت الحصص مرتبطة بشعب، يتم استبدال الشعب الموجودة في الملف فقط بدلاً من حذف كل صفوف الصف.

---

## إصلاح صلاحية إعادة توليد الجلسات من SQL Editor

إذا ظهر:

```txt
ليست لديك صلاحية إعادة توليد الجلسات
```

عند تشغيل الدالة من Supabase SQL Editor، شغّلي:

```txt
sql/archive/25_regenerate_sessions_permission_fix.sql
```

السبب أن `auth.uid()` يكون `null` داخل SQL Editor، بينما يكون موجوداً عند التشغيل من الواجهة بحساب مدير.

الملف يسمح بالتشغيل من SQL Editor، ويمنع `anon/public` من استدعاء الدالة عبر API.

---

## تقرير المواد الناقصة لكل صف/شعبة

أضيف ملف SQL:

```txt
sql/archive/27_schedule_required_subjects_report.sql
```

ويضيف دالة:

```txt
schedule_required_subjects_report(academic_period_id)
```

تُظهر لكل صف/شعبة:

- المواد الإلزامية الموجودة.
- المواد الإلزامية الناقصة.
- المواد المطلوبة غير الموجودة أصلاً في قاعدة بيانات المواد.

كما أضيف قسم جديد داخل `schedule-management.html`:

```txt
تقرير المواد الناقصة
```

ومن التقرير يمكن الضغط على `إضافة حصة` للانتقال مباشرة إلى التعديل اليدوي مع تعبئة الصف والشعبة والمادة.

---

## اقتراح وإضافة الحصص الناقصة تلقائياً

أضيف ملف SQL:

```txt
sql/archive/28_schedule_missing_subject_suggestions.sql
```

ويضيف:

- `schedule_missing_subject_suggestions(period_id)`
- `add_missing_schedule_slot(...)`

في صفحة `schedule-management.html` أصبح تقرير المواد الناقصة يدعم:

- عرض المواد الناقصة.
- اقتراح أول خانة فارغة مناسبة.
- التأكد من عدم تعارض المعلم.
- زر إضافة حصة واحدة.
- زر إضافة كل المقترحات الممكنة.
- إذا لا يوجد معلم مسند للمادة والشعبة، يظهر زر للانتقال إلى صفحة إسناد المعلمين مع تعبئة الشعبة والمادة تلقائياً.

---

## تحسين لوحة المعلم — تحضير الدروس

تم تفعيل تبويب:

```txt
تحضير الدروس
```

في `teacher.html`.

الميزات:

- اختيار حصة قادمة.
- كتابة عنوان الدرس.
- كتابة أهداف الدرس.
- كتابة ملخص الشرح.
- إضافة مصادر أو روابط.
- إضافة فكرة واجب.
- حفظ التحضير.
- حفظ التحضير يثبت نشاط المعلمة للحصة ويُحسب ضمن نشاطها.

يعتمد على دالة SQL من ملف:

```txt
sql/archive/30_teacher_daily_workflow_enhancements.sql
```

خصوصاً:

```txt
save_lesson_plan
```

---

## واجهات بنك الأسئلة والاختبارات الإلكترونية

أضيفت صفحات:

```txt
teacher-exams.html   # للمعلم: بنوك أسئلة، إضافة سؤال، إنشاء اختبار، النتائج
online-exams.html    # للطالب: الاختبارات المتاحة، بدء الاختبار، المؤقت، التسليم
```

وأضيفت ملفات:

```txt
assets/teacher-exams.js
assets/online-exams.js
assets/exams.css
sql/archive/31_question_bank_online_exams.sql
sql/archive/32_online_exam_payload_and_submit.sql
```

خطوات الاستخدام:

1. شغلي SQL 31 ثم SQL 32.
2. افتحي `teacher-exams.html` بحساب معلم.
3. أنشئي بنك أسئلة.
4. أضيفي أسئلة.
5. أنشئي اختباراً وانشريه.
6. افتحي `online-exams.html` بحساب طالب.
7. ابدئي الاختبار وسلميه.

النتيجة تُرحّل إلى `exam_scores` وتدخل في النظام الأكاديمي.

---

## تحسينات الاختبارات الإلكترونية — الحفظ التلقائي والتحليل

أضيف ملف SQL:

```txt
sql/archive/33_online_exams_enhancements.sql
```

ويضيف:

- ربط الاختبار بحصة فعلية `class_session_id`.
- حفظ تلقائي لإجابات الطالب أثناء الاختبار.
- تسجيل تنبيهات عند مغادرة صفحة الاختبار.
- منع النسخ واللصق داخل صفحة الاختبار كإجراء تقليل غش بسيط.
- تصحيح يدوي للإجابات المقالية أو غير التلقائية.
- Views للتحليل:
  - `v_online_exam_analysis`
  - `v_online_exam_question_analysis`

تم تحديث:

```txt
teacher-exams.html
online-exams.html
assets/teacher-exams.js
assets/online-exams.js
```

الآن المعلم يستطيع ربط الاختبار بحصة، ورؤية تحليل الاختبار، وتصحيح الإجابات التي تحتاج مراجعة.
والطالب يحصل على حفظ تلقائي أثناء الاختبار.

---

## تعديل وحذف الأسئلة والنماذج الامتحانية

أضيف ملف SQL:

```txt
sql/archive/34_question_exam_edit_delete.sql
```

ويضيف دوال آمنة:

```txt
upsert_question_with_options
delete_question_safely
update_online_exam_model
delete_online_exam_safely
```

الآن في صفحة:

```txt
teacher-exams.html
```

أصبح بإمكان المعلم:

- تعديل السؤال.
- حذف السؤال.
- تعديل النموذج الامتحاني.
- حذف النموذج الامتحاني.
- تعديل عنوان الاختبار، التعليمات، الوقت، الحالة، الحصة، والأسئلة المختارة.

ملاحظة أمان مهمة:

- إذا كان السؤال أو النموذج مستخدماً في محاولات طلاب، يمنع النظام حذف/تغيير البنية حتى لا تتلف النتائج.
- إذا حُذف نموذج عليه محاولات، يتم أرشفته بدل حذفه.

---

## متابعة الاختبار واسترجاع المسودات

أضيف ملف SQL:

```txt
sql/archive/35_online_exam_resume_drafts_reports.sql
```

ويضيف:

- متابعة نفس محاولة الاختبار إذا كانت لا تزال `in_progress`.
- عدم إنشاء محاولة جديدة عند رجوع الطالب للاختبار.
- حفظ ترتيب الأسئلة داخل المحاولة حتى لا يتغير ترتيب الأسئلة عند الرجوع.
- إرجاع إجابات المسودة إلى الطالب عند فتح الاختبار مرة أخرى.
- عرض آخر وقت حفظ داخل بطاقة الاختبار.
- عرض تنبيهات مغادرة الصفحة في سجل محاولات الطالب.
- تقرير تفصيلي جديد للمعلم:

```txt
v_online_exam_attempts_detailed
```

تم تحديث:

```txt
assets/online-exams.js
assets/teacher-exams.js
assets/exams.css
```

صفحة الطالب الآن تعرض:

- زر "متابعة الاختبار" إذا توجد محاولة مفتوحة.
- استرجاع الإجابات المحفوظة تلقائياً.
- سجل محاولات أوضح مع الدرجة والتنبيهات.

صفحة المعلم الآن تعرض في النتائج:

- تحليل الاختبارات.
- تحليل سؤال بسؤال.
- محاولات الطلاب بالتفصيل.

---

## أدوات مراجعة المعلم للاختبارات الإلكترونية

أضيف ملف SQL:

```txt
sql/archive/36_online_exam_teacher_review_tools.sql
```

ويضيف:

- View تفصيلي لإجابات الطلاب:

```txt
v_online_exam_answers_detailed
```

- تغيير حالة النموذج بسرعة:

```txt
set_online_exam_status
```

- نسخ النموذج الامتحاني كمسودة جديدة بدون نسخ محاولات الطلاب:

```txt
clone_online_exam_model
```

- إعادة تصحيح محاولة واحدة أو نموذج كامل:

```txt
regrade_online_exam_attempt
regrade_online_exam
```

تم تحديث صفحة المعلم:

```txt
teacher-exams.html
assets/teacher-exams.js
```

والآن يستطيع المعلم من قائمة النماذج:

- نشر النموذج.
- إغلاق النموذج.
- نسخ النموذج.
- إعادة التصحيح.
- تعديل النموذج.
- حذف/أرشفة النموذج.

وفي صفحة النتائج:

- تصحيح يدوي أوضح مع اسم الطالب والسؤال والإجابة.
- تصدير محاولات الطلاب إلى CSV.

---

## أنواع الأسئلة المتقدمة ومولد النماذج الامتحانية

أضيف ملف SQL:

```txt
sql/archive/37_advanced_exam_question_types_and_generator.sql
```

ويضيف دعم أنواع أسئلة جديدة داخل بنك الأسئلة والاختبارات:

- اختيار متعدد الإجابات `multi_select`
- ترتيب `ordering`
- تحديد الخطأ `identify_error`
- قراءة وفهم `reading_comprehension`
- إكمال حوار `dialog_completion`
- تصحيح خطأ نحوي/إملائي `grammar_correction`
- حل مسائل `problem_solving`
- مقارنة `comparison`
- سبب ونتيجة `cause_effect`
- موقف تطبيقي `scenario`

ويحسن التصحيح الآلي لـ:

- اختيار من متعدد
- صح وخطأ
- تحديد الخطأ
- اختيار متعدد الإجابات
- إكمال الفراغات مع تطبيع عربي ودعم بدائل مقبولة
- مطابقة/توصيل
- ترتيب

تم تحديث:

```txt
teacher-exams.html
online-exams.html
assets/teacher-exams.js
assets/online-exams.js
assets/exams.css
```

في صفحة المعلم أضيف تبويب:

```txt
مولد النماذج
```

وهو يعمل محلياً بدون روابط خارجية، ويولّد:

- نص طلب احترافي لإنشاء نماذج أ، ب، ج...
- قالب CSV للنماذج والأسئلة
- ملف TXT للنص الجاهز

طريقة إدخال الأسئلة المتقدمة:

- الاختيارات: كل خيار في سطر، وضع `*` قبل الإجابة الصحيحة.
- متعدد الإجابات: يمكن وضع `*` قبل أكثر من خيار صحيح.
- المطابقة: كل سطر بصيغة `عنصر = مقابل`.
- الترتيب: كل عنصر في سطر بالترتيب الصحيح.
- الفراغات: الإجابة والبدائل مفصولة بـ `|` مثل: `المدرسة | المدرسةُ | المدرسه`.

---

## كشف نزاهة الاختبارات: تطابق الإجابات ومؤشرات النسخ/AI

أضيف ملف SQL:

```txt
sql/archive/38_exam_integrity_similarity_ai_flags.sql
```

ويضيف نظام كشف محلي بدون أي روابط خارجية:

- مقارنة إجابات الطلاب مع بعضهم داخل نفس السؤال والاختبار.
- مصادر مقارنة محلية يلصقها المعلم أو الإدارة، مثل نص من الإنترنت أو كتاب أو نموذج AI.
- مقارنة إجابات الطلاب مع المصادر الملصقة محلياً.
- مؤشرات احتمالية أن الإجابة مولدة بالذكاء الاصطناعي.
- احتساب سرعة إدخال/تسليم غير طبيعية.
- تسجيل محاولات النسخ/اللصق داخل الاختبار كتنبيه.

أضيفت صفحة جديدة:

```txt
exam-integrity.html
```

وتستخدم:

```txt
assets/exam-integrity.js
assets/exams.css
```

الدوال والجداول/views الجديدة:

```txt
exam_reference_sources
exam_norm_text
exam_answer_plain_text
exam_best_text_similarity
exam_ai_likelihood_score
exam_ai_likelihood_reasons
v_exam_integrity_answer_texts
v_exam_answer_similarity_pairs
v_exam_answer_source_matches
v_exam_integrity_answer_flags
```

ملاحظة مهمة:

- لا يوجد كشف AI مضمون 100%.
- النظام يعطي مؤشرات مراجعة فقط، ولا يجب اعتبارها حكماً نهائياً بدون مراجعة المعلم.
- كشف النسخ من الإنترنت يتم عبر لصق نص المصدر في صفحة "مصادر المقارنة"، لأن النظام لا يفتح روابط خارجية.

---

## إعادة تصميم أسئلة الترتيب والتوصيل + تطوير الواجبات ودرجات الواجب

أضيف ملف SQL:

```txt
sql/archive/39_homework_grades_attachments_notifications_audit.sql
```

ويضيف:

- تطوير جدول الواجبات بحقول: الشعبة، وقت التسليم، درجة كاملة، تاريخ نشر، حالة.
- مرفقات متعددة للواجب الواحد.
- جدول درجات واجبات مستقل `homework_grades`.
- منع قاعدة البيانات من إضافة/تعديل/حذف درجة واجب إلا إذا كان الواجب `published`.
- مزامنة درجة الواجب المنشور مع `continuous_assessments` كمكون `homework`.
- إشعارات داخلية للطلاب وأولياء الأمور عند نشر/تعديل/إغلاق واجب.
- Audit Log لجميع العمليات المهمة.
- Error Logs لتتبع أخطاء الحفظ.
- دوال آمنة:

```txt
save_homework_pro
add_homework_attachment
save_homework_grade
save_continuous_assessment_safe
notify_homework_recipients
log_school_audit
log_teacher_error
```

تم تحديث:

```txt
assets/teacher-dashboard.js
assets/teacher-dashboard.css
assets/teacher-exams.js
assets/online-exams.js
assets/exams.css
```

### أسئلة الترتيب

أصبحت واجهة المعلم تدعم طريقتين:

1. الترتيب المباشر: يكتب المعلم العناصر بالترتيب الصحيح.
2. تحديد أرقام الترتيب: يكتب المعلم العناصر ويحدد رقم ترتيب كل عنصر.

النظام يحفظ الترتيب الصحيح ويخلط العناصر تلقائياً للطالب.

### أسئلة التوصيل

أصبحت واجهة المعلم قائمة A و B:

- يدخل المعلم عنصر القائمة A.
- يدخل العنصر المطابق في القائمة B.
- لا حاجة لكتابة أكواد أو رموز.
- الطالب يرى القائمة A مرقمة 1،2،3 والقائمة B بالحروف A،B،C.
- التصحيح تلقائي.

### الواجبات

لوحة المعلم الآن تدعم:

- عنوان الواجب.
- الوصف.
- المادة.
- الصف والشعبة.
- تاريخ ووقت النشر.
- تاريخ ووقت التسليم.
- الدرجة الكاملة.
- حالة الواجب: مسودة، منشور، مغلق، مؤرشف.
- رفع عدة ملفات وصور.
- التقاط صورة من الهاتف.
- معاينة وحذف وإعادة ترتيب الملفات قبل الحفظ.
- حفظ تلقائي للمسودة.

### درجات الواجبات

في شاشة إدخال الدرجات يظهر خيار:

```txt
درجة واجب منشور
```

ولا تظهر إلا الواجبات المنشورة. المسودات والمغلقة لا تقبل درجات لا من الواجهة ولا من قاعدة البيانات.

---

## Hotfix: حفظ درجات الواجب + واجهة أسئلة Google Forms-like

أضيف ملف SQL:

```txt
sql/archive/40_homework_grade_save_hotfix_and_forms_ui.sql
```

ويصلح مشكلة بقاء واجهة درجة الواجب على:

```txt
جاري الحفظ التلقائي
```

أو ظهور:

```txt
فشل الحفظ
```

سبب المشكلة كان غالباً من دالة/Trigger حفظ درجات الواجب ومزامنة التقييم المستمر، خصوصاً عند استخدام `ON CONFLICT` مع unique index جزئي، أو قراءة `OLD/NEW` داخل Trigger بطريقة غير مناسبة لبعض العمليات.

الملف الجديد يستبدل:

```txt
enforce_published_homework_grade
save_homework_grade
```

ويضيف فحصاً سريعاً:

```txt
homework_grade_save_health_check()
```

كما تم تحسين الواجهة:

- ظهور سبب فشل الحفظ بجانب الطالب.
- مهلة اتصال تمنع بقاء الحالة معلقة.
- رسالة واضحة إذا لم يتم تشغيل SQL 40.

### واجهة الأسئلة

تم تحديث واجهة إنشاء الأسئلة لتصبح أقرب إلى Google Forms:

- الخيارات تظهر كسطور منفصلة مع radio/checkbox.
- اختيار الإجابة الصحيحة بنقرة واحدة.
- متعدد الإجابات يدعم أكثر من خيار صحيح.
- الترتيب والتوصيل بواجهات منفصلة بدون كتابة رموز.
- التوصيل يعرض للطالب قائمة A بالأرقام وقائمة B بالحروف.

---

## Hotfix نهائي: حفظ درجة الواجب بدون ON CONFLICT

أضيف ملف SQL:

```txt
sql/archive/41_homework_grade_no_on_conflict_fix.sql
```

سبب خطأ:

```txt
there is no unique or exclusion constraint matching the ON CONFLICT specification
```

أن جدول `homework_grades` كان موجوداً من قبل بدون constraint مناسب لـ:

```txt
ON CONFLICT(homework_id, student_id)
```

لذلك تم استبدال دالة:

```txt
save_homework_grade
```

بنسخة لا تستخدم `ON CONFLICT` نهائياً، بل تستخدم:

```txt
SELECT existing grade
UPDATE if exists
INSERT if not exists
```

كما يقوم الملف بمحاولة إنشاء unique index بعد تنظيف أي تكرارات قديمة، لكن الدالة الجديدة لا تعتمد عليه.

بعد تشغيل SQL 41 يجب أن يرجع الفحص:

```txt
save_function_contains_on_conflict: false
```

---

## واجبات الطالب ومركز الإشعارات

أضيف ملف SQL:

```txt
sql/archive/42_student_homeworks_notifications_ui.sql
```

ويضيف:

- RLS محسّن للواجبات والمرفقات والدرجات.
- عرض الواجبات المنشورة والمغلقة للطالب وولي الأمر فقط حسب الصف/الشعبة.
- View جديد:

```txt
v_student_homeworks
v_my_notifications
```

- دوال إشعارات:

```txt
mark_notification_read
mark_all_notifications_read
can_read_homework
can_write_homework
```

أضيفت صفحات جديدة:

```txt
student-homeworks.html
notifications.html
```

وملفات:

```txt
assets/student-homeworks.js
assets/notifications.js
```

### صفحة واجباتي

تعرض للطالب/ولي الأمر:

- الواجبات المنشورة.
- الواجبات المغلقة.
- المرفقات.
- تاريخ ووقت التسليم.
- درجة الواجب بعد التصحيح.
- ملاحظات المعلم.

### مركز الإشعارات

يعرض:

- واجب جديد.
- تعديل واجب.
- إغلاق واجب.
- إشعارات الاختبارات والتنبيهات العامة لاحقاً.

يدعم:

- تعليم إشعار كمقروء.
- تعليم كل الإشعارات كمقروءة.

تمت إضافة الروابط إلى:

```txt
student.html
teacher.html
staff.html
assets/core.js
```

---

## Hotfix الإشعارات 404

أضيف ملف SQL:

```txt
sql/archive/43_notifications_view_and_backfill_fix.sql
```

يحل خطأ:

```txt
/rest/v1/v_my_notifications 404
```

ويقوم بـ:

- إنشاء/إعادة إنشاء جدول `school_notifications` إذا لزم.
- إنشاء/إعادة إنشاء View:

```txt
v_my_notifications
```

- إنشاء دوال:

```txt
mark_notification_read
mark_all_notifications_read
notify_homework_recipients
backfill_homework_notifications
notifications_health_check
```

- توليد إشعارات للواجبات المنشورة السابقة تلقائياً.

بعد التشغيل يمكن الفحص بـ:

```sql
select public.notifications_health_check();
```

---

## Hotfix واجباتي 404

أضيف ملف SQL:

```txt
sql/archive/44_student_homeworks_view_fix.sql
```

يحل خطأ:

```txt
/rest/v1/v_student_homeworks 404
```

ويقوم بـ:

- إنشاء/إعادة إنشاء View:

```txt
v_student_homeworks
```

- إنشاء دالة بديلة:

```txt
get_student_homeworks_payload
```

- إنشاء فحص:

```txt
student_homeworks_health_check
```

- إعادة ضبط RLS للواجبات والمرفقات والدرجات بحيث يرى الطالب/ولي الأمر واجباته فقط.

بعد التشغيل يمكن الفحص بـ:

```sql
select public.student_homeworks_health_check();
```

---

## Hotfix نهائي لواجباتي: RPC مستقل عن View Cache

أضيف ملف SQL:

```txt
sql/archive/45_student_homeworks_rpc_health_fix.sql
```

هذا الملف يحل حالتين:

1. `v_student_homeworks` يرجع 404.
2. `student_homeworks_health_check()` غير موجودة.

الواجهة أصبحت تستخدم RPC أولاً:

```txt
get_student_homeworks_payload
```

ثم تستخدم الـ View كخطة بديلة. لذلك لا تعتمد صفحة واجباتي على ظهور الـ View فوراً في schema cache.

بعد تشغيل SQL 45 افحص:

```sql
select public.student_homeworks_health_check();
```

المهم:

```txt
rpc_exists = true
```

---

## Hotfix الجلسة: JWT failed verification

أضيف إعداد تخزين جلسة ثابت ومختلف في:

```txt
assets/config.js
```

```txt
authStorageKey: 'amin-ovcjzsrqqgjsbqswtkro-auth-v2'
```

وتم تحديث كل ملفات JS التي تنشئ Supabase client لاستخدام هذا المفتاح. الهدف منع استخدام جلسات قديمة محفوظة محلياً وموقعة بمفتاح/مشروع سابق.

أضيفت صفحة:

```txt
clear-session.html
```

عند ظهور:

```txt
JWT failed verification
JWT expired
```

افتح:

```txt
/clear-session.html
```

واضغط تصفير الجلسة ثم سجل الدخول من جديد.

---

## تشخيص واجباتي: هل الواجب يطابق الطالب؟

أضيف ملف SQL:

```txt
sql/archive/46_student_homeworks_visibility_diagnostics.sql
```

ويضيف:

```txt
student_homeworks_match_report
sync_students_from_active_enrollments
```

الاستخدام:

```sql
select public.student_homeworks_match_report();
```

يعرض لكل طالب:

- الصف.
- الشعبة.
- enrollment الفعال.
- عدد الواجبات المطابقة له.

إذا كانت بيانات الطالب في `students` لا تطابق `student_enrollments` يمكن المعاينة أولاً:

```sql
select public.sync_students_from_active_enrollments(false);
```

ثم التنفيذ إذا كان التقرير صحيحاً:

```sql
select public.sync_students_from_active_enrollments(true);
```

---

## تسليم الواجبات من الطالب ومراجعتها من المعلم

أضيف ملف SQL:

```txt
sql/archive/47_homework_submissions_student_teacher.sql
```

ويضيف:

- جدول تسليمات الواجب:

```txt
homework_submissions
homework_submission_attachments
```

- رفع مرفقات حل الطالب إلى bucket:

```txt
homework-submissions
```

- دوال:

```txt
save_homework_submission
add_homework_submission_attachment
review_homework_submission
homework_submissions_health_check
```

- تحديث `get_student_homeworks_payload` ليعرض حالة التسليم للطالب.
- View للمعلم:

```txt
v_teacher_homework_submissions
```

### الطالب/ولي الأمر

في صفحة:

```txt
student-homeworks.html
```

أصبح يستطيع:

- كتابة حل الواجب.
- حفظ مسودة.
- تسليم الواجب.
- رفع صور/ملفات كحل.
- رؤية حالة التسليم والدرجة بعد التصحيح.

### المعلم

في صفحة:

```txt
teacher.html → الواجبات
```

أصبح لكل واجب زر:

```txt
التسليمات
```

ويستطيع المعلم:

- رؤية تسليمات الطلاب.
- قراءة إجابة الطالب.
- رؤية عدد مرفقات الطالب.
- إدخال الدرجة والملاحظات.
- حفظ التصحيح وإشعار الطالب/ولي الأمر.

---

## تحسين مرفقات تسليم الواجب

أضيف ملف SQL:

```txt
sql/archive/48_homework_submission_attachments_access.sql
```

ويحسن صلاحيات عرض مرفقات تسليم الطالب ويضيف View اختيارية:

```txt
v_homework_submission_attachments_detailed
```

كما تم تحديث:

```txt
assets/student-homeworks.js
assets/teacher-dashboard.js
```

الآن:

- الطالب يرى الملفات التي رفعها مع تسليم الواجب بعد إعادة فتح الصفحة.
- المعلم يرى ملفات الطالب داخل صفحة "التسليمات".
- يمكن فتح مرفقات تسليم الطالب بروابط مؤقتة آمنة من bucket:

```txt
homework-submissions
```

---

## متابعة الواجبات والتذكير بغير المسلّمين

أضيف ملف SQL:

```txt
sql/archive/49_homework_followup_reports_reminders.sql
```

ويضيف:

```txt
v_homework_completion_report
v_homework_missing_students
send_homework_reminders
homework_followup_health_check
```

في صفحة المعلم:

```txt
teacher.html → الواجبات
```

أضيف زر:

```txt
المتابعة
```

يعرض:

- عدد الطلاب المطلوب منهم الواجب.
- عدد من سلّموا.
- عدد غير المسلّمين.
- متوسط درجات الواجب.
- قائمة الطلاب غير المسلّمين أو الذين لديهم مسودة فقط.

ويوجد زر:

```txt
إرسال تذكير
```

يرسل إشعاراً للطالب وولي الأمر، مع منع تكرار التذكير أكثر من مرة في نفس اليوم لنفس الواجب.

---

## صفحة تقارير الواجبات المركزية

أضيف ملف SQL:

```txt
sql/archive/50_homework_followup_payload_reports_page.sql
```

ويضيف RPC مباشر:

```txt
get_homework_followup_payload
```

حتى لا تعتمد التقارير على Views التي قد تعطي صفراً في SQL Editor بسبب `auth.uid() = null`.

أضيفت صفحة:

```txt
homework-reports.html
```

وملف:

```txt
assets/homework-reports.js
```

الصفحة تعرض للمعلم والإدارة:

- ملخص الواجبات.
- عدد المطلوب منهم.
- من سلّموا.
- من لم يسلّموا.
- متوسط الدرجات.
- تقرير الإنجاز.
- قائمة غير المسلّمين.
- إرسال تذكير لواجب واحد أو لكل المتأخرين.
- تصدير CSV.

تم إضافة الرابط إلى:

```txt
teacher.html
staff.html
assets/core.js
```

---

## دفعة تسريع 10 تحسينات: عمليات الواجبات ولوحات المتابعة

أضيف ملف SQL:

```txt
sql/archive/51_homework_batch_operations_dashboard.sql
```

ويضيف دفعة تحسينات:

1. عداد الإشعارات غير المقروءة:

```txt
get_notification_badges_payload
```

2. Payload موحد للوحة الواجبات:

```txt
get_homework_dashboard_payload
```

3. إرجاع تسليم الطالب للتعديل:

```txt
return_homework_submission
```

4. إغلاق واجب واحد مع إشعار:

```txt
close_homework
```

5. إعادة فتح واجب مغلق:

```txt
reopen_homework
```

6. إغلاق جماعي للواجبات المتأخرة مع وضع معاينة:

```txt
bulk_close_overdue_homeworks
```

7. فحص صحة الدفعة:

```txt
homework_batch_operations_health_check
```

8. تحديث صفحة تقارير الواجبات لتعرض:

- القريبة من الموعد.
- المتأخرة.
- آخر التسليمات.
- إغلاق المتأخرة.

9. تحديث صفحة المعلم لتدعم:

- إرجاع التسليم للطالب للتعديل.

10. تحديث مركز الإشعارات ليتعرف على:

- تذكير واجب.
- تسليم واجب.
- تصحيح واجب.
- إرجاع واجب.

---

## دفعة تسريع 2: إجراءات جماعية وسجل Audit

أضيف ملف SQL:

```txt
sql/archive/52_homework_fast_batch_actions_audit.sql
```

ويضيف دفعة جديدة:

1. تغيير حالة الواجب بشكل موحد:

```txt
set_homework_status
```

2. إغلاق/إعادة فتح الواجب:

```txt
close_homework
reopen_homework
```

3. تصفير غير المسلّمين لواجب واحد:

```txt
mark_missing_homework_zero
```

4. تصفير غير المسلّمين جماعياً للواجبات المتأخرة:

```txt
bulk_mark_missing_homeworks_zero
```

5. حذف سجل مرفق تسليم الطالب قبل التصحيح:

```txt
delete_homework_submission_attachment
```

6. Payload لسجل عمليات الواجبات:

```txt
get_homework_audit_payload
```

7. Health check:

```txt
homework_fast_batch_health_check
```

أضيفت صفحة:

```txt
homework-audit.html
```

وملف:

```txt
assets/homework-audit.js
```

كما تم تحديث:

```txt
teacher.html
staff.html
homework-reports.html
assets/teacher-dashboard.js
assets/homework-reports.js
assets/notifications.js
assets/core.js
```

الآن يمكن للمعلم والإدارة:

- إغلاق واجب من قائمة الواجبات.
- إعادة فتح واجب مغلق.
- معاينة تصفير غير المسلّمين.
- تنفيذ تصفير غير المسلّمين بدرجة 0.
- تصفير جماعي للواجبات المتأخرة من صفحة التقارير.
- إرجاع التسليم للتعديل.
- فتح سجل عمليات الواجبات والأخطاء.

---

## Mega Batch: مشاهدة الواجب والتعليقات وتذكير من لم يفتح

أضيف ملف SQL:

```txt
sql/archive/53_homework_engagement_comments_mega_batch.sql
```

ويضيف دفعة كبيرة:

1. جدول مشاهدة الواجب:

```txt
homework_views
```

2. جدول تعليقات التسليم:

```txt
homework_submission_comments
```

3. تعليم الواجب كمشاهد:

```txt
mark_homework_viewed
```

4. إضافة تعليق على التسليم:

```txt
add_homework_submission_comment
```

5. View للتعليقات:

```txt
v_homework_submission_comments_detailed
```

6. تذكير الطلاب الذين لم يفتحوا الواجب:

```txt
send_homework_not_viewed_reminders
```

7. Payload لتقرير فتح الواجب:

```txt
get_homework_engagement_payload
```

8. تحديث Payload الطالب ليشمل:

- viewed_at
- view_count
- comments_count

9. تحديث صفحة الطالب:

```txt
student-homeworks.html
```

أصبح الطالب يرى حالة "تمت المشاهدة"، ويستطيع التعليق على تسليم الواجب.

10. تحديث صفحة المعلم:

```txt
teacher.html
```

أصبح المعلم يرى عدد المشاهدات، ويستطيع تذكير من لم يفتح الواجب، والتعليق على تسليمات الطلاب.

11. تحديث صفحة التقارير:

```txt
homework-reports.html
```

أصبحت تعرض عدد من لم يفتحوا الواجب وتتيح إرسال تذكير لهم.

12. تحديث مركز الإشعارات لدعم:

- تعليق واجب.
- تذكير من لم يفتح الواجب.

---

## إنهاء وحدة الواجبات — العمليات النهائية

أضيف ملف SQL:

```txt
sql/archive/54_homework_final_operations.sql
```

ويضيف:

1. نسخ واجب كامل مع مرفقاته:

```txt
clone_homework_pro
```

2. حذف آمن للواجب:

```txt
delete_homework_safely
```

إذا لا توجد تسليمات/درجات يحذف، وإذا توجد بيانات طلاب يؤرشف بدل الحذف.

3. أرشفة الواجبات المغلقة القديمة:

```txt
archive_closed_homeworks
```

4. لوحة نهائية مختصرة:

```txt
get_homework_final_dashboard_payload
```

5. فحص نهائي لوحدة الواجبات:

```txt
homework_final_health_check
```

تم تحديث:

```txt
assets/teacher-dashboard.js
assets/homework-reports.js
```

الآن في لوحة المعلم:

- نسخ واجب.
- حذف/أرشفة واجب بأمان.

وفي تقارير الواجبات:

- معاينة الأرشفة.
- أرشفة المغلقة.
- عرض واجبات تحتاج إجراء.

---

## وحدة المكتبة المدرسية

أضيف ملف SQL:

```txt
sql/archive/55_library_management.sql
```

ويضيف وحدة مكتبة كاملة:

- فهرس الكتب:

```txt
library_items
```

- نسخ الكتب:

```txt
library_copies
```

- الإعارات:

```txt
library_loans
```

- الحجوزات:

```txt
library_reservations
```

- Views:

```txt
v_library_catalog
v_library_loans_detailed
v_library_reservations_detailed
```

- RPCs:

```txt
library_upsert_item
library_add_copy
library_checkout
library_return
library_reserve
library_cancel_reservation
get_library_dashboard_payload
library_health_check
```

أضيفت صفحة:

```txt
library.html
```

وملفات:

```txt
assets/library.js
assets/library.css
```

الميزات:

- إضافة كتاب مع عدد نسخ.
- إضافة نسخة إضافية.
- فهرس للطلاب والمعلمين.
- حجز كتاب.
- إعارة كتاب لطالب/معلم/موظف.
- إرجاع كتاب.
- متابعة المتأخرات.
- لوحة إحصاءات المكتبة.

فحص سريع:

```sql
select public.library_health_check();
```

---

## وحدة المخزون والمشتريات

أضيف ملف SQL:

```txt
sql/archive/56_inventory_procurement_and_library_seed.sql
```

ويضيف:

### للمكتبة

دالة كتب عينة:

```txt
library_seed_sample_books
```

وزر في صفحة المكتبة:

```txt
كتب عينة
```

### للمخزون والمشتريات

جداول:

```txt
suppliers
inventory_categories
inventory_locations
inventory_items
inventory_stock_movements
purchase_requests
purchase_request_items
```

Views:

```txt
v_inventory_stock
v_purchase_requests_detailed
v_inventory_movements_detailed
```

RPCs:

```txt
inventory_seed_defaults
inventory_upsert_item
inventory_adjust_stock
supplier_upsert
purchase_request_create
purchase_request_set_status
purchase_request_receive
get_inventory_dashboard_payload
inventory_health_check
```

أضيفت صفحة:

```txt
inventory.html
```

وملفات:

```txt
assets/inventory.js
assets/inventory.css
```

تدعم:

- إضافة أصناف.
- رصيد افتتاحي.
- إضافة/صرف مخزون.
- موردين.
- طلبات شراء.
- اعتماد/رفض طلب.
- استلام طلب وتحديث المخزون.
- تنبيهات النواقص.

فحص:

```sql
select public.inventory_health_check();
```

---

## وحدة الأصول الثابتة والعهد والصيانة

أضيف ملف SQL:

```txt
sql/archive/57_fixed_assets_custody_maintenance.sql
```

ويضيف:

جداول:

```txt
fixed_asset_categories
fixed_assets
asset_custody_records
asset_maintenance_tickets
```

Views:

```txt
v_fixed_assets_register
v_asset_custody_detailed
v_asset_maintenance_detailed
```

RPCs:

```txt
asset_seed_defaults
asset_upsert
asset_assign
asset_return
asset_maintenance_ticket_save
asset_maintenance_close
get_assets_dashboard_payload
assets_health_check
```

صفحة جديدة:

```txt
fixed-assets.html
```

وملفات:

```txt
assets/fixed-assets.js
assets/fixed-assets.css
```

الميزات:

- سجل أصول ثابتة.
- إهلاك وقيمة دفترية تقريبية.
- تسليم عهدة لمستخدم أو طالب أو جهة نصية.
- إرجاع عهدة.
- فتح طلب صيانة.
- إغلاق صيانة وتحديث حالة الأصل.
- لوحة إحصاءات للأصول.

فحص:

```sql
select public.assets_health_check();
```

---

## وحدة الموارد البشرية HR والرواتب

أضيف ملف SQL:

```txt
sql/archive/58_hr_employee_payroll.sql
```

ويضيف:

جداول:

```txt
hr_departments
hr_employee_profiles
hr_attendance
hr_leave_requests
hr_payroll_runs
hr_payroll_items
```

Views:

```txt
v_hr_employees
v_hr_leave_requests_detailed
v_hr_payroll_detailed
```

RPCs:

```txt
hr_seed_defaults
hr_upsert_employee
hr_record_attendance
hr_request_leave
hr_set_leave_status
hr_generate_payroll
hr_set_payroll_status
get_hr_dashboard_payload
hr_health_check
```

صفحة جديدة:

```txt
hr.html
```

وملفات:

```txt
assets/hr.js
assets/hr.css
```

الميزات:

- إضافة موظف.
- ربط الموظف بحساب مستخدم.
- أقسام وظيفية.
- حضور الموظفين.
- طلبات الإجازة واعتمادها.
- توليد رواتب شهرية.
- خصم الإجازات غير المدفوعة تلقائياً.

فحص:

```sql
select public.hr_health_check();
```

---

## إعادة تصميم UI/UX بالكامل — Amin Premium UI

تمت إضافة نظام تصميم جديد مستوحى من شعار مجمع أمين الرضا التعليمي المرفق.

ملفات جديدة:

```txt
assets/amin-logo.png
assets/amin-logo-small.png
assets/brand-redesign.css
assets/ux-enhancements.js
```

تم حقن التصميم الجديد في جميع صفحات HTML مع الحفاظ على كل الوظائف السابقة.

### الهوية البصرية

الألوان الأساسية:

```txt
#0A6EDC  Primary Blue
#0D47A1  Deep Royal Blue
#6A1B9A  Purple Accent
#D32F2F  Red Accent
#F57C00  Orange Accent
#D4AF37  Gold Accent
#F8FFFF  White Surface
#E9E520  Border Color
#00CFCC  Focus Ring
```

### التحسينات

- Logo-driven interface.
- Glassmorphism + neumorphism.
- تصميم SaaS حديث.
- Responsive grid.
- تحسين البطاقات والجداول والأزرار والنماذج.
- Ripple effect للأزرار.
- Breadcrumb ديناميكي.
- Focus states للوصولية.
- Mobile drawer backdrop.
- Lazy loading للصور.
- الحفاظ على كل APIs وSupabase routes والدوال الموجودة.

---

## إصلاح النقل المدرسي + الواجهة

أضيف ملف SQL:

```txt
sql/archive/60_transportation_policy_fix_and_ui.sql
```

هذا الملف يستبدل SQL 59 عند ظهور خطأ:

```txt
column reference "id" is ambiguous
```

ويعيد إنشاء سياسات RLS باستخدام دوال مساعدة بدون أعمدة مبهمة:

```txt
transport_user_can_read_student
transport_user_can_read_route
transport_user_can_read_trip
```

كما أضيفت صفحة:

```txt
transportation.html
```

وملفات:

```txt
assets/transportation.js
assets/transportation.css
```

الميزات:

- إدارة الحافلات.
- إدارة السائقين.
- إدارة المسارات والمواقف.
- تسجيل الطلاب في النقل.
- إنشاء رحلات يومية.
- تحضير الصعود والنزول.
- واجهة طالب/ولي أمر لعرض النقل المرتبط به.

فحص:

```sql
select public.transport_health_check();
```

---

## البوابة الموحدة والصلاحيات المفوضة

أضيف ملف SQL:

```txt
sql/archive/62_unified_portal_permissions.sql
```

ويضيف:

- جدول صلاحيات إضافية للمستخدمين:

```txt
user_extra_permissions
```

- دوال الصلاحيات:

```txt
portal_default_permissions
get_my_permissions
portal_has_permission
grant_user_permission
revoke_user_permission
get_my_portal_payload
unified_portal_health_check
```

- حماية الإشعارات بحيث يرى كل مستخدم إشعاراته فقط.
- إنشاء/إعادة إنشاء:

```txt
v_my_notifications
```

أضيفت صفحة موحدة:

```txt
portal.html
```

وملف:

```txt
assets/unified-portal.js
assets/unified-portal.css
```

تم تعديل تسجيل الدخول بحيث ينتقل كل المستخدمين إلى:

```txt
portal.html
```

ثم تظهر الواجهات حسب الصلاحيات فقط:

- المدير / المسؤول الأعلى.
- المسؤول المالي.
- المسؤول العلمي.
- المرشد النفسي.
- المسؤول الانضباطي.
- المعلم.
- الطالب.
- ولي الأمر.

يمكن للمدير منح صلاحية إضافية لاحقاً عبر:

```sql
select public.grant_user_permission('USER_ID','finance',null,'تفويض مؤقت');
```

وإلغاؤها عبر:

```sql
select public.revoke_user_permission('USER_ID','finance');
```

فحص:

```sql
select public.unified_portal_health_check();
```

---

## إلغاء الشريط الجانبي القديم والاعتماد على البوابة الموحدة

تم تحديث الواجهة بحيث:

- الدخول يذهب دائماً إلى `portal.html`.
- كل الصفحات القديمة تعمل بوضع Lite بدون الشريط الجانبي الأزرق الغامق.
- يتم إخفاء الـ sidebar تلقائياً واستبداله بشريط علوي خفيف عند فتح أي صفحة من النظام.
- تمت إزالة مجموعة "روابط النظام" من القوائم الديناميكية القديمة.
- أزرار الواجهات غير المصرح بها لا تظهر في البوابة الموحدة أصلاً.
- تم حذف روابط غير مناسبة من لوحة المعلم مثل المخزون والأصول لأنها ليست ضمن صلاحيات المعلم الافتراضية.

الملفات المحدثة:

```txt
assets/ux-enhancements.js
assets/brand-redesign.css
assets/unified-portal.js
assets/core.js
teacher.html
```

---

## Hotfix دالة إغلاق الواجبات المتأخرة + تفعيل المختبرات في البوابة

أضيف ملف SQL:

```txt
sql/archive/63_homework_missing_rpc_restore.sql
```

يحل خطأ:

```txt
Could not find the function public.bulk_close_overdue_homeworks(p_apply) in the schema cache
```

ويعيد إنشاء الدوال:

```txt
bulk_close_overdue_homeworks
bulk_mark_missing_homeworks_zero
mark_missing_homework_zero
close_homework
homework_rpc_restore_health_check
```

بعد التشغيل افحص:

```sql
select public.homework_rpc_restore_health_check();
```

كما تم تفعيل صفحة:

```txt
labs-activities.html
```

داخل البوابة الموحدة للمعلمين والإدارة والطلاب حسب الصلاحيات.

---

## إضافة مستلم الدفعة المالية

أضيف ملف SQL:

```txt
sql/archive/66_finance_payment_receiver.sql
```

ويضيف إلى جدول:

```txt
fee_payments
```

الأعمدة:

```txt
received_by
receiver_name
receiver_role
```

كما يضيف View:

```txt
v_fee_payments_detailed
```

وفحص:

```txt
finance_payment_receiver_health_check
```

تم تحديث:

```txt
assets/finance-pro.js
```

الآن شاشة تسجيل الدفعة تحتوي حقل:

```txt
المستلم الرسمي للمبلغ
```

يمكن اختيار:

- المسؤول المالي.
- المدير.
- أي مستخدم إداري/مالي.
- أو مستلم آخر يدوي.

ويظهر اسم المستلم في:

- جدول المدفوعات.
- الإيصال الرسمي.
- سجل التدقيق المالي.

---

## واجهة الوثائق والأرشفة

أضيفت ملفات الواجهة:

```txt
documents.html
assets/documents.js
assets/documents.css
```

وتعمل مع:

```txt
sql/archive/64_documents_archive_management.sql
sql/archive/65_documents_ui_security_helpers.sql
```

الميزات:

- رفع وثيقة.
- اختيار تصنيف.
- ربط الوثيقة بطالب.
- تحديد الظهور: خاص، الطالب/ولي الأمر، الموظفون، كل مستخدم مسجل.
- رفع عدة ملفات.
- تصوير من الهاتف.
- فتح الملفات عبر Signed URL.
- أرشفة/استعادة الوثيقة.
- تسجيل فتح/تحميل الوثيقة.

تم تفعيل بطاقة الوثائق في البوابة الموحدة:

```txt
portal.html
```

وأضيفت روابط إلى واجهات الإدارة والمعلم والطالب حسب الصلاحيات.

---

## Hotfix الوثائق: سياسة موجودة مسبقاً + تصنيفات افتراضية

أضيف ملف SQL:

```txt
sql/archive/67_documents_policy_idempotent_seed.sql
```

يحل خطأ:

```txt
policy "document_records_manage_update" already exists
```

ويقوم بـ:

- حذف سياسات الوثائق القديمة إن وجدت.
- إعادة إنشائها بشكل آمن.
- إنشاء التصنيفات الافتراضية تلقائياً.
- إعادة إنشاء Views الوثائق.
- فحص:

```sql
select public.documents_policy_seed_health_check();
```

بعد تشغيله يجب أن يصبح:

```txt
categories_count > 0
```

---

## واجهة إدارة التفويضات والصلاحيات

أضيف ملف SQL:

```txt
sql/archive/69_permissions_management_ui.sql
```

ويضيف:

```txt
portal_permissions_catalog
get_permissions_admin_payload
permissions_management_health_check
```

ويعيد تأكيد:

```txt
grant_user_permission
revoke_user_permission
get_my_permissions
```

أضيفت صفحة:

```txt
permissions-management.html
```

وملفات:

```txt
assets/permissions-management.js
assets/permissions-management.css
```

الصفحة للمدير فقط، وتتيح:

- عرض كل المستخدمين.
- رؤية صلاحيات الدور الأساسية.
- رؤية الصلاحيات الإضافية.
- منح صلاحية إضافية.
- تحديد تاريخ انتهاء اختياري.
- إلغاء التفويض الإضافي.
- عرض كتالوج الصلاحيات.

تم ربطها بالبوابة الموحدة للمستخدمين ذوي صلاحية:

```txt
users
```

فحص:

```sql
select public.permissions_management_health_check();
```

---

## صندوق اليومية حسب مستلم المبلغ

أضيف ملف SQL:

```txt
sql/archive/70_finance_cashbox_receiver_reports.sql
```

ويضيف:

- جدول إغلاقات الصندوق:

```txt
finance_cashbox_closures
```

- View يومية:

```txt
v_finance_cashbox_daily
v_fee_payments_detailed
```

- RPCs:

```txt
get_finance_cashbox_payload
close_finance_cashbox
finance_cashbox_health_check
```

أضيفت صفحة:

```txt
finance-cashbox.html
```

وملفات:

```txt
assets/finance-cashbox.js
assets/finance-cashbox.css
```

الميزات:

- تقرير التحصيل حسب المستلم.
- إجمالي USD/IRR.
- نقداً/بطاقة/حوالة.
- إغلاق صندوق كل مستلم.
- تسجيل الموجود الفعلي.
- احتساب فرق الصندوق.
- تصدير CSV.

تم ربط الصفحة في:

```txt
finance-pro.html
staff.html
portal.html
```

فحص:

```sql
select public.finance_cashbox_health_check();
```

---

## Hotfix صندوق اليومية: إعادة إنشاء Views

أضيف ملف SQL:

```txt
sql/archive/71_finance_cashbox_view_recreate_fix.sql
```

يحل خطأ:

```txt
cannot change name of view column "received_by_name" to "effective_receiver_name"
```

السبب أن View:

```txt
v_fee_payments_detailed
```

كانت موجودة بأعمدة قديمة، وPostgreSQL لا يسمح بتغيير أسماء أعمدة View عبر `create or replace view`.

الحل في SQL 71:

- حذف:

```txt
v_finance_cashbox_daily
v_fee_payments_detailed
```

- إعادة إنشائهما بالترتيب الصحيح.
- إعادة إنشاء:

```txt
get_finance_cashbox_payload
close_finance_cashbox
finance_cashbox_health_check
```

بعد التشغيل:

```sql
select public.finance_cashbox_health_check();
```

---

## دفعة مالية إضافية: تقارير المستلمين وإلغاء دفعة آمن

أضيف ملف SQL:

```txt
sql/archive/73_finance_receiver_analytics_voiding.sql
```

ويضيف:

- تقرير شهري حسب المستلم:

```txt
v_finance_receiver_monthly
```

- تقرير فترة حسب المستلم والطريقة:

```txt
get_finance_receiver_report
```

- تعديل مستلم دفعة قديمة:

```txt
update_payment_receiver
```

- إلغاء دفعة بأمان مع عكس الأرصدة:

```txt
void_fee_payment
```

- فحص:

```txt
finance_receiver_analytics_health_check
```

تم تحديث:

```txt
assets/finance-cashbox.js
assets/finance-cashbox.css
```

الآن في صفحة:

```txt
finance-cashbox.html
```

يوجد زر:

```txt
إلغاء
```

بجانب كل دفعة غير ملغاة. عند الإلغاء يتم:

- تعليم الدفعة كملغاة.
- حفظ سبب الإلغاء.
- عكس المبلغ من ملف الطالب المالي.
- عكس المبلغ من القسط إن كان مرتبطاً بقسط.
- تسجيل العملية في audit.

---

## Hotfix التقويم الذكي: جدول academic_years موجود ببنية قديمة

أضيف ملف SQL:

```txt
sql/archive/75_smart_calendar_existing_academic_years_fix.sql
```

يحل خطأ:

```txt
column "school_id" of relation "academic_years" does not exist
```

السبب أن جدول `academic_years` كان موجوداً مسبقاً، و`CREATE TABLE IF NOT EXISTS` لا يضيف الأعمدة الناقصة.

طريقة التشغيل:

1. شغّل:

```txt
sql/archive/75_smart_calendar_existing_academic_years_fix.sql
```

2. ثم أعد تشغيل:

```txt
sql/archive/74_smart_calendar_agenda_completed.sql
```

تم أيضاً تحديث SQL 74 نفسه ليعالج هذه الحالة مستقبلاً.

---

## Hotfix التقويم الذكي: إنشاء Health Check/Core Restore

أضيف ملف SQL:

```txt
sql/archive/78_smart_calendar_healthcheck_core_restore.sql
```

يحل حالة أن:

```txt
smart_calendar_health_check()
```

غير موجودة بعد تشغيل SQL 74، غالباً لأن SQL 74 توقف قبل آخر الملف.

هذا الملف ينشئ/يرمم أساسيات التقويم الذكي بشكل آمن:

- countries
- school_branches
- academic_years
- holiday_rules
- holidays
- exam_periods
- calendar_events
- completed_items
- get_calendar_day_details
- get_calendar_month
- get_my_agenda
- get_my_completed_items
- get_dashboard_home
- smart_calendar_health_check

بعد تشغيله:

```sql
select public.smart_calendar_health_check();
```

ملاحظة: هذا hotfix يشغل نسخة Core آمنة. بعد نجاحه يمكن تشغيل SQL 74 لاحقاً لتفعيل التحويلات الأدق للتقويم الشمسي/القمري.

---

## واجهة المركز المالي التنفيذي

أضيفت ملفات الواجهة:

```txt
finance-executive.html
assets/finance-executive.js
assets/finance-executive.css
```

وتعمل مع:

```txt
sql/archive/79_finance_executive_reports.sql
```

الواجهة تعرض:

- إجمالي الرسوم.
- إجمالي المدفوع.
- المتبقي.
- تحصيل الفترة.
- ملفات متأخرة.
- حسب الصف.
- حسب المستلم.
- حسب طريقة الدفع.
- المتأخرات.
- آخر المدفوعات.
- التحصيل اليومي.
- تصدير CSV.

تم ربطها في:

```txt
portal.html
finance-pro.html
staff.html
```

فحص:

```sql
select public.finance_executive_health_check();
```

---

## واجهة مركز التحصيل والمتابعة المالية

أضيفت ملفات الواجهة:

```txt
finance-collections.html
assets/finance-collections.js
assets/finance-collections.css
```

وتعمل مع:

```txt
sql/archive/80_finance_collections_followups.sql
```

تم ربط الصفحة في:

```txt
portal.html
finance-pro.html
staff.html
```

وتظهر في البوابة الموحدة لمن لديه صلاحية:

```txt
finance
```

الميزات:

- لوحة المتأخرات.
- تذكير جماعي وفردي.
- إضافة متابعة أو وعد دفع.
- كشف حساب طالب سريع.
- تصدير CSV.

---

## التثبيت النهائي وفحص الجاهزية

أضيف ملف SQL:

```txt
sql/archive/81_final_system_readiness_check.sql
```

ويضيف دالة:

```txt
final_system_readiness_check
```

تقوم بفحص:

- وجود الجداول الأساسية لكل وحدة.
- وجود الدوال المهمة.
- وجود Views المهمة.
- RLS والسياسات للجداول الحساسة.
- عدد السجلات الأساسية.
- حالة كل وحدة: ready / warning / missing.

أضيفت صفحة:

```txt
final-readiness.html
```

وملفات:

```txt
assets/final-readiness.js
assets/final-readiness.css
```

الصفحة تفحص أيضاً صفحات الواجهة HTML وتعرض:

- الملخص.
- الوحدات.
- الصفحات.
- RLS.
- JSON كامل قابل للنسخ والتنزيل.

تم ربطها بالبوابة الموحدة لصلاحية:

```txt
system
```

فحص SQL:

```sql
select public.final_system_readiness_check();
```

---

## RLS النهائي الآمن لجدول users

أضيف ملف SQL:

```txt
sql/archive/83_users_final_rls_enable_safe.sql
```

يقوم بـ:

- تفعيل RLS على جدول:

```txt
users
```

- السماح بالقراءة لكل مستخدم مسجل `authenticated` حفاظاً على عمل الصفحات الحالية التي تعتمد على أسماء المستخدمين والمعلمين وأولياء الأمور.
- حصر الإضافة والتعديل بالإدارة فقط.
- حصر الحذف بالمسؤول الأعلى فقط.
- إضافة View مستقبلية:

```txt
v_user_public_profiles
```

- إضافة فحص:

```txt
users_rls_final_health_check
```

بعد التشغيل:

```sql
select public.users_rls_final_health_check();
select public.final_system_readiness_check();
```

إذا حصلت مشكلة دخول أو صلاحيات، يوجد Rollback طارئ:

```txt
sql/archive/84_users_rls_rollback_disable.sql
```

ملاحظة: هذه خطوة آمنة وتوافقية. لاحقاً يمكن تضييق قراءة users تدريجياً بعد تحويل كل الصفحات إلى `v_user_public_profiles`.

---

## Hotfix مستقل: users_rls_final_health_check غير موجودة

أضيف ملف SQL:

```txt
sql/archive/85_users_rls_final_standalone_fix.sql
```

استخدميه إذا ظهر:

```txt
function public.users_rls_final_health_check() does not exist
```

هذا الملف مستقل ويقوم بـ:

- تأكيد وجود جدول users.
- إنشاء دوال:

```txt
current_user_is_admin
current_user_is_super_admin
```

- إنشاء View:

```txt
v_user_public_profiles
```

- تفعيل RLS على users.
- إنشاء سياسات القراءة والكتابة والحذف.
- إنشاء:

```txt
users_rls_final_health_check
```

بعد التشغيل:

```sql
select public.users_rls_final_health_check();
```

---

## Hotfix تذكيرات التحصيل المالي عندما يكون عدد الإشعارات 0

أضيف ملف SQL:

```txt
sql/archive/86_finance_overdue_reminders_diagnostics_fix.sql
```

يعالج حالة ظهور:

```txt
تم إرسال التذكيرات — عدد الإشعارات: 0
```

الأسباب الشائعة:

- تم إرسال التذكير مسبقاً اليوم لنفس ولي الأمر/الطالب.
- الطالب لا يملك `user_id` وولي الأمر غير مربوط `parent_id`.
- لا توجد متأخرات حسب الفلتر.

الدوال الجديدة:

```txt
preview_finance_overdue_reminders
send_finance_overdue_reminders_detailed
finance_overdue_reminders_health_check
```

وتم تحديث:

```txt
assets/finance-collections.js
```

الواجهة الآن تعرض تفاصيل:

- عدد الطلاب المطابقين.
- إشعارات ولي الأمر.
- إشعارات الطالب.
- المكرر اليوم.
- بدون مستلم.

وإذا كان سبب الصفر أنه سبق الإرسال اليوم، تعرض خيار إعادة الإرسال بالقوة.

فحص:

```sql
select public.finance_overdue_reminders_health_check();
```

---

## Hotfix فحص تذكيرات التحصيل داخل SQL Editor

أضيف ملف SQL:

```txt
sql/archive/87_finance_overdue_reminders_health_sql_editor_fix.sql
```

يعالج ظهور:

```json
"preview_all": null
```

في:

```sql
select public.finance_overdue_reminders_health_check();
```

السبب أن `auth.uid()` داخل SQL Editor يكون `null`، لذلك معاينة الصلاحيات المالية لا تعمل مثل الواجهة.

الملف يضيف:

```txt
finance_overdue_reminders_debug_summary
```

ويحدث:

```txt
finance_overdue_reminders_health_check
```

ليعرض:

- هل الفحص من SQL Editor.
- عدد الطلاب المتأخرين.
- من لديه ولي أمر.
- من لديه حساب طالب.
- من تم إرسال تذكير له اليوم مسبقاً.
- عينة من الطلاب المتأخرين.

بعد التشغيل:

```sql
select public.finance_overdue_reminders_health_check();
```

---

## عرض الرصيد الدائن في الواجهات المالية

أضيف ملف SQL:

```txt
sql/archive/94_finance_credit_balance_ui_support.sql
```

ويضيف دعم `credit_balance` في:

```txt
v_finance_exec_student_balances
v_finance_exec_class_summary
v_finance_collection_students
get_finance_executive_payload
```

كما تم تحديث الواجهات:

```txt
assets/finance-pro.js
assets/finance-executive.js
assets/finance-collections.js
```

الآن يظهر الرصيد الدائن في:

- كشف الطالب المالي.
- جدول الطلاب المالي.
- إيصال الدفع.
- المركز المالي التنفيذي.
- التحصيل والمتابعة.
- كشف حساب الطالب السريع.

فحص:

```sql
select public.finance_credit_ui_support_health_check();
```

---

## Hotfix فحص الرصيد الدائن داخل SQL Editor

أضيف ملف SQL:

```txt
sql/archive/95_finance_credit_health_sql_editor_fix.sql
```

إذا ظهر:

```json
"executive_payload_credit": null
```

فهذا طبيعي غالباً داخل SQL Editor لأن `auth.uid()` يساوي `null`، بينما `get_finance_executive_payload` يحتاج جلسة مسؤول مالي.

الملف الجديد يضيف في الفحص:

```txt
direct_total_credit_balance_sql_editor_safe
credit_summary
sql_editor_mode
```

بعد التشغيل:

```sql
select public.finance_credit_ui_support_health_check();
```

---

## صفحة تقرير الرصيد الدائن

أضيفت ملفات الواجهة:

```txt
finance-credit-report.html
assets/finance-credit-report.js
assets/finance-credit-report.css
```

وتعمل مع:

```txt
sql/archive/96_finance_credit_report.sql
```

الصفحة تعرض:

- إجمالي الرصيد الدائن.
- عدد الملفات الدائنة.
- عدد الطلاب.
- أعلى الأرصدة.
- الرصيد حسب الصف.
- تصدير CSV.
- فتح الطالب مباشرة في النظام المالي.

تم ربطها في:

```txt
portal.html
finance-pro.html
finance-executive.html
finance-collections.html
staff.html
```

---

## دعم اللغات الثلاث: العربية والإنجليزية والفارسية

أضيف نظام ترجمة محلي بدون CDN وبدون APIs خارجية:

```txt
assets/i18n.js
assets/i18n.css
```

اللغات المدعومة:

```txt
ar العربية
fa فارسی
en English
```

الميزات:

- زر اختيار لغة عائم في كل الصفحات.
- حفظ اللغة في `localStorage`.
- تغيير اتجاه الصفحة تلقائياً:
  - العربية والفارسية RTL.
  - الإنجليزية LTR.
- ترجمة النصوص الشائعة في الواجهات.
- ترجمة placeholders وaria-labels حيث أمكن.
- مراقبة المحتوى الديناميكي وترجمته بعد تحميله.
- لا يترجم بيانات المستخدمين أو الأسماء المخزنة في قاعدة البيانات إلا إذا كانت تطابق مفاتيح واجهة عامة.

تم حقن ملفات i18n في كل صفحات HTML.

اختبار محلي:

```bash
node tests/i18n.test.js
```

---

## تحسينات PWA + Dark Mode + Mobile UX

أضيفت دفعة تحسينات واجهة نهائية:

```txt
manifest.webmanifest
sw.js
offline.html
```

وتم تحديث:

```txt
assets/ux-enhancements.js
assets/brand-redesign.css
```

الميزات:

- Dark mode محلي بدون CDN.
- زر تبديل الوضع الداكن/الفاتح.
- PWA Manifest لتثبيت التطبيق على الهاتف.
- Service Worker للتخزين المحلي للواجهة فقط.
- لا يتم تخزين `/api` أو Supabase REST/Auth/Storage داخل Service Worker.
- صفحة Offline عند انقطاع الإنترنت.
- Bottom navigation خفيف للبوابة الموحدة على الجوال.
- تحسينات إضافية للوضع الليلي للبطاقات والجداول والنماذج.

تم حقن Manifest وApple touch icon في جميع صفحات HTML.

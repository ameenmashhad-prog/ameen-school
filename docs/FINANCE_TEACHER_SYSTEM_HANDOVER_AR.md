# تسليم نهائي — منظومة المالية + رواتب المعلمين + الانضباط + النمو المالي

تاريخ: 2026-07-06

## 1) ما الذي تم بناؤه فعلياً

### أ) داخل المالية
- تبسيط `finance-pro.html`
- تخفيف التبويبات المكررة
- تحسين عرض الدفعات والإيصال
- ربط سعر الصرف بمصادر إيرانية + TGJU
- إبقاء الإدخال اليدوي كخطة أمان
- إضافة:
  - `finance-growth-dashboard.html`
  - `finance-monthly-close.html`
  - `owner-executive-board.html`

### ب) داخل رواتب المعلمين
- ربط الاستحقاق بالحصة نفسها
- تحضير الدرس = 0.5 حصة
- تنزيل الواجب = 0.5 حصة
- إذا اجتمعا = 1.0 حصة كاملة
- إضافة كشف يومي وشهري وصافي بعد الحسميات

### ج) داخل الانضباط الزمني
- تسجيل دخول الحصة
- قياس التأخير بالدقائق
- قواعد خصم مرنة:
  - 5–9 دقائق: كل 5 مرات = حصة مخصومة
  - 10+ دقائق: كل 3 مرات = حصة مخصومة
- صفحة إدارية مستقلة لضبط القواعد ومراجعة الحسميات

### د) داخل واجهة المعلم
- إظهار “وضعي الراتبي هذا الشهر”
- إظهار حصص اليوم غير المكتملة راتبياً
- تنفيذ workflow سريع من نفس الحصة:
  - تسجيل الدخول
  - تحضير سريع
  - واجب سريع

---

## 2) الصفحات الجديدة

### مالية / إدارة / مالك
- `finance-growth-dashboard.html`
- `finance-monthly-close.html`
- `owner-executive-board.html`
- `teacher-payroll-finance.html`
- `teacher-punctuality-admin.html`

### معلم
- `teacher-session-checkin.html`

---

## 3) ملفات SQL الجديدة والمهمة

- `sql/archive/126_teacher_payroll_lesson_homework_session_model.sql`
- `sql/archive/127_teacher_lateness_alerts_and_penalties.sql`
- `sql/archive/128_teacher_payroll_view_recreate_hotfix.sql`
- `sql/archive/129_teacher_self_payroll_tracking_rpc.sql`
- `sql/archive/130_finance_growth_payload.sql`
- `sql/archive/131_finance_monthly_close_and_approval.sql`
- `sql/archive/132_finance_monthly_close_generated_column_hotfix.sql`

---

## 4) ترتيب تشغيل SQL الصحيح

### شغّل بهذا الترتيب حرفياً:
1. `126_teacher_payroll_lesson_homework_session_model.sql`
2. `127_teacher_lateness_alerts_and_penalties.sql`
3. `128_teacher_payroll_view_recreate_hotfix.sql`
4. `129_teacher_self_payroll_tracking_rpc.sql`
5. `130_finance_growth_payload.sql`
6. `132_finance_monthly_close_generated_column_hotfix.sql`
7. `131_finance_monthly_close_and_approval.sql`
8. `133_teacher_lateness_rules_deduplicate_hotfix.sql`
9. `134_finance_growth_collection_rate_hotfix.sql`
10. `135_teacher_homework_permission_hotfix.sql`
11. `137_teacher_payroll_evidence_hard_rebuild_hotfix.sql`

> ملاحظة مهمة:
> اسم الملف الصحيح هو:
> `132_finance_monthly_close_generated_column_hotfix.sql`
> وشغّله قبل 131.

---

## 5) لماذا يوجد 128 و 132؟

### 128
لحل مشكلة إعادة بناء View راتب المعلمين عندما تختلف أسماء الأعمدة القديمة والجديدة.

### 132
لحل مشكلة:
`generation expression is not immutable`
داخل الإقفال الشهري، عبر إزالة العمود المولد `month_key` من الجدول وحسابه داخل الـ View فقط.

---

## 6) كيف يستخدم كل دور النظام

### المعلم
يفتح:
- `teacher.html`
- `teacher-session-checkin.html`

ويستطيع:
- تسجيل الدخول للحصة
- معرفة التأخير
- معرفة ما ينقص الحصة راتبياً
- تحضير سريع
- واجب سريع
- معرفة وضعه الراتبي الشهري

### المعاون العلمي / الإدارة
يفتح:
- `teacher-punctuality-admin.html`

ويستطيع:
- مراجعة تأخيرات اليوم
- تعديل قواعد الحسم
- رؤية الحسميات الشهرية
- رؤية صافي الاستحقاق بعد الحسم

### المالية
تفتح:
- `teacher-payroll-finance.html`
- `finance-pro.html`
- `finance-growth-dashboard.html`
- `finance-monthly-close.html`

وتستطيع:
- مراجعة صافي الرواتب
- التصدير والطباعة
- متابعة النمو المالي
- حفظ الإقفال الشهري

### المالك
يفتح:
- `owner-executive-board.html`

ويرى:
- الصورة المالية العامة
- أثر رواتب المعلمين
- الحسميات
- المتأخرات
- التوقع القادم
- حالة الإقفال الشهري

---

## 7) اختبارات يدوية سريعة بعد تشغيل SQL

### اختبار 1 — المعلم
1. افتح `teacher-session-checkin.html`
2. تأكد أن حصص اليوم تظهر
3. نفّذ check-in لحصة
4. أضف تحضيراً سريعاً
5. أضف واجباً سريعاً
6. تأكد أن الحصة أصبحت “مكتملة راتبياً”

### اختبار 2 — التأخير
1. نفّذ check-in متأخر لحصة
2. افتح `teacher-punctuality-admin.html`
3. تأكد أن التأخير ظهر في “تأخيرات اليوم”
4. كرر حتى تتحقق قاعدة الحسم
5. تأكد أن “الحصص المخصومة” ظهرت

### اختبار 3 — الراتب المالي
1. افتح `teacher-payroll-finance.html`
2. اختر الشهر
3. تأكد أن:
   - إجمالي الوحدات
   - الوحدات المخصومة
   - الصافي
   - المبلغ النهائي
   كلها ظاهرة

### اختبار 4 — النمو المالي
1. افتح `finance-growth-dashboard.html`
2. تأكد من ظهور:
   - الدخل
   - التشغيل
   - رواتب المعلمين
   - التوقع
   - الاتجاه 6 أشهر

### اختبار 5 — الإقفال الشهري
1. افتح `finance-monthly-close.html`
2. اختر الشهر
3. احفظ كمسودة
4. ثم احفظ واعتمد
5. افتح `owner-executive-board.html`
6. تأكد أن حالة الإقفال ظهرت

---

## 8) إذا ظهر خطأ RPC not found / schema cache

إذا ظهر خطأ مثل:
- `Could not find the function ... in the schema cache`

### الحل
- انتظر قليلاً بعد تشغيل SQL
- أعد تشغيل الصفحة بـ `Ctrl + F5`
- إذا لزم، شغّل أي ملف hotfix المرتبط بالمشكلة
- وجود `notify pgrst, 'reload schema';` في آخر الملفات يساعد، لكن أحياناً يتأخر التحديث لحظات

---

## 9) ماذا بقي اختيارياً وليس أساسياً؟

هذه ليست مطلوبة للتشغيل الأساسي، لكنها تطويرات مستقبلية جيدة:
- إشعارات واتساب أو SMS للإدارة عند تأخير شديد
- ربط تحضير الحضور كوزن راتبي اختياري
- ربط إدخال الدرجات كدليل نشاط إضافي
- ميزانية سنوية Budget مقارنة Actual
- تقارير PDF مصممة خصيصاً للمالك

---

## 10) أهم نقطة تشغيلية

هذا النظام الآن صار يعتمد على مبدأ واضح:

### الراتب ليس فقط من الجدول
بل من:
- الحصة
- تسجيل الدخول
- تحضير الدرس
- الواجب
- التأخير
- الحسميات

وهذا يعطي:
- عدالة أكبر
- وضوحًا ماليًا
- قابلية تدقيق
- وسهولة شرح للمعلم والمالك معاً

# اعتماد التقويم الشمسي + العملتين في الصفحات المالية

## ما تم تنفيذه

### 1) الشهر الشمسي كأساس
تم تحويل الصفحات المالية الأساسية لتتعامل مع **الشهر الشمسي** كأساس للعرض والمتابعة:
- `finance-growth-dashboard.html`
- `finance-monthly-close.html`
- `owner-executive-board.html`
- `teacher-payroll-finance.html`
- `finance-pro.html` (تحسين الجدولة والعرض)

مع إظهار **النطاق الميلادي التابع** دائمًا للمراجعة.

### 2) سعر صرف نشط + عرض الدولار/الريال معًا
تم توحيد عرض المبالغ على الصفحات التشغيلية التالية بحيث يظهر:
- الدولار USD
- الريال الإيراني IRR
- مع سعر صرف مرجعي محفوظ/نشط

وشمل ذلك:
- `finance-pro`
- `finance-growth-dashboard`
- `finance-monthly-close`
- `owner-executive-board`
- `teacher-payroll-finance`
- `finance-executive`
- `finance-cashbox`
- `finance-collections`

### 3) تحسين جدولة الأقساط
في `finance-pro.js` تم تعديل بناء الأقساط ليعتمد **التسلسل الشهري الشمسي** بدل التوزيع الخطي الميلادي فقط، مع إبقاء التخزين النهائي على شكل تواريخ ميلادية متوافقة.

## الملفات الجديدة المهمة
- `assets/finance-runtime.js`
- `sql/archive/139_finance_solar_month_foundation.sql`

## أمر التنفيذ المهم في قاعدة البيانات
شغّل هذا الملف في Supabase SQL Editor:

- `sql/archive/139_finance_solar_month_foundation.sql`

هذا الملف يفعّل:
- دوال الشهر الشمسي المالي
- Payload النمو المالي الشمسي
- الإقفال الشهري الشمسي
- ربط الرواتب/التحليل المالي بالشهر الشمسي

## ملاحظة مهمة
الواجهات صارت جاهزة للعرض الشمسي والعملة المزدوجة، لكن **الاعتماد الخلفي الكامل** للوحات النمو والإقفال يتطلب تنفيذ ملف SQL رقم 139.

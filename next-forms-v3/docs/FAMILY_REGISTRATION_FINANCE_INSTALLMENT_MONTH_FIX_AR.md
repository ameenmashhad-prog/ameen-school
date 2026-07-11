# إصلاح ربط الأقساط عند تفعيل الأسرة

## المشكلة
بعد نجاح submit وربط الرسوم، فشل التفعيل مع الخطأ:
```text
null value in column "installment_month" of relation "student_installments" violates not-null constraint
```

## السبب
بعض البيئات القديمة ما زالت تعتبر العمود:
- `student_installments.installment_month`

إلزاميًا.

بينما دالة:
- `registration_sync_finance_after_family_activation`

كانت تُدخل الأقساط الجديدة مع `installment_month = null`.

## الحل
شغّل هذا الملف:
- `sql/archive/162_fix_family_activation_installment_month.sql`

## ماذا يفعل؟
يعيد تعريف:
- `registration_sync_finance_after_family_activation`

بحيث يحدد `installment_month` بهذه الأولوية:
1. من `due_date` إذا كان شهرًا أكاديميًا صالحًا
2. وإلا من `finance_plan_start_date`
3. وإلا يستخدم `9` كقيمة آمنة

## بعد تشغيله
أكمل أنا التحقق النهائي من:
- submit
- activation
- `student_fees`
- `finance_payment_plans`
- `student_installments`

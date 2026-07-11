# إصلاح حالة الأقساط عند التفعيل المالي للأسرة

## المشكلة
بعد إصلاح `installment_month` ظهرت مشكلة جديدة أثناء التفعيل:
```text
new row for relation "student_installments" violates check constraint "student_installments_status_check"
```

## السبب
بعض البيئات القديمة لا تقبل الحالة:
- `pending`

داخل `student_installments.status`

وتتوقع الحالة المالية التقليدية:
- `unpaid`
- `partial`
- `paid`

## الحل
شغّل هذا الملف:
- `sql/archive/163_fix_family_activation_installment_status.sql`

## ماذا يفعل؟
يعيد تعريف:
- `registration_sync_finance_after_family_activation`

بحيث ينشئ الأقساط الجديدة بالحالة:
- `unpaid`

بدل:
- `pending`

## بعد تشغيله
أكمل أنا فحص النهاية للنهاية حتى أتأكد أن:
- activation تنجح
- student_fees تتولد
- finance_payment_plans تتولد
- student_installments تتولد

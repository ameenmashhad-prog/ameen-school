# المكافآت والحصص الإضافية — شرح مختصر

## الهدف
إضافة منطقة واضحة للمكافآت مع ذكر السبب، وإضافة حصص إضافية مثل:
- حلول المعلم مكان معلم غائب
- دوام أيام العطلات
- حصص إلكترونية
- دعم إضافي
- مراقبة / إشراف
- أخرى

## ماذا أُضيف؟
### SQL
- `sql/archive/138_teacher_payroll_bonuses_and_extra_sessions.sql`

### الجداول
- `teacher_extra_sessions`
- `teacher_payroll_adjustments`

### Views
- `v_teacher_extra_sessions_detailed`
- `v_teacher_extra_sessions_monthly`
- `v_teacher_payroll_adjustments_monthly`
- تحديث `v_teacher_payroll_preview`

## منطق الحساب
### الحصة الإضافية
- تُسجل بعدد وحدات `session_units`
- تُحتسب بسعر الحصة المعتاد
- ويمكن للإدارة وضع سعر خاص `rate_override`

### المكافأة / الخصم
- مبلغ مباشر بالدولار
- سبب إلزامي
- يدخل في صافي الراتب الشهري النهائي

## أين تظهر؟
في صفحة:
- `teacher-payroll-finance.html`

### ستجد:
- نموذج إضافة حصة إضافية
- نموذج إضافة مكافأة / خصم
- جدول الحصص الإضافية
- جدول المكافآت والخصومات
- تحديث الصافي النهائي تلقائياً

## ملاحظة
إذا لم تظهر هذه المنطقة، شغّل:
- `sql/archive/138_teacher_payroll_bonuses_and_extra_sessions.sql`
ثم اعمل:
- `Ctrl + F5`

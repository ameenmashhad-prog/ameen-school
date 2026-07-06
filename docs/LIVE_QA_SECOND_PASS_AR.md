# الفحص الحي — الجولة الثانية

تاريخ: 2026-07-06
الرابط: `https://ameen-school-h6cj.vercel.app`
الحساب: `ameenmashhad@ameen.iq`

## ما الذي تأكد بعد تشغيل 133 + 134؟

### 1) قواعد التأخير
- أصبحت قاعدتين فقط.
- التكرار اختفى.
- `rules_count = 2`

### 2) معدل التحصيل
- `collectionRate` لم يعد يعطي نسباً مضللة مثل 7081%.
- الآن يعتمد على ما تم تسديده فعلياً من أقساط نفس الشهر مع سقف 100%.

### 3) دوال المعلم والنمو المالي
- `get_my_teacher_payroll_tracking()` تعمل.
- `get_finance_growth_payload()` تعمل.
- `close_finance_month()` تعمل.

## المشكلة الجديدة التي ظهرت
### View دليل راتب الحصة ما زال يحمل منطقاً أقدم في بعض السجلات
من الفحص ظهر أن بعض السطور في:
- `v_teacher_session_payroll_evidence`
- `v_teacher_payroll_daily`

تعرض:
- `prepared_sessions = 0`
- `homework_sessions = 0`
- لكن `earned_session_units > 0`

وهذا غير متوافق مع المنطق المطلوب (0.5 تحضير + 0.5 واجب).

## الاستنتاج
يبدو أن البيئة الحالية تحتاج **إعادة إسقاط وإعادة بناء** الـ Views الخاصة بالراتب اليومي/الشهري بشكل صريح.

## الحل المقترح
شغّل:
- `sql/archive/136_teacher_payroll_evidence_rebuild_hotfix.sql`

## مشكلة ثانية تم تأمينها احتياطياً
لوحظ أن دالة:
- `create_session_homework()`

كانت تحتاج تشديد صلاحيات حتى لا يستطيع أي مستخدم إنشاء واجب لحصة ليست له.

### الحل
شغّل أيضاً:
- `sql/archive/135_teacher_homework_permission_hotfix.sql`

## ترتيب التشغيل الموصى به بعد هذا الفحص
1. `135_teacher_homework_permission_hotfix.sql`
2. `136_teacher_payroll_evidence_rebuild_hotfix.sql`

ثم:
- `Ctrl + F5`
- إعادة اختبار:
  - `teacher-session-checkin.html`
  - `teacher-punctuality-admin.html`
  - `teacher-payroll-finance.html`

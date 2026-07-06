# الفحص الحي — الجولة الثالثة

تاريخ: 2026-07-06
الرابط: `https://ameen-school-h6cj.vercel.app`
الحساب: `ameenmashhad@ameen.iq`

## ما الذي تم التحقق منه بعد 135 + 136؟

### 1) قواعد التأخير
- سليمة
- قاعدتان فقط
- لا يوجد تكرار

### 2) collectionRate
- أصبح منطقياً
- لم تعد تظهر قيم مبالغ فيها مثل 7081%

### 3) نقطة جديدة ظهرت
رغم تشغيل 136، ما زالت بعض البيانات في:
- `v_teacher_session_payroll_evidence`
- `v_teacher_payroll_daily`
- `v_teacher_payroll_preview`

تعطي سلوكاً غير صحيح مثل:
- `has_lesson_plan = 0`
- `has_homework = 0`
- لكن `payroll_units = 1.00`

## الاستنتاج
إعادة البناء السابقة لم تكن كافية في هذه البيئة.
يبدو أن هناك طبقة/تعريف قديم ما زال يترك أثراً على الـ Views.

## الحل الأقوى
شغّل:
- `sql/archive/137_teacher_payroll_evidence_hard_rebuild_hotfix.sql`

### هذا الملف:
- يسقط الـ Views بالكامل
- يعيد بناءها من الجداول الفعلية مباشرة
- لا يعتمد على أي منطق قديم باقٍ
- يحسب:
  - تحضير = 0.5
  - واجب = 0.5
  - كلاهما = 1.0
  - لا شيء = 0.0

## الترتيب الآن
إذا كنت شغّلت 135 و136 بالفعل، فالخطوة التالية الوحيدة المطلوبة هي:
1. `sql/archive/137_teacher_payroll_evidence_hard_rebuild_hotfix.sql`

ثم:
- `Ctrl + F5`
- إعادة اختبار:
  - `teacher-session-checkin.html`
  - `teacher-punctuality-admin.html`
  - `teacher-payroll-finance.html`

## ملاحظة
هذا الهوتفكس أقوى من 136 لأنه يتجاوز أي View قديم أو منطق متبقٍ ويعيد البناء من الصفر على الجداول الفعلية.

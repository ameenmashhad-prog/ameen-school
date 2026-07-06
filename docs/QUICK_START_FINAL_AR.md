# تشغيل سريع نهائي — المالية ورواتب المعلمين

## 1) شغّل ملفات SQL بهذا الترتيب
1. `sql/archive/126_teacher_payroll_lesson_homework_session_model.sql`
2. `sql/archive/127_teacher_lateness_alerts_and_penalties.sql`
3. `sql/archive/128_teacher_payroll_view_recreate_hotfix.sql`
4. `sql/archive/129_teacher_self_payroll_tracking_rpc.sql`
5. `sql/archive/130_finance_growth_payload.sql`
6. `sql/archive/132_finance_monthly_close_generated_column_hotfix.sql`
7. `sql/archive/131_finance_monthly_close_and_approval.sql`
8. `sql/archive/133_teacher_lateness_rules_deduplicate_hotfix.sql`
9. `sql/archive/134_finance_growth_collection_rate_hotfix.sql`
10. `sql/archive/135_teacher_homework_permission_hotfix.sql`
11. `sql/archive/137_teacher_payroll_evidence_hard_rebuild_hotfix.sql`
12. `sql/archive/138_teacher_payroll_bonuses_and_extra_sessions.sql`

## 2) الصفحات الأساسية
### للمعلم
- `teacher.html`
- `teacher-session-checkin.html`

### للإدارة/المعاون العلمي
- `teacher-punctuality-admin.html`

### للمالية
- `finance-pro.html`
- `teacher-payroll-finance.html`
- `finance-growth-dashboard.html`
- `finance-monthly-close.html`

### للمالك / الإدارة العليا
- `owner-executive-board.html`

## 3) اختبار سريع بعد SQL
- افتح `teacher-session-checkin.html` وسجل دخول حصة.
- أضف تحضيراً سريعاً ثم واجباً سريعاً.
- افتح `teacher-punctuality-admin.html` وتأكد من ظهور التأخير/الحسم.
- افتح `teacher-payroll-finance.html` وتأكد من الصافي النهائي.
- افتح `finance-growth-dashboard.html` وتأكد من ظهور النمو المالي.
- افتح `finance-monthly-close.html` وجرب حفظ شهر كمسودة ثم اعتماد.
- افتح `owner-executive-board.html` وتأكد من ظهور حالة الإقفال.

## 4) إذا ظهر خطأ cache / RPC not found
- انتظر قليلًا بعد تشغيل SQL.
- اعمل `Ctrl + F5`.
- إذا المشكلة تخص View راتب المعلمين، أعد تشغيل `128`.
- إذا المشكلة تخص الإقفال الشهري، شغّل `132` ثم `131`.

## 5) الهدف النهائي للنظام
- راتب المعلم محسوب بحسب الحصة.
- التحضير + الواجب = استحقاق فعلي.
- التأخير يولد حسميات مرنة.
- المالية ترى الصافي النهائي.
- المالك يرى الأثر على نمو المؤسسة بالدولار والريال.

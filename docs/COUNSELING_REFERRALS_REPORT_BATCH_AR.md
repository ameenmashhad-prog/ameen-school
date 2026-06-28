# دفعة الإحالات وطلب الموعد والتقرير المجهول

تم تنفيذ دفعة سريعة وفعالة لربط برنامج تطوير المهارات والمتابعة التربوية مع الطالب والمعلم والإدارة.

## الملفات المضافة

- `sql/104_counseling_referrals_requests_reports.sql`
- `counseling-report.html`
- `assets/counseling-report.js`
- `assets/counseling-report.css`

## الملفات المعدلة

- `assets/teacher-dashboard.js`
- `assets/core.js`
- `assets/platform-modules.js`
- `assets/i18n.js`
- `sw.js`

## المزايا

### 1) إحالة من لوحة المعلم

في تبويب طلابي داخل لوحة المعلم، تمت إضافة زر:

```txt
إحالة للبرنامج
```

يرسل إحالة إلى المرشد ضمن:

```txt
برنامج تطوير المهارات والمتابعة التربوية
```

دون كشف أي تفاصيل نفسية للمعلم.

### 2) طلب موعد من الطالب/ولي الأمر

في لوحة الطالب تمت إضافة زر:

```txt
أريد موعداً
```

يرسل طلباً للمرشد بصياغة محايدة.

### 3) إشعار المرشدين

عند إرسال إحالة أو طلب موعد، يتم إنشاء إشعار للمرشدين/الأخصائيين/المسؤول الأعلى.

### 4) تقرير إداري مجهول

تمت إضافة صفحة:

```txt
counseling-report.html
```

وتظهر في البوابة لمن يملك صلاحية:

```txt
counseling.report
```

التقرير لا يحتوي أسماء أو ملاحظات جلسات أو معرفات طلاب.

## SQL المطلوب تشغيله

```txt
sql/104_counseling_referrals_requests_reports.sql
```

ثم افحص:

```sql
select public.counseling_referrals_requests_health_check();
```

المتوقع:

```json
{
  "ok": true,
  "teacher_referral_rpc": true,
  "student_request_rpc": true,
  "aggregate_report_rpc": true
}
```

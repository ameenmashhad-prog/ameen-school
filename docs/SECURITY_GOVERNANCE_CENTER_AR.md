# مركز حوكمة الأمن والاختبارات

تمت إضافة مركز حوكمة أمن مركزي لمراقبة أهم التصحيحات التي نفذت في الدفعات السابقة.

## الملفات المضافة

- `security-governance.html`
- `assets/security-governance.js`
- `assets/security-governance.css`
- `sql/archive/105_security_governance_health_check.sql`
- `tests/security-governance.test.js`

## ما يفحصه المركز

1. كلمات المرور الضعيفة المتبقية في جداول التسجيل.
2. تحقق قيود كلمات المرور المؤقتة.
3. RLS على الجداول الأساسية.
4. RLS على جداول الإرشاد النفسي.
5. وجود دوال الحماية الأساسية.
6. اتساع صلاحية `current_user_can_counseling`.
7. وجود التقرير الإداري المجهول.
8. وجود طلب موعد الطالب وإحالة المعلم.

## SQL المطلوب تشغيله

```txt
sql/archive/105_security_governance_health_check.sql
```

ثم افحص:

```sql
select public.security_governance_health_check();
```

## الصفحة

بعد رفع الحزمة افتح:

```txt
security-governance.html
```

أو من البوابة الموحدة:

```txt
حوكمة الأمن
```

## اختبار محلي

```txt
node tests/security-governance.test.js
```


## تحديث مصفوفة الأدوار

أضيف فحص جديد:

```txt
sql/archive/106_role_access_matrix_check.sql
```

ويتحقق من:

- الطالب لا يملك صلاحيات إدارة/مالية عامة/إرشاد.
- المعلم لا يملك صلاحيات مالية أو إرشاد نفسي.
- الإدارة لا تملك تفاصيل الإرشاد افتراضياً، فقط تقرير مجهول.
- الأكاديمي يملك التقرير المجهول فقط وليس التفاصيل.
- المرشد يملك `counseling` و `counseling.full`.
- الطالب والمعلم والمرشد يملكون التقويم والشارات.

الفحص:

```sql
select public.security_role_access_matrix_check();
```

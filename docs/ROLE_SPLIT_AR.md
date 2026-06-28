# تقسيم واجهات الإدارة حسب الدور

تم تعديل النسخة النظيفة بحيث لا يرى كل موظف إداري نفس التبويبات.

## الأدوار المدعومة

| الدور في جدول `users.role` | الواجهة | ما يظهر له |
|---|---|---|
| `admin` أو `is_super_admin=true` | `super-admin.html` | كل شيء |
| `finance` | `staff.html` | المالية والتقارير المالية فقط |
| `discipline` | `staff.html` | الحضور، الغياب، السلوك، الطلاب، التقارير بدون مالية |
| `counselor` أو `psychologist` | `staff.html` | الإرشاد والمتابعة والسلوك والحضور بدون مالية |
| `academic` | `staff.html` | المسؤول العلمي: الطلاب، الحضور، الغياب، السلوك، الدرجات، الإعفاءات بدون مالية |
| `teacher` | `teacher.html` | واجهة المعلم |
| `student` أو `parent` | `student.html` | واجهة الطالب/ولي الأمر |

## الدور المقترح للمسؤول العلمي

استخدمي:

```txt
academic
```

مثال:

```sql
update public.users
set role = 'academic'
where email = 'email@example.com';
```

إذا رفض Supabase القيمة بسبب CHECK constraint على `users.role`، شغّلي هذا الاستعلام وأرسلي النتيجة:

```sql
select conname, pg_get_constraintdef(oid) as constraint_def
from pg_constraint
where conrelid = 'public.users'::regclass
  and pg_get_constraintdef(oid) ilike '%role%';
```

ثم نعدّل القيد بأمان حسب اسمه الحقيقي.

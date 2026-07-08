# إصلاح تفعيل الأسرة عند وجود `public.students.name` كحقل إلزامي

تاريخ الإضافة: 2026-07-09

## المشكلة المكتشفة
في QA الحي لمسار التسجيلات ظهر خطأ عند تفعيل الأسرة:

```text
null value in column "name" of relation "students" violates not-null constraint
```

السبب أن منطق التفعيل كان يدرج في جدول:
- `public.students`

باستخدام الحقل:
- `student_name`

فقط، بينما البيئة الحية تتطلب أيضاً تعبئة الحقل:
- `name`

---

## الحل
تم إعداد الملف:
- `sql/archive/143_fix_registration_family_activation_students_name.sql`

ويقوم بـ:
- إعادة تعريف `activate_registered_user_rpc`
- تمرير حالات `teacher` ونحوها إلى الدالة الأصلية
- معالجة `family` داخلياً
- تعبئة `name` و `student_name` معاً عند إنشاء الطالب في `public.students`

---

## ما الذي يجب تشغيله؟
شغّل هذا الملف على Supabase:
```sql
sql/archive/143_fix_registration_family_activation_students_name.sql
```

---

## تحديث الواجهة
تم أيضاً تحديث:
- `registrations-admin.html`

بحيث إذا ظهر نفس الخطأ في بيئة لم يُطبّق فيها SQL 143 بعد، تظهر رسالة واضحة تطلب تشغيل الملف المناسب بدلاً من رسالة قاعدة بيانات عامة.

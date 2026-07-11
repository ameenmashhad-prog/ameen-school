# إصلاح خطأ `ON CONFLICT` في `forms_submit_family_registration_v3`

## المشكلة
بعد تفعيل bridge المالي ظهر خطأ عند submit:
```text
there is no unique or exclusion constraint matching the ON CONFLICT specification
```

## السبب
الدالة `forms_submit_family_registration_v3` كانت تعتمد على:
```sql
on conflict (forms_v3_submission_ref)
```
لكن بعض البيئات لا تحتوي unique index / constraint مطابق بالشكل المطلوب.

## الحل الأسلم الآن
بدل مطاردة الـ constraint، شغّل هذا الملف:
- `sql/archive/159_family_registration_submit_no_conflict_dependency.sql`

## ماذا يفعل 159؟
- لا يعتمد على `ON CONFLICT` أصلًا
- إذا وجد family بنفس `forms_v3_submission_ref` يقوم بعمل `update`
- إذا لم يجد، يقوم بعمل `insert`
- ثم يُعيد إدراج `registration_students` التابعة للحالة الحالية

## النتيجة
بعد 159 يصبح submit العائلي مستقراً حتى لو كانت البيئة القديمة مختلفة في الـ indexes والقيود.

# إصلاح غموض RPC تفعيل الحسابات

تاريخ الإضافة: 2026-07-09

## المشكلة المكتشفة
أثناء QA الحي ظهر أن استدعاء:
- `activate_registered_user`

قد يفشل عبر PostgREST بالخطأ:
- `PGRST203`
- `Could not choose the best candidate function`

السبب هو وجود دالتين بنفس الاسم:
- `public.activate_registered_user(text, uuid)`
- `public.activate_registered_user(uuid, text)`

وهذا قد يجعل استدعاء RPC بالوسائط المسماة غامضاً.

---

## الحل
تم إعداد ملف:
- `sql/archive/142_fix_activate_registered_user_rpc_ambiguity.sql`

ويضيف دالة RPC فريدة غير محمّلة:
- `public.activate_registered_user_rpc(text, uuid)`

بحيث تستخدمها الواجهة الإدارية بدلاً من الاسم الملتبس.

---

## ما الذي يجب تشغيله؟
شغّل على Supabase:
```sql
-- ملف 142 كامل
sql/archive/142_fix_activate_registered_user_rpc_ambiguity.sql
```

---

## ملاحظة
تم أيضاً تحديث الواجهة `registrations-admin.html` لتستخدم:
- `activate_registered_user_rpc`

وتعرض رسالة واضحة تطلب تشغيل SQL 142 إذا لم تكن الدالة الجديدة موجودة بعد.

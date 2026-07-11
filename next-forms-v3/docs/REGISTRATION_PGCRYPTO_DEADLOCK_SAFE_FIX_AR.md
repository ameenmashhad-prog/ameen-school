# حل مشكلة الـ deadlock عند إصلاح trigger التشفير

## المشكلة
عند تشغيل ملف إصلاح الـ trigger ظهر:
```text
deadlock detected
```

والسبب كان عند أوامر مثل:
- `drop trigger ... on public.registration_families`

## لماذا حدث هذا؟
لأن حذف/إعادة إنشاء trigger يحتاج lock قوي على الجدول، وفي نفس الوقت كانت هناك قراءة/استخدام من جلسة أخرى، فحدث deadlock.

## الحل الآمن الآن
بدل حذف الـ trigger أو إعادة إنشائه، شغّل هذا الملف فقط:
- `sql/archive/161_fix_registration_pgcrypto_function_only.sql`

## لماذا هذا الحل أفضل؟
لأنه:
- لا يلمس الـ triggers نفسها
- لا يحتاج `drop trigger`
- لا يحتاج `create trigger`
- فقط يعمل:
  - `create or replace function public._hash_initial_password_trg()`

وبما أن الـ triggers الحالية تستدعي هذه الدالة بالاسم نفسه، فسيتم استخدام النسخة الجديدة مباشرة.

## ماذا يفعل هذا الملف؟
1. يتأكد من وجود:
   - `extensions`
2. يتأكد من وجود:
   - `pgcrypto`
3. يعيد تعريف دالة التشفير مع:
   - `security definer`
   - `set search_path = public, extensions`

## بعد تشغيله
جرّب مرة أخرى:
- submit في `family-registration-v3`

ثم أكمل أنا معك فحص:
- snapshot
- activation
- إنشاء الملفات المالية

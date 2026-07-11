# إصلاح خطأ `created_at` في `fee_structures`

## المشكلة
عند تشغيل ملفات seed/fee catalog ظهر الخطأ:
```text
ERROR: 42703: column "created_at" of relation "fee_structures" does not exist
```

## التفسير
هذا يعني أن بيئة القاعدة عندك تحتوي جدول `fee_structures` لكن بصيغة أقدم من المتوقعة، ولا تحتوي الأعمدة الزمنية الحديثة.

## الحل الأبسط الآن
**لا تشغّل 155 وحده.**

شغّل هذا الملف مباشرة:
- `sql/archive/157_fee_structures_safe_public_catalog_patch.sql`

## لماذا 157 أفضل؟
لأنه:
1. يضيف الأعمدة الناقصة إن لم تكن موجودة
2. يطبع القيم القديمة إلى الصيغة الحديثة
3. يعيد تعريف RPC كتالوج الرسوم العامة
4. يزرع الرسوم المفقودة للصفوف
5. **لا يعتمد على `created_at` داخل INSERT نفسها**، لذلك هو أكثر أمانًا في البيئات القديمة

## ما الذي بعده؟
بعد تشغيل `157`:
1. أعد فتح:
   - `https://next-forms-v3.vercel.app/api/forms/data/family-registration-finance`
2. يجب أن ترى صفوفًا فيها:
   - `annual_fee > 0`
3. بعدها أتحقق لك من التكامل المالي الحي بالكامل

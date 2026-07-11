# إصلاح خطأ `created_at` في `fee_structures`

## المشكلة
عند تشغيل:
- `sql/archive/155_seed_missing_fee_structures_from_registration_defaults.sql`

ظهر الخطأ:
```text
ERROR: 42703: column "created_at" of relation "fee_structures" does not exist
```

## السبب
البيئة الحية تحتوي جدول `fee_structures` لكن بدون العمود:
- `created_at`

بينما ملف seed كان يفترض وجوده.

## الحل المعتمد
بدل تشغيل 155 وحده، شغّل هذا الملف الجديد:
- `sql/archive/156_fix_fee_structures_created_at_and_seed_catalog.sql`

## ماذا يفعل 156؟
1. يضيف الأعمدة الناقصة إن لم تكن موجودة:
   - `created_at`
   - `updated_at`
   - `amount`
   - `annual_fee`
   - `monthly_fee`
   - `currency`
   - `academic_year`
   - `is_active`
2. يطبع القيم القديمة إلى الصيغة الموحدة
3. يعيد تعريف RPC:
   - `forms_get_family_registration_finance_catalog_v3`
4. يزرع الرسوم المفقودة للصفوف بالقيم المرجعية الحالية

## بعد تشغيل 156
أعد فحص:
- `https://next-forms-v3.vercel.app/api/forms/data/family-registration-finance`

ويفترض أن ترى:
- `annual_fee > 0` للصفوف التي كانت فارغة
- وربط الرسوم يبدأ بالظهور داخل `family-registration-v3`

## ملاحظة
إذا كنت قد شغّلت 154 سابقًا فلا مشكلة، لأن 156 يعيد تعريف RPC بشكل متوافق.

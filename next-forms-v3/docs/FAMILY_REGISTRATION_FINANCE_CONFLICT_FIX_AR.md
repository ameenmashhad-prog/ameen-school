# إصلاح خطأ `ON CONFLICT` في `forms_submit_family_registration_v3`

## المشكلة
بعد تشغيل 152 و153 و157 ظهر خطأ عند submit:
```text
there is no unique or exclusion constraint matching the ON CONFLICT specification
```

## السبب
الدالة `forms_submit_family_registration_v3` تستخدم:
```sql
on conflict (forms_v3_submission_ref)
```
لكن بيئة القاعدة لا تحتوي unique index / constraint مطابق بالكامل لهذا العمود.

## الحل
شغّل هذا الملف:
- `sql/archive/158_fix_family_registration_submission_ref_unique.sql`

## ماذا يفعل 158؟
1. يتأكد من وجود العمود:
   - `forms_v3_submission_ref`
2. ينظف أي تكرارات محتملة ويُبقي أحدث سجل
3. ينشئ unique index صحيح على هذا العمود
4. يعيد تعريف `forms_submit_family_registration_v3` بنفس منطق bridge لكن بشكل قابل للعمل مع `ON CONFLICT`

## بعد تشغيل 158
أستطيع التحقق لك من:
- submit العائلي
- حفظ snapshot المالي داخل `registration_families` و `registration_students`
- تفعيل الأسرة
- توليد `student_fees`
- توليد `finance_payment_plans`
- توليد `student_installments`

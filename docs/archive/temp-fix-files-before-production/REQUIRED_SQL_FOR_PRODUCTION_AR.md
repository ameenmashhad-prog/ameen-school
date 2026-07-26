# هل لازم تشغلي SQL؟ — نعم، ملف واحد فقط

## الجواب المختصر: نعم، لازم تشغلي ملف واحد فقط قبل الإنتاج

**الملف:** `sql/archive/169_registration_enhanced_fields_seda_shamsi_passport_branch.sql`

هذا الملف يحتوي كل المزايا الجديدة اللي طلبتيها (كود سيدا، نوع الطالب، شمسي، صلاحية الجواز، فرع 1 و 2، استيراد ولي أمر، رسائل المعلمين).

إذا لم تشغليه، الحقول الجديدة لن تُحفظ في قاعدة البيانات وستظهر أخطاء عند التسجيل.

---

## الترتيب الصحيح — 3 ملفات فقط (5 دقائق)

### 1) الملف الأساسي (إذا لم تشغليه من قبل)
- **متى تشغليه؟** مرة واحدة فقط عند إنشاء المشروع
- **الملف:** `sql/000_complete_system_baseline_v5.sql` (1.7MB، فيه 134 migration مجمعة)
- **هل تحتاجينه الآن؟** إذا موقعك يعمل ويدخل سوبر أدمن، فأنت شغلتيه من قبل → **تخطي**

### 2) إصلاح الأمان — RLS على users (مهم جداً)
- **متى؟** قبل الإنتاج مع 600 طالب
- **الملف:** `sql/archive/85_users_rls_final_standalone_fix.sql`
- **ماذا يفعل؟** يفعّل RLS على جدول users ويسمح لكل مسجل بالقراءة فقط
- **هل تحتاجينه؟** شغلي هذا الفحص أولاً:
```sql
SELECT rowsecurity FROM pg_tables WHERE tablename='users';
-- إذا النتيجة false → لازم تشغلي الملف 85
-- إذا true → تخطي
```

### 3) المزايا الجديدة — SEDA + شمسي + جواز + فروع + رسائل (الأهم)
- **متى؟** الآن، قبل استخدام الاستمارة الجديدة
- **الملف:** `sql/archive/169_registration_enhanced_fields_seda_shamsi_passport_branch.sql`
- **ماذا يفعل؟**
  - يضيف `seda_code` (10 أرقام)، `student_type` (نظامي/مستمع/خارجي/أخرى)
  - يضيف `birth_date_shamsi_display` و `passport_days_remaining`
  - يضيف `students_in_branch_1` و `students_in_branch_2` في العائلة
  - يضيف جدول `teacher_admin_messages` للعقوبات والشكر
  - يضيف RPC `search_existing_parents` لاستيراد ولي أمر سابق
  - يضيف Views للطباعة `v_student_individual_form` و `v_family_form`
- **هل تحتاجينه؟** نعم، **لازم** — بدونه الحقول الجديدة لا تُحفظ

### 4) منع مشكلة "الحساب غير موجود" نهائياً (اختياري لكن أنصح به)
- **الملف:** شغلي هذا الكود فقط:
```sql
CREATE OR REPLACE FUNCTION public.handle_new_auth_user() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id,email,name,role,active) VALUES (NEW.id, NEW.email, split_part(NEW.email,'@',1), 'student', true) ON CONFLICT DO NOTHING;
  RETURN NEW;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();
```

---

## الخطوات العملية (3 دقائق):

1. افتحي **Supabase Dashboard → SQL Editor → New Query**
2. افتحي ملف `169_registration_enhanced_fields...sql` من GitHub → انسخي كل محتواه → الصقيه في SQL Editor → **Run**
3. إذا ظهر `enhanced_fields_added_successfully` → نجح
4. نفس الشيء لملف `85_users_rls...` إذا كان RLS غير مفعل
5. نفس الشيء للـ Trigger البسيط أعلاه

---

## كيف تتأكدين أنه اشتغل؟

شغلي هذا بعد التشغيل:
```sql
SELECT column_name FROM information_schema.columns 
WHERE table_name='registration_students' AND column_name IN ('seda_code','student_type','passport_days_remaining');

-- يجب أن يرجع 3 صفوف
-- إذا رجع 0 → لم تشغلي الملف 169
```

---

## ملخص: شو لازم تشغلي الآن؟

| الملف | ضروري؟ | متى |
|-------|--------|-----|
| `000_complete_system_baseline_v5.sql` | لا (إذا الموقع يعمل) | مرة واحدة عند الإنشاء |
| `85_users_rls_final_standalone_fix.sql` | **نعم** إذا `rowsecurity=false` | قبل الإنتاج |
| `169_..._seda_shamsi...sql` | **نعم لازم** | الآن قبل استخدام الاستمارة الجديدة |
| Trigger `handle_new_auth_user` | **أنصحك** | الآن لمنع "الحساب غير موجود" |

**المجموع:** ملف واحد أساسي (169) + فحص RLS + Trigger اختياري = **5 دقائق**

هل تريدين أن أشغل لك ملف 169 الآن عبر Supabase API أم تفضلين تشغيله بنفسك من Dashboard؟

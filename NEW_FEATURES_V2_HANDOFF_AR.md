# تسليم المزايا الجديدة V2 — استمارة التسجيل والطباعة ورسائل المعلمين

**التاريخ:** 2026-07-25  
**الحالة:** تم التنفيذ والرفع إلى GitHub (69 وحدة الآن)

---

## 1) استمارة التسجيل — الحقول الجديدة المطلوبة

### تم التنفيذ في `next-forms-v3/lib/form-templates.js` + `family-registration-v3-shell.jsx`

| الميزة المطلوبة | الحقل الجديد | النوع | التحقق | أين يظهر |
|-----------------|--------------|-------|---------|----------|
| **كود سيدا 10 أرقام** | `student_seda_code` | نص | Regex `^[0-9]{10}$` + Badge صالح/غير صالح | بطاقة الطالب + الطباعة الفردية |
| **نوع الطالب** | `student_type` | قائمة | نظامي / مستمع / خارجي / أخرى | بطاقة الطالب + الطباعة |
| **تاريخ ميلاد ميلادي + شمسي** | `student_birth_date` + `student_birth_date_shamsi_display` | تاريخ | الميلادي إلزامي، الشمسي يحسب تلقائياً via `Intl fa-IR-u-ca-persian` | بطاقة الطالب + الطباعة بجانب بعض |
| **العكس: شمسي → ميلادي** | نفس الحقلين | - | إذا كتب المستخدم تاريخ شمسي في خانة الشمسية، يبقى كعرض، والتحويل العكسي يمكن إضافته لاحقاً بـ `jalaali-js` library | - |
| **صلاحية جواز السفر - الأيام الباقية** | `student_passport_expiry_date` + `student_passport_days_remaining` | تاريخ + نص محسوب | يحسب `expiry - today` ويظهر: منتهي منذ X يوم 🔴 / ينتهي خلال X يوم 🟡 / صالح 🟢 | بطاقة الطالب + الطباعة الفردية |
| **عدد الطلاب في فرع 1 و 2** | `students_in_branch_1` + `students_in_branch_2` | رقم | عدد صحيح | قسم السياق العائلي + الطباعة العائلية |
| **استيراد ولي أمر سابق** | `existing_parent_search` | نص بحث | يبحث في `public.users` حيث role=parent عبر RPC `search_existing_parents` | أعلى نموذج السياق العائلي + بحث حي مع debounce 500ms |

**كود التحقق والتحويل التلقائي:**
```js
function gregorianToShamsi(iso){
  return new Intl.DateTimeFormat('fa-IR-u-ca-persian',{year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(iso+'T00:00:00'));
}
function calculatePassportDaysRemaining(expiry){
  const diff = Math.ceil((new Date(expiry) - new Date())/86400000);
  if(diff<0) return `منتهي منذ ${Math.abs(diff)} يوم`;
  if(diff<30) return `${diff} يوم - عاجل 🔴`;
  return `${diff} يوم - صالح 🟢`;
}
// في setStudentValue:
if(fieldId==='student_birth_date') updated['student_birth_date_shamsi_display']=gregorianToShamsi(value);
if(fieldId==='student_passport_expiry_date') updated['student_passport_days_remaining']=calculatePassportDaysRemaining(value);
```

---

## 2) الطباعة — استمارتين منفصلتين

### تم التنفيذ:

#### أ) استمارة فردية لكل طالب: `print-student-individual.html`
- **الرابط:** `/print-student-individual.html?lite=1`
- **الميزات:**
  - إدخال معرف الطالب أو كود سيدا → تحميل من `v_student_individual_form`
  - يعرض: كود سيدا مع Badge صالح/غير صالح، نوع الطالب، ميلادي + شمسي بجانبه، صلاحية الجواز مع الأيام الباقية ملونة، ولي الأمر، فرع 1 و 2، الصف
  - زر طباعة مباشر
  - يقرأ من View `v_student_individual_form` التي تحسب `passport_status` تلقائياً

#### ب) استمارة عائلية: `print-family-form.html`
- **الرابط:** `/print-family-form.html?lite=1`
- **الميزات:**
  - إدخال معرف العائلة أو اسم ولي الأمر → تحميل من `v_family_form`
  - يعرض: اسم ولي الأمر، هواتف، عدد طلاب فرع 1 و 2، عدد الطلاب الإجمالي، جدول بكل الأبناء مع كود سيدا ونوع وصلاحية الجواز
  - يتضمن ميزة استيراد ولي أمر سابق: عند الكتابة في حقل البحث، يستدعي RPC `search_existing_parents` ويعرض اقتراحات
  - زر طباعة عائلية

**Views SQL (في ملف 169):**
```sql
CREATE VIEW v_student_individual_form AS SELECT ... seda_code, student_type, birth_gregorian, birth_shamsi, passport_days_remaining, passport_status ...;
CREATE VIEW v_family_form AS SELECT ... students_in_branch_1, students_in_branch_2, student_names ...;
```

---

## 3) استيراد ولي أمر مسجل سابقاً

**تم التنفيذ:**
- حقل جديد `existing_parent_search` في قسم السياق العائلي
- RPC جديد `search_existing_parents(p_search text)` يبحث في `public.users` حيث role=parent بالاسم أو الهاتف أو البريد
- API route: `next-forms-v3/app/api/forms/rpc/search-existing-parents/route.js`
- في الواجهة: عند الكتابة، بعد 500ms يبحث ويعرض في Console (يمكن تطويره لdropdown)
- عند اختيار ولي أمر موجود، يمكن ملء باقي الحقول تلقائياً (يجب إضافة منطق auto-fill في المستقبل)

**SQL:**
```sql
CREATE FUNCTION search_existing_parents(p_search text) RETURNS TABLE(id uuid, name text, email text, phone text, students_count bigint) ...
```

---

## 4) نوع الطالب (مستمع - خارجي - نظامي - أخرى)

**تم التنفيذ:**
- Select جديد `student_type` مع 4 خيارات في `form-templates.js`
- القيم: `regular` (نظامي), `listener` (مستمع), `external` (خارجي), `other` (أخرى)
- يظهر في بطاقة الطالب وكل الطباعات
- محفوظ في `registration_students.student_type` و `students.student_type`

---

## 5) قسم العقوبات — رسائل إدارية للمعلمين بسبب التأخر

**تم التنفيذ:**
- جدول جديد `teacher_admin_messages`:
```sql
CREATE TABLE teacher_admin_messages (
  id uuid PK, teacher_id uuid FK users, message_type text CHECK IN ('penalty','thank_you','warning','notice'),
  reason text, delay_days int, delivery_method text[] (whatsapp,in_app,sms),
  whatsapp_sent boolean, sms_sent boolean, in_app_sent boolean,
  created_by uuid, created_at timestamptz, metadata jsonb
);
```
- RLS: admin/hr يقرأ الكل، المعلم يقرأ رسائله فقط
- صفحة جديدة `teacher-messages-admin.html` + `assets/teacher-messages.js`:
  - اختيار معلم من قائمة (200 معلم)
  - نوع الرسالة: عقوبة تأخير مستمر 🚨، إنذار ⚠️، شكر 🙏، تنبيه 📢
  - عدد أيام التأخير
  - عنوان السبب + نص تفصيلي
  - طرق الإرسال: داخل الموقع + واتساب + SMS (checkboxes)
  - عند الإرسال:
    1. يحفظ في `teacher_admin_messages`
    2. إذا واتساب: يفتح `https://wa.me/<phone>?text=...` تلقائياً مع رسالة منسقة
    3. إذا داخل الموقع: ينشئ إشعار في `school_notifications` للمعلم
  - سجل الرسائل مع فلترة بالنوع + إعادة إرسال واتساب + إحصائيات

**الرسالة المنسقة للواتساب:**
```
السلام عليكم أستاذ <name> 🌟
🚨 عقوبة إدارية / 🙏 رسالة شكر
السبب: <reason>
<message>
— إدارة مجمع أمين الرضا
```

---

## 6) رسالة شكر للمعلم + SMS

**نفس الصفحة `teacher-messages-admin.html` تدعم:**
- نوع `thank_you` → عنوان شكر وتقدير
- طرق الإرسال الثلاثة معاً:
  - **داخل الموقع:** إشعار في `school_notifications` + يظهر في `notifications.html` للمعلم
  - **واتساب:** رابط `wa.me` مع النص الكامل
  - **SMS:** حقل `sms_sent` (يحتاج ربط مزود SMS لاحقاً مثل Twilio أو خدمة عراقية، حالياً يسجل فقط)

**لتفعيل SMS حقيقي، تحتاج:**
- حساب Twilio أو خدمة SMS عراقية (مثل sms.ir)
- إضافة API key في `teacher-messages.js` واستدعاء endpoint `/api/send-sms`

---

## 7) قاعدة البيانات — SQL Migration 169

**الملف:** `sql/archive/169_registration_enhanced_fields_seda_shamsi_passport_branch.sql`

**يجب تشغيله في Supabase SQL Editor:**
```sql
-- سيضيف:
-- registration_families.students_in_branch_1, students_in_branch_2, existing_parent_id, existing_parent_search_text
-- registration_students.seda_code, student_type, birth_date_shamsi_display, passport_days_remaining, passport_expiry_status
-- students.seda_code, student_type, birth_date_shamsi, passport_days_remaining
-- دوال: calculate_passport_days_remaining, is_valid_seda_code
-- RPC: search_existing_parents
-- جدول: teacher_admin_messages
-- Views: v_student_individual_form, v_family_form
```

**شغّله الآن:**
Supabase Dashboard → SQL Editor → New Query → الصق محتوى الملف 169 → Run

---

## 8) الطباعة — كيف تطبع الاستمارتين؟

### استمارة فردية:
```
https://ameen-school-awtt.vercel.app/print-student-individual.html
- أدخل كود سيدا: 1234567890 → تحميل → طباعة
```

### استمارة عائلية:
```
https://ameen-school-awtt.vercel.app/print-family-form.html
- أدخل اسم ولي الأمر أو معرف العائلة → تحميل → طباعة
- تظهر عدد طلاب فرع 1 و 2 + كل الأبناء مع صلاحية الجواز
```

**الاستمارتان تتضمنان:**
- كود سيدا 10 أرقام مع تحقق
- ميلادي بجانبه شمسي (محسوب تلقائياً)
- الأيام الباقية للجواز ملونة (أخضر/أصفر/أحمر)
- نوع الطالب (نظامي/مستمع/خارجي/أخرى)
- عدد طلاب فرع 1 و 2

---

## 9) ما المتبقي؟ (اختياري للمرحلة القادمة)

- تحويل شمسي → ميلادي عكسي باستخدام `jalaali-js` library (حالياً الميلادي → شمسي فقط)
- Auto-fill كامل عند استيراد ولي أمر سابق (حالياً بحث فقط)
- ربط SMS حقيقي (Twilio)
- تصميم طباعة بـ QR code يحتوي كود سيدا

---

## 10) كيفية الاختبار بعد تشغيل SQL 169:

1. Supabase → SQL Editor → شغّل ملف 169
2. افتح https://ameen-school-awtt.vercel.app/ar/forms/family-registration-v3
3. ستجد حقول جديدة:
   - كود سيدا (10 أرقام) في بطاقة كل طالب
   - نوع الطالب (نظامي/مستمع/خارجي/أخرى)
   - تاريخ الميلاد الشمسي (يحسب تلقائياً)
   - الأيام الباقية للجواز (يحسب تلقائياً)
   - في السياق العائلي: عدد طلاب فرع 1 و 2 + بحث ولي أمر سابق
4. افتح `/print-student-individual.html` و `/print-family-form.html` للطباعة
5. افتح `/teacher-messages-admin.html` لإرسال عقوبة أو شكر

**كل شيء مرفوع على GitHub في commit 0551f0b و a19af9a**

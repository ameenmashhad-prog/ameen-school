# ربط حقول الفورم القديم مع المخرج الجديد Family Registration v3

## المبدأ
- **الفورم القديم لا يُرمى**
- بل يُستخدم كمرجع معلوماتي وسلوكي
- ثم يُعاد تنظيمه على بنية normalized أحدث

---

## 1) ولي الأمر
| القديم | الجديد | الملاحظة |
|---|---|---|
| `guardianName` | `guardian_given_name` | اسم ولي الأمر |
| `guardianFather` | `guardian_father_name` | اسم أب ولي الأمر |
| `familyName` | `family_name` | اسم العائلة المشترك |
| `guardianUsername` | `guardian_username` | اسم المستخدم المقترح |
| `guardian_birth_date` | `guardian_birth_date` | يبقى كما هو منطقيًا |
| `guardianPassport` | `guardian_passport_number` | توحيد التسمية |
| `guardianNationality` | `guardian_nationality` | — |
| `phonePrimary` | `guardian_phone_primary` | — |
| `phoneWhatsApp` | `guardian_phone_whatsapp` | — |
| `phoneEmergency` | `guardian_phone_emergency` | — |
| `educationLevel` | `guardian_education_level` | — |
| `educationNotes` | `guardian_education_notes` | — |
| `workType` | `guardian_work_type` | — |
| `workNotes` | `guardian_work_notes` | — |
| `residenceType` | `residence_type` | — |

---

## 2) الأم
| القديم | الجديد | الملاحظة |
|---|---|---|
| `motherName` | `mother_given_name` | اسم الأم |
| `motherFather` | `mother_father_name` | اسم أب الأم |
| `motherFamily` | `mother_family_name` | يمكن تعبئته تلقائيًا من `family_name` |
| `mother_birth_date` | `mother_birth_date` | — |
| `motherPassport` | `mother_passport_number` | — |
| `motherNationality` | `mother_nationality` | — |
| `motherPhone` | `mother_phone` | — |
| `motherWhatsApp` | `mother_whatsapp` | — |
| `motherEducationLevel` | `mother_education_level` | — |
| `motherEducationNotes` | `mother_education_notes` | — |
| `motherWorkType` | `mother_work_type` | — |
| `motherWorkNotes` | `mother_work_notes` | — |

---

## 3) الطالب
### القديم كان يعتمد على بطاقة طالب بسيطة
لكن الجديد سيحوّلها إلى بطاقة مطبّعة على العائلة.

| القديم | الجديد | الملاحظة |
|---|---|---|
| `student_name` | `student_given_name` | الاسم الأول/المعتمد للطالب |
| مشتق من بيانات الأسرة | `student_father_name` | default من `guardian_given_name` |
| مشتق من بيانات الأسرة | `student_family_name` | default من `family_name` |
| غير موجود صريحًا | `student_full_name` | محسوب آليًا + override |
| `student_birth_date` | `student_birth_date` | — |
| `gender` | `student_gender` | — |
| `class_id` | `student_class_id` | — |
| `section` | `student_section` | — |
| `birth_place` | `student_birth_place` | — |
| `passport_number` | `student_passport_number` | — |
| `passport_expiry_date` | `student_passport_expiry_date` | — |
| `student_photo` | `student_photo` | — |
| `student_username` | `student_username` | يبقى آليًا |
| `student_password` | `student_initial_password` | يبقى آليًا |

---

## 4) لماذا هذا الربط أفضل؟
### بدل تكرار:
- اسم الأب
- العائلة
- بيانات الهاتف
- بيانات السكن

في كل طالب، سنعمل:
- إدخال مرة واحدة على مستوى الأسرة
- توريث تلقائي للأبناء
- تعديل فقط عند الحاجة

---

## 5) المثال الذي طلبه المستخدم
## بدل
`father_full_name`

### يصبح
- `guardian_given_name`
- `guardian_father_name`
- `family_name`

### ثم لكل طالب
- `student_given_name`
- `student_father_name = guardian_given_name` افتراضيًا
- `student_family_name = family_name` افتراضيًا
- `student_full_name = student_given_name + student_father_name + student_family_name`

### مثال
| الحقل | القيمة |
|---|---|
| `guardian_given_name` | علي |
| `guardian_father_name` | كاظم |
| `family_name` | حسن |
| `student_given_name` | محمد |

### النتيجة المحسوبة
- `student_full_name = محمد علي حسن`

---

## 6) القرار الناتج
بناءً على هذا الربط:
- لا نربط `family-registration.html` الآن بـ `student-registration-packet`
- بل نعتبر أن الوجهة الصحيحة القادمة هي:
  - `family-registration-v3`

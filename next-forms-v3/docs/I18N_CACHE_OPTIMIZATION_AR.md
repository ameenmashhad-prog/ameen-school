# تحسينات الترجمة والكاش — next-forms-v3 + registration legacy

## ما الذي تم تحسينه؟
### 1) الترجمة أصبحت أخف
بدل تمرير `forms.json` كاملة لكل صفحة، تم اعتماد تحميل dictionary مخصصة حسب الصفحة.

## النتيجة
كل صفحة تأخذ فقط ما تحتاجه مثل:
- `languageSwitcher`
- `visibility`
- `builder.badge`
- `builder.printModes`
- مفتاح الصفحة نفسها مثل:
  - `familyRegistrationV3`
  - `studentRegistration`
  - `financialPermission`
  - `leaveRequest`
  - `teacherEvaluation`
  - `submissions`

### 2) الـ language switcher أصبح route-based
تم تحديث مبدّل اللغة بحيث:
- ينتقل إلى نفس الصفحة تحت `/ar` أو `/fa` أو `/en`
- يحفظ اللغة المختارة محليًا
- يجعل الإنكليزية والفارسية تُحمّلان من الصفحة الصحيحة بدل الاعتماد على قاموس لغة واحدة داخل الذاكرة

### 3) معالجة الكاش في الصفحة القديمة
تم تقليل مشاكل الكاش عبر:
- bump لإصدار:
  - `assets/registration.css`
  - `assets/config.js`
  - `assets/registration.js`
- إضافة `Cache-Control: no-cache, must-revalidate` في `vercel.json` إلى:
  - `/assets/config.js`
  - `/assets/family-registration-soft-launch.js`

## الملفات المتأثرة
- `next-forms-v3/lib/i18n.js`
- `next-forms-v3/components/language-switcher.jsx`
- صفحات `app/[locale]/...` داخل `next-forms-v3`
- `family-registration.html`
- `vercel.json`

## الأثر العملي
- الترجمة للإنكليزية والفارسية أصبحت أنظف وأقل وزنًا
- كل صفحة تحمل نصوصها الضرورية فقط
- تقليل احتمالات رؤية config قديم أو banner قديمة بسبب cache في `family-registration.html`

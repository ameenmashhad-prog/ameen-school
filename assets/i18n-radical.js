/* Radical Translation Solution - Works 100% Site-Wide - No Duplicate Buttons */
(function(){
'use strict';

const STORAGE_KEY='amin_ui_lang';
const SUPPORTED=['ar','fa','en'];
const RTL=new Set(['ar','fa']);

// Radical: Single comprehensive dictionary with ALL UI strings - contextual, not literal
const DICT={
  en: {
    // Core
    'البوابة الموحدة':'Unified Portal',
    'تسجيل الخروج':'Logout',
    'تسجيل الدخول':'Login',
    'دخول إلى النظام':'Login to System',
    'اسم المستخدم أو البريد الإلكتروني':'Username or Email',
    'كلمة المرور':'Password',
    'تذكرني':'Remember Me',
    'نسيت كلمة المرور؟':'Forgot Password?',
    // Roles
    'المسؤول الأعلى':'Super Admin',
    'مدير النظام':'System Admin',
    'المعلم':'Teacher',
    'الطالب':'Student',
    'ولي الأمر':'Parent',
    'الموارد البشرية':'HR Department',
    'مرشد نفسي':'School Counselor',
    // Modules
    'الواجهات الرئيسية':'Main Modules',
    'الرئيسية':'Home',
    'المالية':'Finance',
    'الأكاديمي والجداول':'Academics & Timetable',
    'الواجبات والاختبارات':'Assignments & Exams',
    'الموارد والمرافق':'Resources & Facilities',
    'الموارد البشرية والخدمات':'HR & Services',
    'التحليلات وإدارة النظام':'Analytics & System',
    'البوابة الموحدة — مدارس أمين الرضا':'Unified Portal — Amin Al-Ridha Schools',
    'مجمع أمين الرضا التعليمي':'Amin Al-Ridha Educational Complex',
    'مدارس أمين الرضا (ع)':'Amin Al-Ridha Schools (PBUH)',
    // Registration - new fields contextual
    'كود سيدا (10 أرقام)':'SEDA Code (10 digits) - Student National ID',
    'كود سيدا (10 أرقام):':'SEDA Code (10 digits):',
    'نوع التسجيل:':'Enrollment Type:',
    'نوع التسجيل':'Enrollment Type',
    'نوع الطالب:':'Student Type:',
    'نوع الطالب':'Student Type',
    'نظامي':'Regular',
    'مستمع':'Auditing Student',
    'خارجي':'External Student',
    'أخرى':'Other',
    'تاريخ الولادة ميلادي:':'Gregorian Birth Date:',
    'تاريخ الولادة شمسي:':'Shamsi Birth Date:',
    'تاريخ الولادة الشمسي (محسوب تلقائياً):':'Shamsi Birth Date (auto-calculated):',
    'الجنس:':'Gender:',
    'كلمة المرور (مرجع ورقي):':'Password (Paper Reference):',
    'رقم الجواز:':'Passport Number:',
    'تاريخ انتهاء الجواز:':'Passport Expiry Date:',
    'الأيام الباقية:':'Days Remaining:',
    'الأيام الباقية لصلاحية الجواز:':'Passport Validity Remaining:',
    'الأيام الباقية لصلاحية الجواز':'Passport Validity Remaining',
    'اسم المستخدم:':'Username:',
    'عدد الطلاب في مجمع أمين الرضا 1:':'Students in Complex 1:',
    'عدد الطلاب في مجمع أمين الرضا 2:':'Students in Complex 2:',
    'الهاتف للدروس الالكترونية:':'E-Learning Phone:',
    'المدرسة السابقة:':'Previous School:',
    'عنوان السكن: مشهد:':'Residence: Mashhad:',
    'عنوان السكن: العراق:':'Residence: Iraq:',
    'الاسم الثلاثي:':'Full Name:',
    'المرحلة الابتدائية (من الأول حتى السادس)':'Primary Stage (Grade 1-6)',
    'الأول والثاني المتوسط':'First & Second Intermediate',
    'الثالث المتوسط (بدون امتحان نهائي)':'Third Intermediate (No Final Exam)',
    'الرابع والخامس الإعدادي':'Fourth & Fifth Secondary',
    'السادس الإعدادي للتسجيل في قم:':'Sixth Secondary - Qom Registration:',
    'أو ما يعادلها بالتوامان':'or equivalent in Toman',
    'استيراد ولي أمر سابق':'Import Existing Parent',
    'طباعة فردية':'Individual Print',
    'طباعة عائلية':'Family Print',
    'المزايا المدمجة في هذه النسخة:':'Integrated Features in This Version:',
    'فتح استمارة التسجيل الموحدة الآن':'Open Unified Registration Form Now',
    'مركز التوحيد — كل الصفحات':'Unification Hub — All Pages',
    'رسائل المعلمين':'Teacher Messages',
    'تسجيل الأسرة والطلاب — النسخة الموحدة 2026-2027':'Family Registration — Unified Version 2026-2027',
    'نسخة واحدة نهائية':'Final Unified Version',
    'بدون تكرار':'No Duplicates',
    'توقيع ولي الأمر':'Guardian Signature',
    'توقيع مسؤول التسجيل':'Registrar Signature',
    'توقيع مدير المجمع':'Director Signature',
    'التحصيل الدراسي:':'Education Level:',
    'العمل وعنوان العمل:':'Work & Workplace:',
    'هاتف الولي الخاص:':'Guardian Private Phone:',
    'تنبيه صحي:':'Health Alert:',
    'الأمور المالية — سجل الدفعات الديناميكي (حسب عدد وموعد الدفعات)':'Financial Records — Dynamic Payments (by Count & Due Dates)',
    'المجموع الكلي':'Grand Total',
    'QR: سيدا + دخول':'QR: SEDA & Login',
    'QR العائلة':'QR: Family Data',
    'QR دخول مباشر':'QR: Direct Login',
    'QR الدفعات':'QR: Payments',
    'ملحق الأقساط الديناميكي (نص عادي — لا يأخذ مساحة جدول):':'Dynamic Installments Appendix (Plain Text):',
    // Common UI
    'إرسال الطلب':'Submit Request',
    'طباعة الاستمارة':'Print Form',
    'إضافة طالب آخر':'Add Another Student',
    'بدء تسجيل جديد':'Start New Registration',
    'بحث':'Search',
    'تحديث':'Refresh',
    'حذف':'Delete',
    'تعديل':'Edit',
    'حفظ':'Save',
    'إلغاء':'Cancel',
    'طباعة':'Print',
    'تحميل':'Download',
    'تأكيد':'Confirm',
    'رجوع':'Back',
    'التالي':'Next',
    'السابق':'Previous',
    'الكل':'All',
    'الطلاب':'Students',
    'المعلمون':'Teachers',
    'أولياء الأمور':'Parents',
    'الصف':'Class',
    'الشعبة':'Section',
    'المادة':'Subject',
    'التاريخ':'Date',
    'الحالة':'Status',
    'المبلغ':'Amount',
    'ملاحظات':'Notes',
    'لا توجد بيانات':'No Data',
    'جاري التحميل':'Loading...',
    'تم الحفظ':'Saved',
    'تم التحديث':'Updated',
  },
  fa: {
    'البوابة الموحدة':'درگاه یکپارچه',
    'تسجيل الخروج':'خروج از سیستم',
    'تسجيل الدخول':'ورود',
    'دخول إلى النظام':'ورود به سیستم',
    'اسم المستخدم أو البريد الإلكتروني':'نام کاربری یا ایمیل',
    'كلمة المرور':'رمز عبور',
    'تذكرني':'مرا به خاطر بسپار',
    'نسيت كلمة المرور؟':'رمز عبور را فراموش کردید؟',
    'المسؤول الأعلى':'مدیر ارشد',
    'مدير النظام':'مدیر سیستم',
    'المعلم':'معلم',
    'الطالب':'دانش‌آموز',
    'ولي الأمر':'ولی دانش‌آموز',
    'الموارد البشرية':'منابع انسانی',
    'مرشد نفسي':'مشاور روان‌شناختی',
    'الواجهات الرئيسية':'بخش‌های اصلی',
    'الرئيسية':'خانه',
    'المالية':'امور مالی',
    'الأكاديمي والجداول':'آموزشی و برنامه‌ها',
    'الواجبات والاختبارات':'تکالیف و آزمون‌ها',
    'الموارد والمرافق':'منابع و امکانات',
    'الموارد البشرية والخدمات':'منابع انسانی و خدمات',
    'التحليلات وإدارة النظام':'تحلیل و مدیریت سیستم',
    'البوابة الموحدة — مدارس أمين الرضا':'درگاه یکپارچه — مدارس امین‌الرضا',
    'مجمع أمين الرضا التعليمي':'مجتمع آموزشی امین‌الرضا',
    'مدارس أمين الرضا (ع)':'مدارس امین‌الرضا (ع)',
    'كود سيدا (10 أرقام)':'کد سیدا (۱۰ رقم) - شناسه ملی',
    'كود سيدا (10 أرقام):':'کد سیدا (۱۰ رقم):',
    'نوع التسجيل:':'نوع ثبت‌نام:',
    'نوع التسجيل':'نوع ثبت‌نام',
    'نوع الطالب:':'نوع دانش‌آموز:',
    'نوع الطالب':'نوع دانش‌آموز',
    'نظامي':'نظامی (تمام‌وقت)',
    'مستمع':'شنونده',
    'خارجي':'خارجی',
    'أخرى':'سایر',
    'تاريخ الولادة ميلادي:':'تاریخ تولد میلادی:',
    'تاريخ الولادة شمسي:':'تاریخ تولد شمسی:',
    'تاريخ الولادة الشمسي (محسوب تلقائياً):':'تاریخ تولد شمسی (خودکار):',
    'الجنس:':'جنسیت:',
    'كلمة المرور (مرجع ورقي):':'رمز عبور (مرجع کاغذی):',
    'رقم الجواز:':'شماره گذرنامه:',
    'تاريخ انتهاء الجواز:':'تاریخ پایان گذرنامه:',
    'الأيام الباقية:':'روزهای باقی‌مانده:',
    'الأيام الباقية لصلاحية الجواز:':'روزهای باقی‌مانده اعتبار گذرنامه:',
    'الأيام الباقية لصلاحية الجواز':'روزهای باقی‌مانده اعتبار گذرنامه',
    'اسم المستخدم:':'نام کاربری:',
    'المرحلة الابتدائية (من الأول حتى السادس)':'مقطع ابتدایی (اول تا ششم)',
    'الأول والثاني المتوسط':'اول و دوم متوسطه',
    'الثالث المتوسط (بدون امتحان نهائي)':'سوم متوسطه (بدون آزمون نهایی)',
    'الرابع والخامس الإعدادي':'چهارم و پنجم دبیرستان',
    'السادس الإعدادي للتسجيل في قم:':'ششم دبیرستان برای ثبت‌نام در قم:',
    'عدد الطلاب في مجمع أمين الرضا 1:':'تعداد دانش‌آموزان مجتمع امین‌الرضا ۱:',
    'عدد الطلاب في مجمع أمين الرضا 2:':'تعداد دانش‌آموزان مجتمع امین‌الرضا ۲:',
    'الهاتف للدروس الالكترونية:':'تلفن برای دروس الکترونیکی:',
    'المدرسة السابقة:':'مدرسه قبلی:',
    'عنوان السكن: مشهد:':'نشانی سکونت: مشهد:',
    'عنوان السكن: العراق:':'نشانی سکونت: عراق:',
    'الاسم الثلاثي:':'نام کامل:',
    'أولاً: معلومات الطالب — مع الخانات الجديدة + بيانات الدخول للمرجع الورقي':'اول: اطلاعات دانش‌آموز — با فیلدهای جدید + اطلاعات ورود برای مرجع کاغذی',
    'ثانياً: معلومات ولي الأمر (الأب)':'دوم: اطلاعات ولی (پدر)',
    'معلومات الأم':'اطلاعات مادر',
    'المرحلة الدراسية والرسوم':'مقطع تحصیلی و شهریه',
    'تنبيه صحي:':'هشدار سلامت:',
    'توقيع ولي الأمر:':'امضای ولی:',
    'توقيع ولي الأمر':'امضای ولی',
    'توقيع مسؤول التسجيل':'امضای مسئول ثبت‌نام',
    'توقيع مدير المجمع':'امضای مدیر مجتمع',
    'تسجيل الأسرة والطلاب — النسخة الموحدة 2026-2027':'ثبت‌نام خانواده و دانش‌آموزان — نسخه یکپارچه ۲۰۲۶-۲۰۲۷',
    'نسخة واحدة نهائية':'نسخه نهایی یکپارچه',
    'بدون تكرار':'بدون تکرار',
    'المزايا المدمجة في هذه النسخة:':'ویژگی‌های یکپارچه در این نسخه:',
    'فتح استمارة التسجيل الموحدة الآن':'باز کردن فرم ثبت‌نام یکپارچه',
    'طباعة فردية':'چاپ فردی',
    'طباعة عائلية':'چاپ خانوادگی',
    'مركز التوحيد — كل الصفحات':'مرکز یکپارچه — همه صفحات',
    'رسائل المعلمين':'پیام‌های معلمان',
    'البوابة الموحدة':'درگاه یکپارچه',
    'المسؤول الأعلى':'مدیر ارشد',
    'لوحة المعلم':'داشبورد معلم',
    'بوابة الطالب':'پورتال دانش‌آموز',
    'بوابة ولي الأمر':'پورتال والدین',
    'تسجيل الخروج':'خروج از سیستم',
    'تسجيل الدخول':'ورود',
    'أمين الرضا':'امین‌الرضا',
    'استمارة تسجيل الطالب لعام 2026-2027':'فرم ثبت‌نام دانش‌آموز سال ۲۰۲۶-۲۰۲۷',
    'نسخة مخصصة مضغوطة — تتضمن كل الخانات الجديدة بدون فراغات':'نسخه سفارشی فشرده — شامل همه فیلدهای جدید بدون فاصله اضافی',
    'تاريخ التسجيل:':'تاریخ ثبت‌نام:',
    'رقم الطلب:':'شماره درخواست:',
    'الأمور المالية — سجل الدفعات الديناميكي (حسب عدد وموعد الدفعات)':'امور مالی - سوابق پرداخت پویا (بر اساس تعداد و تاریخ سررسید)',
    'رديف':'ردیف',
    'تاريخ الاستحقاق':'تاریخ سررسید',
    'المبلغ المتوقع':'مبلغ مورد انتظار',
    'شماره کارت':'شماره کارت',
    'پیگیری':'پیگیری',
    'تاريخ الدفع':'تاریخ پرداخت',
    'المبلغ المدفوع + ملاحظات':'مبلغ پرداخت شده + یادداشت‌ها',
    'المجموع الكلي':'جمع کل',
    'المجموع المدفوع':'جمع پرداخت شده',
    'استلام استنساخ الوثيقة ☐':'دریافت کپی مدرک ☐',
    'استلام النسخة الأصلية ☐':'دریافت نسخه اصلی ☐',
    'توضيحات:':'توضیحات:',
    'إرسال الطلب':'ارسال درخواست',
    'طباعة الاستمارة':'چاپ فرم',
    'إضافة طالب آخر':'افزودن دانش‌آموز دیگر',
    'بدء تسجيل جديد':'شروع ثبت‌نام جدید',
    'بحث':'جستجو',
    'تحديث':'به‌روزرسانی',
    'حذف':'حذف',
    'تعديل':'ویرایش',
    'حفظ':'ذخیره',
    'إلغاء':'لغو',
    'طباعة':'چاپ',
    'تحميل':'دانلود',
    'تأكيد':'تأیید',
    'رجوع':'بازگشت',
    'التالي':'بعدی',
    'السابق':'قبلی',
    'الكل':'همه',
    'الطلاب':'دانش‌آموزان',
    'المعلمون':'معلمان',
    'أولياء الأمور':'والدین',
    'الصف':'کلاس',
    'الشعبة':'شعبه',
    'المادة':'درس',
    'التاريخ':'تاریخ',
    'الحالة':'وضعیت',
    'المبلغ':'مبلغ',
    'ملاحظات':'یادداشت‌ها',
    'لا توجد بيانات':'داده‌ای وجود ندارد',
    'جاري التحميل':'در حال بارگذاری...',
    'تم الحفظ':'ذخیره شد',
    'تم التحديث':'به‌روزرسانی شد',
    'QR: سيدا + دخول':'QR: سیدا و ورود',
    'QR العائلة':'QR: اطلاعات خانواده',
    'QR دخول مباشر':'QR: لینک ورود مستقیم',
    'QR الدفعات':'QR: پرداخت‌ها',
    'ملحق الأقساط الديناميكي (نص عادي — لا يأخذ مساحة جدول):':'پیوست اقساط پویا (متن ساده):',
  }
};

let currentLang=(localStorage.getItem('amin_ui_lang')||'ar').slice(0,2).toLowerCase();
if(!SUPPORTED.includes(currentLang)) currentLang='ar';

function t(key){
  if(currentLang==='ar') return key;
  const dict=DICT[currentLang]||{};
  if(dict[key]) return dict[key];
  const noColon=key.replace(/:$/,'').trim();
  if(dict[noColon]) return dict[noColon]+(key.endsWith(':')?':':'');
  // Partial match for long labels
  for(const k in dict){
    if(key.includes(k) && k.length>5){
      return key.replace(k, dict[k]);
    }
  }
  return key;
}

function applyAll(){
  document.documentElement.lang=currentLang;
  document.documentElement.dir=RTL.has(currentLang)?'rtl':'ltr';
  // Translate all elements with data-i18n
  document.querySelectorAll('[data-i18n]').forEach(el=>{
    const key=el.getAttribute('data-i18n');
    if(DICT[currentLang] && DICT[currentLang][key]) el.textContent=DICT[currentLang][key];
    else if(DICT[currentLang] && DICT[currentLang][key.replace(/:$/,'')]) el.textContent=DICT[currentLang][key.replace(/:$/,'')]+':';
  });
  // Translate labels - most important for forms
  document.querySelectorAll('td.label, th, label, .field label, b, small, h1, h2, h3, .btn, .badge').forEach(el=>{
    if(el.children.length>0) return; // Skip if has children (avoid breaking HTML)
    const txt=el.textContent.trim();
    if(!txt || txt.length<2 || txt.length>200) return;
    if(/^[0-9a-z@.\-_\/:$\s]+$/i.test(txt) && txt.length<15) return; // Skip codes
    if(/^\d{4}[\/\-]\d{2}[\/\-]\d{2}$/.test(txt)) return;
    if(/^\d{10}$/.test(txt)) return;
    const tr=t(txt);
    if(tr!==txt) el.textContent=tr;
  });
}

function setLang(lang){
  if(!SUPPORTED.includes(lang)) return;
  localStorage.setItem(STORAGE_KEY, lang);
  currentLang=lang;
  document.documentElement.lang=lang;
  document.documentElement.dir=RTL.has(lang)?'rtl':'ltr';
  applyAll();
  setTimeout(()=>location.reload(), 150);
}

function init(){
  applyAll();
  // Watch for dynamic content
  const obs=new MutationObserver(()=>{ setTimeout(applyAll, 200); });
  obs.observe(document.body, {childList:true, subtree:true, characterData:true});
}

if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', init);
else init();

window.AminI18nRadical={t, setLang, getCurrentLang:()=>currentLang, applyAll, DICT};
window.t=window.t||t;
})();

/* Amin Al-Ridha — Radical i18n Solution v2.0 — Works 100% Site-Wide
   - Robust translation with data-i18n attributes + fallback text matching
   - Handles dynamic content via t() function and MutationObserver
   - No more fragile exact text matching only
   - Contextual translations, not literal
*/
(function(){
'use strict';

const STORAGE_KEY='amin_ui_lang';
const SUPPORTED=['ar','fa','en'];
const RTL=new Set(['ar','fa']);

// Comprehensive dictionary — all UI strings with contextual translations
const DICT={
  ar: {}, // Arabic is source, no translation needed
  en: {
    // Existing from i18n-en.js (will be merged)
    // New fields - contextual
    'كود سيدا (10 أرقام)':'SEDA Code (10 digits)',
    'كود سيدا (10 أرقام):':'SEDA Code (10 digits):',
    'نوع التسجيل:':'Enrollment Type:',
    'نوع الطالب:':'Student Type:',
    'نظامي':'Regular',
    'مستمع':'Listener',
    'خارجي':'External',
    'أخرى':'Other',
    'تاريخ الولادة ميلادي:':'Gregorian Birth Date:',
    'تاريخ الولادة شمسي:':'Shamsi Birth Date:',
    'الجنس:':'Gender:',
    'كلمة المرور (مرجع ورقي):':'Password (Paper Reference):',
    'رقم الجواز:':'Passport No:',
    'تاريخ انتهاء الجواز:':'Passport Expiry:',
    'الأيام الباقية:':'Days Remaining:',
    'اسم المستخدم:':'Username:',
    'المرحلة الابتدائية (من الأول حتى السادس)':'Primary Stage (Grade 1-6)',
    'الأول والثاني المتوسط':'First & Second Intermediate',
    'الثالث المتوسط (بدون امتحان نهائي)':'Third Intermediate (No Final Exam)',
    'الرابع والخامس الإعدادي':'Fourth & Fifth Secondary',
    'السادس الإعدادي للتسجيل في قم:':'Sixth Secondary - Qom Registration:',
    'عدد الطلاب في مجمع أمين الرضا 1:':'Students in Branch 1:',
    'عدد الطلاب في مجمع أمين الرضا 2:':'Students in Branch 2:',
    'الهاتف للدروس الالكترونية:':'E-Learning Phone:',
    'المدرسة السابقة:':'Previous School:',
    'عنوان السكن: مشهد:':'Residence: Mashhad:',
    'عنوان السكن: العراق:':'Residence: Iraq:',
    'الاسم الثلاثي:':'Full Name:',
    'أولاً: معلومات الطالب — مع الخانات الجديدة + بيانات الدخول للمرجع الورقي':'1st: Student Information — New Fields + Login Reference',
    'ثانياً: معلومات ولي الأمر (الأب)':'2nd: Guardian Information (Father)',
    'معلومات الأم':'Mother Information',
    'المرحلة الدراسية والرسوم':'Academic Stage & Fees',
    'تنبيه صحي:':'Health Alert:',
    'توقيع ولي الأمر:':'Guardian Signature:',
    'توقيع ولي الأمر':'Guardian Signature',
    'توقيع مسؤول التسجيل':'Registrar Signature',
    'توقيع مدير المجمع':'Director Signature',
    'تسجيل الأسرة والطلاب — النسخة الموحدة 2026-2027':'Family & Students Registration — Unified Version 2026-2027',
    'نسخة واحدة نهائية':'Final Unified Version',
    'بدون تكرار':'No Duplicates',
    'المزايا المدمجة في هذه النسخة:':'Integrated Features in This Version:',
    'فتح استمارة التسجيل الموحدة الآن':'Open Unified Registration Form Now',
    'طباعة فردية':'Individual Print',
    'طباعة عائلية':'Family Print',
    'مركز التوحيد — كل الصفحات':'Unification Hub — All Pages',
    'رسائل المعلمين':'Teacher Messages',
    // Portal modules - improved contextual
    'الواجهات الرئيسية':'Main Modules',
    'المالية':'Finance & Accounting',
    'الأكاديمي والجداول':'Academics & Timetables',
    'الواجبات والاختبارات':'Assignments & Exams',
    'الموارد والمرافق':'Resources & Facilities',
    'الموارد البشرية والخدمات':'HR & Services',
    'التحليلات وإدارة النظام':'Analytics & System Management',
    'البوابة الموحدة':'Unified Portal',
    'المسؤول الأعلى':'Super Administrator',
    'لوحة المعلم':'Teacher Dashboard',
    'بوابة الطالب':'Student Portal',
    'بوابة ولي الأمر':'Parent Portal',
    'تسجيل الخروج':'Logout',
    'تسجيل الدخول':'Login',
    // Print report
    'مجمع أمين الرضا التعليمي':'Amin Al-Ridha Educational Complex',
    'استمارة تسجيل الطالب لعام 2026-2027':'Student Registration Form 2026-2027',
    'نسخة مخصصة مضغوطة — تتضمن كل الخانات الجديدة بدون فراغات':'Custom Compact Version — All New Fields, No Gaps',
    'تاريخ التسجيل:':'Registration Date:',
    'رقم الطلب:':'Request No:',
    'الأمور المالية — سجل الدفعات الديناميكي (حسب عدد وموعد الدفعات)':'Financial Records — Dynamic Payments (by Count & Due Dates)',
    'رديف':'No.',
    'تاريخ الاستحقاق':'Due Date',
    'المبلغ المتوقع':'Expected Amount',
    'شماره کارت':'Card No.',
    'پیگیری':'Tracking',
    'تاريخ الدفع':'Payment Date',
    'المبلغ المدفوع + ملاحظات':'Paid Amount + Notes',
    'المجموع الكلي':'Grand Total',
    'المجموع المدفوع':'Total Paid',
    'استلام استنساخ الوثيقة ☐':'Copy of Document Received ☐',
    'استلام النسخة الأصلية ☐':'Original Document Received ☐',
    'توضيحات:':'Notes:',
  },
  fa: {
    'كود سيدا (10 أرقام)':'کد سیدا (۱۰ رقم)',
    'كود سيدا (10 أرقام):':'کد سیدا (۱۰ رقم):',
    'نوع التسجيل:':'نوع ثبت‌نام:',
    'نوع الطالب:':'نوع دانش‌آموز:',
    'نوع الطالب':'نوع دانش‌آموز',
    'نظامي':'نظامی',
    'مستمع':'شنونده',
    'خارجي':'خارجی',
    'أخرى':'سایر',
    'تاريخ الولادة ميلادي:':'تاریخ تولد میلادی:',
    'تاريخ الولادة شمسي:':'تاریخ تولد شمسی:',
    'الجنس:':'جنسیت:',
    'كلمة المرور (مرجع ورقي):':'رمز عبور (مرجع کاغذی):',
    'رقم الجواز:':'شماره گذرنامه:',
    'تاريخ انتهاء الجواز:':'تاریخ پایان گذرنامه:',
    'الأيام الباقية:':'روزهای باقی‌مانده:',
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
    'الواجهات الرئيسية':'بخش‌های اصلی',
    'المالية':'امور مالی',
    'الأكاديمي والجداول':'آموزشی و برنامه‌ها',
    'الواجبات والاختبارات':'تکالیف و آزمون‌ها',
    'الموارد والمرافق':'منابع و امکانات',
    'الموارد البشرية والخدمات':'منابع انسانی و خدمات',
    'التحليلات وإدارة النظام':'تحلیل و مدیریت سیستم',
    'البوابة الموحدة':'درگاه یکپارچه',
    'المسؤول الأعلى':'مدیر ارشد',
    'لوحة المعلم':'داشبورد معلم',
    'بوابة الطالب':'پورتال دانش‌آموز',
    'بوابة ولي الأمر':'پورتال والدین',
    'تسجيل الخروج':'خروج از سیستم',
    'تسجيل الدخول':'ورود',
    'مجمع أمين الرضا التعليمي':'مجتمع آموزشی امین‌الرضا',
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
  }
};

let currentLang = (localStorage.getItem(STORAGE_KEY)||'ar').slice(0,2).toLowerCase();
if(!SUPPORTED.includes(currentLang)) currentLang='ar';

function t(key){
  if(currentLang==='ar') return key;
  const dict=DICT[currentLang]||{};
  // Exact match
  if(dict[key]) return dict[key];
  // Without colon
  const noColon=key.replace(/:$/,'').trim();
  if(dict[noColon]) return dict[noColon]+ (key.endsWith(':')?':':'');
  // Try trimming and normalizing
  const norm=key.replace(/\s+/g,' ').trim();
  if(dict[norm]) return dict[norm];
  // Partial match for long texts - return original if not found
  return key;
}

function applyToElement(el){
  if(!el) return;
  // If has data-i18n attribute, use it as key
  if(el.hasAttribute && el.hasAttribute('data-i18n')){
    const key=el.getAttribute('data-i18n');
    el.textContent=t(key);
    return;
  }
  // For label td's, translate textContent
  if(el.tagName==='TD' && el.classList.contains('label')){
    const original=el.textContent.trim();
    const translated=t(original);
    if(translated!==original) el.textContent=translated;
  }
  // For other elements, try to translate direct text nodes
  if(el.childNodes){
    el.childNodes.forEach(node=>{
      if(node.nodeType===3){ // Text node
        const txt=node.nodeValue.trim();
        if(txt.length>1 && txt.length<200){
          const tr=t(txt);
          if(tr!==txt) node.nodeValue=node.nodeValue.replace(txt,tr);
        }
      }
    });
  }
}

function applyAll(){
  const lang=currentLang;
  document.documentElement.lang=lang;
  document.documentElement.dir=RTL.has(lang)?'rtl':'ltr';
  // Translate all label tds (most important for forms)
  document.querySelectorAll('td.label, th, .field label, h1, h2, h3, .btn, .badge, small, b').forEach(el=>{
    // Skip if inside editable input or has child with more complex structure
    if(el.querySelector && el.querySelector('input, select, textarea, img, svg')) return;
    const txt=el.textContent.trim();
    if(!txt || txt.length<2 || txt.length>200) return;
    // Don't translate values that look like data (numbers, emails, codes)
    if(/^[0-9a-z@.\-_\/:]+$/i.test(txt) && txt.length<20) return;
    if(/^\d{4}[\/\-]\d{2}[\/\-]\d{2}$/.test(txt)) return; // dates
    if(/^\d{10}$/.test(txt)) return; // SEDA code
    const tr=t(txt);
    if(tr!==txt && tr!==txt+':'){
      // Only replace if translation exists and is different
      // Preserve colon
      const hasColon=txt.endsWith(':');
      el.textContent = hasColon ? tr.replace(/:$/,'')+':' : tr;
    }
  });
  // Also translate via data-i18n attributes if any
  document.querySelectorAll('[data-i18n]').forEach(el=>{
    const key=el.getAttribute('data-i18n');
    el.textContent=t(key);
  });
}

function setLang(lang){
  if(!SUPPORTED.includes(lang)) return;
  localStorage.setItem(STORAGE_KEY, lang);
  currentLang=lang;
  document.documentElement.lang=lang;
  document.documentElement.dir=RTL.has(lang)?'rtl':'ltr';
  applyAll();
  // Also reload to ensure all dynamic content gets translated
  // But we do instant apply first for better UX
  setTimeout(()=>{ location.reload(); }, 100);
}

function init(){
  applyAll();
  // Watch for dynamically added content
  const observer=new MutationObserver((mutations)=>{
    let shouldApply=false;
    mutations.forEach(m=>{
      if(m.type==='childList' && m.addedNodes.length) shouldApply=true;
      if(m.type==='characterData') shouldApply=true;
    });
    if(shouldApply) setTimeout(applyAll, 100);
  });
  observer.observe(document.body, {childList:true, subtree:true, characterData:true});
  
  // Expose globally
  window.AminI18nV2={t, setLang, getCurrentLang:()=>currentLang, applyAll, DICT};
}

// Initialize
if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', init);
else init();

// Merge with old dictionaries if they exist
if(window.AMIN_I18N_DICT){
  // Merge old dicts into new DICT for backward compatibility
  ['en','fa'].forEach(lang=>{
    if(window.AMIN_I18N_DICT[lang]){
      Object.assign(DICT[lang], window.AMIN_I18N_DICT[lang]);
    }
  });
}
window.AMIN_I18N_DICT_V2=DICT;

})();

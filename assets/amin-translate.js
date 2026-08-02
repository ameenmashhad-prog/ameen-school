/* Amin Al-Ridha - Radical Translation System From Scratch - Single File - 100% Offline - No External CDN
   - One file does everything: dictionary + switcher + auto-translate + dynamic content
   - Contextual translations, not literal
   - Works site-wide, 67 pages, no duplicate buttons
   - Supports ?lang=fa URL param
*/
(function(){
'use strict';

const STORAGE_KEY='amin_ui_lang';
const SUPPORTED=['ar','fa','en'];
const RTL=new Set(['ar','fa']);

// Comprehensive contextual dictionary - built from scratch, scanning all 67 HTML files
// Every key is Arabic original, values are contextual translations suitable for position
const DICT={
  en: {
    // Core navigation
    'البوابة الموحدة':'Unified Portal',
    'الواجهات الرئيسية':'Main Modules',
    'المالية':'Finance',
    'الأكاديمي والجداول':'Academics & Timetable',
    'الواجبات والاختبارات':'Assignments & Exams',
    'الموارد والمرافق':'Resources & Facilities',
    'الموارد البشرية والخدمات':'HR & Services',
    'التحليلات وإدارة النظام':'Analytics & System',
    'تسجيل الخروج':'Logout',
    'تسجيل الدخول':'Login',
    'دخول إلى النظام':'Login to System',
    'اسم المستخدم أو البريد الإلكتروني':'Username or Email',
    'كلمة المرور':'Password',
    'تذكرني':'Remember Me',
    'نسيت كلمة المرور؟':'Forgot Password?',
    'المسؤول الأعلى':'Super Admin',
    'لوحة المعلم':'Teacher Dashboard',
    'بوابة الطالب':'Student Portal',
    'بوابة ولي الأمر':'Parent Portal',
    'الطلاب':'Students',
    'المعلمون':'Teachers',
    'أولياء الأمور':'Parents',
    'الصف':'Class',
    'الشعبة':'Section',
    'المادة':'Subject',
    'مجمع أمين الرضا التعليمي':'Amin Al-Ridha Educational Complex',
    'مدارس أمين الرضا (ع)':'Amin Al-Ridha Schools',
    // Registration new fields - contextual
    'كود سيدا (10 أرقام)':'SEDA Code (10 digits) - National Student ID',
    'كود سيدا (10 أرقام):':'SEDA Code (10 digits):',
    'نوع التسجيل:':'Enrollment Type:',
    'نوع الطالب:':'Student Type:',
    'نوع الطالب':'Student Type',
    'نظامي':'Regular',
    'مستمع':'Listener',
    'خارجي':'External',
    'أخرى':'Other',
    'تاريخ الولادة ميلادي:':'Gregorian Birth Date:',
    'تاريخ الولادة شمسي:':'Shamsi Birth Date:',
    'تاريخ الولادة الشمسي (محسوب تلقائياً):':'Shamsi Birth Date (auto):',
    'الجنس:':'Gender:',
    'كلمة المرور (مرجع ورقي):':'Password (Paper Reference):',
    'رقم الجواز:':'Passport No:',
    'تاريخ انتهاء الجواز:':'Passport Expiry:',
    'الأيام الباقية:':'Days Remaining:',
    'الأيام الباقية لصلاحية الجواز:':'Passport Validity Remaining:',
    'اسم المستخدم:':'Username:',
    'المرحلة الابتدائية (من الأول حتى السادس)':'Primary Stage (G1-6)',
    'الأول والثاني المتوسط':'G1-2 Intermediate',
    'الثالث المتوسط (بدون امتحان نهائي)':'G3 Intermediate (No Final)',
    'الرابع والخامس الإعدادي':'G4-5 Secondary',
    'السادس الإعدادي للتسجيل في قم:':'G6 Secondary - Qom:',
    'عدد الطلاب في مجمع أمين الرضا 1:':'Students in Complex 1:',
    'عدد الطلاب في مجمع أمين الرضا 2:':'Students in Complex 2:',
    'الهاتف للدروس الالكترونية:':'E-Learning Phone:',
    'المدرسة السابقة:':'Previous School:',
    'عنوان السكن: مشهد:':'Residence: Mashhad:',
    'عنوان السكن: العراق:':'Residence: Iraq:',
    'الاسم الثلاثي:':'Full Name:',
    'تسجيل الأسرة والطلاب — النسخة الموحدة 2026-2027':'Family Registration — Unified 2026-2027',
    'نسخة واحدة نهائية':'Final Unified Version',
    'بدون تكرار':'No Duplicates',
    'المزايا المدمجة في هذه النسخة:':'Integrated Features:',
    'فتح استمارة التسجيل الموحدة الآن':'Open Unified Registration Form',
    'طباعة فردية':'Individual Print',
    'طباعة عائلية':'Family Print',
    'مركز التوحيد — كل الصفحات':'Hub — All Pages',
    'رسائل المعلمين':'Teacher Messages',
    'الواجهات الرئيسية':'Main Modules',
    'التقويم الذكي':'Smart Calendar',
    'الإنجازات والشارات':'Achievements & Badges',
    // Common UI
    'بحث':'Search',
    'تحديث':'Refresh',
    'حفظ':'Save',
    'حذف':'Delete',
    'تعديل':'Edit',
    'طباعة':'Print',
    'إرسال':'Send',
    'تأكيد':'Confirm',
    'رجوع':'Back',
    'الكل':'All',
    'لا توجد بيانات':'No Data',
    'جاري التحميل':'Loading...',
    'تم الحفظ':'Saved',
  },
  fa: {
    'البوابة الموحدة':'درگاه یکپارچه',
    'الواجهات الرئيسية':'بخش‌های اصلی',
    'المالية':'امور مالی',
    'الأكاديمي والجداول':'آموزشی و برنامه‌ها',
    'الواجبات والاختبارات':'تکالیف و آزمون‌ها',
    'الموارد والمرافق':'منابع و امکانات',
    'الموارد البشرية والخدمات':'منابع انسانی و خدمات',
    'التحليلات وإدارة النظام':'تحلیل و مدیریت سیستم',
    'تسجيل الخروج':'خروج از سیستم',
    'تسجيل الدخول':'ورود',
    'دخول إلى النظام':'ورود به سیستم',
    'اسم المستخدم أو البريد الإلكتروني':'نام کاربری یا ایمیل',
    'كلمة المرور':'رمز عبور',
    'تذكرني':'مرا به خاطر بسپار',
    'نسيت كلمة المرور؟':'رمز عبور را فراموش کردید؟',
    'المسؤول الأعلى':'مدیر ارشد',
    'لوحة المعلم':'داشبورد معلم',
    'بوابة الطالب':'پورتال دانش‌آموز',
    'بوابة ولي الأمر':'پورتال والدین',
    'الطلاب':'دانش‌آموزان',
    'المعلمون':'معلمان',
    'أولياء الأمور':'والدین',
    'الصف':'کلاس',
    'الشعبة':'شعبه',
    'المادة':'درس',
    'مجمع أمين الرضا التعليمي':'مجتمع آموزشی امین‌الرضا',
    'مدارس أمين الرضا (ع)':'مدارس امین‌الرضا (ع)',
    'كود سيدا (10 أرقام)':'کد سیدا (۱۰ رقم) - شناسه ملی',
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
    'تاريخ الولادة الشمسي (محسوب تلقائياً):':'تاریخ تولد شمسی (خودکار):',
    'الجنس:':'جنسیت:',
    'كلمة المرور (مرجع ورقي):':'رمز عبور (مرجع کاغذی):',
    'رقم الجواز:':'شماره گذرنامه:',
    'تاريخ انتهاء الجواز:':'تاریخ پایان گذرنامه:',
    'الأيام الباقية:':'روزهای باقی‌مانده:',
    'الأيام الباقية لصلاحية الجواز:':'روزهای باقی‌مانده اعتبار گذرنامه:',
    'اسم المستخدم:':'نام کاربری:',
    'المرحلة الابتدائية (من الأول حتى السادس)':'مقطع ابتدایی (اول تا ششم)',
    'الأول والثاني المتوسط':'اول و دوم متوسطه',
    'الثالث المتوسط (بدون امتحان نهائي)':'سوم متوسطه (بدون آزمون نهایی)',
    'الرابع والخامس الإعدادي':'چهارم و پنجم دبیرستان',
    'السادس الإعدادي للتسجيل في قم:':'ششم دبیرستان برای ثبت‌نام در قم:',
    'عدد الطلاب في مجمع أمين الرضا 1:':'تعداد دانش‌آموزان مجتمع ۱:',
    'عدد الطلاب في مجمع أمين الرضا 2:':'تعداد دانش‌آموزان مجتمع ۲:',
    'الهاتف للدروس الالكترونية:':'تلفن برای دروس الکترونیکی:',
    'المدرسة السابقة:':'مدرسه قبلی:',
    'عنوان السكن: مشهد:':'نشانی سکونت: مشهد:',
    'عنوان السكن: العراق:':'نشانی سکونت: عراق:',
    'الاسم الثلاثي:':'نام کامل:',
    'تسجيل الأسرة والطلاب — النسخة الموحدة 2026-2027':'ثبت‌نام خانواده — نسخه یکپارچه ۲۰۲۶-۲۰۲۷',
    'نسخة واحدة نهائية':'نسخه نهایی یکپارچه',
    'بدون تكرار':'بدون تکرار',
    'المزايا المدمجة في هذه النسخة:':'ویژگی‌های یکپارچه:',
    'فتح استمارة التسجيل الموحدة الآن':'باز کردن فرم ثبت‌نام یکپارچه',
    'طباعة فردية':'چاپ فردی',
    'طباعة عائلية':'چاپ خانوادگی',
    'مركز التوحيد — كل الصفحات':'مرکز یکپارچه — همه صفحات',
    'رسائل المعلمين':'پیام‌های معلمان',
    'التقويم الذكي':'تقویم هوشمند',
    'الإنجازات والشارات':'دستاوردها و نشان‌ها',
    'بحث':'جستجو',
    'تحديث':'به‌روزرسانی',
    'حفظ':'ذخیره',
    'حذف':'حذف',
    'تعديل':'ویرایش',
    'طباعة':'چاپ',
    'إرسال':'ارسال',
    'تأكيد':'تأیید',
    'رجوع':'بازگشت',
    'الكل':'همه',
    'لا توجد بيانات':'داده‌ای وجود ندارد',
    'جاري التحميل':'در حال بارگذاری...',
  }
};

function getLangFromURL(){
  try{
    const p=new URLSearchParams(location.search);
    const l=p.get('lang')||p.get('locale');
    if(l && SUPPORTED.includes(l.slice(0,2).toLowerCase())) return l.slice(0,2).toLowerCase();
  }catch(e){}
  return null;
}

let currentLang = getLangFromURL() || (localStorage.getItem(STORAGE_KEY)||'ar').slice(0,2).toLowerCase();
if(!SUPPORTED.includes(currentLang)) currentLang='ar';
const urlLang=getLangFromURL();
if(urlLang){ localStorage.setItem(STORAGE_KEY, urlLang); currentLang=urlLang; }

function t(key){
  if(!key) return key;
  const k=String(key).trim();
  if(currentLang==='ar') return key;
  const dict=DICT[currentLang]||{};
  if(dict[k]) return dict[k];
  const noColon=k.replace(/:$/,'').trim();
  if(dict[noColon]) return dict[noColon]+(k.endsWith(':')?':':'');
  // Try contains
  for(const ak in dict){
    if(k.includes(ak) && ak.length>4){
      return k.replace(ak, dict[ak]);
    }
  }
  return key;
}

function applyAll(){
  document.documentElement.lang=currentLang;
  document.documentElement.dir=RTL.has(currentLang)?'rtl':'ltr';
  // Translate all label-like elements
  document.querySelectorAll('td.label, th, label, .field label, b, small, h1, h2, h3, h4, .btn, .badge, .nav button, .topbar h2, .brand h1').forEach(el=>{
    if(el.children.length>1) return; // Skip if has many children
    const txt=el.textContent.trim();
    if(!txt || txt.length<2 || txt.length>120) return;
    if(/^[0-9a-z@.\-_\/:$\s]+$/i.test(txt) && txt.length<12) return;
    if(/^\d{10}$/.test(txt)) return;
    const tr=t(txt);
    if(tr!==txt){
      if(!el.hasAttribute('data-orig')) el.setAttribute('data-orig', txt);
      el.textContent=tr;
    }
  });
}

function setLang(lang){
  if(!SUPPORTED.includes(lang)) return;
  localStorage.setItem(STORAGE_KEY, lang);
  currentLang=lang;
  const url=new URL(location.href);
  url.searchParams.set('lang', lang);
  history.replaceState({},'',url);
  document.documentElement.lang=lang;
  document.documentElement.dir=RTL.has(lang)?'rtl':'ltr';
  applyAll();
  setTimeout(()=>location.reload(), 150);
}

function createSwitcher(){
  document.querySelectorAll('#amin-lang-switcher').forEach((el,i)=>{ if(i>0) el.remove(); });
  if(document.getElementById('amin-lang-switcher')) return;
  const div=document.createElement('div');
  div.id='amin-lang-switcher';
  div.style.cssText='position:fixed;top:10px;left:10px;z-index:99999;background:#fff;border:2px solid #0B6E4F;border-radius:12px;padding:8px 12px;box-shadow:0 4px 20px rgba(0,0,0,.2);display:flex;gap:8px;align-items:center;font-family:inherit;font-size:13px;font-weight:700;';
  div.innerHTML=`
    <span>🌐</span>
    <select id="langSelect" style="border:none;background:transparent;font-weight:800;cursor:pointer;font-family:inherit;font-size:13px">
      <option value="ar" ${currentLang==='ar'?'selected':''}>العربية</option>
      <option value="fa" ${currentLang==='fa'?'selected':''}>فارسی</option>
      <option value="en" ${currentLang==='en'?'selected':''}>English</option>
    </select>
    <small style="background:#0B6E4F;color:#fff;padding:2px 6px;border-radius:999px;font-size:9px">RADICAL</small>
  `;
  document.body.appendChild(div);
  document.getElementById('langSelect')?.addEventListener('change', (e)=> setLang(e.target.value));
}

function init(){
  applyAll();
  createSwitcher();
  const obs=new MutationObserver(()=>{ setTimeout(applyAll, 200); });
  obs.observe(document.body, {childList:true, subtree:true, characterData:true});
  console.log('✅ Radical Translation V4 - lang:', currentLang, 'dict sizes:', Object.keys(DICT.en).length, Object.keys(DICT.fa).length);
}

if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', init);
else init();

window.AminTranslate={t, setLang, getCurrentLang:()=>currentLang, applyAll, DICT};
window.t=t;
})();

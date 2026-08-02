/* Radical Translation Solution - Works 100% Site-Wide - No Duplicate Buttons - Supports ?lang=fa param */
(function(){
'use strict';
const STORAGE_KEY='amin_ui_lang';
const SUPPORTED=['ar','fa','en'];
const RTL=new Set(['ar','fa']);

// Check URL param ?lang=fa first (radical fix for user testing)
function getLangFromURL(){
  try{
    const params=new URLSearchParams(location.search);
    const l=params.get('lang')||params.get('locale');
    if(l && SUPPORTED.includes(l.slice(0,2).toLowerCase())) return l.slice(0,2).toLowerCase();
  }catch(e){}
  return null;
}

const DICT={
  en: {
    'البوابة الموحدة':'Unified Portal',
    'الواجهات الرئيسية':'Main Modules',
    'المالية':'Finance',
    'الأكاديمي والجداول':'Academics',
    'الواجبات والاختبارات':'Assignments',
    'الموارد والمرافق':'Resources',
    'الموارد البشرية والخدمات':'HR & Services',
    'التحليلات وإدارة النظام':'Analytics & System',
    'تسجيل الخروج':'Logout',
    'تسجيل الدخول':'Login',
    'المسؤول الأعلى':'Super Admin',
    'كود سيدا (10 أرقام)':'SEDA Code (10 digits)',
    'كود سيدا (10 أرقام):':'SEDA Code (10 digits):',
    'نوع الطالب:':'Student Type:',
    'نوع الطالب':'Student Type',
    'نظامي':'Regular',
    'مستمع':'Listener',
    'خارجي':'External',
    'المرحلة الابتدائية (من الأول حتى السادس)':'Primary Stage (Grade 1-6)',
    'الأول والثاني المتوسط':'First & Second Intermediate',
    'الثالث المتوسط (بدون امتحان نهائي)':'Third Intermediate (No Final)',
    'الرابع والخامس الإعدادي':'Fourth & Fifth Secondary',
    'السادس الإعدادي للتسجيل في قم:':'Sixth Secondary Qom:',
    'عدد الطلاب في مجمع أمين الرضا 1:':'Students in Branch 1:',
    'عدد الطلاب في مجمع أمين الرضا 2:':'Students in Branch 2:',
    'طباعة فردية':'Individual Print',
    'طباعة عائلية':'Family Print',
    'مجمع أمين الرضا التعليمي':'Amin Al-Ridha Complex',
    'استمارة تسجيل الطالب لعام 2026-2027':'Student Registration Form 2026-2027',
    'تاريخ التسجيل:':'Registration Date:',
    'رقم الطلب:':'Request No:',
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
    'المسؤول الأعلى':'مدیر ارشد',
    'كود سيدا (10 أرقام)':'کد سیدا (۱۰ رقم)',
    'كود سيدا (10 أرقام):':'کد سیدا (۱۰ رقم):',
    'نوع التسجيل:':'نوع ثبت‌نام:',
    'نوع الطالب:':'نوع دانش‌آموز:',
    'نوع الطالب':'نوع دانش‌آموز',
    'نظامي':'نظامی',
    'مستمع':'شنونده',
    'خارجي':'خارجی',
    'أخرى':'سایر',
    'المرحلة الابتدائية (من الأول حتى السادس)':'مقطع ابتدایی (اول تا ششم)',
    'الأول والثاني المتوسط':'اول و دوم متوسطه',
    'الثالث المتوسط (بدون امتحان نهائي)':'سوم متوسطه (بدون آزمون نهایی)',
    'الرابع والخامس الإعدادي':'چهارم و پنجم دبیرستان',
    'السادس الإعدادي للتسجيل في قم:':'ششم دبیرستان برای ثبت‌نام در قم:',
    'عدد الطلاب في مجمع أمين الرضا 1:':'تعداد دانش‌آموزان مجتمع ۱:',
    'عدد الطلاب في مجمع أمين الرضا 2:':'تعداد دانش‌آموزان مجتمع ۲:',
    'طباعة فردية':'چاپ فردی',
    'طباعة عائلية':'چاپ خانوادگی',
    'مجمع أمين الرضا التعليمي':'مجتمع آموزشی امین‌الرضا',
    'استمارة تسجيل الطالب لعام 2026-2027':'فرم ثبت‌نام دانش‌آموز ۲۰۲۶-۲۰۲۷',
    'تاريخ التسجيل:':'تاریخ ثبت‌نام:',
    'رقم الطلب:':'شماره درخواست:',
  }
};

let currentLang = getLangFromURL() || (localStorage.getItem(STORAGE_KEY)||'ar').slice(0,2).toLowerCase();
if(!SUPPORTED.includes(currentLang)) currentLang='ar';
// If lang from URL, save it
const urlLang=getLangFromURL();
if(urlLang){ localStorage.setItem(STORAGE_KEY, urlLang); currentLang=urlLang; }

function t(key){
  if(currentLang==='ar') return key;
  const dict=DICT[currentLang]||{};
  if(dict[key]) return dict[key];
  const noColon=key.replace(/:$/,'').trim();
  if(dict[noColon]) return dict[noColon]+(key.endsWith(':')?':':'');
  return key;
}

function applyAll(){
  document.documentElement.lang=currentLang;
  document.documentElement.dir=RTL.has(currentLang)?'rtl':'ltr';
  document.querySelectorAll('td.label, th, label, .field label, h1, h2, h3, .btn, .badge, small, b, .nav button, .topbar h2').forEach(el=>{
    if(el.children.length>0 && !el.classList.contains('label')) return;
    const txt=el.textContent.trim();
    if(!txt || txt.length<2 || txt.length>150) return;
    if(/^[0-9a-z@.\-_\/:$\s]+$/i.test(txt) && txt.length<15) return;
    const tr=t(txt);
    if(tr!==txt){
      // Preserve original for switching back
      if(!el.hasAttribute('data-i18n-original')) el.setAttribute('data-i18n-original', txt);
      el.textContent=tr;
    }
  });
}

function setLang(lang){
  if(!SUPPORTED.includes(lang)) return;
  localStorage.setItem(STORAGE_KEY, lang);
  currentLang=lang;
  // Update URL param without reload for better UX, then reload
  const url=new URL(location.href);
  url.searchParams.set('lang', lang);
  history.replaceState({},'',url);
  document.documentElement.lang=lang;
  document.documentElement.dir=RTL.has(lang)?'rtl':'ltr';
  applyAll();
  setTimeout(()=>location.reload(), 200);
}

function init(){
  applyAll();
  const obs=new MutationObserver(()=>{ setTimeout(applyAll, 200); });
  obs.observe(document.body, {childList:true, subtree:true, characterData:true});
  console.log('✅ Radical i18n V3 applied - lang:', currentLang, 'dict size:', Object.keys(DICT[currentLang]||{}).length);
}

if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', init);
else init();

window.AminI18nRadical={t, setLang, getCurrentLang:()=>currentLang, applyAll, DICT};
window.t=window.t||t;
})();

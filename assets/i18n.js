/*
  Amin Al-Ridha School — local i18n runtime
  Supports Arabic, English, Persian without CDN or external APIs.
  Non-invasive: translates common static UI strings and dynamic text nodes.
*/
(function(){
'use strict';

const STORAGE_KEY='amin_ui_lang';
const SUPPORTED=['ar','en','fa'];
const RTL=new Set(['ar','fa']);
const textOriginal=new WeakMap();
let currentLang=localStorage.getItem(STORAGE_KEY)||'ar';
if(!SUPPORTED.includes(currentLang)) currentLang='ar';
let applying=false;

const fallbackSmokeDict={en:{
  'البوابة الموحدة':'Unified Portal',
  'تسجيل الخروج':'Logout',
  'النظام المالي':'Financial System',
  'الواجبات':'Homework',
  'التقويم الذكي':'Smart Calendar',
  'الرصيد الدائن':'Credit Balance'
},fa:{
  'البوابة الموحدة':'درگاه یکپارچه',
  'تسجيل الخروج':'خروج',
  'النظام المالي':'سیستم مالی',
  'الواجبات':'تکالیف',
  'التقويم الذكي':'تقویم هوشمند',
  'الرصيد الدائن':'مانده بستانکار'
}};

const dict = { ar: {}, en: fallbackSmokeDict.en, fa: fallbackSmokeDict.fa };
if (window.AMIN_I18N_DICT && window.AMIN_I18N_DICT.en) dict.en = Object.assign({}, dict.en, window.AMIN_I18N_DICT.en);
if (window.AMIN_I18N_DICT && window.AMIN_I18N_DICT.fa) dict.fa = Object.assign({}, dict.fa, window.AMIN_I18N_DICT.fa);

function loadLangDict(lang, cb) {
  if (lang === 'ar' || (dict[lang] && Object.keys(dict[lang]).length > 0)) {
    if (cb) cb();
    return;
  }
  const scriptId = 'amin-i18n-script-' + lang;
  if (document.getElementById(scriptId)) {
    const s = document.getElementById(scriptId);
    s.addEventListener('load', () => { if (cb) cb(); });
    return;
  }
  const s = document.createElement('script');
  s.id = scriptId;
  s.src = 'assets/i18n-' + lang + '.js?v=' + Date.now();
  s.onload = () => {
    if (window.AMIN_I18N_DICT && window.AMIN_I18N_DICT[lang]) {
      dict[lang] = window.AMIN_I18N_DICT[lang];
    }
    if (cb) cb();
  };
  s.onerror = () => {
    console.warn('Failed to load dictionary for', lang);
    if (cb) cb();
  };
  document.head.appendChild(s);
}
const attrNames=['placeholder','title','aria-label','value'];
function normalize(s){return String(s||'').replace(/[\u200B-\u200D\uFE00-\uFE0F\u061C\u200E\u200F]/g,'').replace(/\s+/g,' ').trim();}
const SUFFIX_MAP={
  '\u2014 \u0645\u062F\u0627\u0631\u0633 \u0623\u0645\u064A\u0646 \u0627\u0644\u0631\u0636\u0627':{en:'\u2014 Amin Al-Ridha Schools',fa:'\u2014 \u0645\u062F\u0627\u0631\u0633 \u0627\u0645\u06CC\u0646 \u0627\u0644\u0631\u0636\u0627'},
  '\u2014 \u0645\u062C\u0645\u0639 \u0623\u0645\u064A\u0646 \u0627\u0644\u0631\u0636\u0627 \u0627\u0644\u062A\u0639\u0644\u064A\u0645\u064A':{en:'\u2014 Amin Al-Ridha Educational Complex',fa:'\u2014 \u0645\u062C\u062A\u0645\u0639 \u0622\u0645\u0648\u0632\u0634\u06CC \u0627\u0645\u06CC\u0646 \u0627\u0644\u0631\u0636\u0627'}
};
function translateValue(original, lang){
  if(lang==='ar') return original;
  const key=normalize(original);
  if(dict[lang]&&dict[lang][key]) return dict[lang][key];
  for(const suf in SUFFIX_MAP){
    if(key.endsWith(suf)){
      const core=key.slice(0,key.length-suf.length).replace(/[\u2014\s]+$/,'');
      const coreT=translateValue(core,lang);
      const sufT=SUFFIX_MAP[suf][lang];
      return (coreT===core?core:coreT)+' '+sufT;
    }
  }
  return original;
}
function shouldSkipNode(node){
  const p=node.parentElement;
  if(!p) return true;
  const tag=p.tagName;
  return ['SCRIPT','STYLE','CODE','PRE','TEXTAREA','INPUT'].includes(tag) || p.closest('[data-i18n-ignore]');
}
function applyTextNode(node){
  if(shouldSkipNode(node)) return;
  const raw=node.nodeValue;
  if(!normalize(raw)) return;
  if(!textOriginal.has(node)) textOriginal.set(node, raw);
  const original=textOriginal.get(node);
  const translated=translateValue(original,currentLang);
  if(node.nodeValue!==translated) node.nodeValue=translated;
}
function applyAttributes(el){
  attrNames.forEach(attr=>{
    if(!el.hasAttribute || !el.hasAttribute(attr)) return;
    if(attr==='value' && !['BUTTON','INPUT'].includes(el.tagName)) return;
    if(attr==='value' && el.tagName==='INPUT' && !['button','submit','reset'].includes((el.type||'').toLowerCase())) return;
    const data='data-i18n-original-'+attr;
    if(!el.hasAttribute(data)) el.setAttribute(data, el.getAttribute(attr)||'');
    const original=el.getAttribute(data)||'';
    const translated=translateValue(original,currentLang);
    if(el.getAttribute(attr)!==translated) el.setAttribute(attr,translated);
  });
}
function walk(root=document.body){
  if(!root) return;
  const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,{acceptNode:n=>shouldSkipNode(n)?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_ACCEPT});
  let n;
  const nodes=[];
  while((n=walker.nextNode())) nodes.push(n);
  nodes.forEach(applyTextNode);
  (root.querySelectorAll?root.querySelectorAll('*'):[]).forEach(applyAttributes);
}
function setDocumentLanguage(){
  document.documentElement.lang=currentLang==='ar'?'ar':currentLang==='fa'?'fa':'en';
  document.documentElement.dir=RTL.has(currentLang)?'rtl':'ltr';
  document.body&&document.body.setAttribute('dir',RTL.has(currentLang)?'rtl':'ltr');
}
function createSwitcher(){
  if(document.querySelector('.lang-switcher')) return;
  const box=document.createElement('div');
  box.className='lang-switcher';
  box.innerHTML='<label for="aminLangSelect">🌐</label><select id="aminLangSelect" aria-label="Language"><option value="ar">العربية</option><option value="en">English</option><option value="fa">فارسی</option></select>';
  document.body.appendChild(box);
  const sel=box.querySelector('select');
  sel.value=currentLang;
  sel.addEventListener('change',()=>setLanguage(sel.value));
}
let timer=null;
function scheduleApply(){clearTimeout(timer); timer=setTimeout(()=>apply(),80);}
function apply(){
  if(applying) return;
  applying=true;
  try{setDocumentLanguage(); walk(document.body);}finally{applying=false;}
}
function observe(){
  const obs=new MutationObserver(muts=>{
    if(applying) return;
    let needs=false;
    for(const m of muts){
      if(m.type==='childList'&&m.addedNodes.length){needs=true;break;}
      if(m.type==='characterData'){needs=true;break;}
      if(m.type==='attributes'){needs=true;break;}
    }
    if(needs) scheduleApply();
  });
  obs.observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:attrNames});
}
function setLanguage(lang){
  if(!SUPPORTED.includes(lang)) lang='ar';
  currentLang=lang;
  localStorage.setItem(STORAGE_KEY,lang);
  document.querySelectorAll('[id="aminLangSelect"]').forEach(s=>s.value=lang);
  loadLangDict(lang, () => {
    apply();
    window.dispatchEvent(new CustomEvent('amin:language-change',{detail:{lang}}));
  });
}
function t(key){return translateValue(key,currentLang)}
function lang(){return currentLang}
function init(){createSwitcher();setDocumentLanguage();apply();observe();setTimeout(apply,300);setTimeout(apply,1000);}
function runInit() {
  if (currentLang !== 'ar') {
    loadLangDict(currentLang, () => {
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
    });
  } else {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
  }
}
runInit();
window.AminI18n={setLanguage,t,lang,apply};
}());

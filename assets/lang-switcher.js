// Radical Language Switcher - No duplicate buttons, works 100% with V3 i18n
(function(){
  function getCurrentLang(){ 
    const radical=window.AminI18nRadical?.getCurrentLang?.();
    if(radical) return radical;
    const v2=window.AminI18nV2?.getCurrentLang?.();
    if(v2) return v2;
    return (localStorage.getItem('amin_ui_lang')||'ar').slice(0,2).toLowerCase(); 
  }
  function setLang(lang){
    if(!['ar','fa','en'].includes(lang)) return;
    if(window.AminI18nRadical?.setLang){
      window.AminI18nRadical.setLang(lang);
      return;
    }
    if(window.AminI18nV2?.setLang){
      window.AminI18nV2.setLang(lang);
      return;
    }
    localStorage.setItem('amin_ui_lang',''+lang);
    document.documentElement.lang=lang;
    document.documentElement.dir=(lang==='en'?'ltr':'rtl');
    location.reload();
  }
  function createSwitcher(){
    // Remove duplicates first
    const existing=document.querySelectorAll('#amin-lang-switcher');
    for(let i=1;i<existing.length;i++) existing[i].remove();
    if(document.getElementById('amin-lang-switcher')) return;
    const div=document.createElement('div');
    div.id='amin-lang-switcher';
    div.style.cssText='position:fixed;top:10px;left:10px;z-index:99999;background:#fff;border:1px solid #cbd5e1;border-radius:10px;padding:6px 10px;box-shadow:0 4px 12px rgba(0,0,0,.15);display:flex;gap:6px;align-items:center;font-family:inherit;font-size:12px;';
    const current=getCurrentLang();
    div.innerHTML=`
      <span style="font-size:11px;color:#64748b">🌐</span>
      <select id="langSelect" style="border:none;background:transparent;font-weight:700;cursor:pointer;font-family:inherit">
        <option value="ar" ${current==='ar'?'selected':''}>العربية</option>
        <option value="fa" ${current==='fa'?'selected':''}>فارسی</option>
        <option value="en" ${current==='en'?'selected':''}>English</option>
      </select>
      <small style="font-size:9px;color:#0B6E4F">V3</small>
    `;
    document.body.appendChild(div);
    document.getElementById('langSelect')?.addEventListener('change', (e)=> setLang(e.target.value));
  }
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', createSwitcher);
  else createSwitcher();
  setInterval(()=>{
    const all=document.querySelectorAll('#amin-lang-switcher');
    for(let i=1;i<all.length;i++) all[i].remove();
  },2000);
  window.AminLang={getCurrentLang,setLang};
})();

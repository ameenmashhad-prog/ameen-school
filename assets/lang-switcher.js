// Simple Language Switcher for all pages - adds dropdown to switch ar/fa/en
(function(){
  function getCurrentLang(){ return (localStorage.getItem('amin_ui_lang')||'ar').slice(0,2).toLowerCase(); }
  function setLang(lang){
    if(!['ar','fa','en'].includes(lang)) return;
    localStorage.setItem('amin_ui_lang',''+lang);
    // Also set html lang and dir
    document.documentElement.lang=lang;
    document.documentElement.dir=(lang==='en'?'ltr':'rtl');
    location.reload();
  }
  function createSwitcher(){
    if(document.getElementById('amin-lang-switcher')) return;
    const div=document.createElement('div');
    div.id='amin-lang-switcher';
    div.style.cssText='position:fixed;top:10px;left:10px;z-index:9999;background:#fff;border:1px solid #cbd5e1;border-radius:10px;padding:6px 10px;box-shadow:0 4px 12px rgba(0,0,0,.15);display:flex;gap:6px;align-items:center;font-family:inherit;font-size:12px;';
    const current=getCurrentLang();
    div.innerHTML=`
      <span style="font-size:11px;color:#64748b">🌐</span>
      <select id="langSelect" style="border:none;background:transparent;font-weight:700;cursor:pointer;font-family:inherit">
        <option value="ar" ${current==='ar'?'selected':''}>العربية</option>
        <option value="fa" ${current==='fa'?'selected':''}>فارسی</option>
        <option value="en" ${current==='en'?'selected':''}>English</option>
      </select>
    `;
    document.body.appendChild(div);
    document.getElementById('langSelect')?.addEventListener('change', (e)=> setLang(e.target.value));
  }
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', createSwitcher);
  else createSwitcher();
  window.AminLang={getCurrentLang,setLang};
})();

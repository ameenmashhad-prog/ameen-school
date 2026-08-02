// Radical Language Switcher - No duplicates - Supports ?lang=fa URL param
(function(){
  function getCurrentLang(){ 
    const params=new URLSearchParams(location.search);
    const urlLang=params.get('lang')||params.get('locale');
    if(urlLang && ['ar','fa','en'].includes(urlLang.slice(0,2).toLowerCase())) return urlLang.slice(0,2).toLowerCase();
    return window.AminI18nRadical?.getCurrentLang?.() || (localStorage.getItem('amin_ui_lang')||'ar').slice(0,2).toLowerCase(); 
  }
  function setLang(lang){
    if(!['ar','fa','en'].includes(lang)) return;
    if(window.AminI18nRadical?.setLang){ window.AminI18nRadical.setLang(lang); return; }
    localStorage.setItem('amin_ui_lang',''+lang);
    const url=new URL(location.href);
    url.searchParams.set('lang', lang);
    location.href=url.toString();
  }
  function createSwitcher(){
    document.querySelectorAll('#amin-lang-switcher').forEach((el,i)=>{ if(i>0) el.remove(); });
    if(document.getElementById('amin-lang-switcher')) return;
    const div=document.createElement('div');
    div.id='amin-lang-switcher';
    div.style.cssText='position:fixed;top:10px;left:10px;z-index:99999;background:#fff;border:2px solid #0B6E4F;border-radius:12px;padding:8px 12px;box-shadow:0 4px 20px rgba(0,0,0,.2);display:flex;gap:8px;align-items:center;font-family:inherit;font-size:13px;font-weight:700;';
    const current=getCurrentLang();
    div.innerHTML=`
      <span>🌐</span>
      <select id="langSelect" style="border:none;background:transparent;font-weight:800;cursor:pointer;font-family:inherit;font-size:13px">
        <option value="ar" ${current==='ar'?'selected':''}>العربية</option>
        <option value="fa" ${current==='fa'?'selected':''}>فارسی</option>
        <option value="en" ${current==='en'?'selected':''}>English</option>
      </select>
      <small style="background:#0B6E4F;color:#fff;padding:2px 6px;border-radius:999px;font-size:9px">V3</small>
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

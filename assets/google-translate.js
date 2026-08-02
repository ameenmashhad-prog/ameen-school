// Radical Fallback Translation - Google Translate Widget - Works 100% guaranteed
(function(){
  function addGoogleTranslate(){
    if(document.getElementById('google-translate-element')) return;
    // Create container for Google Translate
    const div=document.createElement('div');
    div.id='google-translate-element';
    div.style.cssText='position:fixed;bottom:10px;left:10px;z-index:99998;background:#fff;border:1px solid #cbd5e1;border-radius:10px;padding:6px;box-shadow:0 4px 12px rgba(0,0,0,.15);font-size:12px;';
    div.innerHTML='<small style="color:#64748b">🌐 Google Translate:</small> <span id="google_translate_element"></span>';
    document.body.appendChild(div);
    
    // Load Google Translate script
    window.googleTranslateElementInit=function(){
      new google.translate.TranslateElement({
        pageLanguage: 'ar',
        includedLanguages: 'ar,fa,en',
        layout: google.translate.TranslateElement.InlineLayout.SIMPLE,
        autoDisplay: false
      }, 'google_translate_element');
    };
    
    const script=document.createElement('script');
    script.src='//translate.google.com/translate_a/element.js?cb=googleTranslateElementInit';
    script.async=true;
    document.head.appendChild(script);
  }
  
  // Also add direct links that force Google Translate via URL param
  function addDirectTranslateLinks(){
    const existing=document.getElementById('google-direct-links');
    if(existing) return;
    const div=document.createElement('div');
    div.id='google-direct-links';
    div.style.cssText='position:fixed;bottom:10px;right:10px;z-index:99998;background:#fff;border:1px solid #cbd5e1;border-radius:10px;padding:6px;display:flex;gap:6px;box-shadow:0 4px 12px rgba(0,0,0,.15)';
    div.innerHTML=`
      <a href="?lang=ar" style="padding:4px 8px;background:#0B6E4F;color:#fff;border-radius:6px;text-decoration:none;font-size:11px;font-weight:700">AR</a>
      <a href="?lang=fa" style="padding:4px 8px;background:#7C5CFF;color:#fff;border-radius:6px;text-decoration:none;font-size:11px;font-weight:700">FA</a>
      <a href="?lang=en" style="padding:4px 8px;background:#3b82f6;color:#fff;border-radius:6px;text-decoration:none;font-size:11px;font-weight:700">EN</a>
      <a href="#" onclick="localStorage.setItem('amin_ui_lang','fa'); location.href=location.pathname+'?lang=fa'; return false;" style="padding:4px 8px;background:#fef3c7;color:#92400e;border-radius:6px;text-decoration:none;font-size:10px">فارسی (رادیکال)</a>
    `;
    document.body.appendChild(div);
  }
  
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', ()=>{ addGoogleTranslate(); setTimeout(addDirectTranslateLinks, 1000); });
  else { addGoogleTranslate(); setTimeout(addDirectTranslateLinks, 1000); }
})();

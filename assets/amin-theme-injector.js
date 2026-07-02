/* ================================================================
   AMIN THEME INJECTOR v6 - يحترم portal.css ويضيف تحسينات فقط
   الآن يقوم أيضاً باستبدال روابط CSS القديمة بروابط النظام التصميمي V3
   ================================================================ */
(function(){
  'use strict';
  
  if (window._aminThemeInjected) return;
  window._aminThemeInjected = true;
  
  // ===== CONFIG: ملفات CSS القديمة التي نريد استبدالها =====
  const OLD_CSS = [
    'assets/portal.css',
    'assets/amin-identity.css',
    'assets/brand-redesign.css',
    'assets/amin-v3.css'
  ];
  const NEW_CSS = [
    'assets/design-tokens.css',
    'assets/components.css'
  ];

  // ===== Dark Mode Support =====
  function applyDarkMode() {
    if (localStorage.getItem('darkMode') === '1') {
      document.body.classList.add('dark');
    }
  }
  
  // ===== حقن CSS لدعم Dark Mode =====
  function injectDarkModeCSS() {
    if (document.getElementById('amin-dark-mode-support')) return;
    var style = document.createElement('style');
    style.id = 'amin-dark-mode-support';
    style.textContent = 
      'body.dark {' +
        'background: linear-gradient(135deg, #14181A, #1C2236) !important;' +
        'color: #E8EAF2 !important;' +
      '}' +
      'body.dark .sidebar {' +
        'background: rgba(28, 34, 54, 0.85) !important;' +
        'border-color: #2E3450 !important;' +
      '}' +
      'body.dark .topbar {' +
        'background: rgba(28, 34, 54, 0.85) !important;' +
        'color: #E8EAF2 !important;' +
      '}' +
      'body.dark .card, body.dark .kpi, body.dark .panel {' +
        'background: linear-gradient(145deg, #1C2236, #242B42) !important;' +
        'border-color: #2E3450 !important;' +
        'color: #E8EAF2 !important;' +
      '}' +
      'body.dark .brand, body.dark .profile-mini {' +
        'background: linear-gradient(145deg, #1C2236, #242B42) !important;' +
        'border-color: #2E3450 !important;' +
        'color: #E8EAF2 !important;' +
      '}' +
      'body.dark .nav button {' +
        'color: #9CA3AF !important;' +
      '}' +
      'body.dark .nav button:hover {' +
        'background: #242B42 !important;' +
        'color: #E8EAF2 !important;' +
      '}' +
      'body.dark .nav button.active {' +
        'background: linear-gradient(145deg, #242B42, #2E3450) !important;' +
        'color: #9EBCEC !important;' +
        'border-color: #3D4564 !important;' +
      '}' +
      'body.dark table {' +
        'background: #1C2236 !important;' +
        'color: #E8EAF2 !important;' +
      '}' +
      'body.dark th {' +
        'background: linear-gradient(145deg, #1C2236, #242B42) !important;' +
        'color: #9CA3AF !important;' +
      '}' +
      'body.dark td {' +
        'color: #E8EAF2 !important;' +
        'border-bottom-color: #2E3450 !important;' +
      '}' +
      'body.dark tbody tr:hover {' +
        'background: rgba(158, 188, 236, 0.05) !important;' +
      '}' +
      'body.dark .input, body.dark .select, body.dark textarea {' +
        'background: linear-gradient(145deg, #1C2236, #242B42) !important;' +
        'color: #E8EAF2 !important;' +
        'border-color: #2E3450 !important;' +
      '}' +
      'body.dark .btn {' +
        'background: linear-gradient(145deg, #242B42, #2E3450) !important;' +
        'color: #E8EAF2 !important;' +
        'border-color: #3D4564 !important;' +
      '}' +
      'body.dark .toast {' +
        'background: #1C2236 !important;' +
        'color: #E8EAF2 !important;' +
      '}' +
      'body.dark .modal {' +
        'background: #1C2236 !important;' +
        'color: #E8EAF2 !important;' +
      '}' +
      'body.dark .item {' +
        'background: rgba(28, 34, 54, 0.7) !important;' +
        'border-color: #2E3450 !important;' +
      '}' +
      'body.dark body::before { opacity: 0.15 !important; }';
    document.head.appendChild(style);
  }
  
  // ===== Floating Buttons =====
  function addFloatingButtons() {
    if (document.getElementById('amin-floating-controls')) return;
    var container = document.createElement('div');
    container.id = 'amin-floating-controls';
    container.style.cssText = 'position:fixed;bottom:24px;left:24px;z-index:9998;display:flex;flex-direction:column;gap:12px;';
    var homeBtn = document.createElement('button');
    homeBtn.title = 'البوابة الموحدة';
    homeBtn.style.cssText = 'width:52px;height:52px;border-radius:50%;background:linear-gradient(145deg,#9EBCEC,#7FA1DD);color:white;border:1px solid rgba(255,255,255,0.9);cursor:pointer;box-shadow:0 8px 30px rgba(62,100,170,0.12);';
    homeBtn.onmouseover = function(){ this.style.transform = 'scale(1.08)'; };
    homeBtn.onmouseout = function(){ this.style.transform = 'scale(1)'; };
    homeBtn.onclick = function(){ location.href = 'portal.html'; };
    homeBtn.innerHTML = '🏛️';
    var darkBtn = document.createElement('button');
    darkBtn.title = 'تبديل الوضع الليلي';
    darkBtn.style.cssText = 'width:52px;height:52px;border-radius:50%;background:linear-gradient(145deg,#fff,#F8FFFF);color:#294B83;border:1px solid rgba(158,188,236,0.4);cursor:pointer;box-shadow:0 8px 30px rgba(62,100,170,0.06);';
    darkBtn.onmouseover = function(){ this.style.transform = 'scale(1.08)'; };
    darkBtn.onmouseout = function(){ this.style.transform = 'scale(1)'; };
    darkBtn.onclick = function(){
      document.body.classList.toggle('dark');
      var dark = document.body.classList.contains('dark');
      localStorage.setItem('darkMode', dark ? '1' : '0');
      darkBtn.innerHTML = dark ? '☀️' : '🌙';
    };
    var isDark = document.body.classList.contains('dark');
    darkBtn.innerHTML = isDark ? '☀️' : '🌙';
    container.appendChild(darkBtn);
    container.appendChild(homeBtn);
    document.body.appendChild(container);
  }

  // ===== New: Replace old stylesheet links with unified design tokens/components =====
  function unifyStylesheets() {
    try {
      var head = document.head || document.getElementsByTagName('head')[0];
      if(!head) return;

      // If new CSS already present, skip
      var already = NEW_CSS.some(function(h){ return !!document.querySelector('link[rel="stylesheet"][href="'+h+'"]'); });
      if(already) return;

      // Remove old CSS links if present
      var links = Array.from(document.querySelectorAll('link[rel="stylesheet"]'));
      var removedAny = false;
      links.forEach(function(l){
        var href = l.getAttribute('href') || '';
        if(OLD_CSS.some(function(o){ return href.indexOf(o) !== -1; })){
          l.parentNode && l.parentNode.removeChild(l);
          removedAny = true;
        }
      });

      // Insert new CSS links at the start of head
      for(var i=0;i<NEW_CSS.length;i++){
        var href = NEW_CSS[i];
        var link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = href;
        head.insertBefore(link, head.firstChild);
      }

      // Re-run theme injector pieces that depend on variables
      injectDarkModeCSS();

      // If we removed anything, log for diagnostics
      if(removedAny) console.log('Amin Theme: Replaced legacy CSS with unified design tokens/components');
    } catch(e) { console.warn('Amin Theme: unifyStylesheets failed', e); }
  }

  // ===== التشغيل =====
  function init() {
    applyDarkMode();
    injectDarkModeCSS();
    addFloatingButtons();
    // Try to unify early (in head-run pages this will still work when script is at end)
    unifyStylesheets();
    console.log('✨ Amin Theme v6 Applied');
  }
  
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

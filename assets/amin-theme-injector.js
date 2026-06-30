/* ================================================================
   AMIN THEME INJECTOR - تطبيق الهوية تلقائياً على كل الصفحات
   ================================================================ */
(function(){
'use strict';

// تجنب التحميل المتكرر
if (window._aminThemeInjected) return;
window._aminThemeInjected = true;

// ===== 1. حقن CSS Variables (Design Tokens) =====
function injectCSS() {
  if (document.getElementById('amin-theme-vars')) return;
  
  var link1 = document.createElement('link');
  link1.id = 'amin-theme-vars';
  link1.rel = 'stylesheet';
  link1.href = 'assets/design-tokens.css';
  document.head.appendChild(link1);
  
  var link2 = document.createElement('link');
  link2.rel = 'stylesheet';
  link2.href = 'assets/components.css';
  document.head.appendChild(link2);
}

// ===== 2. حقن السكريبتات المساعدة =====
function injectScripts(callback) {
  var scripts = [
    'assets/signature-star.js',
    'assets/amin-icons.js',
    'assets/renderHelpers.js'
  ];
  var loaded = 0;
  scripts.forEach(function(src){
    // تجنب التحميل المتكرر
    if (document.querySelector('script[src="' + src + '"]')) {
      loaded++;
      if (loaded === scripts.length && callback) callback();
      return;
    }
    var s = document.createElement('script');
    s.src = src;
    s.onload = function(){
      loaded++;
      if (loaded === scripts.length && callback) callback();
    };
    document.body.appendChild(s);
  });
}

// ===== 3. تطبيق Dark Mode المحفوظ =====
function applyDarkMode() {
  if (localStorage.getItem('darkMode') === '1') {
    document.body.classList.add('dark');
  }
}

// ===== 4. إضافة Floating Buttons (Dark Mode + Home) =====
function addFloatingButtons() {
  if (document.getElementById('amin-floating-controls')) return;
  
  var container = document.createElement('div');
  container.id = 'amin-floating-controls';
  container.style.cssText = 'position:fixed;bottom:20px;inset-inline-start:20px;z-index:9000;display:flex;flex-direction:column;gap:10px;';
  
  // زر العودة للبوابة
  var homeBtn = document.createElement('button');
  homeBtn.title = 'البوابة الموحدة';
  homeBtn.style.cssText = 'width:48px;height:48px;border-radius:50%;background:var(--primary);color:white;border:none;cursor:pointer;box-shadow:0 4px 12px var(--primary-shadow);display:flex;align-items:center;justify-content:center;transition:transform 0.2s;';
  homeBtn.onmouseover = function(){ this.style.transform = 'scale(1.05)'; };
  homeBtn.onmouseout = function(){ this.style.transform = 'scale(1)'; };
  homeBtn.onclick = function(){ location.href = 'portal.html'; };
  homeBtn.innerHTML = window.AminIcons ? window.AminIcons.create('overview', 24) : '🏠';
  
  // زر تبديل الوضع
  var darkBtn = document.createElement('button');
  darkBtn.title = 'تبديل الوضع';
  darkBtn.style.cssText = 'width:48px;height:48px;border-radius:50%;background:var(--surface);color:var(--text-primary);border:1px solid var(--border-subtle);cursor:pointer;box-shadow:var(--shadow-soft);display:flex;align-items:center;justify-content:center;transition:transform 0.2s;';
  darkBtn.onmouseover = function(){ this.style.transform = 'scale(1.05)'; };
  darkBtn.onmouseout = function(){ this.style.transform = 'scale(1)'; };
  darkBtn.onclick = function(){
    document.body.classList.toggle('dark');
    var dark = document.body.classList.contains('dark');
    localStorage.setItem('darkMode', dark ? '1' : '0');
    darkBtn.innerHTML = window.AminIcons ? window.AminIcons.create(dark ? 'lightmode' : 'darkmode', 24) : (dark ? '☀️' : '🌙');
  };
  var isDark = document.body.classList.contains('dark');
  darkBtn.innerHTML = window.AminIcons ? window.AminIcons.create(isDark ? 'lightmode' : 'darkmode', 24) : (isDark ? '☀️' : '🌙');
  
  container.appendChild(homeBtn);
  container.appendChild(darkBtn);
  document.body.appendChild(container);
}

// ===== 5. تطبيق التحسينات على Body =====
function enhanceBody() {
  // ضمان الخط والاتجاه
  if (!document.body.style.fontFamily) {
    document.body.style.fontFamily = "'Cairo', 'Segoe UI', Tahoma, sans-serif";
  }
  
  // CSS إضافي لتجميل العناصر الموجودة
  if (document.getElementById('amin-enhance-styles')) return;
  var style = document.createElement('style');
  style.id = 'amin-enhance-styles';
  style.textContent = [
    /* تطبيق الألوان الجديدة على الأزرار الموجودة */
    'button:not(.btn-3d-primary):not(.btn-3d-secondary):not(.btn-3d-danger):not(.btn-3d-accent):not(.logout-btn):not(.mobile-toggle):not(.sidebar-nav-item):not(.bottom-nav-item):not(.tab-btn):not(.amin-tab-btn):not(.modal-close):not(.toggle-slider):not(.error-inline-retry):not(.amin-star-progress-step):not(.timeline-item):not(.task-item):not(.mobile-card-expand-btn):not(.btn-row-action) {',
      'font-family: inherit;',
      'cursor: pointer;',
    '}',
    /* تحسين الـ links */
    'a { color: var(--primary); transition: color 0.2s; }',
    'a:hover { color: var(--accent); }',
    /* تحسين الـ inputs */
    'input:not(.amin-input):not(.filter-input):not([type="checkbox"]):not([type="radio"]):not([type="file"]), select:not(.amin-select):not(.filter-select), textarea {',
      'font-family: inherit;',
      'background: var(--surface);',
      'color: var(--text-primary);',
      'border: 1px solid var(--border-subtle);',
      'border-radius: var(--radius-md);',
      'padding: var(--space-3) var(--space-4);',
      'transition: border-color 0.2s;',
    '}',
    'input:not(.amin-input):not(.filter-input):not([type="checkbox"]):not([type="radio"]):not([type="file"]):focus, select:not(.amin-select):not(.filter-select):focus, textarea:focus {',
      'outline: none;',
      'border-color: var(--primary);',
      'box-shadow: 0 0 0 3px var(--primary-shadow);',
    '}',
    /* تحسين الـ tables */
    'table:not(.table-flat) { width: 100%; border-collapse: collapse; background: var(--surface); border-radius: var(--radius-lg); overflow: hidden; }',
    'table:not(.table-flat) th { background: var(--surface-2); padding: 12px; text-align: start; font-weight: 600; color: var(--text-secondary); border-bottom: 1px solid var(--border-subtle); }',
    'table:not(.table-flat) td { padding: 10px 12px; border-bottom: 1px solid var(--border-subtle); }',
    'table:not(.table-flat) tbody tr:hover { background: var(--surface-2); }',
    /* تحسين الـ cards */
    '.card:not(.card-soft):not(.kpi-card) { background: var(--surface); border-radius: var(--radius-lg); padding: var(--space-5); box-shadow: var(--shadow-soft); border: 1px solid var(--border-subtle); margin-block-end: var(--space-4); }',
    /* تحسين الـ topbar/header الموجود */
    '.topbar, header:not(.app-topbar) { background: var(--surface); padding: var(--space-3) var(--space-5); border-bottom: 1px solid var(--border-subtle); }',
    /* تحسين الـ sidebar الموجود */
    '.sidebar:not(.app-sidebar) { background: var(--bg-sidebar); color: var(--text-sidebar); }',
    '.sidebar:not(.app-sidebar) button { color: var(--text-sidebar); }',
    '.sidebar:not(.app-sidebar) button:hover { background: rgba(255,255,255,0.05); color: white; }',
    '.sidebar:not(.app-sidebar) .active { background: var(--primary); color: white; }',
  ].join('\n');
  document.head.appendChild(style);
}

// ===== 6. التشغيل =====
function init() {
  injectCSS();
  applyDarkMode();
  
  injectScripts(function(){
    enhanceBody();
    addFloatingButtons();
    console.log('✨ Amin Theme Applied');
  });
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

})();

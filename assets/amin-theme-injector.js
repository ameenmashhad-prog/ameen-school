/* ================================================================
   AMIN THEME INJECTOR v5 - يحترم portal.css ويضيف تحسينات فقط
   ================================================================ */
(function(){
  'use strict';
  
  if (window._aminThemeInjected) return;
  window._aminThemeInjected = true;
  
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
    homeBtn.style.cssText = 'width:52px;height:52px;border-radius:50%;background:linear-gradient(145deg,#9EBCEC,#7FA1DD);color:white;border:1px solid rgba(255,255,255,0.9);cursor:pointer;box-shadow:0 8px 24px rgba(158,188,236,0.4);display:flex;align-items:center;justify-content:center;padding:0;font-size:22px;transition:transform 0.2s;';
    homeBtn.onmouseover = function(){ this.style.transform = 'scale(1.08)'; };
    homeBtn.onmouseout = function(){ this.style.transform = 'scale(1)'; };
    homeBtn.onclick = function(){ location.href = 'portal.html'; };
    homeBtn.innerHTML = '🏛️';
    
    var darkBtn = document.createElement('button');
    darkBtn.title = 'تبديل الوضع الليلي';
    darkBtn.style.cssText = 'width:52px;height:52px;border-radius:50%;background:linear-gradient(145deg,#fff,#F8FFFF);color:#294B83;border:1px solid rgba(158,188,236,0.4);cursor:pointer;box-shadow:0 8px 24px rgba(31,41,55,0.15);display:flex;align-items:center;justify-content:center;padding:0;font-size:22px;transition:transform 0.2s;';
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
  
  // ===== التشغيل =====
  function init() {
    applyDarkMode();
    injectDarkModeCSS();
    addFloatingButtons();
    console.log('✨ Amin Theme v5 Applied');
  }
  
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

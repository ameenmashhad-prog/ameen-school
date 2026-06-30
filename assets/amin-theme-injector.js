/* ================================================================
   AMIN THEME INJECTOR v2 - يفرض الهوية الجديدة على CSS القديم
   ================================================================ */
(function(){
'use strict';

if (window._aminThemeInjected) return;
window._aminThemeInjected = true;

// ===== 1. حقن CSS Variables (Design Tokens) =====
function injectCSS() {
  if (document.getElementById('amin-theme-vars')) return;
  
  // الإضافة في النهاية لزيادة الـ priority
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
    s.onerror = function(){
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

// ===== 4. إضافة Floating Buttons =====
function addFloatingButtons() {
  if (document.getElementById('amin-floating-controls')) return;
  
  var container = document.createElement('div');
  container.id = 'amin-floating-controls';
  container.style.cssText = 'position:fixed !important;bottom:20px !important;inset-inline-start:20px !important;z-index:9000 !important;display:flex !important;flex-direction:column !important;gap:10px !important;';
  
  // زر العودة للبوابة
  var homeBtn = document.createElement('button');
  homeBtn.title = 'البوابة الموحدة';
  homeBtn.style.cssText = 'width:48px !important;height:48px !important;border-radius:50% !important;background:#0B6E4F !important;color:white !important;border:none !important;cursor:pointer !important;box-shadow:0 4px 12px rgba(11,110,79,0.3) !important;display:flex !important;align-items:center !important;justify-content:center !important;transition:transform 0.2s !important;padding:0 !important;';
  homeBtn.onmouseover = function(){ this.style.transform = 'scale(1.05)'; };
  homeBtn.onmouseout = function(){ this.style.transform = 'scale(1)'; };
  homeBtn.onclick = function(){ location.href = 'portal.html'; };
  homeBtn.innerHTML = window.AminIcons ? window.AminIcons.create('overview', 24) : '🏠';
  
  // زر تبديل الوضع
  var darkBtn = document.createElement('button');
  darkBtn.title = 'تبديل الوضع';
  darkBtn.style.cssText = 'width:48px !important;height:48px !important;border-radius:50% !important;background:white !important;color:#1E2433 !important;border:1px solid #E5E8F0 !important;cursor:pointer !important;box-shadow:0 4px 12px rgba(0,0,0,0.08) !important;display:flex !important;align-items:center !important;justify-content:center !important;transition:transform 0.2s !important;padding:0 !important;';
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

// ===== 5. فرض الهوية الجديدة بـ CSS قوي يطغى على القديم =====
function forceNewIdentity() {
  if (document.getElementById('amin-force-identity')) return;
  
  var style = document.createElement('style');
  style.id = 'amin-force-identity';
  style.textContent = `
/* ===== فرض الألوان الجديدة على CSS القديم ===== */

/* الخط الأساسي */
body, button, input, select, textarea, table {
  font-family: 'Cairo', 'Segoe UI', Tahoma, sans-serif !important;
}

/* الخلفية العامة */
body {
  background: #F7F5F0 !important;
  color: #1E2433 !important;
}

body.dark {
  background: #14181A !important;
  color: #E8EAF2 !important;
}

/* Sidebar (يفرض اللون الأخضر بدل أي لون قديم) */
.sidebar, .app-sidebar, aside.sidebar {
  background: #081426 !important;
  color: #cbd5e1 !important;
}

body.dark .sidebar, body.dark .app-sidebar, body.dark aside.sidebar {
  background: #020617 !important;
}

/* العلامة التجارية في الـ sidebar */
.brand, .sidebar-brand {
  border-bottom: 1px solid rgba(255,255,255,0.1) !important;
}

.brand h1, .sidebar-brand h1 {
  color: white !important;
}

.brand small, .sidebar-brand small {
  color: #cbd5e1 !important;
  opacity: 0.7 !important;
}

.brand-mark, .sidebar-brand-logo {
  background: linear-gradient(135deg, #0B6E4F, #1FAE7C) !important;
  color: white !important;
}

/* قائمة التنقل في الـ sidebar */
.sidebar .nav button, .sidebar-nav button, .sidebar-nav-item {
  color: #cbd5e1 !important;
  background: transparent !important;
  border: none !important;
  transition: all 0.2s !important;
}

.sidebar .nav button:hover, .sidebar-nav button:hover, .sidebar-nav-item:hover {
  background: rgba(255,255,255,0.05) !important;
  color: white !important;
}

.sidebar .nav button.active, .sidebar-nav button.active, .sidebar-nav-item.active {
  background: linear-gradient(135deg, #0B6E4F, #1FAE7C) !important;
  color: white !important;
  box-shadow: 0 4px 12px rgba(11,110,79,0.3) !important;
}

/* عنوان الأقسام في الـ sidebar */
.nav-section {
  color: #cbd5e1 !important;
  opacity: 0.6 !important;
  font-size: 11px !important;
  text-transform: uppercase !important;
  padding: 12px !important;
  letter-spacing: 0.5px !important;
}

/* profile-mini */
.profile-mini {
  background: rgba(255,255,255,0.05) !important;
  border-radius: 10px !important;
  margin: 12px !important;
}

.profile-mini b {
  color: white !important;
}

.profile-mini small {
  color: #cbd5e1 !important;
}

.profile-mini .avatar {
  background: linear-gradient(135deg, #3b82f6, #1e40af) !important;
  color: white !important;
}

/* Topbar */
.topbar, header.topbar {
  background: white !important;
  border-bottom: 1px solid #E5E8F0 !important;
  color: #1E2433 !important;
}

body.dark .topbar, body.dark header.topbar {
  background: #1C2236 !important;
  border-bottom-color: #2E3450 !important;
  color: #E8EAF2 !important;
}

.topbar h2 {
  color: #1E2433 !important;
  font-weight: 700 !important;
}

body.dark .topbar h2 {
  color: #E8EAF2 !important;
}

/* Buttons - الأزرار العامة */
button.btn, .btn {
  font-family: 'Cairo', sans-serif !important;
  border-radius: 14px !important;
  padding: 12px 24px !important;
  min-height: 44px !important;
  font-weight: 600 !important;
  cursor: pointer !important;
  transition: transform 0.15s, box-shadow 0.15s !important;
  border: none !important;
}

button.btn:hover, .btn:hover {
  transform: translateY(-2px) !important;
}

button.btn:active, .btn:active {
  transform: translateY(1px) !important;
}

/* الأزرار الذهبية → استبدلها بالأخضر الأساسي */
.btn.gold, button.btn.gold {
  background: #0B6E4F !important;
  color: white !important;
  box-shadow: 0 8px 20px rgba(11,110,79,0.25) !important;
}

.btn.gold:hover, button.btn.gold:hover {
  background: #0a5c43 !important;
}

/* الأزرار الزرقاء */
.btn.blue, button.btn.blue {
  background: #3A3565 !important;
  color: white !important;
  box-shadow: 0 8px 20px rgba(58,53,101,0.25) !important;
}

/* الأزرار الحمراء */
.btn.red, button.btn.red {
  background: #DC2626 !important;
  color: white !important;
  box-shadow: 0 8px 20px rgba(220,38,38,0.25) !important;
}

/* الأزرار الخضراء */
.btn.green, button.btn.green {
  background: #16A34A !important;
  color: white !important;
  box-shadow: 0 8px 20px rgba(22,163,74,0.25) !important;
}

/* Logout button */
#logoutBtn {
  background: rgba(220,38,38,0.1) !important;
  color: #fca5a5 !important;
  border: 1px solid rgba(220,38,38,0.2) !important;
}

#logoutBtn:hover {
  background: #DC2626 !important;
  color: white !important;
}

/* Cards */
.card, .kpi, .panel {
  background: white !important;
  border-radius: 14px !important;
  box-shadow: 0 1px 3px rgba(0,0,0,0.1) !important;
  border: 1px solid #E5E8F0 !important;
}

body.dark .card, body.dark .kpi, body.dark .panel {
  background: #1C2236 !important;
  border-color: #2E3450 !important;
}

/* Tables */
table {
  background: white !important;
  border-radius: 14px !important;
  overflow: hidden !important;
}

body.dark table {
  background: #1C2236 !important;
}

table th {
  background: #F4F6FB !important;
  color: #6B7280 !important;
  padding: 12px !important;
  font-weight: 600 !important;
  border-bottom: 1px solid #E5E8F0 !important;
  text-align: start !important;
}

body.dark table th {
  background: #242B42 !important;
  color: #9CA3AF !important;
  border-bottom-color: #2E3450 !important;
}

table td {
  padding: 10px 12px !important;
  border-bottom: 1px solid #E5E8F0 !important;
  color: #1E2433 !important;
}

body.dark table td {
  color: #E8EAF2 !important;
  border-bottom-color: #2E3450 !important;
}

table tbody tr:hover {
  background: #F4F6FB !important;
}

body.dark table tbody tr:hover {
  background: #242B42 !important;
}

/* Inputs */
input:not([type="checkbox"]):not([type="radio"]):not([type="file"]),
select, textarea {
  background: white !important;
  color: #1E2433 !important;
  border: 1px solid #E5E8F0 !important;
  border-radius: 12px !important;
  padding: 10px 14px !important;
  transition: border-color 0.2s !important;
  font-family: 'Cairo', sans-serif !important;
}

body.dark input:not([type="checkbox"]):not([type="radio"]):not([type="file"]),
body.dark select, body.dark textarea {
  background: #1C2236 !important;
  color: #E8EAF2 !important;
  border-color: #2E3450 !important;
}

input:focus, select:focus, textarea:focus {
  outline: none !important;
  border-color: #0B6E4F !important;
  box-shadow: 0 0 0 3px rgba(11,110,79,0.2) !important;
}

/* Badges */
.badge {
  display: inline-flex !important;
  align-items: center !important;
  padding: 4px 10px !important;
  border-radius: 8px !important;
  font-size: 12px !important;
  font-weight: 600 !important;
  border: 1px solid !important;
}

.badge.green, .badge-flat.success {
  background: #DCFCE7 !important;
  color: #16A34A !important;
  border-color: #16A34A !important;
}

.badge.red, .badge-flat.danger {
  background: #FEE2E2 !important;
  color: #DC2626 !important;
  border-color: #DC2626 !important;
}

.badge.gold, .badge.yellow, .badge-flat.warning {
  background: #FEF3C7 !important;
  color: #D97706 !important;
  border-color: #D97706 !important;
}

.badge.blue, .badge-flat.info {
  background: #E0F2FE !important;
  color: #0EA5E9 !important;
  border-color: #0EA5E9 !important;
}

/* Links */
a {
  color: #0B6E4F !important;
  transition: color 0.2s !important;
}

a:hover {
  color: #1FAE7C !important;
}

/* العناوين */
h1, h2, h3, h4 {
  color: #1E2433 !important;
  font-family: 'Cairo', sans-serif !important;
  font-weight: 700 !important;
}

body.dark h1, body.dark h2, body.dark h3, body.dark h4 {
  color: #E8EAF2 !important;
}

/* الـ KPI الموجودة */
.kpi {
  padding: 20px !important;
  border-right: 4px solid #0B6E4F !important;
}

.kpi small {
  color: #6B7280 !important;
  font-size: 13px !important;
  font-weight: 600 !important;
  display: block !important;
  margin-bottom: 8px !important;
}

.kpi b {
  font-size: 24px !important;
  color: #1E2433 !important;
  font-weight: 800 !important;
}

.kpi.gold { border-right-color: #B8860B !important; }
.kpi.green { border-right-color: #16A34A !important; }
.kpi.red { border-right-color: #DC2626 !important; }
.kpi.blue { border-right-color: #0EA5E9 !important; }

/* Scrollbars */
::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

::-webkit-scrollbar-track {
  background: #F4F6FB;
}

::-webkit-scrollbar-thumb {
  background: #D1D5DB;
  border-radius: 4px;
}

::-webkit-scrollbar-thumb:hover {
  background: #6B7280;
}

body.dark ::-webkit-scrollbar-track {
  background: #242B42;
}

body.dark ::-webkit-scrollbar-thumb {
  background: #3D4564;
}

/* Toast */
.toast {
  background: white !important;
  border-radius: 12px !important;
  box-shadow: 0 12px 32px rgba(0,0,0,0.15) !important;
  border-right: 4px solid #0B6E4F !important;
  color: #1E2433 !important;
}

body.dark .toast {
  background: #1C2236 !important;
  color: #E8EAF2 !important;
}

/* Mobile menu button */
.mobile-menu {
  background: transparent !important;
  border: none !important;
  font-size: 24px !important;
  color: #1E2433 !important;
}

body.dark .mobile-menu {
  color: #E8EAF2 !important;
}

/* تحسين الـ tooltips والـ titles */
.muted {
  color: #6B7280 !important;
}

/* تحسين الـ form labels */
label {
  color: #1E2433 !important;
  font-weight: 600 !important;
  font-size: 14px !important;
}

body.dark label {
  color: #E8EAF2 !important;
}
  `;
  document.head.appendChild(style);
}

// ===== 6. التشغيل =====
function init() {
  injectCSS();
  applyDarkMode();
  forceNewIdentity(); // ← الجديد: فرض الهوية بـ !important
  
  injectScripts(function(){
    addFloatingButtons();
    console.log('✨ Amin Theme Applied (v2 - forced)');
  });
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

})();

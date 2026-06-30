/* ================================================================
   AMIN THEME INJECTOR v3 - يعطّل CSS القديم ويفرض الجديد
   ================================================================ */
(function(){
'use strict';

if (window._aminThemeInjected) return;
window._aminThemeInjected = true;

// ===== 1. تعطيل ملفات CSS القديمة المسببة للمشكلة =====
function disableOldCSS() {
  var oldCSSFiles = [
    'amin-identity.css',
    'brand-redesign.css',
    'amin-v3.css',
    'documents.css',
    'i18n.css'
  ];
  
  document.querySelectorAll('link[rel="stylesheet"]').forEach(function(link){
    var href = link.getAttribute('href') || '';
    oldCSSFiles.forEach(function(oldFile){
      if (href.indexOf(oldFile) !== -1) {
        link.disabled = true;
        link.remove();
        console.log('🚫 Disabled old CSS:', href);
      }
    });
  });
  
  // إزالة inline styles من body
  if (document.body.hasAttribute('data-portal')) {
    // نحتفظ بالـ attribute لكن نزيل أي style مرتبط به
  }
}

// ===== 2. حقن CSS الجديد (أولاً لضمان الأولوية) =====
function injectNewCSS() {
  // إذا موجود أصلاً، أزله ثم أضفه من جديد لرفع الأولوية
  document.querySelectorAll('#amin-theme-vars, #amin-theme-components').forEach(function(el){
    el.remove();
  });
  
  var link1 = document.createElement('link');
  link1.id = 'amin-theme-vars';
  link1.rel = 'stylesheet';
  link1.href = 'assets/design-tokens.css';
  document.head.appendChild(link1);
  
  var link2 = document.createElement('link');
  link2.id = 'amin-theme-components';
  link2.rel = 'stylesheet';
  link2.href = 'assets/components.css';
  document.head.appendChild(link2);
}

// ===== 3. حقن السكريبتات المساعدة =====
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

// ===== 4. تطبيق Dark Mode المحفوظ =====
function applyDarkMode() {
  if (localStorage.getItem('darkMode') === '1') {
    document.body.classList.add('dark');
  }
}

// ===== 5. حقن CSS قوي جداً يفرض الهوية =====
function forceIdentity() {
  if (document.getElementById('amin-force-identity-v3')) return;
  
  var style = document.createElement('style');
  style.id = 'amin-force-identity-v3';
  // نضعه في نهاية الـ head لأقصى أولوية
  style.textContent = `
/* ===================== RESET الألوان القديمة ===================== */

* {
  font-family: 'Cairo', 'Segoe UI', Tahoma, sans-serif !important;
}

/* الخلفية الرئيسية - دافئة كريمي */
body {
  background: #F7F5F0 !important;
  background-image: none !important;
  color: #1E2433 !important;
}

body.dark {
  background: #14181A !important;
  color: #E8EAF2 !important;
}

/* إزالة أي خلفيات وردية/بنفسجية على الـ shell */
.shell, .unified-shell, .app-shell {
  background: transparent !important;
}

/* ===================== SIDEBAR ===================== */

.sidebar, .unified-side, aside.sidebar {
  background: #081426 !important;
  background-image: none !important;
  color: #cbd5e1 !important;
  border: none !important;
}

body.dark .sidebar, body.dark .unified-side {
  background: #020617 !important;
}

/* العلامة التجارية */
.brand {
  background: transparent !important;
  border-bottom: 1px solid rgba(255,255,255,0.1) !important;
  padding: 20px !important;
}

.brand-mark {
  background: linear-gradient(135deg, #0B6E4F, #1FAE7C) !important;
  color: white !important;
  width: 44px !important;
  height: 44px !important;
  border-radius: 12px !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  font-weight: 700 !important;
  font-size: 18px !important;
}

.brand h1 {
  color: white !important;
  font-size: 16px !important;
  font-weight: 700 !important;
  margin: 0 !important;
}

.brand small {
  color: #cbd5e1 !important;
  opacity: 0.7 !important;
  font-size: 11px !important;
}

/* Profile mini */
.profile-mini {
  background: rgba(255,255,255,0.05) !important;
  border-radius: 10px !important;
  margin: 12px !important;
  padding: 12px !important;
  border: none !important;
}

.profile-mini .avatar {
  background: linear-gradient(135deg, #3b82f6, #1e40af) !important;
  color: white !important;
  width: 40px !important;
  height: 40px !important;
  border-radius: 50% !important;
  font-size: 20px !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
}

.profile-mini b {
  color: white !important;
  font-weight: 600 !important;
}

.profile-mini small {
  color: #cbd5e1 !important;
}

/* قائمة Sidebar */
.sidebar .nav, .sidebar-nav {
  padding: 12px !important;
  background: transparent !important;
}

.sidebar .nav button, .sidebar-nav button {
  background: transparent !important;
  color: #cbd5e1 !important;
  border: none !important;
  padding: 10px 14px !important;
  margin-bottom: 4px !important;
  border-radius: 8px !important;
  font-family: 'Cairo', sans-serif !important;
  font-size: 14px !important;
  width: 100% !important;
  text-align: start !important;
  cursor: pointer !important;
  display: flex !important;
  align-items: center !important;
  gap: 12px !important;
  transition: all 0.2s !important;
  box-shadow: none !important;
}

.sidebar .nav button:hover, .sidebar-nav button:hover {
  background: rgba(255,255,255,0.05) !important;
  color: white !important;
  transform: none !important;
}

.sidebar .nav button.active, .sidebar-nav button.active {
  background: linear-gradient(135deg, #0B6E4F, #1FAE7C) !important;
  color: white !important;
  box-shadow: 0 4px 12px rgba(11,110,79,0.3) !important;
}

.nav-section {
  color: #cbd5e1 !important;
  opacity: 0.6 !important;
  font-size: 11px !important;
  text-transform: uppercase !important;
  padding: 12px 14px 6px !important;
  letter-spacing: 0.5px !important;
}

/* ===================== TOPBAR ===================== */

.topbar, .unified-hero, header.topbar {
  background: white !important;
  background-image: none !important;
  border-bottom: 1px solid #E5E8F0 !important;
  padding: 14px 24px !important;
  color: #1E2433 !important;
  box-shadow: 0 1px 3px rgba(0,0,0,0.05) !important;
}

body.dark .topbar, body.dark .unified-hero {
  background: #1C2236 !important;
  border-bottom-color: #2E3450 !important;
  color: #E8EAF2 !important;
}

.topbar h2, .unified-hero h1, .unified-hero h2 {
  color: #1E2433 !important;
  font-weight: 700 !important;
  font-size: 18px !important;
  margin: 0 !important;
}

body.dark .topbar h2 {
  color: #E8EAF2 !important;
}

.unified-hero p {
  color: #6B7280 !important;
}

/* ===================== MAIN ===================== */

.main, .unified-main, main.main {
  background: #F7F5F0 !important;
  background-image: none !important;
  color: #1E2433 !important;
}

body.dark .main, body.dark .unified-main {
  background: #14181A !important;
  color: #E8EAF2 !important;
}

/* العناوين الكبيرة - استبدل الخط الذهبي/الوردي */
.main h1, .unified-main h1, h1.amin-headline {
  color: #0B6E4F !important;
  background: none !important;
  -webkit-background-clip: unset !important;
  -webkit-text-fill-color: #0B6E4F !important;
  font-weight: 800 !important;
  text-shadow: none !important;
}

body.dark .main h1, body.dark .unified-main h1 {
  color: #1FAE7C !important;
  -webkit-text-fill-color: #1FAE7C !important;
}

/* إزالة الخط الذهبي تحت العناوين */
.main h1::after, .unified-main h1::after,
.amin-headline::after, .page-head h1::after {
  display: none !important;
  background: none !important;
  border: none !important;
  content: none !important;
}

/* ===================== BUTTONS ===================== */

button.btn, .btn {
  font-family: 'Cairo', sans-serif !important;
  border-radius: 14px !important;
  padding: 10px 22px !important;
  min-height: 44px !important;
  font-weight: 600 !important;
  font-size: 14px !important;
  cursor: pointer !important;
  transition: transform 0.15s, box-shadow 0.15s !important;
  border: none !important;
  display: inline-flex !important;
  align-items: center !important;
  justify-content: center !important;
  gap: 8px !important;
}

button.btn:hover, .btn:hover {
  transform: translateY(-2px) !important;
}

button.btn:active, .btn:active {
  transform: translateY(1px) !important;
}

/* الأزرار الذهبية → استبدلها بالأخضر */
.btn.gold, button.btn.gold {
  background: #0B6E4F !important;
  background-image: none !important;
  color: white !important;
  box-shadow: 0 6px 16px rgba(11,110,79,0.25) !important;
  border: none !important;
}

.btn.gold:hover {
  background: #0a5c43 !important;
}

/* الزر الأزرق */
.btn.blue {
  background: #3A3565 !important;
  background-image: none !important;
  color: white !important;
  box-shadow: 0 6px 16px rgba(58,53,101,0.25) !important;
}

.btn.blue:hover {
  background: #2d2950 !important;
}

/* الزر الأحمر */
.btn.red {
  background: #DC2626 !important;
  background-image: none !important;
  color: white !important;
  box-shadow: 0 6px 16px rgba(220,38,38,0.25) !important;
}

/* الزر الأخضر */
.btn.green {
  background: #16A34A !important;
  background-image: none !important;
  color: white !important;
  box-shadow: 0 6px 16px rgba(22,163,74,0.25) !important;
}

/* الأزرار الصغيرة - مثل بحث سريع */
button.btn:not(.gold):not(.blue):not(.red):not(.green):not(.mobile-menu) {
  background: white !important;
  color: #1E2433 !important;
  border: 1px solid #E5E8F0 !important;
  box-shadow: 0 1px 3px rgba(0,0,0,0.05) !important;
}

body.dark button.btn:not(.gold):not(.blue):not(.red):not(.green):not(.mobile-menu) {
  background: #1C2236 !important;
  color: #E8EAF2 !important;
  border-color: #2E3450 !important;
}

/* logout button */
#logoutBtn {
  background: rgba(220,38,38,0.1) !important;
  color: #fca5a5 !important;
  border: 1px solid rgba(220,38,38,0.2) !important;
  width: 100% !important;
}

#logoutBtn:hover {
  background: #DC2626 !important;
  color: white !important;
}

/* ===================== KPI CARDS ===================== */

.kpi, .card.kpi {
  background: white !important;
  background-image: none !important;
  padding: 20px !important;
  border-radius: 14px !important;
  box-shadow: 0 1px 3px rgba(0,0,0,0.08) !important;
  border: 1px solid #E5E8F0 !important;
  border-right: 4px solid #0B6E4F !important;
  position: relative !important;
}

body.dark .kpi {
  background: #1C2236 !important;
  border-color: #2E3450 !important;
  border-right-color: #0B6E4F !important;
}

.kpi small {
  color: #6B7280 !important;
  font-size: 13px !important;
  font-weight: 600 !important;
  display: block !important;
  margin-bottom: 8px !important;
}

.kpi b {
  font-size: 28px !important;
  color: #1E2433 !important;
  font-weight: 800 !important;
  display: block !important;
}

body.dark .kpi b {
  color: #E8EAF2 !important;
}

/* ألوان حدود الـ KPI */
.kpi.gold, .kpi.secondary { border-right-color: #B8860B !important; }
.kpi.green, .kpi.success { border-right-color: #16A34A !important; }
.kpi.red, .kpi.danger { border-right-color: #DC2626 !important; }
.kpi.blue, .kpi.info { border-right-color: #0EA5E9 !important; }
.kpi.warning { border-right-color: #D97706 !important; }

/* إزالة الخلفيات الدائرية الوردية */
.kpi::before, .kpi::after,
.card::before, .card::after {
  display: none !important;
  content: none !important;
  background: none !important;
}

/* ===================== CARDS ===================== */

.card, .panel {
  background: white !important;
  background-image: none !important;
  border-radius: 14px !important;
  box-shadow: 0 1px 3px rgba(0,0,0,0.08) !important;
  border: 1px solid #E5E8F0 !important;
  padding: 20px !important;
  color: #1E2433 !important;
}

body.dark .card, body.dark .panel {
  background: #1C2236 !important;
  border-color: #2E3450 !important;
  color: #E8EAF2 !important;
}

/* ===================== TABLES ===================== */

table {
  width: 100% !important;
  border-collapse: collapse !important;
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
  font-size: 13px !important;
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

/* ===================== INPUTS ===================== */

input:not([type="checkbox"]):not([type="radio"]):not([type="file"]),
select, textarea {
  background: white !important;
  color: #1E2433 !important;
  border: 1px solid #E5E8F0 !important;
  border-radius: 12px !important;
  padding: 10px 14px !important;
  font-family: 'Cairo', sans-serif !important;
  font-size: 14px !important;
  min-height: 44px !important;
  transition: border-color 0.2s !important;
}

body.dark input, body.dark select, body.dark textarea {
  background: #1C2236 !important;
  color: #E8EAF2 !important;
  border-color: #2E3450 !important;
}

input:focus, select:focus, textarea:focus {
  outline: none !important;
  border-color: #0B6E4F !important;
  box-shadow: 0 0 0 3px rgba(11,110,79,0.2) !important;
}

/* ===================== BADGES ===================== */

.badge {
  display: inline-flex !important;
  align-items: center !important;
  padding: 4px 10px !important;
  border-radius: 8px !important;
  font-size: 12px !important;
  font-weight: 600 !important;
  border: 1px solid !important;
  background-image: none !important;
}

.badge.green, .badge-success {
  background: #DCFCE7 !important;
  color: #16A34A !important;
  border-color: #16A34A !important;
}

.badge.red, .badge-danger {
  background: #FEE2E2 !important;
  color: #DC2626 !important;
  border-color: #DC2626 !important;
}

.badge.gold, .badge.yellow, .badge-warning {
  background: #FEF3C7 !important;
  color: #D97706 !important;
  border-color: #D97706 !important;
}

.badge.blue, .badge-info {
  background: #E0F2FE !important;
  color: #0EA5E9 !important;
  border-color: #0EA5E9 !important;
}

/* ===================== LINKS ===================== */

a {
  color: #0B6E4F !important;
  transition: color 0.2s !important;
  text-decoration: none !important;
}

a:hover {
  color: #1FAE7C !important;
}

/* ===================== SHORTCUTS / KBD ===================== */

kbd, .kbd, .ctrlk, .shortcut {
  background: rgba(255,255,255,0.1) !important;
  color: #6B7280 !important;
  border: 1px solid #E5E8F0 !important;
  border-radius: 6px !important;
  padding: 2px 8px !important;
  font-size: 11px !important;
  font-family: monospace !important;
}

/* ===================== HEADINGS ===================== */

h1, h2, h3, h4, h5, h6 {
  color: #1E2433 !important;
  font-family: 'Cairo', sans-serif !important;
  font-weight: 700 !important;
  background: none !important;
  -webkit-background-clip: unset !important;
  -webkit-text-fill-color: inherit !important;
}

body.dark h1, body.dark h2, body.dark h3, body.dark h4 {
  color: #E8EAF2 !important;
}

/* ===================== PAGE HEAD ===================== */

.page-head, .section-page-head {
  margin-bottom: 20px !important;
  padding: 0 !important;
  background: none !important;
  border: none !important;
}

.page-head h1 {
  color: #0B6E4F !important;
  font-size: 28px !important;
  margin-bottom: 8px !important;
}

body.dark .page-head h1 {
  color: #1FAE7C !important;
}

.page-head p, .page-head .muted {
  color: #6B7280 !important;
}

/* إزالة الخطوط الذهبية المتدرجة تحت العناوين */
.page-head::after, .page-head::before {
  display: none !important;
  background: none !important;
  border: none !important;
  content: none !important;
}

/* ===================== MOBILE MENU ===================== */

.mobile-menu {
  background: transparent !important;
  border: none !important;
  font-size: 24px !important;
  color: #1E2433 !important;
  width: 44px !important;
  height: 44px !important;
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  cursor: pointer !important;
  box-shadow: none !important;
}

body.dark .mobile-menu {
  color: #E8EAF2 !important;
}

/* ===================== TOAST ===================== */

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

/* ===================== SCROLLBARS ===================== */

::-webkit-scrollbar {
  width: 8px !important;
  height: 8px !important;
}

::-webkit-scrollbar-track {
  background: #F4F6FB !important;
}

::-webkit-scrollbar-thumb {
  background: #D1D5DB !important;
  border-radius: 4px !important;
}

body.dark ::-webkit-scrollbar-track {
  background: #242B42 !important;
}

body.dark ::-webkit-scrollbar-thumb {
  background: #3D4564 !important;
}

/* ===================== MUTED & SECONDARY TEXT ===================== */

.muted, small, .text-secondary {
  color: #6B7280 !important;
}

body.dark .muted, body.dark small {
  color: #9CA3AF !important;
}

/* ===================== FORM GROUPS ===================== */

label {
  color: #1E2433 !important;
  font-weight: 600 !important;
  font-size: 14px !important;
  display: block !important;
  margin-bottom: 6px !important;
}

body.dark label {
  color: #E8EAF2 !important;
}

/* ===================== TIMELINE ===================== */

.timeline-list-lite, .timeline-list {
  background: white !important;
  border-radius: 12px !important;
  border: 1px solid #E5E8F0 !important;
  padding: 16px !important;
}

body.dark .timeline-list {
  background: #1C2236 !important;
  border-color: #2E3450 !important;
}

/* ===================== STAR / LOGO STYLING ===================== */

.brand-mark, [class*="logo"] {
  background: linear-gradient(135deg, #0B6E4F, #1FAE7C) !important;
}

/* ===================== خلفيات هندسية وردية - إزالة كاملة ===================== */

.unified-hero::before, .unified-hero::after,
.shell::before, .shell::after,
body::before, body::after {
  display: none !important;
  background: none !important;
  background-image: none !important;
  content: none !important;
}
  `;
  document.head.appendChild(style);
}

// ===== 6. إضافة Floating Buttons =====
function addFloatingButtons() {
  if (document.getElementById('amin-floating-controls')) return;
  
  var container = document.createElement('div');
  container.id = 'amin-floating-controls';
  container.style.cssText = 'position:fixed !important;bottom:20px !important;inset-inline-start:20px !important;z-index:9000 !important;display:flex !important;flex-direction:column !important;gap:10px !important;';
  
  var homeBtn = document.createElement('button');
  homeBtn.title = 'البوابة الموحدة';
  homeBtn.style.cssText = 'width:48px !important;height:48px !important;border-radius:50% !important;background:#0B6E4F !important;color:white !important;border:none !important;cursor:pointer !important;box-shadow:0 4px 12px rgba(11,110,79,0.3) !important;display:flex !important;align-items:center !important;justify-content:center !important;padding:0 !important;';
  homeBtn.onclick = function(){ location.href = 'portal.html'; };
  homeBtn.innerHTML = window.AminIcons ? window.AminIcons.create('overview', 24) : '🏠';
  
  var darkBtn = document.createElement('button');
  darkBtn.title = 'تبديل الوضع';
  darkBtn.style.cssText = 'width:48px !important;height:48px !important;border-radius:50% !important;background:white !important;color:#1E2433 !important;border:1px solid #E5E8F0 !important;cursor:pointer !important;box-shadow:0 4px 12px rgba(0,0,0,0.08) !important;display:flex !important;align-items:center !important;justify-content:center !important;padding:0 !important;';
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

// ===== التشغيل =====
function init() {
  // 1. عطّل القديم أولاً
  disableOldCSS();
  
  // 2. حقن الجديد
  injectNewCSS();
  
  // 3. تطبيق Dark Mode
  applyDarkMode();
  
  // 4. حقن السكريبتات
  injectScripts(function(){
    // 5. فرض الهوية بقوة
    forceIdentity();
    
    // 6. إضافة الأزرار العائمة
    addFloatingButtons();
    
    console.log('✨ Amin Theme v3 Applied - Old CSS Disabled');
  });
  
  // 7. مراقبة إضافة CSS جديد ديناميكي ومنعه
  if (window.MutationObserver) {
    var observer = new MutationObserver(function(mutations) {
      mutations.forEach(function(mutation) {
        mutation.addedNodes.forEach(function(node) {
          if (node.tagName === 'LINK' && node.rel === 'stylesheet') {
            var href = node.getAttribute('href') || '';
            if (href.indexOf('amin-identity') !== -1 || 
                href.indexOf('brand-redesign') !== -1 || 
                href.indexOf('amin-v3') !== -1) {
              node.disabled = true;
              node.remove();
              console.log('🚫 Blocked dynamic CSS:', href);
            }
          }
        });
      });
    });
    observer.observe(document.head, { childList: true });
    observer.observe(document.body, { childList: true });
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

// تشغيل مرة ثانية بعد load كاملة لضمان فرض الهوية
window.addEventListener('load', function() {
  setTimeout(function(){
    forceIdentity();
    disableOldCSS();
  }, 500);
});

})();

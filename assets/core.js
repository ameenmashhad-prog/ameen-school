<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>بوابة ولي الأمر — مدارس أمين الرضا</title>
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" type="image/svg+xml" href="/favicon.svg">
<link rel="stylesheet" href="assets/portal.css">
<link rel="stylesheet" href="assets/amin-identity.css">
<link rel="stylesheet" href="assets/brand-redesign.css">
<link rel="stylesheet" href="assets/amin-v3.css">
<link rel="stylesheet" href="assets/i18n.css">
<link rel="manifest" href="manifest.webmanifest">
<link rel="apple-touch-icon" href="assets/amin-logo-small.png">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="أمين الرضا">
</head>
<body data-portal="parent">
<a class="skip-link" href="#mainContent">تخطي إلى المحتوى</a>

<div class="shell">
  <aside class="sidebar" id="sidebar">
    <div class="brand">
      <div class="brand-mark">و</div>
      <div>
        <h1>بوابة ولي الأمر</h1>
        <small>متابعة الأبناء · درجات · أقساط</small>
      </div>
    </div>
    
    <div class="profile-mini">
      <div class="avatar">👨‍👩‍👧</div>
      <div>
        <b id="profileName">...</b>
        <small id="profileRole">...</small>
      </div>
    </div>

    <nav class="nav">
      <button onclick="location.href='portal.html'">🏛️ البوابة الموحدة</button>
      <button data-view="overview" class="active">🏠 الرئيسية</button>
      <button data-view="grades">📊 الدرجات</button>
      <button data-view="attendance">📋 الحضور</button>
      <button data-view="finance">💰 الأقساط</button>
      <button data-view="behavior">🌟 السلوك</button>
      <button onclick="location.href='student-homeworks.html'">📚 الواجبات</button>
      <button onclick="location.href='notifications.html'">🔔 الإشعارات</button>
      <button onclick="location.href='smart-calendar.html'">📅 التقويم</button>
    </nav>

    <div class="side-footer">
      <button id="logoutBtn" class="btn red block">تسجيل الخروج</button>
    </div>
  </aside>

  <main class="main" id="mainContent" tabindex="-1">
    <header class="topbar">
      <button class="btn mobile-menu" id="mobileMenuBtn">☰</button>
      <h2>بوابة ولي الأمر</h2>
      <div class="top-actions">
        <select id="childSelector" class="select" style="display:none; min-width: 200px; padding:8px; border-radius:8px;"></select>
      </div>
    </header>

    <section id="view-overview" class="view active"></section>
    <section id="view-grades" class="view"></section>
    <section id="view-attendance" 

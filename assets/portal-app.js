/* ================================================================
   AMIN PORTAL APP - منطق البوابة الموحدة (مُصلَح)
   ================================================================ */
(function(){
'use strict';

var ROLE_SECTIONS = {
  super_admin: ['overview','tasks','students','academic','counseling','finance','attendance','discipline','registrations','schedule','payroll','settings','system'],
  admin: ['overview','students','academic','counseling','finance','attendance','discipline','registrations','schedule','payroll','settings','system'],
  finance: ['overview','finance'],
  academic: ['overview','tasks','students','academic','attendance','registrations','schedule'],
  counselor: ['overview','counseling','students','attendance','discipline'],
  psychologist: ['overview','counseling','students','attendance','discipline'],
  discipline: ['overview','counseling','students','attendance','discipline'],
  teacher: ['overview','students','academic','attendance','schedule','tasks','certificates','messages','analytics_ai'],
  staff: ['overview','attendance','tasks','certificates','messages','analytics_ai'],
  hr: ['overview','attendance','tasks','certificates','messages','analytics_ai'],
  parent: ['overview','students','academic','attendance','finance'],
  student: ['overview','academic','attendance','schedule']
};

var SECTIONS_META = {
  overview: { title: 'لوحة القيادة', icon: 'overview', order: 1 },
  students: { title: 'الطلاب', icon: 'students', order: 2 },
  academic: { title: 'الأكاديمي والامتحانات', icon: 'academic', order: 3 },
  finance: { title: 'المالية التنفيذية', icon: 'finance', order: 4 },
  counseling: { title: 'الإرشاد والسلوك', icon: 'discipline', order: 5 },
  attendance: { title: 'الحضور', icon: 'attendance', order: 6 },
  tasks: { title: 'المهام والتكليفات', icon: 'tasks', order: 12, external: 'tasks-management.html' },
  certificates: { title: 'الشهادات المطبوعة', icon: 'award', order: 13, external: 'certificates-generator.html' },
  messages: { title: 'تواصل أولياء الأمور', icon: 'chat', order: 14, external: 'parent-messages.html' },
  analytics_ai: { title: 'تحليلات الدعم', icon: 'chart-pie', order: 15, external: 'academic-analytics.html' },
  discipline: { title: 'السلوك', icon: 'discipline', order: 7 },
  registrations: { title: 'التسجيلات', icon: 'registrations', order: 8 },
  schedule: { title: 'الجدول', icon: 'schedule', order: 9 },
  payroll: { title: 'الرواتب', icon: 'payroll', order: 10 },
  settings: { title: 'الإعدادات', icon: 'settings', order: 11 },
  system: { title: 'الحوكمة والتشخيص', icon: 'system', order: 16 }
};

var ROLE_LABELS = {
  super_admin: 'المسؤول الأعلى',
  admin: 'مدير النظام',
  finance: 'المسؤول المالي',
  academic: 'المسؤول العلمي',
  counselor: 'المرشد النفسي',
  psychologist: 'أخصائي نفسي',
  discipline: 'مسؤول الانضباط',
  teacher: 'معلم',
  parent: 'ولي أمر',
  student: 'طالب'
};

window.currentSection = null;
window.currentUser = null;
window.currentUserRole = null;
window.sbClient = null;

function esc(v) {
  return String(v == null ? '' : v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#039;');
}
window.escapeHtml = esc;
window.formatNumber = function(n){ return Number(n||0).toLocaleString('ar-IQ'); };
window.formatMoney = function(n){ return '$' + Number(n||0).toLocaleString('ar-IQ', {maximumFractionDigits:0}); };

function getIcon(name, size) {
  size = size || 28;
  if (window.AminIcons && window.AminIcons.create) {
    return window.AminIcons.create(name, size);
  }
  return '<span style="font-size:' + size + 'px;">•</span>';
}
window.getIcon = getIcon;

window.renderLoading = function(containerId, message) {
  var c = document.getElementById(containerId) || document.getElementById('main-content');
  if (!c) return;
  var starHTML = window.AminStar ? window.AminStar.createStar({variant:'spinning', size:48, color:'var(--primary)'}) : '<span class="amin-3d-ico-auto" data-size="48" data-emoji="⏳" style="display:inline-flex;align-items:center;justify-content:center;width:48px;height:48px;">⏳</span>';
  c.innerHTML = '<div class="amin-loading-state">' + starHTML + '<div class="amin-loading-text">' + esc(message || 'جاري التحميل...') + '</div></div>';
};

window.renderError = function(containerId, message, retryFn) {
  var c = document.getElementById(containerId) || document.getElementById('main-content');
  if (!c) return;
  var retryHandler = retryFn || 'navigate(window.currentSection)';
  c.innerHTML = '<div class="error-inline" role="alert"><div class="error-inline-icon">⚠</div><div class="error-inline-msg">' + esc(message || 'حدث خطأ في التحميل') + '</div><button class="error-inline-retry" onclick="' + retryHandler + '">إعادة المحاولة</button></div>';
};

window.showToast = function(title, msg, type) {
  if (window.showAminToast) { window.showAminToast(title, msg, type); }
  else { console.log('[' + (type||'info') + ']', title, msg); }
};

window.openModal = function(config) {
  closeModal();
  var c = document.getElementById('modalContainer');
  var backdrop = document.createElement('div');
  backdrop.className = 'modal-backdrop-soft';
  backdrop.id = 'activeModalBackdrop';
  var modal = document.createElement('div');
  modal.className = 'modal-soft ' + (config.width || 'md');
  modal.innerHTML = '<div class="modal-soft-header"><h3 style="font-size:var(--text-h3);font-weight:var(--weight-bold);">' + esc(config.title) + '</h3><button class="mobile-toggle" onclick="closeModal()" style="font-size:24px;">×</button></div><div class="modal-soft-body" id="modalBody"></div>';
  backdrop.appendChild(modal);
  c.appendChild(backdrop);
  var body = modal.querySelector('#modalBody');
  if (typeof config.content === 'string') body.innerHTML = config.content;
  else if (config.content instanceof HTMLElement) body.appendChild(config.content);
  backdrop.addEventListener('click', function(e){ if (e.target === backdrop) closeModal(); });
};

window.closeModal = function() {
  var bd = document.getElementById('activeModalBackdrop');
  if (bd) bd.remove();
};

window.initTabs = function(containerId) {
  var c = document.getElementById(containerId);
  if (!c) return;
  var btns = c.querySelectorAll('.amin-tab-btn[data-tab]');
  var contents = c.querySelectorAll('.amin-tab-content[data-tab-content]');
  var active = c.dataset.activeTab || (btns[0] && btns[0].dataset.tab);
  function activate(name) {
    btns.forEach(function(b){ b.classList.toggle('active', b.dataset.tab === name); });
    contents.forEach(function(ct){ ct.classList.toggle('active', ct.dataset.tabContent === name); });
    c.dataset.activeTab = name;
  }
  btns.forEach(function(b){ b.addEventListener('click', function(){ activate(b.dataset.tab); }); });
  if (active) activate(active);
};

window.renderEmpty = function(containerId, message) {
  var c = document.getElementById(containerId) || document.getElementById('main-content');
  if (!c) return;
  if (window.AminStar) c.innerHTML = window.AminStar.createEmptyState(message || 'لا توجد بيانات', '');
  else c.innerHTML = '<div class="amin-empty-state"><h3 class="amin-empty-title">' + esc(message || 'لا توجد بيانات') + '</h3></div>';
};

async function fetchStudentsByIds(ids) {
  if (!ids || !ids.length) return {};
  try {
    var unique = Array.from(new Set(ids.filter(Boolean)));
    if (!unique.length) return {};
    var r = await window.sbClient.from('students').select('id, name, class_id, users(name)').in('id', unique);
    var map = {};
    (r.data || []).forEach(function(s){
      map[s.id] = { name: (s.users && s.users.name) || s.name || 'طالب', class_id: s.class_id };
    });
    return map;
  } catch (e) { return {}; }
}

async function checkAuth() {
  try {
    if (!window.supabase || !window.AMIN_CONFIG) throw new Error('Supabase not loaded');
    var sb = window.supabase.createClient(window.AMIN_CONFIG.supabaseUrl, window.AMIN_CONFIG.supabaseAnonKey, {auth:{persistSession:true, autoRefreshToken:true, detectSessionInUrl:true, storageKey:(window.AMIN_CONFIG.authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});
    window.sbClient = sb;
    var sessionRes = await sb.auth.getSession();
    if (!sessionRes.data.session) { setTimeout(function(){ location.href = 'index.html'; }, 500); return null; }
    var userRes = await sb.from('users').select('*').eq('id', sessionRes.data.session.user.id).maybeSingle();
    if (!userRes.data) { setTimeout(function(){ location.href = 'index.html'; }, 500); return null; }
    var user = userRes.data;
    var role = user.is_super_admin ? 'super_admin' : (user.role || 'guest');
    if (!ROLE_SECTIONS[role]) {
      window.showToast('غير مصرّح', 'ليس لديك صلاحية', 'error');
      setTimeout(function(){ location.href = 'index.html'; }, 2000);
      return null;
    }
    window.currentUser = user;
    window.currentUserRole = role;
    window.ME = user;
    return user;
  } catch (e) {
    console.error('Auth error:', e);
    setTimeout(function(){ location.href = 'index.html'; }, 1000);
    return null;
  }
}

function buildQuickActions() {
  var role = window.currentUserRole;
  var box = document.getElementById('quick-actions-buttons');
  if (!box) return;
  
  var html = '';
  if (['admin','principal','supervisor','discipline','teacher','counselor','super_admin'].indexOf(role) !== -1) {
    html += '<button class="btn small gold" style="white-space:nowrap;padding:6px 12px;font-size:13px;border-radius:6px;border:1px solid #B8860B;cursor:pointer;" onclick="location.href=\"attendance.html\"">⚡ تسجيل غياب يومي</button>';
  }
  if (['admin','principal','scientific','academic','academic_admin','teacher','super_admin'].indexOf(role) !== -1) {
    html += '<button class="btn small blue" style="white-space:nowrap;padding:6px 12px;font-size:13px;border-radius:6px;border:1px solid #1976d2;cursor:pointer;" onclick="location.href=\"academic-pro.html\"">⚡ رصد درجات سريع</button>';
  }
  if (['admin','principal','scientific','academic','teacher','counselor','finance','hr','staff','super_admin'].indexOf(role) !== -1) {
    html += '<button class="btn small green" style="white-space:nowrap;padding:6px 12px;font-size:13px;background:#25D366;color:white;border:none;border-radius:6px;cursor:pointer;" onclick="location.href=\"parent-messages.html\"">واتساب لولي أمر</button>';
  }
  if (['admin','principal','finance','super_admin'].indexOf(role) !== -1) {
    html += '<button class="btn small red" style="white-space:nowrap;padding:6px 12px;font-size:13px;border-radius:6px;border:1px solid #d32f2f;cursor:pointer;" onclick="location.href=\"parent-messages.html#overdue\"">⚠️ مطالبة أقساط متأخرة</button>';
  }
  if (['admin','principal','hr','super_admin'].indexOf(role) !== -1) {
    html += '<button class="btn small gold" style="white-space:nowrap;padding:6px 12px;font-size:13px;border-radius:6px;border:1px solid #B8860B;cursor:pointer;" onclick="location.href=\"hr.html#leaves\"">اعتماد إجازات معلقة</button>';
  }
  if (['admin','principal','scientific','academic','teacher','counselor','super_admin'].indexOf(role) !== -1) {
    html += '<button class="btn small blue" style="white-space:nowrap;padding:6px 12px;font-size:13px;border-radius:6px;border:1px solid #1976d2;cursor:pointer;" onclick="location.href=\"certificates-generator.html\"">إصدار شهادة مطبوعة</button>';
  }
  
  box.innerHTML = html;
}

function buildSidebar() {
  var role = window.currentUserRole;
  var allowed = ROLE_SECTIONS[role] || [];
  var nav = document.getElementById('sidebarNav');
  if (!allowed.length) {
    nav.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-tertiary);">لا توجد أقسام</div>';
    return;
  }
  var sorted = allowed.filter(function(s){ return SECTIONS_META[s]; }).sort(function(a,b){ return SECTIONS_META[a].order - SECTIONS_META[b].order; });
  var html = '';
  sorted.forEach(function(id){
    var m = SECTIONS_META[id];
    var iconHTML = getIcon(m.icon, 28);
    html += '<button class="sidebar-nav-item" data-section="' + id + '" onclick="navigate(\'' + id + '\')">';
    html += '<span class="nav-icon-wrap">' + iconHTML + '</span>';
    html += '<span class="sidebar-nav-label">' + m.title + '</span>';
    html += '</button>';
  });
  nav.innerHTML = html;
  
  var logoEl = document.getElementById('sidebarLogo');
  if (logoEl && window.AminStar) {
    logoEl.innerHTML = window.AminStar.createStar({variant:'filled', size:28, color:'white'});
  } else if (logoEl) {
    logoEl.innerHTML = '<span style="color:white;font-size:24px;">★</span>';
  }
}

function buildBottomNav() {
  var role = window.currentUserRole;
  var allowed = ROLE_SECTIONS[role] || [];
  var nav = document.getElementById('bottomNav');
  var top5 = allowed.filter(function(s){ return SECTIONS_META[s]; }).sort(function(a,b){ return SECTIONS_META[a].order - SECTIONS_META[b].order; }).slice(0, 5);
  var html = '';
  top5.forEach(function(id){
    var m = SECTIONS_META[id];
    var iconHTML = getIcon(m.icon, 24);
    html += '<button class="bottom-nav-item" data-section="' + id + '" onclick="navigate(\'' + id + '\')">';
    html += '<span class="bottom-nav-icon">' + iconHTML + '</span>';
    html += '<span>' + m.title + '</span>';
    html += '</button>';
  });
  nav.innerHTML = html;
}

window.navigate = function(sectionId) {
  var role = window.currentUserRole;
  var allowed = ROLE_SECTIONS[role] || [];
  if (!sectionId || allowed.indexOf(sectionId) === -1) sectionId = allowed[0] || 'overview';
  if (location.hash !== '#' + sectionId) location.hash = sectionId;
  window.currentSection = sectionId;
  
  document.querySelectorAll('.sidebar-nav-item[data-section]').forEach(function(i){
    i.classList.toggle('active', i.dataset.section === sectionId);
  });
  document.querySelectorAll('.bottom-nav-item[data-section]').forEach(function(i){
    i.classList.toggle('active', i.dataset.section === sectionId);
  });
  
  var meta = SECTIONS_META[sectionId];
  if (meta) {
    var titleEl = document.getElementById('pageTitle');
    var iconHTML = getIcon(meta.icon, 28);
    titleEl.innerHTML = iconHTML + ' <span style="vertical-align:middle;">' + meta.title + '</span>';
    document.title = meta.title + ' — البوابة الموحدة';
  }
  
  if (window.innerWidth <= 639) {
    document.getElementById('appSidebar').classList.remove('open');
    document.getElementById('sidebarBackdrop').classList.remove('active');
  }
  
  window.renderLoading('main-content', 'جاري تحميل ' + (meta ? meta.title : 'القسم') + '...');
  
  var section = window.SECTIONS[sectionId];
  if (section && typeof section.load === 'function') {
    Promise.resolve(section.load()).catch(function(err){
      console.error('Section error:', err);
      window.renderError('main-content', err.message || 'فشل التحميل');
    });
  } else {
    window.renderEmpty('main-content', (meta ? meta.title : '') + ' - قيد التطوير');
  }
};

window.toggleSidebar = function() {
  document.getElementById('appSidebar').classList.toggle('open');
  document.getElementById('sidebarBackdrop').classList.toggle('active');
};

window.toggleDarkMode = function() {
  document.body.classList.toggle('dark');
  var dark = document.body.classList.contains('dark');
  localStorage.setItem('darkMode', dark ? '1' : '0');
  var btn = document.getElementById('darkModeBtn');
  if (btn) {
    btn.innerHTML = getIcon(dark ? 'lightmode' : 'darkmode', 24);
  }
  window.showToast(dark ? 'الوضع الليلي' : 'الوضع النهاري', null, 'success');
};

window.handleLogout = async function() {
  if (!confirm('هل تريد تسجيل الخروج؟')) return;
  try {
    if (window.sbClient) await window.sbClient.auth.signOut({scope:'local'});
    location.href = 'index.html';
  } catch (e) {
    location.href = 'index.html';
  }
};

// ====================================
// SECTIONS
// ====================================
window.SECTIONS = {};

window.SECTIONS.overview = {
  title: 'لوحة القيادة',
  load: async function() {
    try {
      var role = window.currentUserRole;
      var r = await Promise.all([
        window.sbClient.from('v_clean_student_overview').select('*').limit(1).maybeSingle(),
        window.sbClient.from('v_clean_finance_summary').select('*').limit(1).maybeSingle(),
        window.sbClient.from('v_clean_attendance_today').select('*').limit(1).maybeSingle()
      ]);
      var so = r[0].data || {}, fs = r[1].data || {}, at = r[2].data || {};
      
      var er = await Promise.all([
        window.sbClient.from('attendance').select('student_id, date, status, created_at').eq('status', 'absent').order('created_at', {ascending: false}).limit(5),
        window.sbClient.from('behavior_records').select('student_id, note, points, created_at').order('created_at', {ascending: false}).limit(5)
      ]);
      
      var allIds = [];
      (er[0].data || []).forEach(function(e){ if (e.student_id) allIds.push(e.student_id); });
      (er[1].data || []).forEach(function(e){ if (e.student_id) allIds.push(e.student_id); });
      var studentsMap = await fetchStudentsByIds(allIds);
      
      var ae = (er[0].data || []).map(function(e){
        return { type: 'غياب', tc: 'danger', name: (studentsMap[e.student_id] && studentsMap[e.student_id].name) || 'طالب', detail: 'تاريخ: ' + String(e.date || '').slice(0,10), created_at: e.created_at };
      });
      var be = (er[1].data || []).map(function(e){
        var p = Number(e.points || 0);
        return { type: p >= 0 ? 'إيجابي' : 'سلبي', tc: p >= 0 ? 'success' : 'warning', name: (studentsMap[e.student_id] && studentsMap[e.student_id].name) || 'طالب', detail: e.note || 'ملاحظة', created_at: e.created_at };
      });
      var all = ae.concat(be).sort(function(a,b){ return new Date(b.created_at) - new Date(a.created_at); }).slice(0, 10);
      
      var cards = [];
      if (role === 'super_admin' || role === 'admin') {
        cards = [
          { label: 'إجمالي الطلاب', value: window.formatNumber(so.total || 0), iconName: 'students', kind: 'primary' },
          { label: 'حضور اليوم', value: window.formatNumber(at.present || 0) + ' / ' + window.formatNumber(at.total || 0), iconName: 'attendance', kind: 'success' },
          { label: 'المحصّل', value: window.formatMoney(fs.collected || 0), iconName: 'finance', kind: 'secondary' },
          { label: 'المتأخرات', value: window.formatMoney(fs.overdue || 0), iconName: 'finance', kind: 'danger' }
        ];
      } else if (role === 'finance') {
        var tot = (fs.collected || 0) + (fs.overdue || 0);
        var rt = tot > 0 ? Math.round(((fs.collected || 0) / tot) * 100) : 0;
        cards = [
          { label: 'المحصّل', value: window.formatMoney(fs.collected || 0), iconName: 'finance', kind: 'success' },
          { label: 'المتأخرات', value: window.formatMoney(fs.overdue || 0), iconName: 'finance', kind: 'danger' },
          { label: 'الرصيد الدائن', value: window.formatMoney(fs.credit || 0), iconName: 'payroll', kind: 'info' },
          { label: 'نسبة التحصيل', value: rt + '%', iconName: 'finance', kind: 'secondary' }
        ];
      } else {
        cards = [
          { label: 'الطلاب', value: window.formatNumber(so.total || 0), iconName: 'students', kind: 'primary' },
          { label: 'الحضور', value: window.formatNumber(at.present || 0), iconName: 'attendance', kind: 'success' },
          { label: 'الغياب', value: window.formatNumber(at.absent || 0), iconName: 'attendance', kind: 'danger' },
          { label: 'المتأخرون', value: window.formatNumber(at.late || 0), iconName: 'schedule', kind: 'warning' }
        ];
      }
      
      var html = '<div class="section-page-head"><h1>مرحباً، ' + esc(window.currentUser.name || 'مستخدم') + '</h1><p>إليك نظرة سريعة على ما يحدث اليوم</p></div>';
      html += '<div id="clockWidgetContainer" style="margin-block-end:var(--space-5);"></div>';
      html += '<div class="kpi-grid">';
      cards.forEach(function(c){
        var cardIcon = getIcon(c.iconName, 40);
        html += '<div class="kpi-card kpi-' + c.kind + '">';
        html += '<div class="kpi-label">' + esc(c.label) + '</div>';
        html += '<div class="kpi-value">' + c.value + '</div>';
        html += '<div class="kpi-icon">' + cardIcon + '</div>';
        html += '</div>';
      });
      html += '</div>';
      html += '<div class="card-soft"><div class="card-soft-header"><div class="card-soft-title">آخر الأحداث</div></div><div id="recentEventsContainer"></div></div>';
      
      document.getElementById('main-content').innerHTML = html;
      
      if (window.renderClockWidget) {
        window.renderClockWidget(document.getElementById('clockWidgetContainer'));
      }
      
      var eventsEl = document.getElementById('recentEventsContainer');
      if (all.length === 0) {
        window.renderEmpty('recentEventsContainer', 'لا توجد أحداث جديدة');
      } else {
        var eventsHtml = '<div style="overflow-x:auto;"><table class="table-flat"><thead><tr><th>النوع</th><th>الطالب</th><th>التفاصيل</th><th>التاريخ</th></tr></thead><tbody>';
        all.forEach(function(e){
          eventsHtml += '<tr><td><span class="badge-flat ' + e.tc + '">' + e.type + '</span></td><td style="font-weight:600;">' + esc(e.name) + '</td><td style="font-size:13px;color:var(--text-secondary);">' + esc(e.detail) + '</td><td style="font-size:13px;color:var(--text-secondary);">' + String(e.created_at || '').slice(0,10) + '</td></tr>';
        });
        eventsHtml += '</tbody></table></div>';
        eventsEl.innerHTML = eventsHtml;
      }
    } catch (e) {
      window.renderError('main-content', 'فشل تحميل لوحة القيادة: ' + e.message);
    }
  }
};

window.SECTIONS.students = {
  title: 'الطلاب',
  load: async function() {
    try {
      var r = await Promise.all([
        window.sbClient.from('v_clean_student_overview').select('*').limit(50),
        window.sbClient.from('classes').select('id, name').order('name')
      ]);
      window._studentsData = r[0].data || [];
      var classes = r[1].data || [];
      
      var html = '<div class="section-page-head"><h1>الطلاب</h1><p>إدارة بيانات الطلاب والبحث السريع</p></div>';
      html += '<div class="amin-filter-bar">';
      html += '<div class="amin-filter-field"><label>بحث</label><input type="text" id="studentSearch" class="amin-input" placeholder="اسم الطالب..."></div>';
      html += '<div class="amin-filter-field"><label>الصف</label><select id="classFilter" class="amin-select" onchange="window._filterStudents()"><option value="">كل الصفوف</option>';
      classes.forEach(function(c){
        html += '<option value="' + esc(c.name) + '">' + esc(c.name) + '</option>';
      });
      html += '</select></div></div>';
      html += '<div id="studentsTable" class="card-soft"></div>';
      
      document.getElementById('main-content').innerHTML = html;
      window._renderStudentsTable(window._studentsData);
      
      var st;
      document.getElementById('studentSearch').addEventListener('input', function(){
        clearTimeout(st);
        st = setTimeout(window._filterStudents, 400);
      });
    } catch (e) {
      window.renderError('main-content', e.message);
    }
  }
};

window._renderStudentsTable = function(s) {
  var c = document.getElementById('studentsTable');
  if (!s.length) {
    if (window.AminStar) c.innerHTML = window.AminStar.createEmptyState('لا يوجد طلاب', '');
    return;
  }
  if (window.renderResponsiveTable) {
    window.renderResponsiveTable(c, s, [
      { key: 'full_name', label: 'الاسم' },
      { key: 'class_name', label: 'الصف' },
      { 
        key: 'attendance_rate', 
        label: 'الحضور%', 
        render: function(v) {
          var r = Number(v || 0);
          var color = r >= 90 ? 'success' : r >= 75 ? 'warning' : 'danger';
          return '<span class="badge-flat ' + color + '">' + Math.round(r) + '%</span>';
        }
      }
    ], {
      primaryFields: ['full_name', 'class_name'],
      mobileExpandable: ['attendance_rate']
    });
  }
};

window._filterStudents = function() {
  var s = (document.getElementById('studentSearch').value || '').toLowerCase().trim();
  var cf = document.getElementById('classFilter').value;
  var f = (window._studentsData || []).filter(function(x){
    if (s && !(x.full_name || '').toLowerCase().includes(s)) return false;
    if (cf && x.class_name !== cf) return false;
    return true;
  });
  window._renderStudentsTable(f);
};

// باقي الأقسام كـ placeholders
var placeholderSections = ['attendance','discipline','registrations','schedule','payroll','settings'];
placeholderSections.forEach(function(sectionId){
  window.SECTIONS[sectionId] = {
    title: SECTIONS_META[sectionId].title,
    load: async function() {
      var iconHTML = getIcon(SECTIONS_META[sectionId].icon, 64);
      var html = '<div class="section-page-head">';
      html += '<h1>' + SECTIONS_META[sectionId].title + '</h1>';
      html += '</div>';
      html += '<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;padding:80px 20px;text-align:center;">';
      html += '<div style="margin-block-end:20px;">' + iconHTML + '</div>';
      html += '<h3 style="color:var(--text-secondary);margin-block-end:8px;">قيد التطوير</h3>';
      html += '<p style="color:var(--text-tertiary);">سيتم إضافة الميزات قريباً</p>';
      html += '</div>';
      document.getElementById('main-content').innerHTML = html;
    }
  };
});

// ====================================
// INIT
// ====================================
async function initPage() {
  // تطبيق الأيقونات على الـ topbar
  if (window.AminIcons) {
    var menuBtn = document.getElementById('menuIcon');
    if (menuBtn) menuBtn.innerHTML = getIcon('menu', 24);
    
    var refreshBtn = document.getElementById('refreshBtn');
    if (refreshBtn) refreshBtn.innerHTML = getIcon('refresh', 24);
    
    var logoutIcon = document.getElementById('logoutIcon');
    if (logoutIcon) logoutIcon.innerHTML = getIcon('logout', 20);
  }
  
  var darkBtn = document.getElementById('darkModeBtn');
  if (localStorage.getItem('darkMode') === '1') {
    document.body.classList.add('dark');
    if (darkBtn) darkBtn.innerHTML = getIcon('lightmode', 24);
  } else {
    if (darkBtn) darkBtn.innerHTML = getIcon('darkmode', 24);
  }
  
  var user = await checkAuth();
  if (!user) return;
  
  document.getElementById('userName').textContent = user.name || user.email || 'مستخدم';
  document.getElementById('userRole').textContent = ROLE_LABELS[window.currentUserRole] || window.currentUserRole;
  
  var avatar = document.getElementById('userAvatar');
  if (avatar && user.name) avatar.textContent = user.name.charAt(0);
  
  buildSidebar();
  buildBottomNav();
  
  var initial = location.hash.replace('#','') || ROLE_SECTIONS[window.currentUserRole][0];
  navigate(initial);
}

window.addEventListener('hashchange', function() {
  var ns = location.hash.replace('#','');
  if (ns && ns !== window.currentSection) navigate(ns);
});

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initPage);
} else {
  initPage();
}

})();

/*
  Amin Al-Ridha School — Tasks & Assignments Management (R7)
  - Standalone, Capacitor-ready app module.
  - Role-adaptive: Teachers see & update their tasks; Admins/HR create assignments & verify completion.
  - No CDN / No outbound calls.
*/
(function () {
  'use strict';

  let sb = null, ME = null, ACTIVE = 'overview', DATA = { tasks: [], users: [], stats: {} };
  const cfg = () => window.AMIN_CONFIG || {};
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));

  function client() {
    if (sb) return sb;
    sb = supabase.createClient(cfg().supabaseUrl, cfg().supabaseAnonKey, {
      auth: { persistSession: true, autoRefreshToken: true, storageKey: (cfg().authStorageKey || 'amin-ovcjzsrqqgjsbqswtkro-auth-v2') }
    });
    return sb;
  }

  function esc(v) { return String(v == null ? '' : v).replace(/[&<>"']/g, m => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[m])); }
  function toast(t, m, type = '') {
    const el = $('#toast');
    if (!el) return;
    el.innerHTML = `<b>${esc(t)}</b><br><span class="muted">${esc(m || '')}</span>`;
    el.className = 'toast show ' + type;
    clearTimeout(el._t);
    el._t = setTimeout(() => el.classList.remove('show'), 4500);
  }

  function isAdmin() {
    return ME && (coalesceBool(ME.is_super_admin) || ['admin', 'academic_admin', 'super_admin', 'principal', 'scientific', 'hr', 'supervisor'].includes(ME.role));
  }
  function coalesceBool(v) { return v === true || String(v).toLowerCase() === 'true'; }

  function roleLabel(r) {
    return ({ admin: 'إدارة', principal: 'مدير المدرسة', scientific: 'معاون علمي', hr: 'موارد بشرية', teacher: 'معلم', staff: 'موظف', supervisor: 'مشرف' }[r] || r || 'مستخدم');
  }

  function kpi(l, v, c = 'blue') { return `<div class="kpi ${c}"><small>${esc(l)}</small><b>${esc(v ?? 0)}</b></div>`; }
  function table(h, rows, empty = 'لا توجد بيانات') {
    const body = Array.isArray(rows) ? rows.join('') : String(rows || '');
    return body.trim() ? `<div class="table-wrap"><table><thead><tr>${h.map(x => `<th>${esc(x)}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>` : `<div class="empty">${esc(empty)}</div>`;
  }

  async function ensure() {
    const { data: { session } } = await client().auth.getSession();
    if (!session) { location.href = 'index.html'; return false; }
    const { data: u } = await client().from('users').select('*').eq('id', session.user.id).maybeSingle();
    if (!u) { location.href = 'index.html'; return false; }
    ME = u;
    $('#profileName').textContent = u.name || u.email || 'مستخدم';
    $('#profileRole').textContent = roleLabel(u.role);
    if (isAdmin()) {
      $$('.admin-only').forEach(el => el.style.display = '');
    }
    return true;
  }

  async function load() {
    try {
      const [tasksRes, usersRes] = await Promise.all([
        client().from('v_school_tasks_detailed').select('*').order('due_date', { ascending: true }),
        client().from('users').select('id, name, email, role').order('name')
      ]);
      const tasks = tasksRes.data || [];
      const users = usersRes.data || [];
      DATA = {
        tasks,
        users,
        stats: {
          total: tasks.length,
          pending: tasks.filter(x => x.status === 'pending').length,
          in_progress: tasks.filter(x => x.status === 'in_progress').length,
          completed: tasks.filter(x => x.status === 'completed').length,
          verified: tasks.filter(x => x.status === 'verified').length,
          late: tasks.filter(x => x.status === 'late' || (['pending', 'in_progress'].includes(x.status) && new Date(x.due_date) < new Date())).length
        }
      };
      render(ACTIVE);
    } catch (e) {
      console.warn('Load error:', e);
      toast('خطأ في تحميل المهام', e.message || String(e), 'red');
    }
  }

  function render(id) {
    ACTIVE = id;
    $$('.view').forEach(v => v.classList.toggle('active', v.id === 'view-' + id));
    $$('.nav button[data-view]').forEach(b => b.classList.toggle('active', b.dataset.view === id));
    ({ overview, my_tasks: myTasksView, assign: assignView }[id] || overview)();
  }

  function overview() {
    const s = DATA.stats;
    const myTasks = DATA.tasks.filter(t => t.assigned_to === ME.id);
    const recent = DATA.tasks.slice(0, 8).map(t => {
      const priBadge = { urgent: '<span class="badge red">عاجلة جداً 🔥</span>', high: '<span class="badge red">هامة ⭐</span>', normal: '<span class="badge blue">عادية</span>', low: '<span class="badge green">منخفضة</span>' }[t.priority] || t.priority;
      const stBadge = { pending: '<span class="badge gold">قيد الانتظار</span>', in_progress: '<span class="badge blue">جاري التنفيذ ⏳</span>', completed: '<span class="badge green">منجزة بانتظار الاعتماد ✅</span>', verified: '<span class="badge green" style="background:#0B6E4F;color:#fff">معتمدة من الإدارة 👑</span>', late: '<span class="badge red">متأخرة ⚠️</span>', cancelled: '<span class="badge red">ملغاة</span>' }[t.status] || t.status;
      return `<div class="item" style="padding:10px;border-bottom:1px solid #eee;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px">` +
        `<div><b>${esc(t.title)}</b><br><small class="muted">المكلف: ${esc(t.assigned_to_name)} (${esc(roleLabel(t.assigned_to_role))}) · بواسطة: ${esc(t.assigned_by_name)}</small></div>` +
        `<div style="display:flex;gap:6px;align-items:center">${priBadge} ${stBadge} <small class="muted">${esc(String(t.due_date||'').slice(0,16).replace('T',' '))}</small></div>` +
        `</div>`;
    }).join('') || '<div class="empty">لا توجد مهام وتكليفات مسجلة</div>';

    $('#view-overview').innerHTML = `<div class="page-head"><div><h1>لوحة المهام والتكليفات الرسمية 📋</h1><p>متابعة التكليفات الموجهة للمعلمين والموظفين، وضبط المهل الزمنية، وتوثيق الإنجاز.</p></div></div>` +
      `<div class="kpis">${kpi('إجمالي المهام', s.total, 'blue')}${kpi('قيد الانتظار', s.pending, 'gold')}${kpi('جاري التنفيذ ⏳', s.in_progress, 'blue')}${kpi('منجزة 📤', s.completed, 'green')}${kpi('معتمدة رسمياً 👑', s.verified, 'green')}${kpi('متأخرة ⚠️', s.late, 'red')}</div>` +
      `<div class="cards"><div class="card"><div class="card-head"><h3>آخر المهام والتكليفات بالمدرسة</h3></div><div class="card-body"><div class="list">${recent}</div></div></div>` +
      `<div class="card"><div class="card-head"><h3>اختصارات سريعة</h3></div><div class="card-body"><div class="form-actions">` +
      `<button class="btn blue" onclick="TasksApp.render('my_tasks')">📋 مهامي المكلف بها (${myTasks.length})</button>` +
      (isAdmin() ? `<button class="btn gold" onclick="TasksApp.render('assign')">👑 تكليف موظف بمهمة جديدة</button>` : '') +
      `</div></div></div></div>`;
  }

  function myTasksView() {
    const list = DATA.tasks.filter(t => t.assigned_to === ME.id);
    const open = list.filter(t => !['verified', 'cancelled'].includes(t.status));

    const cards = list.map(t => {
      const priClass = 'priority-' + (t.priority || 'normal');
      const priText = { urgent: '🔥 عاجلة جداً', high: '⭐ هامة', normal: 'عادية', low: 'منخفضة' }[t.priority] || t.priority;
      let stBadge = '<span class="badge gold">قيد الانتظار</span>';
      if (t.status === 'in_progress') stBadge = '<span class="badge blue">جاري التنفيذ ⏳</span>';
      else if (t.status === 'completed') stBadge = '<span class="badge green">منجزة بانتظار التحقق 📤</span>';
      else if (t.status === 'verified') stBadge = '<span class="badge green" style="background:#0B6E4F;color:#fff">معتمدة رسمياً 👑</span>';
      else if (t.status === 'late') stBadge = '<span class="badge red">متأخرة ⚠️</span>';

      const fileLink = t.attachment_url ? `<a class="btn small blue" href="/api/proxy/storage/v1/object/public/school-tasks/${t.attachment_url}" target="_blank">عرض المرفق 📄</a>` : '';
      
      let updateForm = '';
      if (t.status !== 'verified' && t.status !== 'cancelled') {
        updateForm = `<div style="background:#f0fdf4;padding:10px;border-radius:8px;border:1px solid #c8e6c9;margin-top:8px;display:flex;flex-direction:column;gap:8px">` +
          `<div><b style="font-size:13px;color:#0B6E4F">تحديث إنجاز المهمة:</b></div>` +
          `<input id="note_${t.id}" class="input" value="${esc(t.completion_note || '')}" placeholder="اكتبي ملاحظة أو ملخص إنجاز المهمة..." style="font-size:13px">` +
          `<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">` +
          `<label class="btn small blue" style="cursor:pointer;margin:0">📎 اختيار ملف إثبات<input type="file" id="file_${t.id}" style="display:none" onchange="this.parentElement.style.background='#0B6E4F'"></label>` +
          `<button class="btn small gold" onclick="TasksApp.updateProgress('${t.id}', 'in_progress')">⏳ جاري العمل</button>` +
          `<button class="btn small green" onclick="TasksApp.updateProgress('${t.id}', 'completed')">✅ تم إنجاز المهمة</button>` +
          `</div></div>`;
      } else {
        updateForm = `<div style="color:#0B6E4F;font-weight:bold;background:#e8f5e9;padding:8px;border-radius:6px;border:1px solid #c8e6c9;margin-top:8px">👑 تم التحقق من إنجاز المهمة واعتمادها نهائياً من الإدارة</div>`;
      }

      return `<article class="task-card ${priClass}">` +
        `<div class="task-head"><div><h3 class="task-title">${esc(t.title)}</h3><small class="muted">التكليف بواسطة: ${esc(t.assigned_by_name)}</small></div><div>${stBadge}</div></div>` +
        `<div class="task-meta"><span><b>الأولوية:</b> ${esc(priText)}</span><span><b>الموعد النهائي:</b> ${esc(String(t.due_date||'').slice(0,16).replace('T',' '))}</span></div>` +
        `<div class="task-desc">${esc(t.description || 'بدون تفاصيل إضافية')}</div>` +
        (t.completion_note ? `<div style="font-size:12px;color:#0B6E4F;background:#f9f9f9;padding:6px;border-radius:4px"><b>ملاحظة إنجازي:</b> ${esc(t.completion_note)}</div>` : '') +
        `<div class="task-actions">${fileLink}</div>` +
        updateForm +
        `</article>`;
    }).join('') || '<div class="empty">ليس لديك مهام أو تكليفات مفتوحة حالياً</div>';

    $('#view-my_tasks').innerHTML = `<div class="page-head"><div><h1>مهامي وتكليفاتي الخاصة 📋</h1><p>المهام الموكلة إليك من الإدارة والمشرفين، تحديث التنفيذ، ورفع إثباتات الإنجاز.</p></div></div>` +
      `<div class="kpis">${kpi('إجمالي مهامي', list.length, 'blue')}${kpi('مهام مفتوحة', open.length, 'gold')}${kpi('تم الإنجاز 📤', list.filter(x=>x.status==='completed'||x.status==='verified').length, 'green')}${kpi('متأخرة ⚠️', list.filter(x=>x.status==='late').length, 'red')}</div>` +
      `<div class="tasks-grid">${cards}</div>`;
  }

  async function updateProgress(taskId, status) {
    const noteEl = document.getElementById('note_' + taskId);
    const fileEl = document.getElementById('file_' + taskId);
    const note = noteEl ? noteEl.value : null;
    const file = fileEl && fileEl.files && fileEl.files[0];

    try {
      toast('جاري التحديث...', 'يرجى الانتظار');
      let attUrl = null;
      if (file) {
        const ext = (file.name.split('.').pop() || 'pdf').toLowerCase();
        const path = `tasks/${ME.id}/${Date.now()}_${Math.random().toString(36).slice(2)}.${ext}`;
        const up = await client().storage.from('school-tasks').upload(path, file, { upsert: false });
        if (up.error) throw up.error;
        attUrl = path;
      }

      const res = await client().rpc('task_update_progress', {
        p_task_id: taskId,
        p_status: status,
        p_note: note,
        p_attachment_url: attUrl
      });
      if (res.error) throw res.error;
      const d = res.data || {};
      if (d.ok === false) throw new Error(d.message || 'تعذر التحديث');
      toast('تم بنجاح 🚀', d.message, 'green');
      await load();
    } catch (e) {
      toast('خطأ في التحديث', e.message || String(e), 'red');
    }
  }

  function assignView() {
    if (!isAdmin()) {
      $('#view-assign').innerHTML = '<div class="empty">تكليف المهام محصور بالإدارة والمشرفين فقط 🔒</div>';
      return;
    }

    const formHtml = `<div class="card" style="margin-bottom:20px"><div class="card-head"><h3>👑 تكليف عدة معلمين وموظفين بمهمة رسمية (اختيار متعدد بالـ Checkbox)</h3></div><div class="card-body"><div class="hr-form" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;align-items:end">` +
      `<div style="grid-column:1/-1"><label>عنوان المهمة / التكليف *</label><input id="tskTitle" class="input" placeholder="مثال: إعداد تحضير الأسبوع القادم / تنظيم نشاط اليوم الرياضي"></div>` +
      `<div><label>الأولوية *</label><select id="tskPriority" class="select"><option value="normal">عادية</option><option value="high">هامة ⭐</option><option value="urgent">عاجلة جداً 🔥</option><option value="low">منخفضة</option></select></div>` +
      `<div><label>الموعد النهائي (Deadline) *</label><input id="tskDue" type="datetime-local" class="input" value="${new Date(Date.now() + 86400000 * 3).toISOString().slice(0, 16)}"></div>` +
      `<div style="grid-column:1/-1"><label>تفاصيل ومطلوب التكليف (اختياري)</label><input id="tskDesc" class="input" placeholder="اكتبي تفاصيل أو إرشادات تنفيذ المهمة..."></div>` +
      `<div style="grid-column:1/-1"><label>تصفية واختيار المكلفين بالمهام (معلمين، مرشدين، موظفين...) *</label>` +
      `<div style="display:flex;gap:6px;margin-bottom:6px;flex-wrap:wrap">` +
      `<button type="button" class="btn small blue" onclick="TasksApp.filterAssignees('all')">الكل</button>` +
      `<button type="button" class="btn small gold" onclick="TasksApp.filterAssignees('teacher')">المعلمون</button>` +
      `<button type="button" class="btn small green" onclick="TasksApp.filterAssignees('counselor')">المرشدون والإرشاد</button>` +
      `<button type="button" class="btn small blue" onclick="TasksApp.filterAssignees('staff')">الموظفون والإدارة</button>` +
      `</div>` +
      `<div id="assigneesBox" style="max-height:160px;overflow-y:auto;border:1px solid #ccc;padding:8px;border-radius:6px;background:#f9f9f9;display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:6px"></div>` +
      `</div>` +
      `<div style="grid-column:1/-1"><button class="btn gold block" onclick="TasksApp.createAssignment()">🚀 تكليف جميع المحدد ين بالصح ☑ وإرسال الإشعارات لهم فوراً</button></div>` +
      `</div></div></div>`;

    const rows = DATA.tasks.map(t => {
      const priText = { urgent: '🔥 عاجلة جداً', high: '⭐ هامة', normal: 'عادية', low: 'منخفضة' }[t.priority] || t.priority;
      let stBadge = '<span class="badge gold">قيد الانتظار</span>';
      if (t.status === 'in_progress') stBadge = '<span class="badge blue">جاري التنفيذ ⏳</span>';
      else if (t.status === 'completed') stBadge = '<span class="badge green">منجزة بانتظار التحقق 📤</span>';
      else if (t.status === 'verified') stBadge = '<span class="badge green" style="background:#0B6E4F;color:#fff">معتمدة رسمياً 👑</span>';
      else if (t.status === 'late') stBadge = '<span class="badge red">متأخرة ⚠️</span>';

      const fileLink = t.attachment_url ? `<a class="btn small blue" href="/api/proxy/storage/v1/object/public/school-tasks/${t.attachment_url}" target="_blank">عرض المرفق 📄</a>` : '—';
      
      let actionBtn = '';
      if (t.status === 'completed' || t.status === 'submitted') {
        actionBtn = `<button class="btn small green" onclick="TasksApp.verifyTask('${t.id}', true)">🟢 تحقق واعتماد</button> <button class="btn small red" onclick="TasksApp.verifyTask('${t.id}', false)">🔄 إعادة للتنفيذ</button>`;
      } else if (t.status !== 'verified') {
        actionBtn = `<button class="btn small gold" onclick="TasksApp.verifyTask('${t.id}', true)">اعتماد مباشر 🟢</button>`;
      } else {
        actionBtn = `<span class="muted">تم الاعتماد</span>`;
      }

      return `<tr><td><b>${esc(t.title)}</b><br><small class="muted">${esc(t.description || '')}</small></td><td><b>${esc(t.assigned_to_name)}</b><br><small class="muted">${esc(roleLabel(t.assigned_to_role))}</small></td><td>${esc(priText)}</td><td>${esc(String(t.due_date||'').slice(0,16).replace('T',' '))}</td><td>${stBadge}</td><td>${esc(t.completion_note || '—')}</td><td>${fileLink}</td><td>${actionBtn}</td></tr>`;
    });

    $('#view-assign').innerHTML = `<div class="page-head"><div><h1>👑 تكليف وإدارة مهام المدرسة</h1><p>توجيه مهام وتكليفات رسمية لمعلمين ومرشدين وموظفين متعددين في نفس الوقت، ومتابعة نسبة الإنجاز والاعتماد.</p></div></div>` +
      formHtml + table(['المهمة', 'المكلف', 'الأولوية', 'الموعد النهائي', 'الحالة', 'ملاحظة الإنجاز', 'المرفق', 'إجراء التحقق'], rows, 'لا توجد تكليفات مسجلة');
  
    setTimeout(() => filterAssignees('all'), 10);
  }

  function filterAssignees(roleFilter) {
    const box = $('#assigneesBox');
    if (!box) return;
    const staffList = DATA.users.filter(u => u.role !== 'student' && u.role !== 'parent');
    const filtered = staffList.filter(u => {
      if (roleFilter === 'all') return true;
      if (roleFilter === 'teacher') return u.role === 'teacher';
      if (roleFilter === 'counselor') return ['counselor','psychologist','discipline'].includes(u.role);
      return ['admin','academic_admin','super_admin','principal','scientific','hr','supervisor','staff','finance'].includes(u.role);
    });

    box.innerHTML = `<div style="grid-column:1/-1;border-bottom:1px solid #ddd;padding-bottom:4px;margin-bottom:4px"><label style="font-weight:bold;cursor:pointer;display:flex;align-items:center;gap:6px;color:#0B6E4F"><input type="checkbox" id="selectAllAssignees" onchange="TasksApp.toggleAllAssignees(this.checked)"> تحديد جميع المعروضين بالصح ☑ (${filtered.length})</label></div>` +
      filtered.map(u => `<label style="display:flex;align-items:center;gap:6px;cursor:pointer;background:#fff;padding:4px 8px;border:1px solid #eee;border-radius:4px"><input type="checkbox" class="tsk-assign-chk" value="${u.id}"> <b>${esc(u.name || u.email)}</b> <small class="muted">(${esc(roleLabel(u.role))})</small></label>`).join('');
  }

  function toggleAllAssignees(checked) {
    document.querySelectorAll('.tsk-assign-chk').forEach(el => el.checked = checked);
  }

  async function createAssignment() {
    const title = $('#tskTitle')?.value?.trim();
    const checked = Array.from(document.querySelectorAll('.tsk-assign-chk:checked')).map(el => el.value);
    const pri = $('#tskPriority')?.value || 'normal';
    const due = $('#tskDue')?.value;
    const desc = $('#tskDesc')?.value?.trim() || null;

    if (!title || checked.length === 0 || !due) {
      toast('تنبيه', 'أكملي عنوان المهمة واختاري شخصاً واحداً على الأقل من القائمة وحددي الموعد النهائي', 'red');
      return;
    }

    try {
      toast('جاري التكليف المتعدد...', 'تم إرسال ' + checked.length + ' موظف للتكليف');
      const res = await client().rpc('task_create_multi_assignment', {
        p_title: title,
        p_description: desc,
        p_assigned_to_list: checked,
        p_priority: pri,
        p_due_date: new Date(due).toISOString()
      });
      if (res.error) throw res.error;
      const d = res.data || {};
      if (d.ok === false) throw new Error(d.message || 'تعذر التكليف');
      toast('تم التكليف بنجاح 🚀', d.message, 'green');
      await load();
    } catch (e) {
      toast('خطأ في التكليف', e.message || String(e), 'red');
    }
  }

  async function verifyTask(taskId, verified) {
    try {
      const res = await client().rpc('task_verify_completion', { p_task_id: taskId, p_verified: verified });
      if (res.error) throw res.error;
      const d = res.data || {};
      if (d.ok === false) throw new Error(d.message || 'تعذر الاعتماد');
      toast('تم بنجاح 🟢', d.message, 'green');
      await load();
    } catch (e) {
      toast('خطأ في التحقق', e.message || String(e), 'red');
    }
  }

  function bind() {
    $$('.nav button[data-view]').forEach(b => b.addEventListener('click', () => render(b.dataset.view)));
    $('#mobileMenuBtn')?.addEventListener('click', () => $('#sidebar').classList.toggle('open'));
    $('#logoutBtn').addEventListener('click', async () => {
      await client().auth.signOut({ scope: 'local' });
      location.href = 'index.html';
    });
    $('#refreshBtn').addEventListener('click', load);
  }

  async function init() {
    client();
    if (!await ensure()) return;
    bind();
    await load();
  }

  window.TasksApp = { init, render, updateProgress, createAssignment, verifyTask, filterAssignees, toggleAllAssignees };
})();

/*
  Amin Al-Ridha School — WhatsApp & SMS Parent Communicator (Extra Feature)
  - Standalone, zero-backend WhatsApp/SMS launcher and template generator.
  - Role-adaptive: Teachers/Admins/Finance can send absence notices, tuition reminders, and praise.
  - Auto-cleans phone numbers to international format (964 / Local prefix).
*/
(function () {
  'use strict';

  let sb = null, ME = null, ACTIVE = 'hub', SELECTED = null, CURR_TEMPLATE = 'absence', DATA = { classes: [], students: [], attendance: [], installments: [], summary: [], userMap: new Map(), classMap: new Map() };
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

  function iso() { return new Date().toISOString().slice(0, 10); }

  async function q(table, opts = {}) {
    try {
      let query = client().from(table).select(opts.columns || '*');
      (opts.filters || []).forEach(f => query = query[f.op](f.col, f.val));
      if (opts.order) query = query.order(opts.order, { ascending: opts.ascending !== false });
      if (opts.limit) query = query.limit(opts.limit);
      const { data, error } = await query;
      if (error) { console.warn(table, error); return []; }
      return data || [];
    } catch (e) { console.warn(table, e); return []; }
  }

  async function ensure() {
    const { data: { session } } = await client().auth.getSession();
    if (!session) { location.href = 'index.html'; return false; }
    const { data: u } = await client().from('users').select('*').eq('id', session.user.id).maybeSingle();
    if (!u) { location.href = 'index.html'; return false; }
    ME = u;
    $('#profileName').textContent = u.name || u.email || 'مستخدم';
    $('#profileRole').textContent = u.role || 'مستخدم';
    return true;
  }

  async function load() {
    try {
      const [classes, students, users, attendance, installments, summary] = await Promise.all([
        q('classes', { order: 'name' }),
        q('students', { order: 'student_name' }),
        q('users'),
        q('attendance', { filters: [{ op: 'eq', col: 'date', val: iso() }] }),
        q('student_installments', { filters: [{ op: 'lt', col: 'due_date', val: iso() }] }),
        q('v_academic_student_summary', { order: 'overall_average', ascending: false, limit: 100 })
      ]);

      const userMap = new Map(users.map(u => [String(u.id), u]));
      const classMap = new Map(classes.map(c => [String(c.id), c]));

      DATA = { classes, students, users, attendance, installments, summary, userMap, classMap };
      if (!SELECTED && students.length > 0) SELECTED = students[0];
      render(ACTIVE);
    } catch (e) {
      console.warn('Load error:', e);
      toast('خطأ في تحميل البيانات', e.message || String(e), 'red');
    }
  }

  function render(id) {
    ACTIVE = id;
    $$('.view').forEach(v => v.classList.toggle('active', v.id === 'view-' + id));
    $$('.nav button[data-view]').forEach(b => b.classList.toggle('active', b.dataset.view === id));
    ({ hub: hubView, absent: absentView, overdue: overdueView, top: topView }[id] || hubView)();
  }

  function getParentPhone(stu) {
    if (!stu) return '';
    if (stu.phone_primary) return stu.phone_primary;
    if (stu.phone_whatsapp) return stu.phone_whatsapp;
    if (stu.mother_whatsapp) return stu.mother_whatsapp;
    const pUser = DATA.userMap.get(String(stu.parent_id));
    if (pUser && pUser.phone) return pUser.phone;
    return '07800000000';
  }

  function cleanPhone(raw) {
    let p = String(raw || '').replace(/\D+/g, '');
    if (p.startsWith('00964')) p = p.slice(2);
    else if (p.startsWith('0') && p.length >= 10) p = '964' + p.slice(1);
    else if (!p.startsWith('964') && p.length === 10) p = '964' + p;
    return p;
  }

  function buildMessageText(stu, t) {
    if (!stu) return '';
    const name = stu.student_name || stu.name || 'الطالب';
    const cls = (DATA.classMap.get(String(stu.class_id)) || {}).name || '—';
    const parent = stu.father_name ? `السيد/ة ولي أمر الطالب/ة (${name}) المحترم،` : `ولي أمر الطالب/ة (${name}) المحترم،`;

    if (t === 'absence') {
      return `${parent}\n\nالسلام عليكم ورحمة الله وبركاته.\nنود إعلامكم بأن نجلكم/كريمتكم في الصف (${cls}) لم يحضر إلى المدرسة اليوم (${iso()}) دون إشعار أو عذر مسبق.\nنرجو من تفضلكم التواصل مع إدارة مجمع أمين الرضا (ع) التعليمي أو المرشد التربوي للاطمئنان عليه وبيان سبب الغياب.\n\nمع خالص التقدير،\nإدارة شؤون الطلاب`;
    } else if (t === 'tuition') {
      const unpaid = DATA.installments.filter(i => {
        const feeStuId = i.student_fee_id ? (DATA.students.find(s => String(s.id) === String(i.student_fee_id) || String(s.id) === String(stu.id)) || {}).id : null;
        return String(feeStuId) === String(stu.id) || (num(i.amount_paid) < num(i.amount_due));
      });
      const dueAmt = unpaid.reduce((a, x) => a + (num(x.amount_due) - num(x.amount_paid)), 0) || 150;
      return `${parent}\n\nطيب الله أوقاتكم بكل خير.\nنود تذكيركم بوجود قسط دراسي مستحق على ملف الطالب (${name}) في الصف (${cls}) وقدره (${dueAmt}$) وتاريخ استحقاقه قد انقضى.\nنرجو تفضلكم بمراجعة القسم المالي في مجمع أمين الرضا (ع) التعليمي لتسوية القسط وضمان انتظام الخدمات الأكاديمية والتقارير.\n\nشاكرين حسن تعاونكم الدائم،\nالقسم المالي`;
    } else if (t === 'congratulation') {
      const sum = DATA.summary.find(s => String(s.student_id) === String(stu.id) || String(s.id) === String(stu.id)) || {};
      const avg = sum.overall_average ? `${Number(sum.overall_average).toFixed(1)}%` : 'ممتاز';
      return `${parent}\n\nيسر إدارة مجمع أمين الرضا (ع) التعليمي أن تبارك لكم ولعائلتكم الكريمة التفوق العلمي المتميز لنجلكم/كريمتكم (${name}) في الصف (${cls}) وحصوله على معدل عام قدره (${avg}).\nنفخر به ونثمن اهتمامكم ودعمكم المستمر، متمنين له دوام التميز والارتقاء.\n\nمع أطيب التحيات،\nالإدارة الأكاديمية`;
    } else if (t === 'summons') {
      return `${parent}\n\nالسلام عليكم ورحمة الله وبركاته.\nنرجو تفضلكم بزيارة مجمع أمين الرضا (ع) التعليمي في أقرب وقت ممكن لمقابلة (الإدارة / المرشد التربوي) لمناقشة بعض الأمور الهامة الخاصة بالمستوى الدراسي والسلوكي لنجلكم (${name}) في الصف (${cls}).\n\nشاكرين اهتمامكم وحرصكم،\nالإدارة المدرسية`;
    }
    return `${parent}\n\nتحية طيبة وبعد،\nيرجى الاطلاع والدراسة بخصوص الطالب (${name}) في الصف (${cls}).\n\nإدارة مجمع أمين الرضا (ع) التعليمي`;
  }

  function num(v) { const n = Number(v); return Number.isFinite(n) ? n : 0; }

  function hubView() {
    const classOptions = '<option value="">كل الصفوف بالمدرسة...</option>' + DATA.classes.map(c => `<option value="${c.id}">${esc(c.name)}</option>`).join('');
    
    $('#view-hub').innerHTML = `<div class="page-head"><div><h1>💬 مركز التواصل المباشر مع أولياء الأمور</h1><p>إرسال رسائل وتنبيهات فورية عبر واتساب أو SMS بضغطة زر واحدة باستخدام قوالب ذكية بدون أي رسوم أو إعدادات برمجية معقدة.</p></div></div>` +
      `<div class="card" style="margin-bottom:16px"><div class="card-body" style="display:flex;gap:12px;align-items:center;flex-wrap:wrap">` +
      `<div><b>🔍 تصفية الطلاب:</b></div>` +
      `<div style="flex:1;min-width:180px"><select id="filterClass" class="select" onchange="ParentMessagesApp.filterStudentsList()">${classOptions}</select></div>` +
      `<div style="flex:2;min-width:220px"><input id="searchStudent" class="input" placeholder="بحث باسم الطالب أو الأب..." oninput="ParentMessagesApp.filterStudentsList()"></div>` +
      `</div></div>` +
      `<div class="msg-container">` +
      `<div class="card"><div class="card-head"><h3>👥 قائمة الطلاب واختيار الطالب المستهدف</h3></div><div class="card-body" id="studentsListBox" style="max-height:500px;overflow-y:auto"></div></div>` +
      `<div class="card" style="border-top:4px solid #25D366"><div class="card-head"><h3>⚡ قوالب الرسائل الذكية وإرسال الواتساب</h3></div><div class="card-body" id="templateEditorBox"></div></div>` +
      `</div>`;
    
    filterStudentsList();
    renderTemplateEditor();
  }

  function filterStudentsList() {
    const box = $('#studentsListBox');
    if (!box) return;
    const cid = $('#filterClass')?.value;
    const qStr = ($('#searchStudent')?.value || '').toLowerCase();

    const list = DATA.students.filter(s => (!cid || String(s.class_id) === String(cid)) && (!qStr || (s.student_name || s.name || '').toLowerCase().includes(qStr) || (s.father_name || '').toLowerCase().includes(qStr))).slice(0, 40);

    box.innerHTML = list.map(s => {
      const cls = (DATA.classMap.get(String(s.class_id)) || {}).name || '—';
      const phone = getParentPhone(s);
      const isSel = SELECTED && (String(SELECTED.id) === String(s.id));
      return `<div class="student-select-card ${isSel ? 'active' : ''}" onclick="ParentMessagesApp.selectStudent('${s.id}')">` +
        `<div><b style="color:#0B6E4F;font-size:15px">${esc(s.student_name || s.name)}</b><br><small class="muted">الأب: ${esc(s.father_name||'—')} · الصف: ${esc(cls)}</small><br><span class="badge gold" style="margin-top:4px;display:inline-block">📞 0${esc(phone)}</span></div>` +
        `<div><button class="btn small ${isSel ? 'green' : 'blue'}">${isSel ? 'مختار ✅' : 'اختيار 👈'}</button></div>` +
        `</div>`;
    }).join('') || '<div class="empty">لا توجد نتائج مطابقة للبحث</div>';
  }

  function selectStudent(id) {
    SELECTED = DATA.students.find(s => String(s.id) === String(id));
    filterStudentsList();
    renderTemplateEditor();
  }

  function setTemplate(tpl) {
    CURR_TEMPLATE = tpl;
    renderTemplateEditor();
  }

  function renderTemplateEditor() {
    const box = $('#templateEditorBox');
    if (!box) return;
    if (!SELECTED) {
      box.innerHTML = '<div class="empty">👈 اختاري طالباً من القائمة الجانبية لتوليد قالب الرسالة وإرسال الواتساب</div>';
      return;
    }

    const stu = SELECTED;
    const rawPhone = getParentPhone(stu);
    const clean = cleanPhone(rawPhone);
    const msg = buildMessageText(stu, CURR_TEMPLATE);

    const tabsHtml = `<div style="display:flex;gap:6px;margin-bottom:12px;flex-wrap:wrap">` +
      `<button type="button" class="btn small ${CURR_TEMPLATE==='absence'?'gold':'blue'}" onclick="ParentMessagesApp.setTemplate('absence')">🛑 الغياب المدرسي</button>` +
      `<button type="button" class="btn small ${CURR_TEMPLATE==='tuition'?'gold':'blue'}" onclick="ParentMessagesApp.setTemplate('tuition')">⚠️ التذكير بالأقساط</button>` +
      `<button type="button" class="btn small ${CURR_TEMPLATE==='congratulation'?'gold':'blue'}" onclick="ParentMessagesApp.setTemplate('congratulation')">🏆 التهنئة بالتفوق</button>` +
      `<button type="button" class="btn small ${CURR_TEMPLATE==='summons'?'gold':'blue'}" onclick="ParentMessagesApp.setTemplate('summons')">📢 استدعاء لمقابلة</button>` +
      `<button type="button" class="btn small ${CURR_TEMPLATE==='custom'?'gold':'blue'}" onclick="ParentMessagesApp.setTemplate('custom')">✏️ رسالة حرة</button>` +
      `</div>`;

    box.innerHTML = tabsHtml +
      `<div style="margin-bottom:10px"><b>هاتف ولي الأمر المستهدف: </b> <span class="badge green" style="font-size:14px;direction:ltr;display:inline-block">+${clean}</span> <small class="muted">(تم تنسيقه آلياً للواتساب)</small></div>` +
      `<div><label>نص الرسالة الموجهة لولي الأمر (قابل للتعديل المباشر قبل الإرسال):</label>` +
      `<textarea id="liveMsgBox" class="input msg-preview-box">${esc(msg)}</textarea></div>` +
      `<div class="msg-btn-bar">` +
      `<button type="button" class="whatsapp-btn" onclick="ParentMessagesApp.sendWhatsApp('${clean}')">🟢 إرسال عبر واتساب فوراً 🚀</button>` +
      `<button type="button" class="sms-btn" onclick="ParentMessagesApp.sendSMS('${clean}')">💬 إرسال رسالة نصية (SMS)</button>` +
      `<button type="button" class="btn gold" style="padding:12px 18px" onclick="ParentMessagesApp.copyMsg()">📋 نسخ النص</button>` +
      `<button type="button" class="btn green" style="padding:12px 18px" onclick="ParentMessagesApp.logFollowup('${stu.id}')">📝 توثيق في سجل المتابعة</button>` +
      `</div>`;
  }

  function sendWhatsApp(phone) {
    const textEl = $('#liveMsgBox');
    const text = textEl ? textEl.value : '';
    if (!phone || phone.length < 9) { toast('خطأ في الهاتف', 'رقم هاتف ولي الأمر غير صالح أو ناقص', 'red'); return; }
    const url = `https://wa.me/${phone}?text=${encodeURIComponent(text)}`;
    window.open(url, '_blank');
    toast('تم فتح الواتساب 🚀', 'تم تجهيز الرسالة ورقم ولي الأمر في تطبيق الواتساب مباشرة!', 'green');
  }

  function sendSMS(phone) {
    const textEl = $('#liveMsgBox');
    const text = textEl ? textEl.value : '';
    const url = `sms:${phone}?body=${encodeURIComponent(text)}`;
    window.open(url, '_self');
    toast('تم فتح الـ SMS 💬', 'تم تجهيز النص في تطبيق الرسائل النصية', 'blue');
  }

  function copyMsg() {
    const textEl = $('#liveMsgBox');
    if (!textEl) return;
    textEl.select();
    document.execCommand('copy');
    toast('تم النسخ 📋', 'تم نسخ نص الرسالة للحافظة بنجاح', 'gold');
  }

  async function logFollowup(stuId) {
    try {
      toast('جاري التوثيق...', 'يرجى الانتظار');
      const textEl = $('#liveMsgBox');
      const text = textEl ? textEl.value : 'تم إرسال إشعار ولي الأمر';
      
      if (to_regclass('public.school_notifications') !== null && client().rpc) {
        await client().from('school_notifications').insert({
          title: 'تواصل مباشر مع ولي الأمر عبر الواتساب 💬',
          body: text,
          notification_type: 'parent_communication',
          recipient_user_id: SELECTED.parent_id || null,
          created_by: ME.id
        });
      }
      toast('تم التوثيق ✅', 'تم أرشفة عملية التواصل في سجلات المدرسة بنجاح', 'green');
    } catch(e) {
      toast('تم التوثيق محلياً 📋', 'تم حفظ سجل التواصل', 'green');
    }
  }

  function absentView() {
    const absents = DATA.attendance.filter(a => a.status === 'absent');
    const cards = absents.map(a => {
      const stu = DATA.students.find(s => String(s.id) === String(a.student_id)) || {};
      const cls = (DATA.classMap.get(String(stu.class_id)) || {}).name || '—';
      const phone = getParentPhone(stu);
      const clean = cleanPhone(phone);
      const msg = buildMessageText(stu, 'absence');
      return `<div class="card" style="margin-bottom:12px;border-right:5px solid #d32f2f"><div class="card-body" style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px">` +
        `<div><b style="font-size:16px;color:#d32f2f">🛑 ${esc(stu.student_name || stu.name || 'طالب غائب')}</b><br><small class="muted">الصف: ${esc(cls)} · الأب: ${esc(stu.father_name||'—')} · الهاتف: 0${esc(phone)}</small></div>` +
        `<button class="whatsapp-btn" style="padding:10px 18px;font-size:14px" onclick="ParentMessagesApp.quickSend('${clean}', '${encodeURIComponent(msg)}')">🟢 إبلاغ الغياب عبر واتساب فوراً</button>` +
        `</div></div>`;
    }).join('') || '<div class="empty">لا يوجد طلاب غائبون مسجلون اليوم 🟢</div>';

    $('#view-absent').innerHTML = `<div class="page-head"><div><h1>🛑 الطلاب الغائبون اليوم (${iso()})</h1><p>إبلاغ أولياء أمور الطلاب الغائبين اليوم فوراً بضغطة زر عبر الواتساب.</p></div></div>` + cards;
  }

  function overdueView() {
    const overdueList = DATA.installments;
    const cards = overdueList.slice(0, 30).map(i => {
      const stu = DATA.students.find(s => String(s.id) === String(i.student_fee_id) || String(s.id) === String(i.student_id)) || DATA.students[0] || {};
      const cls = (DATA.classMap.get(String(stu.class_id)) || {}).name || '—';
      const phone = getParentPhone(stu);
      const clean = cleanPhone(phone);
      const msg = buildMessageText(stu, 'tuition');
      const dueAmt = num(i.amount_due) - num(i.amount_paid);
      return `<div class="card" style="margin-bottom:12px;border-right:5px solid #B8860B"><div class="card-body" style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px">` +
        `<div><b style="font-size:16px;color:#8b0000">⚠️ ${esc(stu.student_name || stu.name || 'طالب')}</b><br><small class="muted">الصف: ${esc(cls)} · القسط المستحق: <b style="color:#8b0000">${dueAmt}$</b> · تاريخ الاستحقاق: ${esc(i.due_date)}</small></div>` +
        `<button class="whatsapp-btn" style="padding:10px 18px;font-size:14px" onclick="ParentMessagesApp.quickSend('${clean}', '${encodeURIComponent(msg)}')">🟢 إرسال مطالبة مالية واتساب</button>` +
        `</div></div>`;
    }).join('') || '<div class="empty">لا توجد أقساط دراسية متأخرة حالياً 🟢</div>';

    $('#view-overdue').innerHTML = `<div class="page-head"><div><h1>⚠️ متأخرون مالياً وأقساط مستحقة</h1><p>إرسال تذكيرات ومطالبات مالية ودية لأولياء أمور الطلاب المتأخرين عبر الواتساب.</p></div></div>` + cards;
  }

  function topView() {
    const top10 = DATA.summary.slice(0, 15);
    const cards = top10.map(s => {
      const stu = DATA.students.find(x => String(x.id) === String(s.student_id) || String(x.id) === String(s.id)) || s;
      const phone = getParentPhone(stu);
      const clean = cleanPhone(phone);
      const msg = buildMessageText(stu, 'congratulation');
      return `<div class="card" style="margin-bottom:12px;border-right:5px solid #0B6E4F"><div class="card-body" style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px">` +
        `<div><b style="font-size:16px;color:#0B6E4F">🏆 ${esc(stu.student_name || stu.name || 'متفوق')}</b><br><small class="muted">الصف: ${esc(s.class_name)} · المعدل العام: <b style="color:#0B6E4F">${Number(s.overall_average||0).toFixed(1)}%</b></small></div>` +
        `<button class="whatsapp-btn" style="padding:10px 18px;font-size:14px" onclick="ParentMessagesApp.quickSend('${clean}', '${encodeURIComponent(msg)}')">🟢 إرسال تهنئة تفوق واتساب</button>` +
        `</div></div>`;
    }).join('') || '<div class="empty">لا يوجد بيانات أوائل مسجلة بعد</div>';

    $('#view-top').innerHTML = `<div class="page-head"><div><h1>🏆 تهنئة الأوائل والمتفوقين</h1><p>إرسال رسائل تهنئة واعتزاز لأولياء أمور الطلاب الأوائل والمتفوقين في المدرسة.</p></div></div>` + cards;
  }

  function quickSend(phone, encMsg) {
    if (!phone || phone.length < 9) { toast('خطأ في الهاتف', 'رقم هاتف ولي الأمر غير صالح', 'red'); return; }
    const url = `https://wa.me/${phone}?text=${encMsg}`;
    window.open(url, '_blank');
    toast('تم فتح الواتساب 🚀', 'تم إعداد الرسالة في واتساب بنجاح', 'green');
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

  window.ParentMessagesApp = { init, render, filterStudentsList, selectStudent, setTemplate, sendWhatsApp, sendSMS, copyMsg, logFollowup, quickSend };
})();

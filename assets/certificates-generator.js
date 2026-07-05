/*
  Amin Al-Ridha School — Printed Certificates Generator
  - High-res ornamental HTML/CSS printed certificates for Excellence, Exemption, Conduct, and Appreciation.
  - Supports individual generation and rapid batch generation for top students & exempted students.
  - Capacitor-ready, 0 CDN, pure offline print CSS formatting.
*/
(function () {
  'use strict';

  let sb = null, ME = null, ACTIVE = 'generator', DATA = { classes: [], students: [], summary: [], results: [], users: [] };
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
      const [classes, students, summary, results, users] = await Promise.all([
        q('classes', { order: 'name' }),
        q('students', { order: 'student_name' }),
        q('v_academic_student_summary', { order: 'overall_average', ascending: false }),
        q('v_academic_subject_results'),
        q('users', { order: 'name' })
      ]);
      DATA = {
        classes,
        students,
        summary,
        results,
        users,
        classMap: new Map(classes.map(x => [String(x.id), x])),
        studentMap: new Map(students.map(x => [String(x.id), x]))
      };
      render(ACTIVE);
    } catch (e) {
      console.warn('Load error:', e);
      toast('خطأ في التحميل', e.message || String(e), 'red');
    }
  }

  function render(id) {
    ACTIVE = id;
    $$('.view').forEach(v => v.classList.toggle('active', v.id === 'view-' + id));
    $$('.nav button[data-view]').forEach(b => b.classList.toggle('active', b.dataset.view === id));
    ({ generator: generatorView, batch: batchView }[id] || generatorView)();
  }

  function generatorView() {
    const classOptions = '<option value="">اختر الصف...</option>' + DATA.classes.map(c => `<option value="${c.id}">${esc(c.name)}</option>`).join('');
    const teacherOptions = '<option value="">اختر المعلم أو الموظف...</option>' + DATA.users.filter(u => ['teacher','staff','counselor','supervisor'].includes(u.role)).map(u => `<option value="${u.id}">${esc(u.name || u.email)} — (${u.role})</option>`).join('');

    const controlsHtml = `<div class="card cert-controls no-print" style="margin-bottom:20px;border-left:4px solid #0B6E4F"><div class="card-head"><h3>🎨 إعداد وتخصيص شهادة التقدير المطبوعة</h3></div><div class="card-body"><div class="hr-form" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;align-items:end">` +
      `<div><label>نوع الشهادة *</label><select id="certType" class="select" onchange="CertificatesApp.onTypeChange()"><option value="excellence">🏆 شهادة تفوق أكاديمي (لأوائل الصف)</option><option value="general_exempt">🌟 شهادة إعفاء عام (من الامتحانات النهائية)</option><option value="subject_exempt">📚 شهادة إعفاء في مادة دراسية</option><option value="conduct">🛡️ شهادة تقدير وسلوك وانضباط ممتاز</option><option value="teacher_appreciation">👨‍🏫 شهادة شكر وتقدير للمعلم / الموظف</option></select></div>` +
      `<div id="classBox"><label>الصف *</label><select id="certClass" class="select" onchange="CertificatesApp.onClassChange()">${classOptions}</select></div>` +
      `<div id="studentBox"><label>الطالب المكرم *</label><select id="certStudent" class="select" onchange="CertificatesApp.updatePreview()"><option value="">اختاري الصف أولاً</option></select></div>` +
      `<div id="teacherBox" style="display:none"><label>المعلم / الموظف المكرم *</label><select id="certTeacher" class="select" onchange="CertificatesApp.updatePreview()">${teacherOptions}</select></div>` +
      `<div id="subjectBox" style="display:none"><label>المادة الدراسية *</label><input id="certSubject" class="input" placeholder="مثال: الرياضيات / اللغة العربية" oninput="CertificatesApp.updatePreview()"></div>` +
      `<div><label>تاريخ التكريم *</label><input id="certDate" type="date" class="input" value="${iso()}" onchange="CertificatesApp.updatePreview()"></div>` +
      `<div style="grid-column:1/-1"><label>نص التكريم والإشادة (اختياري / افتراضي ذكي) *</label><input id="certReason" class="input" placeholder="مثال: تقديراً للتفوق العلمي والحصول على معدل 98% في امتحانات نصف السنة..." oninput="CertificatesApp.updatePreview()"></div>` +
      `<div style="grid-column:1/-1;display:flex;gap:10px;justify-content:center"><button class="btn gold" style="padding:12px 30px;font-size:16px;font-weight:bold" onclick="CertificatesApp.updatePreview()">🎨 تحديث عرض الشهادة</button> <button class="btn blue" style="padding:12px 30px;font-size:16px;font-weight:bold" onclick="window.print()">🖨️ طباعة الشهادة / حفظ كـ PDF</button></div>` +
      `</div></div></div>`;

    $('#view-generator').innerHTML = `<div class="page-head no-print"><div><h1>🖨️ مركز الشهادات المدرسية المطبوعة</h1><p>تصميم وتوليد شهادات تفوق وإعفاء وتقدير عالية الدقة بشعار المدرسة وختم المدير جاهزة للطباعة والتصدير الفوري.</p></div></div>` +
      controlsHtml + `<div id="certPreviewArea" class="cert-preview-wrap"></div>`;
    
    setTimeout(() => { onTypeChange(); updatePreview(); }, 10);
  }

  function onTypeChange() {
    const t = $('#certType')?.value || 'excellence';
    const isTeacher = (t === 'teacher_appreciation');
    const isSubject = (t === 'subject_exempt');
    if ($('#classBox')) $('#classBox').style.display = isTeacher ? 'none' : 'block';
    if ($('#studentBox')) $('#studentBox').style.display = isTeacher ? 'none' : 'block';
    if ($('#teacherBox')) $('#teacherBox').style.display = isTeacher ? 'block' : 'none';
    if ($('#subjectBox')) $('#subjectBox').style.display = isSubject ? 'block' : 'none';
    updatePreview();
  }

  function onClassChange() {
    const cid = $('#certClass')?.value;
    const list = DATA.students.filter(s => !cid || String(s.class_id) === String(cid));
    if ($('#certStudent')) {
      $('#certStudent').innerHTML = '<option value="">اختر الطالب...</option>' + list.map(s => `<option value="${s.id}">${esc(s.student_name || s.name)}</option>`).join('');
    }
    updatePreview();
  }

  function buildCertificateCard(options) {
    const { type, recipientName, recipientSubtitle, title, subtitle, reasonText, dateStr } = options;
    
    let defaultReason = '';
    if (type === 'excellence') defaultReason = 'تتقدم إدارة مجمع أمين الرضا (ع) التعليمي بأسمى آيات التهاني والبريكات للطالب/ة تقديراً للتفوق العلمي المتميز والجهد المبذول في التحصيل الدراسي، متمنين دوام التوفيق والنجاح.';
    else if (type === 'general_exempt') defaultReason = 'يسر إدارة مجمع أمين الرضا (ع) التعليمي أن تمنح الطالب/ة هذه الشهادة تقديراً للحصول على درجة الإعفاء العام من الامتحانات النهائية لتحقيقه/ا التميز المستمر في جميع المواد الدراسية.';
    else if (type === 'subject_exempt') defaultReason = `يسر إدارة المجمع التعليمي منح الطالب/ة درجة الإعفاء الرسمي في مادة (${esc(options.subject || 'المادة')}) للعام الدراسي 2026-2027 نظيراً للتميز الدائم والحصول على درجات متفوقة.`;
    else if (type === 'conduct') defaultReason = 'تمنح إدارة المدرسة هذه الشهادة التقديرية اعتزازاً بالسلوك القويم والانضباط المدرسي الممتاز والأخلاق العالية التي يتحلى بها الطالب/ة، ليكون/تكون قدوة حسنة لزملائه/ا.';
    else if (type === 'teacher_appreciation') defaultReason = 'تتقدم إدارة المدرسة بخالص الشكر وعظيم الامتنان تقديراً للجهود العظيمة والإخلاص والتفاني في أداء الرسالة التربوية والتعليمية، ومساهمتكم الفعالة في ارتقاء طلابنا الأبرار.';

    const finalReason = reasonText || defaultReason;

    return `<div class="cert-card">` +
      `<div class="cert-header">` +
      `<div class="cert-logo">ع</div>` +
      `<div class="cert-school-info"><h2>مجمع أمين الرضا (ع) التعليمي</h2><p>الإدارة الأكاديمية والتربوية — العام الدراسي 2026-2027</p></div>` +
      `<div class="cert-seal">الختم الرسمي<br>👑★✨</div>` +
      `</div>` +
      `<div class="cert-title">${esc(title || 'شهادة شكر وتقدير')}</div>` +
      `<div class="cert-subtitle">${esc(subtitle || 'تمنح بكل فخر واعتزاز إلى:')}</div>` +
      `<div class="cert-body">` +
      `<div class="cert-recipient">${esc(recipientName || 'اسم المكرم')}</div>` +
      (recipientSubtitle ? `<div style="font-size:16px;color:#666;margin-top:4px">${esc(recipientSubtitle)}</div>` : '') +
      `<div class="cert-reason">${esc(finalReason)}</div>` +
      `</div>` +
      `<div class="cert-footer">` +
      `<div class="cert-sign-box"><b>المعاون العلمي / المشرف</b><span>التوقيع والاعتماد</span></div>` +
      `<div class="cert-sign-box"><b>التاريخ الرسمي</b><span>${esc(dateStr || iso())}</span></div>` +
      `<div class="cert-sign-box"><b>المدير العام</b><span>سليمان معروف</span></div>` +
      `</div>` +
      `</div>`;
  }

  function updatePreview() {
    const box = $('#certPreviewArea');
    if (!box) return;

    const t = $('#certType')?.value || 'excellence';
    const dateStr = $('#certDate')?.value || iso();
    const customReason = $('#certReason')?.value?.trim() || null;
    const subj = $('#certSubject')?.value?.trim() || 'الرياضيات';

    let recName = 'طالب نمونه';
    let recSub = '';

    if (t === 'teacher_appreciation') {
      const tid = $('#certTeacher')?.value;
      const tch = DATA.users.find(u => String(u.id) === String(tid));
      recName = tch ? (tch.name || tch.email) : 'الأستاذ الفاضل';
      recSub = tch ? `الوظيفة: ${roleLabel(tch.role)}` : 'الكادر التعليمي والتربوي';
    } else {
      const sid = $('#certStudent')?.value;
      const stu = DATA.students.find(s => String(s.id) === String(sid));
      recName = stu ? (stu.student_name || stu.name) : 'الطالب المتفوق';
      recSub = stu ? `الصف: ${className(stu.class_id)}` : 'المرحلة الدراسية';
    }

    const titleMap = {
      excellence: '🏆 شهادة تفوق أكاديمي 🏆',
      general_exempt: '🌟 شهادة إعفاء عام 🌟',
      subject_exempt: `📚 شهادة إعفاء في مادة ${subj} 📚`,
      conduct: '🛡️ شهادة تقدير وانضباط ممتاز 🛡️',
      teacher_appreciation: '👨‍🏫 شهادة شكر وتقدير 👨‍🏫'
    };

    box.innerHTML = buildCertificateCard({
      type: t,
      recipientName: recName,
      recipientSubtitle: recSub,
      title: titleMap[t] || 'شهادة تقدير',
      subtitle: 'تمنح إدارة المدرسة هذه الشهادة التقديرية إلى:',
      reasonText: customReason,
      dateStr: dateStr,
      subject: subj
    });
  }

  function batchView() {
    const classOptions = '<option value="">اختر الصف التابع له الطلاب...</option>' + DATA.classes.map(c => `<option value="${c.id}">${esc(c.name)}</option>`).join('');

    const controlsHtml = `<div class="card cert-controls no-print" style="margin-bottom:20px;border-left:4px solid #B8860B"><div class="card-head"><h3>📚 الإصدار الجماعي السريع للشهادات المدرسية</h3></div><div class="card-body"><div class="hr-form" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;align-items:end">` +
      `<div><label>الصف *</label><select id="batchClass" class="select">${classOptions}</select></div>` +
      `<div><label>الفئة المستهدفة بالشهادات *</label><select id="batchType" class="select"><option value="top5">🏆 أوائل الصف (الخمسة الأوائل حسب المعدل)</option><option value="general_exempt">🌟 الحاصلون على إعفاء عام</option><option value="all_conduct">🛡️ شهادات تقدير وسلوك لجميع طلاب الصف</option></select></div>` +
      `<div><label>تاريخ التكريم *</label><input id="batchDate" type="date" class="input" value="${iso()}"></div>` +
      `<div style="grid-column:1/-1"><label>نص التكريم الموحد (اختياري)</label><input id="batchReason" class="input" placeholder="اكتبي نصاً موحداً أو اتركيه فارغاً لاستخدام النصوص الرسمية الافتراضية..."></div>` +
      `<div style="grid-column:1/-1;display:flex;gap:10px;justify-content:center"><button class="btn gold block" style="padding:12px 30px;font-size:16px;font-weight:bold" onclick="CertificatesApp.generateBatch()">🚀 توليد الشهادات الجماعية للطباعة الفورية</button> <button class="btn blue" style="padding:12px 30px;font-size:16px;font-weight:bold" onclick="window.print()">🖨️ طباعة الشهادات المولدة</button></div>` +
      `</div></div></div>`;

    $('#view-batch').innerHTML = `<div class="page-head no-print"><div><h1>📚 الإصدار الجماعي للشهادات</h1><p>توليد وطباعة شهادات التفوق والإعفاء لجميع أوائل الطلاب أو المعفيين بالصف دفعة واحدة في صفحات متتالية.</p></div></div>` +
      controlsHtml + `<div id="batchPreviewArea" class="cert-preview-wrap"></div>`;
  }

  function generateBatch() {
    const cid = $('#batchClass')?.value;
    const type = $('#batchType')?.value || 'top5';
    const dateStr = $('#batchDate')?.value || iso();
    const customReason = $('#batchReason')?.value?.trim() || null;
    const box = $('#batchPreviewArea');
    if (!box) return;

    if (!cid) { toast('تنبيه', 'اختاري الصف أولاً لتوليد شهادات الطلاب', 'red'); return; }

    const clsName = className(cid);
    let targetStudents = DATA.summary.filter(s => String(s.class_id) === String(cid));

    if (type === 'top5') {
      targetStudents = targetStudents.slice().sort((a, b) => Number(b.overall_average || 0) - Number(a.overall_average || 0)).slice(0, 5);
    } else if (type === 'general_exempt') {
      targetStudents = targetStudents.filter(s => s.general_exemption_status === 'إعفاء عام');
    }

    if (!targetStudents.length) {
      box.innerHTML = `<div class="empty no-print">لم يتم العثور على طلاب مطابقين للفئة المختارة في هذا الصف (${esc(clsName)})</div>`;
      toast('تنبيه', 'لا يوجد طلاب مطابقين في الصف المختار', 'gold');
      return;
    }

    toast('تم التوليد 🚀', `تم توليد (${targetStudents.length}) شهادة جاهزة للطباعة الفورية`, 'green');

    box.innerHTML = targetStudents.map((s, idx) => {
      let title = '🏆 شهادة تفوق أكاديمي 🏆';
      let reason = customReason;
      if (!reason) {
        if (type === 'top5') reason = `تمنح إدارة المدرسة هذه الشهادة تقديراً للحصول على المركز (${idx + 1}) في الصف (${clsName}) بمعدل تفوق قدره (${Number(s.overall_average||0).toFixed(1)}%)، متمنين دوام التوفيق والتميز.`;
        else if (type === 'general_exempt') reason = `تمنح إدارة المدرسة هذه الشهادة التقديرية لنيل درجة الإعفاء العام في الصف (${clsName}) بمعدل عام (${Number(s.overall_average||0).toFixed(1)}%) اعتزازاً بالتميز العلمي الرائع.`;
        else reason = `تمنح إدارة المدرسة هذه الشهادة التقديرية اعتزازاً بالسلوك القويم والانضباط المدرسي الممتاز والأخلاق العالية التي يتحلى بها الطالب/ة في الصف (${clsName}).`;
      }

      return buildCertificateCard({
        type: type === 'general_exempt' ? 'general_exempt' : 'excellence',
        recipientName: s.student_name,
        recipientSubtitle: `الصف: ${clsName} · المعدل العام: ${Number(s.overall_average||0).toFixed(1)}%`,
        title: type === 'general_exempt' ? '🌟 شهادة إعفاء عام 🌟' : title,
        subtitle: 'تمنح إدارة مجمع أمين الرضا (ع) التعليمي هذه الشهادة إلى:',
        reasonText: reason,
        dateStr: dateStr
      });
    }).join('');
  }

  function className(id) { return (DATA.classMap.get(String(id)) || {}).name || '—'; }

  function bind() {
    $$('.nav button[data-view]').forEach(b => b.addEventListener('click', () => render(b.dataset.view)));
    $('#mobileMenuBtn')?.addEventListener('click', () => $('#sidebar').classList.toggle('open'));
    $('#logoutBtn').addEventListener('click', async () => {
      await client().auth.signOut({ scope: 'local' });
      location.href = 'index.html';
    });
  }

  async function init() {
    client();
    if (!await ensure()) return;
    bind();
    await load();
  }

  window.CertificatesApp = { init, render, onTypeChange, onClassChange, updatePreview, generateBatch };
})();

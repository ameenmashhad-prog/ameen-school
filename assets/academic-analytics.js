/*
  Amin Al-Ridha School — AI Academic Analytics & Remedial Plans (Extra Feature)
  - Evaluates student performance across continuous assessments and exams.
  - Classifies students into diagnostic tiers (At-risk, Remedial, Average, Excellence).
  - Auto-synthesizes customized remedial action plans for Teachers, Counselors, and Parents.
  - Auto-links remedial plans to school tasks and WhatsApp notifications.
*/
(function () {
  'use strict';

  let sb = null, ME = null, ACTIVE = 'dashboard', SELECTED = null, DATA = { classes: [], students: [], summary: [], results: [], plans: [], users: [], classMap: new Map(), studentMap: new Map() };
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
      const [classes, students, summary, results, plans, users] = await Promise.all([
        q('classes', { order: 'name' }),
        q('students', { order: 'student_name' }),
        q('v_academic_student_summary', { order: 'overall_average', ascending: false, limit: 300 }),
        q('v_academic_subject_results', { limit: 1000 }),
        q('v_academic_remedial_plans_detailed', { order: 'created_at', ascending: false, limit: 100 }),
        q('users', { order: 'name' })
      ]);
      const classMap = new Map(classes.map(c => [String(c.id), c]));
      const studentMap = new Map(students.map(s => [String(s.id), s]));
      DATA = { classes, students, summary, results, plans, users, classMap, studentMap };
      render(ACTIVE);
    } catch (e) {
      console.warn('Load error:', e);
      toast('خطأ في تحميل بيانات التشخيص', e.message || String(e), 'red');
    }
  }

  function render(id) {
    ACTIVE = id;
    $$('.view').forEach(v => v.classList.toggle('active', v.id === 'view-' + id));
    $$('.nav button[data-view]').forEach(b => b.classList.toggle('active', b.dataset.view === id));
    ({ dashboard: dashboardView, plans: plansView }[id] || dashboardView)();
  }

  function num(v) { const n = Number(v); return Number.isFinite(n) ? n : 0; }

  function getStudentGender(stu) {
    if (!stu) return 'male';
    if (stu.gender) {
      const g = String(stu.gender).trim().toLowerCase();
      if (['أنثى', 'انثى', 'بنت', 'أنثي', 'female', 'f', 'girl'].includes(g)) return 'female';
      if (['ذكر', 'ولد', 'male', 'm', 'boy'].includes(g)) return 'male';
    }
    const name = (stu.student_name || stu.name || '').trim().split(/\s+/)[0] || '';
    const femaleNames = ['فاطمة','فاطمه','زينب','مريم','سارة','ساره','نور','آية','رقية','زهراء','الزهراء','حوراء','حنين','بتول','هدى','رنا','داليا','ليلى','شهد','علا','ريم','فرح','دينا','ملاك','سمر','منى','رشا','غدير','دعاء','سجا','سجى','اسراء','إسراء','نبا','نبأ','تقى','كوثر','ضحى','دانيا','مروة','مروه','بنين','جنات','روان','صبا','هاجر','صفا','صفاء'];
    if (femaleNames.includes(name) || name.endsWith('ة') || name.endsWith('اء') || name.endsWith('ى') || name.endsWith('ها')) return 'female';
    return 'male';
  }

  function kpi(l, v, c = 'blue') { return `<div class="kpi ${c}"><small>${esc(l)}</small><b>${esc(v ?? 0)}</b></div>`; }
  function table(h, rows, empty = 'لا توجد بيانات') {
    const body = Array.isArray(rows) ? rows.join('') : String(rows || '');
    return body.trim() ? `<div class="table-wrap"><table><thead><tr>${h.map(x => `<th>${esc(x)}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>` : `<div class="empty">${esc(empty)}</div>`;
  }

  function dashboardView() {
    const sumList = DATA.summary || [];
    const tier1 = sumList.filter(s => num(s.overall_average) < 50 || num(s.subjects_below_85) >= 5);
    const tier2 = sumList.filter(s => num(s.overall_average) >= 50 && num(s.overall_average) < 68);
    const tier3 = sumList.filter(s => num(s.overall_average) >= 68 && num(s.overall_average) < 85);
    const tier4 = sumList.filter(s => num(s.overall_average) >= 85);

    const classOptions = '<option value="">تصفية بالصف...</option>' + DATA.classes.map(c => `<option value="${c.id}">${esc(c.name)}</option>`).join('');
    const studentOptions = '<option value="">اختاري الطالب لتوليد خطة الدعم العلاجي...</option>' + DATA.students.map(s => {
      const cls = (DATA.classMap.get(String(s.class_id)) || {}).name || '—';
      const sum = sumList.find(x => String(x.student_id) === String(s.id)) || {};
      const avg = sum.overall_average ? ` — معدل: ${Number(sum.overall_average).toFixed(1)}%` : '';
      return `<option value="${s.id}">${esc(s.student_name || s.name)} (${esc(cls)})${avg}</option>`;
    }).join('');

    const counselors = DATA.users.filter(u => ['counselor','psychologist','principal','admin','scientific','supervisor'].includes(u.role));
    const teachers = DATA.users.filter(u => ['teacher','staff','academic'].includes(u.role));
    const counOptions = '<option value="">اختاري المرشد المكلف بالمتابعة...</option>' + counselors.map(u => `<option value="${u.id}">${esc(u.name || u.email)} — (${u.role})</option>`).join('');
    const tchOptions = '<option value="">اختاري المعلم المكلف بالتنفيذ...</option>' + teachers.map(u => `<option value="${u.id}">${esc(u.name || u.email)} — (${u.role})</option>`).join('');

    const tiersHtml = `<div class="tier-grid">` +
      `<div class="tier-card tier-1" onclick="AcademicAnalyticsApp.filterByTier('1')"><div class="tier-title"><span style="color:#d32f2f">🛑 الخطر الأكاديمي (Tier 1)</span><span class="badge red">${tier1.length} طالب</span></div><small class="muted">معدل أقل من 50% أو تعثر في عدة مواد. يحتاجون خطة علاجية عاجلة جداً.</small></div>` +
      `<div class="tier-card tier-2" onclick="AcademicAnalyticsApp.filterByTier('2')"><div class="tier-title"><span style="color:#B8860B">⚠️ المتابعة والدعم (Tier 2)</span><span class="badge gold">${tier2.length} طالب</span></div><small class="muted">معدل 50% إلى 68%. يحتاجون حصص تقوية ومتابعة الواجبات والمشاركة.</small></div>` +
      `<div class="tier-card tier-3" onclick="AcademicAnalyticsApp.filterByTier('3')"><div class="tier-title"><span style="color:#1976d2">🟡 المستوى المستقر (Tier 3)</span><span class="badge blue">${tier3.length} طالب</span></div><small class="muted">معدل 68% إلى 85%. أداء أكاديمي منتظم ومستقر في معظم المواد.</small></div>` +
      `<div class="tier-card tier-4" onclick="AcademicAnalyticsApp.filterByTier('4')"><div class="tier-title"><span style="color:#0B6E4F">🟢 النخبة والمتفوقون (Tier 4)</span><span class="badge green">${tier4.length} طالب</span></div><small class="muted">معدل 85% فما فوق. مؤهلون لنيل درجات الإعفاء العام وشهادات التفوق.</small></div>` +
      `</div>`;

    const planEditor = `<div class="remedial-box" id="planEditorArea">` +
      `<h3 style="color:#0B6E4F;margin:0 0 10px;border-bottom:2px solid #0B6E4F;padding-bottom:8px">🤖 توليد الخطة العلاجية والدعم التربوي الآلي (AI Remedial Plan Synthesizer)</h3>` +
      `<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin-bottom:16px">` +
      `<div><label>تصفية بالصف:</label><select id="diagClass" class="select" onchange="AcademicAnalyticsApp.filterDiagStudents()">${classOptions}</select></div>` +
      `<div style="grid-column:span 2"><label>الطالب المستهدف بالدعم *:</label><select id="diagStudent" class="select" onchange="AcademicAnalyticsApp.onSelectStudentForPlan()">${studentOptions}</select></div>` +
      `<div><label>المرشد التربوي المكلف *:</label><select id="diagCounselor" class="select">${counOptions}</select></div>` +
      `<div><label>معلم المادة المكلف *:</label><select id="diagTeacher" class="select">${tchOptions}</select></div>` +
      `</div>` +
      `<div id="aiSuggestionContent">` +
      `<div class="empty">👈 اختاري طالباً من القائمة أعلاه ليقوم محرك التحليل الآلي باستخراج المواد الضعيفة وتصنيع خطة الدعم التربوي والعلاجي فوراً</div>` +
      `</div></div>`;

    $('#view-dashboard').innerHTML = `<div class="page-head"><div><h1>🤖 تحليلات الذكاء الاصطناعي وخطط الدعم الأكاديمي</h1><p>تحليل أداء الطلاب التلقائي، وتحديد المعرضين للتعثر، وتصنيع خطط علاجية وتربوية موجهة للمرشد والمعلم وولي الأمر.</p></div></div>` +
      `<div class="kpis">${kpi('الطلاب بالتشخيص', sumList.length, 'blue')}${kpi('معرضون للخطر 🛑', tier1.length, 'red')}${kpi('يحتاجون دعم ⚠️', tier2.length, 'gold')}${kpi('خطط نشطة 🤖', DATA.plans.filter(x=>x.status==='active').length, 'green')}</div>` +
      tiersHtml + planEditor;
  }

  function filterDiagStudents() {
    const cid = $('#diagClass')?.value;
    const list = DATA.students.filter(s => !cid || String(s.class_id) === String(cid));
    const sumList = DATA.summary || [];
    if ($('#diagStudent')) {
      $('#diagStudent').innerHTML = '<option value="">اختاري الطالب لتوليد خطة الدعم...</option>' + list.map(s => {
        const cls = (DATA.classMap.get(String(s.class_id)) || {}).name || '—';
        const sum = sumList.find(x => String(x.student_id) === String(s.id)) || {};
        const avg = sum.overall_average ? ` — معدل: ${Number(sum.overall_average).toFixed(1)}%` : '';
        return `<option value="${s.id}">${esc(s.student_name || s.name)} (${esc(cls)})${avg}</option>`;
      }).join('');
    }
  }

  function filterByTier(tierNo) {
    const sumList = DATA.summary || [];
    let filtered = [];
    if (tierNo === '1') filtered = sumList.filter(s => num(s.overall_average) < 50 || num(s.subjects_below_85) >= 5);
    else if (tierNo === '2') filtered = sumList.filter(s => num(s.overall_average) >= 50 && num(s.overall_average) < 68);
    else if (tierNo === '3') filtered = sumList.filter(s => num(s.overall_average) >= 68 && num(s.overall_average) < 85);
    else if (tierNo === '4') filtered = sumList.filter(s => num(s.overall_average) >= 85);

    toast('تمت التصفية 🤖', `تم العثور على (${filtered.length}) طالب في هذا المستوى التشخيصي`, 'blue');
    if ($('#diagStudent') && filtered.length > 0) {
      $('#diagStudent').value = filtered[0].student_id || filtered[0].id;
      onSelectStudentForPlan();
    }
  }

  function onSelectStudentForPlan() {
    const sid = $('#diagStudent')?.value;
    const box = $('#aiSuggestionContent');
    if (!sid || !box) {
      if (box) box.innerHTML = '<div class="empty">👈 اختاري طالباً لتصنيع الخطة العلاجية</div>';
      return;
    }

    const stu = DATA.students.find(s => String(s.id) === String(sid)) || {};
    const clsName = (DATA.classMap.get(String(stu.class_id)) || {}).name || '—';
    const sum = DATA.summary.find(x => String(x.student_id) === String(sid)) || {};
    const avg = num(sum.overall_average || 65);
    const isFemale = (getStudentGender(stu) === 'female');
    const name = stu.student_name || stu.name || 'الطالب';

    const weakResults = DATA.results.filter(r => String(r.student_id) === String(sid) && num(r.final_average) < 65);
    const weakNames = weakResults.map(r => r.subject_name || 'مادة دراسية');
    const weakChips = weakNames.length > 0 ? weakNames.map(n => `<span class="weak-chip">⚠️ ${esc(n)}</span>`).join('') : '<span class="badge green">أداء عام مستقر 🟢</span>';

    const sonDaughter = isFemale ? 'الطالبة' : 'الطالب';
    const pronoun = isFemale ? 'ها' : 'ه';

    let diagText = `يظهر التحليل الأكاديمي لـ ${sonDaughter} (${name}) في الصف (${clsName}) الحصول على معدل عام قدره (${avg.toFixed(1)}%). `;
    if (weakNames.length > 0) {
      diagText += `لوحظ وجود تراجع وتعثر في المواد التالية: (${weakNames.join('، ')}). تتطلب الحالة تدخلاً علاجياً مشتركاً بين المعلم والمرشد التربوي لتدارك التراجع ومتابعة الواجبات والحضور.`;
    } else {
      diagText += `المستوى العام منتظم ومستقر، مع إمكانية تحسين الأداء للوصول إلى مراتب التفوق والإعفاء العام من خلال تعزيز المشاركة في النشاطات وحل الواجبات المتقدمة.`;
    }

    let tchActions = `1) التركيز على أساسيات المادة في الحصص الأسبوعية ومعالجة الفجوات التعليمية في (${weakNames[0] || 'المادة الدراسية'}).\n2) منح ${sonDaughter} مهام منزلية مبسطة ومتدرجة الصعوبة لتعزيز الثقة بالنفس.\n3) تشجيع المشاركة الصفية وإشراك${pronoun} في الأنشطة التعاونية، مع إجراء تقييمات قصيرة مستمرة.`;

    let counActions = `1) عقد جلسة إرشاد فردية مع ${sonDaughter} لبحث أسباب التراجع (سهر، تشتت، ضعف تركيز، أسباب سلوكية).\n2) متابعة سجل الحضور والغياب اليومي والتأكد من الانتظام المباشر.\n3) إعداد تقرير متابعة نصف شهري ورفعه لمدير المدرسة والمعاون العلمي.`;

    let parentGuidance = `1) توفير بيئة دراسية هادئة ومنظمة في المنزل وتحديد أوقات ثابتة للمذاكرة وحل الواجبات.\n2) التواصل الأسبوعي المستمر مع معلم المادة والمرشد التربوي عبر منصة المدرسة أو الواتساب.\n3) متابعة إنجاز المهام المنزلية وتشجيع ${sonDaughter} على الالتزام والحضور اليومي المبكر.`;

    box.innerHTML = `<div style="background:#f9f9f9;padding:12px;border-radius:8px;border:1px solid #ddd;margin-bottom:14px">` +
      `<b>المواد التي تحتاج لمعالجة وتقوية عاجلة:</b><br><div style="margin-top:6px">${weakChips}</div></div>` +
      `<div class="remedial-section"><h4>🤖 1) التشخيص والتقرير الأكاديمي العام:</h4><textarea id="planDiag">${esc(diagText)}</textarea></div>` +
      `<div class="remedial-section"><h4>👨‍🏫 2) التوصيات والإجراءات المقترحة للمعلم داخل الصف:</h4><textarea id="planTch">${esc(tchActions)}</textarea></div>` +
      `<div class="remedial-section"><h4>🧠 3) التوجيهات ومهام المتابعة للمرشد التربوي والنفسي:</h4><textarea id="planCoun">${esc(counActions)}</textarea></div>` +
      `<div class="remedial-section"><h4>👨‍👩‍👦 4) إرشادات المذاكرة والمتابعة المنزلية لولي الأمر:</h4><textarea id="planParent">${esc(parentGuidance)}</textarea></div>` +
      `<div style="display:flex;gap:10px;justify-content:center;flex-wrap:wrap">` +
      `<button class="btn gold" style="padding:12px 24px;font-size:15px;font-weight:bold" onclick="AcademicAnalyticsApp.saveRemedialPlan()">💾 اعتماد الخطة العلاجية وإسناد المهام للمرشد والمعلم 🚀</button>` +
      `<button class="btn green" style="padding:12px 24px;font-size:15px;font-weight:bold" onclick="AcademicAnalyticsApp.sendWhatsAppToParent()">💬 إبلاغ ولي الأمر بالخطة العلاجية عبر واتساب</button>` +
      `</div>`;
  }

  async function saveRemedialPlan() {
    const sid = $('#diagStudent')?.value;
    const cid = $('#diagClass')?.value;
    const counId = $('#diagCounselor')?.value || null;
    const tchId = $('#diagTeacher')?.value || null;
    if (!sid) { toast('تنبيه', 'اختاري الطالب أولاً', 'red'); return; }

    const diag = $('#planDiag')?.value?.trim();
    const tch = $('#planTch')?.value?.trim();
    const coun = $('#planCoun')?.value?.trim();
    const parent = $('#planParent')?.value?.trim();

    if (!diag || !tch || !coun) { toast('تنبيه', 'أكملي نصوص الخطة العلاجية أولاً', 'red'); return; }

    const sum = DATA.summary.find(x => String(x.student_id) === String(sid)) || {};
    const weakResults = DATA.results.filter(r => String(r.student_id) === String(sid) && num(r.final_average) < 65);
    const weakNames = weakResults.map(r => r.subject_name || 'مادة دراسية');

    try {
      toast('جاري اعتماد الخطة...', 'يرجى الانتظار');
      const res = await client().rpc('save_remedial_plan_with_tasks', {
        p_student_id: sid,
        p_class_id: cid || (DATA.students.find(s=>String(s.id)===String(sid))||{}).class_id || null,
        p_counselor_id: counId,
        p_teacher_id: tchId,
        p_diagnostic_summary: diag,
        p_teacher_actions: tch,
        p_counselor_actions: coun,
        p_parent_guidance: parent,
        p_weak_subjects: weakNames,
        p_overall_average: num(sum.overall_average || 65)
      });
      if (res.error) throw res.error;
      const d = res.data || {};
      if (d.ok === false) throw new Error(d.message || 'تعذر الاعتماد');
      toast('تم الاعتماد 🚀', d.message, 'green');
      await load();
      render('plans');
    } catch(e) {
      toast('خطأ في الاعتماد', e.message || String(e), 'red');
    }
  }

  function sendWhatsAppToParent() {
    const sid = $('#diagStudent')?.value;
    if (!sid) { toast('تنبيه', 'اختاري الطالب أولاً', 'red'); return; }
    const stu = DATA.students.find(s => String(s.id) === String(sid)) || {};
    let phone = stu.phone_primary || stu.phone_whatsapp || stu.mother_whatsapp || '07800000000';
    let p = String(phone).replace(/\D+/g, '');
    if (p.startsWith('00964')) p = p.slice(2);
    else if (p.startsWith('0') && p.length >= 10) p = '964' + p.slice(1);
    else if (!p.startsWith('964') && p.length === 10) p = '964' + p;

    const name = stu.student_name || stu.name || 'الطالب';
    const isFemale = (getStudentGender(stu) === 'female');
    const sonDaughter = isFemale ? 'كريمتكم' : 'نجلكم';

    const text = `السيد/ة ولي أمر الطالب/ة (${name}) المحترم،\n\nالسلام عليكم ورحمة الله وبركاته.\nنود إعلامكم بأنه حرصاً من إدارة مجمع أمين الرضا (ع) التعليمي على التفوق والارتقاء الأكاديمي لـ ${sonDaughter}، فقد تم إعداد خطة دعم تربوي وعلاجي مشتركة لمتابعته/ا وتدارك التعثر في بعض المواد الدراسية.\nنرجو تفضلكم بالتعاون ومتابعة المذاكرة المنزلية والتواصل المستمر مع معلم المادة والمرشد التربوي عبر منصة المدرسة.\n\nمع خالص التقدير،\nالإدارة الأكاديمية والإرشاد التربوي`;

    const url = `https://wa.me/${p}?text=${encodeURIComponent(text)}`;
    window.open(url, '_blank');
    toast('تم فتح الواتساب 🚀', 'تم إعداد نص الخطة العلاجية لولي الأمر في تطبيق الواتساب مباشرة!', 'green');
  }

  function plansView() {
    const list = DATA.plans || [];
    const rows = list.map(p => {
      const stBadge = { active: '<span class="badge green">نشطة 🤖</span>', under_review: '<span class="badge gold">قيد المراجعة</span>', completed: '<span class="badge blue">مكتملة ✅</span>', cancelled: '<span class="badge red">ملغاة</span>' }[p.status] || p.status;
      const weak = (p.weak_subjects || []).map(w => `<span class="weak-chip">${esc(w)}</span>`).join('') || '—';
      return `<tr><td><b>${esc(p.student_name)}</b><br><small class="muted">${esc(p.class_name)}</small></td><td><b>${num(p.overall_average).toFixed(1)}%</b></td><td>${weak}</td><td>${esc(p.counselor_name)}<br><small class="muted">${esc(p.teacher_name)}</small></td><td>${stBadge}</td><td>${esc(String(p.created_at||'').slice(0,10))}</td><td><button class="btn small gold" onclick="AcademicAnalyticsApp.viewPlanDetails('${p.id}')">التفاصيل / طباعة 🖨️</button></td></tr>`;
    });

    $('#view-plans').innerHTML = `<div class="page-head"><div><h1>📋 سجل خطط الدعم الأكاديمي والعلاجي</h1><p>متابعة الخطط العلاجية المعتمدة للطلاب الضعاف وموقف التنفيذ مع المرشدين والمعلمين.</p></div></div>` +
      table(['الطالب والصف', 'المعدل', 'المواد الضعيفة', 'المتابعة (إرشاد/معلم)', 'الحالة', 'تاريخ الاعتماد', 'إجراء'], rows, 'لا توجد خطط علاجية مسجلة بعد');
  }

  function viewPlanDetails(planId) {
    const p = DATA.plans.find(x => String(x.id) === String(planId));
    if (!p) return;
    const html = `<div class="card" style="margin:20px 0;border:3px solid #0B6E4F;padding:20px"><div class="card-head"><h3>🤖 تقرير خطة الدعم التربوي والعلاجي — الطالب: (${esc(p.student_name)})</h3></div>` +
      `<div class="card-body" style="font-size:15px;line-height:1.8">` +
      `<p><b>الصف:</b> ${esc(p.class_name)} · <b>المعدل العام:</b> ${num(p.overall_average).toFixed(1)}% · <b>المواد الضعيفة:</b> ${(p.weak_subjects||[]).join('، ') || '—'}</p>` +
      `<hr style="margin:12px 0;border-top:1px dashed #ccc">` +
      `<p><b>🤖 ملخص التشخيص:</b><br>${esc(p.diagnostic_summary)}</p>` +
      `<p><b>👨‍🏫 توصيات المعلم في الحصص:</b><br>${esc(p.teacher_actions)}</p>` +
      `<p><b>🧠 إجراءات المرشد التربوي:</b><br>${esc(p.counselor_actions)}</p>` +
      `<p><b>👨‍👩‍👦 توجيهات المذاكرة لولي الأمر:</b><br>${esc(p.parent_guidance)}</p>` +
      `<div style="margin-top:20px;text-align:center"><button class="btn blue" onclick="window.print()">🖨️ طباعة تقرير الخطة</button></div>` +
      `</div></div>`;
    $('#view-plans').insertAdjacentHTML('afterbegin', html);
    window.scrollTo({ top: 0, behavior: 'smooth' });
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

  window.AcademicAnalyticsApp = { init, render, filterDiagStudents, filterByTier, onSelectStudentForPlan, saveRemedialPlan, sendWhatsAppToParent, viewPlanDetails };
})();

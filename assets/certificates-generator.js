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
      `<div><label>🎨 قالب الشهادة الاحترافي *</label><select id="certTemplate" class="select" onchange="CertificatesApp.updatePreview()"><optgroup label="🎨 القوالب الرسمية الزخرفية (للمراحل العليا والرسمية)"><option value="royal">👑 القالب الملكي المذهب (Royal Gold)</option><option value="classic">🏛️ قالب التميز الأكاديمي الكلاسيكي (Classic Heritage)</option><option value="emerald">🌟 قالب الزمرد الإسلامي الفاخر (Emerald Green)</option><option value="modern">💎 القالب العصري الماسي (Modern Executive)</option></optgroup><optgroup label="🖼️ قوالب مدرسة أمين الرضا المصورة (خاص بالأطفال والمرحلة الابتدائية)"><option value="illustrated_auto">✨ القالب المصور الذكي (تلقائي حسب جنس الطالب: أولاد / بنات)</option><option value="illustrated_anime">🎒 قالب الطالب الأنيق (Anime Student - أولاد وبنات)</option><option value="illustrated_graduate">🎓 قالب خريج المستقبل (Graduation Diploma - أولاد وبنات)</option><option value="illustrated_balloons">🎈 قالب البالونات والفراشات (Festive Balloons & Butterflies)</option><option value="illustrated_trophy">🏆 قالب بطل الكأس والقراءة الأنيقة (Trophy & Reading Girl)</option></optgroup></select></div><div><label>نوع الشهادة *</label><select id="certType" class="select" onchange="CertificatesApp.onTypeChange()"><option value="excellence">🏆 شهادة تفوق أكاديمي (لأوائل الصف)</option><option value="general_exempt">🌟 شهادة إعفاء عام (من الامتحانات النهائية)</option><option value="subject_exempt">📚 شهادة إعفاء في مادة دراسية</option><option value="conduct">🛡️ شهادة تقدير وسلوك وانضباط ممتاز</option><option value="teacher_appreciation">👨‍🏫 شهادة شكر وتقدير للمعلم / الموظف</option></select></div>` +
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

  function buildCertificateCard(options) {
    const { type, recipientName, recipientSubtitle, title, subtitle, reasonText, dateStr } = options;
    
    const isFemale = (options.gender === 'female');
    let defaultReason = '';
    if (type === 'excellence') defaultReason = isFemale ? 'تتقدم إدارة مجمع أمين الرضا (ع) التعليمي بأسمى آيات التهاني والبريكات للطالبة المتفوقة تقديراً للتفوق العلمي المتميز والجهد المبذول في التحصيل الدراسي، متمنين لها دوام التوفيق والنجاح.' : 'تتقدم إدارة مجمع أمين الرضا (ع) التعليمي بأسمى آيات التهاني والبريكات للطالب المتفوق تقديراً للتفوق العلمي المتميز والجهد المبذول في التحصيل الدراسي، متمنين له دوام التوفيق والنجاح.';
    else if (type === 'general_exempt') defaultReason = isFemale ? 'يسر إدارة مجمع أمين الرضا (ع) التعليمي أن تمنح الطالبة هذه الشهادة تقديراً للحصول على درجة الإعفاء العام من الامتحانات النهائية لتحقيقها التميز المستمر في جميع المواد الدراسية.' : 'يسر إدارة مجمع أمين الرضا (ع) التعليمي أن تمنح الطالب هذه الشهادة تقديراً للحصول على درجة الإعفاء العام من الامتحانات النهائية لتحقيقه التميز المستمر في جميع المواد الدراسية.';
    else if (type === 'subject_exempt') defaultReason = isFemale ? `يسر إدارة المجمع التعليمي منح الطالبة درجة الإعفاء الرسمي في مادة (${esc(options.subject || 'المادة')}) للعام الدراسي 2026-2027 نظيراً للتميز الدائم والحصول على درجات متفوقة.` : `يسر إدارة المجمع التعليمي منح الطالب درجة الإعفاء الرسمي في مادة (${esc(options.subject || 'المادة')}) للعام الدراسي 2026-2027 نظيراً للتميز الدائم والحصول على درجات متفوقة.`;
    else if (type === 'conduct') defaultReason = isFemale ? 'تمنح إدارة المدرسة هذه الشهادة التقديرية اعتزازاً بالسلوك القويم والانضباط المدرسي الممتاز والأخلاق العالية التي تتحلى بها الطالبة، لتكون قدوة حسنة لزميلاتها.' : 'تمنح إدارة المدرسة هذه الشهادة التقديرية اعتزازاً بالسلوك القويم والانضباط المدرسي الممتاز والأخلاق العالية التي يتحلى بها الطالب، ليكون قدوة حسنة لزملائه.';
    else if (type === 'teacher_appreciation') defaultReason = 'تتقدم إدارة المدرسة بخالص الشكر وعظيم الامتنان تقديراً للجهود العظيمة والإخلاص والتفاني في أداء الرسالة التربوية والتعليمية، ومساهمتكم الفعالة في ارتقاء طلابنا الأبرار.';

    const finalReason = reasonText || defaultReason;
    const template = options.template || 'royal';
    const serial = 'CERT-2026-AMN-' + Math.floor(1000 + Math.random() * 9000);

    if (template.startsWith('illustrated_')) {
      let imgFile = 'boy-anime.jpg';
      if (template === 'illustrated_auto' || template === 'illustrated_anime') {
        imgFile = isFemale ? 'girl-anime.jpg' : 'boy-anime.jpg';
      } else if (template === 'illustrated_graduate') {
        imgFile = isFemale ? 'girl-graduate.jpg' : 'boy-graduate.jpg';
      } else if (template === 'illustrated_balloons') {
        imgFile = isFemale ? 'girl-butterflies.jpg' : 'boy-balloons.jpg';
      } else if (template === 'illustrated_trophy') {
        imgFile = isFemale ? 'girl-reading.jpg' : 'boy-trophy.jpg';
      }
      const imgUrl = `assets/cert-templates/${imgFile}`;

      return `<div class="cert-card illustrated-card" style="background: url('${imgUrl}') center/cover no-repeat; min-height: 680px; position: relative; padding: 40px; display: flex; flex-direction: column; justify-content: center; align-items: center; border: 4px solid #B8860B; border-radius: 18px; box-shadow: 0 10px 30px rgba(0,0,0,0.15); overflow: hidden;">` +
        `<div class="illustrated-overlay" style="background: rgba(255, 255, 255, 0.92); backdrop-filter: blur(6px); border: 2px dashed #0B6E4F; border-radius: 18px; padding: 30px 40px; width: 100%; max-width: 720px; margin: auto; box-shadow: 0 10px 30px rgba(0,0,0,0.12); text-align: center; direction: rtl;">` +
        `<div style="font-size: 26px; font-weight: 800; color: #0B6E4F; margin-bottom: 8px;">` +
        `${esc(title || (isFemale ? '🌟 شهادة شكر وتقدير للطالبة 🌟' : '🏆 شهادة شكر وتقدير للطالب 🏆'))}` +
        `</div>` +
        `<div style="font-size: 16px; color: #555; margin-bottom: 12px;">` +
        `يسر إدارة مدرسة أمين الرضا (ع) أن تهنئ ${isFemale ? 'الطالبة المتميزة' : 'الطالب المتميز'}:` +
        `</div>` +
        `<div style="font-size: 34px; font-weight: 900; color: #8b0000; border-bottom: 3px solid #D4AF37; display: inline-block; padding: 0 25px 8px; margin-bottom: 16px;">` +
        `${esc(recipientName || 'اسم الطالب')}` +
        `</div>` +
        (recipientSubtitle ? `<div style="font-size: 18px; font-weight: 700; color: #1e3a8a; margin-bottom: 14px;">${esc(recipientSubtitle)}</div>` : '') +
        `<div style="font-size: 19px; color: #333; line-height: 1.7; margin-bottom: 25px; padding: 0 10px;">` +
        `${esc(finalReason)}` +
        `</div>` +
        `<div style="display: flex; justify-content: space-around; align-items: center; border-top: 1px dashed #ccc; padding-top: 18px; font-size: 16px; font-weight: bold; color: #0B6E4F; flex-wrap: wrap; gap: 10px;">` +
        `<div>المعلمة: <span style="color:#1e3a8a;">أمل الأسود</span> ✍️</div>` +
        `<div>المديرة: <span style="color:#8b0000;">ريحانة ابراهيمي</span> ✍️</div>` +
        `<div>التاريخ: <span style="color:#555;">${esc(dateStr || iso())}</span></div>` +
        `</div>` +
        `</div>` +
        `<div style="position: absolute; bottom: 12px; left: 20px; background: rgba(0,0,0,0.65); color: #fff; padding: 4px 12px; border-radius: 6px; font-size: 11px; font-family: monospace; letter-spacing: 1px;">` +
        `🔒 ${serial}` +
        `</div>` +
        `</div>`;
    }

    return `<div class="cert-card theme-${template}">` +
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
      `<div style="display:flex;justify-content:space-between;align-items:center;margin-top:25px;padding-top:12px;border-top:1px solid rgba(0,0,0,0.1);font-size:11px;color:#666;direction:rtl;">` +
      `<span>🔒 رمز التحقق الأمني والاعتماد: <b>${serial}</b></span>` +
      `<span>🏫 مجمع أمين الرضا (ع) التعليمي — نظام الشهادات الإلكترونية</span>` +
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
    let stu = null;

    if (t === 'teacher_appreciation') {
      const tid = $('#certTeacher')?.value;
      const tch = DATA.users.find(u => String(u.id) === String(tid));
      recName = tch ? (tch.name || tch.email) : 'الأستاذ الفاضل';
      recSub = tch ? `الوظيفة: ${roleLabel(tch.role)}` : 'الكادر التعليمي والتربوي';
    } else {
      const sid = $('#certStudent')?.value;
      stu = DATA.students.find(s => String(s.id) === String(sid));
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

    let waButtonHtml = '';
    if (t !== 'teacher_appreciation') {
      const sid = $('#certStudent')?.value;
      const stuObj = DATA.students.find(s => String(s.id) === String(sid));
      if (stuObj && stuObj.phone) {
        const cleanPhone = String(stuObj.phone).replace(/\D/g, '');
        const phoneFormatted = cleanPhone.startsWith('0') ? '964' + cleanPhone.substring(1) : (!cleanPhone.startsWith('964') ? '964' + cleanPhone : cleanPhone);
        const msgText = `حضرة ولي أمر الطالب/ة (${recName}) المحترم،\nيسعدنا ويشرفنا في مجمع أمين الرضا (ع) التعليمي أن نبعث لكم خالص التهاني والتبريكات بمناسبة صدور شهادة التميز والتفوق لابنكم/ابنتكم تقديراً للجهد المبذول والأداء الأكاديمي المشرف.\nمع تمنياتنا بدوام التوفيق والنجاح الدائم 🌟👑.`;
        waButtonHtml = `<div class="no-print" style="margin-bottom:15px;text-align:center;"><button class="btn" style="background:#25D366;color:#fff;font-size:15px;font-weight:bold;padding:10px 24px;border-radius:10px;box-shadow:0 4px 12px rgba(37,211,102,0.3);" onclick="window.open('https://wa.me/${phoneFormatted}?text=${encodeURIComponent(msgText)}', '_blank')">💬 إرسال تهنئة الشهادة لولي الأمر عبر واتساب مباشرة</button></div>`;
      }
    }

    box.innerHTML = waButtonHtml + buildCertificateCard({
      type: t,
      recipientName: recName,
      recipientSubtitle: recSub,
      title: titleMap[t] || 'شهادة تقدير',
      subtitle: 'تمنح إدارة المدرسة هذه الشهادة التقديرية إلى:',
      reasonText: customReason,
      dateStr: dateStr,
      subject: subj,
      gender: getStudentGender(stu),
      template: $('#certTemplate')?.value || 'royal'
    });
  }

  function batchView() {
    const classOptions = '<option value="">اختر الصف التابع له الطلاب...</option>' + DATA.classes.map(c => `<option value="${c.id}">${esc(c.name)}</option>`).join('');

    const controlsHtml = `<div class="card cert-controls no-print" style="margin-bottom:20px;border-left:4px solid #B8860B"><div class="card-head"><h3>📚 الإصدار الجماعي السريع للشهادات المدرسية</h3></div><div class="card-body"><div class="hr-form" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;align-items:end">` +
      `<div><label>الصف *</label><select id="batchClass" class="select">${classOptions}</select></div>` +
      `<div><label>🎨 قالب الشهادة الاحترافي *</label><select id="batchTemplate" class="select"><optgroup label="🎨 القوالب الرسمية الزخرفية (للمراحل العليا والرسمية)"><option value="royal">👑 القالب الملكي المذهب (Royal Gold)</option><option value="classic">🏛️ قالب التميز الأكاديمي الكلاسيكي (Classic Heritage)</option><option value="emerald">🌟 قالب الزمرد الإسلامي الفاخر (Emerald Green)</option><option value="modern">💎 القالب العصري الماسي (Modern Executive)</option></optgroup><optgroup label="🖼️ قوالب مدرسة أمين الرضا المصورة (خاص بالأطفال والمرحلة الابتدائية)"><option value="illustrated_auto">✨ القالب المصور الذكي (تلقائي حسب جنس الطالب: أولاد / بنات)</option><option value="illustrated_anime">🎒 قالب الطالب الأنيق (Anime Student - أولاد وبنات)</option><option value="illustrated_graduate">🎓 قالب خريج المستقبل (Graduation Diploma - أولاد وبنات)</option><option value="illustrated_balloons">🎈 قالب البالونات والفراشات (Festive Balloons & Butterflies)</option><option value="illustrated_trophy">🏆 قالب بطل الكأس والقراءة الأنيقة (Trophy & Reading Girl)</option></optgroup></select></div><div><label>الفئة المستهدفة بالشهادات *</label><select id="batchType" class="select"><option value="top5">🏆 أوائل الصف (الخمسة الأوائل حسب المعدل)</option><option value="general_exempt">🌟 الحاصلون على إعفاء عام</option><option value="all_conduct">🛡️ شهادات تقدير وسلوك لجميع طلاب الصف</option></select></div>` +
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
        dateStr: dateStr,
        gender: getStudentGender(s),
        template: $('#batchTemplate')?.value || 'royal'
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

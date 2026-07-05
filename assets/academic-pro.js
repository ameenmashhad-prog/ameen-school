/* Academic Grading and Exemption System */
(function(){
'use strict';
const cfg=()=>window.AMIN_CONFIG||{};let sb=null,ME=null,DATA=null,ACTIVE='overview';
const $=(s,r=document)=>r.querySelector(s);const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
function esc(v){return String(v==null?'':v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#039;')}
function num(v){const n=Number(v);return Number.isFinite(n)?n:0}function pct(v){return Math.round(num(v)*100)/100}function iso(){return new Date().toISOString().slice(0,10)}
function client(){if(sb)return sb;sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});return sb}function toast(t,m,type=''){const el=$('#toast');el.innerHTML=`<b>${esc(t)}</b><br><span class="muted">${esc(m||'')}</span>`;el.className='toast show '+type;clearTimeout(el._t);el._t=setTimeout(()=>el.classList.remove('show'),4200)}
async function q(table,opts={}){try{let query=client().from(table).select(opts.columns||'*');(opts.filters||[]).forEach(f=>query=query[f.op](f.col,f.val));if(opts.order)query=query.order(opts.order,{ascending:opts.ascending!==false});if(opts.limit)query=query.limit(opts.limit);const {data,error}=await query;if(error){console.warn(table,error);return[]}return data||[]}catch(e){console.warn(table,e);return[]}}
function isAdmin(){return ME&&(ME.role==='admin'||ME.is_super_admin||['academic','academic_admin','scientific','supervisor'].includes(ME.role))}function isTeacher(){return ME&&ME.role==='teacher'}
async function ensure(){const {data:{session}}=await client().auth.getSession();if(!session){location.href='index.html';return false}const {data:u}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();ME=u;if(!u){location.href='index.html';return false}if(!(isAdmin()||isTeacher())){document.body.innerHTML='<main class="login-page"><section class="login-card"><h1>غير مصرح</h1><p>نظام الدرجات متاح للإدارة والمعلمين فقط.</p></section></main>';return false}$('#profileName').textContent=u.name||u.email;$('#profileRole').textContent=u.role;return true}
async function load(){const [classes,students,subjects,periods,weights,continuous,exams,scores,results,summary,decisions,locks,tasks,settings]=await Promise.all([q('classes',{order:'name'}),q('students',{order:'name'}),q('subjects',{order:'name'}),q('academic_periods'),q('grade_weights'),q('continuous_assessments'),q('exams'),q('exam_scores'),q('v_academic_subject_results'),q('v_academic_student_summary'),q('academic_exemption_decisions',{order:'created_at',ascending:false}),q('academic_grade_locks',{order:'period_name'}),q('v_my_exam_submission_tasks',{order:'submission_deadline'}),q('school_academic_settings')]);DATA={classes,students,subjects,periods,weights,continuous,exams,scores,results,summary,decisions,locks,tasks,settings:(settings&&settings[0])||{},classMap:new Map(classes.map(x=>[String(x.id),x])),studentMap:new Map(students.map(x=>[String(x.id),x])),subjectMap:new Map(subjects.map(x=>[String(x.id),x]))};render(ACTIVE)}
function fullName(s){return s?[s.name,s.father_name,s.last_name].filter(Boolean).join(' ')||s.name:'—'}
function normAr(v){return String(v||'').toLowerCase().replace(/[إأآا]/g,'ا').replace(/[ىي]/g,'ي').replace(/ة/g,'ه').replace(/ـ/g,'').replace(/\s+/g,'')}
function classStage(cls){if(!cls)return 'all';if(cls.stage_type&&['primary','middle','preparatory'].includes(cls.stage_type))return cls.stage_type;if(cls.stage&&['primary','middle','preparatory'].includes(cls.stage))return cls.stage;const n=normAr(cls.name||'');if(n.includes('ابتدائي')||n.includes('ابتداي')||n.includes('الابتدائ'))return'primary';if(n.includes('متوسط')||n.includes('المتوسط'))return'middle';if(n.includes('اعدادي')||n.includes('إعدادي')||n.includes('الاعدادي')||n.includes('ثانوي')||n.includes('علمي')||n.includes('ادبي'))return'preparatory';return'primary'}
function gradeNo(cls){const n=normAr(cls&&cls.name);const arr=[['الاول',1],['اول',1],['الثاني',2],['ثاني',2],['الثالث',3],['ثالث',3],['الرابع',4],['رابع',4],['الخامس',5],['خامس',5],['السادس',6],['سادس',6]];const h=arr.find(([k])=>n.includes(k));return h?h[1]:0}
function subjectAllowedForClass(sub,cls){const s=normAr(sub&&sub.name),st=classStage(cls),g=gradeNo(cls);if(s.includes('اسلام')||s.includes('قران')||s.includes('عربي')||s.includes('انجليزي')||s.includes('انكليزي')||s.includes('english')||s.includes('رياضيات'))return true;if(st==='primary'){if(s.includes('علوم')||s.includes('فني')||s.includes('فن')||s.includes('بدني')||s.includes('رياضه'))return true;if(g>=4&&g<=6&&s.includes('اجتماع'))return true;return false}if(st==='middle'){return s.includes('فيزياء')||s.includes('كيمياء')||s.includes('احياء')||s.includes('اجتماع')||s.includes('فني')||s.includes('فن')||s.includes('بدني')||s.includes('رياضه')}if(st==='preparatory'){return s.includes('فيزياء')||s.includes('كيمياء')||s.includes('احياء')||s.includes('فني')||s.includes('فن')||s.includes('بدني')||s.includes('رياضه')}return true}
function subjectsForClassId(classId){const cls=DATA.classMap.get(String(classId));return cls?DATA.subjects.filter(s=>subjectAllowedForClass(s,cls)):DATA.subjects}
function className(id){return (DATA.classMap.get(String(id))||{}).name||'—'}function subjectName(id){return (DATA.subjectMap.get(String(id))||{}).name||'—'}function table(h,rows,empty='لا توجد بيانات'){const body=Array.isArray(rows)?rows.join(''):String(rows||'');return body.trim()?`<div class="table-wrap"><table><thead><tr>${h.map(x=>`<th>${esc(x)}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>`:`<div class="empty">${esc(empty)}</div>`}function kpi(l,v,c='gold'){return`<div class="kpi ${c}"><small>${esc(l)}</small><b>${esc(v)}</b></div>`}
function render(id){ACTIVE=id;$$('.view').forEach(v=>v.classList.toggle('active',v.id==='view-'+id));$$('.nav button[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view===id));if(!DATA)return;({overview:overview,entry:entry,continuous:continuousView,exams:examsView,exemptions:exemptionsView,reports:reports,settings:settingsView,locks:renderLocks,schedules:renderSchedules}[id]||overview)()}
function overview(){const total=DATA.students.length,subj=DATA.results.filter(r=>r.subject_exemption_status==='إعفاء مادة').length,general=DATA.summary.filter(s=>s.general_exemption_status==='إعفاء عام').length,cand=DATA.summary.filter(s=>s.general_exemption_status==='مرشح للإعفاء').length,avg=DATA.summary.length?pct(DATA.summary.reduce((a,b)=>a+num(b.overall_average),0)/DATA.summary.length):0;const top=DATA.summary.slice().sort((a,b)=>num(b.overall_average)-num(a.overall_average)).slice(0,10).map((s,i)=>`<tr><td><span class="rank">${i+1}</span></td><td>${esc(s.student_name)}</td><td>${esc(s.class_name)}</td><td>${pct(s.overall_average)}%</td><td><span class="badge ${s.general_exemption_status==='إعفاء عام'?'status-exempt':s.general_exemption_status==='مرشح للإعفاء'?'status-candidate':'status-none'}">${esc(s.general_exemption_status)}</span></td></tr>`);$('#view-overview').innerHTML=`<div class="page-head"><div><h1>لوحة المتابعة الأكاديمية</h1><p>درجات، تقييم مستمر، اختبارات، إعفاءات، وترتيب الطلاب والصفوف.</p></div></div><div class="kpis">${kpi('الطلاب',total,'gold')}${kpi('إعفاء مادة',subj,'green')}${kpi('إعفاء عام',general,'green')}${kpi('مرشحون',cand,'blue')}</div><div class="cards"><div class="card"><div class="card-head"><h3>أوائل الطلاب</h3></div><div class="card-body">${table(['#','الطالب','الصف','المتوسط','الحالة'],top)}</div></div><div class="card"><div class="card-head"><h3>مؤشرات عامة</h3></div><div class="card-body"><div class="list"><div class="item"><b>المتوسط العام</b><span class="badge gold">${avg}%</span></div><div class="item"><b>عدد المواد المقيمة</b><span class="badge blue">${DATA.results.length}</span></div><div class="item"><b>قرارات إدارية</b><span class="badge green">${DATA.decisions.length}</span></div></div></div></div></div>`}
function selectors(prefix){return`<div class="academic-form no-print"><div class="field span-3"><label>الصف</label><select id="${prefix}Class" class="select" onchange="AcademicPro.onClassChange('${prefix}')"><option value="">اختر الصف</option>${DATA.classes.map(c=>`<option value="${c.id}">${esc(c.name)}</option>`).join('')}</select></div><div class="field span-3"><label>الطالب</label><select id="${prefix}Student" class="select"><option value="">اختر الطالب</option></select></div><div class="field span-3"><label>المادة المناسبة للصف</label><select id="${prefix}Subject" class="select"><option value="">اختاري الصف أولاً</option></select></div></div>`}
function fillStudents(prefix){const cid=$('#'+prefix+'Class').value;$('#'+prefix+'Student').innerHTML='<option value="">اختر الطالب</option>'+DATA.students.filter(s=>!cid||String(s.class_id)===String(cid)).map(s=>`<option value="${s.id}">${esc(fullName(s))}</option>`).join('')}
function fillSubjects(prefix){const cid=$('#'+prefix+'Class').value;const list=subjectsForClassId(cid);$('#'+prefix+'Subject').innerHTML='<option value="">اختر المادة</option>'+list.map(s=>`<option value="${s.id}">${esc(s.name)}</option>`).join('')}
function onClassChange(prefix){fillStudents(prefix);fillSubjects(prefix)}
function entry(){if(!isTeacher()&&!isAdmin())return;$('#view-entry').innerHTML=`<div class="page-head"><div><h1>إدخال الدرجات</h1><p>اختاري نوع الإدخال: تقييم مستمر أو اختبار شهري.</p></div></div><div class="cards"><div class="card"><div class="card-head"><h3>تقييم مستمر</h3></div><div class="card-body">${selectors('cont')}<div class="academic-form"><div class="field span-3"><label>نوع التقييم</label><select id="contType" class="select"><option value="participation">المشاركة الصفية</option><option value="homework">الواجبات</option><option value="activity">النشاطات</option><option value="project">المشاريع</option><option value="discipline">الانضباط</option><option value="quiz">اختبار قصير</option></select></div><div class="field span-3"><label>الدرجة من 100</label><input id="contScore" class="input" type="number" min="0" max="100"></div><div class="field span-6"><label>ملاحظات</label><input id="contNotes" class="input"></div><div class="span-12"><button class="btn gold" onclick="AcademicPro.saveContinuous()">حفظ التقييم</button></div></div></div></div><div class="card"><div class="card-head"><h3>اختبار شهري</h3></div><div class="card-body">${selectors('exam')}<div class="academic-form"><div class="field span-3"><label>اسم الاختبار</label><input id="examName" class="input" value="الاختبار الأول"></div><div class="field span-3"><label>ترتيب الاختبار</label><input id="examOrder" class="input" type="number" value="1"></div><div class="field span-3"><label>الدرجة</label><input id="examScore" class="input" type="number" min="0" max="100"></div><div class="field span-3"><label>تاريخ الاختبار</label><input id="examDate" class="input" type="date" value="${new Date().toISOString().slice(0,10)}"></div><div class="span-12"><button class="btn gold" onclick="AcademicPro.saveExamScore()">حفظ الاختبار</button></div></div></div></div></div>`}
function continuousView(){const rows=DATA.continuous.map(r=>`<tr><td>${esc(fullName(DATA.studentMap.get(String(r.student_id))))}</td><td>${esc(subjectName(r.subject_id))}</td><td>${esc(r.component_type)}</td><td>${r.score}</td><td>${esc(r.assessment_date)}</td></tr>`);$('#view-continuous').innerHTML=`<div class="page-head"><div><h1>سجل التقييم المستمر</h1></div></div>${table(['الطالب','المادة','النوع','الدرجة','التاريخ'],rows)}`}
function examsView(){const rows=DATA.scores.map(sc=>{const ex=DATA.exams.find(e=>e.id===sc.exam_id);return`<tr><td>${esc(fullName(DATA.studentMap.get(String(sc.student_id))))}</td><td>${esc(ex?subjectName(ex.subject_id):'—')}</td><td>${esc(ex&&ex.exam_name||'—')}</td><td>${sc.absent?'غائب':sc.score}</td><td>${esc(ex&&ex.exam_date||'—')}</td></tr>`});$('#view-exams').innerHTML=`<div class="page-head"><div><h1>الاختبارات الشهرية</h1></div></div>${table(['الطالب','المادة','الاختبار','الدرجة','التاريخ'],rows)}`}
async function saveContinuous(){const sid=$('#contStudent').value,sub=$('#contSubject').value,cid=$('#contClass').value,score=num($('#contScore').value);if(!sid||!sub||!score){toast('تنبيه','أكملي الطالب والمادة والدرجة','red');return}const {error}=await client().from('continuous_assessments').insert({student_id:sid,subject_id:sub,class_id:cid,teacher_id:ME.id,component_type:$('#contType').value,score,notes:$('#contNotes').value,assessment_month:new Date().getMonth()+1});if(error)toast('خطأ',error.message,'red');else{toast('تم الحفظ','سيتم تحديث الحسابات تلقائياً','green');await load()}}

function renderSchedules() {
  const list = DATA.tasks || [];
  const teachers = (DATA.users||[]).filter(u => u.role === 'teacher' || u.role === 'staff');

  const rows = list.map(t => {
    const pText = {term1_m1:'الشهر 1 (ف1)', term1_m2:'الشهر 2 (ف1)', term1_m3:'الشهر 3 (ف1)', midterm:'نصف السنة', term2_m1:'الشهر 1 (ف2)', term2_m2:'الشهر 2 (ف2)', final:'نهاية السنة', resit2:'الدور الثاني', resit3:'الدور الثالث'}[t.term_period] || t.term_period;
    let stBadge = '<span class="badge gold">بانتظار الرفع</span>';
    if (t.status === 'submitted') stBadge = '<span class="badge green">تم الرفع 📤</span>';
    else if (t.status === 'late') stBadge = '<span class="badge red">متأخر! تجاوز المهلة ⚠️</span>';
    else if (t.status === 'approved') stBadge = '<span class="badge green" style="background:#0B6E4F;color:#fff">معتمد رسمياً 🟢</span>';
    else if (t.status === 'rejected') stBadge = '<span class="badge red">مرفوض/طلب تعديل 🔄</span>';
    else if (t.status === 'offline_verified') stBadge = `<span class="badge blue">إثبات: ${esc(t.delivery_method)} 📲</span>`;

    let actions = `<button class="btn small gold" onclick="AcademicPro.verifyOfflinePrompt('${t.id}')">إثبات تسليم 📲</button>`;
    if (t.status === 'submitted' || t.status === 'offline_verified' || t.status === 'late') {
      actions += ` <button class="btn small green" onclick="AcademicPro.reviewTask('${t.id}', 'approved')" title="اعتماد وقفل على المعلم">✅ اعتماد</button>`;
      actions += ` <button class="btn small red" onclick="AcademicPro.reviewTask('${t.id}', 'rejected')" title="طلب إعادة رفع من المعلم">🔄 تعديل</button>`;
    } else if (t.status === 'approved') {
      actions += ` <button class="btn small red" onclick="AcademicPro.reviewTask('${t.id}', 'rejected')" title="إلغاء الاعتماد وطلب التعديل">🔓 إلغاء وتعديل</button>`;
    }

    const fileLink = t.question_file_url ? `<a class="btn small blue" href="/api/proxy/storage/v1/object/public/exam-questions/${t.question_file_url}" target="_blank">تحميل الأسئلة 📄</a>` : '—';
    const proofAction = `<button class="btn small gold" onclick="AcademicPro.verifyOfflinePrompt('${t.id}')">إثبات تسليم خارجي 📲</button>`;

    return `<tr><td><b>${esc(pText)}</b></td><td>${esc(t.class_name||'—')}</td><td>${esc(t.subject_name||'—')}</td><td>${esc(t.teacher_name||'—')}</td><td><b>${esc(t.exam_date||'—')}</b><br><small class="muted">${t.start_time||''}-${t.end_time||''}</small></td><td>${esc(t.required_topics||'لم تُحدد بعد')}</td><td>${esc(String(t.submission_deadline||'').slice(0,16).replace('T',' '))}</td><td>${stBadge}</td><td>${fileLink}</td><td>${actions}</td></tr>`;
  });

  const excelBatchHtml = `<div class="card" style="margin-bottom:20px;border-left:4px solid #0B6E4F"><div class="card-head"><h3>🚀 الجدولة السريعة عبر الإكسل (Excel Batch Import)</h3></div><div class="card-body" style="display:flex;gap:12px;align-items:center;flex-wrap:wrap">` +
    `<button class="btn blue" onclick="AcademicPro.downloadExamTemplate()">📥 تحميل قالب إكسل الامتحانات (CSV Template)</button>` +
    `<div style="flex:1;min-width:230px"><input type="file" id="examExcelFile" accept=".csv,.xlsx,.xls" class="input" style="padding:4px"></div>` +
    `<button class="btn gold" onclick="AcademicPro.uploadExamExcel()">📤 رفع الإكسل وتوليد مواعيد الامتحانات والمهام فوراً</button>` +
    `</div></div>`;

  const formHtml = `<div class="card" style="margin-bottom:20px"><div class="card-head"><h3>إعداد موعد امتحان وتكليف المعلم بتسليم الأسئلة يدوياً (حصري بالإدارة)</h3></div><div class="card-body"><div class="academic-form">` +
    `<div class="field span-3"><label>الفترة الامتحانية *</label><select id="schPeriod" class="select"><option value="term1_m1">الشهر الأول (الفصل الأول)</option><option value="term1_m2">الشهر الثاني (الفصل الأول)</option><option value="term1_m3">الشهر الثالث (الفصل الأول)</option><option value="midterm">امتحان نصف السنة</option><option value="term2_m1">الشهر الأول (الفصل الثاني)</option><option value="term2_m2">الشهر الثاني (الفصل الثاني)</option><option value="final">امتحان نهاية السنة</option><option value="resit2">امتحان الدور الثاني</option><option value="resit3">امتحان الدور الثالث</option></select></div>` +
    `<div class="field span-3"><label>الصف *</label><select id="schClass" class="select" onchange="AcademicPro.onSchClassChange()"><option value="">اختر الصف</option>${DATA.classes.map(c=>`<option value="${c.id}">${esc(c.name)}</option>`).join('')}</select></div>` +
    `<div class="field span-3"><label>المادة *</label><select id="schSubj" class="select"><option value="">اختر المادة</option></select></div>` +
    `<div class="field span-3"><label>المعلم المكلف بوضع الأسئلة *</label><select id="schTeacher" class="select"><option value="">اختر المعلم</option>${teachers.map(u=>`<option value="${u.id}">${esc(u.name||u.email)}</option>`).join('')}</select></div>` +
    `<div class="field span-3"><label>يوم وتاريخ الامتحان *</label><input id="schDate" type="date" class="input" value="${new Date().toISOString().slice(0,10)}"></div>` +
    `<div class="field span-2"><label>وقت البداية *</label><input id="schStart" type="time" class="input" value="08:30"></div>` +
    `<div class="field span-2"><label>وقت النهاية *</label><input id="schEnd" type="time" class="input" value="10:00"></div>` +
    `<div class="field span-5"><label>موعد انتهاء صلاحية رفع الأسئلة (Deadline) *</label><input id="schDeadline" type="datetime-local" class="input" value="${new Date(Date.now()+86400000*2).toISOString().slice(0,16)}"></div>` +
    `<div class="span-6"><button class="btn gold block" onclick="AcademicPro.saveExamScheduleTask()">حفظ موعد مادة واحدة وتكليف المعلم 🚀</button></div><div class="span-6"><button class="btn blue block" onclick="AcademicPro.autoGenerateClassSchedule()" title="ينشئ مواعيد ومهام لكل مواد الصف تلقائياً بضغطة زر">⚡ توليد ذكي لجدول الصف كامل بضغطة زر ⚡</button></div>` +
    `</div></div></div>`;

  $('#view-schedules').innerHTML = `<div class="page-head"><div><h1>جدول ومواعيد الامتحانات ومهام الأسئلة 🗓️</h1><p>تحديد الإدارة لأيام ومواعيد الامتحانات حصراً، وتكليف المعلمين برفع الأسئلة ومتابعة التسليم.</p></div></div>` +
    `<div class="kpis">${kpi('إجمالي المهام', list.length, 'blue')}${kpi('تم التسليم 📤', list.filter(x=>x.status==='submitted'||x.status==='offline_verified').length, 'green')}${kpi('متأخر / تجاوز المهلة ⚠️', list.filter(x=>x.status==='late').length, 'red')}</div>` +
    excelBatchHtml + formHtml + table(['الفترة', 'الصف', 'المادة', 'المعلم المكلف', 'موعد الامتحان', 'المادة المطلوبة', 'مهلة الرفع', 'الحالة', 'ملف الأسئلة', 'إجراء'], rows, 'لا توجد مواعيد امتحانات مسجلة');
}

function downloadExamTemplate() {
  const headers = ['period', 'class_name', 'subject_name', 'teacher_email', 'exam_date', 'start_time', 'end_time', 'deadline'];
  const sample1 = ['term1_m1', 'الأول الابتدائي', 'الرياضيات', 'slyman@ameen.iq', '2026-10-15', '08:30', '10:00', '2026-10-12 23:59'];
  const sample2 = ['midterm', 'الثاني المتوسط', 'الفيزياء', 'teacher@ameen.iq', '2026-12-20', '09:00', '11:00', '2026-12-17 23:59'];
  
  const csvContent = '\uFEFF' + [headers.join(','), sample1.join(','), sample2.join(',')].join('\n');
  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'exam_schedules_template.csv';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  toast('تم التحميل 📥', 'تم تحميل قالب جدول الامتحانات بنجاح', 'green');
}

async function uploadExamExcel() {
  const fileEl = $('#examExcelFile');
  const file = fileEl && fileEl.files && fileEl.files[0];
  if (!file) { toast('تنبيه', 'اختاري ملف الإكسل (CSV) أولاً', 'red'); return; }

  const reader = new FileReader();
  reader.onload = async function(e) {
    const text = e.target.result;
    const lines = text.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
    if (lines.length < 2) { toast('خطأ', 'الملف فارغ أو لا يحتوي على بيانات بعد السطر الأول', 'red'); return; }

    const rows = [];
    for (let i = 1; i < lines.length; i++) {
      const cols = lines[i].split(',').map(c => c.trim().replace(/^["']|["']$/g, ''));
      if (cols.length < 5) continue;
      rows.push({
        period: cols[0],
        class_name: cols[1],
        subject_name: cols[2],
        teacher_email: cols[3],
        exam_date: cols[4],
        start_time: cols[5] || '08:30',
        end_time: cols[6] || '10:00',
        deadline: cols[7] || null
      });
    }

    if (!rows.length) { toast('خطأ', 'لم يتم العثور على أسطر صالحة للاستيراد', 'red'); return; }

    try {
      toast('جاري الاستيراد...', 'تم إرسال ' + rows.length + ' موعد للتوليد');
      const res = await client().rpc('academic_batch_import_exam_schedules', { p_rows: rows });
      if (res.error) throw res.error;
      const d = res.data || {};
      if (d.ok === false) throw new Error(d.message || 'فشل الاستيراد');
      toast('تم الاستيراد بنجاح 🚀', d.message, 'green');
      await load();
    } catch(err) {
      toast('خطأ في الاستيراد', err.message || String(err), 'red');
    }
  };
  reader.readAsText(file, 'utf-8');
}

async function autoGenerateClassSchedule() {
  const period = $('#schPeriod')?.value;
  const cid = $('#schClass')?.value;
  const date = $('#schDate')?.value;
  if (!cid || !date) {
    toast('تنبيه', 'اختاري الصف وتاريخ بدء الامتحانات أولاً لتوليد الجدول كاملاً', 'red');
    return;
  }
  if (!confirm('هل تريدين توليد مواعيد ومهام تسليم الأسئلة لجميع مواد الصف بضغطة زر واحدة؟')) return;

  try {
    toast('جاري التوليد الذكي...', 'يرجى الانتظار');
    const res = await client().rpc('academic_auto_generate_class_schedule', {
      p_period: period,
      p_class_id: cid,
      p_start_date: date
    });
    if (res.error) throw res.error;
    const d = res.data || {};
    if (d.ok === false) throw new Error(d.message || 'تعذر التوليد');
    toast('تم التوليد الذكي بنجاح 🚀', d.message, 'green');
    await load();
  } catch(e) {
    toast('خطأ في التوليد', e.message || String(e), 'red');
  }
}

async function reviewTask(taskId, status) {
  let notes = null;
  if (status === 'rejected') {
    notes = prompt('أدخلي ملاحظة طلب التعديل للمعلم (مثال: الأسئلة غير واضحة في السؤال الثاني):', 'يرجى مراجعة وتعديل الأسئلة وإعادة الرفع');
    if (notes === null) return;
  }
  try {
    const res = await client().rpc('academic_review_exam_task', {
      p_task_id: taskId,
      p_status: status,
      p_notes: notes || null
    });
    if (res.error) throw res.error;
    const d = res.data || {};
    if (d.ok === false) throw new Error(d.message || 'تعذر الاعتماد');
    toast('تم بنجاح 🟢', d.message, status === 'approved' ? 'green' : 'gold');
    await load();
  } catch(e) {
    toast('خطأ في المراجعة', e.message || String(e), 'red');
  }
}
function onSchClassChange() {
  const cid = $('#schClass')?.value;
  const list = subjectsForClassId(cid);
  if ($('#schSubj')) $('#schSubj').innerHTML = '<option value="">اختر المادة</option>' + list.map(s => `<option value="${s.id}">${esc(s.name)}</option>`).join('');
}

async function saveExamScheduleTask() {
  const period = $('#schPeriod')?.value;
  const cid = $('#schClass')?.value;
  const sid = $('#schSubj')?.value;
  const tid = $('#schTeacher')?.value;
  const date = $('#schDate')?.value;
  const start = $('#schStart')?.value;
  const end = $('#schEnd')?.value;
  const deadline = $('#schDeadline')?.value;

  if (!cid || !sid || !tid || !date) {
    toast('تنبيه', 'أكملي اختيار الصف والمادة والمعلم وتاريخ الامتحان', 'red');
    return;
  }

  try {
    const res = await client().rpc('academic_create_exam_schedule_with_task', {
      p_period: period,
      p_class_id: cid,
      p_subject_id: sid,
      p_teacher_id: tid,
      p_exam_date: date,
      p_start_time: start || '08:30',
      p_end_time: end || '10:00',
      p_deadline: deadline ? new Date(deadline).toISOString() : null
    });
    if (res.error) throw res.error;
    const d = res.data || {};
    if (d.ok === false) throw new Error(d.message || 'تعذر الحفظ');
    toast('تم بنجاح', d.message, 'green');
    await load();
  } catch(e) {
    toast('خطأ في الحفظ', e.message || String(e), 'red');
  }
}

async function verifyOfflinePrompt(taskId) {
  const method = prompt('أدخلي طريقة التسليم الخارجي أو اليدوي (manual / whatsapp / eitaa / bale):', 'manual');
  if (!method) return;
  const note = prompt('ملاحظة إثبات التسليم (مثال: تم الاستلام ورقي عند انقطاع الإنترنت):', 'تم الاستلام يدوياً ورقي');
  try {
    const res = await client().rpc('submit_exam_task_questions', {
      p_task_id: taskId,
      p_file_url: null,
      p_delivery_method: method,
      p_proof_note: note || null
    });
    if (res.error) throw res.error;
    toast('تم التوثيق', 'تم توثيق التسليم الخارجي بنجاح 📲', 'green');
    await load();
  } catch(e) {
    toast('خطأ', e.message || String(e), 'red');
  }
}
function renderLocks() {
  const list = DATA.locks || [];
  const lockedCount = list.filter(x => x.is_locked).length;
  const openCount = list.filter(x => !x.is_locked).length;

  const rows = list.map(l => {
    const pText = {m1:'الشهر الأول', m2:'الشهر الثاني', midterm:'امتحان نصف السنة', m3:'الشهر الثالث', m4:'الشهر الرابع', final:'امتحان نهاية السنة'}[l.period_name] || l.period_name;
    const stText = {all:'كل المراحل', primary:'الابتدائية', middle:'المتوسطة', preparatory:'الإعدادية'}[l.stage_type] || l.stage_type;
    const clsText = l.class_id ? className(l.class_id) : 'كل الصفوف';
    const badge = l.is_locked ? '<span class="badge red">🔒 مقفل</span>' : '<span class="badge green">🔓 مفتوح</span>';
    const actionBtn = l.is_locked
      ? `<button class="btn small green" onclick="AcademicPro.toggleGradeLock('${l.period_name}', '${l.stage_type}', ${l.class_id ? `'${l.class_id}'` : 'null'}, false)">فتح الرصد 🔓</button>`
      : `<button class="btn small red" onclick="AcademicPro.toggleGradeLock('${l.period_name}', '${l.stage_type}', ${l.class_id ? `'${l.class_id}'` : 'null'}, true)">قفل الرصد 🔒</button>`;
    return `<tr><td><b>${esc(pText)}</b></td><td><span class="badge blue">${esc(stText)}</span></td><td>${esc(clsText)}</td><td>${badge}</td><td>${esc(l.notes||'—')}</td><td>${actionBtn}</td></tr>`;
  });

  const formHtml = `<div class="card" style="margin-bottom:20px"><div class="card-head"><h3>تعديل قفل فترة دراسية (مع فلترة الصفوف حسب المرحلة واختيار متعدد بالصح ☑)</h3></div><div class="card-body"><div class="academic-form">` +
    `<div class="field span-3"><label>الفترة الدراسية *</label><select id="lockPeriod" class="select"><option value="m1">الشهر الأول</option><option value="m2">الشهر الثاني</option><option value="midterm">امتحان نصف السنة</option><option value="m3">الشهر الثالث</option><option value="m4">الشهر الرابع</option><option value="final">امتحان نهاية السنة</option></select></div>` +
    `<div class="field span-3"><label>المرحلة المستهدفة *</label><select id="lockStage" class="select" onchange="AcademicPro.onLockStageChange()"><option value="all">كل المراحل</option><option value="primary">المرحلة الابتدائية</option><option value="middle">المرحلة المتوسطة</option><option value="preparatory">المرحلة الإعدادية</option></select></div>` +
    `<div class="field span-3"><label>حالة القفل *</label><select id="lockState" class="select"><option value="true">🔒 قفل وإغلاق الرصد</option><option value="false">🔓 فتح الرصد للتعديل</option></select></div>` +
    `<div class="field span-3"><label>&nbsp;</label><button class="btn gold block" onclick="AcademicPro.saveNewGradeLock()">حفظ حالة القفل 🚀</button></div>` +
    `<div class="field span-12"><label>الصفوف التابعة للمرحلة (اختيار متعدد بالـ Checkbox / الجميع) *</label><div id="lockClassBox" style="max-height:130px;overflow-y:auto;border:1px solid #ccc;padding:8px;border-radius:6px;background:#f9f9f9;display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:6px"></div></div>` +
    `<div class="field span-12"><label>ملاحظات إدارية</label><input id="lockNotes" class="input" placeholder="مثال: تم إغلاق رصد درجات الشهر الأول بعد انتهاء المهلة الرسمية"></div>` +
    `</div></div></div>`;

  $('#view-locks').innerHTML = `<div class="page-head"><div><h1>قفل الدرجات والصلاحيات 🔒</h1><p>التحكم في إغلاق وفتح رصد وتعديل الدرجات للمعلمين حسب الفترات الدراسية والمراحل.</p></div></div>` +
    `<div class="kpis">${kpi('إجمالي الفترات', list.length, 'blue')}${kpi('فترات مقفلة 🔒', lockedCount, 'red')}${kpi('فترات مفتوحة 🔓', openCount, 'green')}</div>` +
    formHtml + table(['الفترة الدراسية', 'المرحلة', 'الصف', 'حالة القفل', 'ملاحظات', 'إجراء'], rows, 'لا توجد فترات مقفلة حالياً (الرصد مفتوح لجميع الفترات)');
  
  setTimeout(() => { if (window.AcademicPro && AcademicPro.onLockStageChange) AcademicPro.onLockStageChange(); }, 10);
}

function onLockStageChange() {
  const st = $('#lockStage')?.value || 'all';
  const list = DATA.classes.filter(c => st === 'all' || classStage(c) === st);
  const box = $('#lockClassBox');
  if (!box) return;

  box.innerHTML = `<div style="grid-column:1/-1;border-bottom:1px solid #ddd;padding-bottom:4px;margin-bottom:4px"><label style="font-weight:bold;cursor:pointer;display:flex;align-items:center;gap:6px;color:#0B6E4F"><input type="checkbox" id="selectAllLocks" onchange="AcademicPro.toggleAllLockClasses(this.checked)"> اختيار جميع صفوف المرحلة (${list.length})</label></div>` +
    list.map(c => `<label style="display:flex;align-items:center;gap:6px;cursor:pointer;background:#fff;padding:4px 8px;border:1px solid #eee;border-radius:4px"><input type="checkbox" class="lock-cls-chk" value="${c.id}"> ${esc(c.name)}</label>`).join('');
}

function toggleAllLockClasses(checked) {
  document.querySelectorAll('.lock-cls-chk').forEach(el => el.checked = checked);
}

async function toggleGradeLock(period, stage, classId, lockState) {
  try {
    const res = await client().rpc('academic_set_grade_lock', {
      p_period: period,
      p_stage: stage || 'all',
      p_class_id: classId || null,
      p_is_locked: lockState,
      p_notes: null
    });
    if (res.error) throw res.error;
    const d = res.data || {};
    if (d.ok === false) throw new Error(d.message || 'تعذر التحديث');
    toast('تم التحديث بنجاح', d.message, lockState ? 'red' : 'green');
    await load();
  } catch(e) {
    toast('خطأ في التحديث', e.message || String(e), 'red');
  }
}

async function saveNewGradeLock() {
  const period = $('#lockPeriod')?.value;
  const stage = $('#lockStage')?.value || 'all';
  const checked = Array.from(document.querySelectorAll('.lock-cls-chk:checked')).map(el => el.value);
  const isLocked = ($('#lockState')?.value === 'true');
  const notes = $('#lockNotes')?.value || null;

  if (checked.length === 0 && !confirm('لم تقمي باختيار صفوف محددة بالصح ☑. هل تريدين تطبيق القفل على كل الصفوف في المرحلة (' + stage + ') دفعة واحدة؟')) return;

  try {
    const targetClasses = checked.length > 0 ? checked : [null];
    for (const cid of targetClasses) {
      const res = await client().rpc('academic_set_grade_lock', {
        p_period: period,
        p_stage: stage,
        p_class_id: cid,
        p_is_locked: isLocked,
        p_notes: notes
      });
      if (res.error) throw res.error;
    }
    toast('تم الحفظ بنجاح 🔒', 'تم تحديث قفل الدرجات والصلاحيات بنجاح', 'green');
    await load();
  } catch(e) {
    toast('خطأ في الحفظ', e.message || String(e), 'red');
  }
}
async function saveExamScore(){const sid=$('#examStudent').value,sub=$('#examSubject').value,cid=$('#examClass').value,score=num($('#examScore').value);if(!sid||!sub){toast('تنبيه','أكملي الطالب والمادة','red');return}let {data:exam,error:e1}=await client().from('exams').insert({class_id:cid,subject_id:sub,teacher_id:ME.id,exam_name:$('#examName').value,exam_order:num($('#examOrder').value),exam_date:$('#examDate').value}).select().single();if(e1){toast('خطأ',e1.message,'red');return}const {error}=await client().from('exam_scores').upsert({exam_id:exam.id,student_id:sid,score,entered_by:ME.id},{onConflict:'exam_id,student_id'});if(error)toast('خطأ',error.message,'red');else{toast('تم الحفظ','تم تحديث نتيجة الاختبار','green');await load()}}
function exemptionsView(){
  const pub = DATA.settings && DATA.settings.exemption_published;
  const toggleBtn = isAdmin() ? `<div style="margin-bottom:15px;background:#fff;padding:12px;border-radius:8px;border:1px solid #ccc;display:flex;align-items:center;justify-content:space-between"><span style="font-weight:bold">حالة نشر الإعفاءات للطلاب والمعلمين (حصري بالمدير والمعاون العلمي):</span><div><button class="btn ${pub ? 'red' : 'blue'}" onclick="AcademicPro.toggleExemptionPublish(${!pub})">${pub ? '🔴 إخفاء الإعفاءات (مخفية حالياً)' : '🟢 إظهار ونشر الإعفاءات للجميع'}</button> <span class="badge ${pub ? 'green' : 'gold'}">${pub ? 'منشورة 🟢' : 'مخفية 🔒'}</span></div></div>` : '';
  const rows=DATA.results.map(r=>`<tr><td>${esc(r.student_name)}</td><td>${esc(r.class_name)}</td><td>${esc(r.subject_name)}</td><td>${pct(r.final_average)}%</td><td>${pct(r.attendance_rate)}%</td><td><span class="badge ${r.subject_exemption_status==='إعفاء مادة'?'status-exempt':r.subject_exemption_status==='مرشح للإعفاء'?'status-candidate':'status-none'}">${esc(r.subject_exemption_status)}</span></td><td>${r.points_to_subject_exemption?`يحتاج ${pct(r.points_to_subject_exemption)} درجة`:''}</td><td>${isAdmin()?`<button class="btn green" onclick="AcademicPro.approveSubject('${r.student_id}','${r.subject_id}',${r.final_average})">اعتماد</button>`:''}</td></tr>`);const gen=DATA.summary.map(s=>`<tr><td>${esc(s.student_name)}</td><td>${esc(s.class_name)}</td><td>${pct(s.overall_average)}%</td><td>${s.subjects_below_85}</td><td><span class="badge ${s.general_exemption_status==='إعفاء عام'?'status-exempt':s.general_exemption_status==='مرشح للإعفاء'?'status-candidate':'status-none'}">${esc(s.general_exemption_status)}</span></td><td>${isAdmin()?`<button class="btn green" onclick="AcademicPro.approveGeneral('${s.student_id}',${s.overall_average})">اعتماد عام</button>`:''}</td></tr>`);$('#view-exemptions').innerHTML=`<div class="page-head"><div><h1>الإعفاءات والمرشحون</h1><p>الإعفاء لا يطبق على الابتدائي. المرشحون يحتاجون مراجعة الإدارة.</p></div></div>${toggleBtn}<div class="card"><div class="card-head"><h3>إعفاء مادة</h3></div><div class="card-body">${table(['الطالب','الصف','المادة','النهائي','الحضور','الحالة','الدعم',''],rows)}</div></div><div class="card"><div class="card-head"><h3>الإعفاء العام</h3></div><div class="card-body">${table(['الطالب','الصف','المتوسط','مواد أقل من 85','الحالة',''],gen)}</div></div>`}
async function approveSubject(student,subject,avg){await client().from('academic_exemption_decisions').insert({student_id:student,subject_id:subject,exemption_kind:'subject',status_ar:'إعفاء مادة',calculated_average:avg,approved_by:ME.id,approved_at:new Date().toISOString()});toast('تم الاعتماد','تم اعتماد إعفاء المادة','green');await load()}
async function approveGeneral(student,avg){await client().from('academic_exemption_decisions').insert({student_id:student,exemption_kind:'general',status_ar:'إعفاء عام',calculated_average:avg,approved_by:ME.id,approved_at:new Date().toISOString()});toast('تم الاعتماد','تم اعتماد الإعفاء العام','green');await load()}
async function toggleExemptionPublish(pub) {
  try {
    const res = await client().rpc('toggle_exemption_publish', { p_publish: pub });
    if (res.error) throw res.error;
    const d = res.data || {};
    if (d.ok === false) throw new Error(d.message || 'تعذر التغيير');
    toast('تم بنجاح', d.message, 'green');
    await load();
  } catch(e) {
    toast('خطأ', e.message || String(e), 'red');
  }
}
function reports(){const rows=DATA.summary.map((s,i)=>`<tr><td>${i+1}</td><td>${esc(s.student_name)}</td><td>${esc(s.class_name)}</td><td>${pct(s.overall_average)}%</td><td>${esc(s.general_exemption_status)}</td></tr>`);$('#view-reports').innerHTML=`<div class="page-head"><div><h1>التقارير الأكاديمية</h1></div></div>${table(['الترتيب','الطالب','الصف','المتوسط','الحالة'],rows)}`}
function settingsView(){if(!isAdmin()){$('#view-settings').innerHTML='<div class="empty">الأوزان والمعايير للإدارة فقط.</div>';return}const rows=['primary','middle','preparatory'].map(st=>{const w=DATA.weights.find(x=>x.stage_type===st)||{};const label={primary:'ابتدائي',middle:'متوسط',preparatory:'إعدادي'}[st];return`<div class="weights-row"><b>${label}</b><input class="input" id="cw_${st}" type="number" value="${w.continuous_weight??(st==='primary'?20:10)}"><input class="input" id="ew_${st}" type="number" value="${w.monthly_exam_weight??(st==='primary'?80:90)}"><button class="btn gold" onclick="AcademicPro.saveWeight('${st}')">حفظ</button></div>`}).join('');$('#view-settings').innerHTML=`<div class="page-head"><div><h1>الأوزان والمعايير</h1><p>تعديل الأوزان دون تعديل الكود.</p></div></div><div class="card"><div class="card-body">${rows}</div></div>`}
async function saveWeight(stage){const cw=num($('#cw_'+stage).value),ew=num($('#ew_'+stage).value);if(cw+ew!==100&&!confirm('مجموع الأوزان ليس 100. هل تريدين الحفظ؟'))return;const {error}=await client().from('grade_weights').upsert({academic_year:'2026-2027',stage_type:stage,continuous_weight:cw,monthly_exam_weight:ew,updated_by:ME.id},{onConflict:'academic_year,stage_type'});if(error)toast('خطأ',error.message,'red');else{toast('تم الحفظ','تم تحديث الأوزان','green');await load()}}
function printActive(){window.print()}function bind(){ $$('.nav button[data-view]').forEach(b=>b.addEventListener('click',()=>render(b.dataset.view)));$('#mobileMenuBtn')?.addEventListener('click',()=>$('#sidebar').classList.toggle('open'));$('#logoutBtn').addEventListener('click',async()=>{await client().auth.signOut({scope:'local'});location.href='index.html'});$('#refreshBtn').addEventListener('click',load)}
async function init(){client();if(!await ensure())return;bind();await load()}
window.AcademicPro={init,render,fillStudents,fillSubjects,onClassChange,saveContinuous,saveExamScore,approveSubject,approveGeneral,saveWeight,printActive,renderLocks,toggleGradeLock,saveNewGradeLock,onLockStageChange,toggleAllLockClasses,toggleExemptionPublish,renderSchedules,downloadExamTemplate,uploadExamExcel,onSchClassChange,saveExamScheduleTask,verifyOfflinePrompt};
}());
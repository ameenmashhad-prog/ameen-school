/* مدارس أمين الرضا (ع) — Clean Role Portals
   Vanilla JS + local Supabase + Vercel /api proxy.
   ملاحظة صيانة:
   - هذا الملف هو runtime الفعلي لصفحات index.html و staff.html وبعض البوابات الدورّية.
   - لا يُعتبر بديلاً عن assets/portal-app.js لصفحة portal.html.
*/
(function(){
'use strict';
window.AMIN_RUNTIME_INFO = Object.assign({}, window.AMIN_RUNTIME_INFO || {}, {
  core: 'assets/core.js',
  core_mode: 'role-portals',
  core_active: true
});

const cfg = () => window.AMIN_CONFIG || {};
let sb = null;
let ME = null;
let SESSION = null;
let DATA = null;
let CURRENT_STUDENT_ID = null;
let ACTIVE_VIEW = null;
let LAST_ATTENDANCE_ROWS = [];

const ROLE_LABELS = {
  admin:'مدير', finance:'مسؤول مالي', discipline:'مسؤول انضباط', counselor:'مرشد نفسي', psychologist:'مرشد نفسي',
  teacher:'معلم', parent:'ولي أمر', student:'طالب', academic:'مسؤول علمي', scientific:'مسؤول علمي', academic_supervisor:'مسؤول علمي', academic_admin:'مسؤول علمي', educational:'مسؤول علمي', education:'مسؤول علمي', supervisor:'مسؤول علمي'
};
const MONTHS = {9:'سبتمبر',10:'أكتوبر',11:'نوفمبر',12:'ديسمبر',1:'يناير',2:'فبراير',3:'مارس',4:'أبريل',5:'مايو'};
const DAYS = ['السبت','الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة'];

function $(s,r=document){return r.querySelector(s)}
function $$(s,r=document){return Array.from(r.querySelectorAll(s))}
function esc(v){return String(v==null?'':v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#039;')}
function num(v){const n=Number(v);return Number.isFinite(n)?n:0}
function money(v){return num(v).toLocaleString('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0})}
function ar(v){return num(v).toLocaleString('ar-IQ')}
function iso(){return new Date().toISOString().slice(0,10)}
function pct(v){return Math.max(0,Math.min(100,Math.round(num(v))))}
function fullName(s){return s ? [s.name,s.father_name,s.last_name].filter(Boolean).join(' ') || s.name || '—' : '—'}
function roleLabel(role){return ROLE_LABELS[role] || role || 'مستخدم'}
function className(id){const c = DATA && DATA.classMap.get(String(id)); return c ? (c.name || c.title || 'صف') : '—'}
function subjectName(id){const s = DATA && DATA.subjectMap.get(String(id)); return s ? (s.name || s.title || 'مادة') : '—'}
function studentName(id){const s = DATA && DATA.studentMap.get(String(id)); return fullName(s)}
function toast(title,msg,type=''){const t=$('#toast'); if(!t)return; t.innerHTML=`<b>${esc(title)}</b><br><span class="muted">${esc(msg||'')}</span>`; t.className='toast show '+type; clearTimeout(t._to); t._to=setTimeout(()=>t.classList.remove('show'),4200)}

function client(){
  if(sb) return sb;
  if(!window.supabase) throw new Error('مكتبة Supabase غير محملة');
  sb = window.supabase.createClient(cfg().supabaseUrl, cfg().supabaseAnonKey, {auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});
  return sb;
}

async function recover(error){
  const m = String(error && (error.message || error.code) || '').toLowerCase();
  if(!m.includes('jwt expired') && !m.includes('pgrst303')) return false;
  try{ const r=await client().auth.refreshSession(); return !!(r.data && r.data.session); }catch(e){ return false; }
}

async function q(table, options={}){
  const {_retry=false, columns='*', limit=1000, order=null, ascending=true, filters=[]} = options;
  try{
    let query = client().from(table).select(columns);
    filters.forEach(f=>{ if(f && query[f.op]) query=query[f.op](f.col,f.val); });
    if(order) query=query.order(order,{ascending});
    if(limit) query=query.limit(limit);
    const {data,error}=await query;
    if(error){ if(!_retry && await recover(error)) return q(table,Object.assign({},options,{_retry:true})); console.warn('[select]',table,error); return []; }
    return data || [];
  }catch(e){ if(!_retry && await recover(e)) return q(table,Object.assign({},options,{_retry:true})); console.warn('[select failed]',table,e); return []; }
}

async function authProfile(){
  const {data:{session}} = await client().auth.getSession();
  if(!session){ location.href='index.html'; return null; }
  SESSION=session;
  const {data:user,error}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();
  if(error || !user){ toast('تعذر تحميل الحساب','سجلي دخول من جديد','red'); return null; }
  ME=user;
  return user;
}

function routeFor(profile){
  if(!profile) return 'portal.html';
  
  // المسؤول الأعلى
  if(profile.is_super_admin || profile.role === 'admin') return 'super-admin.html';
  
  // الأدوار التخصصية
  const r = profile.role;
  if(r === 'parent') return 'parent.html';
  if(r === 'teacher') return 'teacher.html';
  if(r === 'student') return 'student.html';
  if(r === 'counselor' || r === 'psychologist') return 'counselor.html';
  
  // باقي الأدوار (finance, discipline, academic, supervisor...) → البوابة الموحدة
  return 'portal.html';
}

function setFieldError(id,msg){const input=$('#'+id),err=$('#'+id+'Error');if(input)input.setAttribute('aria-invalid',msg?'true':'false');if(err)err.textContent=msg||''}
function clearLoginErrors(){setFieldError('username','');setFieldError('password','')}
function failedAttempts(){return Number(localStorage.getItem('amin_login_failed_attempts')||0)}
function setFailedAttempts(n){localStorage.setItem('amin_login_failed_attempts',String(n));const box=$('#attemptsBox');if(box){if(n>=3){box.classList.add('show');box.textContent=`تم تسجيل ${n} محاولات غير ناجحة. تأكدي من البيانات أو استخدمي استعادة كلمة المرور.`}else{box.classList.remove('show');box.textContent=''}}}
async function login(ev){
  if(ev&&ev.preventDefault)ev.preventDefault();
  clearLoginErrors();
  const u=$('#username')?.value.trim()||''; const p=$('#password')?.value||'';
  let ok=true;
  if(!u){setFieldError('username','يرجى إدخال اسم المستخدم أو البريد الإلكتروني');ok=false}
  if(!p){setFieldError('password','يرجى إدخال كلمة المرور');ok=false}
  if(!ok)return;
  const btn=$('#loginBtn'); if(btn){btn.disabled=true;btn.classList.add('loading')}
  try{
    const email = u.includes('@') ? u : `${u}@ameen.iq`;
    const {data,error}=await client().auth.signInWithPassword({email,password:p});
    if(error) throw error;
    const {data:profile,error:pe}=await client().from('users').select('*').eq('id',data.user.id).maybeSingle();
    if(pe || !profile) throw new Error('الحساب غير موجود في جدول users');
    setFailedAttempts(0);
    location.href = routeFor(profile);
  }catch(e){ const n=failedAttempts()+1; setFailedAttempts(n); toast('فشل الدخول', e.message || 'تحققي من البيانات','red'); setFieldError('password','اسم المستخدم أو كلمة المرور غير صحيحة'); }
  finally{if(btn){btn.disabled=false;btn.classList.remove('loading')}}
}

async function logout(){ await client().auth.signOut({scope:'local'}).catch(()=>{}); location.href='index.html'; }

function accessPolicy(role=ME && ME.role){
  const admin = ME && (ME.is_super_admin || role==='admin');
  return {
    admin,
    finance: admin || isFinanceRole(role),
    attendance: admin || isDisciplineRole(role) || isCounselorRole(role) || isAcademicRole(role) || role==='teacher' || role==='student' || role==='parent',
    behavior: admin || isDisciplineRole(role) || isCounselorRole(role) || isAcademicRole(role) || role==='teacher' || role==='student' || role==='parent',
    grades: admin || isAcademicRole(role) || isCounselorRole(role) || role==='teacher' || role==='student' || role==='parent',
    schedule: admin || isAcademicRole(role) || role==='teacher' || role==='student' || role==='parent',
    users: admin,
    students: true
  };
}

async function loadData(){
  const access = accessPolicy();
  const role = ME && ME.role;

  const [classes, subjects, periods, stages] = await Promise.all([
    q('classes',{order:'name'}),
    q('subjects',{order:'name'}),
    q('academic_periods'),
    q('stages')
  ]);

  let studentFilters=[];
  if(role==='parent') studentFilters.push({op:'eq',col:'parent_id',val:ME.id});
  if(role==='student') studentFilters.push({op:'eq',col:'user_id',val:ME.id});

  let schedule = [];
  if(access.schedule){
    const scheduleFilters = role==='teacher' ? [{op:'eq',col:'teacher_id',val:ME.id}] : [];
    schedule = await q('weekly_schedule',{filters:scheduleFilters});
  }

  let students = await q('students',{order:'name',filters:studentFilters});

  if(role==='teacher' && schedule.length){
    const teacherClassIds = new Set(schedule.map(x=>String(x.class_id)).filter(Boolean));
    if(teacherClassIds.size) students = students.filter(s=>teacherClassIds.has(String(s.class_id)));
  }

  const studentIds = new Set(students.map(s=>String(s.id)));

  let users=[];
  if(access.users) users = await q('users',{columns:'id,name,email,role,is_super_admin',order:'name'});
  else users = ME ? [{id:ME.id,name:ME.name,email:ME.email,role:ME.role,is_super_admin:ME.is_super_admin}] : [];

  let fees=[], installments=[], payments=[];
  if(access.finance || role==='student' || role==='parent'){
    fees = await q('student_fees');
    if(!access.admin && studentIds.size) fees = fees.filter(f=>studentIds.has(String(f.student_id)));
    const feeIds = new Set(fees.map(f=>String(f.id)));
    installments = await q('student_installments',{order:'installment_month'});
    payments = await q('fee_payments',{order:'created_at',ascending:false});
    if(!access.admin){
      installments = installments.filter(i=>feeIds.has(String(i.student_fee_id)));
      payments = payments.filter(p=>feeIds.has(String(p.student_fee_id)) || installments.some(i=>String(i.id)===String(p.student_installment_id)));
    }
  }

  let attendance=[];
  if(access.attendance){
    attendance = await q('attendance',{order:'date',ascending:false});
    if(!access.admin && studentIds.size) attendance = attendance.filter(a=>studentIds.has(String(a.student_id)));
  }

  let behaviorTypes=[], behaviorRecords=[];
  if(access.behavior){
    behaviorTypes = await q('behavior_types',{order:'name'});
    behaviorRecords = await q('behavior_records',{order:'created_at',ascending:false});
    if(!access.admin && studentIds.size) behaviorRecords = behaviorRecords.filter(r=>studentIds.has(String(r.student_id)));
  }

  let grades=[], exemptions=[];
  if(access.grades){
    grades = await q('grades');
    exemptions = await q('exemptions');
    if(!access.admin && studentIds.size){
      grades = grades.filter(g=>studentIds.has(String(g.student_id)));
      exemptions = exemptions.filter(e=>studentIds.has(String(e.student_id)));
    }
  }

  let notifications=[], achievements=[], studentHomeworks=[], onlineExams=[];
  notifications = await q('school_notifications',{filters:[{op:'eq',col:'recipient_user_id',val:ME.id}],order:'created_at',ascending:false,limit:20});
  achievements = await q('v_achievement_awards_detailed',{order:'awarded_at',ascending:false,limit:80});
  if(access.homework || role==='student' || role==='parent') studentHomeworks = await q('v_student_homeworks',{order:'due_date',ascending:true,limit:80});
  if(access.online_exams || role==='student' || role==='parent' || role==='teacher') onlineExams = await q('online_exams',{order:'start_at',ascending:true,limit:80});

  const classMap=new Map(classes.map(x=>[String(x.id),x]));
  const studentMap=new Map(students.map(x=>[String(x.id),x]));
  const subjectMap=new Map(subjects.map(x=>[String(x.id),x]));
  const userMap=new Map(users.map(x=>[String(x.id),x]));
  DATA={classes,students,users,subjects,fees,installments,payments,attendance,behaviorTypes,behaviorRecords,grades,exemptions,periods,schedule,stages,notifications,achievements,studentHomeworks,onlineExams,classMap,studentMap,subjectMap,userMap,access};
  return DATA;
}

function metrics(scopeStudents){
  const students = scopeStudents || DATA.students;
  const ids = new Set(students.map(s=>String(s.id)));
  const fees = DATA.fees.filter(f=>ids.has(String(f.student_id)));
  const total=fees.reduce((a,f)=>a+num(f.net_amount||f.base_amount),0);
  const paid=fees.reduce((a,f)=>a+num(f.total_paid),0);
  const today=iso();
  const todayAtt=DATA.attendance.filter(a=>String(a.date).slice(0,10)===today && ids.has(String(a.student_id)));
  const present=todayAtt.filter(a=>['present','حاضر'].includes(String(a.status))).length;
  const gradeVals=DATA.grades.filter(g=>ids.has(String(g.student_id))).map(g=>num(g.score??g.grade??g.mark)).filter(Boolean);
  return {students:students.length, classes:DATA.classes.length, users:DATA.users.length, total, paid, remaining:Math.max(total-paid,0), attendanceRate:todayAtt.length?Math.round(present/todayAtt.length*100):0, gradesAvg:gradeVals.length?Math.round(gradeVals.reduce((a,b)=>a+b,0)/gradeVals.length):0, behavior:DATA.behaviorRecords.length, exemptions:DATA.exemptions.filter(e=>e.is_active!==false).length};
}

function kpi(label,value,color='gold',sub=''){return `<div class="kpi ${color}"><small>${esc(label)}</small><b>${esc(value)}</b>${sub?`<div class="muted">${esc(sub)}</div>`:''}</div>`}
function progress(done,total){const p=total?Math.round(num(done)/num(total)*100):0;return `<div class="progress"><span style="width:${pct(p)}%"></span></div><small class="muted">${pct(p)}%</small>`}
function table(headers, rows, empty='لا توجد بيانات'){
  const body = Array.isArray(rows) ? rows.join('') : String(rows || '');
  if(!body.trim()) return `<div class="empty">${esc(empty)}</div>`;
  return `<div class="table-wrap"><table><thead><tr>${headers.map(h=>`<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>`;
}
function studentRows(students){
  return students.map(s=>{const fee=DATA.fees.find(f=>String(f.student_id)===String(s.id)); const net=num(fee&& (fee.net_amount||fee.base_amount)); const paid=num(fee&&fee.total_paid); const att=DATA.attendance.filter(a=>String(a.student_id)===String(s.id)); const pres=att.filter(a=>['present','حاضر'].includes(String(a.status))).length; return `<tr><td><b>${esc(fullName(s))}</b><br><span class="badge">${esc(s.id).slice(0,8)}</span></td><td>${esc(className(s.class_id))}</td><td>${esc(s.gender||'—')}</td><td>${att.length?Math.round(pres/att.length*100)+'%':'—'}</td><td>${money(paid)} / ${money(net)}</td><td>${progress(paid,net)}</td></tr>`}).join('');
}
function feeRows(students){const ids=new Set(students.map(s=>String(s.id))); return DATA.fees.filter(f=>ids.has(String(f.student_id))).map(f=>{const net=num(f.net_amount||f.base_amount); const paid=num(f.total_paid); return `<tr><td>${esc(studentName(f.student_id))}</td><td>${money(net)}</td><td>${money(paid)}</td><td>${money(net-paid)}</td><td>${progress(paid,net)}</td><td><span class="badge ${paid>=net?'green':paid>0?'gold':'red'}">${paid>=net?'مدفوع':'جزئي/معلق'}</span></td></tr>`}).join('')}
function academicStudentRows(students){return students.map(s=>{const att=DATA.attendance.filter(a=>String(a.student_id)===String(s.id)); const pres=att.filter(a=>['present','حاضر'].includes(String(a.status))).length; const today=DATA.attendance.find(a=>String(a.student_id)===String(s.id)&&String(a.date).slice(0,10)===iso()); const last=DATA.behaviorRecords.find(r=>String(r.student_id)===String(s.id)); return `<tr><td><b>${esc(fullName(s))}</b></td><td>${esc(className(s.class_id))}</td><td>${esc(s.gender||'—')}</td><td>${att.length?Math.round(pres/att.length*100)+'%':'—'}</td><td><span class="badge ${today&&today.status==='absent'?'red':today&&today.status==='late'?'gold':'green'}">${esc((today&&today.status)||'—')}</span></td><td>${esc((last&& (last.note||last.description)) || '—')}</td></tr>`}).join('')}
function attendanceRows(students){const today=iso(); return students.map(s=>{const rec=DATA.attendance.find(a=>String(a.student_id)===String(s.id)&&String(a.date).slice(0,10)===today); const status=rec?rec.status:'—'; return `<tr><td>${esc(fullName(s))}</td><td>${esc(className(s.class_id))}</td><td><span class="badge ${status==='present'?'green':status==='absent'?'red':'gold'}">${esc(status)}</span></td><td>${esc((rec&&rec.note)||'—')}</td></tr>`}).join('')}
function gradeRows(students){const ids=new Set(students.map(s=>String(s.id))); return DATA.grades.filter(g=>ids.has(String(g.student_id))).map(g=>`<tr><td>${esc(studentName(g.student_id))}</td><td>${esc(subjectName(g.subject_id))}</td><td><span class="badge ${num(g.score??g.grade)>=85?'green':num(g.score??g.grade)>=60?'gold':'red'}">${esc(g.score??g.grade??g.mark??'—')}</span></td><td>${esc(g.notes||g.note||'—')}</td></tr>`).join('')}
function scheduleRows(filter={}){return DATA.schedule.filter(x=>(!filter.teacher || String(x.teacher_id)===String(filter.teacher)) && (!filter.classId || String(x.class_id)===String(filter.classId))).map(x=>`<tr><td>${esc(DAYS[num(x.day)]||x.day_name||x.day||'—')}</td><td>${esc(x.period_number||x.period_no||'—')}</td><td>${esc(className(x.class_id))}</td><td>${esc(subjectName(x.subject_id))}</td><td>${esc((DATA.userMap.get(String(x.teacher_id))||{}).name||x.teacher_name||'—')}</td></tr>`).join('')}

function isFinanceRole(role=ME && ME.role){return role==='finance'}
function isDisciplineRole(role=ME && ME.role){return role==='discipline'}
function isCounselorRole(role=ME && ME.role){return ['counselor','psychologist'].includes(role)}
function isAcademicRole(role=ME && ME.role){return ['academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor'].includes(role)}
function staffScope(){
  const r=ME.role;
  if(isFinanceRole(r)) return {title:'واجهة المسؤول المالي', focus:'finance'};
  if(isDisciplineRole(r)) return {title:'واجهة مسؤول الانضباط', focus:'discipline'};
  if(isCounselorRole(r)) return {title:'واجهة المرشد النفسي', focus:'counselor'};
  if(isAcademicRole(r)) return {title:'واجهة المسؤول العلمي', focus:'academic'};
  return {title:'واجهة الإدارة التشغيلية', focus:'ops'};
}
function allowedStaffViews(){
  const r=ME.role;
  if(isFinanceRole(r)) return ['overview','finance','reports'];
  if(isDisciplineRole(r)) return ['overview','attendance','counseling','students','reports'];
  if(isCounselorRole(r)) return ['overview','counseling','students','attendance','reports'];
  if(isAcademicRole(r)) return ['overview','students','attendance','evaluation','counseling','reports'];
  return ['overview','finance','attendance','counseling','students','evaluation','reports'];
}
function configureStaffNav(){
  if(document.body.dataset.portal!=='staff') return;
  const allowed = new Set(allowedStaffViews());
  $$('.nav button[data-view]').forEach(btn=>{
    const ok = allowed.has(btn.dataset.view);
    btn.style.display = ok ? '' : 'none';
    btn.disabled = !ok;
  });
  $$('.academic-only-link').forEach(el=>{
    const ok = isAcademicRole(ME.role) || ME.role==='admin' || ME.is_super_admin;
    el.style.display = ok ? '' : 'none';
  });
  $$('.finance-only-link').forEach(el=>{
    const ok = isFinanceRole(ME.role) || ME.role==='admin' || ME.is_super_admin;
    el.style.display = ok ? '' : 'none';
  });
  const title=$('.topbar h2'); if(title) title.textContent = staffScope().title;
}

const SIDE_ICONS={
  home:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 10.5 12 3l9 7.5V21a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1V10.5Z"/></svg>',
  academic:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 6l9-4 9 4-9 4-9-4Z"/><path d="M7 10v5c0 2 2 4 5 4s5-2 5-4v-5"/></svg>',
  finance:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="6" width="18" height="12" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M6 12h.01M18 12h.01"/></svg>',
  attendance:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>',
  users:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/></svg>',
  reports:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 3v18h18"/><rect x="7" y="12" width="3" height="5"/><rect x="12" y="8" width="3" height="9"/><rect x="17" y="5" width="3" height="12"/></svg>',
  forms:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z"/><path d="M14 2v6h6"/><path d="M8 13h8M8 17h5"/></svg>',
  links:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>'
};
function currentPortal(){return document.body.dataset.portal||''}
function canSeeGroup(key){
  const r=ME&&ME.role;
  const admin=ME&&(ME.is_super_admin||r==='admin');
  if(admin)return true;
  if(key==='finance')return isFinanceRole(r);
  if(key==='users')return false;
  if(key==='forms')return isAcademicRole(r);
  if(key==='links')return false;
  if(key==='academic')return true;
  if(key==='attendance')return ['discipline','teacher','student','parent'].includes(r)||isCounselorRole(r)||isAcademicRole(r);
  if(key==='reports')return true;
  return true;
}
function viewExists(v){return !!document.getElementById('view-'+v)}
function filterItem(item){
  const r=ME&&ME.role, admin=ME&&(ME.is_super_admin||r==='admin');
  if(item.adminOnly&&!admin)return false;
  if(item.financeOnly&&!(admin||isFinanceRole(r)))return false;
  if(item.academicOnly&&!(admin||isAcademicRole(r)))return false;
  if(item.roles&&!item.roles.includes(r)&&!admin)return false;
  if(item.view&&!viewExists(item.view))return false;
  return true;
}
function sidebarGroups(){return [
  {key:'home',icon:'home',label:'الرئيسية',items:[{label:'البوابة الموحدة',href:'portal.html'},{label:'لوحة البداية',view:'overview'}]},
  {key:'academic',icon:'academic',label:'الطلاب والشؤون الأكاديمية',items:[{label:'الطلاب',view:'students'},{label:'الأكاديمية والجداول',view:'academics'},{label:'إدارة الجدول المدرسي',href:'schedule-management.html',academicOnly:true},{label:'النظام الأكاديمي الاحترافي',href:'academic-pro.html',roles:['admin','academic','academic_admin','scientific','teacher']},{label:'بنك الأسئلة والاختبارات',href:'teacher-exams.html',roles:['teacher']},{label:'كشف نزاهة الاختبارات',href:'exam-integrity.html',roles:['admin','teacher','academic','academic_admin','scientific','supervisor']},{label:'التقييم والإعفاءات',view:'evaluation'},{label:'الاختبارات الإلكترونية',href:'online-exams.html',roles:['student','parent']}]},
  {key:'finance',icon:'finance',label:'المالية',items:[{label:'المالية المختصرة',view:'finance'},{label:'النظام المالي الاحترافي',href:'finance-pro.html',financeOnly:true},{label:'أجور المعلمات ورسوم الصفوف',href:'admin-finance-rules.html',adminOnly:true}]},
  {key:'attendance',icon:'attendance',label:'الحضور والسلوك',items:[{label:'الحضور',view:'attendance'},{label:'الانضباط والسلوك',view:'behavior'},{label:'الإرشاد والمتابعة',view:'counseling'}]},
  {key:'users',icon:'users',label:'المستخدمون والصلاحيات',items:[{label:'إدارة المستخدمين',view:'users',adminOnly:true}]},
  {key:'reports',icon:'reports',label:'التقارير',items:[{label:'مركز التقارير',view:'reports'},{label:'تقارير الواجبات',href:'homework-reports.html',roles:['admin','teacher','academic','academic_admin','scientific','supervisor']},{label:'سجل الواجبات',href:'homework-audit.html',roles:['admin','teacher','academic','academic_admin','scientific','supervisor']},{label:'صحة النظام والتنظيف',href:'system-maintenance.html',adminOnly:true}]},
  {key:'forms',icon:'forms',label:'نماذج التسجيل',items:[{label:'تسجيل ولي أمر/طالب',href:'family-registration.html'},{label:'تسجيل معلم',href:'teacher-registration.html'},{label:'مراجعة الطلبات',href:'registrations-admin.html',academicOnly:true}]}
]}
function buildRoleSidebar(){
  const nav=$('.nav'); if(!nav||!ME)return;
  const groups=sidebarGroups().filter(g=>canSeeGroup(g.key)).map(g=>Object.assign({},g,{items:g.items.filter(filterItem)})).filter(g=>g.items.length);
  nav.innerHTML=`<div class="side-search"><input id="sidebarSearch" type="search" placeholder="بحث سريع في القائمة..." aria-label="بحث في القائمة"></div><div class="side-grid" id="sideGrid">${groups.map((g,i)=>`<button class="nav-group-card" type="button" aria-expanded="${i===0?'true':'false'}" data-group="${g.key}"><span class="icon-badge">${SIDE_ICONS[g.icon]}</span><span class="nav-group-title">${esc(g.label)}</span></button><div class="nav-children ${i===0?'open':''}" data-children="${g.key}">${g.items.map(it=>`<button class="nav-child-btn" type="button" ${it.view?`data-view="${it.view}"`:''} ${it.href?`data-href="${it.href}"`:''}>${esc(it.label)}</button>`).join('')}</div>`).join('')}</div>`;
  $$('.nav-group-card',nav).forEach(btn=>btn.addEventListener('click',()=>{const key=btn.dataset.group;const open=btn.getAttribute('aria-expanded')==='true';$$('.nav-group-card',nav).forEach(b=>b.setAttribute('aria-expanded','false'));$$('.nav-children',nav).forEach(c=>c.classList.remove('open'));if(!open){btn.setAttribute('aria-expanded','true');$(`[data-children="${key}"]`,nav)?.classList.add('open')}}));
  $$('.nav-child-btn',nav).forEach(btn=>btn.addEventListener('click',()=>{if(btn.dataset.view)showView(btn.dataset.view);else if(btn.dataset.href)location.href=btn.dataset.href}));
  $('#sidebarSearch')?.addEventListener('input',e=>{const q=String(e.target.value||'').trim().toLowerCase();let hits=0;$$('.nav-group-card',nav).forEach(card=>{const key=card.dataset.group;const child=$(`[data-children="${key}"]`,nav);const text=(card.textContent+' '+(child?child.textContent:'')).toLowerCase();const ok=!q||text.includes(q);card.style.display=ok?'':'none';if(child)child.style.display=ok?'':'none';if(ok)hits++});if(!hits&&!$('.nav-empty',nav))$('#sideGrid').insertAdjacentHTML('beforeend','<div class="nav-empty">لا توجد نتائج</div>');if(hits){$('.nav-empty',nav)?.remove()}});
  if(!document.getElementById('sidebarBackdrop')){document.body.insertAdjacentHTML('beforeend','<div class="sidebar-backdrop" id="sidebarBackdrop" aria-hidden="true"></div>');$('#sidebarBackdrop').addEventListener('click',()=>{$('#sidebar')?.classList.remove('open');$('#sidebarBackdrop').classList.remove('show')})}
}
function layoutReady(){
  $('#profileName').textContent = ME.name || ME.email || 'مستخدم';
  $('#profileRole').textContent = roleLabel(ME.role) + (ME.is_super_admin?' · مسؤول أعلى':'');
  $('#logoutBtn').onclick = logout;
  buildRoleSidebar();
  configureStaffNav();
  $('#mobileMenuBtn')?.addEventListener('click',()=>{$('#sidebar').classList.toggle('open');$('#sidebarBackdrop')?.classList.toggle('show',$('#sidebar').classList.contains('open'))});
}
function showView(id){ACTIVE_VIEW=id; $$('.view').forEach(v=>v.classList.toggle('active',v.id==='view-'+id)); $$('.nav button[data-view], .nav-child-btn[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view===id)); renderView(id); $('#sidebar')?.classList.remove('open');$('#sidebarBackdrop')?.classList.remove('show');}

function renderView(id){
  const portal=document.body.dataset.portal;
  if(portal==='super') return renderSuper(id);
  if(portal==='staff') return renderStaff(id);
  if(portal==='teacher') return renderTeacher(id);
  if(portal==='student') return renderStudentPortal(id);
}

function renderSuper(id){
  const root=$('#view-'+id); if(!root)return; const m=metrics();
  if(id==='overview') root.innerHTML=`<div class="page-head"><div><h1>واجهة المسؤول الأعلى</h1><p>رؤية شاملة لكل أقسام المدرسة دون تكرار التبويبات.</p></div></div><div class="kpis">${kpi('الطلاب',ar(m.students),'gold')}${kpi('المستخدمون',ar(m.users),'blue')}${kpi('المحصّل',money(m.paid),'green')}${kpi('المتبقي',money(m.remaining),'red')}</div><div class="cards"><div class="card"><div class="card-head"><h3>آخر الطلاب</h3></div><div class="card-body">${table(['الطالب','الصف','الجنس','الحضور','المالية','التقدم'],studentRows(DATA.students.slice(0,8)))}</div></div><div class="card"><div class="card-head"><h3>مؤشرات ذكية</h3></div><div class="card-body"><div class="list"><div class="item"><b>متوسط الدرجات</b><span class="badge gold">${m.gradesAvg}%</span></div><div class="item"><b>الحضور اليوم</b><span class="badge blue">${m.attendanceRate}%</span></div><div class="item"><b>الإعفاءات النشطة</b><span class="badge green">${ar(m.exemptions)}</span></div></div></div></div></div>`;
  if(id==='students') root.innerHTML=`<div class="page-head"><div><h1>إدارة الطلاب</h1><p>عرض موحد للطلاب والصفوف والحضور والمالية.</p></div></div>${table(['الطالب','الصف','الجنس','الحضور','المالية','التقدم'],studentRows(DATA.students))}`;
  if(id==='finance') root.innerHTML=`<div class="page-head"><div><h1>المالية</h1><p>رسوم، أقساط، مدفوعات، ومتبقيات.</p></div></div><div class="kpis">${kpi('إجمالي الرسوم',money(m.total),'gold')}${kpi('المحصّل',money(m.paid),'green')}${kpi('المتبقي',money(m.remaining),'red')}${kpi('عمليات الدفع',ar(DATA.payments.length),'blue')}</div>${table(['الطالب','الصافي','المدفوع','المتبقي','التقدم','الحالة'],feeRows(DATA.students))}`;
  if(id==='attendance') root.innerHTML=`<div class="page-head"><div><h1>الحضور</h1><p>قراءة حضور اليوم وسجل الطلاب.</p></div></div>${attendanceTools(DATA.students)}${table(['الطالب','الصف','الحالة اليوم','ملاحظة'],attendanceRows(DATA.students))}`;
  if(id==='behavior') root.innerHTML=`<div class="page-head"><div><h1>الانضباط والإرشاد</h1><p>سلوك الطلاب ومؤشرات المتابعة النفسية.</p></div></div>${behaviorPanel()}`;
  if(id==='evaluation') root.innerHTML=`<div class="page-head"><div><h1>التقييم والإعفاءات</h1><p>درجات وإعفاءات مرتبطة بالطلاب والمواد.</p></div></div><div class="kpis">${kpi('الدرجات',ar(DATA.grades.length),'blue')}${kpi('متوسط عام',m.gradesAvg+'%','gold')}${kpi('إعفاءات',ar(m.exemptions),'green')}${kpi('مواد',ar(DATA.subjects.length),'blue')}</div>${table(['الطالب','المادة','الدرجة','ملاحظة'],gradeRows(DATA.students))}`;
  if(id==='academics') root.innerHTML=`<div class="page-head"><div><h1>الأكاديمية والجداول</h1><p>صفوف، مواد، وجدول أسبوعي.</p></div></div><div class="kpis">${kpi('الصفوف',ar(DATA.classes.length),'gold')}${kpi('المواد',ar(DATA.subjects.length),'blue')}${kpi('حصص الجدول',ar(DATA.schedule.length),'green')}${kpi('فترات',ar(DATA.periods.length),'blue')}</div>${table(['اليوم','الحصة','الصف','المادة','المعلم'],scheduleRows())}`;
  if(id==='users') root.innerHTML=`<div class="page-head"><div><h1>المستخدمون والصلاحيات</h1><p>إدارة أدوار النظام.</p></div></div>${table(['الاسم','البريد','الدور','مسؤول أعلى'],DATA.users.map(u=>`<tr><td>${esc(u.name||'—')}</td><td>${esc(u.email||'—')}</td><td><span class="badge gold">${esc(roleLabel(u.role))}</span></td><td>${u.is_super_admin?'نعم':'—'}</td></tr>`))}`;
  if(id==='reports') root.innerHTML=`<div class="page-head"><div><h1>التقارير</h1><p>مركز تقارير مختصر ومنظم بدون فراغات كبيرة.</p></div></div><div class="report-grid"><article class="report-card"><h3>التقرير المالي</h3><p>المحصّل: ${money(m.paid)} · المتبقي: ${money(m.remaining)}</p></article><article class="report-card"><h3>التقرير الأكاديمي</h3><p>متوسط الدرجات: ${m.gradesAvg}% · الطلاب: ${ar(m.students)}</p></article><article class="report-card"><h3>الحضور والسلوك</h3><p>حضور اليوم: ${m.attendanceRate}% · سجلات السلوك: ${ar(DATA.behaviorRecords.length)}</p></article><article class="report-card"><h3>الرسوم والإعفاءات</h3><p>إعفاءات نشطة: ${ar(m.exemptions)} · مدفوعات: ${ar(DATA.payments.length)}</p></article></div>`;
}

function renderStaff(id){
  const root=$('#view-'+id); if(!root)return; const s=staffScope(); const m=metrics(); const allowed=new Set(allowedStaffViews());
  const quick = allowedStaffViews().filter(v=>v!=='overview').map(v=>{
    const labels={finance:'💰 المالية',attendance:'📋 الحضور والانضباط',counseling:'🧠 الإرشاد والمتابعة',students:'🎓 الطلاب',evaluation:'📊 العلمي والتقييم',reports:'📈 التقارير'};
    return `<button class="btn ${v==='finance'?'gold':v==='attendance'?'blue':v==='counseling'?'green':'blue'}" onclick="showView('${v}')">${labels[v]||v}</button>`;
  }).join('');
  if(id==='overview') root.innerHTML=`<div class="page-head"><div><h1>${esc(s.title)}</h1><p>${s.focus==='finance'?'مساحة مالية فقط، بدون صلاحيات سلوك أو حضور.':s.focus==='discipline'?'مساحة انضباط وحضور فقط، بدون أمور مالية.':s.focus==='academic'?'مساحة علمية لمتابعة الدرجات والحضور والسلوك بدون مالية.':s.focus==='counselor'?'مساحة إرشاد نفسي ومتابعة الطلاب بدون مالية.':'واجهة تشغيلية حسب الدور.'}</p></div></div><div class="kpis">${allowed.has('finance')?kpi('المحصّل',money(m.paid),'green'):kpi('الطلاب',ar(m.students),'gold')}${allowed.has('finance')?kpi('المتبقي',money(m.remaining),'red'):kpi('حضور اليوم',m.attendanceRate+'%','blue')}${allowed.has('evaluation')?kpi('متوسط الدرجات',m.gradesAvg+'%','gold'):kpi('سلوك/متابعة',ar(DATA.behaviorRecords.length),'red')}${kpi('تقارير', 'جاهزة','blue')}</div><div class="cards"><div class="card"><div class="card-head"><h3>مهامي حسب الدور</h3></div><div class="card-body"><div class="list">${quick}</div></div></div><div class="card"><div class="card-head"><h3>تنبيهات مسموحة</h3></div><div class="card-body">${alertsList(allowed)}</div></div></div>`;
  if(id==='finance'){
    if(!allowed.has('finance')){root.innerHTML='<div class="empty">ليس لديك صلاحية مالية.</div>';return;}
    root.innerHTML=`<div class="page-head"><div><h1>المالية</h1><p>مخصصة للمسؤول المالي فقط.</p></div></div><div class="kpis">${kpi('إجمالي',money(m.total),'gold')}${kpi('محصل',money(m.paid),'green')}${kpi('متبقي',money(m.remaining),'red')}${kpi('مدفوعات',ar(DATA.payments.length),'blue')}</div>${table(['الطالب','الصافي','المدفوع','المتبقي','التقدم','الحالة'],feeRows(DATA.students))}`;
  }
  if(id==='attendance'){
    if(!allowed.has('attendance')){root.innerHTML='<div class="empty">ليس لديك صلاحية الحضور.</div>';return;}
    root.innerHTML=`<div class="page-head"><div><h1>الحضور والانضباط</h1><p>تحميل وحفظ الحضور اليومي ومتابعة الغياب.</p></div></div>${attendanceTools(DATA.students)}${table(['الطالب','الصف','الحالة اليوم','ملاحظة'],attendanceRows(DATA.students))}`;
  }
  if(id==='counseling'){
    if(!allowed.has('counseling')){root.innerHTML='<div class="empty">ليس لديك صلاحية الإرشاد أو السلوك.</div>';return;}
    root.innerHTML=`<div class="page-head"><div><h1>${s.focus==='academic'?'السلوك والحضور للمتابعة العلمية':'الإرشاد النفسي والمتابعة'}</h1><p>مؤشرات من الغياب والسلوك والدرجات، بدون معلومات مالية.</p></div></div>${behaviorPanel()}`;
  }
  if(id==='students'){
    if(!allowed.has('students')){root.innerHTML='<div class="empty">ليس لديك صلاحية الطلاب.</div>';return;}
    root.innerHTML=`<div class="page-head"><div><h1>الطلاب</h1><p>عرض أكاديمي/سلوكي بدون أعمدة مالية لهذا الدور.</p></div></div>${table(['الطالب','الصف','الجنس','الحضور','الحالة اليوم','آخر ملاحظة'],academicStudentRows(DATA.students))}`;
  }
  if(id==='evaluation'){
    if(!allowed.has('evaluation')){root.innerHTML='<div class="empty">هذه الصفحة للمسؤول العلمي فقط.</div>';return;}
    root.innerHTML=`<div class="page-head"><div><h1>المتابعة العلمية والتقييم</h1><p>درجات الطلاب، الحضور، السلوك، والإعفاءات — بدون أي بيانات مالية.</p></div></div><div class="kpis">${kpi('الدرجات',ar(DATA.grades.length),'blue')}${kpi('متوسط عام',m.gradesAvg+'%','gold')}${kpi('إعفاءات',ar(m.exemptions),'green')}${kpi('غيابات',ar(DATA.attendance.filter(a=>a.status==='absent').length),'red')}</div>${table(['الطالب','المادة','الدرجة','ملاحظة'],gradeRows(DATA.students))}`;
  }
  if(id==='reports') root.innerHTML=`<div class="page-head"><div><h1>تقارير القسم</h1><p>تظهر التقارير حسب صلاحيتك فقط.</p></div></div><div class="report-grid"><article class="report-card"><h3>ملخص الصلاحية</h3><p>${s.focus==='finance'?'تقرير مالي مختصر فقط.':s.focus==='academic'?'تقرير علمي: درجات، حضور، سلوك.':'تقرير متابعة بدون مالية.'}</p></article><article class="report-card"><h3>الطلاب</h3><p>${ar(m.students)} طالب ضمن نطاق العرض.</p></article><article class="report-card"><h3>الحضور</h3><p>${m.attendanceRate}% حضور اليوم.</p></article></div>`;
}

function renderTeacher(id){
  const root=$('#view-'+id); if(!root)return; const teacherSchedule=DATA.schedule.filter(x=>String(x.teacher_id)===String(ME.id)); const classIds=[...new Set(teacherSchedule.map(x=>String(x.class_id)).filter(Boolean))]; let students=DATA.students.filter(s=>classIds.includes(String(s.class_id))); if(!students.length) students=DATA.students;
  const m=metrics(students);
  if(id==='overview') root.innerHTML=`<div class="page-head"><div><h1>واجهة المعلم</h1><p>طلابي، حضوري، جدولي، وتقييماتي في مكان واحد.</p></div></div><div class="kpis">${kpi('طلابي',ar(students.length),'gold')}${kpi('حصصي',ar(teacherSchedule.length),'blue')}${kpi('حضور اليوم',m.attendanceRate+'%','green')}${kpi('متوسط الدرجات',m.gradesAvg+'%','gold')}</div><div class="cards"><div class="card"><div class="card-head"><h3>جدولي</h3></div><div class="card-body">${table(['اليوم','الحصة','الصف','المادة','المعلم'],scheduleRows({teacher:ME.id}))}</div></div><div class="card"><div class="card-head"><h3>طلابي</h3></div><div class="card-body">${table(['الطالب','الصف','الجنس','الحضور','الحالة اليوم','آخر ملاحظة'],academicStudentRows(students.slice(0,8)))}</div></div></div>`;
  if(id==='students') root.innerHTML=`<div class="page-head"><div><h1>طلابي</h1></div></div>${table(['الطالب','الصف','الجنس','الحضور','الحالة اليوم','آخر ملاحظة'],academicStudentRows(students))}`;
  if(id==='attendance') root.innerHTML=`<div class="page-head"><div><h1>حضور طلابي</h1><p>يمكن حفظ الحضور اليومي للطلاب المعروضين.</p></div></div>${attendanceTools(students)}${table(['الطالب','الصف','الحالة اليوم','ملاحظة'],attendanceRows(students))}`;
  if(id==='grades') root.innerHTML=`<div class="page-head"><div><h1>درجات طلابي</h1></div></div>${table(['الطالب','المادة','الدرجة','ملاحظة'],gradeRows(students))}`;
  if(id==='schedule') root.innerHTML=`<div class="page-head"><div><h1>جدولي الأسبوعي</h1></div></div>${table(['اليوم','الحصة','الصف','المادة','المعلم'],scheduleRows({teacher:ME.id}))}`;
  if(id==='behavior') root.innerHTML=`<div class="page-head"><div><h1>ملاحظات السلوك</h1></div></div>${behaviorPanel(students)}`;
}

function scopedStudentList(){
  if(ME.role==='parent') return DATA.students.filter(s=>String(s.parent_id)===String(ME.id));
  let own=DATA.students.filter(s=>String(s.user_id)===String(ME.id));
  if(!own.length && DATA.students.length) own=[DATA.students[0]];
  return own;
}
function renderStudentPortal(id){
  const root=$('#view-'+id); if(!root)return; const students=scopedStudentList(); if(!CURRENT_STUDENT_ID && students.length) CURRENT_STUDENT_ID=students[0].id; const selected=DATA.studentMap.get(String(CURRENT_STUDENT_ID))||students[0]; const one=selected?[selected]:[]; const m=metrics(one);
  const switcher=students.length>1?`<select class="select" onchange="CURRENT_STUDENT_ID=this.value;renderView(ACTIVE_VIEW)">${students.map(s=>`<option value="${s.id}" ${String(s.id)===String(CURRENT_STUDENT_ID)?'selected':''}>${esc(fullName(s))}</option>`).join('')}</select>`:'';
  if(id==='overview') root.innerHTML=`<div class="page-head student-focus-head"><div><h1>مركز الطالب اليومي</h1><p>${esc(fullName(selected))} · ${esc(className(selected&&selected.class_id))}</p></div>${switcher}<div class="form-actions"><button class="btn gold" onclick="location.href='smart-calendar.html?lite=1'">التقويم</button><button class="btn blue" onclick="location.href='achievements.html?lite=1'">الشارات</button><button class="btn green" onclick="AminPortal.requestSkillProgramAppointment()">أريد موعداً</button></div></div>${studentVitalIndicators(selected,m)}<div class="student-focus-grid"><div class="card priority-card"><div class="card-head"><h3>الأهم حسب الأولوية</h3></div><div class="card-body">${studentPriorityHub(selected)}</div></div><div class="card"><div class="card-head"><h3>التقويم القريب</h3></div><div class="card-body">${studentCalendarFocus(selected)}</div></div><div class="card"><div class="card-head"><h3>الشارات والتطور</h3></div><div class="card-body">${studentBadges(selected)}</div></div><div class="card"><div class="card-head"><h3>مؤشرات النمو</h3></div><div class="card-body">${studentGrowth(selected,m)}</div></div></div>`;
  if(id==='grades') root.innerHTML=`<div class="page-head"><div><h1>درجاتي</h1></div>${switcher}</div>${table(['الطالب','المادة','الدرجة','ملاحظة'],gradeRows(one))}`;
  if(id==='attendance') root.innerHTML=`<div class="page-head"><div><h1>حضوري</h1></div>${switcher}</div>${table(['الطالب','الصف','الحالة اليوم','ملاحظة'],attendanceRows(one))}`;
  if(id==='finance') root.innerHTML=`<div class="page-head"><div><h1>أقساطي</h1></div>${switcher}</div>${table(['الطالب','الصافي','المدفوع','المتبقي','التقدم','الحالة'],feeRows(one))}`;
  if(id==='schedule') root.innerHTML=`<div class="page-head"><div><h1>جدولي</h1></div>${switcher}</div>${table(['اليوم','الحصة','الصف','المادة','المعلم'],scheduleRows({classId:selected&&selected.class_id}))}`;
  if(id==='behavior') root.innerHTML=`<div class="page-head"><div><h1>السلوك والملاحظات</h1></div>${switcher}</div>${behaviorPanel(one)}`;
}

function dueText(d){if(!d)return'بدون موعد';const x=new Date(String(d).slice(0,10)+'T00:00:00'),t=new Date(iso()+'T00:00:00');const diff=Math.round((x-t)/86400000);if(diff<0)return 'متأخر '+Math.abs(diff)+' يوم';if(diff===0)return 'اليوم';if(diff===1)return 'غداً';return 'بعد '+diff+' يوم'}
function itemPriorityBadge(kind,d){const txt=dueText(d);const urgent=txt.includes('متأخر')||txt==='اليوم';return `<span class="badge ${urgent?'red':kind==='exam'?'gold':'blue'}">${esc(txt)}</span>`}

async function requestSkillProgramAppointment(){
  try{
    const students=scopedStudentList();
    const selected=DATA.studentMap.get(String(CURRENT_STUDENT_ID))||students[0];
    if(!selected){toast('تنبيه','لا يوجد طالب مرتبط بهذا الحساب','red');return}
    const reason=prompt('سبب اختياري للموعد ضمن برنامج تطوير المهارات والمتابعة التربوية:');
    if(reason===null)return;
    const {data,error}=await client().rpc('counseling_student_request_session',{p_student_id:selected.id,p_reason:reason||null});
    if(error)throw error;
    if(data&&data.ok===false)throw new Error(data.message||'تعذر إرسال طلب الموعد');
    toast('تم إرسال طلب الموعد',data.message||'سيتم مراجعته من المرشد','green');
  }catch(e){toast('تعذر إرسال طلب الموعد',e.message||String(e),'red')}
}

function studentVitalIndicators(st,m){return `<div class="kpis student-vitals">${kpi('تقدم الدرجات',m.gradesAvg+'%','gold')}${kpi('انتظام الحضور',m.attendanceRate+'%','green')}${kpi('شاراتي',ar((DATA.achievements||[]).filter(a=>String(a.recipient_student_id||'')===String(st&&st.id)||String(a.recipient_user_id||'')===String(st&&st.user_id)).length),'blue')}${kpi('مهام قريبة',ar(studentPriorityItems(st).length),'red')}</div>`}
function studentPriorityItems(st){if(!st)return[];const sid=String(st.id),uid=String(st.user_id||'');const items=[];(DATA.studentHomeworks||[]).filter(h=>!h.student_id||String(h.student_id)===sid).slice(0,8).forEach(h=>items.push({kind:'homework',title:h.title||h.homework_title||'واجب',date:h.due_date||h.due_at,href:'student-homeworks.html?lite=1'}));(DATA.onlineExams||[]).slice(0,8).forEach(e=>items.push({kind:'exam',title:e.title||e.exam_title||'اختبار إلكتروني',date:e.starts_at||e.start_at||e.exam_date,href:'online-exams.html?lite=1'}));(DATA.notifications||[]).filter(n=>!n.read_at).slice(0,5).forEach(n=>items.push({kind:'note',title:n.title||'إشعار',date:n.created_at,href:'notifications.html?lite=1'}));return items.sort((a,b)=>new Date(a.date||'2999-01-01')-new Date(b.date||'2999-01-01')).slice(0,8)}
function studentPriorityHub(st){const items=studentPriorityItems(st);return items.map(x=>`<div class="priority-item ${x.kind}"><div><b>${esc(x.title)}</b><small>${esc(x.kind==='exam'?'اختبار':x.kind==='homework'?'واجب':'إشعار')}</small></div>${itemPriorityBadge(x.kind,x.date)}<button class="btn small" onclick="location.href='${esc(x.href)}'">فتح</button></div>`).join('')||'<div class="empty">لا توجد مهام عاجلة الآن. راجع التقويم للاستعداد المسبق.</div>'}
function studentCalendarFocus(st){const rows=studentPriorityItems(st).slice(0,5);return `<div class="timeline-list-lite">${rows.map(x=>`<div class="calendar-focus-row"><b>${esc(x.title)}</b><span>${itemPriorityBadge(x.kind,x.date)}</span></div>`).join('')||'<div class="empty">التقويم هادئ حالياً</div>'}</div><button class="btn gold" onclick="location.href='smart-calendar.html?lite=1'">فتح التقويم الكامل</button>`}
function studentBadges(st){const sid=String(st&&st.id||''),uid=String(st&&st.user_id||'');const list=(DATA.achievements||[]).filter(a=>String(a.recipient_student_id||'')===sid||String(a.recipient_user_id||'')===uid).slice(0,6);return list.map(a=>`<div class="badge-row"><span class="badge gold">🏆</span><div><b>${esc(a.badge_title_ar||a.badge_code||'شارة')}</b><small>${esc(a.awarded_at?String(a.awarded_at).slice(0,10):'')}</small></div><b>${ar(a.points_awarded||0)} نقطة</b></div>`).join('')||'<div class="empty">لم تحصل على شارات بعد — أنجز واجباتك وحافظ على حضورك.</div>'}
function studentGrowth(st,m){const gradeTxt=m.gradesAvg>=85?'ممتاز':m.gradesAvg>=70?'جيد ويتحسن':'يحتاج متابعة';const attTxt=m.attendanceRate>=90?'انتظام قوي':m.attendanceRate>=75?'جيد':'انتبه للحضور';return `<div class="growth-list"><div><b>الأداء</b><span>${esc(gradeTxt)}</span></div><div><b>الحضور</b><span>${esc(attTxt)}</span></div><div><b>الخطوة القادمة</b><span>ابدأ بأقرب مهمة في قائمة الأولويات.</span></div></div>`}

function alertsList(allowed){
  allowed = allowed || new Set(['finance','attendance','counseling','evaluation']);
  const parts=[];
  if(allowed.has('finance')){
    DATA.fees.filter(f=>num(f.total_paid)<num(f.net_amount||f.base_amount)).slice(0,5).forEach(f=>parts.push(`<div class="item"><div><b>${esc(studentName(f.student_id))}</b><small>متبقي ${money(num(f.net_amount||f.base_amount)-num(f.total_paid))}</small></div><span class="badge red">مالي</span></div>`));
  }
  if(allowed.has('attendance')||allowed.has('counseling')||allowed.has('evaluation')){
    DATA.attendance.filter(a=>a.status==='absent').slice(0,5).forEach(a=>parts.push(`<div class="item"><div><b>${esc(studentName(a.student_id))}</b><small>${esc(a.date||'')}</small></div><span class="badge red">غياب</span></div>`));
  }
  return `<div class="list">${parts.join('')||'<div class="empty">لا تنبيهات حرجة</div>'}</div>`;
}
function behaviorPanel(scopeStudents){
  const ids=scopeStudents?new Set(scopeStudents.map(s=>String(s.id))):null;
  const records=DATA.behaviorRecords.filter(r=>!ids||ids.has(String(r.student_id))).slice(0,20);
  const riskStudents=(scopeStudents||DATA.students).map(s=>{const abs=DATA.attendance.filter(a=>String(a.student_id)===String(s.id)&&a.status==='absent').length; const gr=DATA.grades.filter(g=>String(g.student_id)===String(s.id)).map(g=>num(g.score??g.grade)).filter(Boolean); const avg=gr.length?Math.round(gr.reduce((a,b)=>a+b,0)/gr.length):0; return {s,abs,avg,risk:abs*8+(avg&&avg<70?20:0)} }).sort((a,b)=>b.risk-a.risk).slice(0,6);
  return `<div class="cards"><div class="card"><div class="card-head"><h3>آخر السجلات</h3></div><div class="card-body"><div class="list">${records.map(r=>`<div class="item"><div><b>${esc(studentName(r.student_id))}</b><small>${esc(r.note||r.description||'سجل سلوك')} · ${esc(String(r.created_at||r.date||'').slice(0,10))}</small></div><span class="badge ${num(r.points)>=0?'green':'red'}">${ar(r.points||0)}</span></div>`).join('')||'<div class="empty">لا سجلات</div>'}</div></div></div><div class="card"><div class="card-head"><h3>طلاب بحاجة متابعة</h3></div><div class="card-body"><div class="list">${riskStudents.map(x=>`<div class="item"><div><b>${esc(fullName(x.s))}</b><small>غياب: ${ar(x.abs)} · متوسط: ${x.avg?x.avg+'%':'—'}</small></div><span class="badge ${x.risk?'red':'green'}">${x.risk?'متابعة':'طبيعي'}</span></div>`).join('')}</div></div></div></div>`;
}
function attendanceTools(students){
  LAST_ATTENDANCE_ROWS=students;
  const classOptions=['<option value="">كل الصفوف</option>'].concat(DATA.classes.map(c=>`<option value="${c.id}">${esc(c.name)}</option>`)).join('');
  return `<div class="card" style="margin-bottom:14px"><div class="card-body"><div class="toolbar"><div class="filters"><input class="input" type="date" id="attDate" value="${iso()}"><select class="select" id="attClassFilter">${classOptions}</select></div><button class="btn gold" onclick="AminPortal.renderAttendanceEditor()">تحميل للتحضير</button></div><div id="attEditor"></div></div></div>`;
}
function renderAttendanceEditor(){
  const date=$('#attDate')?.value||iso(); const cls=$('#attClassFilter')?.value||'';
  let students=LAST_ATTENDANCE_ROWS||DATA.students; if(cls) students=students.filter(s=>String(s.class_id)===String(cls));
  const rows=students.map(s=>{const rec=DATA.attendance.find(a=>String(a.student_id)===String(s.id)&&String(a.date).slice(0,10)===date); const st=rec?rec.status:'present'; return `<tr><td>${esc(fullName(s))}</td><td>${esc(className(s.class_id))}</td><td><select class="select" data-att-student="${s.id}"><option value="present" ${st==='present'?'selected':''}>حاضر</option><option value="absent" ${st==='absent'?'selected':''}>غائب</option><option value="late" ${st==='late'?'selected':''}>متأخر</option></select></td><td><input class="input" data-att-note="${s.id}" value="${esc((rec&&rec.note)||'')}" placeholder="ملاحظة"></td></tr>`}).join('');
  $('#attEditor').innerHTML=`${table(['الطالب','الصف','الحالة','ملاحظة'],rows,'لا طلاب')}<div style="margin-top:12px"><button class="btn green" onclick="AminPortal.saveAttendance()">حفظ الحضور</button></div>`;
}
async function saveAttendance(){
  const date=$('#attDate')?.value||iso(); const selects=$$('[data-att-student]'); let errors=0;
  for(const sel of selects){const sid=sel.dataset.attStudent; const note=$(`[data-att-note="${sid}"]`)?.value||null; const payload={student_id:sid,recorded_by:ME.id,date,status:sel.value,note,attendance_type:cfg().defaultAttendanceType||'daily'}; const existing=await q('attendance',{columns:'id',limit:1,filters:[{op:'eq',col:'student_id',val:sid},{op:'eq',col:'date',val:date},{op:'eq',col:'attendance_type',val:payload.attendance_type}]}); let res; if(existing[0]) res=await client().from('attendance').update(payload).eq('id',existing[0].id); else res=await client().from('attendance').insert(payload); if(res.error){console.warn(res.error); errors++;}}
  await loadData(); renderAttendanceEditor(); toast(errors?'تم مع أخطاء':'تم حفظ الحضور', errors?String(errors):'تم تحديث قاعدة البيانات', errors?'red':'green');
}

async function bootLogin(){
  client();
  $('#loginForm')?.addEventListener('submit',login);
  $('#loginBtn')?.addEventListener('click',login);
  $('#password')?.addEventListener('keydown',e=>{if(e.key==='Enter')login(e)});
  ['username','password'].forEach(id=>$('#'+id)?.addEventListener('input',()=>setFieldError(id,'')));
  $('#togglePassword')?.addEventListener('click',()=>{const input=$('#password'); if(!input)return; const show=input.type==='password'; input.type=show?'text':'password'; $('#togglePassword').setAttribute('aria-label',show?'إخفاء كلمة المرور':'إظهار كلمة المرور')});
  $('#forgotPassword')?.addEventListener('click',e=>{e.preventDefault();toast('استعادة كلمة المرور','يرجى مراجعة إدارة المدرسة لإعادة تعيين كلمة المرور.','blue')});
  setFailedAttempts(failedAttempts());
  const {data:{session}}=await client().auth.getSession();
  if(session){ const {data:p}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle(); if(p) $('#sessionHint').innerHTML=`توجد جلسة نشطة · <a href="${routeFor(p)}">دخول مباشر إلى الواجهة المناسبة</a>`; }
}
async function bootPortal(){
  client(); const p=await authProfile(); if(!p)return; layoutReady(); await loadData(); const first=$$('.nav button[data-view]').find(b=>b.style.display!=='none' && !b.disabled); showView(first?first.dataset.view:'overview');
}

window.showView = showView;
window.AminPortal={bootLogin,bootPortal,login,logout,renderAttendanceEditor,saveAttendance,showView,requestSkillProgramAppointment};

// ========== تحميل نظام التنبيهات الذكية تلقائياً ==========
(function loadSmartAlerts(){
  if(document.querySelector('script[src*="smart-alerts.js"]')) return;
  const script = document.createElement('script');
  script.src = 'assets/smart-alerts.js';
  script.async = true;
  document.body.appendChild(script);
})();

}());

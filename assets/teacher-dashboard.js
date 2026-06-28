/* Professional Teacher Dashboard — fast daily workflow, scoped by section assignments */
(function(){
'use strict';

const cfg=()=>window.AMIN_CONFIG||{};
let sb=null,ME=null,DATA=null,ACTIVE='overview';
let HOMEWORK_FILES=[], HOMEWORK_EDIT_ID=null, HOMEWORK_AUTOSAVE_TIMER=null, GRADE_AUTOSAVE_TIMERS=new Map();
const DAYS=['السبت','الأحد','الاثنين','الثلاثاء','الأربعاء'];
const ATT_STATUSES=[
  ['present','حاضر','present'],
  ['absent','غائب','absent'],
  ['late','متأخر','late'],
  ['permission','مستأذن','late'],
  ['medical_excuse','عذر طبي','absent'],
  ['external_activity','نشاط خارجي','present']
];

const $=(s,r=document)=>r.querySelector(s);
const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
function esc(v){return String(v==null?'':v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
function num(v){const n=Number(v);return Number.isFinite(n)?n:0}
function iso(){return new Date().toISOString().slice(0,10)}
function addDays(d,days){const x=new Date(d+'T00:00:00');x.setDate(x.getDate()+days);return x.toISOString().slice(0,10)}
function schoolDayIndex(dateISO){const d=new Date(dateISO+'T00:00:00').getDay();return (d+1)%7}
function client(){if(sb)return sb;sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});return sb}
function toast(t,m,type=''){const el=$('#toast');if(!el)return;el.innerHTML=`<b>${esc(t)}</b><br><span class="muted">${esc(m||'')}</span>`;el.className='toast show '+type;clearTimeout(el._t);el._t=setTimeout(()=>el.classList.remove('show'),4200)}
async function q(table,opts={}){try{let query=client().from(table).select(opts.columns||'*');(opts.filters||[]).forEach(f=>query=query[f.op](f.col,f.val));if(opts.order)query=query.order(opts.order,{ascending:opts.ascending!==false});if(opts.limit)query=query.limit(opts.limit);const {data,error}=await query;if(error){console.warn(table,error);return[]}return data||[]}catch(e){console.warn(table,e);return[]}}
function withTimeout(promise,ms=15000,label='operation'){return Promise.race([promise,new Promise((_,reject)=>setTimeout(()=>reject(new Error('انتهت مهلة الاتصال أثناء '+label+' — تحققي من SQL 40 أو الاتصال')),ms))])}

async function ensure(){
  const {data:{session}}=await client().auth.getSession();
  if(!session){location.href='index.html';return false}
  const {data:u}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();
  ME=u;
  if(!u||u.role!=='teacher'){
    document.body.innerHTML='<main class="login-page"><section class="login-card"><h1>غير مصرح</h1><p>هذه اللوحة للمعلمين فقط.</p></section></main>';
    return false;
  }
  $('#profileName').textContent=u.name||u.email;
  $('#profileRole').textContent='معلم';
  return true;
}
function norm(v){return String(v||'').replace(/[إأآا]/g,'ا').replace(/[ىي]/g,'ي').replace(/ة/g,'ه').replace(/\s+/g,'').toLowerCase()}
function classStageByName(name){const n=norm(name);if(n.includes('ابتدائي'))return'primary';if(n.includes('متوسط'))return'middle';return'preparatory'}
function fullName(s){return s?[s.name,s.father_name,s.last_name].filter(Boolean).join(' ')||s.name:'—'}
function className(id){return (DATA.classMap.get(String(id))||{}).name||'—'}
function subjectName(id){return (DATA.subjectMap.get(String(id))||{}).name||'—'}
function sectionLabel(sec){if(!sec)return'—';return sec.section_name||`${sec.class_name||className(sec.class_id)} — شعبة ${sec.section_code||''}`}
function uniqueBy(arr,key){const m=new Map();arr.forEach(x=>{const k=key(x);if(k&&!m.has(k))m.set(k,x)});return [...m.values()]}

async function load(){
  const [scheduleRows, rosterRows, classes, subjects, attendance, continuous, exams, scores, sessions, homeworks, homeworkAttachments, homeworkGrades, homeworkSubmissions, homeworkSubmissionAttachments, homeworkComments, homeworkViews, homeworkFollowup, homeworkMissing, lessonPlans, risks, curriculumSlots] = await Promise.all([
    q('v_teacher_schedule',{order:'day'}),
    q('v_teacher_students',{order:'student_name'}),
    q('classes',{order:'name'}),
    q('subjects',{order:'name'}),
    q('attendance',{order:'date',ascending:false}),
    q('continuous_assessments'),
    q('exams'),
    q('exam_scores'),
    q('class_sessions',{filters:[{op:'eq',col:'teacher_id',val:ME.id}],order:'session_date'}),
    q('homeworks',{filters:[{op:'eq',col:'teacher_id',val:ME.id}],order:'created_at',ascending:false}),
    q('homework_attachments',{order:'sort_order'}),
    q('homework_grades',{order:'updated_at',ascending:false}),
    q('v_teacher_homework_submissions',{order:'updated_at',ascending:false}),
    q('homework_submission_attachments',{order:'sort_order'}),
    q('v_homework_submission_comments_detailed',{order:'created_at'}),
    q('homework_views',{order:'last_viewed_at',ascending:false}),
    q('v_homework_completion_report',{order:'due_date',ascending:true}),
    q('v_homework_missing_students',{order:'due_date',ascending:true}),
    q('lesson_plans',{filters:[{op:'eq',col:'teacher_id',val:ME.id}],order:'created_at',ascending:false}),
    q('v_teacher_student_risk'),
    q('v_curriculum_plan_slots_detailed',{order:'planned_date',limit:1000})
  ]);

  const [notifications, achievementAwards] = await Promise.all([
    q('school_notifications',{filters:[{op:'eq',col:'recipient_user_id',val:ME.id}],order:'created_at',ascending:false,limit:20}),
    q('v_achievement_awards_detailed',{filters:[{op:'eq',col:'recipient_user_id',val:ME.id}],order:'awarded_at',ascending:false,limit:20})
  ]);

  const sections = uniqueBy(
    scheduleRows.map(r=>({section_id:r.section_id,class_id:r.class_id,class_name:r.class_name,section_code:r.section_code,section_name:r.section_name})).concat(
      rosterRows.map(r=>({section_id:r.section_id,class_id:r.class_id,class_name:r.class_name,section_code:r.section_code,section_name:r.section_name}))
    ),
    x=>String(x.section_id||x.class_id)
  ).filter(x=>x.section_id||x.class_id);

  const students = uniqueBy(rosterRows.map(r=>({
    id:r.student_id,
    name:r.student_name,
    gender:r.gender,
    father_name:r.father_name,
    mother_name:r.mother_name,
    last_name:r.last_name,
    class_id:r.class_id,
    class_name:r.class_name,
    section_id:r.section_id,
    section_code:r.section_code,
    section_name:r.section_name
  })),x=>String(x.id));

  DATA={
    schedule:scheduleRows,
    sections,
    classes,
    subjects,
    students,
    attendance,
    continuous,
    exams,
    scores,
    sessions,
    homeworks,
    homeworkAttachments,
    homeworkGrades,
    homeworkSubmissions,
    homeworkSubmissionAttachments,
    homeworkComments,
    homeworkViews,
    homeworkFollowup,
    homeworkMissing,
    lessonPlans,
    risks,
    curriculumSlots,
    notifications,
    achievementAwards,
    classMap:new Map(classes.map(x=>[String(x.id),x])),
    subjectMap:new Map(subjects.map(x=>[String(x.id),x])),
    sectionMap:new Map(sections.map(x=>[String(x.section_id||x.class_id),x])),
    studentMap:new Map(students.map(x=>[String(x.id),x]))
  };
  render(ACTIVE);
}

function table(h,rows,empty='لا توجد بيانات'){
  const body=Array.isArray(rows)?rows.join(''):String(rows||'');
  return body.trim()?`<div class="table-wrap"><table><thead><tr>${h.map(x=>`<th>${esc(x)}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>`:`<div class="empty">${esc(empty)}</div>`;
}
function kpi(l,v,c='gold'){return`<div class="kpi ${c}"><small>${esc(l)}</small><b>${esc(v)}</b></div>`}
function sectionOptions(){return `<option value="">اختاري الصف / الشعبة</option>`+DATA.sections.map(s=>`<option value="${esc(s.section_id||s.class_id)}">${esc(sectionLabel(s))}</option>`).join('')}
function studentsForSection(sectionId){return DATA.students.filter(s=>String(s.section_id||s.class_id)===String(sectionId))}
function scheduleForSection(sectionId){return DATA.schedule.filter(s=>String(s.section_id||s.class_id)===String(sectionId))}
function subjectsForSection(sectionId){const ids=[...new Set(scheduleForSection(sectionId).map(s=>String(s.subject_id)))];return DATA.subjects.filter(s=>ids.includes(String(s.id)))}
function periodsForSection(sectionId){const sec=DATA.sectionMap.get(String(sectionId));const stage=classStageByName(sec&&sec.class_name);let p=[...new Set(DATA.schedule.filter(s=>String(s.section_id||s.class_id)===String(sectionId)).map(s=>Number(s.period_number)).filter(Boolean))].sort((a,b)=>a-b);if(stage==='primary')p=p.filter(x=>x<=2);return p.length?p:(stage==='primary'?[1,2]:[1,2,3])}
function subjectForAttendance(sectionId,period,date){const day=schoolDayIndex(date);return scheduleForSection(sectionId).find(s=>Number(s.day)===day&&Number(s.period_number)===Number(period))?.subject_id||null}
function sessionById(id){return DATA.sessions.find(s=>String(s.id)===String(id))}

function render(id){
  ACTIVE=id;
  $$('.view').forEach(v=>v.classList.toggle('active',v.id==='view-'+id));
  $$('.nav button[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view===id));
  ({overview,attendance:attendanceView,homework:homeworkView,plan:planView,grades:gradesView,students:studentsView,schedule:scheduleView}[id]||overview)();
}
function show(id){render(id);$('#sidebar')?.classList.remove('open')}

function overview(){
  const today=iso();
  const todaySessions=DATA.sessions.filter(s=>s.session_date===today);
  const nextSessions=DATA.sessions.filter(s=>s.session_date>=today&&s.status!=='holiday').slice(0,8);
  const absentToday=DATA.attendance.filter(a=>a.date===today&&a.status==='absent').length;
  $('#view-overview').innerHTML=`<div class="page-head"><div><h1>مركز المعلم اليومي</h1><p>الأهم أولاً: حصص اليوم، مهام قريبة، إشعارات مهمة، وتقويم العمل.</p></div><div class="form-actions"><button class="btn gold" onclick="location.href='smart-calendar.html?lite=1'">التقويم</button><button class="btn blue" onclick="TeacherDashboard.reload()">تحديث</button></div></div><div class="teacher-dashboard-grid">${kpi('حصص اليوم',todaySessions.length,'green')}${kpi('مهام قريبة',teacherPriorityItems().length,'red')}${kpi('إشعارات مهمة',(DATA.notifications||[]).filter(n=>!n.read_at).length,'gold')}${kpi('شاراتي',(DATA.achievementAwards||[]).length,'blue')}</div><div class="teacher-hero-strip"><div class="mini-tile"><small>الشعب</small><b>${DATA.sections.length}</b></div><div class="mini-tile"><small>طلابي</small><b>${DATA.students.length}</b></div><div class="mini-tile"><small>غيابات اليوم</small><b>${absentToday}</b></div></div><div class="teacher-priority-grid"><div class="card"><div class="card-head"><h3>أهم مهام اليوم</h3></div><div class="card-body">${teacherPriorityHub()}</div></div><div class="card"><div class="card-head"><h3>التقويم والحصص</h3></div><div class="card-body">${dailyCommand(nextSessions)}</div></div><div class="card"><div class="card-head"><h3>الإشعارات الأكثر أهمية</h3></div><div class="card-body">${teacherImportantNotifications()}</div></div><div class="card"><div class="card-head"><h3>الشارات والتحفيز</h3></div><div class="card-body">${teacherBadges()}</div></div></div>`;
}

function dueText(d){if(!d)return'بدون موعد';const x=new Date(String(d).slice(0,10)+'T00:00:00'),t=new Date(iso()+'T00:00:00');const diff=Math.round((x-t)/86400000);if(diff<0)return 'متأخر '+Math.abs(diff)+' يوم';if(diff===0)return 'اليوم';if(diff===1)return 'غداً';return 'بعد '+diff+' يوم'}
function teacherPriorityItems(){const items=[];DATA.sessions.filter(s=>s.session_date>=iso()&&s.status!=='holiday').slice(0,6).forEach(s=>items.push({kind:'session',title:subjectName(s.subject_id)+' · '+className(s.class_id),date:s.session_date,action:`TeacherDashboard.startAttendanceFromSession('${s.id}')`,label:'حضور'}));DATA.homeworkFollowup.filter(r=>Number(r.missing_count||0)>0||String(r.due_date||'')<=addDays(iso(),2)).slice(0,6).forEach(r=>items.push({kind:'homework',title:r.title||'متابعة واجب',date:r.due_date,action:`location.href='homework-reports.html?lite=1'`,label:'متابعة'}));(DATA.notifications||[]).filter(n=>!n.read_at).slice(0,5).forEach(n=>items.push({kind:'note',title:n.title||'إشعار',date:n.created_at,action:`location.href='notifications.html?lite=1'`,label:'فتح'}));return items.sort((a,b)=>new Date(a.date||'2999-01-01')-new Date(b.date||'2999-01-01')).slice(0,8)}
function teacherPriorityHub(){const list=teacherPriorityItems();return list.map(x=>`<div class="teacher-priority-item ${x.kind}"><div><b>${esc(x.title)}</b><small>${esc(x.kind==='session'?'حصة':x.kind==='homework'?'واجب يحتاج متابعة':'إشعار')}</small></div><span class="badge ${dueText(x.date).includes('متأخر')||dueText(x.date)==='اليوم'?'red':'blue'}">${esc(dueText(x.date))}</span><button class="btn small" onclick="${x.action}">${esc(x.label)}</button></div>`).join('')||'<div class="empty">لا توجد مهام عاجلة الآن</div>'}
function teacherImportantNotifications(){const list=(DATA.notifications||[]).filter(n=>!n.read_at).slice(0,6);return list.map(n=>`<div class="teacher-priority-item note"><div><b>${esc(n.title||'إشعار')}</b><small>${esc(String(n.created_at||'').slice(0,16))}</small></div><span class="badge gold">مهم</span><button class="btn small" onclick="location.href='notifications.html?lite=1'">فتح</button></div>`).join('')||'<div class="empty">لا توجد إشعارات مهمة</div>'}
function teacherBadges(){const list=(DATA.achievementAwards||[]).slice(0,5);return list.map(a=>`<div class="badge-row"><span class="badge gold">🏆</span><div><b>${esc(a.badge_title_ar||a.badge_code||'شارة')}</b><small>${esc(String(a.awarded_at||'').slice(0,10))}</small></div><b>${num(a.points_awarded||0)} نقطة</b></div>`).join('')||'<div class="empty">لم تحصل على شارات بعد — أنشئ واجبات واختبارات وتابع الحضور.</div>'}

function dailyCommand(list){return list.length?list.map(s=>`<div class="session-card ${s.status==='holiday'?'holiday':''}"><div><b>${esc(subjectName(s.subject_id))}</b><small class="muted">${esc(className(s.class_id))} · الحصة ${s.period_number} · ${esc(s.session_date)} · ${String(s.start_time||'').slice(0,5)}</small></div><div class="session-actions"><button class="btn green" onclick="TeacherDashboard.startAttendanceFromSession('${s.id}')">حضور</button><button class="btn" onclick="TeacherDashboard.startPlanFromSession('${s.id}')">تحضير</button><button class="btn blue" onclick="TeacherDashboard.homeworkForSession('${s.id}')">واجب</button><button class="btn gold" onclick="TeacherDashboard.startGradesFromSession('${s.id}')">درجات</button></div></div>`).join(''):'<div class="empty">لا توجد حصص قادمة. اطلبي من الإدارة توليد الجلسات.</div>'}

function attendanceView(){
  const first=DATA.sections[0];
  $('#view-attendance').innerHTML=`<div class="page-head"><div><h1>الحضور والغياب</h1><p>الجميع حاضر افتراضياً؛ ثبتي فقط الغياب أو التأخير أو الاستئذان. لا يسمح للمعلم بتعديل أيام سابقة.</p></div></div><div class="card"><div class="card-body"><div class="teacher-toolbar"><div class="field"><label>التاريخ</label><input id="attDate" class="input" type="date" value="${iso()}"></div><div class="field"><label>الصف / الشعبة</label><select id="attSection" class="select" onchange="TeacherDashboard.refreshAttendanceForm()">${sectionOptions()}</select></div><div class="field"><label>الحصة</label><select id="attPeriod" class="select"></select></div><button class="btn gold" onclick="TeacherDashboard.refreshAttendanceForm()">تحميل الطلاب</button></div><div id="attendanceBox"></div></div></div>`;
  if(first){$('#attSection').value=first.section_id||first.class_id;refreshAttendanceForm()}
}
function refreshAttendanceForm(){
  const date=$('#attDate').value;
  if(date!==iso()){$('#attendanceBox').innerHTML='<div class="teacher-note">يسمح للمعلم بتسجيل حضور اليوم الحالي فقط. تعديل الأيام السابقة يحتاج فتح صلاحية من الإدارة.</div>';return}
  const sectionId=$('#attSection').value;
  const periods=periodsForSection(sectionId);
  const previous=$('#attPeriod').value;
  $('#attPeriod').innerHTML=periods.map(p=>`<option value="${p}">الحصة ${p}</option>`).join('');
  if(previous&&periods.includes(Number(previous)))$('#attPeriod').value=previous;
  const period=Number($('#attPeriod').value||periods[0]);
  const students=studentsForSection(sectionId);
  const rows=students.map(s=>{
    const rec=DATA.attendance.find(a=>String(a.student_id)===String(s.id)&&a.date===date&&Number(a.period_number||0)===period&&a.attendance_type==='period');
    const status=rec?rec.status:'present';
    const absType=rec&&rec.absence_type||'unexcused';
    return `<div class="student-mark-row" data-student="${s.id}"><div><b>${esc(fullName(s))}</b><small class="muted">${esc(sectionLabel(s))}</small></div><div class="status-toggle">${ATT_STATUSES.map(([key,label,cls])=>`<button type="button" class="${cls} ${status===key?'active':''}" data-status="${key}">${label}</button>`).join('')}</div><select class="select absence-type" ${status==='present'?'disabled':''}><option value="excused" ${absType==='excused'?'selected':''}>مبرر</option><option value="unexcused" ${absType==='unexcused'?'selected':''}>غير مبرر</option></select><input class="input att-note" placeholder="ملاحظة" value="${esc(rec&&rec.note||'')}"></div>`;
  }).join('');
  $('#attendanceBox').innerHTML=`<div class="bulk-tools"><button class="btn green" onclick="TeacherDashboard.markAllPresent()">جعل الكل حاضر</button><button class="btn gold" onclick="TeacherDashboard.saveAttendance()">حفظ الغياب والتأخير فقط</button></div><div class="teacher-note">الحاضرون لا يُحفظ لهم سجل منفصل لتسريع العمل وتقليل البيانات.</div>${rows||'<div class="empty">لا يوجد طلاب في هذه الشعبة ضمن جدولك.</div>'}`;
  $$('.status-toggle button',$('#attendanceBox')).forEach(btn=>btn.addEventListener('click',()=>{const row=btn.closest('[data-student]');$$('.status-toggle button',row).forEach(b=>b.classList.remove('active'));btn.classList.add('active');const type=$('.absence-type',row);type.disabled=btn.dataset.status==='present';if(['permission','medical_excuse','external_activity'].includes(btn.dataset.status)){type.value='excused'}}));
}
function markAllPresent(){$$('[data-student]').forEach(row=>{$$('.status-toggle button',row).forEach(b=>b.classList.remove('active'));$('.present',row).classList.add('active');$('.absence-type',row).disabled=true})}
async function saveAttendance(){
  const date=$('#attDate').value;
  if(date!==iso()){toast('غير مسموح','المعلم يسجل حضور اليوم الحالي فقط','red');return}
  const sectionId=$('#attSection').value,period=Number($('#attPeriod').value),subject_id=subjectForAttendance(sectionId,period,date);
  let errors=0;
  for(const row of $$('[data-student]')){
    const sid=row.dataset.student,status=$('.status-toggle button.active',row)?.dataset.status||'present';
    const note=$('.att-note',row).value||null;
    const absence_type=$('.absence-type',row).value;
    const existing=await q('attendance',{columns:'id',filters:[{op:'eq',col:'student_id',val:sid},{op:'eq',col:'date',val:date},{op:'eq',col:'period_number',val:period},{op:'eq',col:'attendance_type',val:'period'}],limit:1});
    if(status==='present'){
      if(existing[0]){const {error}=await client().from('attendance').delete().eq('id',existing[0].id);if(error)errors++}
      continue;
    }
    const payload={student_id:sid,recorded_by:ME.id,date,status,note,period_number:period,attendance_type:'period',absence_type:(status==='absent'?absence_type:['permission','medical_excuse','external_activity'].includes(status)?'excused':null),subject_id};
    let res;if(existing[0])res=await client().from('attendance').update(payload).eq('id',existing[0].id);else res=await client().from('attendance').insert(payload);
    if(res.error){console.warn(res.error);errors++}
  }
  toast(errors?'تم مع أخطاء':'تم الحفظ',errors?String(errors):'تم تثبيت الغياب والتأخير فقط',errors?'red':'green');
  await load();attendanceView();
}
function startAttendanceFromSession(id){const s=sessionById(id);if(!s)return;show('attendance');setTimeout(()=>{$('#attDate').value=s.session_date||iso();$('#attSection').value=s.section_id||s.class_id;refreshAttendanceForm();setTimeout(()=>{$('#attPeriod').value=s.period_number;refreshAttendanceForm()},40)},40)}

function sessionsList(list){return list.length?list.map(s=>`<div class="session-card ${s.status==='holiday'?'holiday':''}"><div><b>${esc(subjectName(s.subject_id))}</b><small class="muted">${esc(className(s.class_id))} · الحصة ${s.period_number} · ${String(s.start_time||'').slice(0,5)}</small></div><div class="session-actions"><button class="btn green" onclick="TeacherDashboard.confirmSession('${s.id}')">تثبيت</button><button class="btn" onclick="TeacherDashboard.startPlanFromSession('${s.id}')">تحضير</button><button class="btn blue" onclick="TeacherDashboard.homeworkForSession('${s.id}')">واجب</button><button class="btn gold" onclick="TeacherDashboard.startGradesFromSession('${s.id}')">درجات</button></div></div>`).join(''):'<div class="empty">لا توجد جلسات اليوم. اطلبي من الإدارة توليد الجلسات من صفحة الجدول.</div>'}
async function confirmSession(id){const {data,error}=await client().rpc('confirm_teacher_session',{p_session_id:id,p_activity_type:'manual_confirm',p_notes:'تثبيت من لوحة المعلم'});if(error||data?.ok===false)toast('تعذر التثبيت',error?.message||data?.message||'خطأ','red');else{toast('تم التثبيت','تم إثبات نشاط الحصة','green');await load();overview()}}

function statusAr(s){return ({draft:'مسودة',published:'منشور',closed:'مغلق',archived:'مؤرشف'}[s]||s||'—')}
function homeworkSessionOptions(){const upcoming=DATA.sessions.filter(s=>s.session_date>=addDays(iso(),-7)&&s.status!=='holiday').slice(0,80);return '<option value="">بدون حصة محددة</option>'+upcoming.map(s=>`<option value="${s.id}">${esc(s.session_date)} — ${esc(className(s.class_id))} — ${esc(subjectName(s.subject_id))} — الحصة ${s.period_number}</option>`).join('')}
function homeworkSectionOptions(selected=''){return sectionOptions().replace(`value="${esc(selected)}"`,`value="${esc(selected)}" selected`)}
function homeworkSubjectOptions(sectionId='',selected=''){const list=sectionId?subjectsForSection(sectionId):DATA.subjects;return '<option value="">اختاري المادة</option>'+list.map(s=>`<option value="${s.id}" ${String(selected)===String(s.id)?'selected':''}>${esc(s.name)}</option>`).join('')}
function curriculumTopicOptions(sectionId='',subjectId='',selected=''){
  const sec=DATA.sectionMap.get(String(sectionId))||{};
  const list=(DATA.curriculumSlots||[]).filter(x=>{
    if(x.status==='cancelled')return false;
    if(subjectId&&String(x.subject_id)!==String(subjectId))return false;
    if(sec.section_id && x.section_id && String(x.section_id)!==String(sec.section_id))return false;
    if(sec.class_id && x.class_id && String(x.class_id)!==String(sec.class_id))return false;
    return true;
  }).sort((a,b)=>(a.status==='completed')-(b.status==='completed')||Number(a.week_index||0)-Number(b.week_index||0)||Number(a.slot_order||0)-Number(b.slot_order||0));
  return '<option value="">موضوع حر / مراجعة / شيء آخر</option>'+list.map(x=>`<option value="${esc(x.id)}" ${String(selected)===String(x.id)?'selected':''}>${esc(x.lesson_title||'درس')} — أسبوع ${esc(x.week_index||'—')} ${x.status==='completed'?'✓ مُعطى':''}</option>`).join('')
}
function updateHomeworkCurriculumTopics(){const sectionId=$('#hwSection')?.value||'',subjectId=$('#hwSubject')?.value||'',current=$('#hwCurriculumSlot')?.value||'';const sel=$('#hwCurriculumSlot');if(sel)sel.innerHTML=curriculumTopicOptions(sectionId,subjectId,current)}
function onHomeworkCurriculumChange(){const id=$('#hwCurriculumSlot')?.value;const slot=(DATA.curriculumSlots||[]).find(x=>String(x.id)===String(id));if(slot){$('#hwTitle').value=slot.lesson_title||'';if(!$('#hwDescription').value)$('#hwDescription').value='واجب مرتبط بدرس: '+(slot.lesson_title||'');}scheduleHomeworkAutosave()}

function homeworkAttachmentsFor(id){return DATA.homeworkAttachments.filter(a=>String(a.homework_id)===String(id)).sort((a,b)=>(a.sort_order||0)-(b.sort_order||0))}
function homeworkGradeCount(id){return DATA.homeworkGrades.filter(g=>String(g.homework_id)===String(id)).length}
function homeworkSubmissionCount(id){return (DATA.homeworkSubmissions||[]).filter(s=>String(s.homework_id)===String(id)&&s.submission_id).length}
function submissionAttachmentsFor(id){return (DATA.homeworkSubmissionAttachments||[]).filter(a=>String(a.submission_id)===String(id)).sort((a,b)=>(a.sort_order||0)-(b.sort_order||0))}
function homeworkReportFor(id){return (DATA.homeworkFollowup||[]).find(r=>String(r.homework_id)===String(id))||null}
function homeworkViewedCount(id){return (DATA.homeworkViews||[]).filter(v=>String(v.homework_id)===String(id)).length}
function commentsForSubmission(id){return (DATA.homeworkComments||[]).filter(c=>String(c.submission_id)===String(id)).sort((a,b)=>new Date(a.created_at)-new Date(b.created_at))}
function homeworkMissingFor(id){return (DATA.homeworkMissing||[]).filter(r=>String(r.homework_id)===String(id))}
function submissionAttachmentChip(a){const icon=(a.file_type||'').startsWith('image/')?'🖼️':(a.file_type||'').includes('pdf')?'📕':'📎';return `<button class="attachment-chip submitted" onclick="TeacherDashboard.openSubmissionAttachment('${esc(a.storage_path)}','${esc(a.file_name)}')"><span>${icon}</span><b>${esc(a.file_name)}</b><small>${Math.round((a.file_size||0)/1024)} KB</small></button>`}
function homeworkView(){
  const todaySessions=DATA.sessions.filter(s=>s.session_date===iso());
  $('#view-homework').innerHTML=`<div class="page-head"><div><h1>الواجبات</h1><p>إنشاء واجب بمرفقات متعددة، مسودة أو منشور، مع حفظ تلقائي للمسودات.</p></div></div><div class="cards"><div class="card"><div class="card-head"><h3>إنشاء / تعديل واجب</h3></div><div class="card-body">${homeworkFormHTML()}</div></div><div class="card"><div class="card-head"><h3>حصص اليوم</h3></div><div class="card-body">${sessionsList(todaySessions)}</div></div></div><div class="card"><div class="card-head"><h3>آخر الواجبات</h3></div><div class="card-body">${homeworksList(DATA.homeworks)}</div></div>`;
  bindHomeworkForm();
}
function homeworkFormHTML(){return `<div class="homework-form" id="homeworkForm">
  <input type="hidden" id="hwId" value="${esc(HOMEWORK_EDIT_ID||'')}">
  <div class="teacher-toolbar"><div class="field"><label>الحصة</label><select id="hwSession" class="select" onchange="TeacherDashboard.updateHomeworkSessionMeta()">${homeworkSessionOptions()}</select></div><div class="field"><label>الصف / الشعبة</label><select id="hwSection" class="select" onchange="TeacherDashboard.updateHomeworkSubjects()">${sectionOptions()}</select></div><div class="field"><label>المادة</label><select id="hwSubject" class="select" onchange="TeacherDashboard.updateHomeworkCurriculumTopics()">${homeworkSubjectOptions()}</select></div></div>
  <div class="homework-grid"><div class="field span-6"><label>درس من الخطة السنوية</label><select id="hwCurriculumSlot" class="select" onchange="TeacherDashboard.onHomeworkCurriculumChange()">${curriculumTopicOptions()}</select><small class="muted">اختاري درساً أو اتركيه موضوعاً حراً مثل مراجعة</small></div><div class="field span-6"><label>عنوان الواجب / موضوع حر</label><input id="hwTitle" class="input" placeholder="عنوان الواجب أو مراجعة أو نشاط"></div><div class="field span-3"><label>تاريخ النشر</label><input id="hwPublishAt" class="input" type="datetime-local"></div><div class="field span-3"><label>الحالة</label><select id="hwStatus" class="select"><option value="draft">مسودة</option><option value="published">منشور</option><option value="closed">مغلق</option><option value="archived">مؤرشف</option></select></div><div class="field span-12"><label>وصف الواجب</label><textarea id="hwDescription" class="input" placeholder="تعليمات الواجب"></textarea></div><div class="field span-4"><label>تاريخ التسليم</label><input id="hwDueDate" class="input" type="date" value="${addDays(iso(),3)}"></div><div class="field span-4"><label>وقت التسليم</label><input id="hwDueTime" class="input" type="time" value="23:59"></div><div class="field span-4"><label>الدرجة الكاملة</label><input id="hwMaxScore" class="input" type="number" min="1" step="0.5" value="10"></div></div>
  <div class="upload-zone"><label class="btn blue">اختيار ملفات<input id="hwFiles" type="file" multiple accept=".jpg,.jpeg,.png,.webp,.pdf,.docx,.pptx,image/jpeg,image/png,image/webp,application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,application/vnd.openxmlformats-officedocument.presentationml.presentation" hidden></label><label class="btn">التقاط صورة<input id="hwCamera" type="file" accept="image/*" capture="environment" hidden></label><span class="muted">JPG, PNG, WEBP, PDF, DOCX, PPTX</span></div>
  <div id="hwPreview" class="homework-preview"></div><div id="hwSaveStatus" class="alert info" style="display:none;margin:12px 0"></div>
  <div class="form-actions"><button class="btn" onclick="TeacherDashboard.saveHomework('draft')">حفظ مسودة</button><button class="btn gold" onclick="TeacherDashboard.saveHomework('published')">نشر الواجب وإرسال إشعار</button><button class="btn blue" onclick="TeacherDashboard.saveHomework()">حفظ حسب الحالة</button><button class="btn red" onclick="TeacherDashboard.resetHomeworkForm()">تفريغ</button></div>
</div>`}
function bindHomeworkForm(){
  $('#hwFiles')?.addEventListener('change',e=>addHomeworkFiles(e.target.files));
  $('#hwCamera')?.addEventListener('change',e=>addHomeworkFiles(e.target.files));
  ['hwTitle','hwDescription','hwDueDate','hwDueTime','hwMaxScore','hwStatus','hwSubject','hwSection','hwSession','hwPublishAt','hwCurriculumSlot'].forEach(id=>{$('#'+id)?.addEventListener('input',scheduleHomeworkAutosave);$('#'+id)?.addEventListener('change',scheduleHomeworkAutosave)});
  renderHomeworkFilePreview();
  if(HOMEWORK_EDIT_ID) loadHomeworkIntoForm(HOMEWORK_EDIT_ID);
}
function setHwStatus(msg,type='info'){const el=$('#hwSaveStatus');if(!el)return;el.className='alert '+(type==='red'?'error':type==='green'?'success':'info');el.textContent=msg;el.style.display='block'}
function updateHomeworkSessionMeta(){const s=sessionById($('#hwSession')?.value);if(!s)return;$('#hwSection').value=s.section_id||s.class_id||'';updateHomeworkSubjects();$('#hwSubject').value=s.subject_id||'';if(!$('#hwPublishAt').value){$('#hwPublishAt').value=(new Date().toISOString().slice(0,16))}updateHomeworkCurriculumTopics()}
function updateHomeworkSubjects(){const sectionId=$('#hwSection')?.value||'';const current=$('#hwSubject')?.value||'';$('#hwSubject').innerHTML=homeworkSubjectOptions(sectionId,current);updateHomeworkCurriculumTopics()}
function addHomeworkFiles(files){const allowed=['image/jpeg','image/png','image/webp','application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.presentationml.presentation'];Array.from(files||[]).forEach(f=>{if(!allowed.includes(f.type)&&!/(\.docx|\.pptx)$/i.test(f.name)){toast('ملف غير مدعوم',f.name,'red');return}HOMEWORK_FILES.push({id:crypto.randomUUID?crypto.randomUUID():String(Date.now()+Math.random()),file:f,name:f.name,type:f.type,size:f.size,preview:f.type.startsWith('image/')?URL.createObjectURL(f):null})});renderHomeworkFilePreview();scheduleHomeworkAutosave()}
function renderHomeworkFilePreview(){const box=$('#hwPreview');if(!box)return;const existing=HOMEWORK_EDIT_ID?homeworkAttachmentsFor(HOMEWORK_EDIT_ID):[];const ex=existing.map(a=>`<div class="file-chip"><span>📎</span><b>${esc(a.file_name)}</b><small>${esc(a.file_type||'ملف محفوظ')}</small></div>`).join('');const local=HOMEWORK_FILES.map((f,i)=>`<div class="file-card"><div class="file-thumb">${f.preview?`<img src="${f.preview}" alt="">`:'📄'}</div><div><b>${esc(f.name)}</b><small>${Math.round((f.size||0)/1024)} KB</small></div><div class="file-actions"><button class="btn small" onclick="TeacherDashboard.moveHomeworkFile(${i},-1)">↑</button><button class="btn small" onclick="TeacherDashboard.moveHomeworkFile(${i},1)">↓</button><button class="btn small red" onclick="TeacherDashboard.removeHomeworkFile(${i})">حذف</button></div></div>`).join('');box.innerHTML=ex+local||'<div class="muted">لا توجد مرفقات مختارة.</div>'}
function moveHomeworkFile(i,dir){const j=i+dir;if(j<0||j>=HOMEWORK_FILES.length)return;[HOMEWORK_FILES[i],HOMEWORK_FILES[j]]=[HOMEWORK_FILES[j],HOMEWORK_FILES[i]];renderHomeworkFilePreview()}
function removeHomeworkFile(i){const f=HOMEWORK_FILES.splice(i,1)[0];if(f&&f.preview)URL.revokeObjectURL(f.preview);renderHomeworkFilePreview();scheduleHomeworkAutosave()}
function resetHomeworkForm(){HOMEWORK_EDIT_ID=null;HOMEWORK_FILES.forEach(f=>f.preview&&URL.revokeObjectURL(f.preview));HOMEWORK_FILES=[];homeworkView()}
function loadHomeworkIntoForm(id){const h=DATA.homeworks.find(x=>String(x.id)===String(id));if(!h)return;$('#hwId').value=h.id;$('#hwSession').value=h.class_session_id||'';$('#hwSection').value=h.section_id||h.class_id||'';updateHomeworkSubjects();$('#hwSubject').value=h.subject_id||'';updateHomeworkCurriculumTopics();if($('#hwCurriculumSlot'))$('#hwCurriculumSlot').value=h.curriculum_slot_id||'';$('#hwTitle').value=h.title||'';$('#hwDescription').value=h.description||'';$('#hwDueDate').value=h.due_date||'';$('#hwDueTime').value=(h.due_time||'').slice(0,5)||'23:59';$('#hwMaxScore').value=h.max_score||10;$('#hwStatus').value=h.status||'draft';if(h.publish_at){const d=new Date(h.publish_at);d.setMinutes(d.getMinutes()-d.getTimezoneOffset());$('#hwPublishAt').value=d.toISOString().slice(0,16)}renderHomeworkFilePreview()}
function editHomework(id){HOMEWORK_EDIT_ID=id;HOMEWORK_FILES=[];show('homework')}
function scheduleHomeworkAutosave(){clearTimeout(HOMEWORK_AUTOSAVE_TIMER);HOMEWORK_AUTOSAVE_TIMER=setTimeout(()=>saveHomework(null,true),1200)}
async function uploadHomeworkFiles(homeworkId){let uploaded=0;for(let i=0;i<HOMEWORK_FILES.length;i++){const f=HOMEWORK_FILES[i].file;const safe=(f.name||'file').replace(/[^\w\.\-\u0600-\u06FF]+/g,'_');const path=`${ME.id}/${homeworkId}/${Date.now()}_${i}_${safe}`;const up=await client().storage.from('homework-attachments').upload(path,f,{upsert:false,contentType:f.type||undefined});if(up.error){console.warn('homework upload failed',up.error);try{await client().rpc('log_teacher_error',{p_module:'homework_upload',p_message:up.error.message,p_details:{file:f.name,homework_id:homeworkId}})}catch(_){ }continue}const {data,error}=await client().rpc('add_homework_attachment',{p_homework_id:homeworkId,p_file_name:f.name,p_file_type:f.type,p_file_size:f.size,p_storage_path:path,p_public_url:null,p_sort_order:i});if(error||data?.ok===false){console.warn('attachment metadata failed',error||data);continue}uploaded++}HOMEWORK_FILES.forEach(f=>f.preview&&URL.revokeObjectURL(f.preview));HOMEWORK_FILES=[];return uploaded}
async function saveHomework(statusOverride=null,autosave=false){
  const title=$('#hwTitle')?.value.trim();
  if(!title){if(!autosave){toast('تنبيه','اكتبي عنوان الواجب','red');setHwStatus('اكتبي عنوان الواجب','red')}return}
  const sectionId=$('#hwSection')?.value, subjectId=$('#hwSubject')?.value, sec=DATA.sectionMap.get(String(sectionId));
  if(!subjectId||!sec){if(!autosave){toast('تنبيه','اختاري الصف/الشعبة والمادة','red');setHwStatus('اختاري الصف/الشعبة والمادة','red')}return}
  const status=statusOverride||$('#hwStatus').value||'draft';
  if(autosave&&status!=='draft')return;
  if(!autosave)setHwStatus('جاري حفظ الواجب...','info');
  try{
    const {data,error}=await client().rpc('save_homework_pro',{p_homework_id:$('#hwId').value||null,p_session_id:$('#hwSession').value||null,p_title:title,p_description:$('#hwDescription').value||null,p_subject_id:subjectId,p_class_id:sec.class_id,p_section_id:sec.section_id||null,p_publish_at:$('#hwPublishAt').value?new Date($('#hwPublishAt').value).toISOString():null,p_due_date:$('#hwDueDate').value||null,p_due_time:$('#hwDueTime').value||null,p_max_score:Number($('#hwMaxScore').value||10),p_status:status});
    if(error)throw error;if(data&&data.ok===false){if(!autosave){toast('تعذر حفظ الواجب',data.message||'خطأ','red');setHwStatus(data.message||'تعذر الحفظ','red')}return}
    $('#hwId').value=data.homework_id;HOMEWORK_EDIT_ID=data.homework_id;
    const slotId=$('#hwCurriculumSlot')?.value||null;
    if(slotId||title){try{await client().rpc('link_homework_to_curriculum',{p_homework_id:data.homework_id,p_slot_id:slotId,p_custom_title:title,p_mark_given:status==='published'});}catch(e){console.warn('curriculum link failed',e)}}
    let uploaded=0;if(!autosave&&HOMEWORK_FILES.length)uploaded=await uploadHomeworkFiles(data.homework_id);
    if(!autosave){toast('تم حفظ الواجب',status==='published'?'تم النشر وإرسال الإشعارات':'تم حفظ الواجب','green');setHwStatus('تم حفظ الواجب بنجاح'+(uploaded?` ورفع ${uploaded} ملف`:''),'green');await load();homeworkView()}else{setHwStatus('تم الحفظ التلقائي للمسودة','green')}
  }catch(e){console.error('saveHomework failed',e);try{await client().rpc('log_teacher_error',{p_module:'homework_ui',p_message:e.message||String(e),p_details:{title}})}catch(_){ }if(!autosave){toast('تعذر حفظ الواجب',e.message||String(e),'red');setHwStatus('تعذر الحفظ: '+(e.message||String(e)),'red')}}
}
function homeworksList(list){return list.length?list.map(h=>{const atts=homeworkAttachmentsFor(h.id).length, grades=homeworkGradeCount(h.id), subs=homeworkSubmissionCount(h.id), rep=homeworkReportFor(h.id);return `<div class="item homework-item"><div><b>${esc(h.title)}</b><small>${esc(className(h.class_id))} · ${esc(subjectName(h.subject_id))} · التسليم ${esc(h.due_date||'—')} ${esc((h.due_time||'').slice(0,5))} · ${atts} مرفق · ${subs} تسليم · ${homeworkViewedCount(h.id)} مشاهدة · ${grades} درجة ${rep?`· الإنجاز ${rep.submitted_count||0}/${rep.assigned_count||0} · لم يسلم ${rep.missing_count||0}`:''}</small></div><div class="item-actions"><span class="badge ${h.status==='published'?'green':h.status==='closed'?'red':'blue'}">${esc(statusAr(h.status))}</span><button class="btn small" onclick="TeacherDashboard.viewHomeworkFollowup('${h.id}')">المتابعة</button><button class="btn small gold" onclick="TeacherDashboard.viewHomeworkSubmissions('${h.id}')">التسليمات</button>${h.status==='published'?`<button class="btn small red" onclick="TeacherDashboard.setHomeworkStatus('${h.id}','closed')">إغلاق</button>`:''}${h.status==='closed'?`<button class="btn small green" onclick="TeacherDashboard.setHomeworkStatus('${h.id}','published')">إعادة فتح</button>`:''}<button class="btn small blue" onclick="TeacherDashboard.editHomework('${h.id}')">تعديل</button><button class="btn small" onclick="TeacherDashboard.cloneHomework('${h.id}')">نسخ</button><button class="btn small red" onclick="TeacherDashboard.deleteHomeworkSafely('${h.id}')">حذف/أرشفة</button></div></div>`}).join(''):'<div class="empty">لا توجد واجبات بعد</div>'}
async function cloneHomework(id){
  const h=DATA.homeworks.find(x=>String(x.id)===String(id));
  const title=prompt('عنوان النسخة الجديدة:',(h?.title||'واجب')+' — نسخة');
  if(title===null)return;
  try{
    const {data,error}=await client().rpc('clone_homework_pro',{p_homework_id:id,p_new_title:title,p_status:'draft',p_copy_attachments:true});
    if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر النسخ');
    toast('تم النسخ','تم نسخ الواجب كمسودة جديدة','green');await load();homeworkView();
  }catch(e){toast('تعذر نسخ الواجب',e.message||String(e),'red')}
}
async function deleteHomeworkSafely(id){
  if(!confirm('سيتم حذف الواجب إذا لا يحتوي على بيانات طلاب، أو أرشفته إذا فيه تسليمات/درجات. متابعة؟'))return;
  try{
    const {data,error}=await client().rpc('delete_homework_safely',{p_homework_id:id});
    if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر الحذف/الأرشفة');
    toast('تم',data.message||'تمت العملية','green');await load();homeworkView();
  }catch(e){toast('تعذر حذف/أرشفة الواجب',e.message||String(e),'red')}
}
async function setHomeworkStatus(id,status){
  const label=status==='closed'?'إغلاق الواجب':status==='published'?'إعادة فتح الواجب':'تغيير الحالة';
  if(!confirm(label+'؟'))return;
  try{
    const {data,error}=await client().rpc('set_homework_status',{p_homework_id:id,p_status:status});
    if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر تغيير الحالة');
    toast('تم',data.message||'تم تغيير حالة الواجب','green');await load();homeworkView();
  }catch(e){toast('تعذر تغيير حالة الواجب',e.message||String(e),'red')}
}
function viewHomeworkFollowup(id){
  const h=DATA.homeworks.find(x=>String(x.id)===String(id));
  const r=homeworkReportFor(id)||{};
  const missing=homeworkMissingFor(id);
  const rows=missing.map(m=>`<tr><td>${esc(m.student_name||'—')}</td><td>${esc(m.class_name||'—')} ${m.section_code?' / '+esc(m.section_code):''}</td><td><span class="badge ${m.is_overdue?'red':'gold'}">${m.missing_status==='draft_only'?'مسودة فقط':'لم يسلم'}</span></td><td>${m.is_overdue?'متأخر':'قبل الموعد'}</td></tr>`).join('');
  $('#view-homework').innerHTML=`<div class="page-head"><div><h1>متابعة الواجب</h1><p>${esc(h?.title||'واجب')}</p></div><div class="top-actions"><button class="btn gold" onclick="TeacherDashboard.sendHomeworkReminders('${id}')">إرسال تذكير</button><button class="btn" onclick="TeacherDashboard.sendNotViewedReminders('${id}')">تذكير من لم يفتح</button><button class="btn blue" onclick="TeacherDashboard.markMissingZero('${id}',false)">معاينة تصفير</button><button class="btn red" onclick="TeacherDashboard.markMissingZero('${id}',true)">تصفير غير المسلّمين</button><button class="btn" onclick="TeacherDashboard.show('homework')">رجوع</button></div></div><div class="kpis"><div class="kpi gold"><small>المطلوب منهم</small><b>${r.assigned_count??0}</b></div><div class="kpi green"><small>سلّموا</small><b>${r.submitted_count??0}</b></div><div class="kpi red"><small>لم يسلموا</small><b>${r.missing_count??missing.length}</b></div><div class="kpi blue"><small>متوسط الدرجة</small><b>${r.average_grade_percent??'—'}%</b></div></div><div class="card"><div class="card-head"><h3>غير المسلّمين / مسودة فقط</h3></div><div class="card-body">${table(['الطالب','الصف/الشعبة','الحالة','الموعد'],rows,'كل الطلاب سلّموا الواجب')}</div></div>`;
}
async function markMissingZero(id,apply=false){
  if(apply&&!confirm('سيتم حفظ درجة 0 لكل الطلاب غير المسلّمين لهذا الواجب. متابعة؟'))return;
  try{
    const {data,error}=await client().rpc('mark_missing_homework_zero',{p_homework_id:id,p_apply:!!apply,p_feedback:'لم يتم تسليم الواجب'});
    if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر التنفيذ');
    toast(apply?'تم تصفير غير المسلّمين':'معاينة التصفير',`عدد المطابقين: ${data.matched_count||0} · تم الحفظ: ${data.graded_count||0}`,apply?'green':'blue');
    await load();viewHomeworkFollowup(id);
  }catch(e){toast('تعذر تصفير غير المسلّمين',e.message||String(e),'red')}
}
async function sendHomeworkReminders(id){
  try{
    const {data,error}=await client().rpc('send_homework_reminders',{p_homework_id:id});
    if(error)throw error;
    if(data&&data.ok===false)throw new Error(data.message||'تعذر إرسال التذكير');
    toast('تم إرسال التذكيرات','طلاب: '+(data?.students||0)+' · أولياء أمور: '+(data?.parents||0),'green');
    await load();viewHomeworkFollowup(id);
  }catch(e){toast('تعذر إرسال التذكير',e.message||String(e),'red')}
}
async function sendNotViewedReminders(id){
  try{const {data,error}=await client().rpc('send_homework_not_viewed_reminders',{p_homework_id:id});if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر التذكير');toast('تم إرسال تذكير من لم يفتح',`طلاب: ${data.students||0} · أولياء أمور: ${data.parents||0}`,'green');await load();viewHomeworkFollowup(id)}catch(e){toast('تعذر إرسال التذكير',e.message||String(e),'red')}
}
function submissionCommentsBox(s){const list=commentsForSubmission(s.submission_id);return `<div class="comments-box teacher-comments"><h4>تعليقات التسليم</h4>${list.map(c=>`<div class="comment-row ${String(c.author_id)===String(ME.id)?'mine':''}"><b>${esc(c.author_name||c.author_role||'مستخدم')}</b><p>${esc(c.comment_text)}</p><small>${esc(String(c.created_at||'').slice(0,16))}</small></div>`).join('')||'<div class="muted">لا توجد تعليقات</div>'}<div class="comment-form"><input id="teacherComment_${s.submission_id}" class="input" placeholder="تعليق للطالب"><button class="btn blue" onclick="TeacherDashboard.addSubmissionComment('${s.submission_id}')">إرسال تعليق</button></div></div>`}
async function addSubmissionComment(id){const input=$(`#teacherComment_${id}`);const txt=input?.value.trim();if(!txt){toast('تنبيه','اكتب التعليق أولاً','red');return}try{const {data,error}=await client().rpc('add_homework_submission_comment',{p_submission_id:id,p_comment_text:txt,p_is_internal:false});if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر إضافة التعليق');toast('تم','تم إرسال التعليق','green');if(input)input.value='';await load();const sub=(DATA.homeworkSubmissions||[]).find(s=>String(s.submission_id)===String(id));if(sub)viewHomeworkSubmissions(sub.homework_id)}catch(e){toast('تعذر إضافة التعليق',e.message||String(e),'red')}}
function viewHomeworkSubmissions(id){
  const h=DATA.homeworks.find(x=>String(x.id)===String(id));
  const list=(DATA.homeworkSubmissions||[]).filter(s=>String(s.homework_id)===String(id));
  const rows=list.map(s=>`<div class="submission-review-card ${s.submission_status||'none'}"><div><h4>${esc(s.student_name||'طالب')}</h4><small>${esc(statusArSubmission(s.submission_status))} · ${s.submitted_at?esc(String(s.submitted_at).slice(0,16)):'لم يسلم'} · مرفقات: ${s.submission_attachment_count||0}</small></div><p>${esc(s.answer_text||'لا توجد إجابة نصية')}</p>${s.submission_id?`<div class="homework-attachments-list">${submissionAttachmentsFor(s.submission_id).map(submissionAttachmentChip).join('')||'<span class="muted">لا توجد مرفقات محفوظة</span>'}</div>${submissionCommentsBox(s)}`:''}<div class="manual-grade-row"><input id="subScore_${s.submission_id}" class="input" type="number" min="0" max="${esc(h?.max_score||10)}" step="0.25" placeholder="درجة من ${esc(h?.max_score||10)}" value="${s.grade_score??''}" ${s.submission_id?'':'disabled'}><input id="subFeedback_${s.submission_id}" class="input" placeholder="ملاحظة للطالب" value="${esc(s.grade_feedback||s.teacher_feedback||'')}" ${s.submission_id?'':'disabled'}><button class="btn gold" ${s.submission_id?'':'disabled'} onclick="TeacherDashboard.gradeSubmission('${s.submission_id}')">حفظ التصحيح</button><button class="btn" ${s.submission_id?'':'disabled'} onclick="TeacherDashboard.returnSubmission('${s.submission_id}')">إرجاع للتعديل</button></div></div>`).join('');
  $('#view-homework').innerHTML=`<div class="page-head"><div><h1>تسليمات الواجب</h1><p>${esc(h?.title||'واجب')}</p></div><button class="btn" onclick="TeacherDashboard.show('homework')">رجوع للواجبات</button></div><div class="card"><div class="card-body"><div class="submission-review-list">${rows||'<div class="empty">لا توجد تسليمات بعد</div>'}</div></div></div>`;
}
function statusArSubmission(s){return ({draft:'مسودة',submitted:'مسلّم',late:'متأخر',graded:'مصحح',returned:'معاد'}[s]||'لم يسلم')}
async function openSubmissionAttachment(path,name){try{const {data,error}=await client().storage.from('homework-submissions').createSignedUrl(path,3600);if(error)throw error;const a=document.createElement('a');a.href=data.signedUrl;a.target='_blank';a.download=name||'attachment';document.body.appendChild(a);a.click();a.remove()}catch(e){toast('تعذر فتح مرفق التسليم',e.message||String(e),'red')}}
async function returnSubmission(id){const feedback=prompt('سبب الإرجاع أو ملاحظة للطالب:')||'';try{const {data,error}=await client().rpc('return_homework_submission',{p_submission_id:id,p_feedback:feedback});if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر الإرجاع');toast('تم الإرجاع','تم إشعار الطالب وولي الأمر','green');await load();const sub=(DATA.homeworkSubmissions||[]).find(s=>String(s.submission_id)===String(id));if(sub)viewHomeworkSubmissions(sub.homework_id)}catch(e){toast('تعذر إرجاع التسليم',e.message||String(e),'red')}}
async function gradeSubmission(id){const score=Number($(`#subScore_${id}`)?.value||0);const feedback=$(`#subFeedback_${id}`)?.value||null;try{const {data,error}=await client().rpc('review_homework_submission',{p_submission_id:id,p_score:score,p_feedback:feedback});if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر التصحيح');toast('تم التصحيح','تم حفظ درجة التسليم وإشعار الطالب','green');await load();const sub=(DATA.homeworkSubmissions||[]).find(s=>String(s.submission_id)===String(id));if(sub)viewHomeworkSubmissions(sub.homework_id)}catch(e){toast('تعذر التصحيح',e.message||String(e),'red')}}
async function homeworkForSession(id){HOMEWORK_EDIT_ID=null;HOMEWORK_FILES=[];show('homework');setTimeout(()=>{$('#hwSession').value=id;updateHomeworkSessionMeta();$('#hwTitle').focus()},80)}

function planView(){
  const today=iso();
  const upcoming=DATA.sessions.filter(s=>s.session_date>=today&&s.status!=='holiday').slice(0,12);
  const options=upcoming.map(s=>`<option value="${s.id}">${esc(s.session_date)} — ${esc(className(s.class_id))} — ${esc(subjectName(s.subject_id))} — الحصة ${s.period_number}</option>`).join('');
  const recent=DATA.lessonPlans.slice(0,8).map(p=>`<div class="item"><div><b>${esc(p.title)}</b><small>${esc(String(p.created_at||'').slice(0,10))} · ${esc(p.status||'prepared')}</small></div><span class="badge green">محضر</span></div>`).join('')||'<div class="empty">لا توجد تحضيرات محفوظة بعد</div>';
  $('#view-plan').innerHTML=`<div class="page-head"><div><h1>تحضير الدروس</h1><p>حضّري الدرس من حصة فعلية. حفظ التحضير يثبت نشاط المعلمة للحصة.</p></div></div><div class="cards"><div class="card"><div class="card-head"><h3>تحضير سريع</h3></div><div class="card-body"><div class="teacher-toolbar"><div class="field" style="min-width:260px"><label>الحصة</label><select id="planSession" class="select">${options||'<option value="">لا توجد حصص قادمة</option>'}</select></div></div><div class="grade-grid" style="grid-template-columns:1fr"><input id="planTitle" class="input" placeholder="عنوان الدرس"><textarea id="planObjectives" class="input" placeholder="أهداف الدرس"></textarea><textarea id="planSummary" class="input" placeholder="ملخص الشرح"></textarea><input id="planResources" class="input" placeholder="مصادر أو روابط أو ملفات"><input id="planHomeworkHint" class="input" placeholder="فكرة واجب مرتبطة بالدرس"><button class="btn gold" onclick="TeacherDashboard.saveLessonPlan()">حفظ التحضير وتثبيت الحصة</button></div><div id="planStatus" class="alert info" style="display:none;margin-top:12px"></div></div></div><div class="card"><div class="card-head"><h3>آخر التحضيرات</h3></div><div class="card-body"><div class="list">${recent}</div></div></div></div>`;
}
function startPlanFromSession(id){show('plan');setTimeout(()=>{if($('#planSession'))$('#planSession').value=id;},50)}
function setPlanStatus(msg,type='info'){const el=$('#planStatus');if(!el)return;el.className='alert '+(type==='red'?'error':type==='green'?'success':'info');el.textContent=msg;el.style.display='block'}
async function saveLessonPlan(){
  const id=$('#planSession')?.value;
  if(!id){toast('تنبيه','اختاري الحصة أولاً','red');setPlanStatus('اختاري الحصة أولاً','red');return}
  const title=$('#planTitle')?.value.trim();
  if(!title){toast('تنبيه','اكتبي عنوان الدرس','red');setPlanStatus('اكتبي عنوان الدرس','red');return}
  const btn=document.activeElement; if(btn)btn.disabled=true;
  setPlanStatus('جاري حفظ التحضير...','info');
  try{
    const {data,error}=await client().rpc('save_lesson_plan',{p_session_id:id,p_title:title,p_objectives:$('#planObjectives')?.value||null,p_lesson_summary:$('#planSummary')?.value||null,p_resources:$('#planResources')?.value||null,p_homework_hint:$('#planHomeworkHint')?.value||null});
    if(error)throw error;
    if(data&&data.ok===false){toast('تعذر الحفظ',data.message||'خطأ','red');setPlanStatus(data.message||'تعذر الحفظ','red');return}
    toast('تم حفظ التحضير','تم تثبيت نشاط الحصة للمعلمة','green');
    setPlanStatus('تم حفظ التحضير وتثبيت نشاط الحصة بنجاح','green');
    await load();
    planView();
  }catch(e){toast('تعذر حفظ التحضير',e.message+' — شغّلي SQL 30','red');setPlanStatus('تعذر حفظ التحضير: '+e.message,'red')}
  finally{if(btn)btn.disabled=false}
}

function publishedHomeworks(sectionId='',subjectId=''){
  return DATA.homeworks.filter(h=>h.status==='published' && (!sectionId||String(h.section_id||h.class_id)===String(sectionId)) && (!subjectId||String(h.subject_id)===String(subjectId)));
}
function selectedHomework(){return DATA.homeworks.find(h=>String(h.id)===String($('#gradeHomework')?.value||''))}
function gradeMax(){const mode=$('#gradeMode')?.value||'continuous';if(mode==='continuous')return 10;if(mode==='homework')return Number(selectedHomework()?.max_score||10);return 100}
function gradeLabel(){return 'الدرجة من '+gradeMax()}
function homeworkGradeFor(hwId,studentId){return DATA.homeworkGrades.find(g=>String(g.homework_id)===String(hwId)&&String(g.student_id)===String(studentId))}
function gradesView(){const first=DATA.sections[0];$('#view-grades').innerHTML=`<div class="page-head"><div><h1>إدخال الدرجات</h1><p>درجات الواجبات لا تُقبل إلا لواجب منشور. يوجد حفظ تلقائي أثناء الإدخال.</p></div></div><div class="card"><div class="card-body"><div class="teacher-toolbar"><div class="field"><label>الصف / الشعبة</label><select id="gradeSection" class="select" onchange="TeacherDashboard.refreshGradeGrid()">${sectionOptions()}</select></div><div class="field"><label>المادة</label><select id="gradeSubject" class="select" onchange="TeacherDashboard.refreshGradeGrid(false)"></select></div><div class="field"><label>نوع الإدخال</label><select id="gradeMode" class="select" onchange="TeacherDashboard.refreshGradeGrid(false)"><option value="homework">درجة واجب منشور</option><option value="continuous">تقييم يومي / مستمر من 10</option><option value="exam">اختبار شهري من 100</option></select></div><div class="field" id="homeworkSelectWrap" style="display:none"><label>الواجب المنشور</label><select id="gradeHomework" class="select" onchange="TeacherDashboard.refreshGradeGrid(false)"></select></div><button class="btn gold" onclick="TeacherDashboard.refreshGradeGrid(false)">تحميل الطلاب</button></div><div class="bulk-tools"><input id="bulkScore" class="input" type="number" min="0" max="10" placeholder="درجة موحدة"><button class="btn blue" onclick="TeacherDashboard.fillAllScores()">تطبيق على الكل</button><select id="contComponent" class="select"><option value="participation">مشاركة</option><option value="homework">واجب</option><option value="activity">نشاط</option><option value="project">مشروع</option><option value="discipline">انضباط</option><option value="quiz">اختبار قصير</option></select><input id="examName" class="input" value="الاختبار الأول" placeholder="اسم الاختبار"></div><div class="teacher-note" id="gradeModeHint">اختاري واجباً منشوراً لإدخال الدرجات.</div><div id="gradeGrid"></div><div id="gradeSaveStatus" class="alert info" style="display:none;margin:12px 0"></div><button id="saveGradesBtn" class="btn gold" onclick="TeacherDashboard.saveGrades()">حفظ الدرجات للجميع</button></div></div>`;if(first){$('#gradeSection').value=first.section_id||first.class_id;refreshGradeGrid()}}
function refreshGradeGrid(resetSubject=true){
  const sectionId=$('#gradeSection')?.value||'';
  const prevSub=$('#gradeSubject')?.value||'';
  const subjIds=[...new Set(scheduleForSection(sectionId).map(s=>String(s.subject_id)))];
  const subjectList=DATA.subjects.filter(s=>!subjIds.length||subjIds.includes(String(s.id)));
  $('#gradeSubject').innerHTML='<option value="">المادة</option>'+subjectList.map(s=>`<option value="${s.id}">${esc(s.name)}</option>`).join('');
  if(!resetSubject&&prevSub)$('#gradeSubject').value=prevSub;
  const sub=$('#gradeSubject')?.value||'';
  const mode=$('#gradeMode')?.value||'homework';
  const prevHw=$('#gradeHomework')?.value||'';
  const wrap=$('#homeworkSelectWrap');if(wrap)wrap.style.display=mode==='homework'?'block':'none';
  if(mode==='homework'){
    const list=publishedHomeworks(sectionId,sub);
    $('#gradeHomework').innerHTML='<option value="">اختاري واجباً منشوراً</option>'+list.map(h=>`<option value="${h.id}">${esc(h.title)} — ${esc(h.due_date||'بدون تاريخ')} — من ${esc(h.max_score||10)}</option>`).join('');
    if(prevHw&&list.some(h=>String(h.id)===String(prevHw)))$('#gradeHomework').value=prevHw;
  }
  const hw=selectedHomework();
  const max=gradeMax();
  $('#bulkScore').max=max;$('#bulkScore').placeholder='درجة موحدة من '+max;
  $('#contComponent').style.display=mode==='continuous'?'inline-flex':'none';
  $('#examName').style.display=mode==='exam'?'inline-flex':'none';
  $('#gradeModeHint').textContent=mode==='homework'?(hw?'يتم الحفظ التلقائي لكل درجة. لا يمكن الحفظ إلا لأن الواجب منشور.':'لا تظهر إلا الواجبات المنشورة لهذه المادة والشعبة.'):(mode==='continuous'?'التقييم اليومي من 10.':'الاختبار الشهري من 100.');
  const students=studentsForSection(sectionId);
  if(mode==='homework'&&!hw){$('#gradeGrid').innerHTML='<div class="empty">اختاري واجباً منشوراً أولاً. المسودات والمغلقة لا تقبل درجات.</div>';return}
  const rows=students.map(s=>{const g=mode==='homework'?homeworkGradeFor(hw.id,s.id):null;return `<div class="grade-grid" data-student="${s.id}"><b>${esc(fullName(s))}</b><input class="input score-input" type="number" min="0" max="${max}" placeholder="${gradeLabel()}" value="${g?.score??''}"><input class="input note-input" placeholder="ملاحظة" value="${esc(g?.feedback||'')}"><small class="grade-row-status muted">${g?'محفوظ':'غير محفوظ'}</small></div>`}).join('');
  $('#gradeGrid').innerHTML=rows||'<div class="empty">لا يوجد طلاب لهذه الشعبة</div>';
  if(mode==='homework')bindHomeworkGradeAutosave();
}
function fillAllScores(){const v=$('#bulkScore').value;$$('.score-input').forEach(i=>{i.value=v;i.dispatchEvent(new Event('input',{bubbles:true}))});setGradeStatus('تم تطبيق الدرجة على كل الطلاب الظاهرين','green')}
function setGradeStatus(msg,type='info'){const el=$('#gradeSaveStatus');if(!el)return;el.className='alert '+(type==='red'?'error':type==='green'?'success':'info');el.textContent=msg;el.style.display='block'}
function bindHomeworkGradeAutosave(){
  $$('#gradeGrid .grade-grid').forEach(row=>{
    const fn=()=>scheduleHomeworkGradeSave(row);
    $('.score-input',row)?.addEventListener('input',fn);
    $('.note-input',row)?.addEventListener('input',fn);
  });
}
function scheduleHomeworkGradeSave(row){
  const sid=row.dataset.student;clearTimeout(GRADE_AUTOSAVE_TIMERS.get(sid));
  $('.grade-row-status',row).textContent='جاري الحفظ التلقائي...';
  GRADE_AUTOSAVE_TIMERS.set(sid,setTimeout(()=>saveHomeworkGradeRow(row,true),900));
}
async function saveHomeworkGradeRow(row,autosave=false){
  const hw=selectedHomework();
  const statusEl=$('.grade-row-status',row);
  if(!hw||hw.status!=='published'){
    if(statusEl){statusEl.textContent='اختاري واجباً منشوراً';statusEl.className='grade-row-status error'}
    if(!autosave)toast('غير مسموح','اختاري واجباً منشوراً فقط','red');
    return false;
  }
  const raw=$('.score-input',row).value;
  if(raw===''){if(statusEl){statusEl.textContent='غير محفوظ';statusEl.className='grade-row-status muted'}return false}
  const score=num(raw), max=Number(hw.max_score||10);
  if(score<0||score>max){if(statusEl){statusEl.textContent='درجة خارج المدى 0 - '+max;statusEl.className='grade-row-status error'}return false}
  if(statusEl){statusEl.textContent='جاري الحفظ...';statusEl.className='grade-row-status saving'}
  try{
    const rpc=client().rpc('save_homework_grade',{p_homework_id:hw.id,p_student_id:row.dataset.student,p_score:score,p_feedback:$('.note-input',row).value||null});
    const {data,error}=await withTimeout(rpc,15000,'حفظ درجة الواجب');
    if(error)throw error;
    if(data&&data.ok===false)throw new Error(data.message||'تعذر الحفظ من قاعدة البيانات');
    if(statusEl){statusEl.textContent='تم الحفظ الآن';statusEl.className='grade-row-status saved'}
    return true;
  }catch(e){
    console.error('homework grade save failed',e);
    const msg=e.message||String(e)||'فشل الحفظ';
    if(statusEl){statusEl.textContent=msg.includes('function')?'شغّلي SQL 40':('فشل: '+msg.slice(0,80));statusEl.className='grade-row-status error'}
    try{await client().rpc('log_teacher_error',{p_module:'homework_grade_ui',p_message:msg,p_details:{homework_id:hw.id,student_id:row.dataset.student,score}})}catch(_){ }
    if(!autosave)toast('تعذر حفظ درجة الواجب',msg,'red');
    return false;
  }
}
async function saveGrades(){
  const sectionId=$('#gradeSection')?.value;
  const sub=$('#gradeSubject')?.value;
  const mode=$('#gradeMode')?.value;
  const sec=DATA.sectionMap.get(String(sectionId));
  if(!sectionId){toast('تنبيه','اختاري الشعبة أولاً','red');setGradeStatus('اختاري الشعبة أولاً','red');return}
  if(!sub&&mode!=='homework'){toast('تنبيه','اختاري المادة أولاً','red');setGradeStatus('اختاري المادة أولاً','red');return}
  if(mode==='homework'&&!selectedHomework()){toast('تنبيه','اختاري واجباً منشوراً أولاً','red');setGradeStatus('اختاري واجباً منشوراً أولاً','red');return}
  const rows=$$('#gradeGrid .grade-grid');
  if(!rows.length){toast('لا يوجد طلاب','لا يوجد طلاب ظاهرون للحفظ في هذه الشعبة','red');setGradeStatus('لا يوجد طلاب ظاهرون للحفظ في هذه الشعبة','red');return}
  const entered=rows.filter(r=>$('.score-input',r).value!=='');
  if(!entered.length){toast('لا توجد درجات','أدخلي درجة واحدة على الأقل أو استخدمي تطبيق على الكل','red');setGradeStatus('أدخلي درجة واحدة على الأقل أو استخدمي تطبيق على الكل','red');return}
  const btn=$('#saveGradesBtn'), oldText=btn?btn.textContent:'';if(btn){btn.disabled=true;btn.textContent='جاري حفظ الدرجات...'}setGradeStatus('جاري حفظ الدرجات...','info');
  let saved=0,errors=0,skipped=0;
  try{
    if(mode==='homework'){
      for(const r of rows){if($('.score-input',r).value===''){skipped++;continue}const ok=await saveHomeworkGradeRow(r,false);ok?saved++:errors++}
    }else if(mode==='continuous'){
      for(const r of rows){const raw=$('.score-input',r).value;if(raw===''){skipped++;continue}const score=num(raw);if(score<0||score>10){errors++;continue}const {data,error}=await client().rpc('save_continuous_assessment_safe',{p_student_id:r.dataset.student,p_class_id:sec.class_id,p_subject_id:sub,p_component_type:$('#contComponent').value,p_score:score,p_max_score:10,p_notes:$('.note-input',r).value||null,p_class_session_id:null});if(error||data?.ok===false){console.warn('continuous save error',error||data);errors++}else saved++}
    }else{
      const {data:exam,error:e1}=await client().from('exams').insert({class_id:sec.class_id,subject_id:sub,teacher_id:ME.id,exam_name:$('#examName').value||'اختبار شهري',exam_type:'monthly',exam_date:iso(),max_score:100}).select().single();if(e1)throw e1;
      for(const r of rows){const raw=$('.score-input',r).value;if(raw===''){skipped++;continue}const score=num(raw);if(score<0||score>100){errors++;continue}const {error}=await client().from('exam_scores').upsert({exam_id:exam.id,student_id:r.dataset.student,score,entered_by:ME.id},{onConflict:'exam_id,student_id'});if(error){console.warn('exam score save error',error);errors++}else saved++}
    }
    if(saved>0&&errors===0){toast('تم حفظ الدرجات','تم حفظ '+saved+' درجة بنجاح','green');setGradeStatus('تم حفظ '+saved+' درجة بنجاح. تم تجاهل '+skipped+' طالب بدون درجة.','green')}
    else if(saved>0){toast('تم الحفظ مع أخطاء','تم حفظ '+saved+' درجة، وفشل '+errors,'red');setGradeStatus('تم حفظ '+saved+' درجة، وفشل '+errors+'.','red')}
    else{toast('لم يتم حفظ أي درجة','تحققي من الصلاحيات أو القيم المدخلة','red');setGradeStatus('لم يتم حفظ أي درجة.','red')}
    await load();show('grades');
  }catch(e){console.error('saveGrades failed',e);try{await client().rpc('log_teacher_error',{p_module:'saveGrades',p_message:e.message||String(e),p_details:{mode}})}catch(_){ }toast('تعذر حفظ الدرجات',e.message||'حدث خطأ غير معروف','red');setGradeStatus('تعذر حفظ الدرجات: '+(e.message||'حدث خطأ غير معروف'),'red')}
  finally{if(btn){btn.disabled=false;btn.textContent=oldText||'حفظ الدرجات للجميع'}}
}

function startGradesFromSession(id){
  const s=sessionById(id);
  if(!s){toast('تنبيه','لم يتم العثور على الحصة','red');return;}
  show('grades');
  setTimeout(()=>{
    const sectionValue=s.section_id||s.class_id||'';
    if($('#gradeSection')) $('#gradeSection').value=sectionValue;
    refreshGradeGrid();
    setTimeout(()=>{
      if($('#gradeSubject')) $('#gradeSubject').value=s.subject_id||'';
      if($('#gradeMode')) $('#gradeMode').value='continuous';
      refreshGradeGrid();
      setTimeout(()=>{ if($('#gradeSubject')) $('#gradeSubject').value=s.subject_id||''; },30);
    },40);
  },40);
}


function openCounselingReferral(studentId){
  const st=DATA.studentMap.get(String(studentId));
  if(!st){toast('تنبيه','لم يتم العثور على الطالب','red');return}
  const reason=prompt('ملاحظة مختصرة للمرشد حول '+fullName(st)+' — ستظهر ضمن برنامج تطوير المهارات والمتابعة التربوية:');
  if(reason===null)return;
  const urgency=confirm('هل الإحالة عاجلة وتحتاج متابعة قريبة؟')?'high':'followup';
  saveCounselingReferral(studentId,urgency,reason||'إحالة للمتابعة التربوية من المعلم');
}
async function saveCounselingReferral(studentId,urgency,reason){
  try{
    const {data,error}=await client().rpc('counseling_quick_referral',{p_student_id:studentId,p_urgency:urgency,p_concern:reason});
    if(error)throw error;
    if(data&&data.ok===false)throw new Error(data.message||'تعذر إرسال الإحالة');
    toast('تم إرسال الإحالة',data.message||'تم إرسالها للمرشد','green');
  }catch(e){toast('تعذر إرسال الإحالة',e.message||String(e),'red')}
}

function studentsView(){const rows=DATA.students.map(s=>`<tr><td>${esc(fullName(s))}</td><td>${esc(sectionLabel(s))}</td><td>${esc(s.gender||'—')}</td><td><button class="btn small gold" onclick="TeacherDashboard.openCounselingReferral('${s.id}')">إحالة للبرنامج</button></td></tr>`);$('#view-students').innerHTML=`<div class="page-head"><div><h1>طلابي</h1><p>لا تظهر هنا إلا الشعب المرتبطة بجدولك. الإحالة تستخدم الاسم المحايد: برنامج تطوير المهارات والمتابعة التربوية.</p></div></div>${table(['الطالب','الصف / الشعبة','الجنس','برنامج التطوير'],rows)}`}
function scheduleView(){const rows=DATA.schedule.map(r=>`<tr><td>${esc(DAYS[r.day]||'—')}</td><td>${r.period_number}</td><td>${esc(r.section_name||r.class_name||'—')}</td><td>${esc(r.subject_name||subjectName(r.subject_id))}</td></tr>`);$('#view-schedule').innerHTML=`<div class="page-head"><div><h1>جدولي</h1></div></div>${table(['اليوم','الحصة','الصف / الشعبة','المادة'],rows)}`}
function bind(){ $$('.nav button[data-view]').forEach(b=>b.addEventListener('click',()=>show(b.dataset.view)));$('#mobileMenuBtn')?.addEventListener('click',()=>$('#sidebar').classList.toggle('open'));$('#logoutBtn').addEventListener('click',async()=>{await client().auth.signOut({scope:'local'});location.href='index.html'})}
async function reload(){await load()}async function init(){client();if(!await ensure())return;bind();await load();show('overview')}
window.TeacherDashboard={init,show,reload,refreshAttendanceForm,markAllPresent,saveAttendance,confirmSession,homeworkForSession,updateHomeworkSessionMeta,updateHomeworkSubjects,updateHomeworkCurriculumTopics,onHomeworkCurriculumChange,addHomeworkFiles,moveHomeworkFile,removeHomeworkFile,resetHomeworkForm,editHomework,saveHomework,cloneHomework,deleteHomeworkSafely,setHomeworkStatus,viewHomeworkFollowup,markMissingZero,sendHomeworkReminders,sendNotViewedReminders,addSubmissionComment,viewHomeworkSubmissions,openSubmissionAttachment,returnSubmission,gradeSubmission,refreshGradeGrid,fillAllScores,saveGrades,startAttendanceFromSession,startGradesFromSession,startPlanFromSession,saveLessonPlan,openCounselingReferral,saveCounselingReferral};
}());
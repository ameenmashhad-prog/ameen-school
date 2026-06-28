/* Schedule Manager — unified aSc import, manual editing, calendar/holiday aware print */
(function(){
'use strict';

const cfg=()=>window.AMIN_CONFIG||{};
let sb=null, ME=null, DATA=null, IMPORT=null;
const DAYS=['السبت','الأحد','الاثنين','الثلاثاء','الأربعاء'];
const DEFAULT_PERIODS=[1,2,3,4,5,6,7,8];
const DEFAULT_TIME_PROFILES={
  primary:{label:'المرحلة الابتدائية',start:'12:45',periods:5,duration:45,break:10},
  secondary:{label:'المتوسطة والإعدادية',start:'13:00',periods:3,duration:75,break:10}
};

const $=(s,r=document)=>r.querySelector(s);
const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
function esc(v){return String(v==null?'':v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#039;')}
function toast(t,m,type=''){const el=$('#toast');if(!el)return;el.innerHTML=`<b>${esc(t)}</b><br><span class="muted">${esc(m||'')}</span>`;el.className='toast show '+type;clearTimeout(el._t);el._t=setTimeout(()=>el.classList.remove('show'),4500)}
function client(){if(sb)return sb; sb=window.supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});return sb}
function normClass(v){return String(v||'').replace(/[إأآا]/g,'ا').replace(/[ىي]/g,'ي').replace(/ة/g,'ه').replace(/\s+/g,'').toLowerCase()}
function classStageOrder(c){const n=normClass(c.name);if(n.includes('ابتدائي'))return 1;if(n.includes('متوسط'))return 2;if(n.includes('اعدادي'))return 3;return 9}
function classGradeOrder(c){const n=normClass(c.name);const m=[['الاول',1],['اول',1],['الثاني',2],['ثاني',2],['الثالث',3],['ثالث',3],['الرابع',4],['رابع',4],['الخامس',5],['خامس',5],['السادس',6],['سادس',6]].find(([k])=>n.includes(k));return m?m[1]:99}
function sortClasses(list){return (list||[]).slice().sort((a,b)=>(classStageOrder(a)-classStageOrder(b))||(classGradeOrder(a)-classGradeOrder(b))||String(a.name).localeCompare(String(b.name),'ar'))}
function norm(v){return String(v||'').trim().replace(/[إأآا]/g,'ا').replace(/[ىي]/g,'ي').replace(/ة/g,'ه').replace(/[\u064B-\u065F\u0670]/g,'').replace(/\s+/g,' ').toLowerCase()}
function splitIds(v){return String(v||'').split(/[,;]/).map(x=>x.trim()).filter(Boolean)}
async function q(table,opts={}){try{let query=client().from(table).select(opts.columns||'*');(opts.filters||[]).forEach(f=>query=query[f.op](f.col,f.val));if(opts.order)query=query.order(opts.order,{ascending:opts.ascending!==false});if(opts.limit)query=query.limit(opts.limit);const {data,error}=await query;if(error){console.warn(table,error);return[]}return data||[]}catch(e){console.warn(table,e);return[]}}

async function ensureAuth(){
  const {data:{session}}=await client().auth.getSession();
  if(!session){location.href='index.html';return false}
  const {data:u}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();
  ME=u;if(!u){location.href='index.html';return false}
  const ok=u.is_super_admin||['admin','academic','academic_admin','scientific','academic_supervisor','supervisor'].includes(u.role);
  if(!ok){toast('ليست لديك صلاحية','إدارة الجدول متاحة للإدارة أو المسؤول العلمي فقط','red');return false}
  $('#profileName').textContent=u.name||u.email||'مستخدم';$('#profileRole').textContent=u.role||'—';return true;
}

async function loadData(){
  let [classes,subjects,teachers,periods,schedule,students,sections,assignments,settings,holidays,holidayDefinitions,holidayCandidates,classSessions,payrollPreview]=await Promise.all([
    q('classes',{order:'name'}),q('subjects',{order:'name'}),q('users',{filters:[{op:'eq',col:'role',val:'teacher'}],order:'name'}),
    q('academic_periods'),q('weekly_schedule'),q('students',{order:'name'}),q('sections'),q('teacher_assignments'),q('school_calendar_settings',{limit:1}),q('school_holidays',{order:'holiday_date'}),
    q('school_holiday_definitions',{order:'month_no'}),q('school_holiday_candidates',{order:'date_gregorian'}),q('class_sessions',{order:'session_date'}),q('v_teacher_payroll_preview')
  ]);
  classes=sortClasses(classes);DATA={classes,subjects,teachers,periods,schedule,students,sections:sections||[],assignments:assignments||[],settings:settings[0]||null,holidays:holidays||[],holidayDefinitions:holidayDefinitions||[],holidayCandidates:holidayCandidates||[],classSessions:classSessions||[],payrollPreview:payrollPreview||[],classMap:new Map(classes.map(x=>[String(x.id),x])),subjectMap:new Map(subjects.map(x=>[String(x.id),x])),teacherMap:new Map(teachers.map(x=>[String(x.id),x])),studentMap:new Map(students.map(x=>[String(x.id),x])),sectionMap:new Map((sections||[]).map(x=>[String(x.id),x])),assignmentMap:new Map((assignments||[]).map(x=>[String(x.id),x]))};
  fillAllSelects();renderCalendarPanel();renderHolidayCandidates();
}

function todayISO(){return new Date().toISOString().slice(0,10)}
function addDaysISO(iso,days){const d=new Date((iso||todayISO())+'T00:00:00');d.setDate(d.getDate()+days);return d.toISOString().slice(0,10)}
function settings(){return DATA&&DATA.settings?DATA.settings:{}}
function timeProfiles(){const s=settings().schedule_time_settings||{};return {primary:Object.assign({},DEFAULT_TIME_PROFILES.primary,s.primary||{}),secondary:Object.assign({},DEFAULT_TIME_PROFILES.secondary,s.secondary||{})}}
function weekStartISO(){return $('#weekStart')?.value || settings().academic_year_start_date || '2026-09-01'}
function holidayForDate(iso){return (DATA.holidays||[]).find(h=>h.holiday_date===iso || (h.is_recurring&&h.holiday_date&&h.holiday_date.slice(5)===iso.slice(5)))}
function dayDate(day){return addDaysISO(weekStartISO(),day)}
function dayHeader(day){const date=dayDate(day);const h=holidayForDate(date);return `<th>${DAYS[day]}<br><small>${date}</small>${h?`<br><span class="badge red">${esc(h.name)}</span>`:''}</th>`}
function renderCalendarPanel(){
  if(!$('#academicYearStart'))return;
  const s=settings(), t=timeProfiles();
  $('#academicYearStart').value=s.academic_year_start_date||'2026-09-01';
  $('#weekStart').value=$('#weekStart').value||s.academic_year_start_date||'2026-09-01';
  $('#primaryStart').value=t.primary.start; $('#primaryDuration').value=t.primary.duration; $('#primaryBreak').value=t.primary.break;
  $('#secondaryStart').value=t.secondary.start; $('#secondaryDuration').value=t.secondary.duration; $('#secondaryBreak').value=t.secondary.break;
  $('#holidaysBox').innerHTML=(DATA.holidays||[]).map(h=>`<div class="item"><div><b>${esc(h.name)}</b><small>${esc(h.holiday_date)} · ${esc(h.holiday_type||'official')}${h.is_recurring?' · سنوية':''}</small></div><span class="badge red">عطلة</span></div>`).join('')||'<div class="empty">لا توجد عطل مسجلة بعد</div>';
}
async function saveCalendarSettings(){
  const payload={id:'main',academic_year:'2026-2027',academic_year_start_date:$('#academicYearStart').value||'2026-09-01',schedule_time_settings:{primary:{start:$('#primaryStart').value||'12:45',duration:Number($('#primaryDuration').value||45),break:Number($('#primaryBreak').value||10)},secondary:{start:$('#secondaryStart').value||'13:00',duration:Number($('#secondaryDuration').value||75),break:Number($('#secondaryBreak').value||10)}},updated_by:ME&&ME.id};
  const {error}=await client().from('school_calendar_settings').upsert(payload,{onConflict:'id'});
  if(error){toast('تعذر الحفظ',error.message+' — شغّلي SQL إعدادات التقويم','red');return}
  toast('تم الحفظ','تم تحديث بداية العام وأوقات الدوام','green');await loadData();
}
async function addHoliday(){
  const name=$('#holidayName').value.trim(), date=$('#holidayDate').value;
  if(!name||!date){toast('تنبيه','أدخلي اسم العطلة وتاريخها','red');return}
  const payload={name,holiday_date:date,holiday_type:$('#holidayType').value||'official',is_recurring:$('#holidayRecurring').value==='true',source:'manual'};
  const {error}=await client().from('school_holidays').insert(payload);
  if(error){toast('تعذر إضافة العطلة',error.message+' — شغّلي SQL إعدادات التقويم','red');return}
  $('#holidayName').value='';$('#holidayDate').value='';toast('تمت الإضافة','سيظهر يوم العطلة في الجداول المطبوعة','green');await loadData();
}

function canonicalPeriods(){const first=DATA.periods.find(p=>String(p.name||'').includes('الأول')||String(p.name||'').includes('الاول'))||DATA.periods[0];const second=DATA.periods.find(p=>String(p.name||'').includes('الثاني')||String(p.name||'').includes('ثاني'))||DATA.periods.find(p=>p.id!==first?.id);return [first&&{id:first.id,name:'الفصل الدراسي الأول 2026/2027'},second&&{id:second.id,name:'الفصل الدراسي الثاني 2026/2027'}].filter(Boolean)}
function periodOptions(){const p=canonicalPeriods().length?canonicalPeriods():[{id:'',name:'الفصل الحالي'}];return p.map(x=>`<option value="${esc(x.id)}">${esc(x.name||x.title||'فترة')}</option>`).join('')}
function selectOptions(items,placeholder='اختر...'){return `<option value="">${placeholder}</option>`+items.map(x=>`<option value="${esc(x.id)}">${esc(x.name||x.email||x.id)}</option>`).join('')}
function sectionForClass(classId,code='أ'){return (DATA.sections||[]).find(s=>String(s.class_id)===String(classId)&&String(s.code)===String(code))||(DATA.sections||[]).find(s=>String(s.class_id)===String(classId))||null}
function parseClassSectionName(raw){
  let name=String(raw||'').trim().replace(/\s+/g,' ');
  const original=name;
  let code=null;
  const patterns=[
    /(?:شعبة|شعبه|الشعبة|الشعبه)\s*([أابجدهـهA-D])\s*$/i,
    /[-–—/]\s*([أابجدهـهA-D])\s*$/i,
    /\(([أابجدهـهA-D])\)\s*$/i,
    /\s+([أابجدهـهA-D])\s*$/i
  ];
  for(const p of patterns){
    const m=name.match(p);
    if(m){code=m[1];name=name.replace(p,'').trim();break;}
  }
  const map={ا:'أ',أ:'أ',A:'أ',a:'أ',ب:'ب',B:'ب',b:'ب',ج:'ج',C:'ج',c:'ج',د:'د',D:'د',d:'د',ه:'د','هـ':'د'};
  code=map[code]||code;
  return {original,baseName:name||original,sectionCode:code};
}
function selectedImportSectionCode(parsedCode){
  const v=$('#importSectionCode')?.value||'auto';
  if(v==='auto') return parsedCode||'أ';
  return v;
}
function classMatchWithSection(rawName){
  const parsed=parseClassSectionName(rawName);
  const db=nameMatch(parsed.baseName,DATA.classes)||nameMatch(parsed.original,DATA.classes);
  const code=selectedImportSectionCode(parsed.sectionCode);
  const sec=db?sectionForClass(db.id,code):null;
  return {db,section:sec,sectionCode:code,parsed};
}
function sectionOptionsForClass(classId){const list=(DATA.sections||[]).filter(s=>String(s.class_id)===String(classId));return '<option value="">اختر الشعبة</option>'+list.map(s=>`<option value="${s.id}">شعبة ${esc(s.code)} — ${esc(s.name||'')}</option>`).join('')}
function updateManualSections(){const cls=$('#mClass')?.value; if($('#mSection')) $('#mSection').innerHTML=sectionOptionsForClass(cls); updateManualSubjects()}
async function assignmentFor(row){if(!row.section_id||!row.teacher_id||!row.subject_id)return null; const existing=(DATA.assignments||[]).find(a=>String(a.teacher_id)===String(row.teacher_id)&&String(a.section_id)===String(row.section_id)&&String(a.subject_id)===String(row.subject_id)&&(String(a.academic_period_id||'')===String(row.academic_period_id||''))); if(existing)return existing.id; try{const {data,error}=await client().rpc('upsert_teacher_assignment',{p_teacher_id:row.teacher_id,p_section_id:row.section_id,p_subject_id:row.subject_id,p_academic_period_id:row.academic_period_id||null,p_academic_year:'2026-2027'}); if(!error&&data&&data.teacher_assignment_id)return data.teacher_assignment_id;}catch(e){console.warn('assignment rpc',e)} return null}

function fillAllSelects(){['importPeriod','mPeriod','classPeriod','teacherPeriod','studentPeriod','sessionsPeriod','missingPeriod'].forEach(id=>{const el=$('#'+id);if(el)el.innerHTML=periodOptions()});['mClass','classSelect','missingClass'].forEach(id=>{const el=$('#'+id);if(el)el.innerHTML=selectOptions(DATA.classes,'اختر الصف')});updateManualSections();['mTeacher','teacherSelect','sessionTeacher'].forEach(id=>{const el=$('#'+id);if(el)el.innerHTML=selectOptions(DATA.teachers,'كل المعلمات')});$('#studentSelect').innerHTML=selectOptions(DATA.students,'اختر الطالب');$('#mDay').innerHTML='<option value="">اليوم</option>'+DAYS.map((d,i)=>`<option value="${i}">${d}</option>`).join('');$('#mSlot').innerHTML='<option value="">الحصة</option>'+DEFAULT_PERIODS.map(p=>`<option value="${p}">الحصة ${p}</option>`).join('');if($('#sessionsStart')&&!$('#sessionsStart').value)$('#sessionsStart').value=$('#academicYearStart')?.value||'2026-09-01';if($('#sessionsEnd')&&!$('#sessionsEnd').value)$('#sessionsEnd').value=addDaysISO($('#sessionsStart')?.value||todayISO(),30);if($('#sessionDate')&&!$('#sessionDate').value)$('#sessionDate').value=todayISO();if($('#holidayMonth')&&!$('#holidayMonth').value)$('#holidayMonth').value=todayISO().slice(0,7);if($('#payrollMonth')&&!$('#payrollMonth').value)$('#payrollMonth').value=todayISO().slice(0,7)}
function nameMatch(name,items){const n=norm(name);return items.find(x=>String(x.id)===String(name))||items.find(x=>norm(x.name)===n)||items.find(x=>norm(x.name).includes(n)||n.includes(norm(x.name)))}
function teacherMatch(name,items){const n=norm(name);return items.find(x=>String(x.id)===String(name))||items.find(x=>norm(x.name)===n)||items.find(x=>norm(x.email)===n)||items.find(x=>norm(x.name).includes(n)||n.includes(norm(x.name)))}
function decodeDay(days){if(!days)return-1;for(let i=0;i<Math.min(days.length,5);i++)if(days[i]==='1')return i;return-1}
async function readFileText(file){const buf=await file.arrayBuffer();let enc='windows-1256';try{const head=new TextDecoder('ascii').decode(buf.slice(0,180));const m=head.match(/encoding=["']([^"']+)/i);if(m)enc=m[1].toLowerCase()}catch(_){}try{return new TextDecoder(enc).decode(buf)}catch(e){return new TextDecoder('windows-1256').decode(buf)}}

function parseXmlText(text){const doc=new DOMParser().parseFromString(text,'application/xml');if(doc.querySelector('parsererror'))throw new Error('تعذر قراءة XML. تأكدي من أن الملف صادر من aSc Timetables وبترميز Windows-1256.');const subjects={},teachers={},classes={},lessons={};doc.querySelectorAll('subject').forEach(x=>{const id=x.getAttribute('id'),name=x.getAttribute('name')||x.getAttribute('short')||id;const db=nameMatch(name,DATA.subjects);subjects[id]={xmlId:id,name,dbId:db&&db.id,dbName:db&&db.name}});doc.querySelectorAll('teacher').forEach(x=>{const id=x.getAttribute('id'),name=x.getAttribute('name')||[x.getAttribute('lastname'),x.getAttribute('firstname')].filter(Boolean).join(' ')||id;const db=teacherMatch(name,DATA.teachers);teachers[id]={xmlId:id,name,dbId:db&&db.id,dbName:db&&db.name}});doc.querySelectorAll('class').forEach(x=>{const id=x.getAttribute('id'),name=x.getAttribute('name')||x.getAttribute('short')||id;const match=classMatchWithSection(name);const db=match.db;classes[id]={xmlId:id,name,dbId:db&&db.id,dbName:db&&db.name,sectionId:match.section&&match.section.id,sectionCode:match.sectionCode,baseName:match.parsed.baseName,detectedSectionCode:match.parsed.sectionCode}});doc.querySelectorAll('lesson').forEach(x=>{lessons[x.getAttribute('id')]={id:x.getAttribute('id'),classIds:splitIds(x.getAttribute('classids')),subjectId:x.getAttribute('subjectid'),teacherIds:splitIds(x.getAttribute('teacherids'))}});const rows=[],errors=[];const classSlot=new Map(),teacherSlot=new Map();doc.querySelectorAll('card').forEach((card,idx)=>{const lesson=lessons[card.getAttribute('lessonid')];const period=parseInt(card.getAttribute('period'));const day=decodeDay(card.getAttribute('days'));if(!lesson){errors.push({line:idx+1,msg:'حصة بلا درس مرتبط'});return}if(day<0){errors.push({line:idx+1,msg:'تعذر قراءة اليوم: '+card.getAttribute('days')});return}const subj=subjects[lesson.subjectId];const classIds=lesson.classIds.length?lesson.classIds:[''];const teacherIds=lesson.teacherIds.length?lesson.teacherIds:[''];classIds.forEach(cx=>teacherIds.forEach(tx=>{const cls=classes[cx],tch=teachers[tx];let bad=false;if(!cls||!cls.dbId){errors.push({line:idx+1,msg:'صف غير مطابق: '+(cls?cls.name:cx)});bad=true}if(!subj||!subj.dbId){errors.push({line:idx+1,msg:'مادة غير مطابقة: '+(subj?subj.name:lesson.subjectId)});bad=true}if(!tch||!tch.dbId){errors.push({line:idx+1,msg:'معلمة غير مطابقة: '+(tch?tch.name:tx)});bad=true}if(bad)return;const ck=`${cls.sectionId||cls.dbId}-${day}-${period}`,tk=`${tch.dbId}-${day}-${period}`;const conflict=[];if(classSlot.has(ck))conflict.push('تعارض صف داخل الملف');else classSlot.set(ck,idx+1);if(teacherSlot.has(tk))conflict.push('تعارض معلمة داخل الملف');else teacherSlot.set(tk,idx+1);rows.push({academic_period_id:$('#importPeriod').value||null,class_id:cls.dbId,section_id:cls.sectionId||null,subject_id:subj.dbId,teacher_id:tch.dbId,day,period_number:period,asc_lesson_id:lesson.id,asc_card_key:`${lesson.id}-${day}-${period}-${cls.dbId}-${cls.sectionId||'no-section'}-${tch.dbId}`,class_name:cls.dbName,section_code:cls.sectionCode,detected_section_code:cls.detectedSectionCode,subject_name:subj.dbName,teacher_name:tch.dbName,conflict})}))});return {subjects,teachers,classes,lessons,rows,errors,fileStats:{subjects:Object.keys(subjects).length,teachers:Object.keys(teachers).length,classes:Object.keys(classes).length,lessons:Object.keys(lessons).length,cards:doc.querySelectorAll('card').length}}}
async function handleFile(file){try{const text=await readFileText(file);IMPORT=parseXmlText(text);IMPORT.fileName=file.name;renderAnalysis()}catch(e){toast('تعذر تحليل الملف',e.message,'red')}} 
function unmatched(kind){return Object.values(IMPORT[kind]||{}).filter(x=>!x.dbId)}
function renderAnalysis(){const valid=IMPORT.rows.length,errs=IMPORT.errors.length,conf=IMPORT.rows.filter(r=>r.conflict.length).length;$('#analysisBox').innerHTML=`<div class="analysis-grid"><div class="analysis-pill"><small>الحصص الصالحة</small><b>${valid}</b></div><div class="analysis-pill"><small>أخطاء المطابقة</small><b>${errs}</b></div><div class="analysis-pill"><small>تعارضات داخل الملف</small><b>${conf}</b></div><div class="analysis-pill"><small>اسم الملف</small><b style="font-size:16px">${esc(IMPORT.fileName||'—')}</b></div></div><div class="match-list"><div class="match-box"><h4>المواد غير المطابقة</h4>${unmatched('subjects').map(x=>`<div class="match-row"><span>${esc(x.name)}</span><span class="badge red">غير موجود</span></div>`).join('')||'<div class="badge green">كل المواد مطابقة</div>'}</div><div class="match-box"><h4>المعلمات غير المطابقة</h4>${unmatched('teachers').map(x=>`<div class="match-row"><span>${esc(x.name)}</span><span class="badge red">غير موجود</span></div>`).join('')||'<div class="badge green">كل المعلمات مطابقات</div>'}</div><div class="match-box"><h4>الصفوف غير المطابقة</h4>${unmatched('classes').map(x=>`<div class="match-row"><span>${esc(x.name)}</span><span class="badge red">غير موجود</span></div>`).join('')||'<div class="badge green">كل الصفوف مطابقة</div>'}</div></div><div style="margin-top:16px">${previewTable(IMPORT.rows.slice(0,30))}</div><div class="toolbar" style="margin-top:16px"><div class="filters"><button class="btn gold" onclick="ScheduleManager.confirmImport()" ${!valid?'disabled':''}>تأكيد الاستيراد</button><button class="btn red" onclick="ScheduleManager.clearImport()">إلغاء</button></div><span class="muted">سيتم فحص تعارضات الصف والمعلمة قبل الحفظ.</span></div>`}
function previewTable(rows){return `<div class="table-wrap"><table><thead><tr><th>اليوم</th><th>الحصة</th><th>الصف</th><th>الشعبة</th><th>المادة</th><th>المعلمة</th><th>ملاحظات</th></tr></thead><tbody>${rows.map(r=>`<tr class="${r.conflict.length?'conflict':''}"><td>${DAYS[r.day]}</td><td>${r.period_number}</td><td>${esc(r.class_name)}</td><td>${esc(r.section_code||'—')}${r.detected_section_code?'<br><small>تلقائي</small>':''}</td><td>${esc(r.subject_name)}</td><td>${esc(r.teacher_name)}</td><td>${esc(r.conflict.join('، ')||'—')}</td></tr>`).join('')}</tbody></table></div>`}
async function existingSlot(row){const filters=[{op:'eq',col:'day',val:row.day},{op:'eq',col:'period_number',val:row.period_number}];if(row.section_id)filters.push({op:'eq',col:'section_id',val:row.section_id});else filters.push({op:'eq',col:'class_id',val:row.class_id});if(row.academic_period_id)filters.push({op:'eq',col:'academic_period_id',val:row.academic_period_id});return (await q('weekly_schedule',{columns:'id',filters,limit:1}))[0]}
async function teacherConflict(row,ignoreId){let query=client().from('weekly_schedule').select('id,class_id').eq('teacher_id',row.teacher_id).eq('day',row.day).eq('period_number',row.period_number);if(row.academic_period_id)query=query.eq('academic_period_id',row.academic_period_id);const {data}=await query;return (data||[]).find(x=>String(x.id)!==String(ignoreId))}
async function confirmImport(){if(!IMPORT||!IMPORT.rows.length)return;const mode=$('#importMode').value,period=$('#importPeriod').value||null;const rows=IMPORT.rows.map(r=>Object.assign({},r,{academic_period_id:period}));if(!confirm(`سيتم حفظ ${rows.length} حصة. هل تريدين المتابعة؟`))return;try{if(mode==='replace_period'&&period){await client().from('weekly_schedule').delete().eq('academic_period_id',period)}if(mode==='replace_classes'){const sectionIds=[...new Set(rows.map(r=>r.section_id).filter(Boolean))];if(sectionIds.length){for(const sid of sectionIds){let del=client().from('weekly_schedule').delete().eq('section_id',sid);if(period)del=del.eq('academic_period_id',period);await del}}else{const cls=[...new Set(rows.map(r=>r.class_id))];for(const c of cls){let del=client().from('weekly_schedule').delete().eq('class_id',c);if(period)del=del.eq('academic_period_id',period);await del}}}let ok=0,skipped=0;for(const r of rows){const assignment_id=await assignmentFor(r);const payload={academic_period_id:r.academic_period_id,class_id:r.class_id,section_id:r.section_id||null,subject_id:r.subject_id,teacher_id:r.teacher_id,teacher_assignment_id:assignment_id,day:r.day,period_number:r.period_number};const old=await existingSlot(r);const tc=await teacherConflict(r,old&&old.id);if(tc){skipped++;continue}let res;if(old)res=await client().from('weekly_schedule').update(payload).eq('id',old.id);else res=await client().from('weekly_schedule').insert(payload);if(res.error){console.warn(res.error);skipped++}else ok++}toast('انتهى الاستيراد',`تم حفظ ${ok} حصة، وتجاوز ${skipped} بسبب تعارضات أو أخطاء`,skipped?'red':'green');await loadData();clearImport();}catch(e){console.error(e);toast('فشل الاستيراد',e.message,'red')}} 
function clearImport(){IMPORT=null;$('#analysisBox').innerHTML='';$('#importFile').value=''}
async function saveManual(){const r={academic_period_id:$('#mPeriod').value||null,class_id:$('#mClass').value,section_id:$('#mSection').value||null,day:parseInt($('#mDay').value),period_number:parseInt($('#mSlot').value),subject_id:$('#mSubject').value,teacher_id:$('#mTeacher').value};if(!r.class_id||isNaN(r.day)||!r.period_number||!r.subject_id||!r.teacher_id){toast('تنبيه','أكملي كل الحقول','red');return}const old=await existingSlot(r);const tc=await teacherConflict(r,old&&old.id);if(tc){toast('تعارض','هذه المعلمة لديها حصة أخرى في نفس الوقت','red');return}const assignment_id=await assignmentFor(r);const payload={academic_period_id:r.academic_period_id,class_id:r.class_id,section_id:r.section_id||null,teacher_assignment_id:assignment_id,day:r.day,period_number:r.period_number,subject_id:r.subject_id,teacher_id:r.teacher_id};const res=old?await client().from('weekly_schedule').update(payload).eq('id',old.id):await client().from('weekly_schedule').insert(payload);if(res.error)toast('خطأ',res.error.message,'red');else{toast('تم الحفظ','تم تحديث الحصة','green');await loadData()}}
async function deleteManual(){const r={academic_period_id:$('#mPeriod').value||null,class_id:$('#mClass').value,section_id:$('#mSection').value||null,day:parseInt($('#mDay').value),period_number:parseInt($('#mSlot').value)};const old=await existingSlot(r);if(!old){toast('تنبيه','لا توجد حصة في هذا المكان','red');return}if(!confirm('حذف هذه الحصة؟'))return;const res=await client().from('weekly_schedule').delete().eq('id',old.id);if(res.error)toast('خطأ',res.error.message,'red');else{toast('تم الحذف','حُذفت الحصة','green');await loadData()}}
function currentRows(period){return DATA.schedule.filter(r=>!period||String(r.academic_period_id)===String(period))}
function classStage(cls){
  const name=norm(cls&&cls.name);
  if(name.includes('ابتدائي'))return 'primary';
  if(name.includes('متوسط'))return 'middle';
  if(name.includes('اعدادي')||name.includes('اعدادي'))return 'preparatory';
  return 'primary';
}
function gradeNumber(cls){
  const n=norm(cls&&cls.name);
  const map=[['الاول',1],['اول',1],['الثاني',2],['ثاني',2],['الثالث',3],['ثالث',3],['الرابع',4],['رابع',4],['الخامس',5],['خامس',5],['السادس',6],['سادس',6]];
  const hit=map.find(([k])=>n.includes(k));
  return hit?hit[1]:0;
}
function minutesOf(t){const [h,m]=String(t).split(':').map(Number);return h*60+m}function hhmm(min){const h=Math.floor(min/60)%24,m=min%60;return String(h).padStart(2,'0')+':'+String(m).padStart(2,'0')}function periodTime(profile,period){const start=minutesOf(profile.start)+(period-1)*(profile.duration+profile.break);return{start:hhmm(start),end:hhmm(start+profile.duration)}}function profileForClass(cls){const profiles=timeProfiles();const stage=classStage(cls);return (stage==='primary'?profiles.primary:profiles.secondary)||profiles.primary}
function subjectOk(name,aliases){const n=norm(name);return aliases.some(a=>n.includes(norm(a))||norm(a).includes(n))}
function requiredSubjectGroups(cls){
  const stage=classStage(cls), g=gradeNumber(cls);
  const groups=[
    {label:'التربية الإسلامية',aliases:['التربية الاسلامية','الإسلامية','اسلامية','قرآن','القرآن'],type:'core'},
    {label:'اللغة العربية',aliases:['اللغة العربية','العربية','عربي'],type:'core'},
    {label:'اللغة الإنجليزية',aliases:['اللغة الانجليزية','الإنجليزية','انكليزي','انجليزي','english'],type:'core'},
    {label:'الرياضيات',aliases:['الرياضيات','رياضيات'],type:'core'}
  ];
  if(stage==='primary'){
    groups.push({label:'العلوم',aliases:['العلوم','علوم'],type:'core'});
    groups.push({label:'التربية الفنية',aliases:['التربية الفنية','فنية','فن'],type:'core'});
    groups.push({label:'التربية البدنية',aliases:['التربية البدنية','البدنية','رياضة','التربية الرياضية'],type:'core'});
    if(g>=4&&g<=6)groups.push({label:'الاجتماعيات',aliases:['الاجتماعيات','الاجتماعية','اجتماعيات','اجتماعية'],type:'core'});
  }else{
    if(stage==='middle' && g>=1&&g<=3)groups.push({label:'الاجتماعيات',aliases:['الاجتماعيات','الاجتماعية','اجتماعيات','اجتماعية'],type:'core'});
    groups.push({label:'الأحياء',aliases:['الأحياء','احياء'],type:'core'});
    groups.push({label:'الفيزياء',aliases:['الفيزياء','فيزياء'],type:'core'});
    groups.push({label:'الكيمياء',aliases:['الكيمياء','كيمياء'],type:'core'});
  }
  return groups;
}
function activitySubjectGroups(cls){
  const stage=classStage(cls);
  if(stage==='middle'||stage==='preparatory')return [
    {label:'التربية الفنية',aliases:['التربية الفنية','فنية','فن'],type:'activity'},
    {label:'التربية البدنية',aliases:['التربية البدنية','البدنية','رياضة','التربية الرياضية'],type:'activity'}
  ];
  return [];
}
function subjectsForClass(cls){
  const core=requiredSubjectGroups(cls).map(g=>Object.assign({},g,{optional:false}));
  const activity=activitySubjectGroups(cls).map(g=>Object.assign({},g,{optional:true}));
  return core.concat(activity);
}
function subjectForGroup(group){return DATA.subjects.find(s=>subjectOk(s.name,group.aliases))}
function updateManualSubjects(){
  const cls=DATA.classMap.get(String($('#mClass')?.value||''));
  const sel=$('#mSubject'); if(!sel)return;
  if(!cls){sel.innerHTML=selectOptions(DATA.subjects,'اختر الصف أولاً أو اختر مادة');return;}
  const groups=subjectsForClass(cls);
  const core=groups.filter(g=>!g.optional).map(g=>({g,s:subjectForGroup(g)}));
  const act=groups.filter(g=>g.optional).map(g=>({g,s:subjectForGroup(g)}));
  let html='<option value="">اختر المادة</option>';
  html+='<optgroup label="المواد المطلوبة لهذا الصف">'+core.map(x=>x.s?`<option value="${x.s.id}">${esc(x.s.name)}</option>`:`<option disabled>غير موجودة: ${esc(x.g.label)}</option>`).join('')+'</optgroup>';
  if(act.length)html+='<optgroup label="مواد النشاط">'+act.map(x=>x.s?`<option value="${x.s.id}">${esc(x.s.name)} — نشاط</option>`:`<option disabled>غير موجودة: ${esc(x.g.label)}</option>`).join('')+'</optgroup>';
  sel.innerHTML=html;
}
function requiredStatus(cls,rows){const present=[...new Set(rows.map(r=>(DATA.subjectMap.get(String(r.subject_id))||{}).name).filter(Boolean))];return requiredSubjectGroups(cls).map(req=>({label:req.label,ok:present.some(n=>subjectOk(n,req.aliases)),dbName:(DATA.subjects.find(s=>subjectOk(s.name,req.aliases))||{}).name||req.label}))}
function requirementPanel(cls,rows){const st=requiredStatus(cls,rows),ok=st.filter(x=>x.ok).length;return`<div class="require-panel"><div><b>المواد الإلزامية المطابقة: ${ok}/${st.length}</b><small>تتم المراعاة حسب أسماء المواد الموجودة في قاعدة البيانات.</small></div><div class="require-list">${st.map(x=>`<span class="badge ${x.ok?'green':'red'}">${x.ok?'✓':'!'} ${esc(x.dbName)}</span>`).join('')}</div></div>`}
function classRows(period,classId){return currentRows(period).filter(r=>String(r.class_id)===String(classId))}
function renderPrintableClassSchedule(rows,target,options={}){const cls=DATA.classMap.get(String(options.classId||(rows[0]&&rows[0].class_id)));if(!cls){$(target).innerHTML='<div class="empty">اختاري الصف أولاً</div>';return}const profile=profileForClass(cls),allowed=Array.from({length:profile.periods},(_,i)=>i+1),map=new Map(rows.map(r=>[`${r.day}-${r.period_number}`,r])),periodName=options.periodName||($('#classPeriod option:checked')?.textContent)||'الفصل الدراسي';let html=`<article class="printable-schedule"><div class="print-head"><div class="print-logo">ع</div><div><h2>جدول ${esc(cls.name)}</h2><p>مدارس أمين الرضا (ع) · ${esc(periodName)} · ${esc(profile.label)}</p></div><div class="print-meta"><b>بداية الدوام</b><span>${profile.start}</span><small>${profile.periods} حصص · استراحة ${profile.break} دقائق</small></div></div>${requirementPanel(cls,rows)}<div class="table-wrap print-table"><table><thead><tr><th>الحصة</th><th>الوقت</th>${DAYS.map((d,i)=>dayHeader(i)).join('')}</tr></thead><tbody>`;for(const p of allowed){const tm=periodTime(profile,p);html+=`<tr><td><b>الحصة ${p}</b></td><td><span class="time-badge">${tm.start} – ${tm.end}</span></td>`;for(let d=0;d<5;d++){const h=holidayForDate(dayDate(d)),r=map.get(`${d}-${p}`);html+=h?`<td class="holiday-slot"><b>عطلة رسمية</b><br><small>${esc(h.name)}</small></td>`:r?`<td><div class="lesson-title">${esc((DATA.subjectMap.get(String(r.subject_id))||{}).name||'—')}</div><div class="lesson-meta">${esc((DATA.teacherMap.get(String(r.teacher_id))||{}).name||'—')}</div></td>`:`<td class="empty-slot">—</td>`}html+='</tr>'}html+='</tbody></table></div></article>';$(target).innerHTML=html}
function renderTeacherTable(rows,target){
  if(!rows.length){$(target).innerHTML='<div class="empty">لا توجد حصص لهذه المعلمة</div>';return}
  const teacher=DATA.teacherMap.get(String(rows[0].teacher_id));
  const max=Math.max(5,...rows.map(r=>Number(r.period_number)||0));
  const map=new Map(rows.map(r=>[`${r.day}-${r.period_number}`,r]));
  let html=`<article class="printable-schedule"><div class="print-head"><div class="print-logo">ع</div><div><h2>جدول المعلمة ${esc(teacher&&teacher.name||'—')}</h2><p>مدارس أمين الرضا (ع) · عدد الحصص الأسبوعية: ${rows.length}</p></div><div class="print-meta"><b>عرض أسبوعي</b><span>${rows.length}</span><small>حصة</small></div></div><div class="table-wrap print-table"><table><thead><tr><th>الحصة</th><th>الوقت</th>${DAYS.map((d,i)=>dayHeader(i)).join('')}</tr></thead><tbody>`;
  for(let p=1;p<=max;p++){
    html+=`<tr><td><b>الحصة ${p}</b></td><td><span class="time-badge">حسب الصف</span></td>`;
    for(let d=0;d<5;d++){
      const h=holidayForDate(dayDate(d));
      const r=map.get(`${d}-${p}`);
      if(h) html+=`<td class="holiday-slot"><b>عطلة رسمية</b><br><small>${esc(h.name)}</small></td>`;
      else if(r){const cls=DATA.classMap.get(String(r.class_id));const tm=periodTime(profileForClass(cls),r.period_number);html+=`<td><div class="lesson-title">${esc((DATA.subjectMap.get(String(r.subject_id))||{}).name||'—')}</div><div class="lesson-meta">${esc(cls&&cls.name||'—')}</div><div class="lesson-meta">${tm.start} – ${tm.end}</div></td>`;}
      else html+='<td class="empty-slot">—</td>';
    }
    html+='</tr>';
  }
  html+='</tbody></table></div></article>';
  $(target).innerHTML=html;
}
function renderClassView(){const period=$('#classPeriod').value,cls=$('#classSelect').value;if(!cls){toast('تنبيه','اختاري الصف','red');return}renderPrintableClassSchedule(classRows(period,cls),'#classScheduleBox',{classId:cls})}
function renderTeacherView(){const period=$('#teacherPeriod').value,t=$('#teacherSelect').value;if(!t){toast('تنبيه','اختاري المعلمة','red');return}renderTeacherTable(currentRows(period).filter(r=>String(r.teacher_id)===String(t)),'#teacherScheduleBox')}
function renderStudentView(){const period=$('#studentPeriod').value,sid=$('#studentSelect').value,st=DATA.studentMap.get(String(sid));if(!st){toast('تنبيه','اختاري الطالب','red');return}renderPrintableClassSchedule(classRows(period,st.class_id),'#studentScheduleBox',{classId:st.class_id,periodName:'جدول الطالب '+(st.name||'')})}
function showDisplay(kind){$$('.display-panel').forEach(p=>p.classList.toggle('active',p.id==='display-'+kind))}
function printCurrent(){window.print()}
function monthDays(ym){const [y,m]=ym.split('-').map(Number);const d=new Date(y,m,0).getDate();return Array.from({length:d},(_,i)=>`${y}-${String(m).padStart(2,'0')}-${String(i+1).padStart(2,'0')}`)}
function holidayDefMatchesDate(def,iso){if(!window.TripleDate)return false;const td=new TripleDate(iso);if(def.calendar_system==='gregorian'){const [y,m,d]=iso.split('-').map(Number);return m===def.month_no&&d===def.day_no}if(def.calendar_system==='persian')return td.persian.month===def.month_no&&td.persian.day===def.day_no;if(def.calendar_system==='hijri')return td.hijri.month===def.month_no&&td.hijri.day===def.day_no;return false}
async function generateHolidayCandidates(){
  const ym=$('#holidayMonth').value||todayISO().slice(0,7);if(!DATA.holidayDefinitions.length){toast('لا توجد تعريفات عطل','شغّلي SQL 08 الخاص بالعطل والتقويم','red');return}
  const rows=[];for(const iso of monthDays(ym)){const td=window.TripleDate?new TripleDate(iso):null;for(const def of DATA.holidayDefinitions){if(holidayDefMatchesDate(def,iso)){rows.push({academic_year:'2026-2027',holiday_definition_id:def.id,name_ar:def.name_ar,calendar_system:def.calendar_system,date_gregorian:iso,date_hijri:td?td.hijri:{},date_persian:td?td.persian:{},month_key:ym,status:'pending',notes:def.needs_confirmation?'تحتاج تأكيد الإدارة قبل النشر':'عطلة مرشحة للنشر'})}}}
  if(!rows.length){toast('لا توجد عطل مرشحة','لا توجد عطل رسمية/هجرية في هذا الشهر حسب التعريفات الحالية','green');return}
  let added=0;for(const r of rows){const {error}=await client().from('school_holiday_candidates').upsert(r,{onConflict:'academic_year,name_ar,date_gregorian'});if(!error)added++;else console.warn(error)}
  toast('تم توليد المقترحات',`عدد المقترحات: ${added}. راجعيها ثم وافقي على النشر.`,'green');await loadData();
}
function renderHolidayCandidates(){const box=$('#holidayCandidatesBox');if(!box||!DATA)return;const ym=$('#holidayMonth')?.value||todayISO().slice(0,7);const rows=(DATA.holidayCandidates||[]).filter(c=>c.month_key===ym||String(c.date_gregorian||'').startsWith(ym));box.innerHTML=rows.map(c=>`<div class="item"><div><b>${esc(c.name_ar)}</b><small>${esc(c.date_gregorian)} · ${esc(c.calendar_system)} · ${esc(c.status)}</small></div><div style="display:flex;gap:6px;flex-wrap:wrap">${c.status==='pending'?`<button class="btn green" onclick="ScheduleManager.publishHolidayCandidate('${c.id}')">نشر</button><button class="btn red" onclick="ScheduleManager.rejectHolidayCandidate('${c.id}')">رفض</button>`:`<span class="badge ${c.status==='published'?'green':'red'}">${esc(c.status)}</span>`}</div></div>`).join('')||'<div class="empty">لا توجد مقترحات لهذا الشهر. اضغطي توليد مقترحات الشهر.</div>'}
async function publishHolidayCandidate(id){const c=(DATA.holidayCandidates||[]).find(x=>String(x.id)===String(id));if(!c)return;const payload={name:c.name_ar,holiday_date:c.date_gregorian,holiday_type:'official',is_recurring:false,calendar_system:c.calendar_system,source:'confirmed_monthly',notes:'نُشرت من مقترحات العطل الشهرية',created_by:ME&&ME.id};const {error}=await client().from('school_holidays').insert(payload);if(error){toast('تعذر النشر',error.message,'red');return}await client().from('school_holiday_candidates').update({status:'published',confirmed_by:ME&&ME.id,confirmed_at:new Date().toISOString(),published_at:new Date().toISOString()}).eq('id',id);toast('تم النشر','تمت إضافة العطلة إلى التقويم','green');await loadData()}
async function rejectHolidayCandidate(id){await client().from('school_holiday_candidates').update({status:'rejected',confirmed_by:ME&&ME.id,confirmed_at:new Date().toISOString()}).eq('id',id);toast('تم الرفض','لن تُنشر هذه العطلة','green');await loadData()}
async function renderMissingSubjectsReport(){
  const period=$('#missingPeriod')?.value||null;
  const cls=$('#missingClass')?.value||'';
  const status=$('#missingStatus')?.value||'missing';
  const box=$('#missingSubjectsBox');
  if(!box)return;
  box.innerHTML='<div class="skeleton"></div>';
  try{
    const {data,error}=await client().rpc('schedule_required_subjects_report',{p_academic_period_id:period||null});
    if(error)throw error;
    let rows=(data||[]).filter(r=>(!cls||String(r.class_id)===String(cls)) && (status==='all'||r.status===status));
    const missing=rows.filter(r=>r.status==='missing').length;
    const notdb=rows.filter(r=>r.status==='subject_not_in_db').length;
    const present=rows.filter(r=>r.status==='present').length;
    box.innerHTML=`<div class="analysis-grid"><div class="analysis-pill"><small>موجودة</small><b>${present}</b></div><div class="analysis-pill"><small>ناقصة</small><b>${missing}</b></div><div class="analysis-pill"><small>غير موجودة بقاعدة البيانات</small><b>${notdb}</b></div><div class="analysis-pill"><small>إجمالي العرض</small><b>${rows.length}</b></div></div>`+
    (rows.length?`<div class="table-wrap"><table><thead><tr><th>الصف</th><th>الشعبة</th><th>المرحلة</th><th>المادة المطلوبة</th><th>المطابقة في قاعدة البيانات</th><th>الحالة</th><th></th></tr></thead><tbody>${rows.map(r=>`<tr><td>${esc(r.class_name)}</td><td>${esc(r.section_code||'—')}</td><td>${esc(r.stage_type)}</td><td><b>${esc(r.required_subject)}</b></td><td>${esc(r.matched_subject_name||'—')}</td><td><span class="badge ${r.status==='present'?'green':r.status==='missing'?'red':'gold'}">${r.status==='present'?'موجودة':r.status==='missing'?'ناقصة':'المادة غير موجودة'}</span></td><td>${r.status==='missing'&&r.matched_subject_id?`<button class="btn blue" onclick="ScheduleManager.prepareManualAdd('${r.class_id}','${r.section_id}','${r.matched_subject_id}')">إضافة حصة</button>`:''}</td></tr>`).join('')}</tbody></table></div>`:'<div class="empty">لا توجد مواد ضمن هذا الفلتر.</div>');
  }catch(e){box.innerHTML=`<div class="empty error-state">${esc(e.message)} — شغّلي SQL 27 أولاً</div>`}
}
function prepareManualAdd(classId,sectionId,subjectId){
  document.getElementById('manualCard')?.scrollIntoView({behavior:'smooth'});
  if($('#mClass')){$('#mClass').value=classId;updateManualSections();}
  setTimeout(()=>{if($('#mSection'))$('#mSection').value=sectionId;if($('#mSubject'))$('#mSubject').value=subjectId;},80);
}
function missingTeacherSelect(row,index){
  return `<select class="select" id="missingTeacher_${index}" style="min-width:170px"><option value="">اختاري المعلم</option>${DATA.teachers.map(t=>`<option value="${t.id}">${esc(t.name||t.email||t.id)}</option>`).join('')}</select>`;
}
function missingActionCell(row,index){
  if(row.can_auto_add){
    return `<button class="btn blue" onclick="ScheduleManager.addSuggestedMissing('${row.section_id}','${row.subject_id}','${row.teacher_id}',${row.suggested_day},${row.suggested_period})">إضافة</button>`;
  }
  if(!row.teacher_id){
    return `<div style="display:grid;gap:6px;min-width:190px">${missingTeacherSelect(row,index)}<button class="btn gold" onclick="ScheduleManager.assignTeacherForMissing('${row.section_id}','${row.subject_id}','missingTeacher_${index}')">إسناد ثم إعادة الاقتراح</button></div>`;
  }
  return `<button class="btn" onclick="ScheduleManager.prepareAssignmentForMissing('${row.section_id}','${row.subject_id}')">مراجعة الإسناد</button>`;
}
async function renderMissingSubjectSuggestions(){
  const period=$('#missingPeriod')?.value||null;
  const cls=$('#missingClass')?.value||'';
  const box=$('#missingSubjectsBox');
  if(!box)return;
  box.innerHTML='<div class="skeleton"></div>';
  try{
    const {data,error}=await client().rpc('schedule_missing_subject_suggestions',{p_academic_period_id:period||null});
    if(error)throw error;
    let rows=(data||[]).filter(r=>!cls||String(r.class_id)===String(cls));
    const ready=rows.filter(r=>r.can_auto_add).length;
    const needTeacher=rows.filter(r=>!r.teacher_id).length;
    box.innerHTML=`<div class="analysis-grid"><div class="analysis-pill"><small>المواد الناقصة</small><b>${rows.length}</b></div><div class="analysis-pill"><small>جاهزة للإضافة</small><b>${ready}</b></div><div class="analysis-pill"><small>تحتاج إسناد معلم</small><b>${needTeacher}</b></div><div class="analysis-pill"><small>الفصل</small><b style="font-size:15px">${esc($('#missingPeriod option:checked')?.textContent||'كل الفصول')}</b></div></div><div class="toolbar"><button class="btn gold" onclick="ScheduleManager.autoAddAllMissingSuggestions()" ${ready?'':'disabled'}>إضافة كل المقترحات الممكنة</button><span class="muted">إذا لم يوجد معلم، اختاريه من القائمة وسيتم إنشاء الإسناد ثم تحديث الاقتراحات.</span></div>`+
    (rows.length?`<div class="table-wrap"><table><thead><tr><th>الصف</th><th>الشعبة</th><th>المادة</th><th>المعلم المقترح</th><th>اليوم</th><th>الحصة</th><th>الحالة</th><th>إجراء</th></tr></thead><tbody>${rows.map((r,i)=>`<tr><td>${esc(r.class_name)}</td><td>${esc(r.section_code||'—')}</td><td><b>${esc(r.required_subject)}</b></td><td>${esc(r.teacher_name||'—')}</td><td>${r.suggested_day!=null?DAYS[r.suggested_day]:'—'}</td><td>${r.suggested_period||'—'}</td><td><span class="badge ${r.can_auto_add?'green':r.teacher_id?'gold':'red'}">${esc(r.reason)}</span></td><td>${missingActionCell(r,i)}</td></tr>`).join('')}</tbody></table></div>`:'<div class="empty">لا توجد مواد ناقصة ضمن هذا الفلتر.</div>');
  }catch(e){box.innerHTML=`<div class="empty error-state">${esc(e.message)} — شغّلي SQL 28 أولاً</div>`}
}
async function assignTeacherForMissing(sectionId,subjectId,selectId){
  const teacherId=document.getElementById(selectId)?.value;
  const period=$('#missingPeriod')?.value||null;
  if(!teacherId){toast('اختاري المعلم','لا يمكن إنشاء الإسناد دون اختيار معلم','red');return}
  try{
    const {data,error}=await client().rpc('upsert_teacher_assignment',{p_teacher_id:teacherId,p_section_id:sectionId,p_subject_id:subjectId,p_academic_period_id:period||null,p_academic_year:'2026-2027'});
    if(error)throw error;
    if(data&&data.ok===false){toast('تعذر الإسناد',data.message||'خطأ','red');return}
    toast('تم الإسناد','تم إنشاء إسناد المعلم للمادة والشعبة. سنعيد حساب الاقتراحات الآن.','green');
    await loadData();
    await renderMissingSubjectSuggestions();
  }catch(e){toast('تعذر الإسناد',e.message,'red')}
}

async function addSuggestedMissing(sectionId,subjectId,teacherId,day,periodNo){
  const period=$('#missingPeriod')?.value||null;
  try{
    const {data,error}=await client().rpc('add_missing_schedule_slot',{p_academic_period_id:period||null,p_section_id:sectionId,p_subject_id:subjectId,p_teacher_id:teacherId,p_day:day,p_period_number:periodNo});
    if(error)throw error;
    if(data&&data.ok===false){toast('تعذر الإضافة',data.message||'خطأ','red');return}
    toast('تمت الإضافة','تمت إضافة الحصة الناقصة للجدول','green');
    await loadData();
    await renderMissingSubjectSuggestions();
  }catch(e){toast('تعذر الإضافة',e.message,'red')}
}
async function autoAddAllMissingSuggestions(){
  const period=$('#missingPeriod')?.value||null;
  const cls=$('#missingClass')?.value||'';
  const {data,error}=await client().rpc('schedule_missing_subject_suggestions',{p_academic_period_id:period||null});
  if(error){toast('تعذر جلب المقترحات',error.message,'red');return}
  const rows=(data||[]).filter(r=>(!cls||String(r.class_id)===String(cls))&&r.can_auto_add);
  if(!rows.length){toast('لا توجد مقترحات جاهزة','قد تحتاجين إسناد معلمين للمواد الناقصة','red');return}
  if(!confirm(`سيتم إضافة ${rows.length} حصة ناقصة تلقائياً. هل تريدين المتابعة؟`))return;
  let ok=0,fail=0;
  for(const r of rows){
    const {data:res,error:e}=await client().rpc('add_missing_schedule_slot',{p_academic_period_id:period||null,p_section_id:r.section_id,p_subject_id:r.subject_id,p_teacher_id:r.teacher_id,p_day:r.suggested_day,p_period_number:r.suggested_period});
    if(e||res?.ok===false)fail++;else ok++;
  }
  toast('انتهت الإضافة',`تمت إضافة ${ok}، فشل ${fail}`,fail?'red':'green');
  await loadData();
  await renderMissingSubjectSuggestions();
}
function prepareAssignmentForMissing(sectionId,subjectId){
  location.href=`section-assignment-management.html?section=${encodeURIComponent(sectionId)}&subject=${encodeURIComponent(subjectId)}`;
}
async function generateSessions(){const start=$('#sessionsStart').value,end=$('#sessionsEnd').value,period=$('#sessionsPeriod').value||null;if(!start||!end){toast('تنبيه','حددي تاريخ البداية والنهاية','red');return}const {data,error}=await client().rpc('generate_class_sessions',{p_start:start,p_end:end,p_academic_period_id:period||null});if(error){toast('تعذر توليد الجلسات',error.message+' — شغّلي SQL 08','red');return}toast('تم توليد الجلسات',`عدد السجلات المعالجة: ${data}`,'green');await loadData()}
async function regenerateSessions(){const start=$('#sessionsStart').value,end=$('#sessionsEnd').value,period=$('#sessionsPeriod').value||null;if(!start||!end||!period){toast('تنبيه','حددي تاريخ البداية والنهاية والفصل الدراسي','red');return}if(!confirm('سيتم حذف الجلسات غير المثبتة فقط ضمن هذا النطاق ثم إعادة توليدها من الجدول الأسبوعي. الجلسات التي عليها واجبات أو نشاط معلمة ستبقى محفوظة. هل تريدين المتابعة؟'))return;const btn=$('#regenerateSessionsBtn');if(btn)btn.disabled=true;try{const {data,error}=await client().rpc('regenerate_class_sessions',{p_start:start,p_end:end,p_academic_period_id:period,p_preserve_activity:true});if(error)throw error;if(data&&data.ok===false){toast('تعذر إعادة التوليد',data.message||'خطأ','red');return}toast('تمت إعادة التوليد',`حُذف: ${data?.deleted_sessions||0} · وُلّد/حُدّث: ${data?.generated_or_updated_sessions||0}`,'green');await loadData()}catch(e){toast('تعذر إعادة التوليد',e.message+' — شغّلي SQL 24','red')}finally{if(btn)btn.disabled=false}}
async function loadSessions(){const date=$('#sessionDate').value||todayISO(),teacher=$('#sessionTeacher').value;let query=client().from('class_sessions').select('*').eq('session_date',date).order('period_number');if(teacher)query=query.eq('teacher_id',teacher);const {data,error}=await query;if(error){toast('تعذر تحميل الحصص',error.message,'red');return}renderSessions(data||[])}
function renderSessions(rows){const box=$('#sessionsBox');if(!rows.length){box.innerHTML='<div class="empty">لا توجد جلسات لهذا اليوم. ولديها حل: ولّدي الجلسات من قسم التقويم.</div>';return}box.innerHTML=`<div class="table-wrap"><table><thead><tr><th>الحصة</th><th>الوقت</th><th>الصف</th><th>المادة</th><th>المعلمة</th><th>الحالة</th><th>إثبات النشاط</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${r.period_number}</td><td><span class="time-badge">${(r.start_time||'').slice(0,5)} – ${(r.end_time||'').slice(0,5)}</span></td><td>${esc((DATA.classMap.get(String(r.class_id))||{}).name||'—')}</td><td>${esc((DATA.subjectMap.get(String(r.subject_id))||{}).name||'—')}</td><td>${esc((DATA.teacherMap.get(String(r.teacher_id))||{}).name||'—')}</td><td><span class="badge ${r.status==='holiday'?'red':r.status==='completed'?'green':'gold'}">${esc(r.status)}</span></td><td><button class="btn green" onclick="ScheduleManager.confirmSession('${r.id}')">تثبيت حصة</button> <button class="btn blue" onclick="ScheduleManager.addHomework('${r.id}')">واجب</button></td></tr>`).join('')}</tbody></table></div>`}
async function confirmSession(id){
  try{
    const {data,error}=await client().rpc('confirm_teacher_session',{p_session_id:id,p_activity_type:'manual_confirm',p_notes:'تثبيت حصة من الواجهة'});
    if(error)throw error;
    if(data && data.ok===false){toast('تعذر التثبيت',data.message||'لم يتم التثبيت','red');return}
    toast('تم التثبيت',(data&&data.message)||'سيتم احتساب هذه الحصة في نشاط المعلمة','green');
    await loadSessions();
  }catch(e){toast('تعذر التثبيت',e.message+' — شغّلي SQL 18 لإصلاح نشاط المعلمات','red')}
}
async function addHomework(id){
  const title=prompt('عنوان الواجب:');if(!title)return;
  const description=prompt('تفاصيل الواجب أو التعليمات:')||'';
  const due=prompt('تاريخ التسليم YYYY-MM-DD:',addDaysISO(todayISO(),3))||null;
  try{
    const {data,error}=await client().rpc('create_session_homework',{p_session_id:id,p_title:title,p_description:description,p_due_date:due});
    if(error)throw error;
    if(data && data.ok===false){toast('تعذر نشر الواجب',data.message||'لم يتم النشر','red');return}
    toast('تم نشر الواجب',(data&&data.message)||'تم تسجيل نشاط للمعلمة','green');
    await loadSessions();
  }catch(e){toast('تعذر نشر الواجب',e.message+' — شغّلي SQL 18 لإصلاح الواجبات','red')}
}
async function loadPayroll(){let query=client().from('v_teacher_payroll_preview').select('*').order('teacher_name');const month=$('#payrollMonth').value;if(month)query=query.eq('month',month+'-01');const {data,error}=await query;if(error){toast('تعذر حساب الرواتب',error.message+' — شغّلي SQL 08','red');return}$('#payrollBox').innerHTML=(data||[]).length?`<div class="table-wrap"><table><thead><tr><th>المعلمة</th><th>الشهر</th><th>حصص مثبتة بالنشاط</th><th>أجر الحصة</th><th>المبلغ التقديري</th></tr></thead><tbody>${data.map(r=>`<tr><td>${esc(r.teacher_name||'—')}</td><td>${esc(r.month)}</td><td>${r.verified_sessions}</td><td>${Number(r.amount_per_session||0).toLocaleString()} ${esc(r.currency)}</td><td><b>${Number(r.estimated_amount||0).toLocaleString()} ${esc(r.currency)}</b></td></tr>`).join('')}</tbody></table></div>`:'<div class="empty">لا توجد حصص مثبتة بالنشاط لهذا الشهر</div>'}
function bind(){ $$('.nav button').forEach(b=>b.addEventListener('click',()=>{$$('.nav button').forEach(x=>x.classList.remove('active'));b.classList.add('active');$('#sidebar').classList.remove('open')}));$('#mobileMenuBtn').addEventListener('click',()=>$('#sidebar').classList.toggle('open'));$('#logoutBtn').addEventListener('click',async()=>{await client().auth.signOut({scope:'local'});location.href='index.html'});$('#refreshBtn').addEventListener('click',async()=>{await loadData();toast('تم التحديث','تم تحميل البيانات من قاعدة البيانات','green')});$('#saveCalendarSettings')?.addEventListener('click',saveCalendarSettings);$('#addHolidayBtn')?.addEventListener('click',addHoliday);$('#generateHolidayCandidates')?.addEventListener('click',generateHolidayCandidates);$('#refreshHolidayCandidates')?.addEventListener('click',renderHolidayCandidates);$('#generateSessionsBtn')?.addEventListener('click',generateSessions);$('#regenerateSessionsBtn')?.addEventListener('click',regenerateSessions);$('#loadSessionsBtn')?.addEventListener('click',loadSessions);$('#loadPayrollBtn')?.addEventListener('click',loadPayroll);$('#weekStart')?.addEventListener('change',()=>{if($('#classSelect')?.value)renderClassView();if($('#teacherSelect')?.value)renderTeacherView();if($('#studentSelect')?.value)renderStudentView()});$('#importFile').addEventListener('change',e=>{if(e.target.files[0])handleFile(e.target.files[0])});const dz=$('#dropZone');dz.addEventListener('dragover',e=>{e.preventDefault();dz.classList.add('drag')});dz.addEventListener('dragleave',()=>dz.classList.remove('drag'));dz.addEventListener('drop',e=>{e.preventDefault();dz.classList.remove('drag');if(e.dataTransfer.files[0])handleFile(e.dataTransfer.files[0])});$('#mClass')?.addEventListener('change',updateManualSections);$('#saveManual').addEventListener('click',saveManual);$('#deleteManual').addEventListener('click',deleteManual)}
async function init(){client();if(!await ensureAuth())return;bind();await loadData();toast('جاهز','يمكنك استيراد ملف aSc أو تعديل الجدول يدوياً','green')}
window.ScheduleManager={init,confirmImport,clearImport,renderClassView,renderTeacherView,renderStudentView,printCurrent,showDisplay,publishHolidayCandidate,rejectHolidayCandidate,confirmSession,addHomework,regenerateSessions,renderMissingSubjectsReport,prepareManualAdd,renderMissingSubjectSuggestions,addSuggestedMissing,autoAddAllMissingSuggestions,prepareAssignmentForMissing,assignTeacherForMissing};
}());

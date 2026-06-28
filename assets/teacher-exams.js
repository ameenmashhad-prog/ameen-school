(function(){
'use strict';

let sb=null, ME=null, DATA={}, ACTIVE='overview', EDIT_QUESTION_ID=null, EDIT_EXAM_ID=null;
const cfg=()=>window.AMIN_CONFIG||{};
const $=(s,r=document)=>r.querySelector(s);
const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));

function client(){
  if(sb) return sb;
  sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});
  return sb;
}
function esc(v){return String(v==null?'':v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));}
function toast(t,m,type=''){
  const el=$('#toast');
  if(!el) return alert((t||'')+'\n'+(m||''));
  el.innerHTML=`<b>${esc(t)}</b><br><span class="muted">${esc(m||'')}</span>`;
  el.className='toast show '+type;
  clearTimeout(el._t);
  el._t=setTimeout(()=>el.classList.remove('show'),4200);
}
async function q(table,opts={}){
  try{
    let query=client().from(table).select(opts.columns||'*');
    (opts.filters||[]).forEach(f=>query=query[f.op](f.col,f.val));
    if(opts.order) query=query.order(opts.order,{ascending:opts.ascending!==false});
    if(opts.limit) query=query.limit(opts.limit);
    const {data,error}=await query;
    if(error){console.warn(table,error);return[];}
    return data||[];
  }catch(e){console.warn(table,e);return[];}
}
async function ensure(){
  const {data:{session}}=await client().auth.getSession();
  if(!session){location.href='index.html';return false;}
  const {data:u}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();
  ME=u;
  if(!u||u.role!=='teacher'){
    document.body.innerHTML='<main class="login-page"><section class="login-card"><h1>غير مصرح</h1><p>هذه الصفحة للمعلمين فقط.</p></section></main>';
    return false;
  }
  $('#profileName').textContent=u.name||u.email;
  $('#profileRole').textContent='معلم';
  return true;
}
function uniqueBy(arr,key){const m=new Map();arr.forEach(x=>{const k=key(x);if(k&&!m.has(k))m.set(k,x);});return[...m.values()];}

async function load(){
  const [schedule,banks,questions,options,exams,attempts,sessions,analysis,questionAnalysis,answers,examQuestions,allSubjects,attemptDetails,answerDetails]=await Promise.all([
    q('v_teacher_schedule',{order:'day'}),
    q('question_banks',{filters:[{op:'eq',col:'teacher_id',val:ME.id}],order:'created_at',ascending:false}),
    q('questions',{filters:[{op:'eq',col:'teacher_id',val:ME.id}],order:'created_at',ascending:false}),
    q('question_options',{order:'sort_order'}),
    q('online_exams',{filters:[{op:'eq',col:'teacher_id',val:ME.id}],order:'created_at',ascending:false}),
    q('exam_attempts',{order:'created_at',ascending:false}),
    q('class_sessions',{filters:[{op:'eq',col:'teacher_id',val:ME.id}],order:'session_date'}),
    q('v_online_exam_analysis',{filters:[{op:'eq',col:'teacher_id',val:ME.id}]}),
    q('v_online_exam_question_analysis'),
    q('exam_answers',{order:'answered_at',ascending:false}),
    q('online_exam_questions',{order:'sort_order'}),
    q('subjects',{order:'name'}),
    q('v_online_exam_attempts_detailed',{filters:[{op:'eq',col:'teacher_id',val:ME.id}],order:'started_at',ascending:false}),
    q('v_online_exam_answers_detailed',{filters:[{op:'eq',col:'teacher_id',val:ME.id}],order:'answered_at',ascending:false})
  ]);
  const sections=uniqueBy(schedule.map(r=>({section_id:r.section_id,class_id:r.class_id,class_name:r.class_name,section_code:r.section_code,section_name:r.section_name})),x=>String(x.section_id||x.class_id));
  const scheduledSubjects=uniqueBy(schedule.map(r=>({id:r.subject_id,name:r.subject_name,section_id:r.section_id,class_id:r.class_id})),x=>String(x.id)+'-'+String(x.section_id||x.class_id));
  DATA={schedule,sections,banks,questions,options,exams,attempts,sessions,analysis,questionAnalysis,answers,examQuestions,subjects:scheduledSubjects,allSubjects,attemptDetails,answerDetails};
  if(EDIT_QUESTION_ID && !DATA.questions.some(x=>String(x.id)===String(EDIT_QUESTION_ID))) EDIT_QUESTION_ID=null;
  if(EDIT_EXAM_ID && !DATA.exams.some(x=>String(x.id)===String(EDIT_EXAM_ID))) EDIT_EXAM_ID=null;
  render(ACTIVE);
}

function sectionLabel(s){return s?`${s.class_name} — شعبة ${s.section_code||''}`:'—';}
function opt(items,placeholder,label=(x)=>x.name,value=(x)=>x.id,selected=''){
  return `<option value="">${esc(placeholder)}</option>`+items.map(x=>{
    const val=String(value(x)||'');
    return `<option value="${esc(val)}" ${String(selected)===val?'selected':''}>${esc(label(x))}</option>`;
  }).join('');
}
function staticOptions(items,selected=''){
  return items.map(([val,label])=>`<option value="${esc(val)}" ${String(selected)===String(val)?'selected':''}>${esc(label)}</option>`).join('');
}
function subjectOptions(sectionId='',selected=''){
  const list=DATA.subjects.filter(s=>!sectionId||String(s.section_id||s.class_id)===String(sectionId));
  return opt(list,'اختاري المادة',x=>x.name,x=>x.id,selected);
}
function subjectName(id){
  return (DATA.allSubjects||[]).find(s=>String(s.id)===String(id))?.name
    || (DATA.subjects||[]).find(s=>String(s.id)===String(id))?.name
    || '—';
}
function bankName(id){return (DATA.banks.find(b=>String(b.id)===String(id))||{}).title||'—';}
function typeLabel(t){return ({mcq:'اختيار من متعدد',true_false:'صح وخطأ',fill_blank:'إكمال فراغ',essay:'مقالي',matching:'مطابقة',image:'صورة',audio:'صوت',multi_select:'اختيار متعدد الإجابات',ordering:'ترتيب',identify_error:'تحديد الخطأ',reading_comprehension:'قراءة وفهم',dialog_completion:'إكمال حوار',grammar_correction:'تصحيح خطأ',problem_solving:'حل مسائل',comparison:'مقارنة',cause_effect:'سبب ونتيجة',scenario:'موقف تطبيقي'}[t]||t||'—');}
function statusLabel(s){return ({draft:'مسودة',published:'منشور',closed:'مغلق',archived:'مؤرشف'}[s]||s||'—');}
function attemptStatus(s){return ({in_progress:'قيد الحل',submitted:'مسلّم',graded:'مصحح',expired:'منتهي الوقت',cancelled:'ملغى'}[s]||s||'—');}
function fmtDate(v){if(!v)return'—';try{return new Date(v).toLocaleString('ar-IQ')}catch{return v}}
function csvCell(v){const s=String(v==null?'':v).replace(/"/g,'""');return /[",\n]/.test(s)?`"${s}"`:s;}
function downloadCsv(filename,headers,rows){const csv='﻿'+[headers.map(csvCell).join(','),...rows.map(r=>headers.map(h=>csvCell(r[h])).join(','))].join('\n');const blob=new Blob([csv],{type:'text/csv;charset=utf-8'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=filename;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}
function toLocalDateTime(v){if(!v)return'';const d=new Date(v);if(Number.isNaN(d.getTime()))return'';d.setMinutes(d.getMinutes()-d.getTimezoneOffset());return d.toISOString().slice(0,16);}
function toIsoOrNull(v){return v?new Date(v).toISOString():null;}
function examAttempts(examId){return DATA.attempts.filter(a=>String(a.exam_id)===String(examId)).length;}
function examQuestionRows(examId){return DATA.examQuestions.filter(x=>String(x.exam_id)===String(examId)).sort((a,b)=>(a.sort_order||0)-(b.sort_order||0));}
function examQuestionIds(examId){return examQuestionRows(examId).map(x=>String(x.question_id));}
function questionAttemptCount(questionId){
  const examIds=new Set(DATA.examQuestions.filter(x=>String(x.question_id)===String(questionId)).map(x=>String(x.exam_id)));
  return DATA.attempts.filter(a=>examIds.has(String(a.exam_id))).length;
}
function questionOptionsText(questionId,type){
  const q=DATA.questions.find(x=>String(x.id)===String(questionId));
  if(type==='matching') return ((q?.correct_answer_json?.pairs)||[]).map(p=>`${p.left||''} = ${p.right||''}`).join('\n');
  if(type==='ordering') return ((q?.correct_answer_json?.items)||[]).join('\n');
  const opts=DATA.options.filter(o=>String(o.question_id)===String(questionId)).sort((a,b)=>(a.sort_order||0)-(b.sort_order||0));
  if(opts.length) return opts.map(o=>(o.is_correct?'*':'')+(o.option_text||'')).join('\n');
  return type==='true_false'?'*صح\nخطأ':'';
}
function correctAnswerText(q){if(!q)return'';if(q.question_type==='fill_blank'){const alt=(q.correct_answer_json?.acceptable_answers)||[];return [q.correct_answer||'',...alt].filter(Boolean).join(' | ')}return q.correct_answer||'';}
function sessionOptions(sectionId='',subjectId='',selected=''){
  const list=(DATA.sessions||[]).filter(s=>(!sectionId||String(s.section_id||s.class_id)===String(sectionId))&&(!subjectId||String(s.subject_id)===String(subjectId))).slice(0,90);
  return '<option value="">بدون ربط بحصة</option>'+list.map(s=>{
    const val=String(s.id||'');
    return `<option value="${esc(val)}" ${String(selected)===val?'selected':''}>${esc(s.session_date)} — ${esc(subjectName(s.subject_id))} — الحصة ${s.period_number}</option>`;
  }).join('');
}

function render(id){
  ACTIVE=id;
  $$('.view').forEach(v=>v.classList.toggle('active',v.id==='view-'+id));
  $$('.nav button[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view===id));
  ({overview,banks:banksView,questions:questionsView,build:buildView,generator:generatorView,results:resultsView}[id]||overview)();
}

function overview(){
  const published=DATA.exams.filter(e=>e.status==='published').length;
  const archived=DATA.exams.filter(e=>e.status==='archived').length;
  $('#view-overview').innerHTML=`
    <div class="page-head"><div><h1>بنك الأسئلة والاختبارات</h1><p>أنشئي أسئلة، عدّليها، ركّبي نموذجاً امتحانياً، وانشريه للطلاب.</p></div></div>
    <div class="kpis">
      <div class="kpi gold"><small>بنوك الأسئلة</small><b>${DATA.banks.length}</b></div>
      <div class="kpi blue"><small>الأسئلة</small><b>${DATA.questions.length}</b></div>
      <div class="kpi green"><small>اختبارات منشورة</small><b>${published}</b></div>
      <div class="kpi red"><small>مؤرشفة</small><b>${archived}</b></div>
    </div>
    <div class="cards">
      <div class="card"><div class="card-head"><h3>نماذجك الامتحانية</h3></div><div class="card-body">${examList()}</div></div>
      <div class="card"><div class="card-head"><h3>آخر الأسئلة</h3></div><div class="card-body">${questionList(DATA.questions.slice(0,6))}</div></div>
    </div>`;
}

function banksView(){
  $('#view-banks').innerHTML=`
    <div class="page-head"><div><h1>بنوك الأسئلة</h1><p>كل بنك مرتبط بمادة وشعبة أو صف.</p></div></div>
    <div class="card"><div class="card-body"><div class="exam-form">
      <div class="field span-4"><label>عنوان البنك</label><input id="bankTitle" class="input" placeholder="مثال: رياضيات - الفصل الأول"></div>
      <div class="field span-4"><label>الشعبة</label><select id="bankSection" class="select" onchange="TeacherExams.updateBankSubjects()">${opt(DATA.sections,'اختاري الشعبة',sectionLabel,x=>x.section_id||x.class_id)}</select></div>
      <div class="field span-4"><label>المادة</label><select id="bankSubject" class="select">${subjectOptions()}</select></div>
      <div class="field span-12"><label>وصف اختياري</label><input id="bankDesc" class="input"></div>
      <div class="span-12"><button class="btn gold" onclick="TeacherExams.createBank()">إنشاء بنك</button></div>
    </div></div></div>
    <div class="card"><div class="card-head"><h3>البنوك الحالية</h3></div><div class="card-body">${bankList()}</div></div>`;
}
function updateBankSubjects(){const sid=$('#bankSection').value;$('#bankSubject').innerHTML=subjectOptions(sid);}
async function createBank(){
  const sectionId=$('#bankSection').value, subjectId=$('#bankSubject').value, title=$('#bankTitle').value.trim();
  if(!title||!subjectId){toast('تنبيه','أدخلي العنوان والمادة','red');return;}
  const sec=DATA.sections.find(s=>String(s.section_id||s.class_id)===String(sectionId));
  const {error}=await client().from('question_banks').insert({
    title,
    description:$('#bankDesc').value,
    teacher_id:ME.id,
    class_id:sec&&sec.class_id||null,
    section_id:sec&&sec.section_id||null,
    subject_id:subjectId,
    visibility:'private'
  });
  if(error) toast('تعذر الإنشاء',error.message,'red');
  else{toast('تم الإنشاء','تم إنشاء بنك الأسئلة','green');await load();}
}
function bankList(){
  return DATA.banks.length?DATA.banks.map(b=>`
    <div class="item">
      <div><b>${esc(b.title)}</b><small>${esc(subjectName(b.subject_id))}</small></div>
      <span class="badge blue">${esc(b.visibility)}</span>
    </div>`).join(''):'<div class="empty">لا توجد بنوك بعد</div>';
}

function questionsView(){
  const edit=EDIT_QUESTION_ID?DATA.questions.find(q=>String(q.id)===String(EDIT_QUESTION_ID)):null;
  const isEdit=!!edit;
  const type=edit?.question_type||'mcq';
  const locked=isEdit && questionAttemptCount(edit.id)>0;
  const bankOpts=opt(DATA.banks,'اختاري بنك الأسئلة',b=>b.title,b=>b.id,edit?.bank_id||'');
  const typeOpts=staticOptions([
    ['mcq','اختيار من متعدد'],['true_false','صح وخطأ'],['multi_select','اختيار متعدد الإجابات'],['fill_blank','إكمال فراغ'],['matching','توصيل/مطابقة'],['ordering','ترتيب'],['identify_error','تحديد الخطأ'],['reading_comprehension','قراءة وفهم'],['dialog_completion','إكمال حوار'],['grammar_correction','تصحيح خطأ'],['problem_solving','حل مسائل'],['essay','مقالي/قصير'],['comparison','مقارنة'],['cause_effect','سبب ونتيجة'],['scenario','موقف تطبيقي']
  ],type);
  const optionsValue=isEdit?questionOptionsText(edit.id,type):'';
  const answerValue=correctAnswerText(edit);
  const showOptions=['mcq','true_false','multi_select','identify_error','matching','ordering'].includes(type);
  const showAnswer=['fill_blank','essay','reading_comprehension','dialog_completion','grammar_correction','problem_solving','comparison','cause_effect','scenario'].includes(type);
  $('#view-questions').innerHTML=`
    <div class="page-head"><div><h1>${isEdit?'تعديل سؤال':'إضافة سؤال'}</h1><p>للخيارات ضعي * قبل الصحيح. للمطابقة اكتبي: عنصر = مقابل. للترتيب اكتبي العناصر بالترتيب الصحيح.</p></div></div>
    ${locked?'<div class="alert warning">هذا السؤال مستخدم في محاولات طلاب؛ النظام سيمنع تعديل بنيته حفاظاً على النتائج.</div>':''}
    <div class="card"><div class="card-body"><div class="exam-form">
      <div class="field span-4"><label>البنك</label><select id="qBank" class="select">${bankOpts}</select></div>
      <div class="field span-4"><label>نوع السؤال</label><select id="qType" class="select" onchange="TeacherExams.toggleQuestionType()">${typeOpts}</select></div>
      <div class="field span-4"><label>النقاط</label><input id="qPoints" class="input" type="number" value="${esc(edit?.points||1)}" min="0.25" step="0.25"></div>
      <div class="field span-12"><label>نص السؤال</label><textarea id="qPrompt" class="input">${esc(edit?.prompt||'')}</textarea></div>
      <div class="field span-12" id="qOptionsBox" style="display:${showOptions?'block':'none'}"><label id="qOptionsLabel">الخيارات / الأزواج / الترتيب</label><textarea id="qOptions" class="input option-lines" placeholder="*الخيار الصحيح&#10;خيار آخر">${esc(optionsValue)}</textarea><div id="qAdvancedBox" class="advanced-question-builder" style="display:none"></div></div>
      <div class="field span-12" id="qAnswerBox" style="display:${showAnswer?'block':'none'}"><label id="qAnswerLabel">الإجابة الصحيحة / النموذجية</label><input id="qAnswer" class="input" value="${esc(answerValue)}" placeholder="للفراغات يمكن كتابة بدائل مفصولة بـ |"></div>
      <div class="field span-12"><label>شرح الإجابة</label><input id="qExplain" class="input" value="${esc(edit?.explanation||'')}"></div>
      <div class="span-12 form-actions">
        <button class="btn gold" onclick="TeacherExams.createQuestion()">${isEdit?'حفظ التعديل':'حفظ السؤال'}</button>
        ${isEdit?'<button class="btn" onclick="TeacherExams.cancelQuestionEdit()">إلغاء التعديل</button>':''}
      </div>
    </div></div></div>
    <div class="card"><div class="card-head"><h3>أسئلتي</h3></div><div class="card-body">${questionList(DATA.questions)}</div></div>`;
  setTimeout(()=>toggleQuestionType(),0);
}
function parseOptionsFromLines(txt){return String(txt||'').split(/\n+/).map(x=>x.trim()).filter(Boolean).map((line,i)=>({text:line.startsWith('*')?line.slice(1).trim():line,is_correct:line.startsWith('*'),sort_order:i})).filter(o=>o.text)}
function parsePairsFromLines(txt){return String(txt||'').split(/\n+/).map(x=>x.trim()).filter(Boolean).map(line=>{const parts=line.split(/\s*=\s*|\s*\|\s*|\s*:\s*/);return {left:(parts[0]||'').trim(),right:(parts.slice(1).join('=')||'').trim()}}).filter(p=>p.left||p.right)}
function parseItemsFromLines(txt){return String(txt||'').split(/\n+/).map(x=>x.trim()).filter(Boolean)}
function syncOptionBuilder(){const type=$('#qType')?.value;const rows=$$('#qAdvancedBox .option-build-row');const lines=rows.map(r=>{const input=$('.option-correct',r);const correct=input&&(input.checked);const val=$('.option-text',r).value.trim();return val?(correct?'*':'')+val:''}).filter(Boolean);$('#qOptions').value=lines.join('\n')}
function syncMatchingBuilder(){const rows=$$('#qAdvancedBox .match-build-row');const lines=rows.map(r=>`${$('.match-left',r).value.trim()} = ${$('.match-right',r).value.trim()}`).filter(x=>x.replace(/\s|=/g,''));$('#qOptions').value=lines.join('\n')}
function syncOrderingBuilder(){const method=$('input[name="orderMethod"]:checked')?.value||'direct';let items=$$('#qAdvancedBox .order-build-row').map((r,i)=>({text:$('.order-text',r).value.trim(),order:Number($('.order-num',r).value||i+1)})).filter(x=>x.text);if(method==='numbers')items=items.sort((a,b)=>a.order-b.order);$('#qOptions').value=items.map(x=>x.text).join('\n')}
function addOptionRow(text='',correct=false){const box=$('#optionRows');if(!box)return;const type=$('#qType')?.value||'mcq';const multi=type==='multi_select';const idx=box.children.length+1;box.insertAdjacentHTML('beforeend',`<div class="option-build-row"><span class="row-num">${idx}</span><input class="option-correct" name="optionCorrect" type="${multi?'checkbox':'radio'}" ${correct?'checked':''} title="الإجابة الصحيحة"><input class="input option-text" placeholder="نص الخيار" value="${esc(text)}"><button class="btn small red" type="button" onclick="this.closest('.option-build-row').remove();TeacherExams.syncOptionBuilder()">حذف</button></div>`);$$('input',box.lastElementChild).forEach(i=>i.addEventListener('input',syncOptionBuilder));$$('input',box.lastElementChild).forEach(i=>i.addEventListener('change',syncOptionBuilder));syncOptionBuilder()}
function addMatchingRow(left='',right=''){const box=$('#matchingRows');if(!box)return;const idx=box.children.length+1;box.insertAdjacentHTML('beforeend',`<div class="match-build-row"><span class="row-num">${idx}</span><input class="input match-left" placeholder="عنصر القائمة A" value="${esc(left)}"><span>↔</span><input class="input match-right" placeholder="العنصر المطابق في القائمة B" value="${esc(right)}"><button class="btn small red" type="button" onclick="this.closest('.match-build-row').remove();TeacherExams.syncMatchingBuilder()">حذف</button></div>`);$$('input',box.lastElementChild).forEach(i=>i.addEventListener('input',syncMatchingBuilder));syncMatchingBuilder()}
function addOrderingRow(text='',order=''){const box=$('#orderingRows');if(!box)return;const idx=box.children.length+1;box.insertAdjacentHTML('beforeend',`<div class="order-build-row" draggable="true"><span class="row-num">${idx}</span><input class="input order-text" placeholder="العنصر" value="${esc(text)}"><input class="input order-num" type="number" min="1" value="${esc(order||idx)}" title="رقم الترتيب الصحيح"><button class="btn small" type="button" onclick="this.closest('.order-build-row').previousElementSibling?.before(this.closest('.order-build-row'));TeacherExams.syncOrderingBuilder()">↑</button><button class="btn small" type="button" onclick="this.closest('.order-build-row').nextElementSibling?.after(this.closest('.order-build-row'));TeacherExams.syncOrderingBuilder()">↓</button><button class="btn small red" type="button" onclick="this.closest('.order-build-row').remove();TeacherExams.syncOrderingBuilder()">حذف</button></div>`);$$('input',box.lastElementChild).forEach(i=>i.addEventListener('input',syncOrderingBuilder));syncOrderingBuilder()}
function renderAdvancedBuilder(t){
  const box=$('#qAdvancedBox');if(!box)return;
  const optionBased=['mcq','true_false','multi_select','identify_error'];
  if(optionBased.includes(t)){
    let opts=parseOptionsFromLines($('#qOptions').value);
    if(t==='true_false'&&!opts.length)opts=[{text:'صح',is_correct:true},{text:'خطأ',is_correct:false}];
    if(!opts.length)opts=[{text:'',is_correct:true},{text:'',is_correct:false},{text:'',is_correct:false},{text:'',is_correct:false}];
    const note=t==='multi_select'?'يمكن تحديد أكثر من إجابة صحيحة.':t==='identify_error'?'حددي الكلمة/العبارة الخطأ كإجابة صحيحة.':'حددي الإجابة الصحيحة بنقرة واحدة مثل Google Forms.';
    box.innerHTML=`<div class="teacher-note">${esc(note)}</div><div id="optionRows" class="advanced-rows google-option-builder"></div><button class="btn blue" type="button" onclick="TeacherExams.addOptionRow()">إضافة خيار</button>`;
    opts.forEach(o=>addOptionRow(o.text,o.is_correct));
  }else if(t==='matching'){
    const pairs=parsePairsFromLines($('#qOptions').value);
    box.innerHTML=`<div class="teacher-note">أسلوب القائمتين: القائمة A للطالب مرقمة 1،2،3... والقائمة B بالحروف A،B،C... وتخلط تلقائياً. أدخلي كل زوج فقط.</div><div id="matchingRows" class="advanced-rows"></div><button class="btn blue" type="button" onclick="TeacherExams.addMatchingRow()">إضافة عنصر توصيل</button>`;
    (pairs.length?pairs:[{left:'',right:''},{left:'',right:''},{left:'',right:''}]).forEach(p=>addMatchingRow(p.left,p.right));
  }else if(t==='ordering'){
    const items=parseItemsFromLines($('#qOptions').value);
    box.innerHTML=`<div class="teacher-note">الترتيب المباشر: أضيفي العناصر بالترتيب الصحيح. أو استخدمي أرقام الترتيب. النظام يخلط العناصر للطالب تلقائياً.</div><div class="order-method"><label><input type="radio" name="orderMethod" value="direct" checked> الترتيب المباشر</label><label><input type="radio" name="orderMethod" value="numbers"> تحديد أرقام الترتيب</label></div><div id="orderingRows" class="advanced-rows"></div><button class="btn blue" type="button" onclick="TeacherExams.addOrderingRow()">إضافة عنصر ترتيب</button>`;
    $$('input[name="orderMethod"]',box).forEach(i=>i.addEventListener('change',syncOrderingBuilder));
    (items.length?items:['','']).forEach((it,i)=>addOrderingRow(it,i+1));
  }
}
function toggleQuestionType(){
  const t=$('#qType').value;
  const optionBased=['mcq','true_false','multi_select','identify_error'];
  const advancedList=['matching','ordering'];
  const answerBased=['fill_blank','essay','reading_comprehension','dialog_completion','grammar_correction','problem_solving','comparison','cause_effect','scenario'];
  const usesBuilder=[...optionBased,...advancedList].includes(t);
  $('#qOptionsBox').style.display=usesBuilder?'block':'none';
  $('#qAnswerBox').style.display=answerBased.includes(t)?'block':'none';
  const optLabel=$('#qOptionsLabel'), ansLabel=$('#qAnswerLabel'), optArea=$('#qOptions'), adv=$('#qAdvancedBox');
  if(optArea)optArea.style.display=usesBuilder?'none':'block';
  if(adv){adv.style.display=usesBuilder?'block':'none';if(usesBuilder&&(adv.dataset.type!==t||!adv.innerHTML.trim())){adv.dataset.type=t;renderAdvancedBuilder(t)}}
  if(optLabel){
    optLabel.textContent=t==='matching'?'قوائم التوصيل A و B':t==='ordering'?'عناصر الترتيب':t==='multi_select'?'اختيار متعدد الإجابات':t==='identify_error'?'تحديد الخطأ في جملة':'الخيارات';
  }
  if(ansLabel){ansLabel.textContent=t==='fill_blank'?'الإجابة الصحيحة والبدائل — افصليها بـ |':'الإجابة النموذجية للتصحيح اليدوي'}
}
function parseQuestionOptions(type){
  if(['mcq','true_false','multi_select','identify_error'].includes(type))syncOptionBuilder();
  const optionBased=['mcq','true_false','multi_select','identify_error'];
  if(!optionBased.includes(type)) return [];
  const lines=$('#qOptions').value.split(/\n+/).map(x=>x.trim()).filter(Boolean);
  if(lines.length<2){toast('تنبيه','أدخلي خيارين على الأقل','red');return null;}
  const opts=lines.map((line,i)=>({
    text:line.startsWith('*')?line.slice(1).trim():line,
    is_correct:line.startsWith('*'),
    sort_order:i
  })).filter(o=>o.text);
  if(!opts.some(o=>o.is_correct)){toast('تنبيه','ضعي * قبل الإجابة الصحيحة','red');return null;}
  if(type!=='multi_select'&&opts.filter(o=>o.is_correct).length>1){toast('تنبيه','هذا النوع يقبل إجابة صحيحة واحدة فقط','red');return null;}
  return opts;
}
function parseCorrectJson(type){
  if(type==='matching')syncMatchingBuilder();
  if(type==='ordering')syncOrderingBuilder();
  const txt=($('#qOptions')?.value||'').trim();
  const answer=($('#qAnswer')?.value||'').trim();
  if(type==='matching'){
    const pairs=txt.split(/\n+/).map(x=>x.trim()).filter(Boolean).map(line=>{
      const parts=line.split(/\s*=\s*|\s*\|\s*|\s*:\s*/);
      return {left:(parts[0]||'').trim(),right:(parts.slice(1).join('=')||'').trim()};
    }).filter(p=>p.left&&p.right);
    return {pairs};
  }
  if(type==='ordering'){
    return {items:txt.split(/\n+/).map(x=>x.trim()).filter(Boolean)};
  }
  if(type==='fill_blank'){
    const parts=answer.split('|').map(x=>x.trim()).filter(Boolean);
    return {acceptable_answers:parts.slice(1)};
  }
  return {};
}
function normalizedCorrectAnswer(type){
  const answer=($('#qAnswer')?.value||'').trim();
  if(type==='fill_blank') return answer.split('|').map(x=>x.trim()).filter(Boolean)[0]||'';
  return answer||'';
}
async function createQuestion(){
  const bank=DATA.banks.find(b=>String(b.id)===String($('#qBank').value));
  if(!bank){toast('تنبيه','اختاري بنك الأسئلة','red');return;}
  const prompt=$('#qPrompt').value.trim();
  if(!prompt){toast('تنبيه','اكتبي نص السؤال','red');return;}
  const type=$('#qType').value;
  const optionsPayload=parseQuestionOptions(type);
  if(optionsPayload===null) return;
  const correctJson=parseCorrectJson(type);
  if(type==='matching'&&!(correctJson.pairs||[]).length){toast('تنبيه','أدخلي أزواج المطابقة بصيغة: عنصر = مقابل','red');return;}
  if(type==='ordering'&&!(correctJson.items||[]).length){toast('تنبيه','أدخلي عناصر الترتيب الصحيح','red');return;}
  const payload={
    p_question_id:EDIT_QUESTION_ID||null,
    p_bank_id:bank.id,
    p_question_type:type,
    p_prompt:prompt,
    p_points:Number($('#qPoints').value||1),
    p_correct_answer:normalizedCorrectAnswer(type)||null,
    p_explanation:$('#qExplain')?.value||null,
    p_options:optionsPayload,
    p_correct_answer_json:correctJson
  };
  try{
    const {data,error}=await client().rpc('upsert_question_advanced',payload);
    if(error) throw error;
    if(data&&data.ok===false){toast('تعذر الحفظ',data.message||'خطأ غير معروف','red');return;}
    toast('تم الحفظ',data?.message||'تم حفظ السؤال','green');
    EDIT_QUESTION_ID=null;
    await load();
  }catch(e){toast('تعذر الحفظ',e.message||String(e),'red');}
}
function editQuestion(id){EDIT_QUESTION_ID=id;render('questions');setTimeout(()=>$('#mainContent')?.scrollTo?.(0,0),0);}
function cancelQuestionEdit(){EDIT_QUESTION_ID=null;render('questions');}
async function deleteQuestion(id){
  const q=DATA.questions.find(x=>String(x.id)===String(id));
  if(!q) return;
  const attempts=questionAttemptCount(id);
  const msg=attempts>0?'هذا السؤال مستخدم في محاولات طلاب، وغالباً سيمنع النظام حذفه حفاظاً على النتائج. هل تريدين المحاولة؟':'سيتم حذف السؤال وخياراته، وسيُزال من النماذج التي لم يبدأها الطلاب. هل تريدين المتابعة؟';
  if(!confirm(msg)) return;
  try{
    const {data,error}=await client().rpc('delete_question_safely',{p_question_id:id});
    if(error) throw error;
    if(data&&data.ok===false){toast('تعذر الحذف',data.message||'لم يتم الحذف','red');return;}
    if(EDIT_QUESTION_ID&&String(EDIT_QUESTION_ID)===String(id)) EDIT_QUESTION_ID=null;
    toast('تم',data?.message||'تم حذف السؤال','green');
    await load();
  }catch(e){toast('تعذر الحذف',e.message||String(e),'red');}
}
function questionList(list){
  return list.length?list.map(q=>{
    const attempts=questionAttemptCount(q.id);
    return `<div class="question-card ${q.is_active===false?'muted-card':''}">
      <div class="question-card-head">
        <div>
          <h4>${esc(q.prompt)}</h4>
          <div class="muted">${esc(typeLabel(q.question_type))} · ${esc(subjectName(q.subject_id))} · ${q.points} نقطة · ${esc(bankName(q.bank_id))}</div>
        </div>
        <div class="item-actions">
          ${q.is_active===false?'<span class="badge red">مؤرشف</span>':''}
          ${attempts?`<span class="badge blue">${attempts} محاولة</span>`:''}
          <button class="btn small blue" onclick="TeacherExams.editQuestion('${q.id}')">تعديل</button>
          <button class="btn small red" onclick="TeacherExams.deleteQuestion('${q.id}')">حذف</button>
        </div>
      </div>
    </div>`;
  }).join(''):'<div class="empty">لا توجد أسئلة</div>';
}

function buildView(){
  const edit=EDIT_EXAM_ID?DATA.exams.find(e=>String(e.id)===String(EDIT_EXAM_ID)):null;
  const isEdit=!!edit;
  const locked=isEdit && examAttempts(edit.id)>0;
  const selectedQids=isEdit?new Set(examQuestionIds(edit.id)):null;
  const firstQuestionId=isEdit?examQuestionIds(edit.id)[0]:null;
  const firstQuestion=firstQuestionId?DATA.questions.find(q=>String(q.id)===String(firstQuestionId)):null;
  const selectedBankId=firstQuestion?.bank_id||'';
  const bankOpts=opt(DATA.banks,'اختاري بنك الأسئلة',b=>b.title,b=>b.id,selectedBankId);
  const statusOpts=staticOptions([
    ['draft','مسودة'],['published','منشور'],['closed','مغلق'],['archived','مؤرشف']
  ],edit?.status||'draft');
  $('#view-build').innerHTML=`
    <div class="page-head"><div><h1>${isEdit?'تعديل النموذج الامتحاني':'إنشاء نموذج امتحاني'}</h1><p>اختاري بنكاً ثم حددي الأسئلة. إذا بدأ الطلاب محاولات، تُقفل بنية الأسئلة حفاظاً على النتائج.</p></div></div>
    ${locked?'<div class="alert warning">يوجد محاولات طلاب لهذا النموذج؛ يمكن تعديل العنوان والوقت والحالة فقط، ولا يمكن تغيير الأسئلة.</div>':''}
    <div class="card"><div class="card-body"><div class="exam-form">
      <div class="field span-4"><label>عنوان الاختبار</label><input id="examTitle" class="input" placeholder="اختبار قصير" value="${esc(edit?.title||'')}"></div>
      <div class="field span-4"><label>بنك الأسئلة</label><select id="examBank" class="select" onchange="TeacherExams.onExamBankChange()" ${locked?'disabled':''}>${bankOpts}</select></div>
      <div class="field span-4"><label>الحصة المرتبطة</label><select id="examSession" class="select"></select></div>
      <div class="field span-12"><label>وصف / تعليمات</label><input id="examDesc" class="input" value="${esc(edit?.description||'')}"></div>
      <div class="field span-3"><label>المدة بالدقائق</label><input id="examDuration" class="input" type="number" min="1" value="${esc(edit?.duration_minutes||20)}"></div>
      <div class="field span-3"><label>بداية الإتاحة</label><input id="examStart" class="input" type="datetime-local" value="${esc(toLocalDateTime(edit?.start_at))}"></div>
      <div class="field span-3"><label>نهاية الإتاحة</label><input id="examEnd" class="input" type="datetime-local" value="${esc(toLocalDateTime(edit?.end_at))}"></div>
      <div class="field span-3"><label>الحالة</label><select id="examStatus" class="select">${statusOpts}</select></div>
      <div class="span-12" id="questionPicker"></div>
      <div class="span-12 form-actions">
        <button class="btn gold" onclick="TeacherExams.createOnlineExam()">${isEdit?'حفظ تعديل النموذج':'حفظ النموذج'}</button>
        ${isEdit?'<button class="btn" onclick="TeacherExams.cancelExamEdit()">إلغاء التعديل</button>':''}
      </div>
    </div></div></div>
    <div class="card"><div class="card-head"><h3>نماذجي الامتحانية</h3></div><div class="card-body">${examList()}</div></div>`;
  const bank=DATA.banks.find(b=>String(b.id)===String($('#examBank')?.value));
  if($('#examSession')) $('#examSession').innerHTML=sessionOptions(bank&&(bank.section_id||bank.class_id),bank&&bank.subject_id,edit?.class_session_id||'');
  renderQuestionPicker(selectedQids);
}
function onExamBankChange(){
  renderQuestionPicker(null);
  const bank=DATA.banks.find(b=>String(b.id)===String($('#examBank')?.value));
  if($('#examSession')) $('#examSession').innerHTML=sessionOptions(bank&&(bank.section_id||bank.class_id),bank&&bank.subject_id,'');
}
function renderQuestionPicker(selectedIds=null){
  const box=$('#questionPicker');
  if(!box) return;
  const bankId=$('#examBank')?.value;
  const locked=EDIT_EXAM_ID && examAttempts(EDIT_EXAM_ID)>0;
  const qs=DATA.questions.filter(q=>q.is_active!==false && (!bankId||String(q.bank_id)===String(bankId)));
  box.innerHTML=qs.length?`
    <div class="picker-tools"><b>أسئلة النموذج</b><small class="muted">حددي الأسئلة المطلوبة داخل النموذج.</small></div>
    ${qs.map(q=>{
      const checked=selectedIds?selectedIds.has(String(q.id)):true;
      return `<label class="question-pick">
        <input type="checkbox" class="exam-question" value="${q.id}" ${checked?'checked':''} ${locked?'disabled':''}>
        <div><b>${esc(q.prompt)}</b><small class="muted">${esc(typeLabel(q.question_type))} · ${q.points} نقطة</small></div>
        <span class="badge blue">${esc(subjectName(q.subject_id))}</span>
      </label>`;
    }).join('')}`:'<div class="empty">لا توجد أسئلة نشطة في هذا البنك</div>';
}
async function createOnlineExam(){
  if(EDIT_EXAM_ID) return updateOnlineExam();
  const bank=DATA.banks.find(b=>String(b.id)===String($('#examBank').value));
  const title=$('#examTitle').value.trim();
  const qids=$$('.exam-question:checked').map(c=>c.value);
  if(!bank||!title||!qids.length){toast('تنبيه','اختاري البنك والعنوان والأسئلة','red');return;}
  let total=0;
  for(const id of qids){const q=DATA.questions.find(x=>String(x.id)===String(id));total+=Number(q&&q.points||1);}
  const {data:exam,error}=await client().from('online_exams').insert({
    title,
    description:$('#examDesc')?.value||null,
    teacher_id:ME.id,
    class_id:bank.class_id,
    section_id:bank.section_id,
    subject_id:bank.subject_id,
    class_session_id:$('#examSession')?.value||null,
    duration_minutes:Number($('#examDuration').value||20),
    start_at:toIsoOrNull($('#examStart').value),
    end_at:toIsoOrNull($('#examEnd').value),
    status:$('#examStatus').value,
    total_points:total,
    shuffle_questions:true,
    shuffle_options:true
  }).select().single();
  if(error){toast('تعذر إنشاء النموذج',error.message,'red');return;}
  let order=0;
  for(const id of qids){
    const q=DATA.questions.find(x=>String(x.id)===String(id));
    await client().from('online_exam_questions').insert({exam_id:exam.id,question_id:id,points:Number(q&&q.points||1),sort_order:order++});
  }
  toast('تم إنشاء النموذج','يمكن للطلاب رؤيته عند النشر وضمن الوقت المحدد','green');
  await load();
}
async function updateOnlineExam(){
  const exam=DATA.exams.find(e=>String(e.id)===String(EDIT_EXAM_ID));
  if(!exam) return;
  const locked=examAttempts(exam.id)>0;
  const bank=DATA.banks.find(b=>String(b.id)===String($('#examBank').value));
  const title=$('#examTitle').value.trim();
  const qids=locked?examQuestionIds(exam.id):$$('.exam-question:checked').map(c=>c.value);
  if(!title){toast('تنبيه','اكتبي عنوان النموذج','red');return;}
  if(!locked&&(!bank||!qids.length)){toast('تنبيه','اختاري البنك والأسئلة','red');return;}
  try{
    const {data,error}=await client().rpc('update_online_exam_model',{
      p_exam_id:exam.id,
      p_bank_id:bank?.id||null,
      p_title:title,
      p_description:$('#examDesc')?.value||null,
      p_duration_minutes:Number($('#examDuration').value||20),
      p_start_at:toIsoOrNull($('#examStart').value),
      p_end_at:toIsoOrNull($('#examEnd').value),
      p_status:$('#examStatus').value,
      p_class_session_id:$('#examSession')?.value||null,
      p_question_ids:qids
    });
    if(error) throw error;
    if(data&&data.ok===false){toast('تعذر التعديل',data.message||'لم يتم التعديل','red');return;}
    toast('تم الحفظ',data?.message||'تم تعديل النموذج',data?.locked_questions?'':'green');
    EDIT_EXAM_ID=null;
    await load();
  }catch(e){toast('تعذر التعديل',e.message||String(e),'red');}
}
function editExam(id){EDIT_EXAM_ID=id;render('build');setTimeout(()=>$('#mainContent')?.scrollTo?.(0,0),0);}
function cancelExamEdit(){EDIT_EXAM_ID=null;render('build');}
async function deleteExam(id){
  const ex=DATA.exams.find(e=>String(e.id)===String(id));
  if(!ex) return;
  const attempts=examAttempts(id);
  const msg=attempts>0?'يوجد محاولات طلاب لهذا النموذج؛ سيتم أرشفته بدل حذفه حفاظاً على النتائج. هل تريدين المتابعة؟':'سيتم حذف النموذج الامتحاني وأسئلته المرتبطة من جدول النماذج. هل تريدين المتابعة؟';
  if(!confirm(msg)) return;
  try{
    const {data,error}=await client().rpc('delete_online_exam_safely',{p_exam_id:id});
    if(error) throw error;
    if(data&&data.ok===false){toast('تعذر الحذف',data.message||'لم يتم الحذف','red');return;}
    if(EDIT_EXAM_ID&&String(EDIT_EXAM_ID)===String(id)) EDIT_EXAM_ID=null;
    toast('تم',data?.message||'تم حذف النموذج','green');
    await load();
  }catch(e){toast('تعذر الحذف',e.message||String(e),'red');}
}
async function cloneExam(id){
  const ex=DATA.exams.find(e=>String(e.id)===String(id));
  if(!ex)return;
  const title=prompt('اسم النسخة الجديدة:',(ex.title||'اختبار')+' — نسخة');
  if(title===null)return;
  try{
    const {data,error}=await client().rpc('clone_online_exam_model',{p_exam_id:id,p_new_title:title,p_status:'draft'});
    if(error)throw error;
    if(data&&data.ok===false){toast('تعذر النسخ',data.message||'لم يتم النسخ','red');return;}
    toast('تم النسخ',data?.message||'تم نسخ النموذج كمسودة','green');
    await load();
  }catch(e){toast('تعذر النسخ',e.message||String(e),'red');}
}
async function quickExamStatus(id,status){
  const label=statusLabel(status);
  if(!confirm('هل تريدين تغيير حالة النموذج إلى: '+label+'؟'))return;
  try{
    const {data,error}=await client().rpc('set_online_exam_status',{p_exam_id:id,p_status:status});
    if(error)throw error;
    if(data&&data.ok===false){toast('تعذر تغيير الحالة',data.message||'لم يتم التغيير','red');return;}
    toast('تم التحديث','تم تغيير حالة النموذج إلى '+label,'green');
    await load();
  }catch(e){toast('تعذر تغيير الحالة',e.message||String(e),'red');}
}
async function regradeExam(id){
  if(!confirm('سيتم إعادة تصحيح كل المحاولات المسلّمة لهذا النموذج. هل تريدين المتابعة؟'))return;
  try{
    const {data,error}=await client().rpc('regrade_online_exam',{p_exam_id:id});
    if(error)throw error;
    if(data&&data.ok===false){toast('تعذر إعادة التصحيح',data.message||'لم يتم التصحيح','red');return;}
    toast('تمت إعادة التصحيح','عدد المحاولات: '+(data?.attempts_count||0),'green');
    await load();
  }catch(e){toast('تعذر إعادة التصحيح',e.message||String(e),'red');}
}
function examList(){
  return DATA.exams.length?DATA.exams.map(e=>{
    const attempts=examAttempts(e.id);
    const qCount=examQuestionIds(e.id).length;
    const canPublish=e.status!=='published';
    const canClose=e.status==='published';
    return `<div class="item exam-item">
      <div>
        <b>${esc(e.title)}</b>
        <small>${esc(subjectName(e.subject_id))} · ${e.duration_minutes} دقيقة · ${qCount} سؤال · ${attempts} محاولة</small>
      </div>
      <div class="item-actions">
        <span class="exam-status ${esc(e.status)}">${esc(statusLabel(e.status))}</span>
        <button class="btn small blue" onclick="TeacherExams.editExam('${e.id}')">تعديل</button>
        <button class="btn small" onclick="TeacherExams.cloneExam('${e.id}')">نسخ</button>
        ${attempts?`<button class="btn small gold" onclick="TeacherExams.regradeExam('${e.id}')">إعادة التصحيح</button>`:''}
        ${canPublish?`<button class="btn small blue" onclick="TeacherExams.quickExamStatus('${e.id}','published')">نشر</button>`:''}
        ${canClose?`<button class="btn small" onclick="TeacherExams.quickExamStatus('${e.id}','closed')">إغلاق</button>`:''}
        <button class="btn small red" onclick="TeacherExams.deleteExam('${e.id}')">حذف</button>
      </div>
    </div>`;
  }).join(''):'<div class="empty">لا توجد نماذج امتحانية</div>';
}

const GEN_TYPES=[
  ['mcq','اختيار من متعدد','موضوعي'],['true_false','صح وخطأ — انقر للاختيار','موضوعي'],['fill_blank','إكمال فراغات — مرن إملائياً','موضوعي'],['matching','توصيل/مطابقة','موضوعي'],['ordering','ترتيب خطوات/أحداث/أرقام','موضوعي'],['multi_select','اختيار من متعدد بإجابات متعددة','موضوعي'],['identify_error','تحديد الخطأ في جملة','موضوعي'],
  ['reading_comprehension','قراءة نص وإجابة أسئلة عليه','تطبيقي'],['dialog_completion','إكمال حوار/محادثة','تطبيقي'],['grammar_correction','تصحيح خطأ نحوي/إملائي','تطبيقي'],['problem_solving','حل مسائل مع خطوات الحل','تطبيقي'],
  ['essay','مقالي/إجابة قصيرة','تفكير عليا'],['comparison','مقارنة في جدول','تفكير عليا'],['cause_effect','سبب ونتيجة','تفكير عليا'],['scenario','تطبيق على موقف جديد','تفكير عليا']
];
function generatorView(){
  const typeRows=GEN_TYPES.map(([id,label,group])=>`<div class="generator-count"><label>${esc(label)}<small>${esc(group)}</small></label><input id="gen_count_${id}" class="input" type="number" min="0" value="${['mcq','true_false','fill_blank'].includes(id)?2:0}"><input id="gen_points_${id}" class="input" type="number" min="0.25" step="0.25" value="1" title="درجة السؤال"></div>`).join('');
  $('#view-generator').innerHTML=`
    <div class="page-head"><div><h1>مولد النماذج الامتحانية</h1><p>أداة محلية بدون روابط خارجية: تبني نص طلب احترافي وقالب CSV للنماذج أ، ب، ج...</p></div></div>
    <div class="card"><div class="card-body"><div class="exam-form">
      <div class="field span-3"><label>عدد النماذج</label><input id="genModels" class="input" type="number" min="1" max="10" value="3"></div>
      <div class="field span-3"><label>المادة</label><input id="genSubject" class="input" placeholder="مثال: اللغة العربية"></div>
      <div class="field span-3"><label>الصف</label><input id="genGrade" class="input" placeholder="مثال: الأول الابتدائي"></div>
      <div class="field span-3"><label>الفصل الدراسي</label><input id="genTerm" class="input" placeholder="الفصل الأول"></div>
      <div class="field span-3"><label>اللغة</label><select id="genLang" class="select"><option>عربي</option><option>إنجليزي</option><option>ثنائي اللغة</option></select></div>
      <div class="field span-3"><label>التنسيق المطلوب</label><select id="genTarget" class="select"><option>موقعي</option><option>Google Forms</option><option>Word</option></select></div>
      <div class="field span-3"><label>درجة النموذج التقريبية</label><input id="genTotal" class="input" type="number" min="1" value="100"></div>
      <div class="field span-3"><label>مستوى الصعوبة</label><select id="genDifficulty" class="select"><option>متوسط</option><option>سهل</option><option>متدرج</option><option>صعب</option></select></div>
      <div class="field span-12"><label>الدروس/المحاور المطلوبة</label><textarea id="genTopics" class="input" placeholder="اكتبي الدروس أو ألصقي نصاً قصيراً يعتمد عليه الاختبار"></textarea></div>
      <div class="span-12 generator-grid">${typeRows}</div>
      <div class="span-12 form-actions"><button class="btn gold" onclick="TeacherExams.generateExamPrompt()">توليد نص الطلب</button><button class="btn blue" onclick="TeacherExams.copyGeneratorPrompt()">نسخ النص</button><button class="btn" onclick="TeacherExams.exportGeneratorCsv()">تنزيل قالب CSV</button><button class="btn" onclick="TeacherExams.exportGeneratorTxt()">تنزيل TXT</button></div>
      <div class="field span-12"><label>النص الجاهز</label><textarea id="generatorOutput" class="input generator-output" placeholder="اضغطي توليد نص الطلب..."></textarea></div>
    </div></div></div>`;
}
function genVal(id){return ($('#'+id)?.value||'').trim();}
function modelLetters(n){const letters=['أ','ب','ج','د','هـ','و','ز','ح','ط','ي'];return letters.slice(0,Math.max(1,Math.min(10,Number(n||1))));}
function generatorSpec(){
  const counts=GEN_TYPES.map(([id,label,group])=>({id,label,group,count:Number(genVal('gen_count_'+id)||0),points:Number(genVal('gen_points_'+id)||1)})).filter(x=>x.count>0);
  return {models:Number(genVal('genModels')||1),subject:genVal('genSubject')||'[اسم المادة]',grade:genVal('genGrade')||'[الصف]',term:genVal('genTerm')||'[الفصل الدراسي]',lang:genVal('genLang')||'عربي',target:genVal('genTarget')||'موقعي',total:Number(genVal('genTotal')||100),difficulty:genVal('genDifficulty')||'متوسط',topics:genVal('genTopics')||'استخدم المنهج المدرسي والدروس المحددة من المعلم.',counts};
}
function buildGeneratorPrompt(){
  const s=generatorSpec();
  const countLines=s.counts.map(x=>`- ${x.label}: ${x.count} سؤال × ${x.points} درجة`).join('\n')||'- حددي عدد الأسئلة لكل نوع.';
  const models=modelLetters(s.models).map(x=>'نموذج '+x).join('، ');
  return `أنت خبير في إعداد الاختبارات المدرسية الإلكترونية.\nأريد إنشاء ${s.models} نماذج امتحانية مختلفة (${models}) لمادة ${s.subject} للصف ${s.grade} - ${s.term}.\n\n=== المواصفات العامة ===\n- اللغة: ${s.lang}\n- مستوى الصعوبة: ${s.difficulty}\n- الدرجة الكلية التقريبية لكل نموذج: ${s.total}\n- التنسيق المطلوب: جاهز للنسخ إلى ${s.target}\n- لا تستخدم أي روابط خارجية ولا تعتمد على CDN أو مصادر محجوبة.\n\n=== الدروس/المحاور ===\n${s.topics}\n\n=== أنواع الأسئلة المطلوبة ===\n${countLines}\n\n=== متطلبات الإخراج ===\n1. اجعل كل نموذج في جدول منفصل وواضح، ويبدأ الترقيم من جديد في كل نموذج.\n2. للأسئلة الموضوعية القابلة للتصحيح الآلي اكتبها بصيغة CSV واضحة: النموذج، رقم السؤال، نوع السؤال، نص السؤال، الخيار 1، الخيار 2، الخيار 3، الخيار 4، الإجابة الصحيحة، الدرجة، الشرح.\n3. لصح وخطأ: اجعل الاختيار بالنقر لا بالكتابة.\n4. للفراغات: ضع الإجابة الصحيحة وبدائل مقبولة لدعم الأخطاء الإملائية والمعاني القريبة.\n5. للمطابقة: اكتب الأزواج الصحيحة بصيغة عنصر = مقابل.\n6. للترتيب: اكتب العناصر بالترتيب الصحيح.\n7. للأسئلة المقالية والتطبيقية فقط: أنشئ Answer Key بجدول: رقم السؤال - الإجابة النموذجية - الدرجة.\n8. في نهاية كل نموذج اكتب ملخصاً: عدد الأسئلة، مجموع الدرجات، ونسبة كل نوع سؤال من المجموع.\n9. اجعل النماذج متكافئة في الصعوبة لكنها مختلفة في النصوص والأرقام وترتيب الأسئلة.\n`;
}
function generateExamPrompt(){const out=$('#generatorOutput');out.value=buildGeneratorPrompt();out.focus();out.select();toast('تم التوليد','تم تجهيز نص الطلب وقالبه','green');}
async function copyGeneratorPrompt(){const out=$('#generatorOutput');if(!out.value)generateExamPrompt();try{await navigator.clipboard.writeText(out.value);toast('تم النسخ','تم نسخ نص الطلب','green');}catch{out.focus();out.select();document.execCommand('copy');toast('تم النسخ','تم نسخ النص','green');}}
function exportGeneratorTxt(){const out=$('#generatorOutput');if(!out.value)generateExamPrompt();const blob=new Blob([out.value],{type:'text/plain;charset=utf-8'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='exam-generator-prompt.txt';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}
function exportGeneratorCsv(){
  const s=generatorSpec();const headers=['النموذج','رقم السؤال','نوع السؤال','نص السؤال','الخيار 1','الخيار 2','الخيار 3','الخيار 4','الإجابة الصحيحة','الدرجة','الشرح/مفتاح الإجابة'];const rows=[];
  modelLetters(s.models).forEach(letter=>{let n=1;s.counts.forEach(t=>{for(let i=0;i<t.count;i++){rows.push({'النموذج':'نموذج '+letter,'رقم السؤال':n++,'نوع السؤال':t.label,'نص السؤال':'','الخيار 1':'','الخيار 2':'','الخيار 3':'','الخيار 4':'','الإجابة الصحيحة':'','الدرجة':t.points,'الشرح/مفتاح الإجابة':''});}});});
  if(!rows.length){toast('تنبيه','حددي عدد سؤال واحد على الأقل','red');return;}
  downloadCsv('exam-models-template.csv',headers,rows);
}

function resultsView(){
  const rows=(DATA.analysis||[]).map(a=>`<tr><td>${esc(a.title)}</td><td>${esc(a.class_name||'—')} ${a.section_code?' / '+esc(a.section_code):''}</td><td>${esc(a.subject_name||'—')}</td><td>${a.attempts_count||0}</td><td>${a.submitted_count||0}</td><td>${a.average_percent??'—'}%</td><td>${a.highest_percent?Math.round(a.highest_percent):'—'}%</td><td>${a.lowest_percent?Math.round(a.lowest_percent):'—'}%</td></tr>`);
  const qRows=(DATA.questionAnalysis||[]).slice(0,80).map(q=>`<tr><td>${esc(q.exam_title||'—')}</td><td>${esc((q.prompt||'').slice(0,90))}</td><td>${esc(typeLabel(q.question_type))}</td><td>${q.answers_count||0}</td><td>${q.correct_count||0}</td><td>${q.correct_percent??'—'}%</td><td>${q.average_score??'—'}</td></tr>`);
  const attemptRows=(DATA.attemptDetails||[]).slice(0,120).map(a=>`<tr><td>${esc(a.exam_title||'—')}</td><td>${esc(a.student_name||'—')}</td><td>${esc(a.class_name||'—')} ${a.section_code?' / '+esc(a.section_code):''}</td><td>${fmtDate(a.started_at)}</td><td>${fmtDate(a.submitted_at)}</td><td>${esc(attemptStatus(a.status))}</td><td>${a.score??'—'} / ${a.max_score??'—'}<br><small class="muted">${a.percent??'—'}%</small></td><td>${a.answered_count||0}</td><td>${a.violations_count||0}</td></tr>`);
  const detailedManual=(DATA.answerDetails||[]).filter(a=>!a.is_draft && ['essay','reading_comprehension','dialog_completion','grammar_correction','problem_solving','comparison','cause_effect','scenario','image','audio'].includes(a.question_type));
  const essay=detailedManual.length?detailedManual:(DATA.answers||[]).filter(a=>a.score_awarded==null && (a.answer_text||Object.keys(a.answer_json||{}).length));
  $('#view-results').innerHTML=`
    <div class="page-head"><div><h1>النتائج والتحليل</h1><p>متوسطات الاختبارات، تحليل الأسئلة، ومحاولات الطلاب بالتفصيل.</p></div><div class="top-actions"><button class="btn blue" onclick="TeacherExams.exportAttemptsCsv()">تصدير CSV</button></div></div>
    <div class="card"><div class="card-head"><h3>تحليل الاختبارات</h3></div><div class="card-body">${table(['الاختبار','الصف/الشعبة','المادة','محاولات','مسلّم','متوسط','أعلى','أقل'],rows,'لا توجد نتائج بعد')}</div></div>
    <div class="card"><div class="card-head"><h3>تحليل الأسئلة</h3></div><div class="card-body">${table(['الاختبار','السؤال','النوع','إجابات','صحيح','نسبة الصحة','متوسط الدرجة'],qRows,'لا توجد بيانات تحليل للأسئلة بعد')}</div></div>
    <div class="card"><div class="card-head"><h3>محاولات الطلاب</h3></div><div class="card-body">${table(['الاختبار','الطالب','الصف/الشعبة','بدأ','سلّم','الحالة','الدرجة','إجابات','تنبيهات'],attemptRows,'لا توجد محاولات بعد')}</div></div>
    <div class="card"><div class="card-head"><h3>إجابات تحتاج تصحيحاً يدوياً</h3></div><div class="card-body">${manualAnswersList(essay)}</div></div>`;
}
function manualAnswersList(list){
  return list.length?list.slice(0,40).map(a=>{
    const id=a.answer_id||a.id;
    const answer=a.answer_text||a.selected_option_text||JSON.stringify(a.answer_json||{});
    return `<div class="question-card manual-grade-card">
      <h4>${esc(a.exam_title||'إجابة تحتاج مراجعة')} — ${esc(a.student_name||'طالب')}</h4>
      <div class="muted">${esc(a.subject_name||'')} ${a.class_name?' · '+esc(a.class_name):''} ${a.section_code?' / '+esc(a.section_code):''}</div>
      <p><b>السؤال:</b> ${esc(a.prompt||'—')}</p>
      <p><b>إجابة الطالب:</b> ${esc(answer||'—')}</p>
      ${a.correct_answer||a.correct_option_text?`<p class="muted"><b>الإجابة المرجعية:</b> ${esc(a.correct_answer||a.correct_option_text)}</p>`:''}
      <div class="manual-grade-row">
        <input class="input" id="manualScore_${id}" type="number" min="0" max="${esc(a.max_points||100)}" step="0.25" placeholder="الدرجة من ${esc(a.max_points||'') }" value="${a.score_awarded??''}">
        <input class="input" id="manualFeedback_${id}" placeholder="تعليق للطالب" value="${esc(a.feedback||'')}">
        <button class="btn gold" onclick="TeacherExams.manualGrade('${id}')">حفظ التصحيح</button>
      </div>
    </div>`;
  }).join(''):'<div class="empty">لا توجد إجابات تحتاج تصحيحاً يدوياً</div>';
}
async function manualGrade(answerId){
  const score=Number($(`#manualScore_${answerId}`).value||0);
  const feedback=$(`#manualFeedback_${answerId}`).value||null;
  try{
    const {data,error}=await client().rpc('manual_grade_exam_answer',{p_answer_id:answerId,p_score:score,p_feedback:feedback});
    if(error) throw error;
    if(data&&data.ok===false){toast('تعذر التصحيح',data.message||'خطأ','red');return;}
    toast('تم التصحيح','تم تحديث نتيجة المحاولة','green');
    await load();
  }catch(e){toast('تعذر التصحيح',e.message,'red');}
}
function table(h,rows,empty='لا توجد بيانات'){
  const body=Array.isArray(rows)?rows.join(''):String(rows||'');
  return body.trim()?`<div class="table-wrap"><table><thead><tr>${h.map(x=>`<th>${esc(x)}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>`:`<div class="empty">${esc(empty)}</div>`;
}
function exportAttemptsCsv(){
  const headers=['الاختبار','الطالب','الصف','الشعبة','الحالة','بدأ','سلّم','الدرجة','الدرجة العظمى','النسبة','تنبيهات','عدد الإجابات'];
  const rows=(DATA.attemptDetails||[]).map(a=>({
    'الاختبار':a.exam_title||'',
    'الطالب':a.student_name||'',
    'الصف':a.class_name||'',
    'الشعبة':a.section_code||'',
    'الحالة':attemptStatus(a.status),
    'بدأ':fmtDate(a.started_at),
    'سلّم':fmtDate(a.submitted_at),
    'الدرجة':a.score??'',
    'الدرجة العظمى':a.max_score??'',
    'النسبة':a.percent??'',
    'تنبيهات':a.violations_count||0,
    'عدد الإجابات':a.answered_count||0
  }));
  if(!rows.length){toast('لا توجد بيانات','لا توجد محاولات لتصديرها','red');return;}
  downloadCsv('online-exam-attempts.csv',headers,rows);
}
function bind(){
  $$('.nav button[data-view]').forEach(b=>b.addEventListener('click',()=>render(b.dataset.view)));
  $('#mobileMenuBtn')?.addEventListener('click',()=>$('#sidebar').classList.toggle('open'));
  $('#logoutBtn').addEventListener('click',async()=>{await client().auth.signOut({scope:'local'});location.href='index.html';});
  $('#refreshBtn').addEventListener('click',load);
}
async function init(){client();if(!await ensure())return;bind();await load();}

window.TeacherExams={
  init,render,
  updateBankSubjects,createBank,
  toggleQuestionType,addOptionRow,addMatchingRow,addOrderingRow,syncOptionBuilder,syncMatchingBuilder,syncOrderingBuilder,createQuestion,editQuestion,cancelQuestionEdit,deleteQuestion,
  renderQuestionPicker,onExamBankChange,createOnlineExam,editExam,cancelExamEdit,deleteExam,cloneExam,quickExamStatus,regradeExam,
  manualGrade,exportAttemptsCsv,generateExamPrompt,copyGeneratorPrompt,exportGeneratorCsv,exportGeneratorTxt
};
}());

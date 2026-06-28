/* Online Exams — Student Player */
(function(){
'use strict';

let sb=null, ME=null, STUDENT=null;
let DATA={exams:[],attempts:[]}, CURRENT=null, TIMER=null, AUTOSAVE=null, VIOLATIONS=0, REMAINING=0, ACTIVE='available';
const cfg=()=>window.AMIN_CONFIG||{};
const $=(s,r=document)=>r.querySelector(s);
const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));

function client(){if(sb)return sb;sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});return sb;}
function esc(v){return String(v==null?'':v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));}
function toast(t,m,type=''){
  const el=$('#toast');
  if(!el) return alert((t||'')+'\n'+(m||''));
  el.innerHTML=`<b>${esc(t)}</b><br><span class="muted">${esc(m||'')}</span>`;
  el.className='toast show '+type;
  clearTimeout(el._t);
  el._t=setTimeout(()=>el.classList.remove('show'),4200);
}
function fmtDate(v){if(!v)return'—';try{return new Date(v).toLocaleString('ar-IQ')}catch{return v}}
async function q(table,opts={}){
  try{
    let query=client().from(table).select(opts.columns||'*');
    (opts.filters||[]).forEach(f=>query=query[f.op](f.col,f.val));
    if(opts.order)query=query.order(opts.order,{ascending:opts.ascending!==false});
    if(opts.limit)query=query.limit(opts.limit);
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
  if(!u){location.href='index.html';return false;}
  $('#profileName').textContent=u.name||u.email||'مستخدم';
  $('#profileRole').textContent=u.role==='student'?'طالب':(u.role==='parent'?'ولي أمر':u.role||'طالب');
  let st=null;
  if(u.role==='student') st=(await q('students',{filters:[{op:'eq',col:'user_id',val:u.id}],limit:1}))[0];
  else if(u.role==='parent') st=(await q('students',{filters:[{op:'eq',col:'parent_id',val:u.id}],limit:1}))[0];
  if(!st){document.body.innerHTML='<main class="login-page"><section class="login-card"><h1>لا يوجد طالب مرتبط</h1><p>لا يمكن فتح الاختبارات قبل ربط الحساب بسجل طالب.</p></section></main>';return false;}
  STUDENT=st;
  return true;
}
async function load(){
  DATA.exams=await q('online_exams',{order:'created_at',ascending:false});
  DATA.attempts=await q('exam_attempts',{filters:[{op:'eq',col:'student_id',val:STUDENT.id}],order:'created_at',ascending:false});
  render(ACTIVE);
}
function cleanupExamListeners(){
  document.removeEventListener('visibilitychange',handleVisibilityWarning);
  document.removeEventListener('copy',blockExamEvent);
  document.removeEventListener('paste',blockExamEvent);
  document.removeEventListener('cut',blockExamEvent);
}
function render(id){
  ACTIVE=id;
  $$('.view').forEach(v=>v.classList.toggle('active',v.id==='view-'+id));
  $$('.nav button[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view===id));
  ({available:availableView,attempts:attemptsView,player:playerView}[id]||availableView)();
}
function statusLabel(s){return ({in_progress:'قيد الحل',submitted:'مسلّم',graded:'مصحح',expired:'منتهي الوقت',cancelled:'ملغى'}[s]||s||'—');}
function typeLabel(t){return ({mcq:'اختيار من متعدد',true_false:'صح وخطأ',multi_select:'اختيار متعدد الإجابات',fill_blank:'إكمال فراغ',matching:'مطابقة',ordering:'ترتيب',identify_error:'تحديد الخطأ',reading_comprehension:'قراءة وفهم',dialog_completion:'إكمال حوار',grammar_correction:'تصحيح خطأ',problem_solving:'حل مسائل',essay:'مقالي',comparison:'مقارنة',cause_effect:'سبب ونتيجة',scenario:'موقف تطبيقي'}[t]||t||'—');}
function examState(e){
  const now=Date.now(), start=e.start_at?new Date(e.start_at).getTime():0, end=e.end_at?new Date(e.end_at).getTime():Infinity;
  if(e.status!=='published')return['غير منشور','draft'];
  if(now<start)return['لم يبدأ','draft'];
  if(now>end)return['منتهي','closed'];
  return['متاح','published'];
}
function latestAttempt(examId){return DATA.attempts.filter(a=>String(a.exam_id)===String(examId)).sort((a,b)=>new Date(b.started_at)-new Date(a.started_at))[0]||null;}
function availableView(){
  const cards=DATA.exams.map(e=>{
    const [label,cls]=examState(e);
    const at=DATA.attempts.filter(a=>String(a.exam_id)===String(e.id));
    const inProgress=at.find(a=>a.status==='in_progress');
    const done=at.some(a=>['submitted','graded'].includes(a.status));
    const last=latestAttempt(e.id);
    const canOpen=cls==='published'&&!done;
    const btnLabel=inProgress?'متابعة الاختبار':'بدء الاختبار';
    const saved=inProgress&&inProgress.last_saved_at?`<br>آخر حفظ: ${fmtDate(inProgress.last_saved_at)}`:'';
    const result=done&&last?`<br>الدرجة: ${last.score??'—'} / ${last.max_score??'—'}`:'';
    return `<div class="question-card">
      <h4>${esc(e.title)}</h4>
      <div class="muted">${esc(e.description||'')}<br>المدة: ${e.duration_minutes} دقيقة · من ${fmtDate(e.start_at)} إلى ${fmtDate(e.end_at)}${saved}${result}</div>
      <div class="exam-card-actions">
        <span class="exam-status ${cls}">${label}${done?' · تم التسليم':inProgress?' · قيد الحل':''}</span>
        <button class="btn gold" ${canOpen?'':'disabled'} onclick="OnlineExams.startExam('${e.id}')">${btnLabel}</button>
      </div>
    </div>`;
  }).join('');
  $('#view-available').innerHTML=`<div class="page-head"><div><h1>الاختبارات المتاحة</h1><p>${esc(STUDENT.name||'طالب')} — تظهر هنا الاختبارات المنشورة والمتاحة لك، ويمكن متابعة المحاولة المفتوحة.</p></div></div>${cards||'<div class="empty">لا توجد اختبارات متاحة حالياً.</div>'}`;
}
function attemptsView(){
  const rows=DATA.attempts.map(a=>{
    const e=DATA.exams.find(x=>String(x.id)===String(a.exam_id));
    const percent=a.max_score>0&&a.score!=null?Math.round(Number(a.score)/Number(a.max_score)*100)+'%':'—';
    return `<tr><td>${esc(e&&e.title||'—')}</td><td>${fmtDate(a.started_at)}</td><td>${fmtDate(a.submitted_at)}</td><td><span class="badge ${a.status==='graded'?'green':a.status==='in_progress'?'blue':'gold'}">${esc(statusLabel(a.status))}</span></td><td>${a.score??'—'} / ${a.max_score??'—'}<br><small class="muted">${percent}</small></td><td>${a.violations_count||0}</td></tr>`;
  });
  $('#view-attempts').innerHTML=`<div class="page-head"><div><h1>محاولاتي</h1><p>سجل الاختبارات التي بدأتها أو سلمتها.</p></div></div>${table(['الاختبار','بدأ','سلم','الحالة','الدرجة','تنبيهات'],rows,'لا توجد محاولات')}`;
}
function table(h,rows,empty){const body=rows.join('');return body?`<div class="table-wrap"><table><thead><tr>${h.map(x=>`<th>${esc(x)}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>`:`<div class="empty">${esc(empty)}</div>`;}

async function startExam(id){
  try{
    cleanupExamListeners();
    clearInterval(TIMER);clearTimeout(AUTOSAVE);
    const {data,error}=await client().rpc('start_online_exam_attempt',{p_exam_id:id});
    if(error)throw error;
    if(data&&data.ok===false){toast('تعذر البدء',data.message||'الاختبار غير متاح','red');return;}
    const payload=await getPayload(id);
    if(!payload.ok){toast('تعذر تحميل الاختبار',payload.message||'خطأ','red');return;}
    payload.attempt=payload.attempt||{id:data.attempt_id,started_at:new Date().toISOString(),status:'in_progress'};
    CURRENT=payload;
    VIOLATIONS=Number(payload.attempt.violations_count||0);
    render('player');
    startTimer();
    if(data.resumed) toast('متابعة الاختبار','تم استرجاع المحاولة السابقة','green');
  }catch(e){toast('تعذر بدء الاختبار',e.message,'red');}
}
async function getPayload(id){const {data,error}=await client().rpc('get_online_exam_payload',{p_exam_id:id});if(error)throw error;return data;}
function startTimer(){
  clearInterval(TIMER);
  const mins=Number(CURRENT.exam.duration_minutes||0);
  const started=CURRENT.attempt&&CURRENT.attempt.started_at?new Date(CURRENT.attempt.started_at).getTime():Date.now();
  const end=started+mins*60*1000;
  function tick(){
    REMAINING=Math.max(0,Math.floor((end-Date.now())/1000));
    const el=$('#timer');
    if(el){const m=Math.floor(REMAINING/60),s=REMAINING%60;el.textContent=`${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;if(REMAINING<60)el.classList.add('danger');}
    if(REMAINING<=0){clearInterval(TIMER);submitExam(true);}
  }
  tick();TIMER=setInterval(tick,1000);
}
function draftAnswer(qid){return (CURRENT?.draft_answers||[]).find(a=>String(a.question_id)===String(qid))||null;}
function playerView(){
  if(!CURRENT){$('#view-player').innerHTML='<div class="empty">لا يوجد اختبار مفتوح</div>';return;}
  const qs=CURRENT.questions||[];
  const drafts=(CURRENT.draft_answers||[]).length;
  $('#view-player').innerHTML=`<div class="exam-player">
    <div class="page-head"><div><h1>${esc(CURRENT.exam.title)}</h1><p>${esc(CURRENT.exam.description||'')}</p></div><div class="timer" id="timer">--:--</div></div>
    <div class="exam-progress"><span style="width:0%" id="progressBar"></span></div>
    <div id="autosaveStatus" class="alert ${drafts?'success':'info'}" style="margin:10px 0">${drafts?'تم استرجاع مسودة إجابات محفوظة.':'يتم حفظ الإجابات تلقائياً أثناء الاختبار.'}</div>
    <form id="examForm">${qs.map((q,i)=>questionHTML(q,i)).join('')}<div class="toolbar"><button type="button" class="btn gold" onclick="OnlineExams.submitExam(false)">تسليم الاختبار</button></div></form>
    <div id="resultBox"></div>
  </div>`;
  bindAnswerProgress();
}
function questionHTML(q,i){return `<div class="question-card" data-q="${q.id}"><h4>${i+1}. ${esc(q.prompt)}</h4><div class="muted">${esc(typeLabel(q.question_type))} · ${q.points} نقطة</div>${answerHTML(q)}</div>`;}
function draftJson(qid){return draftAnswer(qid)?.answer_json||{};}
function answerHTML(q){
  const d=draftAnswer(q.id);
  const aj=draftJson(q.id);
  if(['mcq','true_false','identify_error'].includes(q.question_type)){
    return `<div class="answer-box">${(q.options||[]).map(o=>`<label class="answer-option"><input type="radio" name="q_${q.id}" value="${o.id}" ${d&&String(d.selected_option_id)===String(o.id)?'checked':''}> <span>${esc(o.text)}</span></label>`).join('')}</div>`;
  }
  if(q.question_type==='multi_select'){
    const selected=new Set((aj.selected_option_ids||[]).map(String));
    return `<div class="answer-box">${(q.options||[]).map(o=>`<label class="answer-option"><input type="checkbox" name="q_${q.id}" value="${o.id}" ${selected.has(String(o.id))?'checked':''}> <span>${esc(o.text)}</span></label>`).join('')}</div>`;
  }
  if(q.question_type==='matching'){
    const saved=new Map((aj.pairs||[]).map(p=>[String(p.left||''),String(p.right||'')]));
    const left=q.interaction?.left_items||[];
    const rights=q.interaction?.right_options||[];
    const letters='ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    const bList=`<div class="match-list-b"><b>القائمة B</b>${rights.map((r,i)=>`<div><span class="match-letter">${letters[i]||i+1}</span> ${esc(r)}</div>`).join('')}</div>`;
    const aList=`<div class="match-list-a"><b>القائمة A</b>${left.map((l,i)=>`<div class="match-row"><span>${i+1}. ${esc(l)}</span><select class="select match-select" data-q="${q.id}" data-left="${esc(l)}"><option value="">اختاري الحرف</option>${rights.map((r,j)=>`<option value="${esc(r)}" ${saved.get(String(l))===String(r)?'selected':''}>${letters[j]||j+1}</option>`).join('')}</select></div>`).join('')}</div>`;
    return `<div class="match-official">${aList}${bList}</div>`;
  }
  if(q.question_type==='ordering'){
    const saved=aj.items||[];
    const items=q.interaction?.items||[];
    const n=items.length;
    return `<div class="order-box">${Array.from({length:n}).map((_,i)=>`<div class="match-row"><span>الترتيب ${i+1}</span><select class="select order-select" data-q="${q.id}" data-pos="${i}"><option value="">اختاري العنصر</option>${items.map(it=>`<option value="${esc(it)}" ${String(saved[i]||'')===String(it)?'selected':''}>${esc(it)}</option>`).join('')}</select></div>`).join('')}</div>`;
  }
  const val=d?.answer_text||'';
  if(q.question_type==='fill_blank')return `<input class="input answer-text" data-q="${q.id}" placeholder="اكتب الإجابة" value="${esc(val)}">`;
  return `<textarea class="input answer-text" data-q="${q.id}" placeholder="اكتب إجابتك"></textarea>`.replace('</textarea>',`${esc(val)}</textarea>`);
}
function bindAnswerProgress(){
  const form=$('#examForm');if(!form)return;
  cleanupExamListeners();
  form.addEventListener('input',()=>{updateProgress();scheduleAutosave();});
  form.addEventListener('change',()=>{updateProgress();scheduleAutosave();});
  document.addEventListener('visibilitychange',handleVisibilityWarning);
  document.addEventListener('copy',blockExamEvent);
  document.addEventListener('paste',blockExamEvent);
  document.addEventListener('cut',blockExamEvent);
  updateProgress();
}
function updateProgress(){
  if(!CURRENT)return;
  const total=(CURRENT.questions||[]).length;
  let answered=0;
  (CURRENT.questions||[]).forEach(q=>{
    if(['mcq','true_false','identify_error'].includes(q.question_type)){if($(`input[name="q_${q.id}"]:checked`))answered++;}
    else if(q.question_type==='multi_select'){if($$(`input[name="q_${q.id}"]:checked`).length)answered++;}
    else if(q.question_type==='matching'){
      const sels=$$(`.match-select[data-q="${q.id}"]`);if(sels.length&&sels.every(s=>s.value))answered++;
    }else if(q.question_type==='ordering'){
      const sels=$$(`.order-select[data-q="${q.id}"]`);if(sels.length&&sels.every(s=>s.value))answered++;
    }else{if(($(`[data-q="${q.id}"]`)||{}).value)answered++;}
  });
  const p=total?Math.round(answered/total*100):0;
  const bar=$('#progressBar');if(bar)bar.style.width=p+'%';
}
function setAutosaveStatus(msg,type='info'){
  const el=$('#autosaveStatus');if(!el)return;
  el.className='alert '+(type==='red'?'error':type==='green'?'success':'info');
  el.textContent=msg;
}
function scheduleAutosave(){clearTimeout(AUTOSAVE);AUTOSAVE=setTimeout(saveDraftAnswers,700);}
async function saveDraftAnswers(){
  if(!CURRENT||!CURRENT.attempt)return;
  const answers=collectAnswers();
  let saved=0;
  for(const a of answers){
    if(!a.selected_option_id && !a.answer_text && !a.answer_json)continue;
    try{
      const {data,error}=await client().rpc('save_exam_answer_draft',{p_attempt_id:CURRENT.attempt.id,p_question_id:a.question_id,p_selected_option_id:a.selected_option_id||null,p_answer_text:a.answer_text||null,p_answer_json:a.answer_json||{}});
      if(error)throw error;
      if(!data||data.ok!==false)saved++;
    }catch(e){console.warn('autosave failed',e);}
  }
  if(saved) setAutosaveStatus('تم الحفظ التلقائي لآخر إجاباتك','green');
}
async function handleVisibilityWarning(){
  if(!CURRENT||!CURRENT.attempt||document.visibilityState==='visible')return;
  VIOLATIONS++;
  setAutosaveStatus('تنبيه: تم تسجيل مغادرة صفحة الاختبار. عدد التنبيهات: '+VIOLATIONS,'red');
  try{await client().rpc('record_exam_attempt_violation',{p_attempt_id:CURRENT.attempt.id,p_reason:'visibility_change'});}catch(e){console.warn(e);}
}
function blockExamEvent(e){if(!CURRENT)return;e.preventDefault();setAutosaveStatus('تم تعطيل النسخ/اللصق أثناء الاختبار','red');try{client().rpc('record_exam_attempt_violation',{p_attempt_id:CURRENT.attempt.id,p_reason:e.type||'copy_paste'}).then(()=>{}).catch(()=>{});}catch{}}
function collectAnswers(){
  return (CURRENT.questions||[]).map(q=>{
    if(['mcq','true_false','identify_error'].includes(q.question_type)){
      const checked=$(`input[name="q_${q.id}"]:checked`);
      return {question_id:q.id,selected_option_id:checked?checked.value:null};
    }
    if(q.question_type==='multi_select'){
      const ids=$$(`input[name="q_${q.id}"]:checked`).map(x=>x.value);
      return {question_id:q.id,answer_json:{selected_option_ids:ids}};
    }
    if(q.question_type==='matching'){
      const pairs=$$(`.match-select[data-q="${q.id}"]`).map(s=>({left:s.dataset.left,right:s.value})).filter(p=>p.left&&p.right);
      return {question_id:q.id,answer_json:{pairs}};
    }
    if(q.question_type==='ordering'){
      const items=$$(`.order-select[data-q="${q.id}"]`).sort((a,b)=>Number(a.dataset.pos)-Number(b.dataset.pos)).map(s=>s.value).filter(Boolean);
      return {question_id:q.id,answer_json:{items}};
    }
    const el=$(`[data-q="${q.id}"]`);
    return {question_id:q.id,answer_text:el?el.value:''};
  });
}
async function submitExam(auto=false){
  if(!CURRENT||!CURRENT.attempt)return;
  if(!auto&&!confirm('هل تريد تسليم الاختبار؟ لا يمكن التعديل بعد التسليم.'))return;
  clearInterval(TIMER);clearTimeout(AUTOSAVE);
  try{
    await saveDraftAnswers();
    const answers=collectAnswers();
    const {data,error}=await client().rpc('submit_online_exam_attempt',{p_attempt_id:CURRENT.attempt.id,p_answers:answers});
    if(error)throw error;
    if(data&&data.ok===false){toast('تعذر التسليم',data.message||'خطأ','red');return;}
    const g=data.grading||{};
    cleanupExamListeners();
    CURRENT=null;
    ACTIVE='attempts';
    await load();
    toast('تم التسليم',`تم حفظ وتصحيح الاختبار — النتيجة: ${g.percent??'—'}%`,'green');
  }catch(e){toast('تعذر التسليم',e.message,'red');}
}
function bind(){
  $$('.nav button[data-view]').forEach(b=>b.addEventListener('click',()=>render(b.dataset.view)));
  $('#mobileMenuBtn')?.addEventListener('click',()=>$('#sidebar').classList.toggle('open'));
  $('#logoutBtn').addEventListener('click',async()=>{await client().auth.signOut({scope:'local'});location.href='index.html';});
  $('#refreshBtn').addEventListener('click',load);
}
async function init(){client();if(!await ensure())return;bind();await load();}
window.OnlineExams={init,render,startExam,submitExam};
}());

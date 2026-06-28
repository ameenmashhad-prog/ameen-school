/* Exam Integrity — similarity, source match, AI-likelihood indicators */
(function(){
'use strict';

let sb=null, ME=null, ACTIVE='overview';
let DATA={flags:[],pairs:[],sourceMatches:[],sources:[],exams:[],questions:[]};
const cfg=()=>window.AMIN_CONFIG||{};
const $=(s,r=document)=>r.querySelector(s);
const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));

function client(){if(sb)return sb;sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});return sb;}
function esc(v){return String(v==null?'':v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));}
function toast(t,m,type=''){
  const el=$('#toast');
  if(!el)return alert((t||'')+'\n'+(m||''));
  el.innerHTML=`<b>${esc(t)}</b><br><span class="muted">${esc(m||'')}</span>`;
  el.className='toast show '+type;
  clearTimeout(el._t);
  el._t=setTimeout(()=>el.classList.remove('show'),4500);
}
function fmtDate(v){if(!v)return'—';try{return new Date(v).toLocaleString('ar-IQ')}catch{return v}}
function roleLabel(r){return ({admin:'إدارة',teacher:'معلم',academic:'أكاديمي',academic_admin:'إدارة أكاديمية',scientific:'علمي',supervisor:'مشرف'}[r]||r||'مستخدم');}
function riskClass(score){score=Number(score||0);return score>=80?'red':score>=60?'gold':score>=35?'blue':'green';}
function sourceTypeLabel(t){return ({internet_paste:'نص من الإنترنت',ai_sample:'نموذج AI',book:'كتاب/ملزمة',teacher_reference:'مرجع المعلم',other:'أخرى'}[t]||t||'—');}
function csvCell(v){const s=String(v==null?'':v).replace(/"/g,'""');return /[",\n]/.test(s)?`"${s}"`:s;}
function downloadCsv(filename,headers,rows){const csv='\ufeff'+[headers.map(csvCell).join(','),...rows.map(r=>headers.map(h=>csvCell(r[h])).join(','))].join('\n');const blob=new Blob([csv],{type:'text/csv;charset=utf-8'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=filename;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}

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
  const {data:u,error}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();
  if(error||!u){location.href='index.html';return false;}
  ME=u;
  const allowed=u.is_super_admin||['admin','teacher','academic','academic_admin','scientific','supervisor'].includes(u.role);
  if(!allowed){document.body.innerHTML='<main class="login-page"><section class="login-card"><h1>غير مصرح</h1><p>هذه الصفحة للمعلمين والإدارة فقط.</p></section></main>';return false;}
  $('#profileName').textContent=u.name||u.email||'مستخدم';
  $('#profileRole').textContent=roleLabel(u.role);
  return true;
}
async function load(){
  const [flags,pairs,sourceMatches,sources,exams,questions]=await Promise.all([
    q('v_exam_integrity_answer_flags',{order:'risk_score',ascending:false,limit:250}),
    q('v_exam_answer_similarity_pairs',{order:'similarity_score',ascending:false,limit:250}),
    q('v_exam_answer_source_matches',{order:'source_similarity',ascending:false,limit:250}),
    q('exam_reference_sources',{order:'created_at',ascending:false,limit:200}),
    q('online_exams',{order:'created_at',ascending:false,limit:300}),
    q('questions',{order:'created_at',ascending:false,limit:500})
  ]);
  DATA={flags,pairs,sourceMatches,sources,exams,questions};
  render(ACTIVE);
}
function render(id){
  ACTIVE=id;
  $$('.view').forEach(v=>v.classList.toggle('active',v.id==='view-'+id));
  $$('.nav button[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view===id));
  ({overview,flags:flagsView,pairs:pairsView,sourceMatches:sourceMatchesView,ai:aiView,sources:sourcesView}[id]||overview)();
}
function kpi(label,value,cls='blue'){return `<div class="kpi ${cls}"><small>${esc(label)}</small><b>${esc(value)}</b></div>`;}
function overview(){
  const high=DATA.flags.filter(x=>Number(x.risk_score||0)>=70).length;
  const peer=DATA.pairs.filter(x=>Number(x.similarity_score||0)>=0.80).length;
  const src=DATA.sourceMatches.filter(x=>Number(x.source_similarity||0)>=0.68).length;
  const ai=DATA.flags.filter(x=>Number(x.ai_likelihood_score||0)>=65).length;
  const rows=DATA.flags.slice(0,12).map(flagRow);
  $('#view-overview').innerHTML=`
    <div class="page-head"><div><h1>كشف نزاهة الاختبارات</h1><p>يكشف التطابق بين الطلاب، ويقارن مع مصادر محلية يلصقها المعلم، ويعرض مؤشرات احتمالية للذكاء الاصطناعي.</p></div></div>
    <div class="alert warning integrity-note"><b>تنبيه مهم:</b> مؤشرات الذكاء الاصطناعي والتشابه ليست حكماً نهائياً. استخدميها كبداية مراجعة فقط، ثم قارني مع مستوى الطالب وسياق الاختبار.</div>
    <div class="kpis">${kpi('إنذارات عالية',high,'red')}${kpi('تطابق طلاب قوي',peer,'gold')}${kpi('مطابقة مصادر',src,'blue')}${kpi('مؤشرات AI',ai,'green')}</div>
    <div class="card"><div class="card-head"><h3>أعلى الإنذارات</h3></div><div class="card-body">${table(['الخطر','الاختبار','الطالب','السؤال','الأسباب','تشابه طلاب','مصادر','AI'],rows,'لا توجد إنذارات حالياً')}</div></div>`;
}
function flagsView(){
  const rows=DATA.flags.map(flagRow);
  $('#view-flags').innerHTML=`<div class="page-head"><div><h1>الإنذارات الموحدة</h1><p>درجة خطر تجمع التشابه بين الطلاب، مطابقة المصادر، مؤشرات AI، وسرعة الإدخال/التنبيهات.</p></div></div>${table(['الخطر','الاختبار','الطالب','السؤال','الأسباب','تشابه طلاب','مصادر','AI','النص'],rows,'لا توجد إجابات مفحوصة')}`;
}
function flagRow(x){
  const flags=(x.flags||[]).map(f=>`<span class="badge ${riskClass(x.risk_score)}">${esc(f)}</span>`).join(' ')||'<span class="muted">—</span>';
  const q=(x.prompt||'').slice(0,90);
  const text=x.answer_text||'';
  return `<tr>
    <td><span class="risk-pill ${riskClass(x.risk_score)}">${Number(x.risk_score||0)}%</span></td>
    <td>${esc(x.exam_title||'—')}<br><small class="muted">${esc(x.subject_name||'')}</small></td>
    <td>${esc(x.student_name||'—')}<br><small class="muted">${esc(x.class_name||'')} ${x.section_code?' / '+esc(x.section_code):''}</small></td>
    <td>${esc(q)}</td>
    <td>${flags}</td>
    <td>${Math.round(Number(x.max_peer_similarity||0)*100)}%</td>
    <td>${Math.round(Number(x.max_source_similarity||0)*100)}%</td>
    <td>${Number(x.ai_likelihood_score||0)}%</td>
    <td><details><summary>عرض</summary><div class="answer-preview">${esc(text)}</div></details></td>
  </tr>`;
}
function pairsView(){
  const rows=DATA.pairs.map(x=>`<tr>
    <td><span class="risk-pill ${riskClass(x.similarity_percent)}">${x.similarity_percent}%</span><br><small>${esc(x.risk_label)}</small></td>
    <td>${esc(x.exam_title||'—')}</td>
    <td>${esc(x.student_a_name||'—')} ↔ ${esc(x.student_b_name||'—')}</td>
    <td>${esc((x.prompt||'').slice(0,120))}</td>
    <td><details><summary>الإجابتان</summary><div class="compare-grid"><div><b>${esc(x.student_a_name||'طالب')}</b><p>${esc(x.answer_a_preview||'')}</p></div><div><b>${esc(x.student_b_name||'طالب')}</b><p>${esc(x.answer_b_preview||'')}</p></div></div></details></td>
  </tr>`);
  $('#view-pairs').innerHTML=`<div class="page-head"><div><h1>تطابق إجابات الطلاب</h1><p>يقارن إجابات الطلاب داخل نفس السؤال ونفس الاختبار باستخدام تشابه النصوص بعد التطبيع.</p></div></div>${table(['التشابه','الاختبار','الطلاب','السؤال','المقارنة'],rows,'لا يوجد تطابق عالٍ بين الطلاب')}`;
}
function sourceMatchesView(){
  const rows=DATA.sourceMatches.map(x=>`<tr>
    <td><span class="risk-pill ${riskClass(x.source_similarity_percent)}">${x.source_similarity_percent}%</span><br><small>${esc(x.risk_label)}</small></td>
    <td>${esc(x.exam_title||'—')}</td>
    <td>${esc(x.student_name||'—')}</td>
    <td>${esc(x.source_title||'—')}<br><small class="muted">${esc(sourceTypeLabel(x.source_type))}</small></td>
    <td>${esc((x.prompt||'').slice(0,100))}</td>
    <td><details><summary>مقارنة</summary><div class="compare-grid"><div><b>إجابة الطالب</b><p>${esc(x.answer_preview||'')}</p></div><div><b>المصدر</b><p>${esc(x.source_preview||'')}</p></div></div></details></td>
  </tr>`);
  $('#view-sourceMatches').innerHTML=`<div class="page-head"><div><h1>مطابقة المصادر</h1><p>يقارن الإجابات مع النصوص التي تلصقها الإدارة أو المعلم في مصادر المقارنة. لا يستخدم الإنترنت مباشرة.</p></div></div>${table(['التشابه','الاختبار','الطالب','المصدر','السؤال','المقارنة'],rows,'لا توجد مطابقات مع المصادر المحلية')}`;
}
function aiView(){
  const list=DATA.flags.filter(x=>Number(x.ai_likelihood_score||0)>=35).sort((a,b)=>Number(b.ai_likelihood_score||0)-Number(a.ai_likelihood_score||0));
  const rows=list.map(x=>`<tr>
    <td><span class="risk-pill ${riskClass(x.ai_likelihood_score)}">${x.ai_likelihood_score}%</span></td>
    <td>${esc(x.exam_title||'—')}</td>
    <td>${esc(x.student_name||'—')}</td>
    <td>${esc((x.prompt||'').slice(0,100))}</td>
    <td>${(x.ai_likelihood_reasons||[]).map(r=>`<span class="badge gold">${esc(r)}</span>`).join(' ')||'—'}</td>
    <td><details><summary>النص</summary><div class="answer-preview">${esc(x.answer_text||'')}</div></details></td>
  </tr>`);
  $('#view-ai').innerHTML=`<div class="page-head"><div><h1>مؤشرات الذكاء الاصطناعي</h1><p>هذه مؤشرات احتمالية فقط، مثل الطول الزائد، العبارات العامة، والتنظيم غير المعتاد.</p></div></div><div class="alert info">لا يوجد كشف AI مضمون 100%. لا تعاقبي الطالب اعتماداً على هذه النسبة وحدها.</div>${table(['المؤشر','الاختبار','الطالب','السؤال','الأسباب','الإجابة'],rows,'لا توجد مؤشرات AI واضحة')}`;
}
function sourcesView(){
  const examOpts='<option value="">عام لكل الاختبارات</option>'+DATA.exams.map(e=>`<option value="${e.id}">${esc(e.title)}</option>`).join('');
  const rows=DATA.sources.map(s=>`<div class="question-card">
    <div class="question-card-head"><div><h4>${esc(s.title)}</h4><div class="muted">${esc(sourceTypeLabel(s.source_type))} · ${fmtDate(s.created_at)}</div></div><button class="btn small red" onclick="ExamIntegrity.deleteSource('${s.id}')">حذف</button></div>
    ${s.source_url?`<div class="muted">${esc(s.source_url)}</div>`:''}
    <p>${esc((s.content_text||'').slice(0,350))}${(s.content_text||'').length>350?'...':''}</p>
  </div>`).join('');
  $('#view-sources').innerHTML=`
    <div class="page-head"><div><h1>مصادر المقارنة المحلية</h1><p>ألصقي هنا نصاً من موقع/كتاب/ذكاء اصطناعي ليقارنه النظام مع إجابات الطلاب. لا يتم فتح أي رابط خارجياً.</p></div></div>
    <div class="card"><div class="card-body"><div class="exam-form">
      <div class="field span-4"><label>عنوان المصدر</label><input id="srcTitle" class="input" placeholder="مثال: مقال من الإنترنت عن التلوث"></div>
      <div class="field span-4"><label>نوع المصدر</label><select id="srcType" class="select"><option value="internet_paste">نص من الإنترنت</option><option value="ai_sample">نموذج AI</option><option value="book">كتاب/ملزمة</option><option value="teacher_reference">مرجع المعلم</option><option value="other">أخرى</option></select></div>
      <div class="field span-4"><label>اختبار مرتبط اختياري</label><select id="srcExam" class="select">${examOpts}</select></div>
      <div class="field span-12"><label>رابط/ملاحظة اختيارية — لا يتم فتحه</label><input id="srcUrl" class="input" placeholder="اكتبي الرابط أو اسم المصدر فقط"></div>
      <div class="field span-12"><label>النص المراد المقارنة معه</label><textarea id="srcContent" class="input source-text" placeholder="الصقي النص هنا..."></textarea></div>
      <div class="span-12"><button class="btn gold" onclick="ExamIntegrity.addSource()">إضافة مصدر مقارنة</button></div>
    </div></div></div>
    <div class="card"><div class="card-head"><h3>المصادر الحالية</h3></div><div class="card-body">${rows||'<div class="empty">لا توجد مصادر مقارنة بعد</div>'}</div></div>`;
}
async function addSource(){
  const title=$('#srcTitle')?.value.trim();
  const content=$('#srcContent')?.value.trim();
  if(!title||!content||content.length<40){toast('تنبيه','أدخلي عنواناً ونصاً لا يقل عن 40 حرفاً','red');return;}
  try{
    const {error}=await client().from('exam_reference_sources').insert({
      teacher_id:ME.id,
      title,
      source_type:$('#srcType').value,
      source_url:$('#srcUrl').value||null,
      exam_id:$('#srcExam').value||null,
      content_text:content
    });
    if(error)throw error;
    toast('تمت الإضافة','تم إضافة مصدر المقارنة','green');
    await load();render('sources');
  }catch(e){toast('تعذر الإضافة',e.message||String(e),'red');}
}
async function deleteSource(id){
  if(!confirm('حذف مصدر المقارنة؟'))return;
  try{
    const {error}=await client().from('exam_reference_sources').delete().eq('id',id);
    if(error)throw error;
    toast('تم الحذف','تم حذف المصدر','green');
    await load();render('sources');
  }catch(e){toast('تعذر الحذف',e.message||String(e),'red');}
}
function table(h,rows,empty='لا توجد بيانات'){
  const body=Array.isArray(rows)?rows.join(''):String(rows||'');
  return body.trim()?`<div class="table-wrap"><table><thead><tr>${h.map(x=>`<th>${esc(x)}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>`:`<div class="empty">${esc(empty)}</div>`;
}
function exportFlagsCsv(){
  const headers=['الخطر','الاختبار','الطالب','الصف','الشعبة','السؤال','الأسباب','تشابه الطلاب','تشابه المصادر','مؤشر AI','سرعة الإدخال','النص'];
  const rows=DATA.flags.map(x=>({
    'الخطر':x.risk_score||0,
    'الاختبار':x.exam_title||'',
    'الطالب':x.student_name||'',
    'الصف':x.class_name||'',
    'الشعبة':x.section_code||'',
    'السؤال':x.prompt||'',
    'الأسباب':(x.flags||[]).join(' | '),
    'تشابه الطلاب':Math.round(Number(x.max_peer_similarity||0)*100),
    'تشابه المصادر':Math.round(Number(x.max_source_similarity||0)*100),
    'مؤشر AI':x.ai_likelihood_score||0,
    'سرعة الإدخال':x.chars_per_minute||'',
    'النص':x.answer_text||''
  }));
  if(!rows.length){toast('لا توجد بيانات','لا توجد إنذارات للتصدير','red');return;}
  downloadCsv('exam-integrity-flags.csv',headers,rows);
}
function bind(){
  $$('.nav button[data-view]').forEach(b=>b.addEventListener('click',()=>render(b.dataset.view)));
  $('#mobileMenuBtn')?.addEventListener('click',()=>$('#sidebar').classList.toggle('open'));
  $('#logoutBtn').addEventListener('click',async()=>{await client().auth.signOut({scope:'local'});location.href='index.html';});
  $('#refreshBtn').addEventListener('click',load);
  $('#exportBtn').addEventListener('click',exportFlagsCsv);
}
async function init(){client();if(!await ensure())return;bind();await load();}
window.ExamIntegrity={init,render,addSource,deleteSource,exportFlagsCsv};
}());

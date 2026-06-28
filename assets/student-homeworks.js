/* Student/Parent Homework Viewer */
(function(){
'use strict';
let sb=null,ME=null,ACTIVE='homeworks',DATA={homeworks:[],attachments:[],students:[],submissionAttachments:[],comments:[],debug:null},CURRENT_STUDENT_ID=null,SUBMISSION_FILES=new Map(),VIEW_MARKED=new Set();
const cfg=()=>window.AMIN_CONFIG||{};
const $=(s,r=document)=>r.querySelector(s);
const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
function client(){if(sb)return sb;sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});return sb}
function esc(v){return String(v==null?'':v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
function toast(t,m,type=''){const el=$('#toast');if(!el)return;el.innerHTML=`<b>${esc(t)}</b><br><span class="muted">${esc(m||'')}</span>`;el.className='toast show '+type;clearTimeout(el._t);el._t=setTimeout(()=>el.classList.remove('show'),4200)}
function fmtDate(v){if(!v)return'—';try{return new Date(v).toLocaleString('ar-IQ')}catch{return v}}
function roleLabel(r){return r==='parent'?'ولي أمر':r==='student'?'طالب':(r||'مستخدم')}
async function q(table,opts={}){try{let query=client().from(table).select(opts.columns||'*');(opts.filters||[]).forEach(f=>query=query[f.op](f.col,f.val));if(opts.order)query=query.order(opts.order,{ascending:opts.ascending!==false});if(opts.limit)query=query.limit(opts.limit);const {data,error}=await query;if(error){console.warn(table,error);return[]}return data||[]}catch(e){console.warn(table,e);return[]}}
async function ensure(){const {data:{session}}=await client().auth.getSession();if(!session){location.href='index.html';return false}const {data:u}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();if(!u){location.href='index.html';return false}ME=u;$('#profileName').textContent=u.name||u.email;$('#profileRole').textContent=roleLabel(u.role);if(!['student','parent'].includes(u.role)){document.body.innerHTML='<main class="login-page"><section class="login-card"><h1>غير مصرح</h1><p>هذه الصفحة للطلاب وأولياء الأمور.</p></section></main>';return false}return true}
async function load(){
  const filters=ME.role==='student'?[{op:'eq',col:'user_id',val:ME.id}]:[{op:'eq',col:'parent_id',val:ME.id}];
  const students=await q('students',{filters,order:'name'});
  let homeworks=[];
  // نستخدم RPC أولاً حتى لا نعتمد على PostgREST schema cache للـ View.
  try{
    const {data,error}=await client().rpc('get_student_homeworks_payload');
    if(error)throw error;
    if(data&&data.ok===false)throw new Error(data.message||'تعذر تحميل الواجبات');
    homeworks=(data&&data.homeworks)||[];DATA.debug=data&&data.debug||null;
  }catch(e){
    console.warn('get_student_homeworks_payload failed, trying view',e);
    try{
      const {data,error}=await client().from('v_student_homeworks').select('*').order('due_date',{ascending:true}).limit(300);
      if(error)throw error;
      homeworks=data||[];
    }catch(e2){
      console.warn('v_student_homeworks fallback failed',e2);
      // fallback أخير: قراءة مباشرة من homeworks إن كانت الـ Function/View لم تدخل cache بعد.
      const raw=await q('homeworks',{filters:[{op:'in',col:'status',val:['published','closed']}],order:'due_date',ascending:true,limit:300});
      homeworks=raw.map(h=>{
        const st=students.find(s=>String(s.section_id||s.class_id)===String(h.section_id||h.class_id));
        return st?{...h,homework_id:h.id,student_id:st.id,student_name:st.name,class_name:'',section_code:'',subject_name:'',teacher_name:'',grade_score:null,attachment_count:0}:null;
      }).filter(Boolean);
    }
  }
  const [attachments,submissionAttachments,comments]=await Promise.all([q('homework_attachments',{order:'sort_order',limit:500}),q('homework_submission_attachments',{order:'sort_order',limit:500}),q('v_homework_submission_comments_detailed',{order:'created_at',limit:500})]);
  DATA={students,homeworks,attachments,submissionAttachments,comments,debug:DATA.debug||null};
  if(!CURRENT_STUDENT_ID&&students[0])CURRENT_STUDENT_ID=students[0].id;
  render(ACTIVE);
}
function switcher(){if(DATA.students.length<=1)return'';return `<select class="select" onchange="StudentHomeworks.setStudent(this.value)">${DATA.students.map(s=>`<option value="${s.id}" ${String(s.id)===String(CURRENT_STUDENT_ID)?'selected':''}>${esc(s.name)}</option>`).join('')}</select>`}
function setStudent(id){CURRENT_STUDENT_ID=id;render(ACTIVE)}
function scopedHomeworks(){return DATA.homeworks.filter(h=>!CURRENT_STUDENT_ID||String(h.student_id)===String(CURRENT_STUDENT_ID))}
function attFor(hwId){return DATA.attachments.filter(a=>String(a.homework_id)===String(hwId)).sort((a,b)=>(a.sort_order||0)-(b.sort_order||0))}
function subAttFor(submissionId){return (DATA.submissionAttachments||[]).filter(a=>String(a.submission_id)===String(submissionId)).sort((a,b)=>(a.sort_order||0)-(b.sort_order||0))}
function commentsFor(submissionId){return (DATA.comments||[]).filter(c=>String(c.submission_id)===String(submissionId)).sort((a,b)=>new Date(a.created_at)-new Date(b.created_at))}
function isLate(h){if(!h.due_date)return false;const due=new Date(h.due_date+'T'+(h.due_time||'23:59'));return Date.now()>due.getTime()&&h.status==='published'}
function statusBadge(h){if(h.status==='closed')return '<span class="badge red">مغلق</span>';if(isLate(h))return '<span class="badge gold">متأخر</span>';return '<span class="badge green">منشور</span>'}
function submissionBadge(h){const s=h.submission_status;if(!s)return '<span class="badge blue">لم يتم التسليم</span>';return `<span class="badge ${s==='graded'?'green':s==='late'?'red':s==='submitted'?'gold':'blue'}">${esc({draft:'مسودة حل',submitted:'تم التسليم',late:'تسليم متأخر',graded:'مصحح',returned:'معاد'}[s]||s)}</span>`}
function homeworkCard(h){
  const atts=attFor(h.homework_id);
  const grade=h.grade_score!=null?`<div class="homework-grade-box"><b>${esc(h.grade_score)} / ${esc(h.grade_max_score||h.max_score)}</b><small>${esc(h.grade_feedback||h.submission_teacher_feedback||'لا توجد ملاحظات')}</small></div>`:'<div class="muted">لم تُسجل درجة بعد</div>';
  const canSubmit=h.status==='published'&&h.submission_status!=='graded';
  return `<article class="student-homework-card">
    <div class="question-card-head"><div><h3>${esc(h.title)}</h3><div class="muted">${esc(h.subject_name||'—')} · ${esc(h.class_name||'—')} ${h.section_code?' / '+esc(h.section_code):''} · المعلم: ${esc(h.teacher_name||'—')}</div></div><div>${h.viewed_at?'<span class="badge green">تمت المشاهدة</span>':'<span class="badge blue">جديد</span>'} ${statusBadge(h)} ${submissionBadge(h)}</div></div>
    <p>${esc(h.description||'')}</p>
    <div class="homework-meta"><span>النشر: ${fmtDate(h.publish_at||h.assigned_date)}</span><span>التسليم: ${esc(h.due_date||'—')} ${esc((h.due_time||'').slice(0,5))}</span><span>الدرجة: ${esc(h.max_score||10)}</span></div>
    <div class="homework-attachments-list">${atts.map(attachmentChip).join('')||'<span class="muted">لا توجد مرفقات من المعلم</span>'}</div>
    <div class="submission-box">
      <h4>حل الواجب</h4>
      <textarea id="subText_${h.homework_id}" class="input submission-text" ${canSubmit?'':'disabled'} placeholder="اكتب الحل أو ملاحظات التسليم هنا...">${esc(h.submission_answer_text||'')}</textarea>
      <div class="upload-zone" style="margin-top:8px">
        <label class="btn blue ${canSubmit?'':'disabled'}">إضافة ملفات<input type="file" multiple ${canSubmit?'':'disabled'} hidden accept=".jpg,.jpeg,.png,.webp,.pdf,.docx,.pptx,image/jpeg,image/png,image/webp,application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,application/vnd.openxmlformats-officedocument.presentationml.presentation" onchange="StudentHomeworks.addSubmissionFiles('${h.homework_id}',this.files)"></label>
        <label class="btn ${canSubmit?'':'disabled'}">تصوير<input type="file" ${canSubmit?'':'disabled'} hidden accept="image/*" capture="environment" onchange="StudentHomeworks.addSubmissionFiles('${h.homework_id}',this.files)"></label>
        <span class="muted">مرفقاتك المسلّمة: ${Number(h.submission_attachment_count||0)}</span>
      </div>
      ${h.submission_id?`<div class="submitted-files"><b>ملفاتك المسلّمة:</b><div class="homework-attachments-list">${subAttFor(h.submission_id).map(submissionAttachmentChip).join('')||'<span class="muted">لا توجد ملفات مسلّمة محفوظة</span>'}</div></div>`:''}
      <div id="subPreview_${h.homework_id}" class="submission-preview"></div>
      <div id="subStatus_${h.homework_id}" class="muted submission-status"></div>
      <div class="form-actions" style="margin-top:10px">
        <button class="btn" ${canSubmit?'':'disabled'} onclick="StudentHomeworks.saveSubmission('${h.homework_id}','draft')">حفظ مسودة</button>
        <button class="btn gold" ${canSubmit?'':'disabled'} onclick="StudentHomeworks.saveSubmission('${h.homework_id}','submitted')">تسليم الواجب</button>
      </div>
      ${h.submission_id?commentsBox(h):'<div class="muted">لإضافة تعليق أو سؤال للمعلم، احفظ مسودة الحل أولاً.</div>'}
    </div>
    ${grade}
  </article>`
}
function attachmentChip(a){const icon=(a.file_type||'').startsWith('image/')?'🖼️':(a.file_type||'').includes('pdf')?'📕':'📎';return `<button class="attachment-chip" onclick="StudentHomeworks.openAttachment('${esc(a.storage_path)}','${esc(a.file_name)}')"><span>${icon}</span><b>${esc(a.file_name)}</b><small>${Math.round((a.file_size||0)/1024)} KB</small></button>`}
function submissionAttachmentChip(a){const icon=(a.file_type||'').startsWith('image/')?'🖼️':(a.file_type||'').includes('pdf')?'📕':'📎';return `<button class="attachment-chip submitted" onclick="StudentHomeworks.openSubmissionAttachment('${esc(a.storage_path)}','${esc(a.file_name)}')"><span>${icon}</span><b>${esc(a.file_name)}</b><small>${Math.round((a.file_size||0)/1024)} KB</small></button>`}
async function openAttachment(path,name){try{const {data,error}=await client().storage.from('homework-attachments').createSignedUrl(path,3600);if(error)throw error;const a=document.createElement('a');a.href=data.signedUrl;a.target='_blank';a.download=name||'attachment';document.body.appendChild(a);a.click();a.remove()}catch(e){toast('تعذر فتح المرفق',e.message||String(e),'red')}}
async function openSubmissionAttachment(path,name){try{const {data,error}=await client().storage.from('homework-submissions').createSignedUrl(path,3600);if(error)throw error;const a=document.createElement('a');a.href=data.signedUrl;a.target='_blank';a.download=name||'attachment';document.body.appendChild(a);a.click();a.remove()}catch(e){toast('تعذر فتح مرفق التسليم',e.message||String(e),'red')}}
function commentsBox(h){const list=commentsFor(h.submission_id);return `<div class="comments-box"><h4>التعليقات</h4>${list.map(c=>`<div class="comment-row ${String(c.author_id)===String(ME.id)?'mine':''}"><b>${esc(c.author_name||c.author_role||'مستخدم')}</b><p>${esc(c.comment_text)}</p><small>${fmtDate(c.created_at)}</small></div>`).join('')||'<div class="muted">لا توجد تعليقات بعد</div>'}<div class="comment-form"><input id="comment_${h.submission_id}" class="input" placeholder="اكتب تعليقاً أو سؤالاً للمعلم"><button class="btn blue" onclick="StudentHomeworks.addComment('${h.submission_id}')">إرسال تعليق</button></div></div>`}
async function addComment(submissionId){const input=$(`#comment_${submissionId}`);const txt=input?.value.trim();if(!txt){toast('تنبيه','اكتب التعليق أولاً','red');return}try{const {data,error}=await client().rpc('add_homework_submission_comment',{p_submission_id:submissionId,p_comment_text:txt,p_is_internal:false});if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر إضافة التعليق');toast('تم','تم إرسال التعليق','green');if(input)input.value='';await load()}catch(e){toast('تعذر إضافة التعليق',e.message||String(e),'red')}}
function markVisibleHomeworksViewed(){const list=scopedHomeworks();list.forEach(h=>{const key=h.homework_id+'_'+h.student_id;if(VIEW_MARKED.has(key))return;VIEW_MARKED.add(key);client().rpc('mark_homework_viewed',{p_homework_id:h.homework_id,p_student_id:h.student_id}).then(()=>{}).catch(()=>{})})}
function setSubmissionStatus(hwId,msg,type='info'){const el=$(`#subStatus_${hwId}`);if(!el)return;el.className='submission-status '+(type==='red'?'error':type==='green'?'saved':'muted');el.textContent=msg}
function addSubmissionFiles(hwId,files){const list=SUBMISSION_FILES.get(hwId)||[];Array.from(files||[]).forEach(f=>{const ok=['image/jpeg','image/png','image/webp','application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.presentationml.presentation'].includes(f.type)||/\.(docx|pptx)$/i.test(f.name);if(!ok){toast('ملف غير مدعوم',f.name,'red');return}list.push({id:crypto.randomUUID?crypto.randomUUID():String(Date.now()+Math.random()),file:f,name:f.name,size:f.size,type:f.type,preview:f.type.startsWith('image/')?URL.createObjectURL(f):null})});SUBMISSION_FILES.set(hwId,list);renderSubmissionPreview(hwId)}
function renderSubmissionPreview(hwId){const box=$(`#subPreview_${hwId}`);if(!box)return;const list=SUBMISSION_FILES.get(hwId)||[];box.innerHTML=list.map((f,i)=>`<div class="file-card"><div class="file-thumb">${f.preview?`<img src="${f.preview}" alt="">`:'📄'}</div><div><b>${esc(f.name)}</b><small>${Math.round((f.size||0)/1024)} KB</small></div><button class="btn small red" onclick="StudentHomeworks.removeSubmissionFile('${hwId}',${i})">حذف</button></div>`).join('')}
function removeSubmissionFile(hwId,i){const list=SUBMISSION_FILES.get(hwId)||[];const f=list.splice(i,1)[0];if(f&&f.preview)URL.revokeObjectURL(f.preview);SUBMISSION_FILES.set(hwId,list);renderSubmissionPreview(hwId)}
async function uploadSubmissionFiles(homeworkId,submissionId){const list=SUBMISSION_FILES.get(homeworkId)||[];let uploaded=0;for(let i=0;i<list.length;i++){const f=list[i].file;const safe=(f.name||'file').replace(/[^\w\.\-\u0600-\u06FF]+/g,'_');const path=`${ME.id}/${submissionId}/${Date.now()}_${i}_${safe}`;const up=await client().storage.from('homework-submissions').upload(path,f,{upsert:false,contentType:f.type||undefined});if(up.error){console.warn(up.error);continue}const {data,error}=await client().rpc('add_homework_submission_attachment',{p_submission_id:submissionId,p_file_name:f.name,p_file_type:f.type,p_file_size:f.size,p_storage_path:path,p_sort_order:i});if(error||data?.ok===false){console.warn(error||data);continue}uploaded++}list.forEach(f=>f.preview&&URL.revokeObjectURL(f.preview));SUBMISSION_FILES.delete(homeworkId);return uploaded}
async function saveSubmission(hwId,status='draft'){const h=DATA.homeworks.find(x=>String(x.homework_id)===String(hwId));if(!h){toast('خطأ','الواجب غير موجود في الصفحة','red');return}setSubmissionStatus(hwId,status==='submitted'?'جاري التسليم...':'جاري حفظ المسودة...');try{const text=$(`#subText_${hwId}`)?.value||'';const {data,error}=await client().rpc('save_homework_submission',{p_homework_id:hwId,p_student_id:h.student_id,p_answer_text:text,p_status:status});if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر حفظ التسليم');let uploaded=0;if(data.submission_id)uploaded=await uploadSubmissionFiles(hwId,data.submission_id);toast(status==='submitted'?'تم تسليم الواجب':'تم حفظ المسودة',uploaded?`تم رفع ${uploaded} ملف`:'تم الحفظ','green');setSubmissionStatus(hwId,'تم الحفظ بنجاح','green');await load()}catch(e){console.error(e);toast('تعذر حفظ/تسليم الواجب',e.message||String(e),'red');setSubmissionStatus(hwId,e.message||String(e),'red')}}
function render(id){ACTIVE=id;$$('.view').forEach(v=>v.classList.toggle('active',v.id==='view-'+id));$$('.nav button[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view===id));if(id==='homeworks')homeworksView();else gradesView()}
function emptyDebug(){if(!DATA.debug)return'<div class="empty">لا توجد واجبات منشورة حالياً</div>';return `<div class="empty"><b>لا توجد واجبات ظاهرة لهذا الحساب</b><br><small>عدد الطلاب المرتبطين بالحساب: ${esc(DATA.debug.my_students_count??'—')} · الواجبات المنشورة في النظام: ${esc(DATA.debug.published_homeworks??'—')} · الواجبات المطابقة للحساب: ${esc(DATA.debug.visible_homeworks??0)}</small><br><small>إذا كان يجب أن تظهر واجبات، شغلي في SQL: select public.student_homeworks_match_report();</small></div>`}
function homeworksView(){const list=scopedHomeworks();const pending=list.filter(h=>h.grade_score==null&&h.status==='published').length;setTimeout(markVisibleHomeworksViewed,300);$('#view-homeworks').innerHTML=`<div class="page-head"><div><h1>واجباتي</h1><p>الواجبات المنشورة والمغلقة مع المرفقات والدرجات.</p></div>${switcher()}</div><div class="kpis"><div class="kpi gold"><small>كل الواجبات</small><b>${list.length}</b></div><div class="kpi blue"><small>بانتظار درجة</small><b>${pending}</b></div><div class="kpi green"><small>مصححة</small><b>${list.filter(h=>h.grade_score!=null).length}</b></div><div class="kpi red"><small>متأخرة</small><b>${list.filter(isLate).length}</b></div></div><div class="student-homework-list">${list.map(homeworkCard).join('')||emptyDebug()}</div>`}
function gradesView(){const rows=scopedHomeworks().filter(h=>h.grade_score!=null).map(h=>`<tr><td>${esc(h.title)}</td><td>${esc(h.subject_name||'—')}</td><td>${esc(h.grade_score)} / ${esc(h.grade_max_score||h.max_score)}</td><td>${esc(h.grade_feedback||'—')}</td><td>${fmtDate(h.graded_at)}</td></tr>`);$('#view-grades').innerHTML=`<div class="page-head"><div><h1>درجات الواجبات</h1></div>${switcher()}</div>${table(['الواجب','المادة','الدرجة','ملاحظة المعلم','تاريخ التصحيح'],rows,'لا توجد درجات واجبات بعد')}`}
function table(h,rows,empty='لا توجد بيانات'){const body=Array.isArray(rows)?rows.join(''):String(rows||'');return body.trim()?`<div class="table-wrap"><table><thead><tr>${h.map(x=>`<th>${esc(x)}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>`:`<div class="empty">${esc(empty)}</div>`}
function bind(){$$('.nav button[data-view]').forEach(b=>b.addEventListener('click',()=>render(b.dataset.view)));$('#mobileMenuBtn')?.addEventListener('click',()=>$('#sidebar').classList.toggle('open'));$('#logoutBtn')?.addEventListener('click',async()=>{await client().auth.signOut({scope:'local'});location.href='index.html'});$('#refreshBtn')?.addEventListener('click',load)}
async function init(){client();if(!await ensure())return;bind();await load()}
window.StudentHomeworks={init,render,setStudent,openAttachment,openSubmissionAttachment,addSubmissionFiles,removeSubmissionFile,saveSubmission,addComment};
}());

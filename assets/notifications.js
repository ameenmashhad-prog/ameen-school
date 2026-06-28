/* Notifications Center */
(function(){
'use strict';
let sb=null,ME=null,ACTIVE='all',DATA={notifications:[]};
const cfg=()=>window.AMIN_CONFIG||{};
const $=(s,r=document)=>r.querySelector(s);
const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
function client(){if(sb)return sb;sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});return sb}
function esc(v){return String(v==null?'':v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
function toast(t,m,type=''){const el=$('#toast');if(!el)return;el.innerHTML=`<b>${esc(t)}</b><br><span class="muted">${esc(m||'')}</span>`;el.className='toast show '+type;clearTimeout(el._t);el._t=setTimeout(()=>el.classList.remove('show'),4200)}
function fmtDate(v){if(!v)return'—';try{return new Date(v).toLocaleString('ar-IQ')}catch{return v}}
function roleLabel(r){return ({admin:'إدارة',teacher:'معلم',student:'طالب',parent:'ولي أمر',finance:'مالية',academic:'أكاديمي'}[r]||r||'مستخدم')}
async function q(table,opts={}){try{let query=client().from(table).select(opts.columns||'*');(opts.filters||[]).forEach(f=>query=query[f.op](f.col,f.val));if(opts.order)query=query.order(opts.order,{ascending:opts.ascending!==false});if(opts.limit)query=query.limit(opts.limit);const {data,error}=await query;if(error){console.warn(table,error);return[]}return data||[]}catch(e){console.warn(table,e);return[]}}
async function ensure(){const {data:{session}}=await client().auth.getSession();if(!session){location.href='index.html';return false}const {data:u}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();if(!u){location.href='index.html';return false}ME=u;$('#profileName').textContent=u.name||u.email;$('#profileRole').textContent=roleLabel(u.role);return true}
async function load(){
  let notifications=[];
  try{
    const {data,error}=await client().from('v_my_notifications').select('*').order('created_at',{ascending:false}).limit(300);
    if(error)throw error;
    notifications=data||[];
  }catch(e){
    console.warn('v_my_notifications fallback',e);
    // fallback مؤقت إذا لم تكن view موجودة في schema cache بعد تشغيل SQL.
    try{
      const {data,error}=await client().from('school_notifications').select('*').order('created_at',{ascending:false}).limit(300);
      if(error)throw error;
      notifications=(data||[]).map(n=>({...n,is_unread:!n.read_at,created_by_name:''}));
    }catch(e2){console.warn('school_notifications fallback failed',e2);notifications=[];}
  }
  DATA.notifications=notifications;
  render(ACTIVE);
}
function typeBadge(n){const t=String(n.notification_type||'info');let cls=t.includes('homework')?'gold':t.includes('exam')?'blue':'green';return `<span class="badge ${cls}">${esc(typeLabel(t))}</span>`}
function typeLabel(t){return ({homework_published:'واجب جديد',homework_updated:'تعديل واجب',homework_closed:'إغلاق واجب',homework_reminder:'تذكير واجب',homework_submitted:'تسليم واجب',homework_graded:'تصحيح واجب',homework_returned:'إرجاع واجب',homework_comment:'تعليق واجب',homework_not_viewed:'لم يفتح الواجب',announcement:'إعلان',info:'تنبيه'}[t]||t)}
function notificationCard(n){return `<article class="notification-card ${n.is_unread?'unread':''}">
  <div class="notification-main"><div class="notification-icon">${n.is_unread?'🔔':'✓'}</div><div><h3>${esc(n.title)}</h3><p>${esc(n.body||'')}</p><div class="muted">${fmtDate(n.created_at)} ${n.created_by_name?' · بواسطة '+esc(n.created_by_name):''}</div></div></div>
  <div class="notification-actions">${typeBadge(n)}${n.is_unread?`<button class="btn small blue" onclick="NotificationsCenter.markRead('${n.id}')">تعليم كمقروء</button>`:''}${entityButton(n)}</div>
</article>`}
function entityButton(n){if(n.entity_table==='homeworks')return `<button class="btn small" onclick="location.href='student-homeworks.html'">فتح الواجبات</button>`;if(n.entity_table==='online_exams')return `<button class="btn small" onclick="location.href='online-exams.html'">فتح الاختبارات</button>`;return ''}
function render(id){ACTIVE=id;$$('.view').forEach(v=>v.classList.toggle('active',v.id==='view-'+id));$$('.nav button[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view===id));const list=id==='unread'?DATA.notifications.filter(n=>n.is_unread):DATA.notifications;const unread=DATA.notifications.filter(n=>n.is_unread).length;const html=`<div class="page-head"><div><h1>${id==='unread'?'غير المقروءة':'كل الإشعارات'}</h1><p>عدد غير المقروء: ${unread}</p></div></div><div class="notification-list">${list.map(notificationCard).join('')||'<div class="empty">لا توجد إشعارات</div>'}</div>`;$('#view-'+id).innerHTML=html}
async function markRead(id){try{const {data,error}=await client().rpc('mark_notification_read',{p_notification_id:id});if(error)throw error;if(data&&data.ok===false){toast('تعذر التحديث',data.message||'خطأ','red');return}toast('تم','تم تعليم الإشعار كمقروء','green');await load()}catch(e){toast('تعذر التحديث',e.message||String(e),'red')}}
async function markAll(){try{const {data,error}=await client().rpc('mark_all_notifications_read');if(error)throw error;toast('تم','تم تعليم '+(data?.count||0)+' إشعار كمقروء','green');await load()}catch(e){toast('تعذر التحديث',e.message||String(e),'red')}}
function bind(){$$('.nav button[data-view]').forEach(b=>b.addEventListener('click',()=>render(b.dataset.view)));$('#mobileMenuBtn')?.addEventListener('click',()=>$('#sidebar').classList.toggle('open'));$('#logoutBtn')?.addEventListener('click',async()=>{await client().auth.signOut({scope:'local'});location.href='index.html'});$('#refreshBtn')?.addEventListener('click',load);$('#markAllBtn')?.addEventListener('click',markAll)}
async function init(){client();if(!await ensure())return;bind();await load()}
window.NotificationsCenter={init,render,markRead,markAll};
}());

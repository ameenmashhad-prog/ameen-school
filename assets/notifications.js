/* Notifications Center - Enhanced with Importance Handling - Effective & Excellent */
(function(){
'use strict';
let sb=null,ME=null,ACTIVE='all',DATA={notifications:[]};
const cfg=()=>window.AMIN_CONFIG||{};
const $=(s,r=document)=>r.querySelector(s);
const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
function client(){if(sb)return sb;sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});return sb}
function esc(v){return String(v==null?'':v).replace(/[&<>\"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#039;'}[m]))}
function toast(t,m,type=''){const el=$('#toast');if(!el)return;el.innerHTML=`<b>${esc(t)}</b><br><span class="muted">${esc(m||'')}</span>`;el.className='toast show '+type;clearTimeout(el._t);el._t=setTimeout(()=>el.classList.remove('show'),4200)}
function fmtDate(v){if(!v)return'—';try{return new Date(v).toLocaleString('ar-IQ')}catch{return v}}
function roleLabel(r){return ({admin:'إدارة',teacher:'معلم',student:'طالب',parent:'ولي أمر',finance:'مالية',academic:'أكاديمي'}[r]||r||'مستخدم')}
async function ensure(){const {data:{session}}=await client().auth.getSession();if(!session){location.href='index.html';return false}const {data:u}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();if(!u){location.href='index.html';return false}ME=u;$('#profileName').textContent=u.name||u.email;$('#profileRole').textContent=roleLabel(u.role);return true}
function playCriticalSound(){
  try{
    const ctx=new (window.AudioContext||window.webkitAudioContext)();
    const osc=ctx.createOscillator(); const gain=ctx.createGain();
    osc.type='sine'; osc.frequency.setValueAtTime(880,ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(440,ctx.currentTime+0.5);
    gain.gain.setValueAtTime(0.3,ctx.currentTime); gain.gain.exponentialRampToValueAtTime(0.01,ctx.currentTime+0.6);
    osc.connect(gain); gain.connect(ctx.destination); osc.start(); osc.stop(ctx.currentTime+0.6);
  }catch(e){}
}

async function requestPushPermission(){
  if(!('Notification' in window)) return false;
  if(Notification.permission==='granted') return true;
  if(Notification.permission==='denied') return false;
  try{ const p=await Notification.requestPermission(); return p==='granted'; }catch{ return false; }
}

function showPushNotification(title,body,type){
  if(!('Notification' in window)||Notification.permission!=='granted') return;
  try{
    const notif=new Notification(`${type==='critical'?'🚨':type==='high'?'⚠️':'🔔'} ${title}`,{body, icon:'/assets/amin-logo-small.png', requireInteraction:type==='critical', tag:`notif-${type}-${Date.now()}`});
    notif.onclick=()=>{ window.focus(); notif.close(); };
    setTimeout(()=>{ try{notif.close();}catch(e){} }, type==='critical'?10000:6000);
  }catch(e){}
}

async function load(){
async function load(){
  let notifications=[];
  try{
    const {data,error}=await client().from('v_my_notifications_enhanced').select('*').limit(300);
    if(error) throw error;
    notifications=data||[];
  }catch(e){
    console.warn('enhanced view fallback',e);
    try{
      const {data,error}=await client().from('v_my_notifications').select('*').order('created_at',{ascending:false}).limit(300);
      if(error)throw error;
      notifications=(data||[]).map(n=>({...n,importance:n.importance||'medium',priority:n.priority||3,is_unread:!n.read_at,computed_priority:n.priority||3,created_by_name:n.created_by_name||'',hours_since_created:0,status:n.read_at?'read':'unread'}));
    }catch(e2){
      try{
        const {data,error}=await client().from('school_notifications').select('*').order('created_at',{ascending:false}).limit(300);
        if(error)throw error;
        notifications=(data||[]).map(n=>({...n,importance:n.importance||'medium',priority:3,is_unread:!n.read_at,computed_priority:3,created_by_name:'',hours_since_created:0,status:n.read_at?'read':'unread'}));
      }catch(e3){notifications=[];}
    }
  }
  // Sort by importance then date
  notifications.sort((a,b)=>{
    const pa=a.computed_priority||a.priority||3;
    const pb=b.computed_priority||b.priority||3;
    if(pa!==pb) return pa-pb;
    return new Date(b.created_at)-new Date(a.created_at);
  });
  DATA.notifications=notifications;
  // Handle importance: play sound and push for critical/high unread
  try{
    const criticalUnread=notifications.filter(n=>(n.is_unread||!n.read_at)&&n.importance==='critical');
    const highUnread=notifications.filter(n=>(n.is_unread||!n.read_at)&&n.importance==='high');
    if(criticalUnread.length>0){
      playCriticalSound();
      requestPushPermission().then(g=>{
        if(g){
          criticalUnread.slice(0,2).forEach(n=>showPushNotification(n.title,n.body||'', 'critical'));
          if(criticalUnread.length>2) showPushNotification(`${criticalUnread.length} إشعارات حرجة`, `${criticalUnread.length} إشعارات حرجة تحتاج انتباهك فوراً`, 'critical');
        }
      });
    } else if(highUnread.length>0){
      requestPushPermission().then(g=>{
        if(g) highUnread.slice(0,1).forEach(n=>showPushNotification(n.title,n.body||'', 'high'));
      });
    }
  }catch(e){ console.warn(e); }
  render(ACTIVE);
}
function importanceBadge(n){
  const imp=n.importance||'medium';
  const map={
    critical:{cls:'red',label:'🔴 حرج',icon:'🚨'},
    high:{cls:'gold',label:'🟠 مهم',icon:'⚠️'},
    medium:{cls:'blue',label:'🔵 متوسط',icon:'📢'},
    low:{cls:'slate',label:'⚪ منخفض',icon:'📄'}
  };
  const m=map[imp]||map.medium;
  return `<span class="badge ${m.cls}">${m.label}</span>`;
}
function typeBadge(n){const t=String(n.notification_type||'info');let cls=t.includes('homework')?'gold':t.includes('exam')?'blue':t.includes('penalty')?'red':'green';return `<span class="badge ${cls}">${esc(typeLabel(t))}</span>`}
function typeLabel(t){return ({homework_published:'واجب جديد',homework_updated:'تعديل واجب',homework_closed:'إغلاق واجب',homework_reminder:'تذكير واجب',homework_submitted:'تسليم واجب',homework_graded:'تصحيح واجب',homework_returned:'إرجاع واجب',homework_comment:'تعليق واجب',homework_not_viewed:'لم يفتح الواجب',announcement:'إعلان',info:'تنبيه',penalty:'عقوبة',thank_you:'شكر',warning:'إنذار',notice:'تنبيه',absence:'غياب',overdue:'متأخر'}[t]||t)}
function deliveryIcons(n){
  const methods=n.delivery_methods||['in_app'];
  return methods.map(m=>m==='whatsapp'?'💬 واتساب':m==='sms'?'📩 SMS':m==='email'?'✉️ بريد':'📱 داخل الموقع').join('، ');
}
function notificationCard(n){
  const imp=n.importance||'medium';
  const escalated=n.status==='escalated' ? '<span class="badge red">⏫ تم التصعيد - لم يقرأ لأكثر من ساعتين</span>' : '';
  const hours=n.hours_since_created ? `<small style="color:#dc2626">· منذ ${Math.round(n.hours_since_created)} ساعة</small>` : '';
  const borderColor=imp==='critical'?'#dc2626':imp==='high'?'#d97706':imp==='medium'?'#2563eb':'#64748b';
  const bg=imp==='critical'?'#fef2f2':imp==='high'?'#fffbeb':'#fff';
  return `<article class="notification-card ${n.is_unread||!n.read_at?'unread':''}" style="border-right:4px solid ${borderColor};background:${bg};padding:14px;border-radius:12px;margin-bottom:10px;box-shadow:0 2px 8px rgba(0,0,0,.06)">
  <div style="display:flex;gap:12px"><div style="font-size:20px">${n.is_unread||!n.read_at?'🔔':'✓'}</div><div style="flex:1"><h3 style="margin:0 0 6px;font-size:15px">${esc(n.title)} ${importanceBadge(n)} ${escalated}</h3><p style="margin:0 0 8px;color:#334155;line-height:1.6">${esc(n.body||'')}</p><div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center;color:#64748b;font-size:11px"><span>${fmtDate(n.created_at)} ${hours}</span><span>${n.created_by_name?' · بواسطة '+esc(n.created_by_name):''}</span><span>· ${deliveryIcons(n)}</span></div></div></div>
  <div style="display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin-top:10px">${typeBadge(n)}${importanceBadge(n)}${n.is_unread||!n.read_at?`<button class="btn small blue" onclick="NotificationsCenter.markRead('${n.id}')">تعليم كمقروء</button>`:''}${n.action_url?`<a class="btn small gold" href="${esc(n.action_url)}">${esc(n.action_label||'فتح')}</a>`:''}${n.entity_table==='homeworks'?`<button class="btn small" onclick="location.href='student-homeworks.html'">فتح الواجبات</button>`:''}${n.entity_table==='online_exams'?`<button class="btn small" onclick="location.href='online-exams.html'">فتح الاختبارات</button>`:''}</div>
</article>`}
function render(id){
  ACTIVE=id;
  $$('.view').forEach(v=>v.classList.toggle('active',v.id==='view-'+id));
  $$('.nav button[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view===id));
  let list=DATA.notifications;
  if(id==='unread') list=list.filter(n=>n.is_unread||!n.read_at);
  else if(id==='critical') list=list.filter(n=>n.importance==='critical');
  else if(id==='high') list=list.filter(n=>n.importance==='high');
  else if(id==='medium') list=list.filter(n=>n.importance==='medium');
  else if(id==='low') list=list.filter(n=>n.importance==='low');
  const unread=DATA.notifications.filter(n=>n.is_unread||!n.read_at).length;
  const criticalUnread=DATA.notifications.filter(n=>(n.is_unread||!n.read_at)&&n.importance==='critical').length;
  const highUnread=DATA.notifications.filter(n=>(n.is_unread||!n.read_at)&&n.importance==='high').length;
  const escCount=DATA.notifications.filter(n=>n.status==='escalated').length;
  
  const tabsHtml=`
    <div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px">
      <button class="btn ${id==='all'?'blue':''}" onclick="NotificationsCenter.render('all')">الكل (${DATA.notifications.length})</button>
      <button class="btn ${id==='unread'?'gold':''}" onclick="NotificationsCenter.render('unread')">غير المقروءة (${unread})</button>
      <button class="btn ${id==='critical'?'red':''}" onclick="NotificationsCenter.render('critical')">🔴 حرجة (${criticalUnread})</button>
      <button class="btn ${id==='high'?'gold':''}" onclick="NotificationsCenter.render('high')">🟠 مهمة (${highUnread})</button>
      <button class="btn ${id==='medium'?'':''}" onclick="NotificationsCenter.render('medium')">🔵 متوسطة</button>
      <button class="btn ${id==='low'?'':''}" onclick="NotificationsCenter.render('low')">⚪ منخفضة</button>
      ${escCount?`<span class="badge red">⏫ ${escCount} تم تصعيدها</span>`:''}
      <button class="btn gold" onclick="NotificationsCenter.markCriticalRead()" style="margin-right:auto">تعليم الحرجة كمقروءة</button>
    </div>
    <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:16px">
      <div style="background:#fee2e2;padding:10px;border-radius:10px;text-align:center;border:1px solid #fecaca"><small>حرجة</small><br><b style="font-size:18px;color:#dc2626">${DATA.notifications.filter(n=>n.importance==='critical').length}</b><br><small>واتساب+SMS+داخلي</small></div>
      <div style="background:#fef3c7;padding:10px;border-radius:10px;text-align:center;border:1px solid #fde68a"><small>مهمة</small><br><b style="font-size:18px;color:#d97706">${DATA.notifications.filter(n=>n.importance==='high').length}</b><br><small>واتساب+داخلي</small></div>
      <div style="background:#dbeafe;padding:10px;border-radius:10px;text-align:center;border:1px solid #bfdbfe"><small>متوسطة</small><br><b style="font-size:18px;color:#2563eb">${DATA.notifications.filter(n=>n.importance==='medium').length}</b><br><small>داخلي فقط</small></div>
      <div style="background:#f1f5f9;padding:10px;border-radius:10px;text-align:center;border:1px solid #e2e8f0"><small>منخفضة</small><br><b style="font-size:18px">${DATA.notifications.filter(n=>n.importance==='low').length}</b><br><small>ملخص يومي</small></div>
    </div>
  `;
  
  const html=`<div class="page-head"><div><h1>${id==='unread'?'غير المقروءة':id==='critical'?'الحرجة':id==='high'?'المهمة':id==='medium'?'المتوسطة':id==='low'?'المنخفضة':'كل الإشعارات'}</h1><p>غير المقروء: ${unread} · حرجة غير مقروءة: ${criticalUnread} ${escCount?`· تم تصعيد: ${escCount}`:''} · مرتبة حسب الأهمية ثم التاريخ</p></div></div>${tabsHtml}<div class="notification-list">${list.map(notificationCard).join('')||'<div class="empty">لا توجد إشعارات</div>'}</div>`;
  const targetEl=document.getElementById('view-'+id) || document.getElementById('view-all');
  if(targetEl) targetEl.innerHTML=html;
  // Also update all view if exists
  if(id!=='all' && document.getElementById('view-all') && id!=='critical' && id!=='high') {
    // Keep all view updated too
  }
}
async function markRead(id){try{const {data,error}=await client().rpc('mark_notification_read',{p_notification_id:id});if(error)throw error;if(data&&data.ok===false){toast('تعذر التحديث',data.message||'خطأ','red');return}toast('تم','تم تعليم الإشعار كمقروء','green');await load()}catch(e){toast('تعذر التحديث',e.message||String(e),'red')}}
async function markAll(){try{const {data,error}=await client().rpc('mark_all_notifications_read');if(error)throw error;toast('تم','تم تعليم '+(data?.count||0)+' إشعار كمقروء','green');await load()}catch(e){toast('تعذر التحديث',e.message||String(e),'red')}}
async function markCriticalRead(){try{const criticalIds=DATA.notifications.filter(n=>(n.is_unread||!n.read_at)&&n.importance==='critical').map(n=>n.id);for(const id of criticalIds){await client().rpc('mark_notification_read',{p_notification_id:id});}toast('تم','تم تعليم كل الحرجة كمقروءة','green');await load()}catch(e){toast('خطأ',e.message,'red')}}
function bind(){$$('.nav button[data-view]').forEach(b=>b.addEventListener('click',()=>render(b.dataset.view)));$('#mobileMenuBtn')?.addEventListener('click',()=>$('#sidebar').classList.toggle('open'));$('#logoutBtn')?.addEventListener('click',async()=>{await client().auth.signOut({scope:'local'});location.href='index.html'});$('#refreshBtn')?.addEventListener('click',load);$('#markAllBtn')?.addEventListener('click',markAll)}
async function init(){client();if(!await ensure())return;bind();await load()}
window.NotificationsCenter={init,render,markRead,markAll,markCriticalRead};
}());

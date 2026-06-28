/* Anonymous counseling aggregate report */
(function(){
'use strict';
let sb=null,ME=null,REPORT=null;
const cfg=()=>window.AMIN_CONFIG||{};const $=(s,r=document)=>r.querySelector(s);
function client(){if(sb)return sb;sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});return sb}
function esc(v){return String(v==null?'':v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
function num(v){try{return Number(v||0).toLocaleString('ar-SA')}catch{return v||0}}
function toast(t,m,type=''){const el=$('#toast');if(!el)return;el.innerHTML=`<b>${esc(t)}</b><br><span class="muted">${esc(m||'')}</span>`;el.className='toast show '+type;clearTimeout(el._t);el._t=setTimeout(()=>el.classList.remove('show'),4200)}
function roleLabel(r){return ({admin:'إدارة',academic:'أكاديمي',counselor:'مرشد نفسي',psychologist:'مرشد نفسي'}[r]||r||'مستخدم')}
async function ensure(){const {data:{session}}=await client().auth.getSession();if(!session){location.href='index.html';return false}const {data:u}=await client().from('users').select('id,name,email,role,is_super_admin').eq('id',session.user.id).maybeSingle();if(!u){location.href='index.html';return false}ME=u;$('#profileName').textContent=u.name||u.email;$('#profileRole').textContent=roleLabel(u.role);return true}
async function load(){try{const {data,error}=await client().rpc('get_counseling_admin_aggregate_report');if(error)throw error;if(!data||data.ok===false)throw new Error(data?.message||'تعذر تحميل التقرير');REPORT=data;render()}catch(e){$('#view-overview').innerHTML=`<div class="empty">${esc(e.message||String(e))}</div>`;toast('تعذر تحميل التقرير',e.message||String(e),'red')}}
function kpi(label,value,color){return `<div class="report-kpi icon-${color||'indigo'}"><small>${esc(label)}</small><b>${num(value)}</b></div>`}
function riskLabel(r){return ({crisis:'أزمة',urgent:'عاجل',high:'مرتفع',medium:'متوسط',followup:'متابعة',stable:'مستقر',new:'غير مقيّم'}[r]||r||'غير محدد')}
function rows(list,key,labelFn){const max=Math.max(1,...(list||[]).map(x=>Number(x.count||x.sessions||0)));return (list||[]).map(x=>{const v=Number(x.count||x.sessions||0);return `<div class="risk-row"><b>${esc(labelFn?labelFn(x[key]):x[key])}</b><div class="risk-bar"><i style="--w:${Math.round(v/max*100)}%"></i></div><span>${num(v)}</span></div>`}).join('')||'<div class="empty">لا توجد بيانات كافية بعد</div>'}
function render(){const r=REPORT||{};$('#view-overview').innerHTML=`<section class="report-privacy-banner"><h1>تقرير مجهول — برنامج تطوير المهارات والمتابعة التربوية</h1><p>هذا التقرير لا يحتوي أسماء أو ملاحظات جلسات أو معرفات طلاب.</p></section><div class="report-kpis">${kpi('الحالات النشطة',r.active_cases,'violet')}${kpi('جلسات هذا الشهر',r.sessions_this_month,'cyan')}${kpi('إحالات معلقة',r.pending_referrals,'gold')}${kpi('أهداف مفتوحة',r.open_goals,'emerald')}</div><div class="report-grid"><div class="report-panel"><h3>توزيع مستويات المتابعة</h3>${rows(r.risk_distribution||[],'risk_level',riskLabel)}</div><div class="report-panel"><h3>اتجاه الجلسات الشهري</h3>${rows((r.monthly_sessions||[]).map(x=>({month:x.month,sessions:x.sessions})),'month')}</div></div><div class="anonymous-note">${esc(r.note||'تقرير مجمع بدون بيانات شخصية.')}</div>`;window.AminI18n?.apply?.()}
function bind(){$('#refreshBtn')?.addEventListener('click',load);$('#mobileMenuBtn')?.addEventListener('click',()=>$('#sidebar')?.classList.toggle('open'));$('#logoutBtn')?.addEventListener('click',async()=>{await client().auth.signOut({scope:'local'});location.href='index.html'})}
async function init(){client();if(!await ensure())return;bind();await load()}
window.CounselingReport={init,load};
}());

/* Finance Receiver Reports */
(function(){
'use strict';
let sb=null,ME=null,ACTIVE='overview',FX={rate:0,label:'آخر سعر محفوظ'},DATA={stats:{},by_receiver:[],by_method:[],payments:[],users:[],rates:[]};
const cfg=()=>window.AMIN_CONFIG||{};const RT=()=>window.FinanceRuntime||{};const $=(s,r=document)=>r.querySelector(s);const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
function client(){if(sb)return sb;sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});return sb}
function esc(v){return String(v==null?'':v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
function toast(t,m,type=''){const el=$('#toast');if(!el)return;el.innerHTML=`<b>${esc(t)}</b><br><span class="muted">${esc(m||'')}</span>`;el.className='toast show '+type;clearTimeout(el._t);el._t=setTimeout(()=>el.classList.remove('show'),4200)}
function roleLabel(r){return ({admin:'إدارة',finance:'مالية',staff:'موظف',accountant:'محاسب',cashier:'أمين صندوق'}[r]||r||'مستخدم')}
function money(v){return Number(v||0).toLocaleString('en-US',{maximumFractionDigits:2})}
function irr(v){return Number(v||0).toLocaleString('fa-IR')+' ریال'}
function dualMoney(usd,irrValue){const rv=Number(irrValue||0)||(FX.rate?Number(usd||0)*FX.rate:0);return rv?`${money(usd)}$ / ${irr(rv)}`:`${money(usd)}$ / —`}
function dualDate(v){return RT().dualDate?RT().dualDate(String(v||'').slice(0,10)):String(v||'').slice(0,10)}
function monthValue(){return RT().currentSolarMonthKey?RT().currentSolarMonthKey():new Date().toISOString().slice(0,7)}
function monthMeta(key){return RT().solarMonthRangeFromKey?RT().solarMonthRangeFromKey(key):{key,label:key,gregorianLabel:'—',start:'',end:''}}
function monthSelect(id,value){return RT().buildMonthSelect?RT().buildMonthSelect(id,value,[value],14,2):`<input id="${id}" class="input" value="${esc(value)}">`}
function currentMonth(){return $('#monthFilter')?.value||monthValue()}
function currentRange(){const m=monthMeta(currentMonth());const today=new Date().toISOString().slice(0,10);return {from:m.start||today,to:m.end||today,label:m.label||currentMonth(),gregorian:m.gregorianLabel||'—'}}
function fmt(v){if(!v)return'—';try{return new Date(v).toLocaleString('ar-IQ')}catch{return v}}
function csvCell(v){const s=String(v==null?'':v).replace(/"/g,'""');return /[",\n]/.test(s)?`"${s}"`:s}
function downloadCsv(filename,headers,rows){const csv='\ufeff'+[headers.map(csvCell).join(','),...rows.map(r=>headers.map(h=>csvCell(r[h])).join(','))].join('\n');const blob=new Blob([csv],{type:'text/csv;charset=utf-8'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=filename;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000)}
async function q(table,opts={}){try{let query=client().from(table).select(opts.columns||'*');(opts.filters||[]).forEach(f=>query=query[f.op](f.col,f.val));if(opts.order)query=query.order(opts.order,{ascending:opts.ascending!==false});if(opts.limit)query=query.limit(opts.limit);const {data,error}=await query;if(error){console.warn(table,error);return[]}return data||[]}catch(e){console.warn(table,e);return[]}}
async function ensure(){const {data:{session}}=await client().auth.getSession();if(!session){location.href='index.html';return false}const {data:u}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();if(!u){location.href='index.html';return false}ME=u;const ok=u.is_super_admin||['admin','finance','staff','accountant','cashier'].includes(u.role);if(!ok){document.body.innerHTML='<main class="login-page"><section class="login-card"><h1>غير مصرح</h1><p>هذه الصفحة للمالية والإدارة فقط.</p></section></main>';return false}$('#profileName').textContent=u.name||u.email;$('#profileRole').textContent=roleLabel(u.role);return true}
function ensureMonthToolbar(){const mount=$('#monthTools');if(!mount)return;mount.innerHTML=`${monthSelect('monthFilter',currentMonth())}<span class="badge blue">${esc(currentRange().gregorian)}</span><span class="badge gold">${FX.rate?irr(FX.rate):'—'}</span>`}
function receiverLabel(p,userMap){const byUser=p.received_by&&(userMap.get(String(p.received_by))||{}).name;const raw=(p.receiver_name||'').trim();if(raw && !/مجمع أمين الرضا التعليمي/.test(raw))return raw;return byUser||raw||p.created_by_name||'غير محدد'}
async function load(){const range=currentRange();try{const [payments,users,rates,fees,students,classes]=await Promise.all([
  q('fee_payments',{columns:'id,receipt_number,payment_date,created_at,student_fee_id,amount_usd,amount_irr,amount,currency,payment_method,payer_name,receiver_name,receiver_role,received_by,transfer_number,voided,void_reason,voided_at,created_by_name',order:'created_at',ascending:false,limit:5000}),
  q('users',{columns:'id,name,role',order:'name',limit:1000}),
  q('exchange_rates',{order:'fetched_at',ascending:false,limit:10}),
  q('student_fees',{columns:'id,student_id',limit:5000}),
  q('students',{columns:'id,name,class_id',limit:5000}),
  q('classes',{columns:'id,name',limit:1000})
]);
  const latest=(rates||[])[0];if(latest&&Number(latest.rate)>0)FX={rate:Number(latest.rate),label:latest.source||'آخر سعر محفوظ'};
  const userMap=new Map((users||[]).map(u=>[String(u.id),u]));
  const feeMap=new Map((fees||[]).map(f=>[String(f.id),f]));
  const studentMap=new Map((students||[]).map(s=>[String(s.id),s]));
  const classMap=new Map((classes||[]).map(c=>[String(c.id),c]));
  const d1=range.from, d2=range.to;
  const filtered=(payments||[]).filter(p=>{
    const d=String((p.payment_date||String(p.created_at||'').slice(0,10))||'').slice(0,10);
    return d && d>=d1 && d<=d2;
  }).map(p=>{
    const fee=feeMap.get(String(p.student_fee_id))||{};
    const stu=studentMap.get(String(fee.student_id))||{};
    const cls=classMap.get(String(stu.class_id))||{};
    return Object.assign({},p,{payment_date:String((p.payment_date||String(p.created_at||'').slice(0,10))||'').slice(0,10),student_id:fee.student_id||null,student_name:stu.name||'—',class_name:cls.name||'—',receiver_name:receiverLabel(p,userMap),receiver_role:(userMap.get(String(p.received_by))||{}).role||p.receiver_role||null,amount_usd:Number(p.amount_usd||p.amount||0),amount_irr:Number(p.amount_irr||0),voided:!!p.voided});
  });
  const byReceiverMap=new Map(), byMethodMap=new Map();
  let totalUsd=0,totalIrr=0,voidedCount=0,paymentsCount=0;
  filtered.forEach(p=>{
    if(p.voided) voidedCount+=1; else {paymentsCount+=1; totalUsd+=p.amount_usd; totalIrr+=p.amount_irr||0;}
    const rk=[p.receiver_name||'غير محدد',p.received_by||'',p.receiver_role||''].join('|');
    const rv=byReceiverMap.get(rk)||{receiver_name:p.receiver_name||'غير محدد',received_by:p.received_by||null,receiver_role:p.receiver_role||null,payments_count:0,voided_count:0,total_usd:0,total_irr:0};
    if(p.voided) rv.voided_count+=1; else {rv.payments_count+=1; rv.total_usd+=p.amount_usd; rv.total_irr+=(p.amount_irr||0);} byReceiverMap.set(rk,rv);
    const mk=p.payment_method||'cash';
    const mv=byMethodMap.get(mk)||{payment_method:mk,payments_count:0,total_usd:0,total_irr:0};
    if(!p.voided){mv.payments_count+=1; mv.total_usd+=p.amount_usd; mv.total_irr+=(p.amount_irr||0);} byMethodMap.set(mk,mv);
  });
  DATA={
    stats:{from:d1,to:d2,payments_count:paymentsCount,voided_count:voidedCount,total_usd:totalUsd,total_irr:totalIrr,receivers_count:byReceiverMap.size},
    by_receiver:[...byReceiverMap.values()].sort((a,b)=>b.total_usd-a.total_usd),
    by_method:[...byMethodMap.values()].sort((a,b)=>b.total_usd-a.total_usd),
    payments:filtered.slice().sort((a,b)=>String(b.created_at||'').localeCompare(String(a.created_at||''))),
    users,rates
  };
}catch(e){toast('تعذر تحميل التقرير',e.message||String(e),'red');DATA={stats:{},by_receiver:[],by_method:[],payments:[],users:[],rates:[]}}
render(ACTIVE);ensureMonthToolbar();bindMonthFilter()}
function render(id){ACTIVE=id;$$('.view').forEach(v=>v.classList.toggle('active',v.id==='view-'+id));$$('.nav button[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view===id));({overview,receivers:receiversView,methods:methodsView,payments:paymentsView,voided:voidedView}[id]||overview)()}
function kpi(l,v,c='blue'){return `<div class="kpi ${c}"><small>${esc(l)}</small><b>${esc(v??0)}</b></div>`}
function overview(){const s=DATA.stats;const range=currentRange();$('#view-overview').innerHTML=`<div class="page-head"><div><h1>تقارير المستلمين</h1><p>تحليل التحصيل حسب المستلم والطريقة للشهر الشمسي المحدد.</p></div><div class="quick-links"><button class="btn blue" onclick="location.href='finance-cashbox.html'">فتح الصندوق</button><button class="btn gold" onclick="location.href='finance-executive.html'">فتح التنفيذي</button></div><span class="report-period">${esc(range.label)} — ${esc(range.gregorian)}</span></div><div class="kpis">${kpi('عدد الدفعات',s.payments_count,'gold')}${kpi('الإجمالي',dualMoney(s.total_usd,s.total_irr),'green')}${kpi('عدد المستلمين',s.receivers_count,'blue')}${kpi('ملغاة',s.voided_count,'red')}</div><div class="cards"><div class="card"><div class="card-head"><h3>أعلى المستلمين</h3></div><div class="card-body">${receiverCards(DATA.by_receiver.slice(0,8))}</div></div><div class="card"><div class="card-head"><h3>حسب طريقة الدفع</h3></div><div class="card-body">${methodCards(DATA.by_method)}</div></div></div>`}
function receiverCards(list){return `<div class="receiver-grid">${list.map(r=>`<article class="receiver-card"><h3>${esc(r.receiver_name)}</h3><div class="receiver-meta"><span>دفعات: ${r.payments_count}</span><span>ملغاة: ${r.voided_count}</span><span>دور: ${esc(r.receiver_role||'—')}</span></div><b>${dualMoney(r.total_usd,r.total_irr)}</b></article>`).join('')||'<div class="empty">لا توجد بيانات</div>'}</div>`}
function methodCards(list){return `<div class="receiver-grid">${list.map(r=>`<article class="receiver-card method-card"><h3>${esc(methodLabel(r.payment_method))}</h3><div class="receiver-meta"><span>دفعات: ${r.payments_count}</span></div><b>${dualMoney(r.total_usd,r.total_irr)}</b></article>`).join('')||'<div class="empty">لا توجد بيانات</div>'}</div>`}
function methodLabel(m){return {cash:'نقداً',card:'بطاقة',transfer:'حوالة',other:'أخرى'}[m]||m||'—'}
function receiversView(){$('#view-receivers').innerHTML=`<div class="page-head"><div><h1>حسب المستلم</h1></div></div>${receiverCards(DATA.by_receiver)}`}
function methodsView(){$('#view-methods').innerHTML=`<div class="page-head"><div><h1>حسب طريقة الدفع</h1></div></div>${methodCards(DATA.by_method)}`}
function paymentsTable(list){const rows=list.map(p=>`<tr class="${p.voided?'voided-row':''}"><td>${esc(p.receipt_number||'—')}</td><td>${esc(dualDate(p.payment_date||'—'))}</td><td>${esc(p.student_name||'—')}</td><td>${dualMoney(p.amount_usd,p.amount_irr)}</td><td>${esc(methodLabel(p.payment_method))}</td><td>${esc(p.payer_name||'—')}</td><td>${esc(p.receiver_name||'—')}</td><td>${p.voided?'<span class="badge red">ملغاة</span>':`<button class="btn small blue" onclick="FinanceReceiverReports.editReceiver('${p.id}')">تعديل المستلم</button><button class="btn small red" onclick="FinanceReceiverReports.voidPayment('${p.id}')">إلغاء</button>`}</td></tr>`);return table(['الإيصال','التاريخ','الطالب','المبلغ','الطريقة','الدافع','المستلم','إجراء'],rows,'لا توجد مدفوعات')}
function paymentsView(){$('#view-payments').innerHTML=`<div class="page-head"><div><h1>كل المدفوعات</h1></div></div>${paymentsTable(DATA.payments)}`}
function voidedView(){$('#view-voided').innerHTML=`<div class="page-head"><div><h1>الدفعات الملغاة</h1></div></div>${paymentsTable(DATA.payments.filter(p=>p.voided))}`}
function userOptions(){const preferred=['admin','finance','staff','accountant','cashier'];return DATA.users.filter(u=>preferred.includes(String(u.role||''))).map(u=>`<option value="${u.id}">${esc(u.name||u.email)} — ${esc(roleLabel(u.role))}</option>`).join('')+'<option value="__other__">مستلم يدوي</option>'}
function editReceiver(id){const p=DATA.payments.find(x=>String(x.id)===String(id));if(!p)return;const html=`<div class="modal-backdrop"><div class="modal-card"><h3>تعديل مستلم الدفعة</h3><p class="muted">إيصال: ${esc(p.receipt_number||'—')} · الطالب: ${esc(p.student_name||'—')}</p><select id="newReceiver" class="select">${userOptions()}</select><input id="newReceiverName" class="input" placeholder="اسم مستلم يدوي اختياري"><div class="form-actions"><button id="confirmReceiver" class="btn gold">حفظ المستلم</button><button class="btn" onclick="this.closest('.modal-backdrop').remove()">إلغاء</button></div></div></div>`;document.body.insertAdjacentHTML('beforeend',html);$('#confirmReceiver').onclick=()=>saveReceiver(id)}
async function saveReceiver(id){const rid=$('#newReceiver')?.value;const manual=$('#newReceiverName')?.value||null;try{const {data,error}=await client().rpc('update_payment_receiver',{p_payment_id:id,p_received_by:rid==='__other__'?null:rid,p_receiver_name:manual,p_receiver_role:null});if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر التعديل');toast('تم','تم تعديل مستلم الدفعة','green');$('.modal-backdrop')?.remove();await load();render('payments')}catch(e){try{const u=(DATA.users||[]).find(x=>String(x.id)===String(rid));const payload={received_by:rid==='__other__'?null:rid,receiver_name:rid==='__other__'?(manual||'مستلم يدوي'):(u?.name||manual||null),receiver_role:rid==='__other__'?null:(u?.role||null)};const {error:pe}=await client().from('fee_payments').update(payload).eq('id',id);if(pe)throw pe;toast('تم','تم تعديل مستلم الدفعة (fallback)','green');$('.modal-backdrop')?.remove();await load();render('payments')}catch(inner){toast('تعذر تعديل المستلم',inner.message||e.message||String(e),'red')}}}
async function directVoidPayment(id,reason){const {data:p,error:pe}=await client().from('fee_payments').select('id,student_fee_id,student_installment_id,amount_usd,amount,voided').eq('id',id).maybeSingle();if(pe)throw pe;if(!p)throw new Error('الدفعة غير موجودة');if(p.voided)return {ok:true,message:'الدفعة ملغاة مسبقاً'};const usd=Number(p.amount_usd||p.amount||0);if(p.student_installment_id){const {data:inst,error:ie}=await client().from('student_installments').select('id,amount_due,amount_paid,actual_payment_date').eq('id',p.student_installment_id).maybeSingle();if(ie)throw ie;if(inst){const newPaid=Math.max(Number(inst.amount_paid||0)-usd,0);const {error:iu}=await client().from('student_installments').update({amount_paid:newPaid,balance_remaining:Math.max(Number(inst.amount_due||0)-newPaid,0),status:newPaid<=0?'unpaid':newPaid<Number(inst.amount_due||0)?'partial':'paid',actual_payment_date:newPaid<=0?null:inst.actual_payment_date}).eq('id',inst.id);if(iu)throw iu;}}
if(p.student_fee_id){const {data:f,error:fe}=await client().from('student_fees').select('id,total_paid,net_amount,base_amount,gross_amount').eq('id',p.student_fee_id).maybeSingle();if(fe)throw fe;if(f){const newPaid=Math.max(Number(f.total_paid||0)-usd,0);const target=Number(f.net_amount||f.base_amount||f.gross_amount||0);const {error:fu}=await client().from('student_fees').update({total_paid:newPaid,status:newPaid<=0?'unpaid':newPaid<target?'partial':'paid'}).eq('id',f.id);if(fu)throw fu;}}
const {error:pu}=await client().from('fee_payments').update({voided:true,void_reason:reason,voided_at:new Date().toISOString()}).eq('id',id);if(pu)throw pu;return {ok:true,message:'تم إلغاء الدفعة وعكس الأرصدة (fallback)'};}
async function voidPayment(id){const reason=prompt('سبب إلغاء الدفعة:');if(!reason)return;try{const {data,error}=await client().rpc('void_fee_payment',{p_payment_id:id,p_reason:reason});if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر الإلغاء');toast('تم إلغاء الدفعة','تم عكس الأرصدة وتسجيل العملية','green');await load();render('payments')}catch(e){try{const r=await directVoidPayment(id,reason);toast('تم إلغاء الدفعة',r.message||'تم بالعكس المباشر','green');await load();render('payments')}catch(inner){toast('تعذر إلغاء الدفعة',inner.message||e.message||String(e),'red')}}}
function table(h,rows,empty='لا توجد بيانات'){const body=Array.isArray(rows)?rows.join(''):String(rows||'');return body.trim()?`<div class="table-wrap"><table><thead><tr>${h.map(x=>`<th>${esc(x)}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>`:`<div class="empty">${esc(empty)}</div>`}
function exportCsv(){const rows=DATA.payments.map(p=>({'الإيصال':p.receipt_number||'','التاريخ':p.payment_date||'','الطالب':p.student_name||'','USD':p.amount_usd||0,'IRR':p.amount_irr||0,'الطريقة':methodLabel(p.payment_method),'الدافع':p.payer_name||'','المستلم':p.receiver_name||'','ملغاة':p.voided?'نعم':'لا'}));if(!rows.length){toast('لا توجد بيانات','لا توجد مدفوعات للتصدير','red');return}downloadCsv(`finance-receiver-report-${currentMonth()}.csv`,['الإيصال','التاريخ','الطالب','USD','IRR','الطريقة','الدافع','المستلم','ملغاة'],rows)}
function printView(){window.print()}
function bindMonthFilter(){const m=$('#monthFilter');if(m&&!m.dataset.bound){m.dataset.bound='1';m.addEventListener('change',load)}}
function bind(){$$('.nav button[data-view]').forEach(b=>b.addEventListener('click',()=>render(b.dataset.view)));$('#mobileMenuBtn')?.addEventListener('click',()=>$('#sidebar').classList.toggle('open'));$('#logoutBtn')?.addEventListener('click',async()=>{await client().auth.signOut({scope:'local'});location.href='index.html'});$('#refreshBtn')?.addEventListener('click',load);$('#exportBtn')?.addEventListener('click',exportCsv);$('#printBtn')?.addEventListener('click',printView);ensureMonthToolbar();bindMonthFilter()}
async function init(){client();if(!await ensure())return;bind();await load()}
window.FinanceReceiverReports={init,render,editReceiver,saveReceiver,voidPayment,exportCsv,printView};
}());

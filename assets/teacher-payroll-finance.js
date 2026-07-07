(function(){
'use strict';
const cfg=()=>window.AMIN_CONFIG||{};
let sb=null,ME=null;
let DATA={daily:[],rates:[],extras:[],adjustments:[],latenessEvents:[],latenessRules:[]};
let FX={rate:0,label:'آخر سعر محفوظ'};
const RT=()=>window.FinanceRuntime||{};
const $=(s,r=document)=>r.querySelector(s);
function esc(v){return String(v==null?'':v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#039;')}
function num(v){const n=Number(v);return Number.isFinite(n)?n:0}
function money(v){return num(v).toLocaleString('en-US',{style:'currency',currency:'USD',maximumFractionDigits:2})}
function irr(v){return num(v).toLocaleString('fa-IR')+' ریال'}
function dualMoney(usd,irrValue){const rv=num(irrValue||0)|| (FX.rate?num(usd)*FX.rate:0);return rv?`${money(usd)} / ${irr(rv)}`:`${money(usd)} / —`}
function dualDate(v){return RT().dualDate?RT().dualDate(String(v||'').slice(0,10)):String(v||'').slice(0,10)}
function monthValue(){return RT().currentSolarMonthKey?RT().currentSolarMonthKey():new Date().toISOString().slice(0,7)}
function monthMeta(key){return RT().solarMonthRangeFromKey?RT().solarMonthRangeFromKey(key):{key,label:key,gregorianLabel:'—'}}
function monthSelect(id,value,seedKeys){return RT().buildMonthSelect?RT().buildMonthSelect(id,value,seedKeys,14,2):`<input id="${id}" class="input" value="${esc(value)}">`}
function monthKeyFromIso(iso){return RT().solarMonthKeyFromIso?RT().solarMonthKeyFromIso(String(iso||'').slice(0,10)):String(iso||'').slice(0,7)}
function client(){if(sb)return sb;sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:(cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}});return sb}
function toast(t,m,type=''){const el=$('#toast');if(!el)return;el.innerHTML=`<b>${esc(t)}</b><br><span class="muted">${esc(m||'')}</span>`;el.className='toast show '+type;clearTimeout(el._t);el._t=setTimeout(()=>el.classList.remove('show'),4500)}
async function q(table,opts={}){try{let query=client().from(table).select(opts.columns||'*');(opts.filters||[]).forEach(f=>query=query[f.op](f.col,f.val));if(opts.order)query=query.order(opts.order,{ascending:opts.ascending!==false});if(opts.limit)query=query.limit(opts.limit);const {data,error}=await query;if(error){console.warn(table,error);return []}return data||[]}catch(e){console.warn(table,e);return []}}
async function ensure(){const {data:{session}}=await client().auth.getSession();if(!session){location.href='index.html';return false}const {data:u}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();if(!u){location.href='index.html';return false}ME=u;$('#profileName').textContent=u.name||u.email||'مستخدم';$('#profileRole').textContent=u.role||'—';const ok=u.is_super_admin||['admin','finance','academic','academic_admin','scientific','supervisor'].includes(String(u.role||''));if(!ok){document.body.innerHTML='<main class="login-page"><section class="login-card"><h1>غير مصرح</h1><p>هذه الصفحة للمدير والمالية والمعاون العلمي فقط.</p></section></main>';return false}return true}
async function load(){
  DATA.daily=await q('v_teacher_payroll_daily',{order:'session_date',ascending:false,limit:5000});
  DATA.extras=await q('v_teacher_extra_sessions_detailed',{order:'session_date',ascending:false,limit:1500});
  DATA.adjustments=await q('teacher_payroll_adjustments',{order:'effective_month',ascending:false,limit:1500});
  DATA.latenessEvents=await q('v_teacher_lateness_events',{order:'session_date',ascending:false,limit:5000});
  DATA.latenessRules=await q('teacher_lateness_rules',{order:'min_late_minutes',ascending:true,limit:100});
  DATA.rates=await q('exchange_rates',{order:'fetched_at',ascending:false,limit:20});
  const latest=DATA.rates[0];
  if(latest&&num(latest.rate)>0)FX={rate:num(latest.rate),label:latest.source||'آخر سعر محفوظ'};
  render();
}
function currentMonth(){return ($('#monthFilter')?.value)||monthValue()}
function currentTeacher(){return ($('#teacherFilter')?.value)||''}
function inMonth(iso,key){return monthKeyFromIso(iso)===key}
function teacherMap(){
  const map=new Map();
  [...(DATA.daily||[]),...(DATA.extras||[]),...(DATA.adjustments||[]),...(DATA.latenessEvents||[])].forEach(x=>{
    if(x.teacher_id&&!map.has(String(x.teacher_id)))map.set(String(x.teacher_id),x.teacher_name||'—');
  });
  return map;
}
function teacherOptions(){return [...teacherMap().entries()].map(([id,name])=>`<option value="${id}">${esc(name)}</option>`).join('')}
function selectedTeacherOptions(){return '<option value="">كل المعلمين</option>'+teacherOptions()}
function categoryLabel(v){return ({substitute_absent_teacher:'حلول مكان معلم غائب',holiday_work:'دوام يوم عطلة',online_session:'حصة إلكترونية',extra_support:'دعم إضافي',exam_supervision:'مراقبة/إشراف',other:'أخرى'}[v]||v||'—')}
function adjustmentTypeLabel(v){return ({bonus:'مكافأة',deduction:'خصم'}[v]||v||'—')}
function table(h,rows,empty){const body=rows.join('');return body?`<div class="table-wrap"><table><thead><tr>${h.map(x=>`<th>${esc(x)}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table></div>`:`<div class="empty">${esc(empty||'لا توجد بيانات')}</div>`}
function csvEscape(v){const s=String(v==null?'':v);return /[",\n]/.test(s)?'"'+s.replace(/"/g,'""')+'"':s}
function penaltyRows(){
  const ym=currentMonth(), tid=currentTeacher();
  const rules=(DATA.latenessRules||[]).filter(r=>r.is_active!==false && num(r.repeat_count)>0 && num(r.penalty_session_units)>0);
  const events=(DATA.latenessEvents||[]).filter(e=>e.late_status==='late' && inMonth(e.session_date,ym) && (!tid||String(e.teacher_id)===String(tid)));
  const rows=[];
  const teacherNameById=teacherMap();
  const groups=new Map();
  events.forEach(e=>{
    rules.forEach(r=>{
      if(num(e.late_minutes)>=num(r.min_late_minutes) && (r.max_late_minutes==null || num(e.late_minutes)<=num(r.max_late_minutes))){
        const key=[e.teacher_id,r.id||r.rule_name].join('|');
        if(!groups.has(key))groups.set(key,{teacher_id:e.teacher_id,teacher_name:e.teacher_name||teacherNameById.get(String(e.teacher_id))||'—',rule_id:r.id,rule_name:r.rule_name||'—',repeat_count:num(r.repeat_count),penalty_session_units:num(r.penalty_session_units),late_events:0});
        groups.get(key).late_events+=1;
      }
    });
  });
  groups.forEach(g=>{const batches=Math.floor(g.late_events/Math.max(g.repeat_count,1));const total=Number((batches*g.penalty_session_units).toFixed(2));if(g.late_events>0)rows.push({...g,penalty_batches:batches,penalty_session_units_total:total})});
  return rows.sort((a,b)=>String(a.teacher_name).localeCompare(String(b.teacher_name),'ar')||num(b.penalty_session_units_total)-num(a.penalty_session_units_total));
}
function extraRows(){const ym=currentMonth(), tid=currentTeacher();return (DATA.extras||[]).filter(x=>inMonth(x.session_date,ym)&&(!tid||String(x.teacher_id)===String(tid)))}
function adjustmentRows(){const ym=currentMonth(), tid=currentTeacher();return (DATA.adjustments||[]).filter(x=>x.is_active!==false && inMonth(x.effective_month,ym)&&(!tid||String(x.teacher_id)===String(tid)))}
function monthlyRows(){
  const ym=currentMonth(), tid=currentTeacher();
  const daily=(DATA.daily||[]).filter(x=>inMonth(x.session_date,ym)&&(!tid||String(x.teacher_id)===String(tid)));
  const extrasByTeacher=new Map();
  extraRows().forEach(x=>{const k=String(x.teacher_id);const cur=extrasByTeacher.get(k)||{count:0,units:0,amount:0};cur.count+=1;cur.units+=num(x.session_units);cur.amount+=num(x.extra_amount);extrasByTeacher.set(k,cur)});
  const adjByTeacher=new Map();
  adjustmentRows().forEach(x=>{const k=String(x.teacher_id);const cur=adjByTeacher.get(k)||{bonus:0,deduction:0};if(x.adjustment_type==='deduction')cur.deduction+=num(x.amount_usd);else cur.bonus+=num(x.amount_usd);adjByTeacher.set(k,cur)});
  const penaltiesByTeacher=new Map();
  penaltyRows().forEach(x=>{const k=String(x.teacher_id);penaltiesByTeacher.set(k,num((penaltiesByTeacher.get(k)||0)+num(x.penalty_session_units_total)))});
  const map=new Map();
  daily.forEach(d=>{
    const k=String(d.teacher_id);const row=map.get(k)||{teacher_id:d.teacher_id,teacher_name:d.teacher_name||'—',month:ym,total_sessions:0,prepared_sessions:0,homework_sessions:0,gross_verified_sessions:0,amount_per_session:num(d.amount_per_session),currency:d.currency||'USD',fully_documented_sessions:0,incomplete_sessions:0};
    row.total_sessions+=num(d.total_sessions);row.prepared_sessions+=num(d.prepared_sessions);row.homework_sessions+=num(d.homework_sessions);row.gross_verified_sessions+=num(d.earned_session_units);row.fully_documented_sessions+=num(d.fully_documented_sessions);row.incomplete_sessions+=num(d.incomplete_sessions);row.amount_per_session=Math.max(row.amount_per_session,num(d.amount_per_session));map.set(k,row);
  });
  [...teacherMap().entries()].forEach(([k,name])=>{if((!tid||String(k)===String(tid)) && !map.has(String(k))){const hasExtra=extrasByTeacher.has(String(k)),hasAdj=adjByTeacher.has(String(k)),hasPenalty=penaltiesByTeacher.has(String(k));if(hasExtra||hasAdj||hasPenalty)map.set(String(k),{teacher_id:k,teacher_name:name,month:ym,total_sessions:0,prepared_sessions:0,homework_sessions:0,gross_verified_sessions:0,amount_per_session:0,currency:'USD',fully_documented_sessions:0,incomplete_sessions:0})}});
  return [...map.values()].map(row=>{
    const extra=extrasByTeacher.get(String(row.teacher_id))||{count:0,units:0,amount:0};
    const adj=adjByTeacher.get(String(row.teacher_id))||{bonus:0,deduction:0};
    const penalty=num(penaltiesByTeacher.get(String(row.teacher_id))||0);
    const verified=Math.max(0,Number((num(row.gross_verified_sessions)-penalty).toFixed(2)));
    const base=Number((verified*num(row.amount_per_session)).toFixed(2));
    const estimated=Number((base+num(extra.amount)+num(adj.bonus)-num(adj.deduction)).toFixed(2));
    return {...row,penalty_session_units:penalty,verified_sessions:verified,base_estimated_amount:base,extra_sessions_count:extra.count,extra_session_units:Number(num(extra.units).toFixed(2)),extra_session_amount:Number(num(extra.amount).toFixed(2)),bonus_amount:Number(num(adj.bonus).toFixed(2)),deduction_amount:Number(num(adj.deduction).toFixed(2)),estimated_amount:estimated};
  }).sort((a,b)=>String(a.teacher_name).localeCompare(String(b.teacher_name),'ar'));
}
function dailyRows(){const ym=currentMonth(), tid=currentTeacher();return (DATA.daily||[]).filter(x=>inMonth(x.session_date,ym)&&(!tid||String(x.teacher_id)===String(tid)))}
function exportCsv(){
  const monthRows=monthlyRows();
  const dayRows=dailyRows();
  const penalty=penaltyRows();
  const lines=[];
  lines.push(['المعلم','الشهر الشمسي','إجمالي الحصص','تحضير','واجبات','إجمالي الوحدات','الحسميات','الصافي','أجر الحصة USD','المبلغ النهائي USD'].map(csvEscape).join(','));
  monthRows.forEach(x=>lines.push([x.teacher_name,x.month,num(x.total_sessions),num(x.prepared_sessions),num(x.homework_sessions),num(x.gross_verified_sessions),num(x.penalty_session_units),num(x.verified_sessions),num(x.amount_per_session||0),num(x.estimated_amount||0)].map(csvEscape).join(',')));
  lines.push('');
  lines.push(['التاريخ','المعلم','الحصص اليومية','الوحدات اليومية','المبلغ اليومي USD'].map(csvEscape).join(','));
  dayRows.forEach(x=>lines.push([String(x.session_date||'').slice(0,10),x.teacher_name,num(x.total_sessions),num(x.earned_session_units),num(x.estimated_amount||0)].map(csvEscape).join(',')));
  lines.push('');
  lines.push(['المعلم','القاعدة','عدد التأخيرات','عدد مرات تحقق القاعدة','الحصص المخصومة'].map(csvEscape).join(','));
  penalty.forEach(x=>lines.push([x.teacher_name,x.rule_name,num(x.late_events),num(x.penalty_batches),num(x.penalty_session_units_total)].map(csvEscape).join(',')));
  const blob=new Blob([lines.join('\n')],{type:'text/csv;charset=utf-8'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=`teacher-payroll-${currentMonth()}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),500)
}
function printView(){window.print()}
async function saveExtraSession(){
  try{
    const teacherId=$('#extraTeacher')?.value;const sessionDate=$('#extraDate')?.value;const category=$('#extraCategory')?.value||'other';const units=num($('#extraUnits')?.value||1);const rateOverride=$('#extraRateOverride')?.value?num($('#extraRateOverride').value):null;const replacementTeacherId=$('#replacementTeacher')?.value||null;const reason=$('#extraReason')?.value||'';const notes=$('#extraNotes')?.value||null;
    if(!teacherId||!sessionDate||!reason.trim()){toast('تنبيه','املئي المعلم والتاريخ والسبب','red');return}
    const {data,error}=await client().rpc('save_teacher_extra_session',{p_teacher_id:teacherId,p_session_date:sessionDate,p_category:category,p_session_units:units,p_rate_override:rateOverride,p_replacement_teacher_id:replacementTeacherId||null,p_reason:reason,p_notes:notes});
    if(error)throw error;if(data&&data.ok===false)throw new Error(data.message||'تعذر حفظ الحصة الإضافية');toast('تم','تم حفظ الحصة الإضافية','green');await load();
  }catch(e){toast('تعذر الحفظ',e.message||String(e),'red')}
}
async function saveAdjustment(){
  try{
    const teacherId=$('#adjTeacher')?.value;const month=$('#adjMonth')?.value;const type=$('#adjType')?.value||'bonus';const amount=num($('#adjAmount')?.value||0);const reason=$('#adjReason')?.value||'';const notes=$('#adjNotes')?.value||null;
    if(!teacherId||!month||!reason.trim()||amount<=0){toast('تنبيه','املئي المعلم والشهر والمبلغ والسبب','red');return}
    const meta=monthMeta(month);
    const payload={teacher_id:teacherId,effective_month:meta.start,adjustment_type:type,amount_usd:amount,reason:reason.trim(),notes:notes&&notes.trim()?notes.trim():null,is_active:true,created_by:ME.id,approved_by:ME.id,approved_at:new Date().toISOString()};
    const {error}=await client().from('teacher_payroll_adjustments').insert(payload);
    if(error)throw error;
    toast('تم','تم حفظ التعديل المالي للشهر الشمسي المحدد','green');
    await load();
  }catch(e){toast('تعذر الحفظ',e.message||String(e),'red')}
}
function render(){
  const ym=currentMonth();
  const meta=monthMeta(ym);
  const monthRows=monthlyRows();
  const dayRows=dailyRows();
  const penalty=penaltyRows();
  const extras=extraRows();
  const adjustments=adjustmentRows();
  const totalNetUnits=monthRows.reduce((a,x)=>a+num(x.verified_sessions),0);
  const totalPenaltyUnits=monthRows.reduce((a,x)=>a+num(x.penalty_session_units),0);
  const totalGrossUnits=monthRows.reduce((a,x)=>a+num(x.gross_verified_sessions),0);
  const totalAmount=monthRows.reduce((a,x)=>a+num(x.estimated_amount),0);
  const extraAmount=monthRows.reduce((a,x)=>a+num(x.extra_session_amount),0);
  const bonusAmount=monthRows.reduce((a,x)=>a+num(x.bonus_amount),0);
  const deductionAmount=monthRows.reduce((a,x)=>a+num(x.deduction_amount),0);
  const avgPerTeacher=monthRows.length?totalAmount/monthRows.length:0;
  const fxRef=esc(FX.label)+(FX.rate?(' ('+irr(FX.rate)+' للدولار)'):'');
  const teacherSelectOptions=selectedTeacherOptions();
  const monthKeys=[...new Set([monthValue(),...(DATA.daily||[]).map(x=>monthKeyFromIso(x.session_date)),...(DATA.extras||[]).map(x=>monthKeyFromIso(x.session_date)),...(DATA.adjustments||[]).map(x=>monthKeyFromIso(x.effective_month)),...(DATA.latenessEvents||[]).map(x=>monthKeyFromIso(x.session_date))].filter(Boolean))];
  const root=$('#teacherPayrollRoot');if(!root)return;
  root.innerHTML=`<div class="page-head"><div><h1>رواتب المعلمين اليومية</h1><p>الشهر المالي هنا شمسي كأساس، والميلادي ظاهر معه للمرجع والتدقيق.</p></div></div>
  <div class="quick-strip" style="margin-bottom:16px"><div class="quick-box"><small>إجمالي الوحدات المكتسبة</small><b>${totalGrossUnits.toFixed(1)}</b></div><div class="quick-box"><small>الوحدات المخصومة</small><b>${totalPenaltyUnits.toFixed(1)}</b></div><div class="quick-box"><small>صافي الوحدات</small><b>${totalNetUnits.toFixed(1)}</b></div><div class="quick-box"><small>صافي المبلغ</small><b>${esc(dualMoney(totalAmount))}</b></div></div>
  <div class="payroll-card no-print" style="margin-bottom:16px"><div style="display:grid;grid-template-columns:1.1fr 1fr auto auto auto;gap:10px">${monthSelect('monthFilter',ym,monthKeys)}<select id="teacherFilter" class="select">${teacherSelectOptions}</select><button class="btn blue" onclick="TeacherPayrollFinance.renderNow()">تطبيق</button><button class="btn gold" onclick="TeacherPayrollFinance.exportCsv()">تصدير CSV</button><button class="btn" onclick="TeacherPayrollFinance.printView()">طباعة</button></div><div class="muted-note" style="margin-top:12px">الشهر المحدد: <b>${esc(meta.label)}</b> — النطاق الميلادي: <b>${esc(meta.gregorianLabel)}</b><br>الرقم النهائي = الأساس بعد الحسميات + الحصص الإضافية + المكافآت - الخصومات اليدوية. | سعر التحويل المرجعي: ${fxRef}</div><div class="payroll-links"><span class="payroll-link">📘 راجع الإقفال الشهري قبل الاعتماد النهائي</span><span class="payroll-link">⏱️ راقب الحسميات قبل دفع الرواتب</span><span class="payroll-link">📈 قارن أثر الرواتب داخل لوحة النمو</span></div></div>
  <div class="payroll-card no-print" style="margin-bottom:16px"><h3>الحصص الإضافية والمكافآت</h3><div style="display:grid;grid-template-columns:1fr 1fr;gap:16px"><div><h4 style="margin-bottom:10px">إضافة حصة إضافية</h4><div style="display:grid;grid-template-columns:1fr 1fr;gap:10px"><select id="extraTeacher" class="select">${teacherSelectOptions}</select><input id="extraDate" class="input" type="date"><select id="extraCategory" class="select"><option value="substitute_absent_teacher">حلول مكان معلم غائب</option><option value="holiday_work">دوام يوم عطلة</option><option value="online_session">حصة إلكترونية</option><option value="extra_support">دعم إضافي</option><option value="exam_supervision">مراقبة/إشراف</option><option value="other">أخرى</option></select><input id="extraUnits" class="input" type="number" step="0.5" value="1" placeholder="عدد الحصص"><input id="extraRateOverride" class="input" type="number" step="0.01" placeholder="سعر خاص اختياري بالدولار"><select id="replacementTeacher" class="select"><option value="">المعلم الغائب (اختياري)</option>${teacherOptions()}</select><input id="extraReason" class="input" style="grid-column:1/-1" placeholder="سبب الحصة الإضافية *"><input id="extraNotes" class="input" style="grid-column:1/-1" placeholder="ملاحظات إضافية"><button class="btn gold" style="grid-column:1/-1" onclick="TeacherPayrollFinance.saveExtraSession()">حفظ الحصة الإضافية</button></div></div><div><h4 style="margin-bottom:10px">إضافة مكافأة / خصم</h4><div style="display:grid;grid-template-columns:1fr 1fr;gap:10px"><select id="adjTeacher" class="select">${teacherSelectOptions}</select>${monthSelect('adjMonth',ym,monthKeys)}<select id="adjType" class="select"><option value="bonus">مكافأة</option><option value="deduction">خصم يدوي</option></select><input id="adjAmount" class="input" type="number" step="0.01" placeholder="المبلغ بالدولار"><input id="adjReason" class="input" style="grid-column:1/-1" placeholder="سبب المكافأة أو الخصم *"><input id="adjNotes" class="input" style="grid-column:1/-1" placeholder="ملاحظات إضافية"><button class="btn gold" style="grid-column:1/-1" onclick="TeacherPayrollFinance.saveAdjustment()">حفظ التعديل المالي</button></div></div></div></div>
  <div class="quick-strip" style="margin-bottom:16px"><div class="quick-box"><small>عدد المعلمين الظاهرين</small><b>${monthRows.length}</b></div><div class="quick-box"><small>متوسط صافي المبلغ</small><b>${esc(dualMoney(avgPerTeacher))}</b></div><div class="quick-box"><small>إجمالي الحسميات</small><b>${totalPenaltyUnits.toFixed(1)} حصة</b></div><div class="quick-box"><small>حوافز/إضافات هذا الشهر</small><b>${esc(dualMoney(extraAmount + bonusAmount - deductionAmount))}</b></div></div>
  <div class="payroll-grid"><div class="payroll-card"><h3>كشف شهري صافي</h3>${table(['المعلم','الشهر الشمسي','إجمالي الوحدات','الحسميات','صافي الوحدات','حصص إضافية','مبلغ الحصص الإضافية','المكافآت','الخصومات','المبلغ النهائي'],monthRows.map(x=>`<tr><td>${esc(x.teacher_name||'—')}</td><td><b>${esc(meta.label)}</b><br><small class="muted">${esc(meta.gregorianLabel)}</small></td><td><span class="badge blue">${num(x.gross_verified_sessions)}</span></td><td><span class="badge red">${num(x.penalty_session_units)}</span></td><td><span class="badge green">${num(x.verified_sessions)}</span></td><td>${num(x.extra_session_units||0)}</td><td>${esc(dualMoney(x.extra_session_amount||0))}</td><td>${esc(dualMoney(x.bonus_amount||0))}</td><td>${esc(dualMoney(x.deduction_amount||0))}</td><td><b>${esc(dualMoney(x.estimated_amount||0))}</b></td></tr>`),'لا توجد بيانات لهذا الشهر الشمسي')}</div><div class="payroll-card"><h3>كشف يومي مختصر</h3>${table(['المعلم','التاريخ','عدد الحصص','محضّرة','لها واجب','وحدات يومية','المبلغ اليومي'],dayRows.slice(0,120).map(x=>`<tr><td>${esc(x.teacher_name||'—')}</td><td>${esc(dualDate(x.session_date))}</td><td>${num(x.total_sessions)}</td><td>${num(x.prepared_sessions)}</td><td>${num(x.homework_sessions)}</td><td><span class="badge blue">${num(x.earned_session_units)}</span></td><td><b>${esc(dualMoney(x.estimated_amount||0))}</b></td></tr>`),'لا توجد بيانات يومية')}</div></div>
  <div class="payroll-grid" style="margin-top:16px"><div class="payroll-card"><h3>تفصيل الحصص الإضافية</h3>${table(['المعلم','التاريخ','النوع','عدد الحصص','السعر','القيمة','السبب'],extras.map(x=>`<tr><td>${esc(x.teacher_name||'—')}</td><td>${esc(dualDate(x.session_date))}</td><td>${esc(categoryLabel(x.category))}</td><td>${num(x.session_units)}</td><td>${esc(dualMoney(x.effective_rate||0))}</td><td><b>${esc(dualMoney(x.extra_amount||0))}</b></td><td>${esc(x.reason||'—')}</td></tr>`),'لا توجد حصص إضافية في هذا الشهر')}</div><div class="payroll-card"><h3>تفصيل المكافآت والخصومات</h3>${table(['المعلم','الشهر','النوع','المبلغ','السبب'],adjustments.map(x=>`<tr><td>${esc(x.teacher_name||'—')}</td><td><b>${esc(meta.label)}</b><br><small class="muted">${esc(monthMeta(monthKeyFromIso(x.effective_month)).gregorianLabel)}</small></td><td><span class="badge ${x.adjustment_type==='bonus'?'green':'red'}">${esc(adjustmentTypeLabel(x.adjustment_type))}</span></td><td><b>${esc(dualMoney(x.amount_usd||0))}</b></td><td>${esc(x.reason||'—')}</td></tr>`),'لا توجد مكافآت أو خصومات يدوية في هذا الشهر')}</div></div>
  <div class="payroll-card" style="margin-top:16px"><h3>تفصيل الحسميات</h3>${table(['المعلم','القاعدة','عدد التأخيرات','عدد مرات تحقق القاعدة','الحصص المخصومة'],penalty.map(x=>`<tr><td>${esc(x.teacher_name||'—')}</td><td>${esc(x.rule_name||'—')}</td><td>${num(x.late_events)}</td><td>${num(x.penalty_batches)}</td><td><span class="badge red">${num(x.penalty_session_units_total)}</span></td></tr>`),'لا توجد حسميات في هذا الشهر')}</div>`;
  bind();
}
function bind(){const m=$('#monthFilter');if(m&&!m.dataset.bound){m.dataset.bound='1';m.addEventListener('change',render)}const t=$('#teacherFilter');if(t&&!t.dataset.bound){t.dataset.bound='1';t.addEventListener('change',render)}}
async function init(){if(!await ensure())return;$('#logoutBtn')?.addEventListener('click',async()=>{await client().auth.signOut({scope:'local'});location.href='index.html'});$('#refreshBtn')?.addEventListener('click',load);$('#exportBtn')?.addEventListener('click',exportCsv);$('#printBtn')?.addEventListener('click',printView);$('#mobileMenuBtn')?.addEventListener('click',()=>$('#sidebar')?.classList.toggle('open'));await load()}
window.TeacherPayrollFinance={init,renderNow:render,exportCsv,printView,saveExtraSession,saveAdjustment};
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
}());

(function(){
'use strict';
const cfg=()=>window.AMIN_CONFIG||{};
let sb=null,ME=null;
const $=s=>document.querySelector(s);
function client(){ if(sb) return sb; sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:cfg().authStorageKey}}); return sb; }
function esc(v){return String(v==null?'':v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}
function toast(t,m,type=''){ const el=$('#toast'); if(!el) return; el.innerHTML=`<b>${esc(t)}</b><br><span>${esc(m||'')}</span>`; el.className='toast show '+type; clearTimeout(el._to); el._to=setTimeout(()=>el.classList.remove('show'),4000); }

async function ensure(){
  const {data:{session}}=await client().auth.getSession();
  if(!session){ location.href='index.html'; return false; }
  const {data:u}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();
  if(!u){ location.href='index.html'; return false; }
  ME=u;
  $('#profileName').textContent=u.name||u.email;
  $('#profileRole').textContent=u.role||'—';
  return true;
}

function switchHtml(checked, id){
  return `<div class="switch ${checked?'on':''}" data-switch="${id}" onclick="NotificationPrefs.toggle('${id}')"></div>`;
}

async function loadPrefs(){
  try{
    let {data,error}=await client().from('notification_preferences').select('*').eq('user_id',ME.id).maybeSingle();
    if(error && error.code!=='PGRST116') throw error;
    if(!data){
      // Create default
      const {data:ins,error:e2}=await client().from('notification_preferences').insert({user_id:ME.id}).select().single();
      if(e2) throw e2;
      data=ins;
    }
    render(data);
  }catch(e){
    console.error(e);
    $('#prefsRoot').innerHTML=`<div style="padding:20px;background:#fee2e2;color:#991b1b;border-radius:12px">خطأ تحميل التفضيلات: ${esc(e.message)}<br><small>تأكد من تشغيل ملف SQL 170</small></div>`;
  }
}

function render(p){
  const html=`
    <div class="pref-card">
      <h3>🔴🟠🔵⚪ تفعيل حسب الأهمية</h3>
      <p style="font-size:12px;color:#64748b;margin-bottom:12px">اختر أي مستويات أهمية تريد استقبالها. إيقاف الحرجة غير مستحسن.</p>
      <div class="switch-row"><div><b>🔴 حرجة Critical</b><br><small>عقوبة، غياب جماعي، نزاهة — واتساب+SMS+داخلي+صوت</small></div>${switchHtml(p.critical_enabled,'critical_enabled')}</div>
      <div class="switch-row"><div><b>🟠 مهمة High</b><br><small>غياب >20%، قسط متأخر، واجب لم يفتح — واتساب+داخلي</small></div>${switchHtml(p.high_enabled,'high_enabled')}</div>
      <div class="switch-row"><div><b>🔵 متوسطة Medium</b><br><small>واجب جديد، إعلان، تذكير — داخلي فقط</small></div>${switchHtml(p.medium_enabled,'medium_enabled')}</div>
      <div class="switch-row"><div><b>⚪ منخفضة Low</b><br><small>شكر، تهنئة — ملخص يومي</small></div>${switchHtml(p.low_enabled,'low_enabled')}</div>
    </div>

    <div class="pref-card">
      <h3>📱 طرق التوصيل المفضلة</h3>
      <p style="font-size:12px;color:#64748b;margin-bottom:12px">اختر كيف تريد استقبال الإشعارات</p>
      <div class="switch-row"><div><b>📱 داخل الموقع</b><br><small>إشعارات في portal + notifications.html</small></div>${switchHtml(p.in_app_enabled,'in_app_enabled')}</div>
      <div class="switch-row"><div><b>💬 واتساب</b><br><small>للحرجة والمهمة فقط</small></div>${switchHtml(p.whatsapp_enabled,'whatsapp_enabled')}</div>
      <div class="switch-row"><div><b>📩 SMS</b><br><small>للحرجة فقط — يحتاج رصيد</small></div>${switchHtml(p.sms_enabled,'sms_enabled')}</div>
      <div class="switch-row"><div><b>✉️ بريد إلكتروني</b><br><small>للتقارير اليومية</small></div>${switchHtml(p.email_enabled,'email_enabled')}</div>
    </div>

    <div class="pref-card">
      <h3>🌙 أوقات عدم الإزعاج</h3>
      <p style="font-size:12px;color:#64748b;margin-bottom:12px">لن تصلك إشعارات واتساب/SMS خلال هذه الأوقات، فقط داخل الموقع</p>
      <div class="switch-row"><div><b>تفعيل عدم الإزعاج</b></div>${switchHtml(p.quiet_hours_enabled,'quiet_hours_enabled')}</div>
      <div class="switch-row"><div><b>من</b> <input type="time" id="quietStart" class="time-input" value="${p.quiet_hours_start||'22:00'}"></div><div><b>إلى</b> <input type="time" id="quietEnd" class="time-input" value="${p.quiet_hours_end||'07:00'}"></div></div>
      <small style="color:#64748b">مثال: من 22:00 إلى 07:00 لن يصلك واتساب، فقط إشعارات داخل الموقع تظهر صباحاً</small>
    </div>

    <div class="pref-card">
      <h3>📋 تجميع المنخفضة</h3>
      <p style="font-size:12px;color:#64748b;margin-bottom:12px">رسائل الشكر والتهنئة المنخفضة الأهمية يمكن تجميعها في ملخص يومي</p>
      <div class="switch-row"><div><b>تجميع المنخفضة في ملخص يومي</b><br><small>بدل إشعار لكل شكر، يصلك ملخص واحد</small></div>${switchHtml(p.digest_low_enabled,'digest_low_enabled')}</div>
      <div class="switch-row"><div><b>وقت الملخص اليومي</b></div><div><input type="time" id="digestTime" class="time-input" value="${p.digest_time||'08:00'}"><small style="margin-right:8px">صباحاً</small></div></div>
    </div>
  `;
  $('#prefsRoot').innerHTML=html;
  // Store prefs in memory for toggle
  window._currentPrefs=p;
}

function toggle(key){
  const p=window._currentPrefs;
  if(!p) return;
  p[key]=!p[key];
  render(p);
}

async function save(){
  const p=window._currentPrefs;
  if(!p) return;
  const btn=$('#saveBtn');
  btn.disabled=true; btn.textContent='جاري الحفظ...';
  try{
    const quietStart=$('#quietStart')?.value||p.quiet_hours_start;
    const quietEnd=$('#quietEnd')?.value||p.quiet_hours_end;
    const digestTime=$('#digestTime')?.value||p.digest_time;
    const payload={
      critical_enabled: !!p.critical_enabled,
      high_enabled: !!p.high_enabled,
      medium_enabled: !!p.medium_enabled,
      low_enabled: !!p.low_enabled,
      whatsapp_enabled: !!p.whatsapp_enabled,
      sms_enabled: !!p.sms_enabled,
      email_enabled: !!p.email_enabled,
      in_app_enabled: !!p.in_app_enabled,
      quiet_hours_enabled: !!p.quiet_hours_enabled,
      quiet_hours_start: quietStart,
      quiet_hours_end: quietEnd,
      digest_low_enabled: !!p.digest_low_enabled,
      digest_time: digestTime,
      updated_at: new Date().toISOString()
    };
    const {error}=await client().from('notification_preferences').update(payload).eq('user_id',ME.id);
    if(error) throw error;
    toast('تم الحفظ','تم حفظ تفضيلاتك بنجاح','green');
  }catch(e){
    toast('خطأ', e.message,'red');
  }finally{
    btn.disabled=false; btn.textContent='💾 حفظ التفضيلات';
  }
}

async function init(){
  if(!await ensure()) return;
  $('#logoutBtn')?.addEventListener('click', async()=>{ await client().auth.signOut(); location.href='index.html'; });
  $('#mobileMenuBtn')?.addEventListener('click', ()=>$('#sidebar').classList.toggle('open'));
  $('#saveBtn')?.addEventListener('click', save);
  await loadPrefs();
}

window.NotificationPrefs={init,toggle,save};
if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',init); else init();
})();

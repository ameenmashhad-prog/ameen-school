(function(){
'use strict';
const cfg=()=>window.AMIN_CONFIG||{};
let sb=null,ME=null;
const $=s=>document.querySelector(s);
function esc(v){return String(v==null?'':v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}
function client(){ if(sb) return sb; sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:cfg().authStorageKey}}); return sb; }
function toast(t,m,type=''){ const el=$('#toast'); if(!el) return; el.innerHTML=`<b>${esc(t)}</b><br><span class=mute>${esc(m||'')}</span>`; el.className='toast show '+type; clearTimeout(el._to); el._to=setTimeout(()=>el.classList.remove('show'),4000); }

async function ensure(){
  const {data:{session}} = await client().auth.getSession();
  if(!session){ location.href='index.html'; return false; }
  const {data:u} = await client().from('users').select('*').eq('id',session.user.id).maybeSingle();
  if(!u){ location.href='index.html'; return false; }
  ME=u;
  $('#profileName').textContent=u.name||u.email||'مستخدم';
  $('#profileRole').textContent=u.role||'—';
  const ok=u.is_super_admin||['admin','hr','academic','academic_admin'].includes(u.role);
  if(!ok){ document.body.innerHTML='<main style="padding:40px;text-align:center"><h1>غير مصرح</h1><p>هذه الصفحة للإدارة فقط</p></main>'; return false; }
  return true;
}

async function loadTeachers(){
  const {data} = await client().from('users').select('id,name,email,phone,role').in('role',['teacher','academic','academic_admin']).order('name').limit(200);
  const sel=$('#teacherSelect');
  sel.innerHTML='<option value="">اختر المعلم...</option>' + (data||[]).map(u=>`<option value="${u.id}" data-phone="${esc(u.phone||'')}" data-name="${esc(u.name)}">${esc(u.name)} - ${esc(u.role)} ${u.phone?('('+u.phone+')'):''}</option>`).join('');
}

async function loadMessages(){
  const filter=$('#filterType')?.value||'';
  let query=client().from('teacher_admin_messages').select('*, teacher:teacher_id(name,email), sender:created_by(name)').order('created_at',{ascending:false}).limit(100);
  if(filter) query=query.eq('message_type',filter);
  const {data,error}=await query;
  if(error){ $('#messagesList').innerHTML=`<div style="padding:16px;background:#fee2e2;color:#991b1b;border-radius:12px">خطأ: ${esc(error.message)}</div>`; return; }
  const stats={total:data.length,penalty:data.filter(x=>x.message_type==='penalty').length,thank_you:data.filter(x=>x.message_type==='thank_you').length,warning:data.filter(x=>x.message_type==='warning').length};
  $('#statsRoot').innerHTML=`
    <div style="background:#fee2e2;padding:12px;border-radius:12px;text-align:center"><small>إجمالي</small><br><b>${stats.total}</b></div>
    <div style="background:#fee2e2;padding:12px;border-radius:12px;text-align:center"><small>عقوبات</small><br><b>${stats.penalty}</b></div>
    <div style="background:#dcfce7;padding:12px;border-radius:12px;text-align:center"><small>شكر</small><br><b>${stats.thank_you}</b></div>
    <div style="background:#fef3c7;padding:12px;border-radius:12px;text-align:center"><small>إنذارات</small><br><b>${stats.warning}</b></div>
  `;
  if(!data.length){ $('#messagesList').innerHTML='<div style="text-align:center;padding:30px;color:#64748b">لا توجد رسائل بعد</div>'; return; }
  let html='<table style="width:100%;border-collapse:collapse;font-size:13px"><thead><tr style="background:#f1f5f9"><th style="padding:8px;border:1px solid #e2e8f0">المعلم</th><th style="padding:8px;border:1px solid #e2e8f0">النوع</th><th style="padding:8px;border:1px solid #e2e8f0">السبب</th><th style="padding:8px;border:1px solid #e2e8f0">الطرق</th><th style="padding:8px;border:1px solid #e2e8f0">التاريخ</th><th style="padding:8px;border:1px solid #e2e8f0">إجراء</th></tr></thead><tbody>';
  data.forEach(m=>{
    const typeLabel={penalty:'🚨 عقوبة',warning:'⚠️ إنذار',thank_you:'🙏 شكر',notice:'📢 تنبيه'}[m.message_type]||m.message_type;
    const methods=(m.delivery_method||[]).map(x=>x==='whatsapp'?'💬 واتساب':x==='sms'?'📩 SMS':'📱 موقع').join('، ');
    html+=`<tr>
      <td style="padding:8px;border:1px solid #e2e8f0"><b>${esc(m.teacher?.name||'—')}</b></td>
      <td style="padding:8px;border:1px solid #e2e8f0">${typeLabel}</td>
      <td style="padding:8px;border:1px solid #e2e8f0">${esc(m.reason||m.metadata?.body||'—').slice(0,80)}</td>
      <td style="padding:8px;border:1px solid #e2e8f0">${methods}</td>
      <td style="padding:8px;border:1px solid #e2e8f0">${new Date(m.created_at).toLocaleDateString('ar-IQ')}</td>
      <td style="padding:8px;border:1px solid #e2e8f0"><button class="btn small" onclick="TeacherMessages.resendWhatsapp('${m.id}')">إعادة واتساب</button></td>
    </tr>`;
  });
  html+='</tbody></table>';
  $('#messagesList').innerHTML=html;
}

function getDeliveryMethods(){
  const m=[];
  if($('#methodInApp')?.checked) m.push('in_app');
  if($('#methodWhatsapp')?.checked) m.push('whatsapp');
  if($('#methodSms')?.checked) m.push('sms');
  return m;
}

function buildWhatsappLink(phone, message){
  if(!phone) return null;
  let clean=String(phone).replace(/[^0-9+]/g,'');
  if(clean.startsWith('0')) clean='964'+clean.slice(1);
  if(!clean.startsWith('+') && !clean.startsWith('964')) clean='+'+clean;
  clean=clean.replace(/\+/g,'');
  return `https://wa.me/${clean}?text=${encodeURIComponent(message)}`;
}

async function sendMessage(){
  const teacherId=$('#teacherSelect')?.value;
  const teacherOption=$('#teacherSelect')?.selectedOptions[0];
  const teacherName=teacherOption?.dataset.name||'المعلم';
  const teacherPhone=teacherOption?.dataset.phone||'';
  const type=$('#messageType')?.value||'notice';
  const delayDays=parseInt($('#delayDays')?.value||'0')||0;
  const reason=$('#messageReason')?.value.trim();
  const body=$('#messageBody')?.value.trim();
  const methods=getDeliveryMethods();

  if(!teacherId){ toast('تنبيه','اختر المعلم أولاً','red'); return; }
  if(!reason){ toast('تنبيه','اكتب سبب الرسالة','red'); return; }
  if(!body){ toast('تنبيه','اكتب نص الرسالة','red'); return; }
  if(!methods.length){ toast('تنبيه','اختر طريقة إرسال واحدة على الأقل','red'); return; }

  const btn=$('#sendBtn');
  btn.disabled=true; btn.textContent='جاري الإرسال...';

  try{
    // 1) Save to DB
    const {data,error}=await client().from('teacher_admin_messages').insert({
      teacher_id: teacherId,
      message_type: type,
      reason: reason,
      delay_days: delayDays,
      delivery_method: methods,
      whatsapp_sent: methods.includes('whatsapp'),
      sms_sent: methods.includes('sms'),
      in_app_sent: methods.includes('in_app'),
      created_by: ME.id,
      metadata: { body: body, teacher_name: teacherName }
    }).select().single();
    if(error) throw error;

    // 2) If WhatsApp selected, open WhatsApp link
    if(methods.includes('whatsapp') && teacherPhone){
      const waMsg = `السلام عليكم أستاذ ${teacherName} 🌟\n\n${type==='penalty'?'🚨 عقوبة إدارية':type==='thank_you'?'🙏 رسالة شكر وتقدير':type==='warning'?'⚠️ إنذار إداري':'📢 تنبيه إداري'}\n\nالسبب: ${reason}\n\n${body}\n\n— إدارة مجمع أمين الرضا`;
      const link=buildWhatsappLink(teacherPhone, waMsg);
      if(link){
        $('#previewBox').style.display='block';
        $('#previewBox').innerHTML=`<b>رابط واتساب جاهز:</b><br><a href="${link}" target="_blank" style="word-break:break-all;color:#0B6E4F">${esc(link)}</a><br><br><button onclick="window.open('${link}','_blank')" style="padding:10px 16px;background:#25D366;color:#fff;border:none;border-radius:8px;cursor:pointer">فتح واتساب الآن</button>`;
        window.open(link,'_blank');
      }
    }

    // 3) If in_app, create notification for teacher
    if(methods.includes('in_app')){
      await client().from('school_notifications').insert({
        recipient_user_id: teacherId,
        title: type==='thank_you' ? 'رسالة شكر وتقدير' : type==='penalty' ? 'عقوبة إدارية - تأخر مستمر' : 'تنبيه إداري',
        message: `${reason}\n\n${body}`,
        type: type,
        created_by: ME.id
      });
    }

    toast('تم الإرسال','تم حفظ الرسالة وإرسالها بنجاح','green');
    $('#messageReason').value=''; $('#messageBody').value=''; $('#delayDays').value='';
    await loadMessages();
  }catch(e){
    console.error(e);
    toast('خطأ', e.message||String(e),'red');
  }finally{
    btn.disabled=false; btn.textContent='إرسال الرسالة 🚀';
  }
}

async function resendWhatsapp(id){
  const {data} = await client().from('teacher_admin_messages').select('*, teacher:teacher_id(name,phone)').eq('id',id).maybeSingle();
  if(!data){ toast('خطأ','الرسالة غير موجودة','red'); return; }
  const phone=data.teacher?.phone;
  if(!phone){ toast('تنبيه','المعلم ليس له هاتف','red'); return; }
  const msg=`إعادة: ${data.reason}\n\n${data.metadata?.body||''}`;
  const link=buildWhatsappLink(phone, msg);
  if(link) window.open(link,'_blank');
}

async function init(){
  if(!await ensure()) return;
  $('#logoutBtn')?.addEventListener('click', async()=>{ await client().auth.signOut(); location.href='index.html'; });
  $('#refreshBtn')?.addEventListener('click', loadMessages);
  $('#sendBtn')?.addEventListener('click', sendMessage);
  $('#filterType')?.addEventListener('change', loadMessages);
  await loadTeachers();
  await loadMessages();
  // Live preview for message
  ['#messageReason','#messageBody','#teacherSelect','#messageType'].forEach(sel=>{
    $(sel)?.addEventListener('input', ()=>{
      const reason=$('#messageReason')?.value||'';
      const body=$('#messageBody')?.value||'';
      if(reason||body){
        $('#previewBox').style.display='block';
        $('#previewBox').innerHTML=`<small>معاينة:</small><br><b>${esc(reason)}</b><br><small>${esc(body)}</small>`;
      }
    });
  });
}

window.TeacherMessages={init,loadMessages,sendMessage,resendWhatsapp};
if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',init); else init();
})();

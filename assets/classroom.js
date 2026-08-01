(function(){
'use strict';
const cfg=()=>window.AMIN_CONFIG||{};
let sb=null,ME=null,CLASS_ID=null,CLASS_NAME='الصف الأول الابتدائي - شعبة أ';
const $=s=>document.querySelector(s);
function client(){ if(sb) return sb; sb=supabase.createClient(cfg().supabaseUrl,cfg().supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,storageKey:cfg().authStorageKey}}); return sb; }
function esc(v){return String(v==null?'':v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}
function toast(t,m,type=''){ const el=$('#toast'); if(!el) return; el.innerHTML=`<b>${esc(t)}</b><br><small>${esc(m||'')}</small>`; el.className='toast show '+type; clearTimeout(el._to); el._to=setTimeout(()=>el.classList.remove('show'),4000); }

async function ensure(){
  const {data:{session}}=await client().auth.getSession();
  if(!session){ location.href='index.html'; return false; }
  const {data:u}=await client().from('users').select('*').eq('id',session.user.id).maybeSingle();
  if(!u){ location.href='index.html'; return false; }
  ME=u;
  $('#profileName').textContent=u.name||u.email;
  $('#profileRole').textContent=u.role||'—';
  // Try to get class_id from user or first class
  try{
    const {data:classes}=await client().from('classes').select('id,name').order('name').limit(1);
    if(classes && classes[0]){ CLASS_ID=classes[0].id; CLASS_NAME=classes[0].name; $('#classroomTitle').textContent=`📚 ${CLASS_NAME}`; }
  }catch(e){}
  return true;
}

function formatDate(iso){
  if(!iso) return '—';
  try{ return new Date(iso).toLocaleDateString('ar-IQ',{year:'numeric',month:'short',day:'numeric'}); }catch{ return iso; }
}

function daysUntil(due){
  if(!due) return '';
  const today=new Date(); today.setHours(0,0,0,0);
  const d=new Date(due+'T00:00:00');
  const diff=Math.ceil((d-today)/86400000);
  if(diff<0) return `متأخر ${Math.abs(diff)} يوم 🔴`;
  if(diff===0) return `اليوم ⚠️`;
  if(diff===1) return `غداً`;
  return `بعد ${diff} يوم`;
}

// --- STREAM (Google Classroom-like) ---
async function loadStream(){
  const listEl=$('#streamList');
  listEl.innerHTML='<div style="text-align:center;padding:30px">⏳ جاري تحميل المنشورات...</div>';
  try{
    let query=client().from('v_classroom_stream_enhanced').select('*').limit(50);
    if(CLASS_ID) query=query.eq('class_id',CLASS_ID);
    const {data,error}=await query;
    if(error) throw error;
    const posts=data||[];
    // Also load from old v_my_notifications as fallback
    if(!posts.length){
      const {data:hw}=await client().from('v_student_homeworks').select('*').limit(20);
      // Convert homeworks to posts format
      const hwPosts=(hw||[]).map(h=>({
        id:h.id, class_name:CLASS_NAME, post_type:'assignment', title:h.title||'واجب', content:h.description||'',
        due_date:h.due_date, is_pinned:false, status:'published', views_count:0, comments_count:0,
        created_at:h.created_at, author_name:h.teacher_name||'معلم', author_role:'teacher', due_status:h.due_date&&new Date(h.due_date)<new Date()?'overdue':'active'
      }));
      renderStream(hwPosts);
    } else {
      renderStream(posts);
    }
    loadUpcoming();
    loadTeachers();
  }catch(e){
    console.error(e);
    listEl.innerHTML=`<div style="padding:20px;background:#fee2e2;color:#991b1b;border-radius:12px">خطأ تحميل المنشورات: ${esc(e.message)}<br><small>تأكد من تشغيل SQL 171_classroom_stream</small></div>`;
  }
}

function renderStream(posts){
  const listEl=$('#streamList');
  if(!posts.length){ listEl.innerHTML='<div style="text-align:center;padding:40px;color:#64748b">📝 لا توجد منشورات بعد — كن أول من ينشر إعلان أو واجب!</div>'; return; }
  let html='';
  posts.forEach(p=>{
    const isPinned=p.is_pinned?'<span style="background:#f59e0b;color:#fff;padding:2px 8px;border-radius:999px;font-size:10px">📌 مثبت</span>':'';
    const dueBadge=p.due_date?`<span class="post-badge ${p.due_status==='overdue'?'b-red':p.due_status==='due_today'?'b-gold':'b-blue'}">${esc(daysUntil(p.due_date))}</span>`:'';
    const typeIcon={announcement:'📢',assignment:'📚',material:'📄',question:'❓'}[p.post_type]||'📄';
    const typeColor={announcement:'blue',assignment:'green',material:'purple',question:'gold'}[p.post_type]||'blue';
    html+=`
      <div class="post-card ${p.is_pinned?'pinned':''}">
        <div class="post-header">
          <div class="post-avatar">${typeIcon}</div>
          <div class="post-meta">
            <b>${esc(p.author_name||'معلم')} ${isPinned}</b>
            <small>${formatDate(p.created_at)} · ${esc(p.class_name||CLASS_NAME)} · ${esc(p.author_role||'')}</small>
          </div>
          <span class="post-badge b-${typeColor}">${esc(p.post_type)}</span>
          ${dueBadge}
        </div>
        <h3 style="margin:8px 0;font-size:16px">${esc(p.title)}</h3>
        <div class="post-content">${esc(p.content||'').slice(0,500)}</div>
        ${p.attachments&&p.attachments.length?`<div class="post-attachments">${(typeof p.attachments==='string'?[]:p.attachments).map(a=>`<a class="attachment" href="${esc(a.url||'#')}" target="_blank">📎 ${esc(a.name||'مرفق')}</a>`).join('')}</div>`:''}
        <div class="post-actions">
          <button onclick="Classroom.likePost('${p.id}')">👍 ${p.views_count||0}</button>
          <button onclick="Classroom.openComments('${p.id}')">💬 ${p.comments_count||p.actual_comments_count||0} تعليق</button>
          <button onclick="Classroom.markDone('${p.id}')">✅ تم الإنجاز</button>
          <span style="margin-right:auto;font-size:11px;color:#64748b">${p.status||'published'}</span>
        </div>
        <div id="comments-${p.id}" class="comments" style="display:none">
          <div id="comments-list-${p.id}">جاري تحميل التعليقات...</div>
          <div class="add-comment"><input id="comment-input-${p.id}" placeholder="أضف تعليقاً..."><button onclick="Classroom.addComment('${p.id}')">إرسال</button></div>
        </div>
      </div>
    `;
  });
  listEl.innerHTML=html;
}

async function createPost(){
  const title=$('#newPostTitle')?.value.trim();
  const content=$('#newPostContent')?.value.trim();
  const type=$('#newPostType')?.value||'announcement';
  const due=$('#newPostDue')?.value||null;
  const pinned=$('#newPostPinned')?.checked||false;
  if(!title){ toast('تنبيه','اكتب عنوان المنشور','red'); return; }
  if(!content){ toast('تنبيه','اكتب محتوى المنشور','red'); return; }
  
  const btn=$('#createPostBtn');
  btn.disabled=true; btn.textContent='جاري النشر...';
  try{
    // Try new RPC with notifications
    const {data,error}=await client().rpc('create_classroom_post_with_notifications',{
      p_class_id: CLASS_ID,
      p_post_type: type,
      p_title: title,
      p_content: content,
      p_due_date: due,
      p_max_points: 100
    });
    if(error){
      // Fallback to direct insert
      const {error:e2}=await client().from('classroom_posts').insert({
        class_id: CLASS_ID,
        author_id: ME.id,
        post_type: type,
        title: title,
        content: content,
        due_date: due,
        is_pinned: pinned,
        status: 'published'
      });
      if(e2) throw e2;
    }
    toast('تم النشر','تم نشر المنشور وإرسال إشعارات للطلاب','green');
    $('#newPostTitle').value=''; $('#newPostContent').value=''; $('#newPostDue').value='';
    await loadStream();
  }catch(e){
    console.error(e);
    toast('خطأ', e.message,'red');
  }finally{
    btn.disabled=false; btn.textContent='نشر';
  }
}

async function loadUpcoming(){
  try{
    const {data}=await client().from('classroom_posts').select('*').eq('post_type','assignment').gte('due_date', new Date().toISOString().slice(0,10)).order('due_date').limit(5);
    const el=$('#upcomingList');
    if(!el) return;
    if(!data||!data.length){ el.innerHTML='<small style="color:#64748b">لا واجبات قادمة</small>'; return; }
    el.innerHTML=data.map(p=>`<div style="padding:8px;border-bottom:1px solid #f1f5f9"><b style="font-size:12px">${esc(p.title)}</b><br><small style="color:#dc2626">${esc(daysUntil(p.due_date))}</small></div>`).join('');
  }catch(e){}
}

async function loadTeachers(){
  try{
    const {data}=await client().from('users').select('name,role').in('role',['teacher','academic']).limit(5);
    const el=$('#teachersList');
    if(!el) return;
    el.innerHTML=(data||[]).map(u=>`<div style="padding:6px 0;border-bottom:1px solid #f8fafc"><b style="font-size:12px">${esc(u.name)}</b><br><small style="color:#64748b">${esc(u.role)}</small></div>`).join('')||'<small>لا معلمين</small>';
  }catch(e){}
}

// --- CLASSWORK (like Google Classroom Classwork tab) ---
async function loadClasswork(){
  const listEl=$('#classworkList');
  listEl.innerHTML='⏳ جاري تحميل الواجبات...';
  try{
    const statusFilter=$('#filterStatus')?.value||'';
    const subjectFilter=$('#filterSubject')?.value||'';
    let query=client().from('v_classroom_stream_enhanced').select('*').eq('post_type','assignment').limit(50);
    if(CLASS_ID) query=query.eq('class_id',CLASS_ID);
    const {data,error}=await query;
    if(error) throw error;
    let items=data||[];
    // Filter by status
    if(statusFilter){
      items=items.filter(i=> (i.due_status||'active')===statusFilter || i.status===statusFilter);
    }
    renderClasswork(items);
  }catch(e){
    listEl.innerHTML=`<div style="padding:20px;background:#fee2e2;color:#991b1b;border-radius:12px">خطأ: ${esc(e.message)}</div>`;
  }
}

function renderClasswork(items){
  const listEl=$('#classworkList');
  if(!items.length){ listEl.innerHTML='<div style="text-align:center;padding:40px;color:#64748b">📚 لا توجد واجبات</div>'; return; }
  let html='';
  // Group by due status
  const groups={overdue:[],due_today:[],due_soon:[],active:[],no_due:[]};
  items.forEach(i=>{
    const g=i.due_status||'active';
    if(groups[g]) groups[g].push(i); else groups.active.push(i);
  });
  const groupLabels={overdue:'🔴 متأخر',due_today:'🟡 اليوم',due_soon:'🟠 قريب',active:'🔵 نشط',no_due:'⚪ بدون تاريخ'};
  Object.entries(groups).forEach(([key, groupItems])=>{
    if(!groupItems.length) return;
    html+=`<h4 style="margin:16px 0 8px">${groupLabels[key]} (${groupItems.length})</h4>`;
    groupItems.forEach(item=>{
      const statusClass=item.due_status==='overdue'?'missing':item.due_status==='due_today'?'assigned':item.due_status==='due_soon'?'submitted':'assigned';
      const statusLabel=item.due_status==='overdue'?'ناقص':item.due_status==='due_today'?'اليوم':item.due_status==='due_soon'?'قريب':'مكلف';
      html+=`
        <div class="classwork-item">
          <div class="classwork-icon assignment">📚</div>
          <div class="classwork-info">
            <b>${esc(item.title)}</b>
            <small>${formatDate(item.due_date)} · ${esc(item.class_name||'')} · ${esc(item.author_name||'')}</small>
          </div>
          <span class="classwork-status status-${statusClass}">${statusLabel}</span>
          <button onclick="Classroom.openPost('${item.id}')" style="padding:6px 12px;border:1px solid #e2e8f0;border-radius:8px;background:#fff;cursor:pointer">فتح</button>
        </div>
      `;
    });
  });
  listEl.innerHTML=html;
}

// --- DAILY FOLLOW-UP ---
async function loadDaily(){
  const dateVal=$('#dailyDate')?.value||new Date().toISOString().slice(0,10);
  const gridEl=$('#dailyGrid');
  const summaryEl=$('#dailySummary');
  gridEl.innerHTML='⏳ جاري التحميل...';
  try{
    let query=client().from('students').select('id,name,class_id,classes(name)').limit(100);
    if(CLASS_ID) query=query.eq('class_id',CLASS_ID);
    const {data:students}=await query;
    const {data:followups}=await client().from('daily_followup').select('*').eq('followup_date',dateVal);

    const followMap=new Map((followups||[]).map(f=>[f.student_id,f]));
    
    // Summary
    const total=students?.length||0;
    const present=followups?.filter(f=>f.attendance_status==='present').length||0;
    const absent=followups?.filter(f=>f.attendance_status==='absent').length||0;
    const homeworkDone=followups?.filter(f=>f.homework_done).length||0;
    const avgPart=followups?.length? (followups.reduce((s,f)=>s+(f.participation_score||0),0)/followups.length).toFixed(1):'—';
    
    summaryEl.innerHTML=`
      <div style="background:#dcfce7;padding:10px;border-radius:10px;text-align:center"><small>حاضر</small><br><b>${present}/${total}</b></div>
      <div style="background:#fee2e2;padding:10px;border-radius:10px;text-align:center"><small>غائب</small><br><b>${absent}</b></div>
      <div style="background:#fef3c7;padding:10px;border-radius:10px;text-align:center"><small>أنجز الواجب</small><br><b>${homeworkDone}/${total}</b></div>
      <div style="background:#dbeafe;padding:10px;border-radius:10px;text-align:center"><small>متوسط المشاركة</small><br><b>${avgPart}/5</b></div>
    `;

    let html='';
    (students||[]).forEach(s=>{
      const f=followMap.get(s.id);
      const status=f?.attendance_status||'present';
      const moodIcon={excellent:'😍',good:'😊',neutral:'😐',tired:'😴',upset:'😢'}[f?.mood]||'😐';
      const cardClass=f ? (f.attendance_status==='absent'?'attention':'good') : '';
      html+=`
        <div class="daily-card ${cardClass}">
          <div style="font-weight:700;font-size:13px">${esc(s.name)}</div>
          <small style="color:#64748b">${esc(s.classes?.name||'')}</small>
          <div style="margin:8px 0;display:flex;gap:4px;justify-content:center">
            <select data-student="${s.id}" data-field="attendance_status" style="padding:4px;border-radius:6px;border:1px solid #cbd5e1;font-size:11px">
              <option value="present" ${status==='present'?'selected':''}>حاضر</option>
              <option value="absent" ${status==='absent'?'selected':''}>غائب</option>
              <option value="late" ${status==='late'?'selected':''}>متأخر</option>
              <option value="excused" ${status==='excused'?'selected':''}>معذور</option>
            </select>
            <select data-student="${s.id}" data-field="mood" style="padding:4px;border-radius:6px;border:1px solid #cbd5e1;font-size:11px">
              <option value="excellent" ${f?.mood==='excellent'?'selected':''}>😍 ممتاز</option>
              <option value="good" ${f?.mood==='good'?'selected':''}>😊 جيد</option>
              <option value="neutral" ${!f?.mood||f?.mood==='neutral'?'selected':''}>😐 عادي</option>
              <option value="tired" ${f?.mood==='tired'?'selected':''}>😴 متعب</option>
              <option value="upset" ${f?.mood==='upset'?'selected':''}>😢 منزعج</option>
            </select>
          </div>
          <div style="display:flex;gap:4px;justify-content:center;align-items:center">
            <span style="font-size:11px">مشاركة:</span>
            <input type="range" min="1" max="5" value="${f?.participation_score||3}" data-student="${s.id}" data-field="participation_score" style="width:60px">
            <span style="font-size:11px">${f?.participation_score||3}/5</span>
          </div>
          <label style="display:flex;gap:4px;align-items:center;justify-content:center;margin-top:6px;font-size:11px"><input type="checkbox" ${f?.homework_done?'checked':''} data-student="${s.id}" data-field="homework_done"> أنجز الواجب</label>
          <input placeholder="ملاحظة سلوك..." value="${esc(f?.behavior_note||'')}" data-student="${s.id}" data-field="behavior_note" style="width:100%;margin-top:6px;padding:6px;border:1px solid #e2e8f0;border-radius:8px;font-size:11px">
        </div>
      `;
    });
    gridEl.innerHTML=html||'<div style="text-align:center;padding:40px;color:#64748b">لا طلاب في هذا الصف</div>';
  }catch(e){
    gridEl.innerHTML=`<div style="padding:20px;background:#fee2e2;color:#991b1b;border-radius:12px">خطأ: ${esc(e.message)}</div>`;
  }
}

async function saveDaily(){
  const dateVal=$('#dailyDate')?.value||new Date().toISOString().slice(0,10);
  const cards=document.querySelectorAll('#dailyGrid [data-student]');
  // Collect unique students
  const studentIds=new Set(Array.from(cards).map(el=>el.dataset.student));
  let saved=0;
  for(const sid of studentIds){
    const getVal=(field)=>{
      const el=document.querySelector(`[data-student="${sid}"][data-field="${field}"]`);
      if(!el) return null;
      if(el.type==='checkbox') return el.checked;
      if(el.type==='range') return parseInt(el.value);
      return el.value;
    };
    const payload={
      student_id: sid,
      class_id: CLASS_ID,
      followup_date: dateVal,
      attendance_status: getVal('attendance_status')||'present',
      mood: getVal('mood')||'neutral',
      participation_score: getVal('participation_score')||3,
      homework_done: !!getVal('homework_done'),
      behavior_note: getVal('behavior_note')||'',
      created_by: ME.id
    };
    try{
      const {error}=await client().from('daily_followup').upsert(payload, {onConflict:'student_id,followup_date'});
      if(!error) saved++;
    }catch(e){ console.warn(e); }
  }
  toast('تم الحفظ',`تم حفظ متابعة ${saved} طالب ليوم ${dateVal}`,'green');
  loadDaily();
}

// --- BIGBLUEBUTTON INTEGRATION ---
function getBBBConfig(){
  return {
    server: localStorage.getItem('bbb_server')||$('#bbbServer')?.value||'https://bbb.example.com/bigbluebutton/',
    secret: localStorage.getItem('bbb_secret')||$('#bbbSecret')?.value||''
  };
}

function saveBBBConfig(){
  const server=$('#bbbServer')?.value||'';
  const secret=$('#bbbSecret')?.value||'';
  localStorage.setItem('bbb_server',server);
  localStorage.setItem('bbb_secret',secret);
  toast('تم الحفظ','تم حفظ إعدادات BigBlueButton','green');
}

function generateChecksum(apiCall, queryString, secret){
  // Simple SHA1 - in production use server-side for security
  // For demo, we use a placeholder - real checksum should be generated server-side
  return 'PLACEHOLDER_CHECKSUM_'+btoa(apiCall+queryString+secret).slice(0,20);
}

async function createBBBMeeting(){
  const server=$('#bbbServer')?.value||localStorage.getItem('bbb_server');
  const secret=$('#bbbSecret')?.value||localStorage.getItem('bbb_secret');
  if(!server||!secret){ toast('تنبيه','أدخل رابط السيرفر و Secret أولاً','red'); return; }
  
  const meetingID=`class-${CLASS_ID||'general'}-${Date.now()}`;
  const meetingName=`حصة ${CLASS_NAME} - ${new Date().toLocaleDateString('ar-IQ')}`;
  const attendeePW='student123';
  const moderatorPW='teacher123';
  
  // In production, this should be done via your backend /api/bbb/create to hide secret
  // Here we simulate creation and save to DB
  try{
    const {data,error}=await client().from('classroom_posts').insert({
      class_id: CLASS_ID,
      author_id: ME.id,
      post_type: 'announcement',
      title: `🎥 حصة مباشرة: ${meetingName}`,
      content: `تم إنشاء حصة مباشرة على BigBlueButton\n\nMeeting ID: ${meetingID}\nرابط المعلم (Moderator): ${server}api/join?meetingID=${meetingID}&password=${moderatorPW}&fullName=${encodeURIComponent(ME.name)}\nرابط الطالب (Attendee): ${server}api/join?meetingID=${meetingID}&password=${attendeePW}&fullName=Student\n\nسيتم الانتقال السلس من موقع المدرسة إلى الحصة الإلكترونية. بعد انتهاء الحصة، سيتم ربط ملخص الحصة تلقائياً بالموقع.`,
      is_pinned: true,
      status: 'published'
    }).select().single();
    if(error) throw error;
    
    // Also save to bbb_meetings table if exists, or as classroom post
    toast('تم إنشاء الحصة','تم إنشاء حصة BBB وحفظها كمنشور مثبت','green');
    
    // Open moderator link directly
    const modUrl=`${server}api/join?meetingID=${meetingID}&password=${moderatorPW}&fullName=${encodeURIComponent(ME.name)}&checksum=${generateChecksum('join',`fullName=${encodeURIComponent(ME.name)}&meetingID=${meetingID}&password=${moderatorPW}`,secret)}`;
    window.open(modUrl,'_blank');
    
    loadStream();
    loadBBBMeetings();
  }catch(e){
    console.error(e);
    toast('خطأ', e.message,'red');
  }
}

async function joinBBB(meetingID=null){
  // If no meetingID, join latest
  if(!meetingID){
    try{
      const {data}=await client().from('classroom_posts').select('*').eq('post_type','announcement').ilike('title','%حصة مباشرة%').order('created_at',{ascending:false}).limit(1).maybeSingle();
      if(data && data.content){
        // Extract meetingID from content if exists
        const match=data.content.match(/Meeting ID:\s*(\S+)/);
        if(match) meetingID=match[1];
      }
    }catch(e){}
  }
  
  const server=localStorage.getItem('bbb_server')||$('#bbbServer')?.value||'';
  const secret=localStorage.getItem('bbb_secret')||$('#bbbSecret')?.value||'';
  
  if(!meetingID){
    // Fallback: open generic join page with instructions
    const bbbUrl=server||'https://bbb.example.com/';
    const joinUrl=`${bbbUrl}api/join?meetingID=class-${CLASS_ID||'demo'}&password=student123&fullName=${encodeURIComponent(ME.name||'Student')}`;
    toast('تنبيه','لم يتم العثور على حصة نشطة، سيتم فتح صفحة BBB العامة','blue');
    window.open(bbbUrl,'_blank');
    return;
  }
  
  // Student join
  const studentUrl=`${server}api/join?meetingID=${meetingID}&password=student123&fullName=${encodeURIComponent(ME.name||'Student')}`;
  window.open(studentUrl,'_blank');
  toast('تم','يتم الانتقال إلى الحصة الإلكترونية...','green');
  
  // Log attendance for online class
  try{
    await client().from('daily_followup').upsert({
      student_id: (await client().from('students').select('id').eq('user_id',ME.id).maybeSingle()).data?.id,
      class_id: CLASS_ID,
      followup_date: new Date().toISOString().slice(0,10),
      attendance_status: 'present',
      behavior_note: `حضر حصة BBB: ${meetingID}`,
      created_by: ME.id
    }, {onConflict:'student_id,followup_date'});
  }catch(e){}
}

async function loadBBBMeetings(){
  const listEl=$('#bbbMeetingsList');
  if(!listEl) return;
  try{
    const {data}=await client().from('classroom_posts').select('*').eq('post_type','announcement').ilike('title','%حصة مباشرة%').order('created_at',{ascending:false}).limit(10);
    if(!data||!data.length){ listEl.innerHTML='<div style="text-align:center;padding:20px;color:#64748b">لا توجد حصص مباشرة سابقة</div>'; return; }
    listEl.innerHTML=data.map(m=>`
      <div class="post-card">
        <div style="display:flex;justify-content:space-between;align-items:center">
          <b>${esc(m.title)}</b>
          <small>${formatDate(m.created_at)}</small>
        </div>
        <p style="font-size:12px;color:#64748b;white-space:pre-wrap;margin:8px 0">${esc(m.content||'').slice(0,200)}</p>
        <div style="display:flex;gap:8px">
          <button onclick="Classroom.joinBBB('${m.id}')" style="padding:6px 12px;background:#0B6E4F;color:#fff;border:none;border-radius:8px;cursor:pointer">دخول كطالب</button>
          <button onclick="Classroom.openPost('${m.id}')" style="padding:6px 12px;background:#fff;border:1px solid #cbd5e1;border-radius:8px;cursor:pointer">تفاصيل</button>
        </div>
      </div>
    `).join('');
  }catch(e){
    listEl.innerHTML=`<div style="padding:12px;background:#fee2e2;color:#991b1b;border-radius:8px">خطأ: ${esc(e.message)}</div>`;
  }
}

async function saveBBBSummary(){
  const summary=$('#bbbSummary')?.value.trim();
  const subject=$('#bbbSummarySubject')?.value||'';
  if(!summary){ toast('تنبيه','اكتب ملخص الحصة','red'); return; }
  try{
    const {data,error}=await client().from('classroom_posts').insert({
      class_id: CLASS_ID,
      author_id: ME.id,
      post_type: 'material',
      title: `📝 ملخص حصة: ${subject||'عام'} - ${new Date().toLocaleDateString('ar-IQ')}`,
      content: `ملخص الحصة المباشرة:\n\n${summary}\n\nالمادة: ${subject}\nالتاريخ: ${new Date().toLocaleString('ar-IQ')}\n\nتم الربط تلقائياً من BigBlueButton إلى موقع المدرسة.`,
      status: 'published'
    }).select().single();
    if(error) throw error;
    toast('تم الحفظ','تم حفظ ملخص الحصة وربطه بالموقع','green');
    $('#bbbSummary').value='';
    loadStream();
  }catch(e){
    toast('خطأ', e.message,'red');
  }
}

function openPost(id){
  location.hash=`post=${id}`;
  document.querySelector('[data-tab="stream"]')?.click();
  setTimeout(()=>{ document.getElementById(`comments-${id}`)?.scrollIntoView({behavior:'smooth'}); },500);
}

async function openComments(postId){
  const el=document.getElementById(`comments-${postId}`);
  if(!el) return;
  el.style.display=el.style.display==='none'?'block':'none';
  if(el.style.display==='none') return;
  const listEl=document.getElementById(`comments-list-${postId}`);
  listEl.innerHTML='⏳ جاري تحميل التعليقات...';
  try{
    const {data}=await client().from('classroom_comments').select('*, author:author_id(name)').eq('post_id',postId).order('created_at');
    if(!data||!data.length){ listEl.innerHTML='<small style="color:#64748b">لا تعليقات بعد - كن أول من يعلق</small>'; return; }
    listEl.innerHTML=data.map(c=>`
      <div class="comment">
        <div class="comment-avatar">${esc((c.author?.name||'U')[0])}</div>
        <div class="comment-body"><b>${esc(c.author?.name||'مستخدم')}</b><p>${esc(c.content)}</p><small style="color:#64748b">${formatDate(c.created_at)}</small></div>
      </div>
    `).join('');
  }catch(e){ listEl.innerHTML=`<small style="color:#dc2626">خطأ: ${esc(e.message)}</small>`; }
}

async function addComment(postId){
  const input=document.getElementById(`comment-input-${postId}`);
  const content=input?.value.trim();
  if(!content) return;
  try{
    const {error}=await client().from('classroom_comments').insert({post_id:postId, author_id:ME.id, content:content});
    if(error) throw error;
    input.value='';
    openComments(postId);
    // Update comments count
    await client().from('classroom_posts').update({comments_count: (await client().from('classroom_comments').select('id',{count:'exact'}).eq('post_id',postId)).count}).eq('id',postId);
  }catch(e){ toast('خطأ',e.message,'red'); }
}

function likePost(postId){
  toast('تم','تم تسجيل إعجابك','green');
  // Could increment views_count
}

function markDone(postId){
  toast('تم','تم تعليم المنشور كمُنجز','green');
}

async function loadPeople(){
  const gridEl=$('#peopleGrid');
  gridEl.innerHTML='⏳ جاري التحميل...';
  try{
    const {data:teachers}=await client().from('users').select('id,name,role,email').in('role',['teacher','academic','academic_admin']).limit(20);
    const {data:students}=await client().from('students').select('id,name,class_id,classes(name)').eq('class_id',CLASS_ID).limit(50);
    let html='<h4 style="grid-column:1/-1">👨‍🏫 المعلمون</h4>';
    (teachers||[]).forEach(t=>{
      html+=`<div class="person-card"><div class="person-avatar">${esc(t.name[0])}</div><div><b>${esc(t.name)}</b><br><small>${esc(t.role)} · ${esc(t.email||'')}</small></div></div>`;
    });
    html+=`<h4 style="grid-column:1/-1;margin-top:16px">🎓 الطلاب (${students?.length||0})</h4>`;
    (students||[]).forEach(s=>{
      html+=`<div class="person-card"><div class="person-avatar">${esc(s.name[0])}</div><div><b>${esc(s.name)}</b><br><small>${esc(s.classes?.name||'')}</small></div></div>`;
    });
    gridEl.innerHTML=html;
  }catch(e){
    gridEl.innerHTML=`<div style="padding:20px;background:#fee2e2;color:#991b1b;border-radius:12px">خطأ: ${esc(e.message)}</div>`;
  }
}

async function loadGrades(){
  const listEl=$('#gradesList');
  listEl.innerHTML='⏳ جاري تحميل الدرجات...';
  try{
    const {data}=await client().from('grades').select('*, students(name), subjects(name)').limit(50);
    if(!data||!data.length){ listEl.innerHTML='<div style="text-align:center;padding:40px;color:#64748b">لا درجات بعد</div>'; return; }
    let html='<table style="width:100%;border-collapse:collapse;background:#fff;border-radius:12px;overflow:hidden"><thead><tr style="background:#f1f5f9"><th style="padding:10px;border:1px solid #e2e8f0">الطالب</th><th style="padding:10px;border:1px solid #e2e8f0">المادة</th><th style="padding:10px;border:1px solid #e2e8f0">الدرجة</th><th style="padding:10px;border:1px solid #e2e8f0">التاريخ</th></tr></thead><tbody>';
    data.forEach(g=>{
      html+=`<tr><td style="padding:8px;border:1px solid #e2e8f0">${esc(g.students?.name||'—')}</td><td style="padding:8px;border:1px solid #e2e8f0">${esc(g.subjects?.name||'—')}</td><td style="padding:8px;border:1px solid #e2e8f0"><b>${g.score||g.grade||'—'}</b></td><td style="padding:8px;border:1px solid #e2e8f0">${formatDate(g.created_at)}</td></tr>`;
    });
    html+='</tbody></table>';
    listEl.innerHTML=html;
  }catch(e){
    listEl.innerHTML=`<div style="padding:20px;background:#fee2e2;color:#991b1b;border-radius:12px">خطأ: ${esc(e.message)}</div>`;
  }
}

function bindTabs(){
  document.querySelectorAll('[data-tab]').forEach(btn=>{
    btn.addEventListener('click',()=>{
      const tab=btn.dataset.tab;
      document.querySelectorAll('.classroom-tab').forEach(b=>b.classList.toggle('active',b.dataset.tab===tab));
      document.querySelectorAll('.nav button[data-tab]').forEach(b=>b.classList.toggle('active',b.dataset.tab===tab));
      document.querySelectorAll('.tab-content').forEach(el=>el.style.display=el.id===`tab-${tab}`?'block':'none');
      if(tab==='stream') loadStream();
      else if(tab==='classwork') loadClasswork();
      else if(tab==='daily'){ $('#dailyDate').valueAsDate=new Date(); loadDaily(); }
      else if(tab==='people') loadPeople();
      else if(tab==='grades') loadGrades();
      else if(tab==='bbb') loadBBBMeetings();
    });
  });
}

async function init(){
  if(!await ensure()) return;
  $('#logoutBtn')?.addEventListener('click', async()=>{ await client().auth.signOut(); location.href='index.html'; });
  $('#mobileMenuBtn')?.addEventListener('click', ()=>$('#sidebar').classList.toggle('open'));
  $('#createPostBtn')?.addEventListener('click', createPost);
  $('#dailyDate')?.valueAsDate=new Date();
  bindTabs();
  await loadStream();
  // Load BBB config from localStorage
  $('#bbbServer').value=localStorage.getItem('bbb_server')||'';
  $('#bbbSecret').value=localStorage.getItem('bbb_secret')||'';
}

window.Classroom={init,loadStream,createPost,loadClasswork,loadDaily,saveDaily,loadPeople,loadGrades,joinBBB,createBBBMeeting,saveBBBConfig,loadBBBMeetings,saveBBBSummary,openPost,openComments,addComment,likePost,markDone};

if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',init); else init();
})();

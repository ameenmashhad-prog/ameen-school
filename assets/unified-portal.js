/* Unified Portal — permission-aware grouped gateway
   ملاحظة صيانة:
   - هذا الملف موجود كمسار بديل/تجريبي أو مرجعي.
   - portal.html في الإنتاج لا يحمّله حالياً، بل يعتمد على assets/portal-app.js.
   - لا تفعّله في الإنتاج إلا بعد refactor مقصود واختبار كامل.
*/
(function(){
  'use strict';
  window.AMIN_RUNTIME_INFO = Object.assign({}, window.AMIN_RUNTIME_INFO || {}, {
    unified_portal: 'assets/unified-portal.js',
    unified_portal_mode: 'legacy-or-experimental',
    unified_portal_active: false
  });

  let sb = null;
  let ME = null;
  let PAYLOAD = { permissions: [], notifications: [], unread_notifications: 0 };
  let MODULES = [];
  let HOME = null;
  let ACTIVE_GROUP = 'all';

  const cfg = () => window.AMIN_CONFIG || {};
  const P = () => window.AMIN_PLATFORM || null;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));

  function client(){
    if(sb) return sb;
    sb = supabase.createClient(cfg().supabaseUrl, cfg().supabaseAnonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        storageKey: (cfg().authStorageKey || 'amin-ovcjzsrqqgjsbqswtkro-auth-v2')
      }
    });
    return sb;
  }

  function esc(v){
    if(P()) return P().esc(v);
    return String(v == null ? '' : v).replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
  }
  function text(obj, fallback){
    if(P()) return P().text(obj, fallback);
    if(!obj) return fallback || '';
    return obj.ar || obj.en || fallback || '';
  }
  function iconHtml(item){
    if(P()) return P().iconHtml(item);
    return `<span class="nav-icon-wrap icon-${esc(item.color || 'indigo')}">◇</span>`;
  }
  function toast(t, m, type = ''){
    const el = $('#toast');
    if(!el) return;
    el.innerHTML = `<b>${esc(t)}</b><br><span class="muted">${esc(m || '')}</span>`;
    el.className = 'toast show ' + type;
    clearTimeout(el._t);
    el._t = setTimeout(() => el.classList.remove('show'), 4200);
  }
  function roleLabel(r){
    return ({
      admin:'مدير النظام', finance:'مسؤول مالي', academic:'مسؤول علمي', academic_admin:'إدارة أكاديمية', scientific:'مسؤول علمي',
      discipline:'مسؤول انضباط', counselor:'مرشد نفسي', psychologist:'مرشد نفسي', teacher:'معلم', student:'طالب', parent:'ولي أمر', staff:'إداري'
    }[r] || r || 'مستخدم');
  }
  function fmt(v){
    if(!v) return '—';
    try { return new Date(v).toLocaleString(P()?.lang() === 'fa' ? 'fa-IR' : (P()?.lang() === 'en' ? 'en-US' : 'ar-IQ')); }
    catch { return v; }
  }
  function has(p){
    if(!p) return true;
    const perms = PAYLOAD.permissions || [];
    const reqs = Array.isArray(p) ? p : [p];
    if(reqs.includes('counseling') || reqs.includes('counseling.full')) return reqs.some(x => perms.includes(x));
    if(perms.includes('admin')) return true;
    return reqs.some(x => perms.includes(x));
  }
  function canSee(m){
    if(P()) return P().moduleMatchesPermission(m, has);
    return has(m.perm || m.perms);
  }
  function groups(){
    return P()?.groups || [
      {key:'main', color:'cyan', title:{ar:'الواجهات الرئيسية'}, desc:{ar:'مداخل النظام'}},
      {key:'finance', color:'teal', title:{ar:'المالية'}, desc:{ar:'الرسوم والمدفوعات'}},
      {key:'academic', color:'indigo', title:{ar:'الأكاديمي'}, desc:{ar:'الدرجات والجداول'}},
      {key:'resources', color:'violet', title:{ar:'الموارد'}, desc:{ar:'المرافق والخدمات'}}
    ];
  }
  function moduleCatalog(){
    if(P()) return P().modules;
    return [
      {key:'smartCalendar', group:'main', perm:'calendar', color:'cyan', icon:'calendar', title:{ar:'التقويم الذكي'}, desc:{ar:'تقويم ثلاثي وأجندتي'}, href:'smart-calendar.html?lite=1'},
      {key:'finance', group:'finance', perm:'finance', color:'teal', icon:'wallet', title:{ar:'النظام المالي'}, desc:{ar:'الرسوم والأقساط والمدفوعات'}, href:'finance-pro.html?lite=1'},
      {key:'academic', group:'academic', perm:'academic', color:'indigo', icon:'school', title:{ar:'النظام الأكاديمي'}, desc:{ar:'درجات وتقارير'}, href:'academic-pro.html?lite=1'}
    ];
  }

  async function ensure(){
    const { data: { session } } = await client().auth.getSession();
    if(!session){ location.href = 'index.html'; return false; }
    await loadPayload();
    if(!PAYLOAD.ok){
      toast('تعذر فتح البوابة', PAYLOAD.message || 'خطأ', 'red');
      return false;
    }
    ME = PAYLOAD.profile || {};
    const name = $('#profileName'); if(name) name.textContent = ME.name || ME.email || '...';
    const role = $('#profileRole'); if(role) role.textContent = roleLabel(ME.role);
    const badge = $('#unreadBadge'); if(badge) badge.textContent = PAYLOAD.unread_notifications || 0;
    return true;
  }
  async function loadPayload(){
    try{
      const { data, error } = await client().rpc('get_my_portal_payload');
      if(error) throw error;
      PAYLOAD = data || { ok:false, message:'لا توجد بيانات', permissions:[], notifications:[] };
    }catch(e){
      console.warn(e);
      PAYLOAD = { ok:false, message:e.message || String(e), permissions:[], notifications:[] };
    }
  }

  function visibleGroups(visibleModules){
    const counts = Object.fromEntries(groups().map(g => [g.key, 0]));
    visibleModules.forEach(m => { counts[m.group] = (counts[m.group] || 0) + 1; });
    return groups().filter(g => counts[g.key] > 0).map(g => ({...g, count: counts[g.key]}));
  }
  function moduleSearchMatches(m, q){
    if(!q) return true;
    return [m.key, m.href, text(m.title), text(m.desc), m.title?.ar, m.title?.fa, m.title?.en, m.desc?.ar, m.desc?.fa, m.desc?.en]
      .join(' ').toLowerCase().includes(q.toLowerCase());
  }
  function setActiveGroup(key){
    ACTIVE_GROUP = key || 'all';
    renderModules();
    const target = ACTIVE_GROUP === 'all' ? $('#modulesGrid') : document.getElementById('portal-group-' + ACTIVE_GROUP);
    target?.scrollIntoView({ behavior:'smooth', block:'start' });
  }
  function quickNavHtml(gList, total){
    const allActive = ACTIVE_GROUP === 'all' ? 'active' : '';
    const chips = [`<button class="${allActive}" onclick="UnifiedPortal.openGroup('all')">${iconHtml({color:'gold', icon:'grid'})}<span>كل الواجهات</span><b>${total}</b></button>`];
    gList.forEach(g => {
      const active = ACTIVE_GROUP === g.key ? 'active' : '';
      chips.push(`<button class="${active}" onclick="UnifiedPortal.openGroup('${esc(g.key)}')">${iconHtml(g)}<span>${esc(text(g.title))}</span><b>${g.count}</b></button>`);
    });
    return chips.join('');
  }
  function moduleCard(m){
    const badge = m.badge ? `<span class="module-badge">${esc(m.badge)}</span>` : '';
    return `<article class="module-card platform-card icon-${esc(m.color || 'indigo')}" data-module-key="${esc(m.key)}">
      <div class="module-card-top">
        ${iconHtml(m)}
        ${badge}
      </div>
      <div class="module-copy">
        <h3>${esc(text(m.title, m.key))}</h3>
        <p>${esc(text(m.desc, ''))}</p>
      </div>
      <div class="module-actions">
        <button class="btn blue" ${m.disabled ? 'disabled' : ''} onclick="UnifiedPortal.openModule('${esc(m.key)}')">${m.disabled ? 'قريباً' : 'فتح'}</button>
      </div>
    </article>`;
  }

  async function loadHome(){
    try{
      const {data,error}=await client().rpc('get_my_landing_home');
      if(error) throw error;
      HOME=data&&data.ok!==false?data:null;
    }catch(e){
      console.warn('home dashboard fallback',e);
      HOME=null;
    }
  }
  function portalClock(){
    const d=new Date();
    const el=document.getElementById('portalClock');
    if(el) el.textContent=new Intl.DateTimeFormat('ar-IQ',{timeZone:'Asia/Tehran',hour:'2-digit',minute:'2-digit',second:'2-digit'}).format(d);
  }
  function agendaItems(){
    const list=(HOME?.agenda?.items||[]).slice();
    return list.sort((a,b)=>priorityScore(b)-priorityScore(a)||String(a.date_gregorian||'').localeCompare(String(b.date_gregorian||'')));
  }
  function priorityScore(a){
    const today=new Date().toISOString().slice(0,10); const d=String(a.date_gregorian||'').slice(0,10); let s=0;
    if(a.status==='overdue'||(d&&d<today))s+=100; if(d===today)s+=80; if(a.priority==='urgent')s+=90; if(a.priority==='high')s+=60;
    if(a.agenda_type==='exam')s+=70; if(a.agenda_type==='assignment')s+=45; if(a.agenda_type==='notification')s+=35; return s;
  }
  function kindLabel(t){return ({exam:'اختبار',assignment:'واجب',notification:'إشعار',calendar:'تقويم',custom:'مهمة'}[t]||t||'مهمة')}
  function dueText(v){const d=String(v||'').slice(0,10),t=new Date().toISOString().slice(0,10);if(!d)return'—';if(d<t)return'متأخر';if(d===t)return'اليوم';return d}
  function homeTaskCard(a){return `<article class="home-task-card"><div><b>${esc(a.title)}</b><small>${esc(kindLabel(a.agenda_type))} · ${esc(dueText(a.date_gregorian))}</small></div><span class="badge ${priorityScore(a)>80?'red':a.agenda_type==='exam'?'gold':'blue'}">${priorityScore(a)}</span><button class="btn small" onclick="location.href='${esc(safeUrl(a.action_url||'portal.html'))}'">فتح</button></article>`}
  function safeUrl(u){u=String(u||'portal.html').trim();if(!u||u.startsWith('javascript:')||u.startsWith('data:'))return'portal.html';try{const x=new URL(u,location.origin);if(x.origin!==location.origin)return'portal.html';return x.pathname.replace(/^\//,'')+x.search+x.hash}catch{return /^[\w\-./?=&%#]+$/.test(u)?u:'portal.html'}}
  function badgeCard(b){const p=Number(b.progress_percent||0);return `<article class="home-badge-card color-${esc(b.color||'gold')}"><div class="home-badge-icon">${P()?.iconSvg?P().iconSvg(b.icon_key||'trophy'):'🏆'}</div><div><h4>${esc(b.title)}</h4><p>${esc(b.metric_label||b.description||'')}</p><div class="home-progress"><i style="width:${Math.max(0,Math.min(100,p))}%"></i></div></div><b>${p}%</b></article>`}
  function scheduleCard(s){return `<article class="home-schedule-card"><b>${esc(s.subject_name||'حصة')}</b><small>${esc(s.class_name||s.section_name||'')} · الحصة ${esc(s.period_number||'—')} · ${esc(s.teacher_name||'')}</small></article>`}
  function dayName(day){return ({0:'السبت',1:'الأحد',2:'الاثنين',3:'الثلاثاء',4:'الأربعاء',5:'الخميس',6:'الجمعة'}[Number(day)]||'يوم')}
  function scheduleRowsHtml(items){
    items=items||[];
    if(!items.length)return '<div class="empty">لا يوجد جدول قريب</div>';
    const days=[...new Set(items.map(x=>String(x.day??'x')))];
    return days.map(d=>`<div class="home-schedule-day-row"><b>${esc(dayName(d))}</b><div class="home-schedule-boxes">${items.filter(x=>String(x.day??'x')===d).map(x=>`<div class="home-schedule-box"><strong>${esc(x.subject_name||'حصة')}</strong><small>حصة ${esc(x.period_number||'—')}</small><em>${esc(x.class_name||x.section_name||'')}</em></div>`).join('')}</div></div>`).join('');
  }
  function localTriple(){
    const d=new Date();
    const greg=d.toLocaleDateString('ar-IQ',{timeZone:'Asia/Tehran',year:'numeric',month:'2-digit',day:'2-digit'});
    let solar='—', lunar='—';
    try{solar=new Intl.DateTimeFormat('fa-IR-u-ca-persian',{timeZone:'Asia/Tehran',year:'numeric',month:'2-digit',day:'2-digit'}).format(d)}catch{}
    try{lunar=new Intl.DateTimeFormat('ar-SA-u-ca-islamic-umalqura',{timeZone:'Asia/Tehran',year:'numeric',month:'2-digit',day:'2-digit'}).format(d)}catch{}
    return {gregorian:greg,solar,lunar,display:greg+' - '+solar+' - '+lunar};
  }
  function tripleHtml(){const tr=HOME?.triple_date&&Object.keys(HOME.triple_date).length?HOME.triple_date:localTriple();return `<div class="triple-cards"><div><small>ميلادي</small><b>${esc(tr.gregorian||tr.display||'—')}</b></div><div><small>شمسي</small><b>${esc(tr.solar||'—')}</b></div><div><small>هجري</small><b>${esc(tr.lunar||'—')}</b></div></div>`}
  function renderHome(){
    const wrap=$('#homeDashboard'); if(!wrap)return;
    if(!HOME){
      const list=(PAYLOAD.notifications||[]).slice(0,6).map(n=>({title:n.title,description:n.body,agenda_type:'notification',date_gregorian:n.created_at,priority:n.is_unread?'high':'normal',status:n.is_unread?'pending':'done',action_label:'فتح',action_url:'notifications.html?lite=1'}));
      wrap.innerHTML=`<section class="home-unique-hero"><div><h2>مرحباً ${esc(ME?.name||'')}</h2><p>صفحتك الأولى تعمل الآن. لم تكتمل بيانات الشارات/الجدول بعد، لكن يمكنك استخدام الواجهات والتقويم والإشعارات.</p></div><div class="home-clock"><b id="portalClock">--:--</b><small>الساعة الآن</small></div></section>${tripleHtml()}<div class="home-main-grid"><section class="home-panel important"><header><h3>أهم المهام الآن</h3><button class="btn small" onclick="location.href='smart-calendar.html?lite=1'">التقويم</button></header><div class="home-task-list">${list.map(homeTaskCard).join('')||'<div class="empty">لا توجد مهام عاجلة الآن</div>'}</div></section><section class="home-panel"><header><h3>الجدول المدرسي</h3><button class="btn small" onclick="location.href='smart-calendar.html?lite=1'">عرض التفاصيل</button></header><div class="home-schedule-list"><div class="empty">شغّلي SQL 114/109 لاحقاً لإظهار الجدول المختصر هنا، أو افتحي التقويم.</div></div></section><section class="home-panel badges"><header><h3>شارات الإنجاز</h3><button class="btn small" onclick="location.href='achievements.html?lite=1'">كل الشارات</button></header><div class="home-badge-list"><div class="empty">الشارات تظهر بعد تفعيل دالة get_my_badge_progress، ويمكنك فتح صفحة الشارات.</div></div></section></div>`;
      portalClock(); clearInterval(window.__portalClockTimer); window.__portalClockTimer=setInterval(portalClock,1000);
      return;
    }
    const tasks=agendaItems().slice(0,6), badges=(HOME.badges?.cards||[]).slice(0,6), schedule=(HOME.schedule||[]).slice(0,6);
    wrap.innerHTML=`<section class="home-unique-hero"><div><h2>مرحباً ${esc(ME?.name||'')}</h2><p>صفحتك الأولى: أهم المهام، الجدول، الشارات، التقويم الثلاثي والساعة.</p></div><div class="home-clock"><b id="portalClock">--:--</b><small>الساعة الآن</small></div></section>${tripleHtml()}<div class="home-main-grid"><section class="home-panel important"><header><h3>أهم المهام الآن</h3><button class="btn small" onclick="location.href='smart-calendar.html?lite=1'">التقويم</button></header><div class="home-task-list">${tasks.map(homeTaskCard).join('')||'<div class="empty">لا توجد مهام مهمة الآن</div>'}</div></section><section class="home-panel"><header><h3>الجدول المدرسي</h3><button class="btn small" onclick="location.href='smart-calendar.html?lite=1'">عرض التفاصيل</button></header><div class="home-schedule-list">${scheduleRowsHtml(schedule)}</div></section><section class="home-panel badges"><header><h3>شارات الإنجاز</h3><button class="btn small" onclick="location.href='achievements.html?lite=1'">كل الشارات</button></header><div class="home-badge-list">${badges.map(badgeCard).join('')||'<div class="empty">لا توجد شارات محسوبة بعد</div>'}</div></section></div>`;
    portalClock(); clearInterval(window.__portalClockTimer); window.__portalClockTimer=setInterval(portalClock,1000);
  }
  function openTab(tab){
    $$('.portal-tabs button').forEach(b=>b.classList.toggle('active',b.dataset.portalTab===tab));
    $$('.portal-tab-panel').forEach(p=>p.classList.remove('active'));
    const panel=document.getElementById('tab-'+tab); if(panel)panel.classList.add('active');
  }

  function renderModules(){
    const search = ($('#moduleSearch')?.value || '').trim();
    const allVisible = (P()?.uniqueModules(moduleCatalog()) || moduleCatalog()).filter(canSee);
    const gList = visibleGroups(allVisible);
    let visible = allVisible.filter(m => moduleSearchMatches(m, search));
    if(ACTIVE_GROUP !== 'all' && !search) visible = visible.filter(m => m.group === ACTIVE_GROUP);
    MODULES = visible;
    window.AMIN_VISIBLE_MODULES = visible;

    const quick = $('#quickNav');
    if(quick) quick.innerHTML = quickNavHtml(gList, allVisible.length) || '<div class="empty">لا توجد روابط</div>';

    const grid = $('#modulesGrid');
    if(!grid) return;
    if(!visible.length){
      grid.className = 'modules-grid empty-grid';
      grid.innerHTML = `<div class="empty no-modules">${search ? 'لا توجد نتائج مطابقة لبحثك' : 'لا توجد واجهات مفوضة لهذا الحساب'}</div>`;
      return;
    }
    grid.className = 'portal-groups';
    const byGroup = new Map();
    visible.forEach(m => {
      const k = m.group || 'main';
      if(!byGroup.has(k)) byGroup.set(k, []);
      byGroup.get(k).push(m);
    });
    const groupsByKey = Object.fromEntries(groups().map(g => [g.key, g]));
    grid.innerHTML = Array.from(byGroup.entries()).map(([key, mods]) => {
      const g = groupsByKey[key] || {key, color:'indigo', icon:'grid', title:{ar:key}, desc:{ar:''}};
      return `<section class="module-group icon-${esc(g.color || 'indigo')}" id="portal-group-${esc(key)}">
        <header class="module-group-head">
          <div class="module-group-title">${iconHtml(g)}<div><h3>${esc(text(g.title, key))}</h3><p>${esc(text(g.desc, ''))}</p></div></div>
          <span class="module-count">${mods.length}</span>
        </header>
        <div class="module-group-grid">${mods.map(moduleCard).join('')}</div>
      </section>`;
    }).join('');
  }

  function renderNotifications(){
    const list = PAYLOAD.notifications || [];
    const wrap = $('#notificationsList');
    if(!wrap) return;
    wrap.innerHTML = list.map(n => `<article class="portal-note ${n.is_unread ? 'unread' : ''}">
      <div><h4>${esc(n.title)}</h4><p>${esc(n.body || '')}</p><small>${fmt(n.created_at)}</small></div>
      ${n.is_unread ? `<button class="btn small blue" onclick="UnifiedPortal.markRead('${esc(n.id)}')">مقروء</button>` : ''}
    </article>`).join('') || '<div class="empty">لا توجد إشعارات</div>';
  }
  function openModule(key){
    const all = moduleCatalog();
    const m = all.find(x => x.key === key);
    if(!m || m.disabled) return;
    if(!canSee(m)){
      toast('غير مصرح', 'هذه الواجهة غير مفوضة لحسابك', 'red');
      return;
    }
    location.href = m.href;
  }
  function openNotifications(){ location.href = 'notifications.html?lite=1'; }
  async function markRead(id){
    try{
      const { data, error } = await client().rpc('mark_notification_read', { p_notification_id:id });
      if(error) throw error;
      if(data && data.ok === false) throw new Error(data.message || 'تعذر التحديث');
      await loadPayload();
      const badge = $('#unreadBadge'); if(badge) badge.textContent = PAYLOAD.unread_notifications || 0;
      renderNotifications();
      toast('تم', 'تم تعليم الإشعار كمقروء', 'green');
    }catch(e){ toast('تعذر تحديث الإشعار', e.message || String(e), 'red'); }
  }
  async function refresh(){
    await loadPayload();
    const badge = $('#unreadBadge'); if(badge) badge.textContent = PAYLOAD.unread_notifications || 0;
    await loadHome();
    renderHome();
    renderModules();
    renderNotifications();
    toast('تم التحديث', 'تم تحديث البوابة', 'green');
  }
  function bind(){
    $('#moduleSearch')?.addEventListener('input', () => { ACTIVE_GROUP = 'all'; renderModules(); });
    $('#refreshBtn')?.addEventListener('click', refresh);
    $('#logoutBtn')?.addEventListener('click', async () => { await client().auth.signOut({ scope:'local' }); location.href = 'index.html'; });
    $('#mobileMenuBtn')?.addEventListener('click', () => $('#sidebar')?.classList.toggle('open'));
    $('#commandOpenBtn')?.addEventListener('click', () => window.AminUX?.openCommandPalette?.());
    $$('.portal-tabs button').forEach(b=>b.addEventListener('click',()=>openTab(b.dataset.portalTab)));
    window.addEventListener('amin:language-change', () => { renderHome(); renderModules(); renderNotifications(); });
  }
  async function init(){
    client();
    if(!await ensure()) return;
    bind();
    await loadHome();
    renderHome();
    renderModules();
    renderNotifications();
  }

  window.UnifiedPortal = { init, openModule, openNotifications, markRead, refresh, openGroup:setActiveGroup, openTab };
}());

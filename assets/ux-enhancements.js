/* Amin Premium UX Enhancements — non-invasive, unified across all pages */
(function(){
  'use strict';
  const $=(s,r=document)=>r.querySelector(s);
  const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
  const P=()=>window.AMIN_PLATFORM||null;
  let commandState={open:false,index:0,results:[]};

  function ready(fn){ if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',fn); else fn(); }
  function normalizeText(v){ return String(v||'').replace(/\s+/g,' ').trim(); }
  function stripEmoji(v){ return normalizeText(v).replace(/^[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\uFE0F\s]+/u,'').trim(); }
  function esc(v){ return P()?.esc(v) || String(v==null?'':v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m])); }

  function addRipple(){
    document.addEventListener('click',function(e){
      const btn=e.target.closest('button,.btn,.amin-login-btn');
      if(!btn||btn.disabled||btn.classList.contains('no-ripple'))return;
      const rect=btn.getBoundingClientRect();
      const size=Math.max(rect.width,rect.height);
      const span=document.createElement('span');
      span.className='ux-ripple';
      span.style.width=span.style.height=size+'px';
      span.style.left=(e.clientX-rect.left-size/2)+'px';
      span.style.top=(e.clientY-rect.top-size/2)+'px';
      btn.appendChild(span);
      setTimeout(()=>span.remove(),620);
    },{passive:true});
  }

  function sanitizeNavigation(){
    $$('.nav').forEach(nav=>{
      const seen=new Set();
      $$('button',nav).forEach(btn=>{
        const view=btn.getAttribute('data-view');
        const onclick=btn.getAttribute('onclick')||'';
        const label=stripEmoji(btn.textContent||'');
        const key=view?`view:${view}`:`link:${onclick||label}`;
        if(seen.has(key)){
          btn.dataset.duplicate='1';
          btn.setAttribute('aria-hidden','true');
          return;
        }
        seen.add(key);
      });
    });
  }

  function enhanceNav(){
    $$('.nav button[data-view]:not([data-duplicate="1"])').forEach(btn=>{
      if(btn.classList.contains('active')) btn.setAttribute('aria-current','page');
      btn.addEventListener('click',()=>{
        setTimeout(()=>{
          const nav=btn.closest('.nav');
          if(nav) $$('button[data-view]',nav).forEach(b=>b.removeAttribute('aria-current'));
          if(btn.classList.contains('active')) btn.setAttribute('aria-current','page');
          updateBreadcrumb();
          syncLiteNav(btn);
        },40);
      });
    });
  }
  function pageTitle(){
    const active=$('.view.active .page-head h1')||$('.topbar h2')||$('title');
    return normalizeText(active&&active.textContent||document.title||'النظام');
  }
  function updateBreadcrumb(){
    const top=$('.topbar'); if(!top)return;
    let holder=$('.ux-title-wrap',top);
    const h2=$('h2',top);
    if(!holder&&h2){
      holder=document.createElement('div'); holder.className='ux-title-wrap';
      h2.parentNode.insertBefore(holder,h2); holder.appendChild(h2);
      const bc=document.createElement('div'); bc.className='ux-breadcrumb'; holder.appendChild(bc);
    }
    const bc=$('.ux-breadcrumb',top);
    if(bc){
      const portal=(document.body.dataset.portal||'').replace(/-/g,' ');
      bc.textContent='مجمع أمين الرضا التعليمي / '+(portal?portal+' / ':'')+pageTitle();
    }
  }
  function lazyImages(){ $$('img').forEach(img=>{ if(!img.loading) img.loading='lazy'; if(!img.decoding) img.decoding='async'; }); }

  function mobileDrawerBackdrop(){
    const sidebar=$('#sidebar'); if(!sidebar)return;
    let backdrop=$('.sidebar-backdrop');
    if(!backdrop){ backdrop=document.createElement('div'); backdrop.className='sidebar-backdrop'; document.body.appendChild(backdrop); }
    document.addEventListener('click',e=>{
      const menu=e.target.closest('#mobileMenuBtn,.mobile-menu');
      if(menu){ setTimeout(()=>backdrop.classList.toggle('show',sidebar.classList.contains('open')),0); }
      if(e.target===backdrop){ sidebar.classList.remove('open'); backdrop.classList.remove('show'); }
      if(e.target.closest('.nav button')&&window.matchMedia('(max-width:900px)').matches){ setTimeout(()=>{ if(!sidebar.classList.contains('open')) backdrop.classList.remove('show'); },80); }
    });
  }

  function applyTheme(mode){
    const m=mode||localStorage.getItem('amin_theme')||'light';
    const prefers=window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches;
    const dark=m==='dark'||(m==='system'&&prefers);
    document.documentElement.setAttribute('data-theme',dark?'dark':'light');
    document.documentElement.style.colorScheme=dark?'dark':'light';
    localStorage.setItem('amin_theme',m);
    const btn=document.getElementById('themeToggle');
    if(btn){btn.textContent=dark?'☀️':'🌙';btn.setAttribute('aria-label',dark?'تفعيل الوضع الفاتح':'تفعيل الوضع الداكن');}
  }
  function setupThemeToggle(){
    if(document.getElementById('themeToggle'))return;
    const btn=document.createElement('button');
    btn.id='themeToggle';
    btn.type='button';
    btn.className='theme-toggle no-ripple';
    btn.setAttribute('aria-label','تفعيل الوضع الداكن');
    btn.addEventListener('click',()=>{
      const now=document.documentElement.getAttribute('data-theme')==='dark'?'light':'dark';
      applyTheme(now);
    });
    document.body.appendChild(btn);
    applyTheme(localStorage.getItem('amin_theme')||'light');
    if(window.matchMedia){
      window.matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change',()=>{
        if((localStorage.getItem('amin_theme')||'light')==='system')applyTheme('system');
      });
    }
  }

  function registerPWA(){
    if(!('serviceWorker' in navigator))return;
    if(location.protocol!=='https:' && location.hostname!=='localhost')return;
    window.addEventListener('load',()=>{
      navigator.serviceWorker.register('/sw.js').catch(err=>console.warn('SW registration failed',err));
    });
  }
  function setupInstallPrompt(){
    let deferred=null;
    window.addEventListener('beforeinstallprompt',e=>{
      e.preventDefault(); deferred=e;
      let btn=document.getElementById('installAppBtn');
      if(!btn){btn=document.createElement('button');btn.id='installAppBtn';btn.className='install-app-btn no-ripple';btn.type='button';btn.textContent='📲 تثبيت';document.body.appendChild(btn);}
      btn.hidden=false;
      btn.onclick=async()=>{if(!deferred)return;deferred.prompt();await deferred.userChoice;deferred=null;btn.hidden=true;};
    });
  }

  function commandModules(){
    const base=(window.AMIN_VISIBLE_MODULES&&window.AMIN_VISIBLE_MODULES.length)?window.AMIN_VISIBLE_MODULES:(P()?.modules||[]);
    return P()?.uniqueModules(base)||base;
  }
  function moduleText(m,field){ return P()?.text(m[field], '') || (m[field]?.ar||m[field]?.en||''); }
  function renderCommandResults(query){
    const results=(P()?.searchModules(query, commandModules())||[]).slice(0,30);
    commandState.results=results;
    if(commandState.index>=results.length) commandState.index=0;
    const wrap=$('#commandResults'); if(!wrap)return;
    if(!results.length){ wrap.innerHTML='<div class="command-empty">لا توجد نتائج</div>'; return; }
    wrap.innerHTML=results.map((m,i)=>`<button type="button" class="command-result ${i===commandState.index?'active':''} icon-${esc(m.color||'indigo')}" data-index="${i}" data-href="${esc(m.href||'#')}">
      ${P()?.iconHtml(m)||''}<span><h4>${esc(moduleText(m,'title')||m.key)}</h4><p>${esc(moduleText(m,'desc')||'')}</p></span><small>${esc((m.href||'').replace('?lite=1',''))}</small>
    </button>`).join('');
  }
  function ensureCommandPalette(){
    if($('#commandPaletteBackdrop'))return;
    const div=document.createElement('div');
    div.id='commandPaletteBackdrop';
    div.className='command-palette-backdrop';
    div.innerHTML=`<div class="command-palette" role="dialog" aria-modal="true" aria-label="بحث سريع">
      <div class="command-head"><input id="commandInput" placeholder="بحث سريع في الواجهات والتقارير..." autocomplete="off"><kbd>Esc</kbd></div>
      <div class="command-results" id="commandResults"></div>
    </div>`;
    div.addEventListener('click',e=>{ if(e.target===div) closeCommandPalette(); });
    div.addEventListener('click',e=>{
      const item=e.target.closest('.command-result'); if(!item)return;
      const href=item.dataset.href; if(href&&href!=='#') location.href=href;
    });
    document.body.appendChild(div);
    const input=$('#commandInput');
    input.addEventListener('input',()=>{ commandState.index=0; renderCommandResults(input.value); });
    input.addEventListener('keydown',e=>{
      if(e.key==='Escape'){ e.preventDefault(); closeCommandPalette(); }
      if(e.key==='ArrowDown'){ e.preventDefault(); commandState.index=Math.min((commandState.results.length||1)-1,commandState.index+1); renderCommandResults(input.value); }
      if(e.key==='ArrowUp'){ e.preventDefault(); commandState.index=Math.max(0,commandState.index-1); renderCommandResults(input.value); }
      if(e.key==='Enter'){
        const m=commandState.results[commandState.index];
        if(m&&m.href){ e.preventDefault(); location.href=m.href; }
      }
    });
  }
  function openCommandPalette(){
    ensureCommandPalette();
    const bd=$('#commandPaletteBackdrop');
    const input=$('#commandInput');
    if(!bd||!input)return;
    commandState.open=true; commandState.index=0;
    bd.classList.add('show');
    input.value='';
    renderCommandResults('');
    setTimeout(()=>input.focus(),40);
  }
  function closeCommandPalette(){
    const bd=$('#commandPaletteBackdrop');
    if(bd) bd.classList.remove('show');
    commandState.open=false;
  }
  function setupCommandPalette(){
    if(!P()?.modules?.length)return;
    document.addEventListener('keydown',e=>{
      const k=(e.key||'').toLowerCase();
      if((e.ctrlKey||e.metaKey)&&k==='k'){
        e.preventDefault(); openCommandPalette();
      }
      if(e.key==='Escape'&&commandState.open){ closeCommandPalette(); }
    });
    const existing=$('#commandOpenBtn');
    if(existing){ existing.classList.add('command-launch'); existing.addEventListener('click',openCommandPalette); }
    const topActions=$('.topbar .top-actions');
    if(topActions&&!$('#commandOpenBtn')&&!topActions.querySelector('.command-launch')){
      const btn=document.createElement('button');
      btn.type='button'; btn.className='btn command-launch no-ripple'; btn.innerHTML='بحث سريع <span class="command-shortcut">Ctrl K</span>';
      btn.addEventListener('click',openCommandPalette);
      topActions.insertBefore(btn,topActions.firstChild);
    }
    if((document.body.dataset.portal||'')==='unified'&&!$('.command-floating')){
      const btn=document.createElement('button'); btn.type='button'; btn.className='command-floating no-ripple'; btn.textContent='⌘ بحث'; btn.addEventListener('click',openCommandPalette); document.body.appendChild(btn);
    }
  }

  function setupUnifiedBottomNav(){
    if((document.body.dataset.portal||'')!=='unified')return;
    if(document.querySelector('.unified-bottom-nav'))return;
    const nav=document.createElement('nav');
    nav.className='unified-bottom-nav';
    nav.innerHTML='<button data-action="home">🏠<span>الرئيسية</span></button><button data-action="notifications">🔔<span>الإشعارات</span></button><button data-action="search">🔎<span>بحث</span></button><button data-action="logout">⏻<span>خروج</span></button>';
    nav.addEventListener('click',e=>{
      const b=e.target.closest('button'); if(!b)return;
      const a=b.dataset.action;
      if(a==='home') window.scrollTo({top:0,behavior:'smooth'});
      if(a==='notifications') location.href='notifications.html?lite=1';
      if(a==='search') openCommandPalette();
      if(a==='logout') document.getElementById('logoutBtn')?.click();
    });
    document.body.appendChild(nav);
  }

  function syncLiteNav(activeSource){
    const nav=$('.unified-lite-nav'); if(!nav||!activeSource)return;
    const view=activeSource.getAttribute('data-view'); if(!view)return;
    $$('button[data-lite-view]',nav).forEach(b=>b.classList.toggle('active',b.dataset.liteView===view));
  }
  function setupLiteMode(){
    const params=new URLSearchParams(location.search);
    const hasLegacySidebar=!!document.querySelector('#sidebar') && (document.body.dataset.portal||'') !== 'unified';
    if(params.get('lite')!=='1' && !hasLegacySidebar)return;
    document.body.classList.add('unified-lite');
    const build=()=>{
      if(document.querySelector('.unified-lite-nav'))return;
      const source=document.querySelector('.sidebar .nav');
      const main=document.querySelector('.main')||document.querySelector('main');
      if(!main)return;
      const nav=document.createElement('div');
      nav.className='unified-lite-nav';
      const back=document.createElement('button');
      back.type='button'; back.className='unified-lite-back'; back.textContent='البوابة الموحدة';
      back.addEventListener('click',()=>location.href='portal.html');
      nav.appendChild(back);
      const search=document.createElement('button');
      search.type='button'; search.className='command-launch no-ripple'; search.innerHTML='بحث سريع <span class="command-shortcut">Ctrl K</span>';
      search.addEventListener('click',openCommandPalette);
      nav.appendChild(search);
      const seen=new Set();
      const buttons=source?Array.from(source.querySelectorAll('button:not([data-duplicate="1"])')).filter(b=>{
        const onclick=b.getAttribute('onclick')||'';
        return b.hasAttribute('data-view') || onclick.includes('scrollIntoView');
      }):[];
      buttons.forEach(orig=>{
        const view=orig.getAttribute('data-view');
        const key=view||orig.getAttribute('onclick')||stripEmoji(orig.textContent||'');
        if(!key||seen.has(key))return;
        seen.add(key);
        const b=document.createElement('button');
        b.type='button';
        if(view) b.dataset.liteView=view;
        b.textContent=stripEmoji(orig.textContent||'');
        if(orig.classList.contains('active'))b.classList.add('active');
        b.addEventListener('click',()=>{orig.click();setTimeout(()=>syncLiteNav(orig),80);});
        nav.appendChild(b);
      });
      main.insertBefore(nav,main.firstChild);
    };
    setTimeout(build,250);
    setTimeout(build,900);
    setTimeout(build,1800);
  }

  ready(()=>{
    document.documentElement.classList.add('amin-premium-ui');
    sanitizeNavigation();
    addRipple(); enhanceNav(); updateBreadcrumb(); lazyImages(); mobileDrawerBackdrop(); setupCommandPalette(); setupLiteMode(); setupThemeToggle(); registerPWA(); setupInstallPrompt(); setupUnifiedBottomNav();
    window.addEventListener('load',()=>setTimeout(()=>{sanitizeNavigation();updateBreadcrumb();},250));
  });

  window.AminUX={openCommandPalette,closeCommandPalette,applyTheme,sanitizeNavigation};
}());

/* Permission-aware navigation pruning — removes tabs/routes the signed-in user cannot access. */
(function(){
  'use strict';
  const cfg=()=>window.AMIN_CONFIG||{};
  const $=(s,r=document)=>r.querySelector(s);
  const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
  let perms=null;
  function readAccessToken(){
    const key=cfg().authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2';
    const candidates=[key,`sb-${(cfg().supabaseUrl||'').split('//')[1]||''}-auth-token`];
    for(const k of candidates){
      try{
        const raw=localStorage.getItem(k); if(!raw)continue;
        const j=JSON.parse(raw);
        const token=j?.currentSession?.access_token||j?.access_token||j?.session?.access_token;
        if(token)return token;
      }catch{}
    }
    return null;
  }
  async function fetchMyPermissions(){
    const token=readAccessToken();
    if(!token||!cfg().supabaseUrl||!cfg().supabaseAnonKey)return [];
    const res=await fetch((cfg().supabaseUrl||'').replace(/\/$/,'')+'/rest/v1/rpc/get_my_permissions',{
      method:'POST',
      headers:{'content-type':'application/json','apikey':cfg().supabaseAnonKey,'authorization':'Bearer '+token},
      body:'{}'
    });
    if(!res.ok)throw new Error('permissions_http_'+res.status);
    const data=await res.json();
    return Array.isArray(data)?data:[];
  }
  function fileOf(href){try{return String(href||'').split('?')[0].split('#')[0].replace(/^\.\//,'').replace(/^\//,'')||''}catch{return''}}
  function modulePermForHref(href){
    const file=fileOf(href); if(!file||file==='portal.html'||file==='index.html'||file==='clear-session.html')return null;
    const mods=(window.AMIN_PLATFORM&&window.AMIN_PLATFORM.modules)||[];
    const m=mods.find(x=>fileOf(x.href)===file);
    if(m)return m.perms||m.perm||null;
    const map={
      'finance-pro.html':'finance','finance-cashbox.html':'finance','finance-receiver-reports.html':'finance','finance-executive.html':'finance','finance-collections.html':'finance','finance-credit-report.html':'finance','admin-finance-rules.html':'finance',
      'academic-pro.html':'academic','schedule-management.html':'schedule','section-assignment-management.html':'sections','teacher.html':'teacher','student.html':'student','staff.html':'staff.dashboard','super-admin.html':'admin',
      'student-homeworks.html':'homework','homework-reports.html':'homework.reports','homework-audit.html':'homework.audit','teacher-exams.html':'question_bank','online-exams.html':'online_exams','exam-integrity.html':'exam_integrity',
      'library.html':'library','inventory.html':'inventory','fixed-assets.html':'assets','hr.html':'hr','transportation.html':'transport','labs-activities.html':['labs','activities'],'documents.html':'documents','analytics-center.html':'analytics','announcements.html':'announcements','registrations-admin.html':'registrations','permissions-management.html':'users','final-readiness.html':'system','system-maintenance.html':'system','notifications.html':'notifications','smart-calendar.html':'calendar','achievements.html':'achievements','counselor.html':'counseling'
    };
    return map[file]||null;
  }
  function hrefFromButton(btn){
    const direct=btn.getAttribute('href'); if(direct)return direct;
    const onclick=btn.getAttribute('onclick')||'';
    const m=onclick.match(/location\.href\s*=\s*['"]([^'"]+)['"]/);
    return m?m[1]:'';
  }
  function viewPerm(btn){
    const v=btn.dataset.view; if(!v)return null;
    if(['overview','dashboard','all','unread'].includes(v))return null;
    const portal=document.body.dataset.portal||fileOf(location.pathname)||'';
    const common={finance:['finance','student','parent'],attendance:'attendance',behavior:'behavior',counseling:'counseling',students:['students','teacher','academic','counseling'],evaluation:['academic','grades'],academics:'academic',grades:'grades',schedule:['schedule','teacher','student','parent'],reports:'reports',homework:'homework',plan:'teacher',cases:'counseling',award:'counseling',analytics:['analytics','counseling'],alerts:['notifications','counseling'],badges:'achievements',leaderboard:'achievements',mine:'achievements',settings:'system'};
    const byPortal={
      teacher:{attendance:'attendance',homework:'homework',plan:'teacher',grades:'grades',students:'teacher',schedule:'teacher'},
      student:{grades:'grades',attendance:'attendance',finance:['finance','student','parent'],schedule:['schedule','student','parent'],behavior:'behavior'},
      staff:{finance:'finance',attendance:'attendance',counseling:'counseling',students:'students',evaluation:'academic',reports:'reports'},
      counselor:{cases:'counseling',schedule:'counseling',analytics:'counseling',alerts:'counseling'},
      achievements:{mine:'achievements',badges:'achievements',leaderboard:'achievements',award:'achievements'}
    };
    return (byPortal[portal]&&byPortal[portal][v])||common[v]||null;
  }
  function has(req){
    if(!req)return true;
    const p=perms||[];
    const reqs=Array.isArray(req)?req:[req];
    if(reqs.includes('counseling')||reqs.includes('counseling.full'))return reqs.some(x=>p.includes(x));
    if(p.includes('admin'))return true;
    return reqs.some(x=>p.includes(x));
  }
  function required(btn){return modulePermForHref(hrefFromButton(btn))||viewPerm(btn)}
  function prune(){
    if(!perms)return;
    $$('.nav button,.unified-lite-nav button,.counselor-mode-tabs button').forEach(btn=>{
      if(btn.dataset.permissionPruned)return;
      const req=required(btn);
      if(req&&!has(req)){
        btn.dataset.permissionPruned='1';
        btn.remove();
      }
    });
    $$('.nav').forEach(nav=>{
      const active=$('button.active[data-view]',nav);
      if(!active){const first=$('button[data-view]',nav); if(first){first.classList.add('active');}}
    });
  }
  async function init(){
    try{
      if((document.body.dataset.portal||'')==='unified')return;
      perms=await fetchMyPermissions();
      if(!perms.length)return;
      prune(); setTimeout(prune,500); setTimeout(prune,1400); setTimeout(prune,2800);
    }catch(e){console.warn('permission nav filter skipped',e)}
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();

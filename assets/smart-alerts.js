(function(){
'use strict';

if(window.SmartAlerts && window.SmartAlerts._initialized) return;

var SmartAlerts = {
  _initialized: false,
  _initInProgress: false,
  alerts: [],
  role: null,
  user: null,
  sb: null,

  init: async function(supabaseClient, currentUser) {
    if(this._initialized || this._initInProgress) return;
    if(!supabaseClient || !currentUser) return;
    
    this._initInProgress = true;
    this.sb = supabaseClient;
    this.user = currentUser;
    this.role = currentUser.role || 'guest';
    this._initialized = true;
    this._initInProgress = false;
    
    console.log('🔔 SmartAlerts initialized for:', this.role);
    
    await this.loadAlerts();
    this.render();
  },

  loadAlerts: async function() {
    this.alerts = [];
    try {
      if(this.role === 'parent') await this.loadParentAlerts();
      else if(this.role === 'teacher') await this.loadTeacherAlerts();
      else if(this.role === 'student') await this.loadStudentAlerts();
      else if(this.role === 'counselor' || this.role === 'psychologist') await this.loadCounselorAlerts();
      else if(this.role === 'admin' || this.user.is_super_admin) await this.loadAdminAlerts();
      else if(this.role === 'finance') await this.loadFinanceAlerts();
      await this.loadNotifications();
    } catch(e) { console.error('🔔 SmartAlerts error:', e); }
  },

  loadParentAlerts: async function() {
    var self = this;
    try {
      var cr = await this.sb.from('students').select('id, users:user_id(name)').eq('parent_id', this.user.id);
      var children = cr.data || [];
      if(!children.length) return;
      for(var i = 0; i < children.length; i++) {
        var child = children[i];
        var childName = (child.users && child.users.name) || 'الطالب';
        try {
          var ar = await this.sb.from('attendance').select('status').eq('student_id', child.id).limit(30);
          var att = ar.data || [];
          if(att.length) {
            var absent = att.filter(function(a){ return a.status === 'absent'; }).length;
            var rate = (absent/att.length)*100;
            if(rate > 20) self.alerts.push({type:'danger', icon:'⚠️', title:'غياب ' + childName, msg: Math.round(rate)+'% غياب', link:'parent.html'});
          }
        } catch(e) {}
        try {
          var fr = await this.sb.from('student_fees').select('net_amount, base_amount, total_paid').eq('student_id', child.id);
          var fees = fr.data || [];
          fees.forEach(function(f) {
            var remaining = (f.net_amount || f.base_amount || 0) - (f.total_paid || 0);
            if(remaining > 0) self.alerts.push({type:'warning', icon:'💰', title:'قسط ' + childName, msg:'متبقي $' + remaining, link:'parent.html'});
          });
        } catch(e) {}
      }
    } catch(e) {}
  },

  loadTeacherAlerts: async function() {
    try {
      var sr = await this.sb.from('weekly_schedule').select('class_id').eq('teacher_id', this.user.id);
      var schedule = sr.data || [];
      if(schedule.length) {
        this.alerts.push({type:'info', icon:'📅', title:'جدولي الأسبوعي', msg: schedule.length + ' حصة', link:'teacher.html'});
      }
    } catch(e) {}
  },

  loadStudentAlerts: async function() {
    var self = this;
    try {
      var sr = await this.sb.from('students').select('id').eq('user_id', this.user.id).maybeSingle();
      if(!sr.data) return;
      var sid = sr.data.id;
      try {
        var hr = await this.sb.from('v_student_homeworks').select('*').eq('student_id', sid).limit(20);
        var homeworks = hr.data || [];
        if(homeworks.length) {
          var today = new Date();
          var upcoming = homeworks.filter(function(h) {
            if(h.status === 'submitted') return false;
            var due = new Date(h.due_date || h.due_at);
            var diff = (due - today) / (1000*60*60*24);
            return diff >= 0 && diff <= 3;
          });
          if(upcoming.length > 0) self.alerts.push({type:'warning', icon:'📚', title:'واجبات قريبة', msg: upcoming.length + ' واجب', link:'student.html'});
        }
      } catch(e) {}
    } catch(e) {}
  },

  loadCounselorAlerts: async function() {
    try {
      var sr = await this.sb.from('students').select('id').limit(100);
      if((sr.data || []).length) {
        this.alerts.push({type:'info', icon:'👥', title:'الطلاب', msg: (sr.data || []).length + ' طالب', link:'counselor.html'});
      }
    } catch(e) {}
  },

  loadAdminAlerts: async function() {
    try {
      var fr = await this.sb.from('student_fees').select('net_amount, base_amount, total_paid').limit(500);
      var fees = fr.data || [];
      if(fees.length) {
        var totalDue = fees.reduce(function(s,f){ return s + Math.max((f.net_amount || f.base_amount || 0) - (f.total_paid || 0), 0); }, 0);
        if(totalDue > 0) this.alerts.push({type:'danger', icon:'💰', title:'متأخرات مالية', msg:'$' + Math.round(totalDue).toLocaleString(), link:'finance-pro.html'});
      }
    } catch(e) {}
    try {
      var sr = await this.sb.from('students').select('id').limit(1000);
      if((sr.data || []).length > 0) {
        this.alerts.push({type:'info', icon:'🎓', title:'الطلاب', msg: (sr.data || []).length + ' طالب', link:'portal.html#students'});
      }
    } catch(e) {}
    try {
      var todayStr = new Date().toISOString().slice(0,10);
      var ar = await this.sb.from('attendance').select('id').eq('date', todayStr).eq('status', 'absent').limit(100);
      if((ar.data || []).length > 0) {
        this.alerts.push({type:'warning', icon:'⚠️', title:'غيابات اليوم', msg: (ar.data || []).length + ' غياب', link:'portal.html#attendance'});
      }
    } catch(e) {}
  },

  loadFinanceAlerts: async function() {
    try {
      var fr = await this.sb.from('student_fees').select('*').limit(500);
      var fees = fr.data || [];
      if(fees.length) {
        var overdue = fees.filter(function(f) {
          var r = (f.net_amount || f.base_amount || 0) - (f.total_paid || 0);
          return r > 0;
        }).length;
        if(overdue > 0) this.alerts.push({type:'warning', icon:'💰', title: overdue + ' طالب متأخر', msg:'يحتاج متابعة', link:'finance-pro.html'});
      }
    } catch(e) {}
  },

  loadNotifications: async function() {
    try {
      var nr = await this.sb.from('school_notifications').select('*').eq('recipient_user_id', this.user.id).is('read_at', null).order('created_at', {ascending: false}).limit(5);
      var notifs = nr.data || [];
      if(notifs.length > 0) {
        this.alerts.unshift({type:'info', icon:'🔔', title: notifs.length + ' إشعار جديد', msg: notifs[0].title || 'تنبيه', link:'notifications.html'});
      }
    } catch(e) {}
  },

  playCriticalSound: function() {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(880, ctx.currentTime);
      osc.frequency.exponentialRampToValueAtTime(440, ctx.currentTime + 0.5);
      gain.gain.setValueAtTime(0.3, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.6);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start();
      osc.stop(ctx.currentTime + 0.6);
      // Second beep for critical
      setTimeout(()=>{
        try{
          const osc2 = ctx.createOscillator();
          const gain2 = ctx.createGain();
          osc2.type = 'sine';
          osc2.frequency.setValueAtTime(880, ctx.currentTime);
          osc2.frequency.exponentialRampToValueAtTime(440, ctx.currentTime + 0.5);
          gain2.gain.setValueAtTime(0.3, ctx.currentTime);
          gain2.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.6);
          osc2.connect(gain2);
          gain2.connect(ctx.destination);
          osc2.start();
          osc2.stop(ctx.currentTime + 0.6);
        }catch(e){}
      }, 300);
    } catch(e){ console.warn('Audio failed', e); }
  },

  requestPushPermission: async function() {
    if (!('Notification' in window)) return false;
    if (Notification.permission === 'granted') return true;
    if (Notification.permission === 'denied') return false;
    try {
      const perm = await Notification.requestPermission();
      return perm === 'granted';
    } catch { return false; }
  },

  showPushNotification: function(title, body, type) {
    if (!('Notification' in window) || Notification.permission !== 'granted') return;
    const icons = { critical: '🚨', high: '⚠️', medium: '📢', low: '📄', danger: '🚨', warning: '⚠️', info: '📢' };
    const icon = icons[type] || '🔔';
    try {
      const notif = new Notification(`${icon} ${title}`, {
        body: body,
        icon: '/assets/amin-logo-small.png',
        badge: '/assets/amin-logo-small.png',
        tag: `amin-${type}-${Date.now()}`,
        requireInteraction: type==='critical'||type==='danger',
        silent: false
      });
      notif.onclick = function(){ window.focus(); location.href='notifications.html'; this.close(); };
      setTimeout(()=>{ try{ notif.close(); }catch(e){} }, type==='critical'?10000:6000);
    } catch(e){ console.warn('Push failed', e); }
  },

  handleImportanceSoundsAndPush: function() {
    const critical = this.alerts.filter(a=>a.type==='critical'||a.type==='danger');
    const high = this.alerts.filter(a=>a.type==='high'||a.type==='warning');
    // Check if we already notified for these critical alerts to avoid spam
    const lastNotified = JSON.parse(localStorage.getItem('amin_last_critical_ids')||'[]');
    const newCritical = critical.filter(a=>!lastNotified.includes(a.title+'|'+a.msg));
    
    if (newCritical.length > 0) {
      this.playCriticalSound();
      this.requestPushPermission().then(granted=>{
        if(granted){
          newCritical.slice(0,2).forEach(a=>{
            this.showPushNotification(a.title, a.msg, 'critical');
          });
          if(critical.length>2){
            this.showPushNotification(`${critical.length} تنبيهات حرجة`, `${critical.length} تنبيهات حرجة تحتاج انتباهك فوراً`, 'critical');
          }
        }
      });
      localStorage.setItem('amin_last_critical_ids', JSON.stringify(critical.map(a=>a.title+'|'+a.msg)));
    }
    
    // For high importance, push without sound (or softer)
    if (high.length > 0 && critical.length===0) {
      const lastHighNotified = JSON.parse(localStorage.getItem('amin_last_high_ids')||'[]');
      const newHigh = high.filter(a=>!lastHighNotified.includes(a.title+'|'+a.msg));
      if(newHigh.length>0){
        this.requestPushPermission().then(granted=>{
          if(granted){
            newHigh.slice(0,1).forEach(a=>{
              this.showPushNotification(a.title, a.msg, 'high');
            });
          }
        });
        localStorage.setItem('amin_last_high_ids', JSON.stringify(high.map(a=>a.title+'|'+a.msg)));
      }
    }
  },

  render: function() {
  render: function() {
    var old = document.getElementById('smartAlertsBar');
    if(old) old.remove();
    if(!this.alerts.length) { this.renderEmptyBar(); return; }
    var bar = document.createElement('div');
    bar.id = 'smartAlertsBar';
    bar.innerHTML = this._buildHTML();
    document.body.appendChild(bar);
    // Play sound and push for critical/high after rendering
    try { this.handleImportanceSoundsAndPush(); } catch(e){ console.warn(e); }
  },

  renderEmptyBar: function() {
    var bar = document.createElement('div');
    bar.id = 'smartAlertsBar';
    bar.innerHTML = '<style>' + this._buildCSS() + '</style><div class="alert-toggle" onclick="SmartAlerts.toggle()" style="background:linear-gradient(135deg,#10b981,#059669);"><span class="amin-3d-ico-auto" data-size="20" data-emoji="✅" style="display:inline-flex;align-items:center;justify-content:center;width:20px;height:20px;">✅</span><span>كل شيء طبيعي</span></div><div class="alerts-panel"><div class="alert-header"><b style="color:#1f2937;">✅ لا توجد تنبيهات</b><button class="alert-close" onclick="SmartAlerts.toggle()">×</button></div><div style="padding:30px;text-align:center;color:#666;"><span class="amin-3d-ico-auto" data-size="48" data-emoji="🎉" style="display:inline-flex;align-items:center;justify-content:center;width:48px;height:48px;">🎉</span><p style="margin-top:12px;">كل شيء على ما يرام!</p></div></div>';
    document.body.appendChild(bar);
  },

  _buildHTML: function() {
    var self = this;
    var css = this._buildCSS();
    var sorted = this.alerts.slice().sort(function(a,b){
      const order={critical:1,danger:1,high:2,warning:2,medium:3,info:3,low:4,success:4};
      return (order[a.type]||3)-(order[b.type]||3);
    });
    var criticalCount = sorted.filter(function(a){return a.type==='critical'||a.type==='danger';}).length;
    var itemsHTML = sorted.map(function(a) {
      const isCritical = a.type==='critical'||a.type==='danger';
      const impBadge = isCritical ? '<span style="background:#dc2626;color:#fff;padding:2px 6px;border-radius:999px;font-size:10px;margin-right:6px">حرج</span>' : 
                       a.type==='high'||a.type==='warning' ? '<span style="background:#d97706;color:#fff;padding:2px 6px;border-radius:999px;font-size:10px;margin-right:6px">مهم</span>' : '';
      const delivery = a.importance==='critical' ? '💬 واتساب+📩 SMS+📱' : a.importance==='high' ? '💬 واتساب+📱' : '📱 داخل الموقع';
      const hoursText = a.hours_since ? Math.round(a.hours_since)+' ساعة' : 'الآن';
      return '<div class="alert-item ' + a.type + (isCritical ? ' critical-pulse' : '') + '" onclick="' + (a.link ? "location.href='" + a.link + "'" : '') + '"><div class="alert-title">' + a.icon + ' ' + self._esc(a.title) + ' ' + impBadge + '</div><div class="alert-msg">' + self._esc(a.msg) + '</div><div style="font-size:10px;color:#64748b;margin-top:4px">'+delivery+' · '+hoursText+'</div></div>';
    }).join('');
    const headerTitle = criticalCount ? `🔴 ${criticalCount} حرجة من ${this.alerts.length}` : `🔔 التنبيهات (${this.alerts.length})`;
    return '<style>' + css + '</style><div class="alerts-panel"><div class="alert-header"><b style="color:#1f2937;">' + headerTitle + '</b><button class="alert-close" onclick="SmartAlerts.toggle()">×</button></div><div style="padding:8px;display:flex;gap:6px;flex-wrap:wrap"><span style="background:#fee2e2;color:#dc2626;padding:4px 8px;border-radius:999px;font-size:11px">🔴 حرجة: واتساب+SMS+داخلي</span><span style="background:#fef3c7;color:#d97706;padding:4px 8px;border-radius:999px;font-size:11px">🟠 مهمة: واتساب+داخلي</span><span style="background:#dbeafe;color:#2563eb;padding:4px 8px;border-radius:999px;font-size:11px">🔵 متوسطة: داخلي فقط</span></div>' + itemsHTML + '</div><div class="alert-toggle ' + (criticalCount?'critical':'') + '" onclick="SmartAlerts.toggle()"><span class="amin-3d-ico-auto" data-size="20" data-emoji="🔔" style="display:inline-flex;align-items:center;justify-content:center;width:20px;height:20px;">🔔</span><span>التنبيهات</span><span class="alert-count">' + this.alerts.length + '</span>' + (criticalCount?'<span style="background:#fff;color:#dc2626;border-radius:999px;padding:2px 6px;font-size:10px;margin-right:4px">!</span>':'') + '</div>';
  },

  _buildCSS: function() {
    return "#smartAlertsBar{position:fixed;bottom:20px;left:20px;z-index:99999;max-width:360px;font-family:'Cairo','Segoe UI',Tahoma,sans-serif;direction:rtl}#smartAlertsBar .alert-toggle{background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;padding:12px 16px;border-radius:12px;cursor:pointer;box-shadow:0 8px 24px rgba(239,68,68,.4);display:flex;align-items:center;gap:10px;font-weight:700;user-select:none;transition:all 0.3s}#smartAlertsBar .alert-toggle.critical{background:linear-gradient(135deg,#dc2626,#991b1b);animation:criticalPulse 1.5s infinite;box-shadow:0 8px 32px rgba(220,38,38,.6)}@keyframes criticalPulse{0%,100%{transform:scale(1);box-shadow:0 8px 24px rgba(239,68,68,.4)}50%{transform:scale(1.05);box-shadow:0 12px 32px rgba(239,68,68,.7)}}#smartAlertsBar .alert-count{background:#fff;color:#dc2626;border-radius:999px;padding:2px 10px;font-size:12px;font-weight:700}#smartAlertsBar .alerts-panel{display:none;background:#fff;border-radius:12px;box-shadow:0 12px 40px rgba(0,0,0,.3);margin-bottom:10px;max-height:75vh;overflow-y:auto;padding:12px;color:#1f2937}#smartAlertsBar.open .alerts-panel{display:block}#smartAlertsBar .alert-item{padding:12px;border-radius:8px;margin-bottom:8px;cursor:pointer;border-right:4px solid;transition:all 0.2s}#smartAlertsBar .alert-item:hover{background:#f3f4f6;transform:translateX(-2px)}#smartAlertsBar .alert-item.danger,#smartAlertsBar .alert-item.critical{background:#fee2e2;border-color:#dc2626}#smartAlertsBar .alert-item.critical-pulse{animation:criticalItemPulse 2s infinite;border-width:2px}#smartAlertsBar .alert-item.warning,#smartAlertsBar .alert-item.high{background:#fef3c7;border-color:#d97706}#smartAlertsBar .alert-item.info,#smartAlertsBar .alert-item.medium{background:#dbeafe;border-color:#2563eb}#smartAlertsBar .alert-item.low{background:#f1f5f9;border-color:#64748b}#smartAlertsBar .alert-item.success{background:#dcfce7;border-color:#16a34a}@keyframes criticalItemPulse{0%,100%{box-shadow:0 0 0 0 rgba(220,38,38,0.4)}50%{box-shadow:0 0 0 8px rgba(220,38,38,0)}}#smartAlertsBar .alert-title{font-weight:700;font-size:14px;color:#1f2937;margin-bottom:4px}#smartAlertsBar .alert-msg{font-size:12px;color:#4b5563}#smartAlertsBar .alert-header{display:flex;justify-content:space-between;align-items:center;padding:8px 12px;border-bottom:1px solid #e5e7eb;margin-bottom:8px}#smartAlertsBar .alert-close{background:none;border:none;font-size:20px;cursor:pointer;color:#6b7280}#smartAlertsBar .alert-toggle .critical-badge{background:#fff;color:#dc2626;padding:2px 6px;border-radius:999px;font-size:10px;animation:blink 1s infinite}@keyframes blink{0%,100%{opacity:1}50%{opacity:0.5}}@media(max-width:768px){#smartAlertsBar{bottom:80px;left:10px;right:10px;max-width:none}}";
  },

  toggle: function() {
    var bar = document.getElementById('smartAlertsBar');
    if(bar) bar.classList.toggle('open');
  },

  _esc: function(v) {
    return String(v==null?'':v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }
};

window.SmartAlerts = SmartAlerts;

async function tryInit() {
  if(SmartAlerts._initialized || SmartAlerts._initInProgress) return true;
  try {
    var client = null;
    var user = null;
    
    // الأولوية: استخدام sbClient الموجود
    if(window.sbClient) {
      client = window.sbClient;
    }
    
    if(window.ME && window.ME.id) {
      user = window.ME;
    } else if(window.currentUser && window.currentUser.id) {
      user = window.currentUser;
    }
    
    // إذا لم نجد client، ننتظر فقط
    if(!client) return false;
    if(!user) {
      try {
        var sessionRes = await client.auth.getSession();
        var session = sessionRes.data.session;
        if(session) {
          var userRes = await client.from('users').select('*').eq('id', session.user.id).maybeSingle();
          if(userRes.data) user = userRes.data;
        }
      } catch(e) {}
    }
    
    if(client && user) {
      await SmartAlerts.init(client, user);
      return true;
    }
    return false;
  } catch(e) {
    console.error('🔔 SmartAlerts try-init error:', e);
    return false;
  }
}

function startSmartAlerts() {
  var attempts = 0;
  var maxAttempts = 10;
  var interval = setInterval(async function() {
    attempts++;
    if(SmartAlerts._initialized) { clearInterval(interval); return; }
    var success = await tryInit();
    if(success || attempts >= maxAttempts) {
      clearInterval(interval);
    }
  }, 2000);
}

if(document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', startSmartAlerts);
} else {
  startSmartAlerts();
}

})();

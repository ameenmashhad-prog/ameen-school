/* مدارس أمين الرضا (ع) — نظام التنبيهات الموحد v3 (مُصلَح)
   يعمل في كل البوابات بشكل صحيح */
(function(){
'use strict';

if(window.SmartAlerts && window.SmartAlerts._initialized) return;

var SmartAlerts = {
  _initialized: false,
  alerts: [],
  role: null,
  user: null,
  sb: null,

  init: async function(supabaseClient, currentUser) {
    if(!supabaseClient || !currentUser) {
      console.warn('🔔 SmartAlerts: missing client or user');
      return;
    }
    this.sb = supabaseClient;
    this.user = currentUser;
    this.role = currentUser.role || 'guest';
    this._initialized = true;
    
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
      
    } catch(e) {
      console.error('🔔 SmartAlerts error:', e);
    }
  },

  loadParentAlerts: async function() {
    var self = this;
    try {
      var childrenRes = await this.sb.from('students').select('id, users:user_id(name)').eq('parent_id', this.user.id);
      var children = childrenRes.data || [];
      
      if(!children.length) return;
      
      for(var i = 0; i < children.length; i++) {
        var child = children[i];
        var childName = (child.users && child.users.name) || 'الطالب';
        
        try {
          var attRes = await this.sb.from('attendance').select('status').eq('student_id', child.id).limit(30);
          var att = attRes.data || [];
          if(att.length) {
            var absent = att.filter(function(a){ return a.status === 'absent'; }).length;
            var rate = (absent/att.length)*100;
            if(rate > 20) self.alerts.push({
              type:'danger', icon:'⚠️',
              title:'غياب ' + childName,
              msg: Math.round(rate)+'% غياب',
              link:'parent.html'
            });
          }
        } catch(e) {}
        
        try {
          var feesRes = await this.sb.from('student_fees').select('net_amount, base_amount, total_paid').eq('student_id', child.id);
          var fees = feesRes.data || [];
          fees.forEach(function(f) {
            var remaining = (f.net_amount || f.base_amount || 0) - (f.total_paid || 0);
            if(remaining > 0) self.alerts.push({
              type:'warning', icon:'💰',
              title:'قسط ' + childName,
              msg:'متبقي $' + remaining,
              link:'parent.html'
            });
          });
        } catch(e) {}
      }
    } catch(e) { console.log('Parent alerts skip'); }
  },

  loadTeacherAlerts: async function() {
    try {
      var scheduleRes = await this.sb.from('weekly_schedule').select('class_id, subject_id').eq('teacher_id', this.user.id);
      var schedule = scheduleRes.data || [];
      
      if(schedule.length) {
        this.alerts.push({
          type:'info', icon:'📅',
          title:'جدولي الأسبوعي',
          msg: schedule.length + ' حصة',
          link:'teacher.html'
        });
      }
    } catch(e) { console.log('Teacher schedule alert skip'); }
    
    try {
      var todayDate = new Date().toISOString().slice(0,10);
      var attRes = await this.sb.from('attendance').select('id').eq('date', todayDate).limit(100);
      var att = attRes.data || [];
      if(att.length === 0) {
        this.alerts.push({
          type:'warning', icon:'📋',
          title:'لم تسجل حضور اليوم',
          msg:'سجل الحضور الآن',
          link:'teacher.html'
        });
      }
    } catch(e) { console.log('Teacher attendance alert skip'); }
  },

  loadStudentAlerts: async function() {
    var self = this;
    try {
      var studentRes = await this.sb.from('students').select('id').eq('user_id', this.user.id).maybeSingle();
      if(!studentRes.data) return;
      var sid = studentRes.data.id;
      
      try {
        var hwRes = await this.sb.from('v_student_homeworks').select('*').eq('student_id', sid).limit(20);
        var homeworks = hwRes.data || [];
        if(homeworks.length) {
          var nowDate = new Date();
          var upcoming = homeworks.filter(function(h) {
            if(h.status === 'submitted') return false;
            var due = new Date(h.due_date || h.due_at);
            var diff = (due - nowDate) / (1000*60*60*24);
            return diff >= 0 && diff <= 3;
          });
          
          if(upcoming.length > 0) self.alerts.push({
            type:'warning', icon:'📚',
            title:'واجبات قريبة',
            msg: upcoming.length + ' واجب خلال 3 أيام',
            link:'student.html'
          });
        }
      } catch(e) {}
      
      try {
        var examsRes = await this.sb.from('online_exams').select('*').limit(20);
        var exams = examsRes.data || [];
        if(exams.length) {
          var nowDate2 = new Date();
          var upcomingExams = exams.filter(function(e) {
            var start = new Date(e.starts_at || e.start_at);
            var diff = (start - nowDate2) / (1000*60*60*24);
            return diff >= 0 && diff <= 7;
          });
          
          if(upcomingExams.length > 0) self.alerts.push({
            type:'info', icon:'📝',
            title:'اختبارات قادمة',
            msg: upcomingExams.length + ' اختبار',
            link:'student.html'
          });
        }
      } catch(e) {}
      
      try {
        var attRes = await this.sb.from('attendance').select('status').eq('student_id', sid).limit(50);
        var att = attRes.data || [];
        if(att.length) {
          var absent = att.filter(function(a){ return a.status === 'absent'; }).length;
          var rate = (absent/att.length)*100;
          if(rate > 20) self.alerts.push({
            type:'danger', icon:'⚠️',
            title:'غيابك مرتفع',
            msg: Math.round(rate)+'% غياب',
            link:'student.html'
          });
        }
      } catch(e) {}
      
    } catch(e) { console.log('Student alerts skip'); }
  },

  loadCounselorAlerts: async function() {
    try {
      var studentsRes = await this.sb.from('students').select('id').limit(100);
      var students = studentsRes.data || [];
      if(students.length) {
        this.alerts.push({
          type:'info', icon:'👥',
          title:'الطلاب المتابعون',
          msg: students.length + ' طالب',
          link:'counselor.html'
        });
      }
    } catch(e) { console.log('Counselor alert skip'); }
    
    try {
      var behaviorRes = await this.sb.from('behavior_records').select('id, points').limit(100);
      var behavior = behaviorRes.data || [];
      if(behavior.length) {
        var negative = behavior.filter(function(b){ return Number(b.points) < 0; }).length;
        if(negative > 0) this.alerts.push({
          type:'warning', icon:'⚠️',
          title:'حالات سلوك سلبي',
          msg: negative + ' حالة تحتاج متابعة',
          link:'counselor.html'
        });
      }
    } catch(e) { console.log('Behavior alert skip'); }
  },

  loadAdminAlerts: async function() {
    try {
      var feesRes = await this.sb.from('student_fees').select('net_amount, base_amount, total_paid').limit(500);
      var fees = feesRes.data || [];
      if(fees.length) {
        var totalDue = fees.reduce(function(s,f){ 
          return s + Math.max((f.net_amount || f.base_amount || 0) - (f.total_paid || 0), 0); 
        }, 0);
        if(totalDue > 0) this.alerts.push({
          type:'danger', icon:'💰',
          title:'متأخرات مالية',
          msg:'$' + Math.round(totalDue).toLocaleString(),
          link:'finance-pro.html'
        });
      }
    } catch(e) { console.log('Admin fees alert skip'); }
    
    try {
      var studentsRes = await this.sb.from('students').select('id').limit(1000);
      var students = studentsRes.data || [];
      if(students.length > 0) {
        this.alerts.push({
          type:'info', icon:'🎓',
          title:'إجمالي الطلاب',
          msg: students.length + ' طالب',
          link:'super-admin.html'
        });
      }
    } catch(e) {}
    
    try {
      var todayStr = new Date().toISOString().slice(0,10);
      var attRes = await this.sb.from('attendance').select('id').eq('date', todayStr).eq('status', 'absent').limit(100);
      var att = attRes.data || [];
      if(att.length > 0) {
        this.alerts.push({
          type:'warning', icon:'⚠️',
          title:'غيابات اليوم',
          msg: att.length + ' غياب',
          link:'super-admin.html'
        });
      }
    } catch(e) {}
    
    try {
      var regsRes = await this.sb.from('registrations').select('id').eq('status', 'pending').limit(50);
      var regs = regsRes.data || [];
      if(regs.length > 0) {
        this.alerts.push({
          type:'info', icon:'📋',
          title:'تسجيلات جديدة',
          msg: regs.length + ' طلب بانتظار المراجعة',
          link:'registrations-admin.html'
        });
      }
    } catch(e) {}
  },

  loadFinanceAlerts: async function() {
    try {
      var feesRes = await this.sb.from('student_fees').select('*').limit(500);
      var fees = feesRes.data || [];
      if(fees.length) {
        var overdue = fees.filter(function(f) {
          var remaining = (f.net_amount || f.base_amount || 0) - (f.total_paid || 0);
          return remaining > 0;
        }).length;
        
        if(overdue > 0) this.alerts.push({
          type:'warning', icon:'💰',
          title: overdue + ' طالب متأخر',
          msg:'يحتاج متابعة',
          link:'finance-collections.html'
        });
      }
    } catch(e) { console.log('Finance alert skip'); }
  },

  loadNotifications: async function() {
    try {
      var notifsRes = await this.sb.from('school_notifications').select('*').eq('recipient_user_id', this.user.id).is('read_at', null).order('created_at', {ascending: false}).limit(5);
      var notifs = notifsRes.data || [];
      
      if(notifs.length > 0) {
        this.alerts.unshift({
          type:'info', icon:'🔔',
          title: notifs.length + ' إشعار جديد',
          msg: notifs[0].title || 'تنبيه',
          link:'notifications.html'
        });
      }
    } catch(e) {}
  },

  render: function() {
    var old = document.getElementById('smartAlertsBar');
    if(old) old.remove();
    
    if(!this.alerts.length) {
      console.log('🔔 No alerts - showing minimal button');
      this.renderEmptyBar();
      return;
    }
    
    var bar = document.createElement('div');
    bar.id = 'smartAlertsBar';
    bar.innerHTML = this._buildHTML();
    document.body.appendChild(bar);
  },

  renderEmptyBar: function() {
    var bar = document.createElement('div');
    bar.id = 'smartAlertsBar';
    bar.innerHTML = 
      '<style>' + this._buildCSS() + '</style>' +
      '<div class="alert-toggle" onclick="SmartAlerts.toggle()" style="background:linear-gradient(135deg,#10b981,#059669);">' +
        '<span style="font-size:20px;">✅</span>' +
        '<span>كل شيء طبيعي</span>' +
      '</div>' +
      '<div class="alerts-panel">' +
        '<div class="alert-header">' +
          '<b style="color:#1f2937;">✅ لا توجد تنبيهات</b>' +
          '<button class="alert-close" onclick="SmartAlerts.toggle()">×</button>' +
        '</div>' +
        '<div style="padding:30px;text-align:center;color:#666;">' +
          '<div style="font-size:48px;">🎉</div>' +
          '<p style="margin-top:12px;">كل شيء على ما يرام!</p>' +
        '</div>' +
      '</div>';
    document.body.appendChild(bar);
  },

  _buildHTML: function() {
    var self = this;
    var css = this._buildCSS();
    var itemsHTML = this.alerts.map(function(a) {
      return '<div class="alert-item ' + a.type + '" onclick="' + (a.link ? "location.href='" + a.link + "'" : '') + '">' +
        '<div class="alert-title">' + a.icon + ' ' + self._esc(a.title) + '</div>' +
        '<div class="alert-msg">' + self._esc(a.msg) + '</div>' +
      '</div>';
    }).join('');

    return '<style>' + css + '</style>' +
      '<div class="alerts-panel">' +
        '<div class="alert-header">' +
          '<b style="color:#1f2937;">🔔 التنبيهات (' + this.alerts.length + ')</b>' +
          '<button class="alert-close" onclick="SmartAlerts.toggle()">×</button>' +
        '</div>' +
        itemsHTML +
      '</div>' +
      '<div class="alert-toggle" onclick="SmartAlerts.toggle()">' +
        '<span style="font-size:20px;">🔔</span>' +
        '<span>التنبيهات</span>' +
        '<span class="alert-count">' + this.alerts.length + '</span>' +
      '</div>';
  },

  _buildCSS: function() {
    return [
      '#smartAlertsBar {',
        'position: fixed;',
        'bottom: 20px;',
        'left: 20px;',
        'z-index: 99999;',
        'max-width: 320px;',
        "font-family: 'Cairo', 'Segoe UI', Tahoma, sans-serif;",
        'direction: rtl;',
      '}',
      '#smartAlertsBar .alert-toggle {',
        'background: linear-gradient(135deg,#ef4444,#dc2626);',
        'color: white;',
        'padding: 12px 16px;',
        'border-radius: 12px;',
        'cursor: pointer;',
        'box-shadow: 0 8px 24px rgba(239,68,68,0.4);',
        'display: flex;',
        'align-items: center;',
        'gap: 10px;',
        'font-weight: bold;',
        'transition: transform 0.2s;',
        'user-select: none;',
      '}',
      '#smartAlertsBar .alert-toggle:hover { transform: translateY(-2px); }',
      '#smartAlertsBar .alert-count {',
        'background: white;',
        'color: #dc2626;',
        'border-radius: 999px;',
        'padding: 2px 10px;',
        'font-size: 12px;',
        'font-weight: bold;',
      '}',
      '#smartAlertsBar .alerts-panel {',
        'display: none;',
        'background: white;',
        'border-radius: 12px;',
        'box-shadow: 0 12px 40px rgba(0,0,0,0.3);',
        'margin-bottom: 10px;',
        'max-height: 70vh;',
        'overflow-y: auto;',
        'padding: 12px;',
        'color: #1f2937;',
      '}',
      '#smartAlertsBar.open .alerts-panel { display: block; }',
      '#smartAlertsBar .alert-item {',
        'padding: 12px;',
        'border-radius: 8px;',
        'margin-bottom: 8px;',
        'cursor: pointer;',
        'transition: background 0.2s;',
        'border-right: 4px solid;',
      '}',
      '#smartAlertsBar .alert-item:hover { background: #f3f4f6; }',
      '#smartAlertsBar .alert-item.danger { background: #fee2e2; border-color: #dc2626; }',
      '#smartAlertsBar .alert-item.warning { background: #fef3c7; border-color: #d97706; }',
      '#smartAlertsBar .alert-item.info { background: #dbeafe; border-color: #2563eb; }',
      '#smartAlertsBar .alert-title {',
        'font-weight: bold;',
        'font-size: 14px;',
        'color: #1f2937;',
        'margin-bottom: 4px;',
      '}',
      '#smartAlertsBar .alert-msg { font-size: 12px; color: #4b5563; }',
      '#smartAlertsBar .alert-header {',
        'display: flex;',
        'justify-content: space-between;',
        'align-items: center;',
        'padding: 8px 12px;',
        'border-bottom: 1px solid #e5e7eb;',
        'margin-bottom: 8px;',
      '}',
      '#smartAlertsBar .alert-close {',
        'background: none;',
        'border: none;',
        'font-size: 20px;',
        'cursor: pointer;',
        'color: #6b7280;',
      '}',
      '@media (max-width: 768px) {',
        '#smartAlertsBar {',
          'bottom: 80px;',
          'left: 10px;',
          'right: 10px;',
          'max-width: none;',
        '}',
      '}'
    ].join('\n');
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
  if(SmartAlerts._initialized) return true;
  
  try {
    var client = null;
    var user = null;
    
    if(window.ME && window.ME.id) {
      user = window.ME;
    }
    
    if(window.currentUser && window.currentUser.id) {
      user = window.currentUser;
    }
    
    if(window.supabase && window.AMIN_CONFIG) {
      var tempClient = window.supabase.createClient(
        window.AMIN_CONFIG.supabaseUrl,
        window.AMIN_CONFIG.supabaseAnonKey,
        {auth:{persistSession:true, autoRefreshToken:true, storageKey:(window.AMIN_CONFIG.authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}}
      );
      
      if(!user) {
        var sessionRes = await tempClient.auth.getSession();
        var session = sessionRes.data.session;
        if(session) {
          var userRes = await tempClient.from('users').select('*').eq('id', session.user.id).maybeSingle();
          if(userRes.data) user = userRes.data;
        }
      }
      
      if(user) {
        client = tempClient;
        await SmartAlerts.init(client, user);
        return true;
      }
    }
    
    return false;
  } catch(e) {
    console.error('🔔 SmartAlerts try-init error:', e);
    return false;
  }
}

function startSmartAlerts() {
  var attempts = 0;
  var maxAttempts = 15;
  
  var interval = setInterval(async function() {
    attempts++;
    
    if(SmartAlerts._initialized) {
      clearInterval(interval);
      return;
    }
    
    var success = await tryInit();
    
    if(success || attempts >= maxAttempts) {
      clearInterval(interval);
      if(!success) console.log('🔔 SmartAlerts: max attempts reached');
    }
  }, 1500);
}

if(document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', startSmartAlerts);
} else {
  startSmartAlerts();
}

window.addEventListener('load', function() {
  setTimeout(function() {
    if(!SmartAlerts._initialized) tryInit();
  }, 2500);
});

})();

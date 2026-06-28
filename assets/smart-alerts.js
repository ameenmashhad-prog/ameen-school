/* مدارس أمين الرضا (ع) — نظام التنبيهات الموحد
   يعمل في كل البوابات: parent, teacher, student, counselor, super-admin, portal */
(function(){
'use strict';

if(window.SmartAlerts) return; // منع التكرار

const SmartAlerts = {
  alerts: [],
  role: null,
  user: null,
  sb: null,

  // ========== التهيئة ==========
  async init(supabaseClient, currentUser) {
    if(!supabaseClient || !currentUser) {
      console.warn('SmartAlerts: missing client or user');
      return;
    }
    this.sb = supabaseClient;
    this.user = currentUser;
    this.role = currentUser.role || 'guest';
    
    console.log('🔔 SmartAlerts initialized for role:', this.role);
    
    await this.loadAlerts();
    this.render();
  },

  // ========== جلب التنبيهات حسب الدور ==========
  async loadAlerts() {
    this.alerts = [];
    
    try {
      if(this.role === 'parent') await this.loadParentAlerts();
      else if(this.role === 'teacher') await this.loadTeacherAlerts();
      else if(this.role === 'student') await this.loadStudentAlerts();
      else if(this.role === 'counselor' || this.role === 'psychologist') await this.loadCounselorAlerts();
      else if(this.role === 'admin' || this.user.is_super_admin) await this.loadAdminAlerts();
      else if(this.role === 'finance') await this.loadFinanceAlerts();
      
      // الإشعارات لكل المستخدمين
      await this.loadNotifications();
      
    } catch(e) {
      console.error('SmartAlerts error:', e);
    }
  },

  // ========== تنبيهات ولي الأمر ==========
  async loadParentAlerts() {
    const { data: children } = await this.sb.from('students')
      .select('id, users:user_id(name)')
      .eq('parent_id', this.user.id);
    
    if(!children || !children.length) return;
    
    for(const child of children) {
      const childName = child.users?.name || 'الطالب';
      
      // غياب
      const { data: att } = await this.sb.from('attendance')
        .select('status').eq('student_id', child.id).limit(30);
      if(att && att.length) {
        const absent = att.filter(a => a.status === 'absent').length;
        const rate = (absent/att.length)*100;
        if(rate > 20) this.alerts.push({
          type:'danger', icon:'⚠️',
          title:`غياب ${childName}`,
          msg:`${Math.round(rate)}% غياب`,
          link:'parent.html'
        });
      }
      
      // أقساط
      const { data: fees } = await this.sb.from('student_fees')
        .select('net_amount, base_amount, total_paid').eq('student_id', child.id);
      if(fees) fees.forEach(f => {
        const remaining = (f.net_amount || f.base_amount || 0) - (f.total_paid || 0);
        if(remaining > 0) this.alerts.push({
          type:'warning', icon:'💰',
          title:`قسط ${childName}`,
          msg:`متبقي $${remaining}`,
          link:'parent.html'
        });
      });
    }
  },

  // ========== تنبيهات المعلم ==========
  async loadTeacherAlerts() {
    // طلاب لم يحضروا اليوم
    const today = new Date().toISOString().slice(0,10);
    const { data: schedule } = await this.sb.from('weekly_schedule')
      .select('class_id').eq('teacher_id', this.user.id);
    
    if(schedule && schedule.length) {
      const classIds = [...new Set(schedule.map(s => s.class_id))];
      
      // الواجبات المتأخرة في التصحيح
      const { data: homeworks } = await this.sb.from('v_student_homeworks')
        .select('*').limit(100);
      
      if(homeworks) {
        const pending = homeworks.filter(h => h.status === 'submitted' && !h.graded_at).length;
        if(pending > 0) this.alerts.push({
          type:'warning', icon:'📝',
          title:'واجبات بانتظار التصحيح',
          msg:`${pending} واجب يحتاج تقييم`,
          link:'homework-reports.html'
        });
      }
    }
  },

  // ========== تنبيهات الطالب ==========
  async loadStudentAlerts() {
    // الواجبات القادمة
    const { data: homeworks } = await this.sb.from('v_student_homeworks')
      .select('*').limit(20);
    
    if(homeworks) {
      const today = new Date();
      const upcoming = homeworks.filter(h => {
        if(h.status === 'submitted') return false;
        const due = new Date(h.due_date || h.due_at);
        const diff = (due - today) / (1000*60*60*24);
        return diff >= 0 && diff <= 3;
      });
      
      if(upcoming.length > 0) this.alerts.push({
        type:'warning', icon:'📚',
        title:'واجبات قريبة',
        msg:`${upcoming.length} واجب خلال 3 أيام`,
        link:'student-homeworks.html'
      });
    }
    
    // الاختبارات القادمة
    const { data: exams } = await this.sb.from('online_exams')
      .select('*').limit(20);
    
    if(exams) {
      const today = new Date();
      const upcoming = exams.filter(e => {
        const start = new Date(e.starts_at || e.start_at);
        const diff = (start - today) / (1000*60*60*24);
        return diff >= 0 && diff <= 7;
      });
      
      if(upcoming.length > 0) this.alerts.push({
        type:'info', icon:'📝',
        title:'اختبارات قادمة',
        msg:`${upcoming.length} اختبار هذا الأسبوع`,
        link:'online-exams.html'
      });
    }
  },

  // ========== تنبيهات المرشد ==========
  async loadCounselorAlerts() {
    // طلبات مواعيد
    const { data: requests } = await this.sb.from('counseling_session_requests')
      .select('*').eq('status', 'pending').limit(20);
    
    if(requests && requests.length > 0) {
      this.alerts.push({
        type:'warning', icon:'📅',
        title:'طلبات مواعيد جديدة',
        msg:`${requests.length} طلب بانتظار الموافقة`,
        link:'counselor.html'
      });
    }
  },

  // ========== تنبيهات المدير ==========
  async loadAdminAlerts() {
    // تسجيلات جديدة
    const { data: regs } = await this.sb.from('registrations')
      .select('id').eq('status', 'pending').limit(50);
    
    if(regs && regs.length > 0) {
      this.alerts.push({
        type:'info', icon:'📋',
        title:'تسجيلات بانتظار المراجعة',
        msg:`${regs.length} طلب جديد`,
        link:'registrations-admin.html'
      });
    }
    
    // إجمالي المتأخرات المالية
    const { data: fees } = await this.sb.from('student_fees').select('net_amount, base_amount, total_paid').limit(500);
    if(fees) {
      const totalDue = fees.reduce((s,f) => s + Math.max((f.net_amount || f.base_amount || 0) - (f.total_paid || 0), 0), 0);
      if(totalDue > 0) this.alerts.push({
        type:'danger', icon:'💰',
        title:'متأخرات مالية',
        msg:`$${Math.round(totalDue).toLocaleString()}`,
        link:'finance-pro.html'
      });
    }
  },

  // ========== تنبيهات المالية ==========
  async loadFinanceAlerts() {
    const { data: fees } = await this.sb.from('student_fees').select('*').limit(500);
    if(fees) {
      const overdue = fees.filter(f => {
        const remaining = (f.net_amount || f.base_amount || 0) - (f.total_paid || 0);
        return remaining > 0;
      }).length;
      
      if(overdue > 0) this.alerts.push({
        type:'warning', icon:'💰',
        title:`${overdue} طالب لديهم متأخرات`,
        msg:'يحتاج متابعة',
        link:'finance-collections.html'
      });
    }
  },

  // ========== الإشعارات العامة ==========
  async loadNotifications() {
    const { data: notifs } = await this.sb.from('school_notifications')
      .select('*')
      .eq('recipient_user_id', this.user.id)
      .is('read_at', null)
      .order('created_at', {ascending: false})
      .limit(5);
    
    if(notifs && notifs.length > 0) {
      this.alerts.unshift({
        type:'info', icon:'🔔',
        title:`${notifs.length} إشعار جديد`,
        msg:notifs[0].title || 'تنبيه',
        link:'notifications.html',
        priority: true
      });
    }
  },

  // ========== عرض شريط التنبيهات ==========
  render() {
    if(!this.alerts.length) {
      console.log('🔔 No alerts to display');
      return;
    }
    
    // حذف القديم إن وجد
    document.getElementById('smartAlertsBar')?.remove();
    
    const bar = document.createElement('div');
    bar.id = 'smartAlertsBar';
    bar.innerHTML = `
      <style>
        #smartAlertsBar {
          position: fixed;
          bottom: 20px;
          left: 20px;
          z-index: 9999;
          max-width: 320px;
          font-family: inherit;
        }
        #smartAlertsBar .alert-toggle {
          background: linear-gradient(135deg,#ef4444,#dc2626);
          color: white;
          padding: 12px 16px;
          border-radius: 12px;
          cursor: pointer;
          box-shadow: 0 8px 24px rgba(239,68,68,0.4);
          display: flex;
          align-items: center;
          gap: 10px;
          font-weight: bold;
          transition: transform 0.2s;
        }
        #smartAlertsBar .alert-toggle:hover {
          transform: translateY(-2px);
        }
        #smartAlertsBar .alert-count {
          background: white;
          color: #dc2626;
          border-radius: 999px;
          padding: 2px 10px;
          font-size: 12px;
          font-weight: bold;
        }
        #smartAlertsBar .alerts-panel {
          display: none;
          background: white;
          border-radius: 12px;
          box-shadow: 0 12px 40px rgba(0,0,0,0.3);
          margin-bottom: 10px;
          max-height: 70vh;
          overflow-y: auto;
          padding: 12px;
        }
        #smartAlertsBar.open .alerts-panel {
          display: block;
        }
        #smartAlertsBar .alert-item {
          padding: 12px;
          border-radius: 8px;
          margin-bottom: 8px;
          cursor: pointer;
          transition: background 0.2s;
          border-right: 4px solid;
        }
        #smartAlertsBar .alert-item:hover {
          background: #f3f4f6;
        }
        #smartAlertsBar .alert-item.danger {
          background: #fee2e2;
          border-color: #dc2626;
        }
        #smartAlertsBar .alert-item.warning {
          background: #fef3c7;
          border-color: #d97706;
        }
        #smartAlertsBar .alert-item.info {
          background: #dbeafe;
          border-color: #2563eb;
        }
        #smartAlertsBar .alert-title {
          font-weight: bold;
          font-size: 14px;
          color: #1f2937;
          margin-bottom: 4px;
        }
        #smartAlertsBar .alert-msg {
          font-size: 12px;
          color: #4b5563;
        }
        #smartAlertsBar .alert-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 8px 12px;
          border-bottom: 1px solid #e5e7eb;
          margin-bottom: 8px;
        }
        #smartAlertsBar .alert-close {
          background: none;
          border: none;
          font-size: 20px;
          cursor: pointer;
          color: #6b7280;
        }
      </style>
      
      <div class="alerts-panel">
        <div class="alert-header">
          <b style="color:#1f2937;">🔔 التنبيهات (${this.alerts.length})</b>
          <button class="alert-close" onclick="SmartAlerts.toggle()">×</button>
        </div>
        ${this.alerts.map(a => `
          <div class="alert-item ${a.type}" onclick="${a.link ? `location.href='${a.link}'` : ''}">
            <div class="alert-title">${a.icon} ${this._esc(a.title)}</div>
            <div class="alert-msg">${this._esc(a.msg)}</div>
          </div>
        `).join('')}
      </div>
      
      <div class="alert-toggle" onclick="SmartAlerts.toggle()">
        <span style="font-size:20px;">🔔</span>
        <span>التنبيهات</span>
        <span class="alert-count">${this.alerts.length}</span>
      </div>
    `;
    
    document.body.appendChild(bar);
  },

  toggle() {
    document.getElementById('smartAlertsBar')?.classList.toggle('open');
  },

  _esc(v) {
    return String(v==null?'':v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }
};

window.SmartAlerts = SmartAlerts;

// ========== تشغيل تلقائي ==========
window.addEventListener('load', () => {
  setTimeout(async () => {
    try {
      // محاولة الحصول على Supabase client و user من البيئة
      let client = null;
      let user = null;
      
      // محاولة 1: من AminPortal (portal.html, student.html, teacher.html, etc.)
      if(window.AminPortal && window.supabase && window.AMIN_CONFIG) {
        const tempClient = window.supabase.createClient(
          window.AMIN_CONFIG.supabaseUrl,
          window.AMIN_CONFIG.supabaseAnonKey,
          {auth:{persistSession:true, storageKey:(window.AMIN_CONFIG.authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}}
        );
        const { data: { session } } = await tempClient.auth.getSession();
        if(session) {
          const { data: u } = await tempClient.from('users').select('*').eq('id', session.user.id).maybeSingle();
          if(u) {
            client = tempClient;
            user = u;
          }
        }
      }
      
      // محاولة 2: من ParentPortal أو غيرها
      if(!user && window.ME) {
        user = window.ME;
      }
      
      if(client && user) {
        await SmartAlerts.init(client, user);
      } else {
        console.log('🔔 SmartAlerts: waiting for user context...');
      }
    } catch(e) {
      console.error('🔔 SmartAlerts auto-init failed:', e);
    }
  }, 1500); // انتظار 1.5 ثانية لتحميل كل شيء
});

})();

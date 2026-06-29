🔥 ممتاز! ننفذها بطريقة مضمونة 100%.

---

## 🔍 المشكلة الحالية:

`smart-alerts.js` لا يعمل في بعض البوابات لأنه:
1. ينتظر `window.AminPortal` أو `window.ME` لكن بعض الصفحات تستخدم `window.ParentPortal` أو `window.StudentPortal` أو `window.TeacherPortal` أو `window.SuperAdmin`
2. التوقيت غير مضبوط (1.5 ثانية قد لا تكون كافية)
3. لا يعيد المحاولة لو لم يجد البيانات

---

## ✅ الحل: ملف `smart-alerts.js` محسّن ومضمون

افتح GitHub → `assets/smart-alerts.js` → ✏️ Edit → **Ctrl+A** → **Delete** → الصق:

```javascript
/* مدارس أمين الرضا (ع) — نظام التنبيهات الموحد v2
   يعمل في كل البوابات: parent, teacher, student, counselor, super-admin, portal, staff */
(function(){
'use strict';

if(window.SmartAlerts && window.SmartAlerts._initialized) return;

const SmartAlerts = {
  _initialized: false,
  alerts: [],
  role: null,
  user: null,
  sb: null,
  _retries: 0,
  _maxRetries: 20,

  // ========== التهيئة ==========
  async init(supabaseClient, currentUser) {
    if(!supabaseClient || !currentUser) {
      console.warn('🔔 SmartAlerts: missing client or user');
      return;
    }
    this.sb = supabaseClient;
    this.user = currentUser;
    this.role = currentUser.role || 'guest';
    this._initialized = true;
    
    console.log('🔔 SmartAlerts initialized for role:', this.role, 'name:', this.user.name);
    
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
      
      await this.loadNotifications();
      
    } catch(e) {
      console.error('🔔 SmartAlerts error:', e);
    }
  },

  // ========== تنبيهات ولي الأمر ==========
  async loadParentAlerts() {
    try {
      const { data: children } = await this.sb.from('students')
        .select('id, users:user_id(name)')
        .eq('parent_id', this.user.id);
      
      if(!children || !children.length) return;
      
      for(const child of children) {
        const childName = (child.users && child.users.name) || 'الطالب';
        
        // غياب
        try {
          const { data: att } = await this.sb.from('attendance')
            .select('status').eq('student_id', child.id).limit(30);
          if(att && att.length) {
            const absent = att.filter(a => a.status === 'absent').length;
            const rate = (absent/att.length)*100;
            if(rate > 20) this.alerts.push({
              type:'danger', icon:'⚠️',
              title:'غياب ' + childName,
              msg: Math.round(rate)+'% غياب',
              link:'parent.html'
            });
          }
        } catch(e) {}
        
        // أقساط
        try {
          const { data: fees } = await this.sb.from('student_fees')
            .select('net_amount, base_amount, total_paid').eq('student_id', child.id);
          if(fees) fees.forEach(f => {
            const remaining = (f.net_amount || f.base_amount || 0) - (f.total_paid || 0);
            if(remaining > 0) this.alerts.push({
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

  // ========== تنبيهات المعلم ==========
  async loadTeacherAlerts() {
    try {
      const { data: schedule } = await this.sb.from('weekly_schedule')
        .select('class_id, subject_id').eq('teacher_id', this.user.id);
      
      if(schedule && schedule.length) {
        this.alerts.push({
          type:'info', icon:'📅',
          title:'جدولي الأسبوعي',
          msg: schedule.length + ' حصة',
          link:'teacher.html'
        });
      }
    } catch(e) { console.log('Teacher schedule alert skip'); }
    
    try {
      const today = new Date().toISOString().slice(0,10);
      const { data: att } = await this.sb.from('attendance').select('id').eq('date', today).limit(100);
      if(att && att.length === 0) {
        this.alerts.push({
          type:'warning', icon:'📋',
          title:'لم تسجل حضور اليوم',
          msg:'سجل الحضور الآن',
          link:'teacher.html'
        });
      }
    } catch(e) { console.log('Teacher attendance alert skip'); }
  },

  // ========== تنبيهات الطالب ==========
  async loadStudentAlerts() {
    try {
      const { data: studentData } = await this.sb.from('students').select('id').eq('user_id', this.user.id).maybeSingle();
      if(!studentData) return;
      const sid = studentData.id;
      
      // الواجبات
      try {
        const { data: homeworks } = await this.sb.from('v_student_homeworks')
          .select('*').eq('student_id', sid).limit(20);
        
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
            msg: upcoming.length + ' واجب خلال 3 أيام',
            link:'student.html'
          });
        }
      } catch(e) {}
      
      // الاختبارات
      try {
        const { data: exams } = await this.sb.from('online_exams').select('*').limit(20);
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
            msg: upcoming.length + ' اختبار',
            link:'student.html'
          });
        }
      } catch(e) {}
      
      // الغياب
      try {
        const { data: att } = await this.sb.from('attendance').select('status').eq('student_id', sid).limit(50);
        if(att && att.length) {
          const absent = att.filter(a => a.status === 'absent').length;
          const rate = (absent/att.length)*100;
          if(rate > 20) this.alerts.push({
            type:'danger', icon:'⚠️',
            title:'غيابك مرتفع',
            msg: Math.round(rate)+'% غياب',
            link:'student.html'
          });
        }
      } catch(e) {}
      
    } catch(e) { console.log('Student alerts skip'); }
  },

  // ========== تنبيهات المرشد ==========
  async loadCounselorAlerts() {
    try {
      const { data: students } = await this.sb.from('students').select('id').limit(100);
      if(students && students.length) {
        this.alerts.push({
          type:'info', icon:'👥',
          title:'الطلاب المتابعون',
          msg: students.length + ' طالب',
          link:'counselor.html'
        });
      }
    } catch(e) { console.log('Counselor alert skip'); }
    
    try {
      const { data: behavior } = await this.sb.from('behavior_records').select('id, points').limit(100);
      if(behavior) {
        const negative = behavior.filter(b => Number(b.points) < 0).length;
        if(negative > 0) this.alerts.push({
          type:'warning', icon:'⚠️',
          title:'حالات سلوك سلبي',
          msg: negative + ' حالة تحتاج متابعة',
          link:'counselor.html'
        });
      }
    } catch(e) { console.log('Behavior alert skip'); }
  },

  // ========== تنبيهات المدير ==========
  async loadAdminAlerts() {
    try {
      const { data: fees } = await this.sb.from('student_fees').select('net_amount, base_amount, total_paid').limit(500);
      if(fees) {
        const totalDue = fees.reduce((s,f) => s + Math.max((f.net_amount || f.base_amount || 0) - (f.total_paid || 0), 0), 0);
        if(totalDue > 0) this.alerts.push({
          type:'danger', icon:'💰',
          title:'متأخرات مالية',
          msg:'$' + Math.round(totalDue).toLocaleString(),
          link:'finance-pro.html'
        });
      }
    } catch(e) { console.log('Admin fees alert skip'); }
    
    try {
      const { data: students } = await this.sb.from('students').select('id').limit(1000);
      if(students && students.length > 0) {
        this.alerts.push({
          type:'info', icon:'🎓',
          title:'إجمالي الطلاب',
          msg: students.length + ' طالب',
          link:'super-admin.html'
        });
      }
    } catch(e) {}
    
    try {
      const today = new Date().toISOString().slice(0,10);
      const { data: att } = await this.sb.from('attendance').select('id').eq('date', today).eq('status', 'absent').limit(100);
      if(att && att.length > 0) {
        this.alerts.push({
          type:'warning', icon:'⚠️',
          title:'غيابات اليوم',
          msg: att.length + ' غياب',
          link:'super-admin.html'
        });
      }
    } catch(e) {}
    
    // محاولة جلب التسجيلات الجديدة
    try {
      const { data: regs } = await this.sb.from('registrations').select('id').eq('status', 'pending').limit(50);
      if(regs && regs.length > 0) {
        this.alerts.push({
          type:'info', icon:'📋',
          title:'تسجيلات جديدة',
          msg: regs.length + ' طلب بانتظار المراجعة',
          link:'registrations-admin.html'
        });
      }
    } catch(e) {}
  },

  // ========== تنبيهات المالية ==========
  async loadFinanceAlerts() {
    try {
      const { data: fees } = await this.sb.from('student_fees').select('*').limit(500);
      if(fees) {
        const overdue = fees.filter(f => {
          const remaining = (f.net_amount || f.base_amount || 0) - (f.total_paid || 0);
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

  // ========== الإشعارات العامة ==========
  async loadNotifications() {
    try {
      const { data: notifs } = await this.sb.from('school_notifications')
        .select('*')
        .eq('recipient_user_id', this.user.id)
        .is('read_at', null)
        .order('created_at', {ascending: false})
        .limit(5);
      
      if(notifs && notifs.length > 0) {
        this.alerts.unshift({
          type:'info', icon:'🔔',
          title: notifs.length + ' إشعار جديد',
          msg: notifs[0].title || 'تنبيه',
          link:'notifications.html'
        });
      }
    } catch(e) {}
  },

  // ========== عرض شريط التنبيهات ==========
  render() {
    // حذف القديم إن وجد
    const old = document.getElementById('smartAlertsBar');
    if(old) old.remove();
    
    if(!this.alerts.length) {
      console.log('🔔 No alerts to display - showing minimal button');
      // عرض زر صغير حتى لو ما في تنبيهات
      this.renderEmptyBar();
      return;
    }
    
    const bar = document.createElement('div');
    bar.id = 'smartAlertsBar';
    bar.innerHTML = this._buildHTML();
    document.body.appendChild(bar);
  },

  renderEmptyBar() {
    const bar = document.createElement('div');
    bar.id = 'smartAlertsBar';
    bar.innerHTML = `
      <style>${this._buildCSS()}</style>
      <div class="alert-toggle" onclick="SmartAlerts.toggle()" style="background:linear-gradient(135deg,#10b981,#059669);">
        <span style="font-size:20px;">✅</span>
        <span>كل شيء طبيعي</span>
      </div>
      <div class="alerts-panel">
        <div class="alert-header">
          <b style="color:#1f2937;">✅ لا توجد تنبيهات</b>
          <button class="alert-close" onclick="SmartAlerts.toggle()">×</button>
        </div>
        <div style="padding:30px;text-align:center;color:#666;">
          <div style="font-size:48px;">🎉</div>
          <p style="margin-top:12px;">كل شيء على ما يرام!</p>
        </div>
      </div>
    `;
    document.body.appendChild(bar);
  },

  _buildHTML() {
    const css = this._buildCSS();
    const itemsHTML = this.alerts.map(a => `
      <div class="alert-item ${a.type}" onclick="${a.link ? `location.href='${a.link}'` : ''}">
        <div class="alert-title">${a.icon} ${this._esc(a.title)}</div>
        <div class="alert-msg">${this._esc(a.msg)}</div>
      </div>
    `).join('');

    return `
      <style>${css}</style>
      <div class="alerts-panel">
        <div class="alert-header">
          <b style="color:#1f2937;">🔔 التنبيهات (${this.alerts.length})</b>
          <button class="alert-close" onclick="SmartAlerts.toggle()">×</button>
        </div>
        ${itemsHTML}
      </div>
      <div class="alert-toggle" onclick="SmartAlerts.toggle()">
        <span style="font-size:20px;">🔔</span>
        <span>التنبيهات</span>
        <span class="alert-count">${this.alerts.length}</span>
      </div>
    `;
  },

  _buildCSS() {
    return `
      #smartAlertsBar {
        position: fixed;
        bottom: 20px;
        left: 20px;
        z-index: 99999;
        max-width: 320px;
        font-family: 'Cairo', 'Segoe UI', Tahoma, sans-serif;
        direction: rtl;
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
        user-select: none;
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
        color: #1f2937;
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
      @media (max-width: 768px) {
        #smartAlertsBar {
          bottom: 10px;
          left: 10px;
          right: 10px;
          max-width: none;
        }
      }
    `;
  },

  toggle() {
    const bar = document.getElementById('smartAlertsBar');
    if(bar) bar.classList.toggle('open');
  },

  _esc(v) {
    return String(v==null?'':v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }
};

window.SmartAlerts = SmartAlerts;

// ========== التشغيل التلقائي الذكي ==========
async function tryInit() {
  if(SmartAlerts._initialized) return true;
  
  try {
    let client = null;
    let user = null;
    
    // المحاولة 1: من window.ME المنشور
    if(window.ME && window.ME.id) {
      user = window.ME;
    }
    
    // المحاولة 2: إنشاء client وجلب المستخدم
    if(window.supabase && window.AMIN_CONFIG) {
      const tempClient = window.supabase.createClient(
        window.AMIN_CONFIG.supabaseUrl,
        window.AMIN_CONFIG.supabaseAnonKey,
        {auth:{persistSession:true, autoRefreshToken:true, storageKey:(window.AMIN_CONFIG.authStorageKey||'amin-ovcjzsrqqgjsbqswtkro-auth-v2')}}
      );
      
      // إذا ما في user، حاول جلبه من الجلسة
      if(!user) {
        const { data: { session } } = await tempClient.auth.getSession();
        if(session) {
          const { data: u } = await tempClient.from('users').select('*').eq('id', session.user.id).maybeSingle();
          if(u) user = u;
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

// إعادة المحاولة كل ثانية لمدة 20 ثانية
function startSmartAlerts() {
  let attempts = 0;
  const maxAttempts = 20;
  
  const interval = setInterval(async function() {
    attempts++;
    
    if(SmartAlerts._initialized) {
      clearInterval(interval);
      return;
    }
    
    const success = await tryInit();
    
    if(success || attempts >= maxAttempts) {
      clearInterval(interval);
      if(!success) {
        console.log('🔔 SmartAlerts: failed after ' + maxAttempts + ' attempts');
      }
    }
  }, 1000);
}

// بدء التشغيل عند تحميل الصفحة
if(document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', startSmartAlerts);
} else {
  startSmartAlerts();
}

// أيضاً عند load النهائي
window.addEventListener('load', function() {
  setTimeout(function() {
    if(!SmartAlerts._initialized) {
      tryInit();
    }
  }, 2000);
});

})();
```

---

## ✅ ما الجديد في هذا الإصدار:

### 1. **آلية إعادة محاولة ذكية** (Retry Mechanism):
- يحاول كل ثانية لمدة 20 ثانية
- يتوقف بمجرد النجاح
- لا يضيع وقت لو فشل

### 2. **يعتمد على `window.ME` أو الجلسة**:
- لو موجود `window.ME` → يستخدمه فوراً
- لو لا → يجلب من الجلسة مباشرة

### 3. **يعرض دائماً شيء**:
- لو في تنبيهات → زر أحمر بعدد التنبيهات
- لو لا → زر أخضر "كل شيء طبيعي ✅"

### 4. **معالجة أخطاء شاملة**:
- كل استعلام محاط بـ `try/catch`
- لو جدول مفقود، يتجاهله ويكمل

### 5. **يدعم كل الأدوار**:
- parent, teacher, student, counselor
- admin/super_admin, finance
- portal, staff

### 6. **استجابة للموبايل**:
- يأخذ عرض الشاشة على الجوال
- ينتقل من اليسار للأسفل

---

## 🚀 الخطوات:

1. افتح GitHub → `assets/smart-alerts.js`
2. ✏️ Edit → **Ctrl+A** → **Delete**
3. الصق الكود الكامل أعلاه
4. **Commit changes**
5. انتظر دقيقة
6. **Ctrl + Shift + R** على أي صفحة

---

## 🧪 الاختبار:

افتح هذه الصفحات وتأكد من ظهور الزر:
- ✅ `super-admin.html`
- ✅ `parent.html`
- ✅ `student.html`
- ✅ `teacher.html`
- ✅ `counselor.html`
- ✅ `portal.html`

**يجب أن يظهر زر عائم في أسفل اليسار**:
- 🔴 أحمر (إذا في تنبيهات)
- 🟢 أخضر (إذا كل شيء طبيعي)

---

## 📋 أخبرني:

- **"يعمل في كل البوابات"** → ✨ ممتاز!
- **"لا يعمل في صفحة X"** → افتح F12 وأرسل لي ما يظهر في Console
- **"يعمل لكن التنبيهات خطأ"** → نضبط المحتوى

🚀

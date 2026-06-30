/* ================================================================
   AMIN RENDER HELPERS — دوال العرض الموحّدة
   مدارس أمين الرضا (ع) — Tactile Identity System
   ================================================================ */

(function(){
'use strict';

// ============================================
// Helper: escapeHtml
// ============================================
function esc(v) {
  return String(v == null ? '' : v)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;').replace(/'/g,'&#039;');
}

// ============================================
// 1. renderProgressRing()
// حلقة تقدم دائرية ناعمة بهوية النجمة
// ============================================
window.renderProgressRing = function(containerEl, options) {
  if (!containerEl) return;
  options = options || {};
  
  var value = Math.max(0, Math.min(100, Number(options.value || 0)));
  var size = options.size || 120;
  var strokeWidth = options.strokeWidth || 8;
  var label = options.label || '';
  var sublabel = options.sublabel || '';
  var color = options.color || 'var(--primary)';
  var trackColor = options.trackColor || 'var(--border-subtle)';
  
  var radius = (size - strokeWidth) / 2;
  var circumference = 2 * Math.PI * radius;
  var offset = circumference - (value / 100) * circumference;
  
  var html = '<div class="progress-ring-wrapper" style="width:' + size + 'px;height:' + size + 'px;position:relative;">';
  html += '<svg width="' + size + '" height="' + size + '" style="transform:rotate(-90deg);">';
  html += '<circle cx="' + (size/2) + '" cy="' + (size/2) + '" r="' + radius + '" ';
  html += 'fill="none" stroke="' + trackColor + '" stroke-width="' + strokeWidth + '"/>';
  html += '<circle cx="' + (size/2) + '" cy="' + (size/2) + '" r="' + radius + '" ';
  html += 'fill="none" stroke="' + color + '" stroke-width="' + strokeWidth + '" ';
  html += 'stroke-dasharray="' + circumference + '" stroke-dashoffset="' + offset + '" ';
  html += 'stroke-linecap="round" style="transition:stroke-dashoffset 800ms cubic-bezier(0.22, 1, 0.36, 1);"/>';
  html += '</svg>';
  html += '<div class="progress-ring-content" style="position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;">';
  html += '<div class="progress-ring-value" style="font-family:var(--font-display);font-size:' + (size/4) + 'px;font-weight:800;color:var(--text-primary);line-height:1;">' + Math.round(value) + '%</div>';
  if (label) html += '<div class="progress-ring-label" style="font-size:var(--text-xs);color:var(--text-secondary);margin-block-start:4px;">' + esc(label) + '</div>';
  if (sublabel) html += '<div class="progress-ring-sublabel" style="font-size:var(--text-xs);color:var(--text-tertiary);">' + esc(sublabel) + '</div>';
  html += '</div></div>';
  
  containerEl.innerHTML = html;
};

// ============================================
// 2. renderTaskList()
// قائمة المهام مع أولويات ملونة
// ============================================
window.renderTaskList = function(containerEl, tasks) {
  if (!containerEl) return;
  tasks = tasks || [];
  
  // حالة فارغة - استخدام نجمة watermark
  if (!tasks.length) {
    if (window.AminStar) {
      containerEl.innerHTML = window.AminStar.createEmptyState('لا توجد مهام حالياً', '');
    } else {
      containerEl.innerHTML = '<div class="amin-empty-state"><h3 class="amin-empty-title">لا توجد مهام</h3></div>';
    }
    return;
  }
  
  // ترتيب: urgent أولاً، ثم normal، ثم low، والمنتهية في الأخير
  var priorityOrder = { urgent: 1, normal: 2, low: 3 };
  var sorted = tasks.slice().sort(function(a, b) {
    if (a.done !== b.done) return a.done ? 1 : -1;
    var pa = priorityOrder[a.priority] || 2;
    var pb = priorityOrder[b.priority] || 2;
    if (pa !== pb) return pa - pb;
    return new Date(a.due_date || 0) - new Date(b.due_date || 0);
  });
  
  var html = '<ul class="task-list" role="list">';
  sorted.forEach(function(task) {
    var priority = task.priority || 'normal';
    var doneClass = task.done ? ' done' : '';
    var dueText = formatDueDate(task.due_date);
    var isUrgent = priority === 'urgent' && !task.done;
    
    html += '<li class="task-item ' + priority + doneClass + '" ';
    html += 'data-task-id="' + esc(task.id) + '" ';
    html += 'data-source-table="' + esc(task.source_table || '') + '" ';
    html += 'data-source-id="' + esc(task.source_id || '') + '" ';
    html += 'tabindex="0" role="listitem">';
    
    html += '<div class="task-checkbox' + (task.done ? ' checked' : '') + '" role="checkbox" aria-checked="' + task.done + '">';
    if (task.done) html += '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="3"><polyline points="20 6 9 17 4 12"/></svg>';
    html += '</div>';
    
    html += '<div class="task-content">';
    html += '<div class="task-title">' + esc(task.title) + '</div>';
    if (dueText) {
      html += '<div class="task-meta">';
      html += '<span class="task-due">' + dueText + '</span>';
      if (isUrgent) html += '<span class="badge-flat danger" style="margin-inline-start:8px;">عاجل</span>';
      html += '</div>';
    }
    html += '</div>';
    
    html += '</li>';
  });
  html += '</ul>';
  
  containerEl.innerHTML = html;
  
  // ربط الأحداث
  containerEl.querySelectorAll('.task-item').forEach(function(item) {
    item.addEventListener('click', function(e) {
      if (e.target.classList.contains('task-checkbox')) return;
      var detail = {
        taskId: item.dataset.taskId,
        sourceTable: item.dataset.sourceTable,
        sourceId: item.dataset.sourceId
      };
      containerEl.dispatchEvent(new CustomEvent('task-click', { detail: detail, bubbles: true }));
    });
    
    var checkbox = item.querySelector('.task-checkbox');
    if (checkbox) {
      checkbox.addEventListener('click', function(e) {
        e.stopPropagation();
        var detail = {
          taskId: item.dataset.taskId,
          sourceTable: item.dataset.sourceTable,
          sourceId: item.dataset.sourceId,
          done: !item.classList.contains('done')
        };
        containerEl.dispatchEvent(new CustomEvent('task-toggle', { detail: detail, bubbles: true }));
      });
    }
  });
};

// ============================================
// 3. renderTimeline()
// Timeline أفقي (Desktop) → عمودي (Mobile)
// ============================================
window.renderTimeline = function(containerEl, items) {
  if (!containerEl) return;
  items = items || [];
  
  if (!items.length) {
    if (window.AminStar) {
      containerEl.innerHTML = window.AminStar.createEmptyState('لا توجد إنجازات لعرضها بعد', '');
    } else {
      containerEl.innerHTML = '<div class="amin-empty-state"><h3 class="amin-empty-title">لا توجد إنجازات</h3></div>';
    }
    return;
  }
  
  // ترتيب: المنتهية حسب التاريخ (الأحدث أولاً)، القادمة حسب التاريخ (الأقرب أولاً)
  var sorted = items.slice().sort(function(a, b) {
    if (a.status !== b.status) return a.status === 'done' ? -1 : 1;
    var da = new Date(a.date || 0);
    var db = new Date(b.date || 0);
    return a.status === 'done' ? db - da : da - db;
  });
  
  var html = '<div class="timeline" role="list">';
  sorted.forEach(function(item, idx) {
    var statusClass = item.status === 'done' ? 'done' : 'upcoming';
    html += '<div class="timeline-item ' + statusClass + '" ';
    html += 'data-item-id="' + esc(item.id) + '" ';
    html += 'tabindex="0" role="listitem" aria-label="' + esc(item.label) + '">';
    
    // النقطة على شكل نجمة
    html += '<div class="timeline-dot">';
    if (window.AminStar) {
      html += window.AminStar.createTimelineDot(item.status);
    } else {
      // Fallback إذا لم تتوفر مكتبة النجمة
      html += '<div style="width:16px;height:16px;border-radius:50%;background:' + (item.status === 'done' ? 'var(--secondary)' : 'var(--text-tertiary)') + ';"></div>';
    }
    html += '</div>';
    
    html += '<div class="timeline-content">';
    html += '<div class="timeline-label">' + esc(item.label) + '</div>';
    html += '<div class="timeline-date">' + formatTimelineDate(item.date) + '</div>';
    
    // شريط تقدم اختياري
    if (typeof item.progress === 'number') {
      html += '<div class="timeline-progress" style="margin-block-start:6px;width:100%;max-width:100px;height:4px;background:var(--border-subtle);border-radius:2px;overflow:hidden;">';
      html += '<div style="width:' + Math.max(0, Math.min(100, item.progress)) + '%;height:100%;background:var(--secondary);transition:width 600ms cubic-bezier(0.22, 1, 0.36, 1);"></div>';
      html += '</div>';
    }
    html += '</div>';
    
    html += '</div>';
  });
  html += '</div>';
  
  containerEl.innerHTML = html;
  
  // Popover عند النقر (لا modal كامل)
  containerEl.querySelectorAll('.timeline-item').forEach(function(item) {
    item.addEventListener('click', function() {
      var detail = { itemId: item.dataset.itemId };
      containerEl.dispatchEvent(new CustomEvent('timeline-click', { detail: detail, bubbles: true }));
    });
  });
};

// ============================================
// 4. renderResponsiveTable()
// جدول يتحول لبطاقات تلقائياً على الموبايل
// ============================================
window.renderResponsiveTable = function(containerEl, data, columns, options) {
  if (!containerEl) return;
  data = data || [];
  columns = columns || [];
  options = options || {};
  
  var primaryFields = options.primaryFields || (columns.length > 0 ? [columns[0].key] : []);
  var mobileExpandable = options.mobileExpandable || [];
  var rowAction = options.rowAction || null; // { label, onClick: function(row){} }
  var emptyMessage = options.emptyMessage || 'لا توجد بيانات لعرضها';
  
  if (!data.length) {
    if (window.AminStar) {
      containerEl.innerHTML = window.AminStar.createEmptyState(emptyMessage, '');
    } else {
      containerEl.innerHTML = '<div class="amin-empty-state"><h3 class="amin-empty-title">' + esc(emptyMessage) + '</h3></div>';
    }
    return;
  }
  
  var html = '<div class="responsive-table-container">';
  
  // ===== Desktop/Tablet: جدول كامل =====
  html += '<table class="table-flat">';
  html += '<thead><tr>';
  columns.forEach(function(col) {
    html += '<th>' + esc(col.label) + '</th>';
  });
  if (rowAction) html += '<th style="width:120px;text-align:center;">إجراء</th>';
  html += '</tr></thead>';
  
  html += '<tbody>';
  data.forEach(function(row, idx) {
    html += '<tr data-row-index="' + idx + '">';
    columns.forEach(function(col) {
      var value = row[col.key];
      var rendered = col.render ? col.render(value, row) : esc(value == null ? '—' : value);
      html += '<td>' + rendered + '</td>';
    });
    if (rowAction) {
      html += '<td style="text-align:center;"><button class="btn-3d-primary btn-row-action" data-row-index="' + idx + '" style="min-height:32px;padding:6px 14px;font-size:var(--text-sm);">' + esc(rowAction.label) + '</button></td>';
    }
    html += '</tr>';
  });
  html += '</tbody></table>';
  
  // ===== Mobile: بطاقات =====
  html += '<div class="mobile-cards">';
  data.forEach(function(row, idx) {
    html += '<div class="mobile-card" data-row-index="' + idx + '">';
    
    // Header: الاسم الرئيسي + Action
    var primaryField = columns.find(function(c){ return c.key === primaryFields[0]; });
    if (primaryField) {
      var primaryValue = row[primaryField.key];
      var primaryRendered = primaryField.render ? primaryField.render(primaryValue, row) : esc(primaryValue == null ? '—' : primaryValue);
      html += '<div class="mobile-card-header">';
      html += '<div class="mobile-card-name">' + primaryRendered + '</div>';
      html += '</div>';
    }
    
    // الحقول الأساسية (أهم 2-3 حقول)
    html += '<div class="mobile-card-primary-info">';
    primaryFields.slice(1).forEach(function(fieldKey) {
      var col = columns.find(function(c){ return c.key === fieldKey; });
      if (col) {
        var val = row[col.key];
        var rendered = col.render ? col.render(val, row) : esc(val == null ? '—' : val);
        html += '<div class="mobile-card-field">';
        html += '<span class="mobile-card-field-label">' + esc(col.label) + '</span>';
        html += '<span class="mobile-card-field-value">' + rendered + '</span>';
        html += '</div>';
      }
    });
    html += '</div>';
    
    // زر التوسيع للحقول الإضافية
    if (mobileExpandable.length > 0) {
      html += '<button class="mobile-card-expand-btn" data-row-index="' + idx + '">';
      html += 'التفاصيل ⌄';
      html += '</button>';
      html += '<div class="mobile-card-expanded" data-row-expanded="' + idx + '">';
      mobileExpandable.forEach(function(fieldKey) {
        var col = columns.find(function(c){ return c.key === fieldKey; });
        if (col) {
          var val = row[col.key];
          var rendered = col.render ? col.render(val, row) : esc(val == null ? '—' : val);
          html += '<div class="mobile-card-field" style="margin-block-end:var(--space-2);">';
          html += '<span class="mobile-card-field-label">' + esc(col.label) + '</span>';
          html += '<span class="mobile-card-field-value">' + rendered + '</span>';
          html += '</div>';
        }
      });
      html += '</div>';
    }
    
    // زر الإجراء الأساسي
    if (rowAction) {
      html += '<div class="mobile-card-action">';
      html += '<button class="btn-3d-primary btn-row-action" data-row-index="' + idx + '" style="min-height:36px;padding:6px 14px;font-size:var(--text-sm);">' + esc(rowAction.label) + '</button>';
      html += '</div>';
    }
    
    html += '</div>';
  });
  html += '</div>';
  
  html += '</div>';
  
  containerEl.innerHTML = html;
  
  // ربط الأحداث
  if (rowAction && typeof rowAction.onClick === 'function') {
    containerEl.querySelectorAll('.btn-row-action').forEach(function(btn) {
      btn.addEventListener('click', function(e) {
        e.stopPropagation();
        var idx = parseInt(btn.dataset.rowIndex, 10);
        if (!isNaN(idx) && data[idx]) {
          rowAction.onClick(data[idx]);
        }
      });
    });
  }
  
  // توسيع البطاقات على الموبايل
  containerEl.querySelectorAll('.mobile-card-expand-btn').forEach(function(btn) {
    btn.addEventListener('click', function() {
      var idx = btn.dataset.rowIndex;
      var expandedEl = containerEl.querySelector('[data-row-expanded="' + idx + '"]');
      if (expandedEl) {
        var isShown = expandedEl.classList.toggle('show');
        btn.textContent = isShown ? 'إخفاء التفاصيل ⌃' : 'التفاصيل ⌄';
      }
    });
  });
};

// ============================================
// Helper Functions
// ============================================
function formatDueDate(dateStr) {
  if (!dateStr) return '';
  try {
    var d = new Date(dateStr);
    var today = new Date();
    today.setHours(0, 0, 0, 0);
    d.setHours(0, 0, 0, 0);
    var diffDays = Math.round((d - today) / (1000 * 60 * 60 * 24));
    
    if (diffDays < 0) return 'متأخر ' + Math.abs(diffDays) + ' يوم';
    if (diffDays === 0) return 'اليوم';
    if (diffDays === 1) return 'غداً';
    if (diffDays <= 7) return 'بعد ' + diffDays + ' أيام';
    
    var locale = (document.documentElement.lang || 'ar') === 'en' ? 'en-US' : 'ar-IQ';
    return d.toLocaleDateString(locale, { day: 'numeric', month: 'short' });
  } catch (e) {
    return '';
  }
}

function formatTimelineDate(dateStr) {
  if (!dateStr) return '';
  try {
    var d = new Date(dateStr);
    var locale = (document.documentElement.lang || 'ar') === 'en' ? 'en-US' : 'ar-IQ';
    return d.toLocaleDateString(locale, { day: 'numeric', month: 'short', year: 'numeric' });
  } catch (e) {
    return String(dateStr).slice(0, 10);
  }
}

// ============================================
// Bonus: renderClockWidget (للساعة الأفقية)
// ============================================
window.renderClockWidget = function(containerEl, options) {
  if (!containerEl) return;
  options = options || {};
  
  var locale = options.locale || (document.documentElement.lang || 'ar');
  var defaultCalendar = locale === 'fa' ? 'persian' : 'gregory';
  var currentCalendar = options.calendar || defaultCalendar;
  
  function updateClock() {
    var now = new Date();
    
    // الوقت
    var timeStr = '';
    var period = '';
    try {
      var timeFormatter = new Intl.DateTimeFormat(locale === 'ar' ? 'ar-IQ' : locale, {
        hour: '2-digit',
        minute: '2-digit',
        hour12: true
      });
      timeStr = timeFormatter.format(now);
      var hours = now.getHours();
      period = hours < 12 ? (locale === 'en' ? 'AM' : 'صباحاً') : (locale === 'en' ? 'PM' : 'مساءً');
    } catch (e) {
      timeStr = now.getHours() + ':' + String(now.getMinutes()).padStart(2, '0');
    }
    
    // التاريخ
    var dateStr = '';
    try {
      var dateLocale = locale === 'ar' ? 'ar-IQ' : (locale === 'fa' ? 'fa-IR' : 'en-US');
      var dateFormatter = new Intl.DateTimeFormat(dateLocale + '-u-ca-' + currentCalendar, {
        day: 'numeric', month: 'long', year: 'numeric'
      });
      dateStr = dateFormatter.format(now);
    } catch (e) {
      // Fallback لـ gregory
      try {
        dateStr = new Intl.DateTimeFormat(locale === 'ar' ? 'ar-IQ' : 'en-US', {
          day: 'numeric', month: 'long', year: 'numeric'
        }).format(now);
        currentCalendar = 'gregory';
      } catch (e2) {
        dateStr = now.toLocaleDateString();
      }
    }
    
    var calendarNames = {
      gregory: 'ميلادي',
      'islamic-umalqura': 'هجري',
      persian: 'شمسي'
    };
    
    var html = '<div class="clock-widget" role="region" aria-label="الوقت والتاريخ">';
    html += '<div class="clock-time">';
    html += '<div class="clock-hour">' + esc(timeStr) + '</div>';
    html += '<div class="clock-period">' + esc(period) + '</div>';
    html += '</div>';
    html += '<div class="clock-date-section">';
    html += '<div class="clock-date">' + esc(dateStr) + '</div>';
    html += '<select class="clock-calendar-select" aria-label="نوع التقويم">';
    ['gregory', 'islamic-umalqura', 'persian'].forEach(function(cal) {
      var selected = cal === currentCalendar ? ' selected' : '';
      html += '<option value="' + cal + '"' + selected + '>' + calendarNames[cal] + '</option>';
    });
    html += '</select>';
    html += '</div>';
    html += '</div>';
    
    containerEl.innerHTML = html;
    
    // ربط تغيير التقويم
    var selectEl = containerEl.querySelector('.clock-calendar-select');
    if (selectEl) {
      selectEl.addEventListener('change', function() {
        currentCalendar = selectEl.value;
        updateClock();
      });
    }
  }
  
  updateClock();
  // تحديث كل دقيقة
  if (containerEl._clockInterval) clearInterval(containerEl._clockInterval);
  containerEl._clockInterval = setInterval(updateClock, 60000);
};

// ============================================
// Bonus: showToast (Tier 1)
// ============================================
window.showAminToast = function(title, msg, type) {
  type = type || 'info';
  var containerId = 'amin-toast-container';
  var container = document.getElementById(containerId);
  if (!container) {
    container = document.createElement('div');
    container.id = containerId;
    container.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);z-index:9999;display:flex;flex-direction:column;gap:8px;pointer-events:none;';
    document.body.appendChild(container);
  }
  
  var icons = { success: '✓', error: '✕', warning: '⚠', info: 'ℹ' };
  var toast = document.createElement('div');
  toast.className = 'amin-toast ' + type;
  toast.style.pointerEvents = 'auto';
  toast.innerHTML = 
    '<div class="toast-icon">' + (icons[type] || icons.info) + '</div>' +
    '<div class="toast-content">' +
      '<div class="toast-title">' + esc(title) + '</div>' +
      (msg ? '<div class="toast-msg">' + esc(msg) + '</div>' : '') +
    '</div>';
  
  toast.style.animation = 'amin-toast-in 350ms cubic-bezier(0.22, 1, 0.36, 1)';
  container.appendChild(toast);
  
  setTimeout(function() {
    toast.style.animation = 'amin-toast-out 350ms cubic-bezier(0.22, 1, 0.36, 1) forwards';
    setTimeout(function(){ toast.remove(); }, 350);
  }, 3000);
};

// حقن CSS الحركة للـ Toast
if (!document.getElementById('amin-toast-keyframes')) {
  var style = document.createElement('style');
  style.id = 'amin-toast-keyframes';
  style.textContent = '@keyframes amin-toast-in { from { opacity:0; transform:translate(-50%, 20px); } to { opacity:1; transform:translate(-50%, 0); } } @keyframes amin-toast-out { to { opacity:0; transform:translate(-50%, 20px); } }';
  document.head.appendChild(style);
}

// ============================================
// Bonus: renderError (Inline - Capacitor friendly)
// ============================================
window.renderAminError = function(containerEl, message, retryFn) {
  if (!containerEl) return;
  var retryAttr = retryFn ? 'onclick="(' + retryFn.toString() + ')()"' : '';
  containerEl.innerHTML = 
    '<div class="error-inline" role="alert">' +
      '<div class="error-inline-icon">⚠</div>' +
      '<div class="error-inline-msg">' + esc(message || 'تحقق من الاتصال') + '</div>' +
      (retryFn ? '<button class="error-inline-retry" ' + retryAttr + '>إعادة المحاولة</button>' : '') +
    '</div>';
};

})();

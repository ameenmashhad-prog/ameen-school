/* ================================================================
   AMIN SIGNATURE STAR — النجمة الثمانية المبسّطة
   التوقيع البصري للهوية - SVG path قابل لإعادة الاستخدام
   ================================================================ */

(function(){
  'use strict';
  
  // ===== النقاط الـ 16 للنجمة الثمانية المبسّطة =====
  // (8 نقاط خارجية + 8 نقاط داخلية، بسماكة 1.5px stroke فقط)
  // مرسومة في viewBox 100x100, نصف القطر الخارجي 45, الداخلي 22
  
  const STAR_PATH = 'M 50 5 L 56.5 28.5 L 80 22 L 71.5 45 L 95 50 L 71.5 55 L 80 78 L 56.5 71.5 L 50 95 L 43.5 71.5 L 20 78 L 28.5 55 L 5 50 L 28.5 45 L 20 22 L 43.5 28.5 Z';
  
  /**
   * إنشاء عنصر SVG للنجمة الثمانية
   * @param {Object} options
   * @param {string} options.variant - 'outline' | 'filled' | 'spinning' | 'watermark'
   * @param {number} options.size - الحجم بالبكسل (default: 24)
   * @param {string} options.color - لون CSS (default: currentColor)
   * @param {string} options.strokeWidth - سماكة الخط (default: 1.5)
   * @param {string} options.className - class CSS إضافي
   * @returns {string} HTML SVG string
   */
  function createStar(options) {
    options = options || {};
    var variant = options.variant || 'outline';
    var size = options.size || 24;
    var color = options.color || 'currentColor';
    var strokeWidth = options.strokeWidth || 1.5;
    var className = options.className || '';
    
    var attrs = 'width="' + size + '" height="' + size + '" viewBox="0 0 100 100"';
    var classes = 'amin-star amin-star-' + variant + (className ? ' ' + className : '');
    
    if (variant === 'outline') {
      return '<svg ' + attrs + ' class="' + classes + '" aria-hidden="true">' +
        '<path d="' + STAR_PATH + '" fill="none" stroke="' + color + '" stroke-width="' + strokeWidth + '" stroke-linejoin="round" stroke-linecap="round"/>' +
        '</svg>';
    }
    
    if (variant === 'filled') {
      return '<svg ' + attrs + ' class="' + classes + '" aria-hidden="true">' +
        '<path d="' + STAR_PATH + '" fill="' + color + '" stroke="' + color + '" stroke-width="' + strokeWidth + '" stroke-linejoin="round"/>' +
        '</svg>';
    }
    
    if (variant === 'spinning') {
      // النجمة الدوّارة كـ loading indicator (بديل spinner التقليدي)
      return '<svg ' + attrs + ' class="' + classes + ' amin-star-spin" aria-label="جاري التحميل" role="status">' +
        '<path d="' + STAR_PATH + '" fill="none" stroke="' + color + '" stroke-width="' + strokeWidth + '" stroke-linejoin="round" stroke-linecap="round" stroke-dasharray="200" stroke-dashoffset="50"/>' +
        '</svg>';
    }
    
    if (variant === 'watermark') {
      // علامة مائية شفافة للـ empty states (opacity منخفض جداً)
      return '<svg ' + attrs + ' class="' + classes + '" aria-hidden="true" style="opacity:0.03;">' +
        '<path d="' + STAR_PATH + '" fill="' + color + '"/>' +
        '</svg>';
    }
    
    // Fallback
    return createStar({variant: 'outline', size: size, color: color});
  }
  
  /**
   * إنشاء حلقة تقدم باستخدام نقاط النجمة (للنماذج متعددة المراحل)
   * @param {number} current - الخطوة الحالية (1-based)
   * @param {number} total - إجمالي الخطوات
   */
  function createStarProgress(current, total) {
    var html = '<div class="amin-star-progress" role="progressbar" aria-valuenow="' + current + '" aria-valuemin="1" aria-valuemax="' + total + '">';
    for (var i = 1; i <= total; i++) {
      var isDone = i < current;
      var isCurrent = i === current;
      var variant = isDone || isCurrent ? 'filled' : 'outline';
      var color = isDone ? 'var(--success)' : isCurrent ? 'var(--secondary)' : 'var(--border-medium)';
      html += '<span class="amin-star-progress-step' + (isCurrent ? ' active' : '') + (isDone ? ' done' : '') + '">';
      html += createStar({variant: variant, size: 20, color: color});
      if (i < total) html += '<span class="amin-star-progress-line' + (isDone ? ' done' : '') + '"></span>';
      html += '</span>';
    }
    html += '</div>';
    return html;
  }
  
  /**
   * إنشاء نقطة Timeline بشكل النجمة
   * @param {string} status - 'done' | 'upcoming'
   */
  function createTimelineDot(status) {
    if (status === 'done') {
      return createStar({variant: 'filled', size: 16, color: 'var(--secondary)', className: 'amin-timeline-dot done'});
    }
    return createStar({variant: 'outline', size: 16, color: 'var(--text-tertiary)', className: 'amin-timeline-dot upcoming'});
  }
  
  /**
   * إنشاء إطار صورة بشكل النجمة (CSS clip-path)
   * يُستخدم للصور الشخصية والشعارات
   */
  function createStarFrame(imageSrc, size, altText) {
    size = size || 80;
    altText = altText || '';
    return '<div class="amin-star-frame" style="width:' + size + 'px;height:' + size + 'px;">' +
      '<img src="' + imageSrc + '" alt="' + altText + '" />' +
      '</div>';
  }
  
  /**
   * إنشاء empty state مع نجمة watermark
   */
  function createEmptyState(message, action) {
    var html = '<div class="amin-empty-state">';
    html += '<div class="amin-empty-watermark">' + createStar({variant: 'watermark', size: 200}) + '</div>';
    html += '<h3 class="amin-empty-title">' + message + '</h3>';
    if (action) html += '<div class="amin-empty-action">' + action + '</div>';
    html += '</div>';
    return html;
  }
  
  /**
   * نسخة Splash Icon للتطبيق (Capacitor APK)
   * 1024x1024px - نجمة ممتلئة بلون primary مع خلفية دائرية ناعمة
   */
  function createSplashIcon() {
    return '<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">' +
      '<defs>' +
        '<linearGradient id="bg-gradient" x1="0%" y1="0%" x2="100%" y2="100%">' +
          '<stop offset="0%" stop-color="#0B6E4F"/>' +
          '<stop offset="100%" stop-color="#1FAE7C"/>' +
        '</linearGradient>' +
        '<linearGradient id="star-gradient" x1="0%" y1="0%" x2="0%" y2="100%">' +
          '<stop offset="0%" stop-color="#FBF1DC"/>' +
          '<stop offset="100%" stop-color="#B8860B"/>' +
        '</linearGradient>' +
      '</defs>' +
      // خلفية مربعة بزوايا ناعمة
      '<rect width="1024" height="1024" rx="200" fill="url(#bg-gradient)"/>' +
      // النجمة الثمانية في المنتصف (مكبرة بمعامل 8.2)
      '<g transform="translate(102, 102) scale(8.2)">' +
        '<path d="' + STAR_PATH + '" fill="url(#star-gradient)" stroke="#FFFFFF" stroke-width="1.2"/>' +
      '</g>' +
      '</svg>';
  }
  
  /**
   * تصدير الـ Splash Icon كـ Blob للتنزيل
   */
  function downloadSplashIcon(filename) {
    filename = filename || 'amin-splash-icon-1024.svg';
    var svgContent = createSplashIcon();
    var blob = new Blob([svgContent], {type: 'image/svg+xml'});
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }
  
  // ===== CSS المرافق للحركة =====
  function injectStarStyles() {
    if (document.getElementById('amin-star-styles')) return;
    var style = document.createElement('style');
    style.id = 'amin-star-styles';
    style.textContent = [
      '.amin-star { display: inline-block; vertical-align: middle; }',
      '.amin-star-spin { animation: amin-star-rotate 2s linear infinite; transform-origin: center; }',
      '@keyframes amin-star-rotate { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }',
      '.amin-star-frame { position: relative; clip-path: polygon(50% 5%, 56.5% 28.5%, 80% 22%, 71.5% 45%, 95% 50%, 71.5% 55%, 80% 78%, 56.5% 71.5%, 50% 95%, 43.5% 71.5%, 20% 78%, 28.5% 55%, 5% 50%, 28.5% 45%, 20% 22%, 43.5% 28.5%); overflow: hidden; }',
      '.amin-star-frame img { width: 100%; height: 100%; object-fit: cover; }',
      '.amin-star-progress { display: flex; align-items: center; gap: 8px; }',
      '.amin-star-progress-step { display: inline-flex; align-items: center; gap: 8px; }',
      '.amin-star-progress-step.active .amin-star { transform: scale(1.2); transition: transform var(--transition-standard); }',
      '.amin-star-progress-line { width: 32px; height: 2px; background: var(--border-subtle); border-radius: 2px; }',
      '.amin-star-progress-line.done { background: var(--success); }',
      '.amin-empty-state { position: relative; padding: 60px 20px; text-align: center; min-height: 240px; display: flex; flex-direction: column; align-items: center; justify-content: center; }',
      '.amin-empty-watermark { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; pointer-events: none; }',
      '.amin-empty-title { font-size: var(--text-h3); color: var(--text-secondary); margin-bottom: 16px; position: relative; z-index: 1; }',
      '.amin-empty-action { position: relative; z-index: 1; }',
      '.amin-timeline-dot { transition: transform var(--transition-standard); }',
      '.amin-timeline-dot:hover { transform: scale(1.15); }'
    ].join('\n');
    document.head.appendChild(style);
  }
  
  // حقن CSS تلقائياً عند التحميل
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectStarStyles);
  } else {
    injectStarStyles();
  }
  
  // ===== التصدير العام =====
  window.AminStar = {
    createStar: createStar,
    createStarProgress: createStarProgress,
    createTimelineDot: createTimelineDot,
    createStarFrame: createStarFrame,
    createEmptyState: createEmptyState,
    createSplashIcon: createSplashIcon,
    downloadSplashIcon: downloadSplashIcon,
    PATH: STAR_PATH
  };
})();

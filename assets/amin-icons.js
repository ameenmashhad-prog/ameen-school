/* ================================================================
   AMIN ICONS — مكتبة أيقونات SVG ثلاثية الأبعاد
   مدارس أمين الرضا (ع) — هوية بصرية موحدة
   ================================================================ */

(function(){
'use strict';

// ===== Gradient Definitions (يُحقن مرة واحدة) =====
var SVG_DEFS = '<defs>' +
  // Primary - أخضر زمردي
  '<linearGradient id="grad-primary" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" stop-color="#1FAE7C"/><stop offset="100%" stop-color="#0B6E4F"/></linearGradient>' +
  // Secondary - ذهبي نحاسي
  '<linearGradient id="grad-secondary" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" stop-color="#DAA520"/><stop offset="100%" stop-color="#B8860B"/></linearGradient>' +
  // Accent - كحلي
  '<linearGradient id="grad-accent" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" stop-color="#6B5DD3"/><stop offset="100%" stop-color="#3A3565"/></linearGradient>' +
  // Danger - أحمر
  '<linearGradient id="grad-danger" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" stop-color="#F87171"/><stop offset="100%" stop-color="#DC2626"/></linearGradient>' +
  // Warning - برتقالي
  '<linearGradient id="grad-warning" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" stop-color="#FBBF24"/><stop offset="100%" stop-color="#D97706"/></linearGradient>' +
  // Info - أزرق
  '<linearGradient id="grad-info" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" stop-color="#38BDF8"/><stop offset="100%" stop-color="#0EA5E9"/></linearGradient>' +
  // Highlight - تأثير اللمعان
  '<linearGradient id="grad-highlight" x1="0%" y1="0%" x2="0%" y2="100%"><stop offset="0%" stop-color="rgba(255,255,255,0.3)"/><stop offset="50%" stop-color="rgba(255,255,255,0)"/></linearGradient>' +
'</defs>';

// ===== مكتبة الأيقونات =====
var ICONS = {

  // 🏠 لوحة القيادة - بيت ثلاثي الأبعاد بقاعدة ذهبية
  overview: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    '<path d="M8 32 L32 10 L56 32 L56 54 L8 54 Z" fill="url(#grad-primary)" stroke="#0B6E4F" stroke-width="1"/>' +
    '<path d="M8 32 L32 10 L56 32 L48 32 L32 18 L16 32 Z" fill="url(#grad-highlight)"/>' +
    '<rect x="22" y="38" width="20" height="16" fill="url(#grad-secondary)" rx="2"/>' +
    '<circle cx="32" cy="46" r="1.5" fill="#0B6E4F"/>' +
    '<path d="M28 8 L32 4 L36 8 L32 6 Z" fill="url(#grad-secondary)"/>' +
  '</svg>',

  // 🎓 الطلاب - قبعة تخرج ثلاثية الأبعاد
  students: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    '<path d="M4 26 L32 14 L60 26 L32 38 Z" fill="url(#grad-accent)"/>' +
    '<path d="M4 26 L32 14 L60 26 L32 32 Z" fill="url(#grad-highlight)"/>' +
    '<path d="M12 30 L12 42 Q12 48 32 48 Q52 48 52 42 L52 30 L32 38 Z" fill="url(#grad-primary)"/>' +
    '<path d="M12 30 L12 36 Q12 38 32 40 Q52 38 52 36 L52 30 L32 36 Z" fill="rgba(255,255,255,0.15)"/>' +
    '<line x1="56" y1="26" x2="56" y2="44" stroke="url(#grad-secondary)" stroke-width="2"/>' +
    '<circle cx="56" cy="46" r="3" fill="url(#grad-secondary)"/>' +
  '</svg>',

  // 📚 الأكاديمي - كتب مكدسة ثلاثية الأبعاد
  academic: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    '<path d="M8 14 L52 14 L56 18 L56 26 L52 22 L8 22 Z" fill="url(#grad-danger)"/>' +
    '<rect x="8" y="14" width="44" height="8" fill="url(#grad-danger)"/>' +
    '<rect x="8" y="14" width="44" height="3" fill="rgba(255,255,255,0.2)"/>' +
    '<path d="M6 28 L50 28 L54 32 L54 40 L50 36 L6 36 Z" fill="url(#grad-primary)"/>' +
    '<rect x="6" y="28" width="44" height="8" fill="url(#grad-primary)"/>' +
    '<rect x="6" y="28" width="44" height="3" fill="rgba(255,255,255,0.2)"/>' +
    '<path d="M10 42 L54 42 L58 46 L58 54 L54 50 L10 50 Z" fill="url(#grad-secondary)"/>' +
    '<rect x="10" y="42" width="44" height="8" fill="url(#grad-secondary)"/>' +
    '<rect x="10" y="42" width="44" height="3" fill="rgba(255,255,255,0.2)"/>' +
    '<rect x="44" y="16" width="2" height="4" fill="white"/>' +
    '<rect x="44" y="30" width="2" height="4" fill="white"/>' +
    '<rect x="46" y="44" width="2" height="4" fill="white"/>' +
  '</svg>',

  // 💰 المالية - كومة عملات ذهبية ثلاثية الأبعاد
  finance: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    // العملة السفلية
    '<ellipse cx="32" cy="50" rx="22" ry="6" fill="#8B6500"/>' +
    '<ellipse cx="32" cy="48" rx="22" ry="6" fill="url(#grad-secondary)"/>' +
    '<ellipse cx="32" cy="46" rx="22" ry="5" fill="rgba(255,255,255,0.2)"/>' +
    // العملة الوسطى
    '<ellipse cx="32" cy="38" rx="20" ry="6" fill="#8B6500"/>' +
    '<ellipse cx="32" cy="36" rx="20" ry="6" fill="url(#grad-secondary)"/>' +
    '<ellipse cx="32" cy="34" rx="20" ry="5" fill="rgba(255,255,255,0.25)"/>' +
    // العملة العلوية
    '<ellipse cx="32" cy="26" rx="18" ry="6" fill="#8B6500"/>' +
    '<ellipse cx="32" cy="24" rx="18" ry="6" fill="url(#grad-secondary)"/>' +
    '<ellipse cx="32" cy="22" rx="18" ry="5" fill="rgba(255,255,255,0.3)"/>' +
    // رمز $
    '<text x="32" y="28" text-anchor="middle" font-size="14" font-weight="bold" fill="#7A5500">$</text>' +
    // نجمة لمعان
    '<circle cx="22" cy="20" r="1.5" fill="white"/>' +
    '<circle cx="42" cy="20" r="1" fill="white"/>' +
  '</svg>',

  // 📋 الحضور - لوحة فحص ثلاثية الأبعاد
  attendance: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    // ظل اللوح
    '<rect x="12" y="14" width="40" height="46" rx="4" fill="#0B6E4F"/>' +
    // اللوح
    '<rect x="10" y="12" width="40" height="46" rx="4" fill="url(#grad-primary)"/>' +
    // مشبك علوي
    '<rect x="22" y="6" width="16" height="10" rx="2" fill="url(#grad-secondary)"/>' +
    '<rect x="22" y="6" width="16" height="4" rx="2" fill="rgba(255,255,255,0.3)"/>' +
    // قائمة محتوى
    '<rect x="16" y="22" width="28" height="2" rx="1" fill="white" opacity="0.8"/>' +
    '<circle cx="16" cy="30" r="2" fill="white"/>' +
    '<path d="M14.5 30 L15.5 31 L17.5 29" stroke="#0B6E4F" stroke-width="1" fill="none"/>' +
    '<rect x="22" y="29" width="22" height="2" rx="1" fill="white" opacity="0.6"/>' +
    '<circle cx="16" cy="38" r="2" fill="white"/>' +
    '<path d="M14.5 38 L15.5 39 L17.5 37" stroke="#0B6E4F" stroke-width="1" fill="none"/>' +
    '<rect x="22" y="37" width="22" height="2" rx="1" fill="white" opacity="0.6"/>' +
    '<circle cx="16" cy="46" r="2" fill="white"/>' +
    '<rect x="22" y="45" width="22" height="2" rx="1" fill="white" opacity="0.6"/>' +
  '</svg>',

  // 🛡️ السلوك - درع ثلاثي الأبعاد
  discipline: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    // ظل الدرع
    '<path d="M34 6 L56 14 L54 38 Q52 50 34 60 Q16 50 14 38 L12 14 Z" fill="#3A3565"/>' +
    // الدرع
    '<path d="M32 4 L54 12 L52 36 Q50 48 32 58 Q14 48 12 36 L10 12 Z" fill="url(#grad-accent)"/>' +
    // لمعان جانبي
    '<path d="M32 4 L54 12 L52 36 Q50 42 32 50 L32 4 Z" fill="rgba(255,255,255,0.15)"/>' +
    // نجمة ثمانية في المنتصف
    '<path d="M32 18 L34 25 L41 26 L36 31 L37 38 L32 35 L27 38 L28 31 L23 26 L30 25 Z" fill="url(#grad-secondary)"/>' +
    // لمعان النجمة
    '<circle cx="32" cy="27" r="2" fill="rgba(255,255,255,0.6)"/>' +
  '</svg>',

  // 📝 التسجيلات - مستند مع قلم ثلاثي الأبعاد
  registrations: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    // ظل المستند
    '<path d="M12 10 L40 10 L52 22 L52 58 L12 58 Z" fill="#8B6500"/>' +
    // المستند
    '<path d="M10 8 L38 8 L50 20 L50 56 L10 56 Z" fill="url(#grad-secondary)"/>' +
    '<path d="M10 8 L38 8 L50 20 L50 24 L10 24 Z" fill="rgba(255,255,255,0.2)"/>' +
    // طية الزاوية
    '<path d="M38 8 L50 20 L38 20 Z" fill="#8B6500"/>' +
    // أسطر النص
    '<rect x="16" y="30" width="28" height="2" rx="1" fill="white" opacity="0.7"/>' +
    '<rect x="16" y="36" width="20" height="2" rx="1" fill="white" opacity="0.5"/>' +
    '<rect x="16" y="42" width="24" height="2" rx="1" fill="white" opacity="0.5"/>' +
    // قلم
    '<rect x="40" y="38" width="14" height="4" rx="2" transform="rotate(-45 47 40)" fill="url(#grad-primary)"/>' +
    '<polygon points="52,32 56,30 58,32 54,34" fill="#0B6E4F"/>' +
  '</svg>',

  // 📅 الجدول - تقويم ثلاثي الأبعاد
  schedule: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    // ظل التقويم
    '<rect x="10" y="14" width="46" height="44" rx="4" fill="#0B6E4F"/>' +
    // التقويم
    '<rect x="8" y="12" width="46" height="44" rx="4" fill="url(#grad-primary)"/>' +
    // رأس التقويم
    '<rect x="8" y="12" width="46" height="14" rx="4" fill="url(#grad-secondary)"/>' +
    '<rect x="8" y="12" width="46" height="5" rx="4" fill="rgba(255,255,255,0.3)"/>' +
    // الحلقات العلوية
    '<rect x="18" y="8" width="3" height="10" rx="1.5" fill="#5A4500"/>' +
    '<rect x="42" y="8" width="3" height="10" rx="1.5" fill="#5A4500"/>' +
    // شبكة التقويم
    '<g fill="white" opacity="0.8">' +
      '<circle cx="16" cy="32" r="1.5"/>' +
      '<circle cx="24" cy="32" r="1.5"/>' +
      '<circle cx="32" cy="32" r="1.5"/>' +
      '<circle cx="40" cy="32" r="1.5"/>' +
      '<circle cx="48" cy="32" r="1.5"/>' +
      '<circle cx="16" cy="40" r="1.5"/>' +
      '<circle cx="24" cy="40" r="1.5"/>' +
      '<circle cx="40" cy="40" r="1.5"/>' +
      '<circle cx="48" cy="40" r="1.5"/>' +
      '<circle cx="16" cy="48" r="1.5"/>' +
      '<circle cx="24" cy="48" r="1.5"/>' +
      '<circle cx="32" cy="48" r="1.5"/>' +
    '</g>' +
    // اليوم المحدد بالذهبي
    '<circle cx="32" cy="40" r="4" fill="url(#grad-secondary)"/>' +
    '<circle cx="32" cy="40" r="2" fill="white"/>' +
  '</svg>',

  // 💵 الرواتب - حزمة أوراق نقدية ثلاثية الأبعاد
  payroll: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    // ظل
    '<rect x="8" y="22" width="48" height="32" rx="3" fill="#0B6E4F"/>' +
    // الورقة الخلفية
    '<rect x="6" y="18" width="48" height="32" rx="3" fill="#0B6E4F" opacity="0.6"/>' +
    // الورقة الرئيسية
    '<rect x="6" y="20" width="48" height="30" rx="3" fill="url(#grad-primary)"/>' +
    '<rect x="6" y="20" width="48" height="8" rx="3" fill="rgba(255,255,255,0.15)"/>' +
    // الإطار الداخلي
    '<rect x="10" y="24" width="40" height="22" rx="2" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="1"/>' +
    // الدائرة المركزية مع $
    '<circle cx="30" cy="35" r="8" fill="url(#grad-secondary)"/>' +
    '<circle cx="30" cy="35" r="6" fill="rgba(255,255,255,0.3)"/>' +
    '<text x="30" y="39" text-anchor="middle" font-size="10" font-weight="bold" fill="#7A5500">$</text>' +
    // أرقام في الزوايا
    '<text x="14" y="32" font-size="6" font-weight="bold" fill="white" opacity="0.8">100</text>' +
    '<text x="42" y="44" font-size="6" font-weight="bold" fill="white" opacity="0.8">100</text>' +
  '</svg>',

  // ⚙️ الإعدادات - ترس ثلاثي الأبعاد
  settings: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    // ظل الترس
    '<g transform="translate(34, 34)">' +
      '<path d="M-3 -22 L3 -22 L4 -15 Q8 -14 11 -12 L17 -15 L20 -12 L17 -6 Q19 -3 20 1 L26 3 L26 9 L20 11 Q19 15 17 18 L20 24 L17 27 L11 24 Q8 26 4 27 L3 33 L-3 33 L-4 27 Q-8 26 -11 24 L-17 27 L-20 24 L-17 18 Q-19 15 -20 11 L-26 9 L-26 3 L-20 1 Q-19 -3 -17 -6 L-20 -12 L-17 -15 L-11 -12 Q-8 -14 -4 -15 Z" fill="#3A3565" opacity="0.3"/>' +
    '</g>' +
    // الترس الرئيسي
    '<g transform="translate(32, 32)">' +
      '<path d="M-3 -22 L3 -22 L4 -15 Q8 -14 11 -12 L17 -15 L20 -12 L17 -6 Q19 -3 20 1 L26 3 L26 9 L20 11 Q19 15 17 18 L20 24 L17 27 L11 24 Q8 26 4 27 L3 33 L-3 33 L-4 27 Q-8 26 -11 24 L-17 27 L-20 24 L-17 18 Q-19 15 -20 11 L-26 9 L-26 3 L-20 1 Q-19 -3 -17 -6 L-20 -12 L-17 -15 L-11 -12 Q-8 -14 -4 -15 Z" fill="url(#grad-accent)"/>' +
      // لمعان
      '<path d="M-3 -22 L3 -22 L4 -15 Q8 -14 11 -12 L17 -15 L20 -12 L17 -6 L0 -6 Z" fill="rgba(255,255,255,0.2)"/>' +
      // الدائرة المركزية
      '<circle cx="0" cy="5" r="9" fill="#1A1530"/>' +
      '<circle cx="0" cy="5" r="7" fill="url(#grad-secondary)"/>' +
      '<circle cx="0" cy="5" r="4" fill="rgba(255,255,255,0.3)"/>' +
    '</g>' +
  '</svg>',

  // 🔧 النظام - مفتاح ربط ثلاثي الأبعاد
  system: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    // ظل
    '<path d="M52 14 L46 8 Q42 4 38 8 L34 12 Q30 16 34 20 L36 22 L20 38 L14 36 L8 42 L22 56 L28 50 L26 44 L42 28 L44 30 Q48 34 52 30 L56 26 Q60 22 56 18 Z" fill="#0B6E4F" opacity="0.3"/>' +
    // المفتاح
    '<path d="M50 12 L44 6 Q40 2 36 6 L32 10 Q28 14 32 18 L34 20 L18 36 L12 34 L6 40 L20 54 L26 48 L24 42 L40 26 L42 28 Q46 32 50 28 L54 24 Q58 20 54 16 Z" fill="url(#grad-primary)"/>' +
    // لمعان
    '<path d="M50 12 L44 6 Q40 2 36 6 L32 10 Q28 14 32 18 L34 20 L25 29 L40 14 Z" fill="rgba(255,255,255,0.25)"/>' +
    // مقبض ذهبي
    '<rect x="12" y="44" width="10" height="4" rx="2" fill="url(#grad-secondary)" transform="rotate(45 17 46)"/>' +
    // برغي مركزي
    '<circle cx="38" cy="20" r="3" fill="#5A4500"/>' +
    '<line x1="36" y1="20" x2="40" y2="20" stroke="white" stroke-width="1"/>' +
  '</svg>',

  // 🚪 خروج
  logout: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    '<path d="M14 8 L34 8 L34 16 L20 16 L20 48 L34 48 L34 56 L14 56 Z" fill="url(#grad-danger)"/>' +
    '<path d="M14 8 L34 8 L34 12 L20 12 L20 16 L14 8 Z" fill="rgba(255,255,255,0.2)"/>' +
    '<path d="M38 20 L50 32 L38 44 L38 36 L28 36 L28 28 L38 28 Z" fill="url(#grad-secondary)"/>' +
    '<path d="M38 20 L50 32 L46 32 L38 24 Z" fill="rgba(255,255,255,0.3)"/>' +
  '</svg>',

  // 🔄 تحديث
  refresh: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    '<path d="M32 8 Q48 8 56 20 L48 20 L52 32 L60 24 L60 28 Q58 12 32 8 Z" fill="url(#grad-primary)"/>' +
    '<path d="M32 56 Q16 56 8 44 L16 44 L12 32 L4 40 L4 36 Q6 52 32 56 Z" fill="url(#grad-primary)"/>' +
  '</svg>',

  // 🌙 وضع ليلي
  darkmode: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    '<path d="M32 8 Q12 8 12 32 Q12 56 32 56 Q24 48 24 32 Q24 16 32 8 Z" fill="url(#grad-accent)"/>' +
    '<path d="M32 8 Q12 8 12 32 L24 24 Q28 14 32 8 Z" fill="rgba(255,255,255,0.15)"/>' +
    '<circle cx="44" cy="20" r="2" fill="url(#grad-secondary)"/>' +
    '<circle cx="48" cy="32" r="1.5" fill="url(#grad-secondary)"/>' +
    '<circle cx="42" cy="44" r="1" fill="url(#grad-secondary)"/>' +
  '</svg>',

  // ☀️ وضع نهاري
  lightmode: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    '<circle cx="32" cy="32" r="14" fill="url(#grad-secondary)"/>' +
    '<circle cx="32" cy="32" r="10" fill="rgba(255,255,255,0.3)"/>' +
    '<g stroke="url(#grad-secondary)" stroke-width="3" stroke-linecap="round">' +
      '<line x1="32" y1="6" x2="32" y2="14"/>' +
      '<line x1="32" y1="50" x2="32" y2="58"/>' +
      '<line x1="6" y1="32" x2="14" y2="32"/>' +
      '<line x1="50" y1="32" x2="58" y2="32"/>' +
      '<line x1="14" y1="14" x2="20" y2="20"/>' +
      '<line x1="44" y1="44" x2="50" y2="50"/>' +
      '<line x1="14" y1="50" x2="20" y2="44"/>' +
      '<line x1="44" y1="20" x2="50" y2="14"/>' +
    '</g>' +
  '</svg>',

  // ☰ قائمة موبايل
  menu: '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">' +
    '<rect x="10" y="14" width="44" height="6" rx="3" fill="url(#grad-primary)"/>' +
    '<rect x="10" y="29" width="44" height="6" rx="3" fill="url(#grad-primary)"/>' +
    '<rect x="10" y="44" width="44" height="6" rx="3" fill="url(#grad-primary)"/>' +
  '</svg>'

};

/**
 * إنشاء أيقونة بالحجم المطلوب
 * @param {string} name - اسم الأيقونة
 * @param {number} size - الحجم بالبكسل (default: 32)
 * @returns {string} HTML SVG
 */
function createIcon(name, size) {
  size = size || 32;
  var icon = ICONS[name];
  if (!icon) {
    console.warn('Icon not found:', name);
    return '<span style="font-size:' + size + 'px;">❓</span>';
  }
  // إدراج الـ defs مرة واحدة في كل أيقونة
  return icon.replace('<svg ', '<svg width="' + size + '" height="' + size + '" style="display:inline-block;vertical-align:middle;" ');
}

/**
 * حقن الـ SVG defs العامة (مرة واحدة في الصفحة)
 */
function injectDefs() {
  if (document.getElementById('amin-icons-defs')) return;
  var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.id = 'amin-icons-defs';
  svg.setAttribute('width', '0');
  svg.setAttribute('height', '0');
  svg.style.position = 'absolute';
  svg.innerHTML = SVG_DEFS;
  document.body.insertBefore(svg, document.body.firstChild);
}

// حقن الـ defs تلقائياً
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', injectDefs);
} else {
  injectDefs();
}

// ===== التصدير =====
window.AminIcons = {
  create: createIcon,
  list: Object.keys(ICONS),
  ICONS: ICONS
};

})();

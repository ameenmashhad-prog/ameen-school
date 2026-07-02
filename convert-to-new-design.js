#!/usr/bin/env node

/**
 * سكريبت تحويل جميع الصفحات للتنسيق الجديد من portal.html
 * يحول من التنسيق القديم (portal.css + amin-identity.css) للتنسيق الحديث
 */

const fs = require('fs');
const path = require('path');

const NEW_DESIGN_HEAD = `<link rel="stylesheet" href="assets/design-tokens.css">
<link rel="stylesheet" href="assets/components.css">`;

const OLD_DESIGN_HEAD = `<link rel="stylesheet" href="assets/portal.css">
<link rel="stylesheet" href="assets/amin-identity.css">`;

const REQUIRED_SCRIPTS = [
  '<script src="assets/amin-theme-injector.js"></script>'
];

const UX_ENHANCEMENTS = '<script src="assets/ux-enhancements.js"></script>';

// الصفحات التي تحتاج تحديث
const PAGES_TO_UPDATE = [
  'teacher.html',
  'student.html',
  'parent.html',
  'admin.html',
  'hr.html',
  'finance-pro.html',
  'finance-cashbox.html',
  'finance-collections.html',
  'finance-credit-report.html',
  'finance-executive.html',
  'finance-receiver-reports.html',
  'counselor.html',
  'announcements.html',
  'analytics-center.html',
  'smart-calendar.html',
  'notifications.html',
  'curriculum-planner.html',
  'teacher-exams.html',
  'homework-reports.html',
  'online-exams.html',
  'student-homeworks.html',
  'homework-audit.html'
];

function convertPage(filePath) {
  try {
    let content = fs.readFileSync(filePath, 'utf8');
    
    // 1. استبدال CSS القديم بالجديد
    content = content.replace(OLD_DESIGN_HEAD, NEW_DESIGN_HEAD);
    
    // 2. إزالة CSS القديمة الإضافية
    content = content.replace(
      /<link rel="stylesheet" href="assets\/(brand-redesign|amin-v3)\.css">\s*/g,
      ''
    );
    
    // 3. إضافة amin-theme-injector في النهاية قبل </body>
    if (!content.includes('amin-theme-injector.js')) {
      content = content.replace(
        '</body>',
        `  ${REQUIRED_SCRIPTS[0]}\n</body>`
      );
    }
    
    // 4. التأكد من أن ux-enhancements.js موجود
    if (!content.includes('ux-enhancements.js')) {
      content = content.replace(
        '</body>',
        `  ${UX_ENHANCEMENTS}\n</body>`
      );
    }
    
    // 5. تحديث <meta name="theme-color">
    content = content.replace(
      /<meta name="theme-color" content="#[0-9A-Fa-f]{6}">/,
      '<meta name="theme-color" content="#0B6E4F">'
    );
    
    fs.writeFileSync(filePath, content, 'utf8');
    console.log(`✅ ${filePath}`);
    return true;
  } catch (error) {
    console.error(`❌ ${filePath}: ${error.message}`);
    return false;
  }
}

// التنفيذ
console.log('🔄 جاري تحويل الصفحات للتنسيق الجديد...\n');

let converted = 0;
let failed = 0;

PAGES_TO_UPDATE.forEach(page => {
  if (fs.existsSync(page)) {
    if (convertPage(page)) {
      converted++;
    } else {
      failed++;
    }
  }
});

console.log(`\n✨ اكتمل التحويل!`);
console.log(`✅ تم تحويل: ${converted} صفحة`);
console.log(`❌ فشل: ${failed} صفحة`);

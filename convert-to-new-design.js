#!/usr/bin/env node
/*
 * Amin Tactile Identity — unified design migration (idempotent & safe)
 * -----------------------------------------------------------------
 * يوحّد كل صفحات HTML على نظام هوية واحد: assets/amin.css
 * (أخضر زمردي #0B6E4F + ذهبي #B8860B + كحلي #3A3565، نجمة ثمانية،
 *  عمق لمسي ثلاثي، RTL، وضع ليلي، responsive).
 *
 * ما يفعله بأمان (قابل لإعادة التشغيل):
 *   1) يزيل طبقات الثيم القديمة من <head> (portal/amin-identity/brand-redesign/amin-v3/design-tokens/components).
 *   2) يضيف رابطاً واحداً: assets/amin.css (مرة واحدة فقط).
 *
 * يُبقي: ملفات CSS الخاصة بكل صفحة (مثل achievements.css) وروابط JS كما هي.
 * ملاحظة: الصفحات الأربع ذات التنسيق الداكن المضمّن عولجت يدوياً بتحويل
 *       تنسيقها المضمّن إلى الهوية الفاتحة أثناء التهجير الأول.
 *
 * التشغيل: node convert-to-new-design.js
 */
const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const AMIN_LINK = '  <link rel="stylesheet" href="assets/amin.css">\n';
const THEME_RE = /<link[^>]*assets\/(portal|amin-identity|brand-redesign|amin-v3|design-tokens|components)\.css[^>]*>\s*\n?/g;
const AMIN_RE  = /<link[^>]*assets\/amin\.css[^>]*>\s*\n?/g;

function migratePage(file){
  let html = fs.readFileSync(file, 'utf8');
  html = html.replace(THEME_RE, '').replace(AMIN_RE, '');
  if (!html.includes('assets/amin.css"')) {
    html = html.replace(/(<\/title>\s*)/, `$1${AMIN_LINK}`);
  }
  fs.writeFileSync(file, html, 'utf8');
}

const pages = fs.readdirSync(ROOT).filter(f => f.endsWith('.html'));
pages.forEach(f => migratePage(path.join(ROOT, f)));
console.log(`✅ وُحّدت ${pages.length} صفحة على assets/amin.css (idempotent)`);

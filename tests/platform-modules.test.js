// Platform modules registry smoke test
// Run: node tests/platform-modules.test.js
const fs = require('fs');
const vm = require('vm');
const path = require('path');
const root = path.join(__dirname, '..');
const code = fs.readFileSync(path.join(root, 'assets/platform-modules.js'), 'utf8');
const context = {
  window: {},
  localStorage: { getItem(){ return 'ar'; } },
  document: { documentElement: { lang: 'ar' } },
  console
};
vm.runInNewContext(code, context, { filename: 'platform-modules.js' });
const P = context.window.AMIN_PLATFORM;
if (!P || !Array.isArray(P.modules) || !Array.isArray(P.groups)) throw new Error('Registry missing');
const groupKeys = new Set(P.groups.map(g => g.key));
const moduleKeys = new Set();
const hrefs = new Set();
for (const m of P.modules) {
  if (!m.key || !m.group || !m.href) throw new Error('Invalid module: ' + JSON.stringify(m));
  if (moduleKeys.has(m.key)) throw new Error('Duplicate module key: ' + m.key);
  moduleKeys.add(m.key);
  if (!groupKeys.has(m.group)) throw new Error('Missing group for ' + m.key + ': ' + m.group);
  const file = m.href.split('?')[0];
  if (!fs.existsSync(path.join(root, file))) throw new Error('Missing html route for ' + m.key + ': ' + file);
  if (hrefs.has(m.href) && m.key !== 'labsActivities') throw new Error('Duplicate href: ' + m.href);
  hrefs.add(m.href);
  for (const lang of ['ar','fa','en']) {
    if (!m.title || !m.title[lang]) throw new Error(`Missing ${lang} title for ${m.key}`);
  }
}
console.log('platform modules smoke tests passed');

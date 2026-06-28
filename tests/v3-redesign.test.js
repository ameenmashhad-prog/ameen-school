// V3 redesign static smoke test
// Run: node tests/v3-redesign.test.js
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
function read(p){return fs.readFileSync(path.join(root,p),'utf8')}
function assert(c,m){if(!c)throw new Error(m)}
const css = read('assets/amin-v3.css');
['--c-primary:#6B2D6B','--c-accent:#D4956A','--c-bg:#F5EDE4','--c-surface:#FDF6F0'].forEach(t=>assert(css.includes(t), 'missing token '+t));
assert(css.includes('.sidebar'), 'sidebar override missing');
assert(css.includes('.topbar'), 'topbar override missing');
assert(css.includes('.card'), 'card override missing');
assert(css.includes('[data-theme="dark"]'), 'dark mode overrides missing');
const htmlFiles = fs.readdirSync(root).filter(f=>f.endsWith('.html'));
const missing = htmlFiles.filter(f=>!read(f).includes('assets/amin-v3.css'));
assert(missing.length===0, 'HTML pages missing amin-v3.css: '+missing.join(', '));
const sw = read('sw.js');
assert(sw.includes('/assets/amin-v3.css'), 'service worker must cache v3 css');
console.log('v3 redesign tests passed');

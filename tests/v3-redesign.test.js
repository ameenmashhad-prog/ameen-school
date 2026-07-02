// Amin Tactile Identity — static smoke test
// Run: node tests/v3-redesign.test.js
// Verifies the unified design system (assets/amin.css) is wired everywhere.
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
function read(p){ return fs.readFileSync(path.join(root, p), 'utf8'); }
function assert(c, m){ if(!c) throw new Error(m); }

const css = read('assets/amin.css');
// Identity tokens (Amin Tactile: emerald + gold + indigo)
['--primary:#0B6E4F', '--secondary:#B8860B', '--accent:#3A3565', '--bg:#F7F5F0',
 '--success:#16A34A', '--warning:#D97706', '--danger:#DC2626'].forEach(t =>
  assert(css.includes(t), 'missing token ' + t));
// Component vocabulary used across the legacy + new pages
['.shell', '.sidebar', '.nav', '.brand', '.card', '.kpi', '.table-flat', 'table',
 '.btn-3d-primary', '.badge', '.modal', 'body.dark'].forEach(s =>
  assert(css.includes(s), 'missing rule/selector ' + s));

// Every HTML page must link the single design system
const htmlFiles = fs.readdirSync(root).filter(f => f.endsWith('.html'));
const missing = htmlFiles.filter(f => !read(f).includes('assets/amin.css'));
assert(missing.length === 0, 'HTML pages missing amin.css: ' + missing.join(', '));
// ...and must NOT link the old theme layers
const oldTheme = ['portal.css', 'amin-identity.css', 'brand-redesign.css', 'amin-v3.css', 'design-tokens.css', 'components.css'];
const stale = htmlFiles.filter(f => oldTheme.some(t => read(f).includes('assets/' + t)));
assert(stale.length === 0, 'HTML pages still linking old theme: ' + stale.join(', '));

// Service worker must cache the unified CSS
const sw = read('sw.js');
assert(sw.includes("'/assets/amin.css',"), 'service worker must cache amin.css');

console.log('Amin Tactile redesign tests passed — ' + htmlFiles.length + ' pages, single design system.');

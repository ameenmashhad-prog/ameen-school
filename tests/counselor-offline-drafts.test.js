// Counselor offline drafts static smoke test
// Run: node tests/counselor-offline-drafts.test.js
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const js = fs.readFileSync(path.join(root, 'assets/counselor.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'counselor.html'), 'utf8');
function assert(cond, msg){ if(!cond) throw new Error(msg); }
assert(js.includes('DRAFT_KEY'), 'draft storage key missing');
assert(js.includes('saveLiveDraft'), 'live autosave function missing');
assert(js.includes('savePostDraft'), 'post-session draft function missing');
assert(js.includes('syncDraft'), 'draft sync function missing');
assert(js.includes('restoreDraft'), 'draft restore function missing');
assert(js.includes('window.addEventListener(\'online\''), 'online sync listener missing');
assert(html.includes('offlineStatus'), 'offline status indicator missing');
assert(html.includes('draftsBtn'), 'drafts button missing');
console.log('counselor offline drafts tests passed');

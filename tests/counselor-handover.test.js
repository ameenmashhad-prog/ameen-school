// Counselor handover static smoke test
// Run: node tests/counselor-handover.test.js
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
function read(p){return fs.readFileSync(path.join(root,p),'utf8')}
function assert(c,m){if(!c)throw new Error(m)}
const sql = read('sql/107_counseling_handover_protocol.sql');
assert(sql.includes('counseling_handover_notes'), 'handover table missing');
assert(sql.includes('create_counseling_handover'), 'create handover RPC missing');
assert(sql.includes('accept_counseling_handover'), 'accept handover RPC missing');
assert(sql.includes('counseling_handover_health_check'), 'handover health check missing');
const js = read('assets/counselor.js');
assert(js.includes('renderHandover'), 'handover UI renderer missing');
assert(js.includes('openHandover'), 'open handover UI missing');
assert(js.includes('acceptHandover'), 'accept handover UI missing');
const html = read('counselor.html');
assert(html.includes('data-view="handover"'), 'handover tab missing');
console.log('counselor handover tests passed');

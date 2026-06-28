// Security governance static smoke test
// Run: node tests/security-governance.test.js
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
function read(p){return fs.readFileSync(path.join(root,p),'utf8')}
function assert(cond,msg){if(!cond)throw new Error(msg)}

const proxy = read('api/proxy.js');
assert(!/Access-Control-Allow-Origin['"],\s*['"]\*/.test(proxy), 'proxy must not use wildcard CORS');
assert(proxy.includes('ALLOWED_PREFIXES'), 'proxy must whitelist Supabase prefixes');
assert(proxy.includes('AbortController'), 'proxy must use timeout/AbortController');

const tgju = read('api/exchange-tgju.js');
assert(!/Access-Control-Allow-Origin['"],\s*['"]\*/.test(tgju), 'TGJU endpoint must not use wildcard CORS');

const registration = read('assets/registration.js');
assert(!registration.includes('${d}${m}${y}'), 'registration passwords must not be date based');
assert(registration.includes('randomTempPassword'), 'registration must generate random temp passwords');

const counselor = read('assets/counselor.js');
assert(!/localStorage\.setItem\(['"]counselor_lock_pin['"]/.test(counselor), 'counselor PIN must not be stored plaintext');
assert(counselor.includes('counselor_lock_pin_hash'), 'counselor lock must store a hash');

const vercel = JSON.parse(read('vercel.json'));
const headers = JSON.stringify(vercel.headers || []);
assert(headers.includes('Content-Security-Policy'), 'vercel must define CSP');
assert(headers.includes('X-Frame-Options'), 'vercel must define X-Frame-Options');

const platform = read('assets/platform-modules.js');
assert(platform.includes("key:'securityGovernance'"), 'security governance module missing');
assert(fs.existsSync(path.join(root,'security-governance.html')), 'security-governance.html missing');
assert(fs.existsSync(path.join(root,'sql/105_security_governance_health_check.sql')), 'SQL 105 missing');


const sg = read('assets/security-governance.js');
assert(sg.includes('security_role_access_matrix_check'), 'security page must load role access matrix');
assert(fs.existsSync(path.join(root,'sql/106_role_access_matrix_check.sql')), 'SQL 106 missing');

console.log('security governance static tests passed');

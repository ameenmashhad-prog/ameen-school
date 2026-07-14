// Forms v3 / registration security regression checks
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const assert = (condition, message) => { if (!condition) throw new Error(message); };

const adminRoutes = [
  'get-submission',
  'list-submissions',
  'list-versions',
  'publish-form',
  'restore-version',
  'save-draft',
  'update-submission-status'
];
adminRoutes.forEach((name) => {
  const source = read(`next-forms-v3/app/api/forms/rpc/${name}/route.js`);
  assert(source.includes('handleAdminRpc'), `${name} must require admin authorization`);
});

const publicRoutes = [
  'request-upload-ticket',
  'submit-family-registration-v3',
  'submit-financial-permission',
  'submit-leave-request',
  'submit-student-registration',
  'submit-student-registration-packet',
  'submit-teacher-evaluation'
];
publicRoutes.forEach((name) => {
  const source = read(`next-forms-v3/app/api/forms/rpc/${name}/route.js`);
  assert(source.includes('handlePublicRpc'), `${name} must use the public security/rate-limit handler`);
});

const apiSecurity = read('next-forms-v3/lib/security/forms-api-security.js');
assert(apiSecurity.includes('auth.getUser'), 'admin API must verify the Supabase JWT');
assert(apiSecurity.includes('forms_rate_limit_check_v3'), 'public API must use the database rate limiter');
assert(apiSecurity.includes('origin_not_allowed'), 'forms API must enforce same-origin browser requests');

const upload = read('next-forms-v3/app/api/forms/upload-file/route.js');
assert(upload.includes('matchesFileSignature'), 'uploads must validate file signatures');
assert(upload.includes('upsert: false'), 'upload tickets must not overwrite existing objects');
assert(!upload.includes('upsert: true'), 'uploads must not enable overwrite');

const sql = read('sql/archive/170_critical_registration_and_forms_security_lockdown.sql');
assert(sql.includes('activate_registered_user_rpc_internal_v170'), 'activation implementation must be hidden behind a secure wrapper');
assert(sql.includes('forbidden_registration_review'), 'activation wrapper must verify the reviewer role');
assert(sql.includes('forms_scrub_passwords_trigger_v170'), 'submission passwords must be scrubbed');
assert(sql.includes('forms_rate_limit_check_v3'), 'SQL rate limiter is missing');
assert(sql.includes("drop policy if exists registration_photos_select_all"), 'public registration-photo reads must be removed');

const adminPage = read('registrations-admin.html');
assert(!adminPage.includes("sb.rpc('activate_registered_user',"), 'admin UI must not fall back to the unsafe activation RPC');
assert(!adminPage.includes('submission_initial_password'), 'admin UI must not load or print stored passwords');
assert(adminPage.includes('showActivationCredentials'), 'admin UI must show one-time activation credentials securely');

const familyShell = read('next-forms-v3/components/family-registration-v3-shell.jsx');
assert(!familyShell.includes('birthDatePasswordFromISO'), 'Forms v3 must not derive a password from birth date');
assert(!familyShell.includes('student_initial_password: student.student_initial_password'), 'Forms v3 must not submit generated passwords');
const mapDeclaration = familyShell.indexOf('const financeCatalogMap = useMemo(');
const firstMapEffectUse = familyShell.indexOf('buildDynamicPaymentRows(current.students, current.payment_entries, financeCatalogMap)');
assert(mapDeclaration >= 0 && firstMapEffectUse >= 0 && mapDeclaration < firstMapEffectUse, 'financeCatalogMap must be initialized before effects use it');

console.log('forms security lockdown tests passed');

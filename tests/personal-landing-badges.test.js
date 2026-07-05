// Personal landing + computed badges static test
// Run: node tests/personal-landing-badges.test.js
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
function read(p){return fs.readFileSync(path.join(root,p),'utf8')}
function assert(c,m){if(!c)throw new Error(m)}
const sql = read('sql/archive/109_personal_landing_dashboard_badge_progress.sql');
assert(sql.includes('get_my_badge_progress'), 'badge progress RPC missing');
assert(sql.includes('get_my_landing_home'), 'landing home RPC missing');
assert(sql.includes('student_perfect_attendance_30'), 'student attendance badge missing');
assert(sql.includes('teacher_lesson_prep_streak'), 'teacher lesson prep badge missing');
assert(sql.includes('teacher_homework_followup'), 'teacher homework follow-up badge missing');
const portal = read('portal.html');
assert(portal.includes('homeDashboard'), 'portal home dashboard missing');
assert(portal.includes('data-portal-tab="home"'), 'portal home tab missing');
const js = read('assets/unified-portal.js');
assert(js.includes('get_my_landing_home'), 'portal must call landing home RPC');
assert(js.includes('portalClock'), 'portal live clock missing');
assert(js.includes('tripleHtml'), 'portal triple calendar missing');
const ach = read('assets/achievements.js');
assert(ach.includes('get_my_badge_progress'), 'achievements page must call progress RPC');
assert(ach.includes('progressCard'), 'progress card renderer missing');
console.log('personal landing and computed badges tests passed');

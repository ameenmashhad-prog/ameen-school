// Curriculum planner static smoke test
// Run: node tests/curriculum-planner.test.js
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
function read(p){return fs.readFileSync(path.join(root,p),'utf8')}
function assert(c,m){if(!c)throw new Error(m)}
const sql = read('sql/archive/110_curriculum_planner_editable.sql');
['curriculum_sources','curriculum_lessons','curriculum_plans','curriculum_plan_slots','curriculum_plan_snapshots','curriculum_plan_audit'].forEach(t=>assert(sql.includes(t), 'missing table '+t));
['get_curriculum_planner_payload','curriculum_create_from_text','curriculum_update_slot','curriculum_add_custom_lesson','curriculum_redistribute_remaining','curriculum_planner_health_check'].forEach(f=>assert(sql.includes(f), 'missing function '+f));
const js = read('assets/curriculum-planner.js');
assert(js.includes('planner:plannerView'), 'render mapping for planner tab missing');
assert(js.includes('import:importView'), 'render mapping for import tab missing');
assert(js.includes('progress:progressView'), 'render mapping for progress tab missing');
assert(js.includes('audit:auditView'), 'render mapping for audit tab missing');
assert(js.includes('dragstart'), 'drag/drop support missing');
assert(js.includes('curriculum_update_slot'), 'slot update RPC missing in UI');
assert(js.includes('curriculum_redistribute_remaining'), 'redistribution RPC missing in UI');
assert(fs.existsSync(path.join(root,'curriculum-planner.html')), 'curriculum planner page missing');
const platform = read('assets/platform-modules.js');
assert(platform.includes("key:'curriculumPlanner'"), 'platform module missing');

const sql112 = read('sql/archive/112_curriculum_holidays_weekly_schedule_fix.sql');
['curriculum_is_school_day','curriculum_infer_lessons_per_week','get_curriculum_holiday_context','curriculum_seed_iran_holidays_for_academic_years'].forEach(f=>assert(sql112.includes(f), 'missing holiday/schedule function '+f));
assert(sql112.includes("country_code='IR'") || sql112.includes("'IR'"), 'Iran country context missing');
const plannerJs = read('assets/curriculum-planner.js');
assert(plannerJs.includes('get_curriculum_holiday_context'), 'UI must load holiday context');
assert(plannerJs.includes('0 = اكتشاف تلقائي'), 'UI must support auto weekly lesson detection');

console.log('curriculum planner tests passed');

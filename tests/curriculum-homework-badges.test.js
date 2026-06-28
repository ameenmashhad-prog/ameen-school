// Curriculum-homework link and badge levels static test
// Run: node tests/curriculum-homework-badges.test.js
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
function read(p){return fs.readFileSync(path.join(root,p),'utf8')}
function assert(c,m){if(!c)throw new Error(m)}
const sql = read('sql/116_curriculum_homework_link_badge_levels.sql');
['curriculum_slot_id','get_teacher_curriculum_topics','link_homework_to_curriculum','_achievement_level_info'].forEach(x=>assert(sql.includes(x),'missing '+x));
const teacher = read('assets/teacher-dashboard.js');
assert(teacher.includes('hwCurriculumSlot'), 'teacher homework form missing curriculum slot select');
assert(teacher.includes('link_homework_to_curriculum'), 'teacher save homework must link curriculum');
assert(teacher.includes('curriculumTopicOptions'), 'teacher curriculum topic options missing');
const achievements = read('assets/achievements.js');
assert(achievements.includes('badge-levels-row'), 'achievement levels UI missing');
console.log('curriculum-homework badge levels tests passed');

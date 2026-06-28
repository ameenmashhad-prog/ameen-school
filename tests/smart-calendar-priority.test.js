// Smart calendar priority UI static test
// Run: node tests/smart-calendar-priority.test.js
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
function read(p){return fs.readFileSync(path.join(root,p),'utf8')}
function assert(c,m){if(!c)throw new Error(m)}
const js = read('assets/smart-calendar.js');
assert(js.includes('priorityScore'), 'priority scoring missing');
assert(js.includes('setAgendaFilter'), 'agenda filter missing');
assert(js.includes('setCalendarFilter'), 'calendar filter missing');
assert(js.includes('مركز اليوم الذكي'), 'daily center title missing');
assert(js.includes('safeInternalUrl'), 'safe internal URL helper missing');
const css = read('assets/smart-calendar.css');
assert(css.includes('calendar-priority-kpis'), 'priority KPI styles missing');
assert(css.includes('priority-panel'), 'priority panel styles missing');
console.log('smart calendar priority tests passed');

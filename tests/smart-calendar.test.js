// اختبارات محلية بسيطة للتقويم الثلاثي — بدون إنترنت/CDN
// التشغيل: node tests/smart-calendar.test.js
const assert = require('assert');
const path = require('path');
const TripleDate = require(path.join(__dirname, '..', 'libs', 'calendar-lib.js'));

function testTripleDate(){
  const d = new TripleDate('2026-06-23');
  const g = d.formatGregorian('YYYY-MM-DD');
  const s = d.formatPersian('YYYY/MM/DD');
  const h = d.formatHijri('YYYY/MM/DD');
  assert.strictEqual(g, '2026-06-23');
  assert.ok(/^14\d{2}\/\d{2}\/\d{2}$/.test(s), 'solar format');
  assert.ok(/^14\d{2}\/\d{2}\/\d{2}$/.test(h), 'lunar format');
}

function testMonthDays(){
  assert.strictEqual(TripleDate.daysInGregorianMonth(2026, 2), 28);
  assert.strictEqual(TripleDate.daysInGregorianMonth(2024, 2), 29);
}

function testAll(){
  testTripleDate();
  testMonthDays();
  console.log('smart-calendar tests passed');
}

testAll();

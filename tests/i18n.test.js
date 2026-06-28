// Simple static i18n coverage smoke test
// Run: node tests/i18n.test.js
const fs = require('fs');
const path = require('path');
const i18n = fs.readFileSync(path.join(__dirname,'..','assets','i18n.js'),'utf8');
['en','fa'].forEach(lang=>{
  if(!i18n.includes(`${lang}:{`)) throw new Error(`Missing ${lang} dictionary`);
});
['البوابة الموحدة','تسجيل الخروج','النظام المالي','الواجبات','التقويم الذكي','الرصيد الدائن'].forEach(key=>{
  if(!i18n.includes(`'${key}'`)) throw new Error(`Missing key ${key}`);
});
const htmlFiles = fs.readdirSync(path.join(__dirname,'..')).filter(f=>f.endsWith('.html'));
for(const f of htmlFiles){
  const html = fs.readFileSync(path.join(__dirname,'..',f),'utf8');
  if(!html.includes('assets/i18n.css')) throw new Error(`${f} missing i18n.css`);
  if(!html.includes('assets/i18n.js')) throw new Error(`${f} missing i18n.js`);
}
console.log('i18n smoke tests passed');

(function(){
'use strict';
const SOLAR_MONTHS=['فروردين','أرديبهشت','خرداد','تير','مرداد','شهريور','مهر','آبان','آذر','دي','بهمن','اسفند'];
function pad(v){return String(v).padStart(2,'0')}
function iso(d=new Date()){return d.toISOString().slice(0,10)}
function esc(v){return String(v==null?'':v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
function parseSolarKey(key){
  const raw=String(key||'').trim();
  const m=raw.match(/^(\d{4})-(\d{2})$/);
  if(!m)return null;
  return {year:Number(m[1]),month:Number(m[2]),key:`${m[1]}-${m[2]}`};
}
function gregToSolar(dateIso){
  try{
    if(!dateIso||!window.TripleDate)return null;
    const td=new TripleDate(String(dateIso).slice(0,10));
    const y=Number(td.persian.year),m=Number(td.persian.month),d=Number(td.persian.day);
    return {year:y,month:m,day:d,key:`${y}-${pad(m)}`,monthName:SOLAR_MONTHS[m-1]||('شهر '+m),text:`${pad(d)} ${SOLAR_MONTHS[m-1]||('شهر '+m)} ${y}`,short:`${y}/${pad(m)}/${pad(d)}`};
  }catch{return null}
}
function solarShift(year,month,offset){
  const total=(Number(year)*12)+(Number(month)-1)+Number(offset||0);
  const y=Math.floor(total/12);
  const m=(total%12)+1;
  return {year:y,month:m,key:`${y}-${pad(m)}`};
}
function solarToIso(year,month,day){
  try{
    if(!window.TripleDate)return null;
    return TripleDate.fromPersian(Number(year),Number(month),Number(day)).toISO();
  }catch{return null}
}
function safeSolarToIso(year,month,day){
  for(let d=Number(day||1);d>=1;d--){
    const out=solarToIso(year,month,d);
    if(out)return out;
  }
  return solarToIso(year,month,1);
}
function currentSolarMonthKey(){
  const sol=gregToSolar(iso());
  return sol?sol.key:new Date().toISOString().slice(0,7);
}
function solarMonthRangeFromKey(key){
  const parsed=parseSolarKey(key);
  if(!parsed)return {key:String(key||''),label:String(key||''),start:'',end:'',gregorianLabel:'—'};
  const start=safeSolarToIso(parsed.year,parsed.month,1)||'';
  const next=solarShift(parsed.year,parsed.month,1);
  const nextStart=safeSolarToIso(next.year,next.month,1)||'';
  let end='';
  if(nextStart){
    const d=new Date(nextStart+'T00:00:00');
    d.setDate(d.getDate()-1);
    end=d.toISOString().slice(0,10);
  }
  const label=`${SOLAR_MONTHS[parsed.month-1]||('شهر '+parsed.month)} ${parsed.year}`;
  return {key:parsed.key,year:parsed.year,month:parsed.month,label,start,end,gregorianLabel:start&&end?`${start} → ${end}`:(start||'—')};
}
function solarMonthKeyFromIso(dateIso){const sol=gregToSolar(dateIso);return sol?sol.key:''}
function dualDate(dateIso){
  const isoDate=String(dateIso||'').slice(0,10);
  if(!isoDate)return '—';
  const sol=gregToSolar(isoDate);
  return sol?`ش ${sol.short} • م ${isoDate}`:isoDate;
}
function monthOptions(seedKeys=[],monthsBack=12,monthsForward=2){
  const map=new Map();
  const current=currentSolarMonthKey();
  for(let i=monthsBack;i>=-monthsForward;i--){
    const meta=solarMonthRangeFromKey(shiftSolarMonthKey(current,-i));
    if(meta.key)map.set(meta.key,meta);
  }
  (Array.isArray(seedKeys)?seedKeys:[]).filter(Boolean).forEach(key=>{
    const normalized=/^\d{4}-\d{2}$/.test(String(key||''))?String(key):solarMonthKeyFromIso(String(key).slice(0,10));
    if(normalized && !map.has(normalized))map.set(normalized,solarMonthRangeFromKey(normalized));
  });
  return [...map.values()].sort((a,b)=>String(b.key).localeCompare(String(a.key)));
}
function buildMonthSelect(id,value,seedKeys,monthsBack=12,monthsForward=2){
  const current=value||currentSolarMonthKey();
  return `<select id="${esc(id)}" class="select">${monthOptions(seedKeys,monthsBack,monthsForward).map(x=>`<option value="${esc(x.key)}" ${x.key===current?'selected':''}>${esc(x.label)} — ${esc(x.gregorianLabel)}</option>`).join('')}</select>`;
}
function shiftSolarMonthKey(key,offset){
  const base=parseSolarKey(key)||parseSolarKey(currentSolarMonthKey());
  return solarShift(base.year,base.month,offset).key;
}
window.FinanceRuntime={SOLAR_MONTHS,pad,iso,esc,parseSolarKey,gregToSolar,solarToIso,safeSolarToIso,solarShift,shiftSolarMonthKey,currentSolarMonthKey,solarMonthKeyFromIso,solarMonthRangeFromKey,monthOptions,buildMonthSelect,dualDate};
}());

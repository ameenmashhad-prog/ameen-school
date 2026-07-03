(function(){'use strict';
function S(inner){return '<svg class="amin-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+inner+'</svg>';}
function starPath(cx,cy,R,r){var p=[],n=8;for(var i=0;i<2*n;i++){var a=Math.PI/n*i-Math.PI/2,rad=(i%2===0)?R:r;p.push((cx+Math.cos(a)*rad).toFixed(2)+','+(cy+Math.sin(a)*rad).toFixed(2));}return '<path d="M'+p.join('L')+'z"/>';}
var STAR=S(starPath(12,12,9.4,4));
var ICONS={  home:S("<path d='M4 11.5 12 4l8 7.5'/><path d='M6 10v9h12v-9'/><path d='M10 19v-5h4v5'/>"),
  menu:S("<path d='M4 7h16M4 12h16M4 17h16'/>"),
  users:S("<circle cx='9' cy='8.5' r='3.2'/><path d='M3.5 19a5.5 5.5 0 0 1 11 0'/><circle cx='16.5' cy='9' r='2.4'/><path d='M15 14.3A4.6 4.6 0 0 1 21 18.5'/>"),
  person:S("<circle cx='12' cy='8.5' r='3.6'/><path d='M5.5 20a6.5 6.5 0 0 1 13 0'/>"),
  chart:S("<path d='M4 20V12M9 20V6M14 20v-5M19 20v-9'/><path d='M3 20h18'/>"),
  trendUp:S("<path d='M3 17l5.5-5.5 4 3L21 7'/><path d='M15 7h6v6'/>"),
  trendDown:S("<path d='M3 7l5.5 5.5 4-3L21 17'/><path d='M15 17h6v-6'/>"),
  clipboard:S("<rect x='5.5' y='4.5' width='13' height='16.5' rx='2'/><rect x='9' y='2.8' width='6' height='3.4' rx='1'/><path d='M9 12h6M9 15.5h6'/>"),
  books:S("<path d='M12 6.2c-1.8-1.2-4.4-1.2-6.4 0v11.6c2-1.2 4.6-1.2 6.4 0 1.8-1.2 4.4-1.2 6.4 0V6.2c-2-1.2-4.6-1.2-6.4 0z'/><path d='M12 6.2v11.6'/>"),
  book:S("<path d='M4 5.5C6 4.5 8 4.5 12 5.5c4-1 6-1 8 .5v12c-2-1.2-4-1.5-8-.5-4-1-6-1-8 0z'/><path d='M12 5.5v12'/>"),
  note:S("<path d='M4 20l4.2-.9L19 8.9l-3.3-3.3L4.9 15.8z'/><path d='M14.5 6.3l3.2 3.2'/>"),
  doc:S("<path d='M7 3.5h7l4 4v13H7z'/><path d='M14 3.5v4h4'/><path d='M9.5 12h6M9.5 15.5h6'/>"),
  mail:S("<rect x='3.5' y='5.5' width='17' height='13' rx='2'/><path d='M4 7l8 6 8-6'/>"),
  calendar:S("<rect x='4' y='5.5' width='16' height='15.5' rx='2.5'/><path d='M4 10h16M8.5 3.5v4M15.5 3.5v4'/><circle cx='9' cy='14.5' r='.9'/><circle cx='14.5' cy='14.5' r='.9'/>"),
  bell:S("<path d='M6 17v-5.5a6 6 0 0 1 12 0V17l1.4 1.8H4.6z'/><path d='M10 20a2 2 0 0 0 4 0'/>"),
  settings:S("<circle cx='12' cy='12' r='3.1'/><path d='M12 2.6v3M12 18.4v3M2.6 12h3M18.4 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2'/>"),
  shield:S("<path d='M12 3l7 2.8v5.8c0 4.3-3 7.6-7 9.1-4-1.5-7-4.8-7-9.1V5.8z'/><path d='M9 11.8 11 13.8 15.2 9.5'/>"),
  lock:S("<rect x='5' y='10.5' width='14' height='9.5' rx='2'/><path d='M8 10.5V7.5a4 4 0 0 1 8 0v3'/><circle cx='12' cy='15' r='1.3'/>"),
  key:S("<circle cx='8' cy='8' r='3.8'/><path d='M10.6 10.6 19 19M16 16l2.2-2.2M13.8 18.2 16 16'/>"),
  print:S("<path d='M7 9V4h10v5'/><rect x='4' y='9' width='16' height='7.5' rx='1.5'/><rect x='7.5' y='13.5' width='9' height='6' rx='1'/><circle cx='16.5' cy='12' r='.7'/>"),
  phone:S("<path d='M6.5 3.5h3l1.4 4-2 1.5a11 11 0 0 0 5 5l1.5-2 4 1.4v3a2 2 0 0 1-2.2 2A15.5 15.5 0 0 1 4.5 5.7 2 2 0 0 1 6.5 3.5z'/>"),
  money:S("<circle cx='12' cy='12' r='8'/><circle cx='12' cy='12' r='4.2'/><path d='M12 7.6v8.8'/>"),
  cash:S("<rect x='3' y='7' width='18' height='11' rx='2'/><circle cx='12' cy='12.5' r='2.3'/><path d='M6 7V5.5h12V7'/>"),
  card:S("<rect x='3' y='6' width='18' height='12' rx='2.6'/><path d='M3 10h18'/><path d='M6.5 14.5h4.5'/>"),
  trophy:S("<path d='M7.5 4.5h9v3.8a4.5 4.5 0 0 1-9 0z'/><path d='M7.5 5.5H4.5v2a3 3 0 0 0 3 3M16.5 5.5h3v2a3 3 0 0 1-3 3'/><path d='M10 13h4l.8 4H9.2z'/><path d='M9.5 20h5'/>"),
  star:STAR,
  check:S("<path d='M4.5 12.5 9.5 17.5 19.5 6.5'/>"),
  close:S("<path d='M6.5 6.5 17.5 17.5M17.5 6.5 6.5 17.5'/>"),
  warning:S("<path d='M12 3.5 21.5 20H2.5z'/><path d='M12 10v4.5'/><circle cx='12' cy='17' r='.85'/>"),
  box:S("<path d='M3.5 8 12 4l8.5 4L12 12z'/><path d='M3.5 8v8L12 20l8.5-4V8'/><path d='M12 12v8'/>"),
  refresh:S("<path d='M20 11a8 8 0 0 0-14.3-4.6M4 5v3.5h3.5'/><path d='M4 13a8 8 0 0 0 14.3 4.6M20 19v-3.5h-3.5'/>"),
  eye:S("<path d='M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z'/><circle cx='12' cy='12' r='2.6'/>"),
  crown:S("<path d='M3.5 8 7 12l5-6.5L17 12l3.5-4v9.5H3.5z'/>"),
  bolt:S("<path d='M13 2.5 5 13.5H11l-1 8 9-12h-6z'/>"),
  link:S("<path d='M9.5 14.5 14.5 9.5'/><path d='M8.2 12.8 6 15a3.5 3.5 0 0 0 5 5l2.2-2.2'/><path d='M15.8 11.2 18 9a3.5 3.5 0 0 0-5-5L10.8 6.2'/>"),
  plus:S("<path d='M12 5v14M5 12h14'/>"),
  minus:S("<path d='M5 12h14'/>"),
  download:S("<path d='M12 3.5v10.5M8 11l4 4 4-4'/><path d='M5 19.5h14'/>"),
  upload:S("<path d='M12 20.5V10M8 14l4-4 4 4'/><path d='M5 4.5h14'/>"),
  folder:S("<path d='M3.5 6.5A1.5 1.5 0 0 1 5 5h4l2 2.3H20a1.5 1.5 0 0 1 1.5 1.5v9A1.5 1.5 0 0 1 20 19.3H5a1.5 1.5 0 0 1-1.5-1.5z'/>"),
  target:S("<circle cx='12' cy='12' r='8.6'/><circle cx='12' cy='12' r='4.6'/><circle cx='12' cy='12' r='1'/>"),
  wrench:S("<path d='M15.5 6.5a3.6 3.6 0 0 0-4.7 4.4L4.7 17.4 6.6 19.3 13.1 12.8a3.6 3.6 0 0 0 4.4-4.7L16.2 9.8 14.2 7.8z'/>"),
  bus:S("<rect x='4.5' y='4' width='15' height='13' rx='2.5'/><path d='M4.5 11h15'/><circle cx='8' cy='18' r='1.6'/><circle cx='16' cy='18' r='1.6'/><path d='M7.5 7.5h9'/>"),
  heart:S("<path d='M12 20.5S4 15 4 9.4A4 4 0 0 1 12 7.6 4 4 0 0 1 20 9.4C20 15 12 20.5 12 20.5z'/>"),
  moon:S("<path d='M20 14.8A8 8 0 0 1 9.2 4 7 7 0 1 0 20 14.8z'/>"),
  sun:S("<circle cx='12' cy='12' r='4'/><path d='M12 2.7v2.4M12 18.9v2.4M2.7 12h2.4M18.9 12h2.4M5.2 5.2l1.7 1.7M17.1 17.1l1.7 1.7M18.8 5.2l-1.7 1.7M6.9 17.1l-1.7 1.7'/>"),
  paperclip:S("<path d='M8.5 8.5 16 16a3 3 0 0 1-4.3 4.2L4.8 13.2A5 5 0 0 1 11.8 6.2l7.7 7.6'/>"),
  tag:S("<path d='M3.5 12 11 4.5h7v7L12 20.5a1.6 1.6 0 0 1-2.3 0z'/><circle cx='14.5' cy='8' r='1.2'/>"),
  clock:S("<circle cx='12' cy='12' r='8.3'/><path d='M12 7.5V12l3 2'/>"),
  pin:S("<path d='M12 21s6.5-5.8 6.5-11A6.5 6.5 0 0 0 5.5 10c0 5.2 6.5 11 6.5 11z'/><circle cx='12' cy='10' r='2.3'/>"),
  chat:S("<path d='M4 5.5h16a1.5 1.5 0 0 1 1.5 1.5v8a1.5 1.5 0 0 1-1.5 1.5H9l-4 3.5V5.5z'/>"),
  image:S("<rect x='3.5' y='5' width='17' height='14' rx='2'/><circle cx='8.5' cy='10' r='1.6'/><path d='M4 17l4.5-4.5 3.5 3.5 3-3L20 16'/>"),
  monitor:S("<rect x='3.5' y='4.5' width='17' height='12' rx='2'/><path d='M9 20.5h6M12 16.5v4'/>"),
  dot:S("<circle cx='12' cy='12' r='5' fill='currentColor' stroke='none'/>"),
  arrowRight:S("<path d='M5 12h13M13 6l6 6-6 6'/>"),
  arrowUp:S("<path d='M12 19V6M6 12l6-6 6 6'/>"),
  arrowDown:S("<path d='M12 5v13M6 12l6 6 6-6'/>"),
  building:S("<rect x='5' y='3.5' width='14' height='17.5' rx='1.5'/><path d='M9 7h2M13 7h2M9 11h2M13 11h2M9 15h2M13 15h2'/><path d='M10.5 21v-2.5h3V21'/>")
};
var EMOJI={"\ud83d\udcca": "chart", "\u2630": "menu", "\ud83d\udccb": "clipboard", "\u2705": "check", "\ud83d\udcda": "books", "\ud83d\udcb0": "money", "\u26a0\ufe0f": "warning", "\ud83c\udf93": "grad", "\ud83d\udda8\ufe0f": "print", "\ud83d\udcdd": "note", "\ud83d\udd14": "bell", "\ud83c\udfc6": "trophy", "\ud83c\udfe0": "home", "\ud83d\udc65": "users", "\ud83d\udcc8": "trendUp", "\u274c": "close", "\ud83d\udce6": "box", "\u2699\ufe0f": "settings", "\ud83c\udf1f": "star", "\u2713": "check", "\ud83d\udcb5": "cash", "\ud83d\udcde": "phone", "\ud83c\udfdb\ufe0f": "building", "\ud83d\udce5": "download", "\ud83d\udc51": "crown", "\ud83d\udd04": "refresh", "\ud83d\udee1\ufe0f": "shield", "\ud83d\udcc4": "doc", "\ud83d\udc68\u200d\ud83c\udfeb": "person", "\ud83d\udc9a": "heart", "\u26a1": "bolt", "\ud83d\udc68\u200d\ud83d\udc69\u200d\ud83d\udc67": "users", "\ud83d\udcc9": "trendDown", "\ud83d\udc41\ufe0f": "eye", "\ud83c\udf89": "star", "\ud83d\ude8c": "bus", "\ud83d\uddd3\ufe0f": "calendar", "\ud83e\udde0": "target", "\ud83d\udd12": "lock", "\u2795": "plus", "\ud83d\udd11": "key", "\ud83d\udcd6": "book", "\ud83d\udd17": "link", "\ud83c\udf19": "moon", "\u2600\ufe0f": "sun", "\ud83d\udcce": "paperclip", "\ud83e\udde9": "target", "\ud83c\udfeb": "building", "\ud83d\udcc1": "folder", "\ud83c\udfaf": "target", "\ud83d\udc64": "person", "\ud83d\udd27": "wrench", "\ud83d\udcb3": "card", "\ud83d\uddc2\ufe0f": "folder", "\u270f\ufe0f": "note", "\ud83e\uddea": "box", "\ud83e\uddfe": "doc", "\ud83e\udded": "target", "\ud83c\udf92": "box", "\ud83d\uddbc\ufe0f": "image", "\ud83d\udcd5": "book", "\u270d\ufe0f": "note", "\ud83d\udce3": "bell", "\ud83d\udea8": "warning", "\ud83d\udce2": "bell", "\ud83d\udda5\ufe0f": "monitor", "\ud83d\udc4b": "star", "\u2717": "close", "\ud83d\udc8e": "star", "\ud83c\udff7\ufe0f": "tag", "\ud83d\udcbe": "download", "\ud83d\udcac": "chat", "\ud83d\udd10": "lock", "\ud83d\udcf1": "phone", "\ud83d\udcbb": "monitor", "\ud83c\udfe2": "building", "\ud83d\udd2c": "box", "\ud83d\ude80": "star", "\ud83d\udcf7": "image", "\ud83c\udfc5": "trophy", "\ud83d\udd34": "dot", "\ud83d\udfe1": "dot", "\ud83d\udd35": "dot", "\ud83d\ude0a": "star", "\u2796": "minus", "\ud83d\udcbc": "box", "\ud83c\udf9a\ufe0f": "settings", "\ud83d\uddfa\ufe0f": "target", "\ud83d\udd50": "clock", "\ud83d\uddc4\ufe0f": "box", "\ud83d\uded2": "box", "\ud83d\udccc": "pin", "\ud83d\udc41": "eye", "\u2709\ufe0f": "mail", "\ud83d\udce4": "upload", "\ud83d\udc69\u200d\ud83c\udfeb": "person", "\ud83c\udfe6": "building", "\u2757": "warning", "\ud83d\udc4d": "star", "\ud83d\udc54": "star", "\ud83e\udd47": "trophy", "\ud83e\udd48": "trophy", "\ud83e\udd49": "trophy", "\ud83d\udeaa": "close", "\u2753": "close", "\u2728": "star", "\ud83c\udf10": "link", "\ud83d\udcd8": "book", "\u2605": "star", "\u2715": "close", "\ud83d\udcf2": "phone", "\u2714": "check"};
var keys=Object.keys(EMOJI).sort(function(a,b){return b.length-a.length;});
var EMOJI_RE=new RegExp(keys.map(function(k){return k.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');}).join('|'),'g');
var FB_RE=/[\u{1F000}-\u{1FAFF}\u2600-\u27BF\u2B00-\u{2BFF}]/gu;
function wrap(n){return ICONS[n]||STAR;}
function iconize(t){EMOJI_RE.lastIndex=0;t=t.replace(EMOJI_RE,function(m){return wrap(EMOJI[m]);});t=t.replace(FB_RE,STAR);return t;}
function isSkip(el){return el.nodeType===1&&(el.nodeName==='SCRIPT'||el.nodeName==='STYLE'||el.nodeName==='TEXTAREA');}
function walk(node){if(node.nodeType===3){replaceText(node);}else if(node.nodeType===1&&!isSkip(node)){var c=node.childNodes;for(var i=0;i<c.length;i++){walk(c[i]);}}}
function replaceText(node){var t=node.nodeValue;if(!t)return;var html=iconize(t);if(html===t)return;var span=document.createElement('span');span.innerHTML=html;var frag=document.createDocumentFragment();while(span.firstChild){frag.appendChild(span.firstChild);}if(node.parentNode){node.parentNode.replaceChild(frag,node);}}
var css='.amin-ico{width:1.18em;height:1.18em;vertical-align:-0.22em;flex:0 0 auto;display:inline-block;overflow:visible}';try{var st=document.createElement('style');st.textContent=css;if(document.head)document.head.appendChild(st);}catch(e){}
function run(){if(document.body){walk(document.body);}}
var obs;function start(){run();if('MutationObserver' in window){obs=new MutationObserver(function(muts){obs.disconnect();for(var i=0;i<muts.length;i++){var m=muts[i];if(m.type==='childList'){var an=m.addedNodes;for(var j=0;j<an.length;j++){walk(an[j]);}}else if(m.type==='characterData'){replaceText(m.target);}}obs.observe(document.documentElement,{subtree:true,childList:true,characterData:true});});obs.observe(document.documentElement,{subtree:true,childList:true,characterData:true});}}
if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',start);}else{start();}
window.AminIcons={replace:run};
})();

/*
  Amin Al-Ridha School — 3D Claymorphism Icon & Navigation Engine (v6.0)
  Strictly implements Master Prompt Claymorphism specifications:
  - 3D soft plastic/clay finish with specular highlights & gradient fills
  - Cobalt Blue #5B8CFF, Electric Violet #7C5CFF, Cyan Glow #45D8FF, Mint #00C896, Amber #F6B93B, Coral #FF5D73
  - Responsive scaling (Sidebar 24-28px, Bottom Nav 22-24px, Topbar 20-22px)
  - Interactive micro-animations (Hover scale 1.08 + rotate, Active translateY(-2px) + glow, Tap scale 0.94, AI pulse loop)
*/
(function(){
'use strict';

// 1. Inject 3D Claymorphism & Animation Specs CSS
function inject3DStyles() {
  if (document.getElementById('amin-3d-clay-style')) return;
  const css = `
    .amin-3d-ico {
      display: inline-block;
      vertical-align: middle;
      transition: transform 220ms ease-out, filter 220ms ease-out;
      filter: drop-shadow(0 2px 5px rgba(27, 35, 53, 0.18));
      flex-shrink: 0;
    }
    .sidebar-nav-item:hover .amin-3d-ico,
    .bottom-nav-item:hover .amin-3d-ico,
    button:hover > .amin-3d-ico,
    a:hover > .amin-3d-ico {
      transform: scale(1.08) rotate(3deg);
      filter: drop-shadow(0 4px 10px rgba(91, 140, 255, 0.45));
    }
    .sidebar-nav-item.active .amin-3d-ico,
    .bottom-nav-item.active .amin-3d-ico {
      transform: translateY(-2px) scale(1.06);
      filter: drop-shadow(0 4px 14px rgba(69, 216, 255, 0.65));
    }
    .sidebar-nav-item:active .amin-3d-ico,
    .bottom-nav-item:active .amin-3d-ico,
    button:active > .amin-3d-ico {
      transform: scale(0.94);
      transition: transform 150ms ease-in-out;
    }
    @keyframes amin-ai-pulse-3d {
      0%, 100% { filter: drop-shadow(0 0 6px rgba(124, 92, 255, 0.55)) scale(1); }
      50% { filter: drop-shadow(0 0 16px rgba(69, 216, 255, 0.9)) scale(1.06); }
    }
    .amin-3d-ico.ico-ai, .amin-3d-ico.ico-sparkle, .amin-3d-ico.ico-analytics_ai {
      animation: amin-ai-pulse-3d 1800ms ease-in-out infinite;
    }
    @media (prefers-reduced-motion: reduce) {
      .amin-3d-ico, .amin-3d-ico * {
        animation: none !important;
        transition: none !important;
        transform: none !important;
      }
    }
    /* Mobile Navigation & Responsive Scaling */
    @media (max-width: 639px) {
      .sidebar-nav-item .amin-3d-ico { width: 24px !important; height: 24px !important; }
      .bottom-nav-item .amin-3d-ico { width: 24px !important; height: 24px !important; }
      .app-topbar .amin-3d-ico { width: 22px !important; height: 22px !important; }
    }
  `;
  const s = document.createElement('style');
  s.id = 'amin-3d-clay-style';
  s.textContent = css;
  document.head.appendChild(s);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', inject3DStyles);
} else {
  inject3DStyles();
}

// 2. 3D SVG Builder Helper
function make3D(name, innerSvg, pHex, sHex) {
  const primary = pHex || '#5B8CFF';
  const secondary = sHex || '#7C5CFF';
  return `<svg class="amin-3d-ico ico-${name}" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">` +
    `<defs>` +
    `<linearGradient id="c-g-${name}" x1="0%" y1="0%" x2="100%" y2="100%">` +
    `<stop offset="0%" stop-color="${primary}"/>` +
    `<stop offset="100%" stop-color="${secondary}"/>` +
    `</linearGradient>` +
    `<radialGradient id="c-h-${name}" cx="30%" cy="25%" r="65%">` +
    `<stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.65"/>` +
    `<stop offset="100%" stop-color="#FFFFFF" stop-opacity="0"/>` +
    `</radialGradient>` +
    `</defs>` +
    innerSvg.replace(/fill="url\(#grad\)"/g, `fill="url(#c-g-${name})"`)
            .replace(/fill="url\(#hi\)"/g, `fill="url(#c-h-${name})"`) +
    `</svg>`;
}

// 3. Complete 3D Claymorphism Icon Definitions
const CLAY_ICONS = {
  overview: make3D('overview', `<rect x="4" y="11" width="24" height="17" rx="5" fill="url(#grad)"/><path d="M3 13 L16 3 L29 13 Z" fill="url(#grad)"/><path d="M4 12 L16 4 L28 12 Z" fill="url(#hi)"/><rect x="13" y="18" width="6" height="10" rx="2" fill="#00C896"/>`),
  home: make3D('home', `<rect x="4" y="11" width="24" height="17" rx="5" fill="url(#grad)"/><path d="M3 13 L16 3 L29 13 Z" fill="url(#grad)"/><path d="M4 12 L16 4 L28 12 Z" fill="url(#hi)"/><rect x="13" y="18" width="6" height="10" rx="2" fill="#00C896"/>`),
  students: make3D('students', `<circle cx="16" cy="11" r="6" fill="url(#grad)"/><circle cx="16" cy="10" r="5" fill="url(#hi)"/><path d="M5 28 C5 21 10 18 16 18 C22 18 27 21 27 28 Z" fill="url(#grad)"/><path d="M16 3 L26 7 L16 11 L6 7 Z" fill="#45D8FF"/><path d="M23 7 V13" stroke="#FF5D73" stroke-width="2.5" stroke-linecap="round"/>`),
  users: make3D('users', `<circle cx="11" cy="11" r="5" fill="url(#grad)"/><circle cx="11" cy="10" r="4" fill="url(#hi)"/><path d="M3 27 C3 21 7 18 11 18 C15 18 19 21 19 27 Z" fill="url(#grad)"/><circle cx="21" cy="13" r="4" fill="#45D8FF"/><path d="M18 27 C18 23 21 21 24 21 C27 21 29 23 29 27 Z" fill="#45D8FF"/>`),
  person: make3D('person', `<circle cx="16" cy="11" r="6" fill="url(#grad)"/><circle cx="16" cy="10" r="5" fill="url(#hi)"/><path d="M6 27 C6 21 10 18 16 18 C22 18 26 21 26 27 Z" fill="url(#grad)"/>`),
  academic: make3D('academic', `<rect x="4" y="17" width="24" height="7" rx="3" fill="url(#grad)"/><rect x="4" y="17" width="24" height="4" rx="2" fill="url(#hi)"/><rect x="6" y="10" width="20" height="7" rx="3" fill="#00C896"/><rect x="6" y="10" width="20" height="4" rx="2" fill="rgba(255,255,255,0.4)"/><path d="M12 10 V24" stroke="#FF5D73" stroke-width="2.5"/>`),
  books: make3D('books', `<rect x="4" y="17" width="24" height="7" rx="3" fill="url(#grad)"/><rect x="4" y="17" width="24" height="4" rx="2" fill="url(#hi)"/><rect x="6" y="10" width="20" height="7" rx="3" fill="#00C896"/><rect x="6" y="10" width="20" height="4" rx="2" fill="rgba(255,255,255,0.4)"/><path d="M12 10 V24" stroke="#FF5D73" stroke-width="2.5"/>`),
  book: make3D('book', `<path d="M4 8 C7 6 10 6 16 8 C22 6 25 6 28 8 V24 C25 22 22 22 16 24 C10 22 7 22 4 24 Z" fill="url(#grad)"/><path d="M5 8 C8 6.5 11 6.5 16 8 V16 C11 14.5 8 14.5 5 16 Z" fill="url(#hi)"/><path d="M16 8 V24" stroke="#45D8FF" stroke-width="2.5"/>`),
  finance: make3D('finance', `<rect x="3" y="8" width="26" height="18" rx="5" fill="url(#grad)"/><rect x="3" y="8" width="26" height="9" rx="4" fill="url(#hi)"/><circle cx="22" cy="17" r="5" fill="#F6B93B"/><circle cx="22" cy="16.5" r="3.5" fill="rgba(255,255,255,0.6)"/><rect x="17" y="14" width="12" height="6" rx="3" fill="#1B2335"/>`),
  money: make3D('money', `<rect x="3" y="8" width="26" height="18" rx="5" fill="url(#grad)"/><rect x="3" y="8" width="26" height="9" rx="4" fill="url(#hi)"/><circle cx="22" cy="17" r="5" fill="#F6B93B"/><circle cx="22" cy="16.5" r="3.5" fill="rgba(255,255,255,0.6)"/><rect x="17" y="14" width="12" height="6" rx="3" fill="#1B2335"/>`),
  attendance: make3D('attendance', `<rect x="4" y="6" width="24" height="22" rx="5" fill="#F7FAFF"/><path d="M4 12 C4 9 6 7 9 7 H23 C26 7 28 9 28 12 V15 H4 V12 Z" fill="url(#grad)"/><rect x="9" y="3" width="3" height="6" rx="1.5" fill="#FF5D73"/><rect x="20" y="3" width="3" height="6" rx="1.5" fill="#FF5D73"/><path d="M11 20 L15 24 L23 16" stroke="#00C896" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>`),
  calendar: make3D('calendar', `<rect x="4" y="6" width="24" height="22" rx="5" fill="#F7FAFF"/><path d="M4 12 C4 9 6 7 9 7 H23 C26 7 28 9 28 12 V15 H4 V12 Z" fill="url(#grad)"/><rect x="9" y="3" width="3" height="6" rx="1.5" fill="#FF5D73"/><rect x="20" y="3" width="3" height="6" rx="1.5" fill="#FF5D73"/><circle cx="11" cy="20" r="2" fill="#5B8CFF"/><circle cx="16" cy="20" r="2" fill="#5B8CFF"/><circle cx="21" cy="20" r="2" fill="#5B8CFF"/>`),
  counseling: make3D('counseling', `<path d="M16 3 L28 7 V16 C28 23 23 27 16 29 C9 27 4 23 4 16 V7 L16 3 Z" fill="url(#grad)"/><path d="M16 4 L26 7.5 V15 C26 20 22 24 16 26 Z" fill="url(#hi)"/><circle cx="16" cy="15" r="5" fill="#00C896"/><path d="M14 15 L15.5 16.5 L19 13" stroke="#FFF" stroke-width="2.5" stroke-linecap="round"/>`),
  discipline: make3D('discipline', `<path d="M16 3 L28 7 V16 C28 23 23 27 16 29 C9 27 4 23 4 16 V7 L16 3 Z" fill="url(#grad)"/><path d="M16 4 L26 7.5 V15 C26 20 22 24 16 26 Z" fill="url(#hi)"/><rect x="14.5" y="10" width="3" height="7" rx="1.5" fill="#F6B93B"/><circle cx="16" cy="20" r="1.8" fill="#F6B93B"/>`),
  shield: make3D('shield', `<path d="M16 3 L28 7 V16 C28 23 23 27 16 29 C9 27 4 23 4 16 V7 L16 3 Z" fill="url(#grad)"/><path d="M16 4 L26 7.5 V15 C26 20 22 24 16 26 Z" fill="url(#hi)"/>`),
  tasks: make3D('tasks', `<rect x="5" y="6" width="22" height="24" rx="5" fill="url(#grad)"/><rect x="5" y="6" width="22" height="13" rx="4" fill="url(#hi)"/><rect x="10" y="3" width="12" height="6" rx="2.5" fill="#45D8FF"/><path d="M11 16 H21 M11 22 H17" stroke="#FFF" stroke-width="3" stroke-linecap="round"/><circle cx="21" cy="22" r="3" fill="#00C896"/><path d="M20 22 L21 23 L23 21" stroke="#FFF" stroke-width="1.5" stroke-linecap="round"/>`),
  clipboard: make3D('clipboard', `<rect x="5" y="6" width="22" height="24" rx="5" fill="url(#grad)"/><rect x="5" y="6" width="22" height="13" rx="4" fill="url(#hi)"/><rect x="10" y="3" width="12" height="6" rx="2.5" fill="#45D8FF"/><path d="M11 16 H21 M11 22 H17" stroke="#FFF" stroke-width="3" stroke-linecap="round"/>`),
  certificates: make3D('certificates', `<circle cx="16" cy="13" r="10" fill="#F6B93B"/><circle cx="16" cy="12" r="8" fill="url(#hi)"/><circle cx="16" cy="13" r="5.5" fill="#FF5D73"/><path d="M11 21 L7 30 L14 26 L16 29 L18 26 L25 30 L21 21 Z" fill="url(#grad)"/>`),
  award: make3D('award', `<circle cx="16" cy="13" r="10" fill="#F6B93B"/><circle cx="16" cy="12" r="8" fill="url(#hi)"/><circle cx="16" cy="13" r="5.5" fill="#FF5D73"/><path d="M11 21 L7 30 L14 26 L16 29 L18 26 L25 30 L21 21 Z" fill="url(#grad)"/>`),
  trophy: make3D('trophy', `<path d="M8 5 H24 V10 C24 15 20 18 16 18 C12 18 8 15 8 10 Z" fill="url(#grad)"/><path d="M9 5 H23 V9 C23 13 19 15 16 15 C13 15 9 13 9 9 Z" fill="url(#hi)"/><rect x="13" y="18" width="6" height="6" fill="#45D8FF"/><rect x="8" y="24" width="16" height="5" rx="2" fill="#1B2335"/><path d="M8 7 H5 C3.5 7 3.5 12 5 12 H8 M24 7 H27 C28.5 7 28.5 12 27 12 H24" stroke="url(#grad)" stroke-width="3"/>`),
  messages: make3D('messages', `<path d="M5 8 C5 5 7 3 11 3 H21 C25 3 27 5 27 8 V18 C27 21 25 23 21 23 H14 L7 28 V23 C5 23 5 21 5 18 Z" fill="url(#grad)"/><path d="M6 8 C6 6 8 4 11 4 H21 C24 4 26 6 26 8 V14 C26 17 24 18 21 18 H12 C9 18 7 17 7 14 Z" fill="url(#hi)"/><circle cx="11" cy="13" r="2" fill="#45D8FF"/><circle cx="16" cy="13" r="2" fill="#45D8FF"/><circle cx="21" cy="13" r="2" fill="#45D8FF"/>`),
  chat: make3D('chat', `<path d="M5 8 C5 5 7 3 11 3 H21 C25 3 27 5 27 8 V18 C27 21 25 23 21 23 H14 L7 28 V23 C5 23 5 21 5 18 Z" fill="url(#grad)"/><path d="M6 8 C6 6 8 4 11 4 H21 C24 4 26 6 26 8 V14 C26 17 24 18 21 18 H12 C9 18 7 17 7 14 Z" fill="url(#hi)"/><circle cx="11" cy="13" r="2" fill="#45D8FF"/><circle cx="16" cy="13" r="2" fill="#45D8FF"/><circle cx="21" cy="13" r="2" fill="#45D8FF"/>`),
  analytics_ai: make3D('analytics_ai', `<path d="M16 2 C16 11 19 14 28 14 C19 14 16 17 16 26 C16 17 13 14 4 14 C13 14 16 11 16 2 Z" fill="url(#grad)"/><path d="M16 4 C16 11 18 13 25 14 C18 15 16 17 16 24 C16 17 14 15 7 14 C14 13 16 11 16 4 Z" fill="url(#hi)"/><circle cx="25" cy="7" r="3" fill="#00C896"/><circle cx="7" cy="23" r="2.5" fill="#FF5D73"/>`),
  ai: make3D('ai', `<path d="M16 2 C16 11 19 14 28 14 C19 14 16 17 16 26 C16 17 13 14 4 14 C13 14 16 11 16 2 Z" fill="url(#grad)"/><path d="M16 4 C16 11 18 13 25 14 C18 15 16 17 16 24 C16 17 14 15 7 14 C14 13 16 11 16 4 Z" fill="url(#hi)"/><circle cx="25" cy="7" r="3" fill="#00C896"/><circle cx="7" cy="23" r="2.5" fill="#FF5D73"/>`),
  sparkle: make3D('sparkle', `<path d="M16 2 C16 11 19 14 28 14 C19 14 16 17 16 26 C16 17 13 14 4 14 C13 14 16 11 16 2 Z" fill="url(#grad)"/><path d="M16 4 C16 11 18 13 25 14 C18 15 16 17 16 24 C16 17 14 15 7 14 C14 13 16 11 16 4 Z" fill="url(#hi)"/>`),
  chart: make3D('chart', `<rect x="5" y="16" width="5" height="12" rx="2" fill="url(#grad)"/><rect x="13" y="10" width="6" height="18" rx="2" fill="url(#grad)"/><rect x="22" y="4" width="5" height="24" rx="2" fill="#00C896"/><path d="M3 28 H29" stroke="#45D8FF" stroke-width="3" stroke-linecap="round"/>`),
  chartPie: make3D('chartPie', `<circle cx="16" cy="16" r="12" fill="url(#grad)"/><circle cx="16" cy="15" r="10" fill="url(#hi)"/><path d="M16 16 L16 4 A12 12 0 0 1 28 16 Z" fill="#00C896"/>`),
  registrations: make3D('registrations', `<path d="M3 8 C3 6 5 5 7 5 H12 L15 8 H25 C27 8 29 10 29 12 V24 C29 26 27 28 25 28 H7 C5 28 3 26 3 24 Z" fill="url(#grad)"/><path d="M4 12 C4 10 6 9 8 9 H24 C26 9 28 10 28 12 V18 C28 21 26 22 24 22 H8 C6 22 4 21 4 18 Z" fill="url(#hi)"/><circle cx="21" cy="19" r="4" fill="#00C896"/><path d="M19 19 H23 M21 17 V21" stroke="#FFF" stroke-width="2" stroke-linecap="round"/>`),
  folder: make3D('folder', `<path d="M3 8 C3 6 5 5 7 5 H12 L15 8 H25 C27 8 29 10 29 12 V24 C29 26 27 28 25 28 H7 C5 28 3 26 3 24 Z" fill="url(#grad)"/><path d="M4 12 C4 10 6 9 8 9 H24 C26 9 28 10 28 12 V18 C28 21 26 22 24 22 H8 C6 22 4 21 4 18 Z" fill="url(#hi)"/>`),
  schedule: make3D('schedule', `<rect x="4" y="6" width="24" height="22" rx="5" fill="#F7FAFF"/><path d="M4 12 C4 9 6 7 9 7 H23 C26 7 28 9 28 12 V15 H4 V12 Z" fill="url(#grad)"/><rect x="9" y="3" width="3" height="6" rx="1.5" fill="#FF5D73"/><rect x="20" y="3" width="3" height="6" rx="1.5" fill="#FF5D73"/><circle cx="11" cy="20" r="2" fill="#5B8CFF"/><circle cx="16" cy="20" r="2" fill="#5B8CFF"/><circle cx="21" cy="20" r="2" fill="#5B8CFF"/>`),
  payroll: make3D('payroll', `<rect x="3" y="8" width="26" height="18" rx="5" fill="url(#grad)"/><rect x="3" y="8" width="26" height="9" rx="4" fill="url(#hi)"/><circle cx="22" cy="17" r="5" fill="#00C896"/><path d="M20 17 L21.5 18.5 L24 15" stroke="#FFF" stroke-width="2" stroke-linecap="round"/>`),
  settings: make3D('settings', `<circle cx="16" cy="16" r="10" fill="url(#grad)"/><circle cx="16" cy="15" r="8" fill="url(#hi)"/><circle cx="16" cy="16" r="4" fill="#1B2335"/><path d="M16 2 V6 M16 26 V30 M2 16 H6 M26 16 H30 M6 6 L9 9 M23 23 L26 26 M6 26 L9 23 M23 9 L26 6" stroke="url(#grad)" stroke-width="4" stroke-linecap="round"/>`),
  system: make3D('system', `<path d="M16 3 L28 7 V16 C28 23 23 27 16 29 C9 27 4 23 4 16 V7 L16 3 Z" fill="url(#grad)"/><path d="M16 4 L26 7.5 V15 C26 20 22 24 16 26 Z" fill="url(#hi)"/><path d="M17 9 L11 17 H16 L15 23 L21 15 H16 Z" fill="#F6B93B"/>`),
  bus: make3D('bus', `<rect x="4" y="8" width="24" height="15" rx="5" fill="url(#grad)"/><rect x="4" y="8" width="24" height="8" rx="4" fill="url(#hi)"/><rect x="7" y="11" width="6" height="5" rx="1.5" fill="#45D8FF"/><rect x="15" y="11" width="6" height="5" rx="1.5" fill="#45D8FF"/><circle cx="9" cy="23" r="3" fill="#1B2335"/><circle cx="23" cy="23" r="3" fill="#1B2335"/><circle cx="9" cy="23" r="1.5" fill="#45D8FF"/><circle cx="23" cy="23" r="1.5" fill="#45D8FF"/>`),
  menu: make3D('menu', `<rect x="5" y="7" width="22" height="4" rx="2" fill="url(#grad)"/><rect x="5" y="7" width="22" height="2" rx="1" fill="url(#hi)"/><rect x="5" y="14" width="22" height="4" rx="2" fill="url(#grad)"/><rect x="5" y="14" width="22" height="2" rx="1" fill="url(#hi)"/><rect x="5" y="21" width="22" height="4" rx="2" fill="url(#grad)"/><rect x="5" y="21" width="22" height="2" rx="1" fill="url(#hi)"/>`),
  bell: make3D('bell', `<path d="M8 18 V11 C8 7 11 4 16 4 C21 4 24 7 24 11 V18 L26 21 H6 L8 18 Z" fill="url(#grad)"/><path d="M9 18 V12 C9 8.5 11.5 6 16 6 C20.5 6 23 8.5 23 12 V18 Z" fill="url(#hi)"/><circle cx="16" cy="24" r="3" fill="#FF5D73"/><circle cx="22" cy="7" r="3.5" fill="#FF5D73"/>`),
  logout: make3D('logout', `<rect x="6" y="5" width="12" height="22" rx="3" fill="#FF5D73"/><rect x="6" y="5" width="12" height="11" rx="2" fill="rgba(255,255,255,0.4)"/><path d="M16 16 L25 16 M22 13 L25 16 L22 19" stroke="#5B8CFF" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>`),
  sun: make3D('sun', `<circle cx="16" cy="16" r="7" fill="#F6B93B"/><circle cx="16" cy="15" r="5" fill="url(#hi)"/><path d="M16 3 V6 M16 26 V29 M3 16 H6 M26 16 H29 M7 7 L9 9 M23 23 L25 25 M7 25 L9 23 M23 9 L25 7" stroke="#F6B93B" stroke-width="3" stroke-linecap="round"/>`),
  moon: make3D('moon', `<path d="M24 19 A10 10 0 1 1 13 6 A7 7 0 0 0 24 19 Z" fill="url(#grad)"/><path d="M23 18 A8 8 0 0 1 14 8 A6 6 0 0 0 23 18 Z" fill="url(#hi)"/>`),
  refresh: make3D('refresh', `<path d="M26 14 A10 10 0 0 0 10 8 M6 6 V12 H12 M6 18 A10 10 0 0 0 22 24 M26 26 V20 H20" stroke="url(#grad)" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>`),
  print: make3D('print', `<rect x="8" y="4" width="16" height="7" rx="2" fill="url(#grad)"/><rect x="5" y="11" width="22" height="12" rx="4" fill="url(#grad)"/><rect x="5" y="11" width="22" height="6" rx="3" fill="url(#hi)"/><rect x="8" y="18" width="16" height="10" rx="2" fill="#FFF"/><path d="M11 22 H21 M11 25 H18" stroke="#5B8CFF" stroke-width="2" stroke-linecap="round"/>`),
  check: make3D('check', `<circle cx="16" cy="16" r="12" fill="#00C896"/><circle cx="16" cy="15" r="10" fill="url(#hi)"/><path d="M10 16 L14 20 L22 12" stroke="#FFF" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>`),
  close: make3D('close', `<circle cx="16" cy="16" r="12" fill="#FF5D73"/><circle cx="16" cy="15" r="10" fill="url(#hi)"/><path d="M11 11 L21 21 M21 11 L11 21" stroke="#FFF" stroke-width="3.5" stroke-linecap="round"/>`),
  eye: make3D('eye', `<path d="M3 16 C7 8 16 8 29 16 C25 24 16 24 3 16 Z" fill="url(#grad)"/><path d="M4 16 C8 10 16 10 28 16 C24 20 16 20 4 16 Z" fill="url(#hi)"/><circle cx="16" cy="16" r="5" fill="#1B2335"/><circle cx="17" cy="15" r="2" fill="#45D8FF"/>`)
};

function create(name, size, state) {
  size = size || 24;
  const ico = CLAY_ICONS[name] || CLAY_ICONS.star || make3D('default', `<circle cx="16" cy="16" r="10" fill="url(#grad)"/>`);
  return `<span class="amin-3d-ico-wrap" style="display:inline-flex;align-items:center;justify-content:center;width:${size}px;height:${size}px;">${ico}</span>`;
}

window.AminIcons = { create, CLAY_ICONS, inject3DStyles };
window.Icon3D = { create };
})();
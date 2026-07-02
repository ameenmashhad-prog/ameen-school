/* Amin Al-Ridha PWA Service Worker — local/offline shell, no external APIs */
// Bump cache name on V3 redesign to force clients to fetch new design assets
const CACHE_NAME = 'amin-pwa-v2026-07-01-v2';
const CORE_ASSETS = [
  '/',
  '/index.html',
  '/portal.html',
  '/deployment-check.html',
  '/achievements.html',
  '/counselor.html',
  '/counseling-report.html',
  '/security-governance.html',
  '/curriculum-planner.html',
  '/offline.html',
  '/assets/design-tokens.css',
  '/assets/components.css',
  '/assets/amin-v3.css',
  '/assets/i18n.css',
  '/assets/i18n.js',
  '/assets/platform-modules.js',
  '/assets/ux-enhancements.js',
  '/assets/config.js',
  '/assets/core.js',
  '/assets/unified-portal.js',
  '/assets/unified-portal.css',
  '/assets/achievements.css',
  '/assets/achievements.js',
  '/assets/counselor.css',
  '/assets/counselor.js',
  '/assets/counseling-report.css',
  '/assets/counseling-report.js',
  '/assets/security-governance.css',
  '/assets/security-governance.js',
  '/assets/curriculum-planner.css',
  '/assets/curriculum-planner.js',
  '/assets/amin-logo-small.png',
  '/manifest.webmanifest',
  '/libs/supabase.min.js'
];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(CORE_ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

function isApiRequest(url){ return url.pathname.startsWith('/api') || url.pathname.includes('/rest/v1') || url.pathname.includes('/auth/v1') || url.pathname.includes('/storage/v1'); }

self.addEventListener('fetch', event => {
  const req = event.request;
  if(req.method !== 'GET') return;
  const url = new URL(req.url);
  if(url.origin !== self.location.origin) return;
  if(isApiRequest(url)) return; // never cache Supabase/API responses

  if(req.mode === 'navigate'){
    event.respondWith(fetch(req).then(res => {
      const copy = res.clone();
      caches.open(CACHE_NAME).then(cache => cache.put(req, copy));
      return res;
    }).catch(() => caches.match(req).then(r => r || caches.match('/offline.html'))));
    return;
  }

  // JS/CSS must be network-first after deployments to avoid stale runtime errors.
  if(url.pathname.endsWith('.js') || url.pathname.endsWith('.css')){
    event.respondWith(fetch(req).then(res => {
      const copy = res.clone();
      if(res.ok) caches.open(CACHE_NAME).then(cache => cache.put(req, copy));
      return res;
    }).catch(() => caches.match(req)));
    return;
  }

  event.respondWith(caches.match(req).then(cached => cached || fetch(req).then(res => {
    const copy = res.clone();
    if(res.ok) caches.open(CACHE_NAME).then(cache => cache.put(req, copy));
    return res;
  }).catch(() => cached)));
});

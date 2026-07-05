/*
  Amin Al-Ridha School — Student/User photo display (R4)
  - Frontend-only. Reads an avatar URL from the user/profile object.
  - Storage paths are resolved through the /api proxy (no external host).
  - Degrades gracefully: if no photo, keeps the original emoji/initials node.
  - Exposes window.AminAvatar:
      url(raw)            -> absolute URL (resolves storage paths via /api proxy)
      img(photoUrl,name)  -> HTML string <img> with onerror fallback to initials
      mount(scope)        -> replaces .profile-mini .avatar content when ME.avatar_url exists
      rosterImg(student)  -> HTML string for teacher/admin roster photos
  Requires the `avatar_url` column on public.users (see sql/archive/110_student_photo.sql).
*/
(function () {
  'use strict';

  function apiBase() {
    try {
      if (window.AMIN_CONFIG && window.AMIN_CONFIG.supabaseUrl) return window.AMIN_CONFIG.supabaseUrl.replace(/\/$/, '');
      return window.location.origin + '/api';
    } catch (e) { return window.location.origin + '/api'; }
  }

  function isPath(v) {
    return typeof v === 'string' && v.length && !/^(https?:)?\/\//i.test(v) && !v.startsWith('data:');
  }

  function url(raw) {
    if (!raw) return '';
    if (/^data:/i.test(raw)) return raw;
    if (/^https?:\/\//i.test(raw)) return raw;
    // storage object path, e.g. "student-photos/<id>/avatar.jpg"
    return apiBase() + '/storage/v1/object/public/' + raw.replace(/^\/+/, '');
  }

  function initials(name) {
    var n = (name || '').toString().trim();
    if (!n) return '؟';
    var parts = n.split(/\s+/);
    if (parts.length === 1) return parts[0].slice(0, 2);
    return parts[0][0] + parts[parts.length - 1][0];
  }

  function img(photoUrl, name) {
    var u = url(photoUrl);
    if (!u) return '<span class="amin-avatar-fallback">' + esc(initials(name)) + '</span>';
    var alt = (name || '').toString().replace(/"/g, '&quot;');
    return '<img class="amin-avatar-img" src="' + esc(u) + '" alt="' + alt + '" ' +
           'referrerpolicy="no-referrer" ' +
           'onerror="this.classList.add(\'amin-avatar-broken\');this.removeAttribute(\'src\');' +
           'this.outerHTML=\'<span class=\\\"amin-avatar-fallback\\\">' + esc(initials(name)) + '<\\/span>\'">';
  }

  function esc(v) {
    return String(v == null ? '' : v).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function photoOf(obj) {
    if (!obj) return '';
    return obj.avatar_url || obj.photo_url || obj.photo || obj.avatar || obj.profile_image || obj.profile_photo || '';
  }

  function mount(scope) {
    scope = scope || document;
    var me = window.ME || (window.AminAuth && AminAuth.me && AminAuth.me()) || null;
    var photo = photoOf(me);
    if (!photo) return;
    var name = (me && (me.name || me.full_name)) || '';
    var avatars = scope.querySelectorAll('.profile-mini .avatar');
    avatars.forEach(function (el) {
      if (el.querySelector('img.amin-avatar-img')) return; // already done
      el.innerHTML = img(photo, name);
      el.classList.add('has-photo');
    });
  }

  function rosterImg(student) {
    var photo = photoOf(student);
    var name = (student && (student.name || student.full_name)) || (student && (student.first_name || '')) || '';
    return '<span class="amin-roster-avatar">' + img(photo, name) + '</span>';
  }

  function injectStyle() {
    if (document.getElementById('aminAvatarStyle')) return;
    var s = document.createElement('style');
    s.id = 'aminAvatarStyle';
    s.textContent =
      '.amin-avatar-img,.amin-avatar-fallback{width:100%;height:100%;object-fit:cover;display:block;border-radius:50%}' +
      '.amin-avatar-fallback{display:grid;place-items:center;background:var(--primary,#0B6E4F);color:#fff;font-weight:700;font-size:14px}' +
      '.avatar.has-photo{background:none;padding:0;overflow:hidden}' +
      '.amin-roster-avatar{width:34px;height:34px;border-radius:50%;overflow:hidden;display:inline-grid;place-items:center;' +
      'background:var(--surface-2,#eef2f0);border:1px solid var(--border-subtle,#e3e3e3);vertical-align:middle}' +
      '.amin-roster-avatar .amin-avatar-fallback{font-size:12px}';
    document.head.appendChild(s);
  }

  function init() {
    injectStyle();
    mount(document);
    // Profiles load asynchronously; poll briefly until window.ME carries a
    // photo, then stop (no busy loop).
    var tries = 0, maxTries = 16; // ~8s at 500ms
    var knownPhoto = '';
    var iv = setInterval(function () {
      tries++;
      var me = window.ME || (window.AminAuth && window.AminAuth.me && window.AminAuth.me()) || null;
      var photo = photoOf(me);
      mount(document);
      if ((photo && photo !== knownPhoto) || tries >= maxTries) {
        clearInterval(iv);
        knownPhoto = photo;
        return;
      }
      knownPhoto = photo;
    }, 500);
    window.addEventListener('amin:language-change', function () {});
  }

  window.AminAvatar = { url: url, img: img, mount: mount, rosterImg: rosterImg, init: init };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();

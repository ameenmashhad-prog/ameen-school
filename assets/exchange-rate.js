/*
  Amin Al-Ridha School — Manual Exchange Rate widget (R10)
  - Frontend-only, no backend, no external/CDN calls (Capacitor-ready).
  - Persists a manually "fixed" rate in localStorage (survives offline).
  - Auto-mounts a collapsible floating panel; self-contained.
  - Trilingual via window.AminI18n (falls back to Arabic).
  - Exposes window.AminExchangeRate for other modules:
      getRate()            -> { usdToIrr, fixedAt }
      convert(amount,from) -> number   (from: 'usd' | 'irr')
      fix(usdToIrr)        -> saves + re-renders
*/
(function () {
  'use strict';

  var STORE_KEY = 'amin_exchange_rate_v1';
  // Placeholder default — the user MUST "fix" the real rate (auto-fetch from
  // external sites is intentionally forbidden: no CDN / no outbound calls).
  var DEFAULT_USD_IRR = 50000;

  function t(key) {
    try { return (window.AminI18n && window.AminI18n.t) ? window.AminI18n.t(key) : key; }
    catch (e) { return key; }
  }
  function curLang() {
    try { return (window.AminI18n && window.AminI18n.lang) ? window.AminI18n.lang() : (localStorage.getItem('amin_ui_lang') || 'ar'); }
    catch (e) { return 'ar'; }
  }
  function storageBase() {
    try { return window.location.origin + '/api'; } catch (e) { return '/api'; }
  }

  function load() {
    try {
      var raw = localStorage.getItem(STORE_KEY);
      if (raw) {
        var o = JSON.parse(raw);
        if (o && typeof o.usdToIrr === 'number' && o.usdToIrr > 0) return o;
      }
    } catch (e) {}
    return { usdToIrr: DEFAULT_USD_IRR, fixedAt: null, manual: true };
  }
  function save(state) {
    try { localStorage.setItem(STORE_KEY, JSON.stringify(state)); } catch (e) {}
  }

  var state = load();

  function fmtMoney(n) {
    try { return new Intl.NumberFormat(curLang() === 'fa' ? 'fa-IR' : (curLang() === 'en' ? 'en-US' : 'ar'), { maximumFractionDigits: 2 }).format(n); }
    catch (e) { return String(n); }
  }
  function fmtDateTime(iso) {
    if (!iso) return t('لم يُثبّت بعد');
    try { return new Date(iso).toLocaleString(curLang() === 'en' ? 'en-GB' : 'ar'); }
    catch (e) { return iso; }
  }

  function convert(amount, from) {
    var amt = Number(amount) || 0;
    if (from === 'irr') return amt / state.usdToIrr;       // IRR -> USD
    return amt * state.usdToIrr;                            // USD -> IRR
  }

  var root = null, collapsed = false, amountInput = null, resultEl = null, rateInput = null, stampEl = null, titleEl = null;

  function build() {
    if (root) return;
    var style = document.createElement('style');
    style.textContent =
      '.amin-xr{position:fixed;left:14px;bottom:14px;z-index:60;width:268px;max-width:calc(100vw - 28px);' +
      'background:var(--surface-1,#fff);color:var(--text-primary,#1a1a1a);border:1px solid var(--border-subtle,#e3e3e3);' +
      'border-radius:var(--radius-lg,14px);box-shadow:0 10px 30px rgba(11,110,79,.18);font:500 13px/1.5 var(--font-body,system-ui);overflow:hidden}' +
      '.amin-xr__h{display:flex;align-items:center;gap:8px;padding:10px 12px;background:var(--primary,#0B6E4F);color:#fff;cursor:pointer}' +
      '.amin-xr__h b{flex:1;font-size:13px}' +
      '.amin-xr__h .tog{font-size:12px;opacity:.85}' +
      '.amin-xr__b{padding:12px;display:block}' +
      '.amin-xr.min .amin-xr__b{display:none}' +
      '.amin-xr__row{display:flex;align-items:center;gap:8px;margin-bottom:8px}' +
      '.amin-xr__row label{flex:0 0 auto;color:var(--text-secondary,#666);font-size:12px}' +
      '.amin-xr input.amt{flex:1;min-width:0;border:1px solid var(--border-subtle,#ddd);border-radius:8px;padding:6px 8px;font:inherit;background:var(--surface-2,#f6f8f7)}' +
      '.amin-xr__stamp{font-size:11px;color:var(--text-secondary,#777);margin-bottom:8px}' +
      '.amin-xr__cv{display:flex;gap:6px;margin-bottom:8px}' +
      '.amin-xr__cv input{flex:1;min-width:0}' +
      '.amin-xr__btns{display:flex;gap:6px}' +
      '.amin-xr .btn{font:600 12px/1 var(--font-body,system-ui);border:none;border-radius:8px;padding:8px 10px;cursor:pointer}' +
      '.amin-xr .btn.fix{background:var(--primary,#0B6E4F);color:#fff;flex:1}' +
      '.amin-xr .btn.ghost{background:var(--surface-2,#eef2f0);color:var(--text-primary,#222)}' +
      '.amin-xr__hint{font-size:10.5px;color:var(--text-secondary,#888);margin-top:8px;line-height:1.4}' +
      '.amin-xr__res{font-weight:700;color:var(--primary,#0B6E4F)}';
    document.head.appendChild(style);

    root = document.createElement('aside');
    root.className = 'amin-xr';
    root.setAttribute('aria-label', t('سعر الصرف اليدوي'));
    root.innerHTML =
      '<div class="amin-xr__h"><span class="ico">💱</span><b data-k="سعر الصرف اليدوي">سعر الصرف اليدوي</b>' +
      '<span class="tog">▾</span></div>' +
      '<div class="amin-xr__b">' +
        '<div class="amin-xr__row"><label data-k="الدولار">الدولار</label>' +
        '<input class="amt" id="aminXrRate" type="number" min="1" step="any" class="input"></div>' +
        '<div class="amin-xr__stamp"><span data-k="آخر تحديث">آخر تحديث</span>: <span id="aminXrStamp"></span></div>' +
        '<div class="amin-xr__cv">' +
          '<input class="amt" id="aminXrAmount" type="number" min="0" step="any" placeholder="0">' +
          '<select class="amt" id="aminXrFrom"><option value="usd" data-k="الدولار">الدولار</option>' +
          '<option value="irr" data-k="الريال الإيراني">الريال الإيراني</option></select>' +
        '</div>' +
        '<div class="amin-xr__row"><span data-k="النتيجة">النتيجة</span>: <span class="amin-xr__res" id="aminXrResult">—</span></div>' +
        '<div class="amin-xr__btns">' +
          '<button class="btn fix" id="aminXrFix" data-k="تثبيت السعر">تثبيت السعر</button>' +
        '</div>' +
        '<div class="amin-xr__hint" data-k="عند الانقطاع استخدم التثبيت اليدوي">عند الانقطاع استخدم التثبيت اليدوي</div>' +
      '</div>';

    document.body.appendChild(root);
    titleEl = root.querySelector('b[data-k]');
    rateInput = root.querySelector('#aminXrRate');
    stampEl = root.querySelector('#aminXrStamp');
    amountInput = root.querySelector('#aminXrAmount');
    resultEl = root.querySelector('#aminXrResult');
    var fromSel = root.querySelector('#aminXrFrom');
    var fixBtn = root.querySelector('#aminXrFix');

    root.querySelector('.amin-xr__h').addEventListener('click', function () {
      collapsed = !collapsed; root.classList.toggle('min', collapsed);
      root.querySelector('.tog').textContent = collapsed ? '▸' : '▾';
    });
    rateInput.addEventListener('input', reRender);
    amountInput.addEventListener('input', reRender);
    fromSel.addEventListener('change', reRender);
    fixBtn.addEventListener('click', function () {
      var v = Number(rateInput.value);
      if (!v || v <= 0) { if (window.toast) window.toast(t('أدخل قيمة صحيحة'), t('سعر الصرف اليدوي'), 'red'); return; }
      state = { usdToIrr: v, fixedAt: new Date().toISOString(), manual: true };
      save(state); reRender();
      if (window.toast) window.toast(t('تم تثبيت سعر الصرف'), '1 ' + t('الدولار') + ' = ' + fmtMoney(v) + ' ' + t('الريال الإيراني'), 'green');
    });

    translate();
    reRender();
  }

  function reRender() {
    if (!rateInput) return;
    var live = Number(rateInput.value) || state.usdToIrr;
    rateInput.value = live;
    stampEl.textContent = fmtDateTime(state.fixedAt) + (state.fixedAt ? '' : '');
    var amt = Number(amountInput.value) || 0;
    var from = root.querySelector('#aminXrFrom').value;
    var res = convert(amt, from);
    var toLabel = from === 'usd' ? t('الريال الإيراني') : t('الدولار');
    resultEl.textContent = fmtMoney(res) + ' ' + toLabel;
  }

  function translate() {
    if (!root) return;
    root.querySelectorAll('[data-k]').forEach(function (el) {
      var k = el.getAttribute('data-k');
      var v = t(k);
      if (el.tagName === 'OPTION') el.textContent = v; else el.textContent = v;
    });
  }

  function init() {
    if (document.getElementById('aminXrRate')) return; // already mounted
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', build);
    else build();
    window.addEventListener('amin:language-change', function () { translate(); reRender(); });
  }

  window.AminExchangeRate = {
    getRate: function () { return { usdToIrr: state.usdToIrr, fixedAt: state.fixedAt }; },
    convert: convert,
    fix: function (v) { var n = Number(v); if (n > 0) { state = { usdToIrr: n, fixedAt: new Date().toISOString(), manual: true }; save(state); if (root) reRender(); } },
    init: init
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();

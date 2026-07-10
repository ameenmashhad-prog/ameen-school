(function () {
  'use strict';

  function normalizeUrl(url) {
    if (!url) return '';
    return String(url).trim();
  }

  function appendSource(url) {
    try {
      const target = new URL(url, window.location.origin);
      if (!target.searchParams.has('source')) {
        target.searchParams.set('source', 'legacy-family-registration');
      }
      return target.toString();
    } catch (error) {
      return url;
    }
  }

  function shouldAutoRedirect(config, params) {
    if (params.get('familyV3Redirect') === '1') return true;
    return Boolean(config.familyRegistrationV3AutoRedirect);
  }

  function boot() {
    const config = window.AMIN_CONFIG || {};
    const params = new URLSearchParams(window.location.search);
    const configuredUrl = normalizeUrl(params.get('familyV3Url') || config.familyRegistrationV3Url || '');
    const previewMode = params.get('showFamilyV3') === '1';

    const banner = document.getElementById('familyV3SoftLaunch');
    if (!banner) return;

    const launchLink = document.getElementById('familyV3LaunchLink');
    const dismissBtn = document.getElementById('familyV3DismissBtn');
    const status = document.getElementById('familyV3Status');
    const countdown = document.getElementById('familyV3Countdown');

    if (!configuredUrl && !previewMode) {
      return;
    }

    banner.hidden = false;

    if (configuredUrl && launchLink) {
      launchLink.href = appendSource(configuredUrl);
      launchLink.removeAttribute('aria-disabled');
      launchLink.classList.remove('is-disabled');
      launchLink.textContent = 'افتح النسخة الجديدة';
      if (status) status.textContent = 'النسخة الجديدة جاهزة للفتح من هنا مع بقاء النسخة الحالية كخيار احتياطي.';
    } else if (launchLink) {
      launchLink.removeAttribute('href');
      launchLink.setAttribute('aria-disabled', 'true');
      launchLink.classList.add('is-disabled');
      launchLink.textContent = 'النسخة الجديدة جاهزة لكن الرابط لم يُثبت بعد';
      if (status) status.textContent = 'تم تجهيز Soft Launch، وما ينقص فقط تثبيت رابط النشر النهائي داخل الإعدادات.';
    }

    dismissBtn?.addEventListener('click', function () {
      banner.hidden = true;
    });

    if (!configuredUrl || !shouldAutoRedirect(config, params)) {
      return;
    }

    if (!countdown) {
      window.setTimeout(function () {
        window.location.href = appendSource(configuredUrl);
      }, 2500);
      return;
    }

    let remaining = 4;
    countdown.textContent = String(remaining);
    const timer = window.setInterval(function () {
      remaining -= 1;
      countdown.textContent = String(Math.max(remaining, 0));
      if (remaining <= 0) {
        window.clearInterval(timer);
        window.location.href = appendSource(configuredUrl);
      }
    }, 1000);

    dismissBtn?.addEventListener('click', function () {
      window.clearInterval(timer);
    }, { once: true });
  }

  window.addEventListener('load', boot);
}());

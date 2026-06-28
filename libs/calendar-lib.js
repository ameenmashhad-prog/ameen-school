/**
 * مكتبة التقويم الثلاثي — Triple Calendar Library
 * تدعم: الميلادي (Gregorian) + الهجري (Hijri) + الشمسي (Solar/Persian)
 * بدون أي مكتبات خارجية — تعمل offline كاملاً
 * الإصدار: 1.0.0
 */

'use strict';

(function(root) {

  // ======================================================
  // الثوابت والبيانات الأساسية
  // ======================================================

  var GREGORIAN_EPOCH = 1721425.5;
  var HIJRI_EPOCH     = 1948439.5;
  var PERSIAN_EPOCH   = 1948320.5;

  var DAYS_AR  = ['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'];
  var DAYS_AR_SHORT = ['أحد','اثنين','ثلاثاء','أربعاء','خميس','جمعة','سبت'];

  var MONTHS_GR_AR = [
    'يناير','فبراير','مارس','أبريل','مايو','يونيو',
    'يوليو','أغسطس','سبتمبر','أكتوبر','نوفمبر','ديسمبر'
  ];
  var MONTHS_GR_EN = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ];

  var MONTHS_HJ = [
    'محرم','صفر','ربيع الأول','ربيع الثاني',
    'جمادى الأولى','جمادى الآخرة','رجب','شعبان',
    'رمضان','شوال','ذو القعدة','ذو الحجة'
  ];

  var MONTHS_SH = [
    'فروردین','اردیبهشت','خرداد','تیر','مرداد','شهریور',
    'مهر','آبان','آذر','دی','بهمن','اسفند'
  ];
  // أسماء الشهور الشمسية بالعربية
  var MONTHS_SH_AR = [
    'فروردین','أردیبهشت','خرداد','تیر','مرداد','شهریور',
    'مهر','آبان','آذر','دي','بهمن','اسفند'
  ];

  // ======================================================
  // دوال Julian Day Number (JDN)
  // ======================================================

  function mod(a, b) { return a - b * Math.floor(a / b); }

  // ميلادي → JDN
  function gregorianToJD(year, month, day) {
    return (GREGORIAN_EPOCH - 1) +
      (365 * (year - 1)) +
      Math.floor((year - 1) / 4) +
      -Math.floor((year - 1) / 100) +
      Math.floor((year - 1) / 400) +
      Math.floor((((367 * month) - 362) / 12) +
        (month <= 2 ? 0 : (isLeapGregorian(year) ? -1 : -2)) +
        day);
  }

  // JDN → ميلادي
  function jdToGregorian(jd) {
    var wjd = Math.floor(jd - 0.5) + 0.5;
    var depoch = wjd - GREGORIAN_EPOCH;
    var quadricent = Math.floor(depoch / 146097);
    var dqc = mod(depoch, 146097);
    var cent = Math.floor(dqc / 36524);
    var dcent = mod(dqc, 36524);
    var quad = Math.floor(dcent / 1461);
    var dquad = mod(dcent, 1461);
    var yindex = Math.floor(dquad / 365);
    var year = (quadricent * 400) + (cent * 100) + (quad * 4) + yindex;
    if (!(cent === 4 || yindex === 4)) year++;
    var yearday = wjd - gregorianToJD(year, 1, 1);
    var leapadj = (wjd < gregorianToJD(year, 3, 1)) ? 0 : (isLeapGregorian(year) ? 1 : 2);
    var month = Math.floor(((yearday + leapadj) * 12 + 373) / 367);
    var day = (wjd - gregorianToJD(year, month, 1)) + 1;
    return { year: year, month: month, day: day };
  }

  function isLeapGregorian(year) {
    return (year % 4 === 0) && (!(year % 100 === 0) || (year % 400 === 0));
  }

  // هجري → JDN
  function hijriToJD(year, month, day) {
    return (day +
      Math.ceil(29.5 * (month - 1)) +
      (year - 1) * 354 +
      Math.floor((3 + (11 * year)) / 30) +
      HIJRI_EPOCH) - 1;
  }

  // JDN → هجري
  function jdToHijri(jd) {
    jd = Math.floor(jd) + 0.5;
    var year = Math.floor(((30 * (jd - HIJRI_EPOCH)) + 10646) / 10631);
    var month = Math.min(12, Math.ceil((jd - (29 + hijriToJD(year, 1, 1))) / 29.5) + 1);
    var day = (jd - hijriToJD(year, month, 1)) + 1;
    return { year: year, month: month, day: Math.floor(day) };
  }

  // شمسي → JDN
  function persianToJD(year, month, day) {
    var epbase = year - (year >= 0 ? 474 : 473);
    var epyear = 474 + mod(epbase, 2820);
    return day +
      (month <= 7 ? (month - 1) * 31 : (month - 1) * 30 + 6) +
      Math.floor((epyear * 682 - 110) / 2816) +
      (epyear - 1) * 365 +
      Math.floor(epbase / 2820) * 1029983 +
      (PERSIAN_EPOCH - 1);
  }

  // JDN → شمسي
  function jdToPersian(jd) {
    jd = Math.floor(jd) + 0.5;
    var depoch = jd - persianToJD(475, 1, 1);
    var cycle = Math.floor(depoch / 1029983);
    var cyear = mod(depoch, 1029983);
    var ycycle;
    if (cyear === 1029982) {
      ycycle = 2820;
    } else {
      var aux1 = Math.floor(cyear / 366);
      var aux2 = mod(cyear, 366);
      ycycle = Math.floor((2134 * aux1 + 2816 * aux2 + 2815) / 1028522) + aux1 + 1;
    }
    var year = ycycle + 2820 * cycle + 474;
    if (year <= 0) year--;
    var yday = jd - persianToJD(year, 1, 1) + 1;
    var month = yday <= 186 ? Math.ceil(yday / 31) : Math.ceil((yday - 6) / 30);
    var day = jd - persianToJD(year, month, 1) + 1;
    return { year: year, month: month, day: Math.floor(day) };
  }

  // ======================================================
  // الكلاس الرئيسي TripleDate
  // ======================================================

  function TripleDate(dateInput) {
    var gr;
    if (!dateInput) {
      var now = new Date();
      gr = { year: now.getFullYear(), month: now.getMonth() + 1, day: now.getDate() };
    } else if (dateInput instanceof Date) {
      gr = { year: dateInput.getFullYear(), month: dateInput.getMonth() + 1, day: dateInput.getDate() };
    } else if (typeof dateInput === 'string') {
      var parts = dateInput.split('-');
      gr = { year: parseInt(parts[0]), month: parseInt(parts[1]), day: parseInt(parts[2]) };
    } else if (dateInput.year && dateInput.month && dateInput.day) {
      gr = { year: dateInput.year, month: dateInput.month, day: dateInput.day };
    } else {
      var now2 = new Date();
      gr = { year: now2.getFullYear(), month: now2.getMonth() + 1, day: now2.getDate() };
    }

    this.jd = gregorianToJD(gr.year, gr.month, gr.day);
    this._gr = gr;
    this._hj = null;
    this._sh = null;
  }

  // getter الميلادي
  Object.defineProperty(TripleDate.prototype, 'gregorian', {
    get: function() { return this._gr; }
  });

  // getter الهجري
  Object.defineProperty(TripleDate.prototype, 'hijri', {
    get: function() {
      if (!this._hj) this._hj = jdToHijri(this.jd);
      return this._hj;
    }
  });

  // getter الشمسي
  Object.defineProperty(TripleDate.prototype, 'persian', {
    get: function() {
      if (!this._sh) this._sh = jdToPersian(this.jd);
      return this._sh;
    }
  });

  // اسم اليوم
  TripleDate.prototype.dayName = function(lang) {
    var dow = mod(Math.floor(this.jd + 1.5), 7);
    return lang === 'short' ? DAYS_AR_SHORT[dow] : DAYS_AR[dow];
  };

  // تنسيق الميلادي
  TripleDate.prototype.formatGregorian = function(fmt) {
    var g = this._gr;
    fmt = fmt || 'DD/MM/YYYY';
    return fmt
      .replace('YYYY', g.year)
      .replace('MM', pad(g.month))
      .replace('DD', pad(g.day))
      .replace('MMMM', MONTHS_GR_AR[g.month - 1])
      .replace('MMM', MONTHS_GR_EN[g.month - 1].slice(0, 3))
      .replace('D', g.day)
      .replace('M', g.month);
  };

  // تنسيق الهجري
  TripleDate.prototype.formatHijri = function(fmt) {
    var h = this.hijri;
    fmt = fmt || 'DD/MM/YYYY';
    return fmt
      .replace('YYYY', h.year)
      .replace('MM', pad(h.month))
      .replace('DD', pad(h.day))
      .replace('MMMM', MONTHS_HJ[h.month - 1])
      .replace('D', h.day)
      .replace('M', h.month);
  };

  // تنسيق الشمسي
  TripleDate.prototype.formatPersian = function(fmt) {
    var p = this.persian;
    fmt = fmt || 'DD/MM/YYYY';
    return fmt
      .replace('YYYY', p.year)
      .replace('MM', pad(p.month))
      .replace('DD', pad(p.day))
      .replace('MMMM', MONTHS_SH_AR[p.month - 1])
      .replace('D', p.day)
      .replace('M', p.month);
  };

  // عرض كامل الأنظمة الثلاثة
  TripleDate.prototype.formatAll = function() {
    return {
      gregorian: this.formatGregorian('DD MMMM YYYY'),
      hijri:     this.formatHijri('DD MMMM YYYY هـ'),
      persian:   this.formatPersian('DD MMMM YYYY ش'),
      dayName:   this.dayName()
    };
  };

  // إضافة أيام
  TripleDate.prototype.addDays = function(n) {
    return TripleDate.fromJD(this.jd + n);
  };

  // الفرق بالأيام
  TripleDate.prototype.diff = function(other) {
    return Math.floor(this.jd) - Math.floor(other.jd);
  };

  // مقارنة
  TripleDate.prototype.isBefore = function(other) { return this.jd < other.jd; };
  TripleDate.prototype.isAfter  = function(other) { return this.jd > other.jd; };
  TripleDate.prototype.isSame   = function(other) { return Math.floor(this.jd) === Math.floor(other.jd); };

  // تحويل لـ JS Date
  TripleDate.prototype.toDate = function() {
    var g = this._gr;
    return new Date(g.year, g.month - 1, g.day);
  };

  // تحويل لـ ISO string
  TripleDate.prototype.toISO = function() {
    var g = this._gr;
    return g.year + '-' + pad(g.month) + '-' + pad(g.day);
  };

  // ======================================================
  // دوال ستاتيك
  // ======================================================

  TripleDate.fromJD = function(jd) {
    var gr = jdToGregorian(jd);
    return new TripleDate(gr);
  };

  TripleDate.today = function() {
    return new TripleDate();
  };

  // من هجري
  TripleDate.fromHijri = function(year, month, day) {
    var jd = hijriToJD(year, month, day);
    return TripleDate.fromJD(jd);
  };

  // من شمسي
  TripleDate.fromPersian = function(year, month, day) {
    var jd = persianToJD(year, month, day);
    return TripleDate.fromJD(jd);
  };

  // بناء تقويم شهر كامل (ميلادي)
  TripleDate.buildMonth = function(year, month) {
    var daysInMonth = new Date(year, month, 0).getDate();
    var firstDay = new TripleDate({ year: year, month: month, day: 1 });
    var startDow = mod(Math.floor(firstDay.jd + 1.5), 7); // 0=أحد

    var weeks = [];
    var week = new Array(startDow).fill(null);

    for (var d = 1; d <= daysInMonth; d++) {
      var td = new TripleDate({ year: year, month: month, day: d });
      week.push(td);
      if (week.length === 7) {
        weeks.push(week);
        week = [];
      }
    }
    if (week.length > 0) {
      while (week.length < 7) week.push(null);
      weeks.push(week);
    }
    return {
      year: year,
      month: month,
      monthName: MONTHS_GR_AR[month - 1],
      daysInMonth: daysInMonth,
      weeks: weeks
    };
  };

  // أسماء الأشهر
  TripleDate.monthNames = {
    gregorian: MONTHS_GR_AR,
    hijri:     MONTHS_HJ,
    persian:   MONTHS_SH_AR
  };

  TripleDate.dayNames = DAYS_AR;
  TripleDate.dayNamesShort = DAYS_AR_SHORT;

  // ======================================================
  // واجهة عرض التقويم HTML
  // ======================================================

  TripleDate.renderCalendarWidget = function(containerId, options) {
    options = options || {};
    var container = document.getElementById(containerId);
    if (!container) return;

    var today = TripleDate.today();
    var currentYear  = options.year  || today.gregorian.year;
    var currentMonth = options.month || today.gregorian.month;
    var onSelect = options.onSelect || function() {};
    var selectedDate = options.selected ? new TripleDate(options.selected) : null;

    function render() {
      var cal = TripleDate.buildMonth(currentYear, currentMonth);
      var todayHj = today.hijri;
      var todaySh = today.persian;

      var html = '<div class="tcal-wrap" dir="rtl">';

      // رأس التقويم
      html += '<div class="tcal-header">';
      html += '<button class="tcal-nav" onclick="__tcalPrev()">&#8250;</button>';
      html += '<div class="tcal-title">';
      html += '<span class="tcal-month-gr">' + cal.monthName + ' ' + currentYear + '</span>';
      var firstDay = new TripleDate({ year: currentYear, month: currentMonth, day: 1 });
      var lastDay  = new TripleDate({ year: currentYear, month: currentMonth, day: cal.daysInMonth });
      html += '<span class="tcal-month-hj">' +
        MONTHS_HJ[firstDay.hijri.month - 1] + ' – ' + MONTHS_HJ[lastDay.hijri.month - 1] +
        ' ' + firstDay.hijri.year + ' هـ</span>';
      html += '<span class="tcal-month-sh">' +
        MONTHS_SH_AR[firstDay.persian.month - 1] + ' – ' + MONTHS_SH_AR[lastDay.persian.month - 1] +
        ' ' + firstDay.persian.year + ' ش</span>';
      html += '</div>';
      html += '<button class="tcal-nav" onclick="__tcalNext()">&#8249;</button>';
      html += '</div>';

      // أيام الأسبوع
      html += '<div class="tcal-grid tcal-days-header">';
      DAYS_AR_SHORT.forEach(function(d) {
        html += '<div class="tcal-cell tcal-day-name">' + d + '</div>';
      });
      html += '</div>';

      // أيام الشهر
      cal.weeks.forEach(function(week) {
        html += '<div class="tcal-grid">';
        week.forEach(function(td) {
          if (!td) {
            html += '<div class="tcal-cell tcal-empty"></div>';
          } else {
            var isToday = td.isSame(today);
            var isSelected = selectedDate && td.isSame(selectedDate);
            var cls = 'tcal-cell tcal-day';
            if (isToday) cls += ' tcal-today';
            if (isSelected) cls += ' tcal-selected';

            var hj = td.hijri;
            var sh = td.persian;

            html += '<div class="' + cls + '" onclick="__tcalSelect(\'' + td.toISO() + '\')">';
            html += '<span class="tcal-d-gr">' + td.gregorian.day + '</span>';
            html += '<span class="tcal-d-hj">' + hj.day + '</span>';
            html += '<span class="tcal-d-sh">' + sh.day + '</span>';
            html += '</div>';
          }
        });
        html += '</div>';
      });

      // مؤشر اليوم الحالي
      html += '<div class="tcal-footer">';
      var allFmt = today.formatAll();
      html += '<div class="tcal-today-bar">';
      html += '<span class="tcal-badge gr">م ' + today.formatGregorian('D/M/YYYY') + '</span>';
      html += '<span class="tcal-badge hj">هـ ' + today.formatHijri('D/M/YYYY') + '</span>';
      html += '<span class="tcal-badge sh">ش ' + today.formatPersian('D/M/YYYY') + '</span>';
      html += '</div>';
      html += '</div>';

      html += '</div>'; // tcal-wrap

      container.innerHTML = html;

      // CSS
      if (!document.getElementById('__tcal_style')) {
        var style = document.createElement('style');
        style.id = '__tcal_style';
        style.textContent = `
.tcal-wrap{font-family:inherit;direction:rtl;user-select:none;max-width:380px}
.tcal-header{display:flex;align-items:center;justify-content:space-between;margin-bottom:10px;gap:8px}
.tcal-nav{background:rgba(201,168,76,0.15);border:1px solid rgba(201,168,76,0.3);color:#c9a84c;border-radius:8px;width:32px;height:32px;cursor:pointer;font-size:18px;display:flex;align-items:center;justify-content:center;transition:.2s}
.tcal-nav:hover{background:rgba(201,168,76,0.3)}
.tcal-title{text-align:center;flex:1}
.tcal-month-gr{display:block;font-size:16px;font-weight:700;color:#fff}
.tcal-month-hj{display:block;font-size:11px;color:#c9a84c;opacity:.8}
.tcal-month-sh{display:block;font-size:11px;color:#88c5a0;opacity:.8}
.tcal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:3px;margin-bottom:3px}
.tcal-days-header .tcal-cell{font-size:11px;color:rgba(255,255,255,.4);font-weight:600;text-align:center;padding:4px 0}
.tcal-cell{border-radius:8px;text-align:center;cursor:default}
.tcal-day{padding:4px 2px;cursor:pointer;transition:.15s;border:1px solid transparent}
.tcal-day:hover{background:rgba(201,168,76,0.1);border-color:rgba(201,168,76,0.2)}
.tcal-today{background:rgba(201,168,76,0.15);border-color:rgba(201,168,76,0.5)!important}
.tcal-selected{background:rgba(201,168,76,0.35)!important;border-color:#c9a84c!important}
.tcal-d-gr{display:block;font-size:14px;font-weight:700;color:#fff;line-height:1.2}
.tcal-d-hj{display:block;font-size:9px;color:#c9a84c;opacity:.75;line-height:1.2}
.tcal-d-sh{display:block;font-size:9px;color:#88c5a0;opacity:.75;line-height:1.2}
.tcal-empty{background:transparent}
.tcal-footer{margin-top:10px;padding-top:10px;border-top:1px solid rgba(255,255,255,.07)}
.tcal-today-bar{display:flex;flex-wrap:wrap;gap:6px;justify-content:center}
.tcal-badge{padding:4px 10px;border-radius:20px;font-size:11px;font-weight:600}
.tcal-badge.gr{background:rgba(255,255,255,.08);color:rgba(255,255,255,.7)}
.tcal-badge.hj{background:rgba(201,168,76,.12);color:#c9a84c}
.tcal-badge.sh{background:rgba(136,197,160,.12);color:#88c5a0}
        `;
        document.head.appendChild(style);
      }
    }

    window.__tcalPrev = function() {
      currentMonth--;
      if (currentMonth < 1) { currentMonth = 12; currentYear--; }
      render();
    };
    window.__tcalNext = function() {
      currentMonth++;
      if (currentMonth > 12) { currentMonth = 1; currentYear++; }
      render();
    };
    window.__tcalSelect = function(iso) {
      selectedDate = new TripleDate(iso);
      onSelect(selectedDate);
      render();
    };

    render();
    return { refresh: render };
  };

  // ======================================================
  // دوال مساعدة
  // ======================================================

  function pad(n) { return n < 10 ? '0' + n : '' + n; }

  // تحويل رقم لعربي
  TripleDate.toArabicNumerals = function(n) {
    return String(n).replace(/[0-9]/g, function(d) {
      return '٠١٢٣٤٥٦٧٨٩'[d];
    });
  };

  // هل السنة الهجرية كبيسة؟
  TripleDate.isLeapHijri = function(year) {
    return (((year * 11) + 14) % 30) < 11;
  };

  // عدد أيام الشهر الميلادي
  TripleDate.daysInGregorianMonth = function(year, month) {
    return new Date(year, month, 0).getDate();
  };

  // ======================================================
  // تصدير المكتبة
  // ======================================================

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = TripleDate;
  } else {
    root.TripleDate = TripleDate;
  }

})(typeof window !== 'undefined' ? window : this);

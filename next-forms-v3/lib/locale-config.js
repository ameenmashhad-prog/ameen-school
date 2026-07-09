export const localeMeta = {
  ar: {
    label: 'العربية',
    dir: 'rtl',
    calendarLabel: 'ميلادي أساسي + هجري تابع',
    fontVariable: 'var(--font-ar)',
    numbers: 'latn'
  },
  fa: {
    label: 'فارسی',
    dir: 'rtl',
    calendarLabel: 'هجری شمسی پایه + میلادی تابع',
    fontVariable: 'var(--font-fa)',
    numbers: 'fa'
  },
  en: {
    label: 'English',
    dir: 'ltr',
    calendarLabel: 'Gregorian only',
    fontVariable: 'var(--font-en)',
    numbers: 'latn'
  }
};

export function isValidLocale(locale) {
  return ['ar', 'fa', 'en'].includes(locale);
}

export function localeNumber(locale, value) {
  return new Intl.NumberFormat(locale === 'fa' ? 'fa-IR' : locale === 'ar' ? 'en' : 'en-US').format(value);
}

export function localeDateLabel(locale) {
  if (locale === 'fa') return 'Jalali Primary';
  if (locale === 'ar') return 'Gregorian Primary + Hijri Secondary';
  return 'Gregorian';
}

export function localeFontClass(locale) {
  if (locale === 'fa') return '[font-family:var(--font-fa)]';
  if (locale === 'en') return '[font-family:var(--font-en)]';
  return '[font-family:var(--font-ar)]';
}

export function formatDateForLocale(locale, iso) {
  if (!iso) return '—';
  const date = new Date(`${iso}T00:00:00`);
  if (Number.isNaN(date.getTime())) return iso;

  if (locale === 'fa') {
    const solar = new Intl.DateTimeFormat('fa-IR-u-ca-persian', { year: 'numeric', month: 'long', day: 'numeric' }).format(date);
    const greg = new Intl.DateTimeFormat('en-CA', { year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
    return `${solar} (${greg})`;
  }

  if (locale === 'ar') {
    const greg = new Intl.DateTimeFormat('ar-IQ', { year: 'numeric', month: 'long', day: 'numeric' }).format(date);
    const hijri = new Intl.DateTimeFormat('ar-SA-u-ca-islamic', { year: 'numeric', month: 'long', day: 'numeric' }).format(date);
    return `${greg} (${hijri})`.replace('حجري','هجري');
  }

  return new Intl.DateTimeFormat('en-US', { year: 'numeric', month: 'long', day: 'numeric' }).format(date);
}

export const localeMeta = {
  ar: {
    label: 'العربية',
    dir: 'rtl',
    calendarLabel: 'ميلادي أساسي + هجري/شمسي تابع',
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
  if (locale === 'ar') return 'Gregorian Primary';
  return 'Gregorian';
}

export function localeFontClass(locale) {
  if (locale === 'fa') return '[font-family:var(--font-fa)]';
  if (locale === 'en') return '[font-family:var(--font-en)]';
  return '[font-family:var(--font-ar)]';
}

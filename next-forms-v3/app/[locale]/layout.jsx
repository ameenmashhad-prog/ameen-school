import { isValidLocale, localeMeta } from '@/lib/locale-config';

export default function LocaleLayout({ children, params }) {
  const locale = params.locale;
  if (!isValidLocale(locale)) {
    return children;
  }

  return (
    <div lang={locale} dir={localeMeta[locale].dir} data-locale={locale}>
      {children}
    </div>
  );
}

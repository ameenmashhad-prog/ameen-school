import { isValidLocale, localeMeta } from '@/lib/locale-config';

export default async function LocaleLayout({ children, params }) {
  const { locale } = await params;
  if (!isValidLocale(locale)) {
    return children;
  }

  const dir = localeMeta[locale].dir;
  const syncHtml = `document.documentElement.lang=${JSON.stringify(locale)};document.documentElement.dir=${JSON.stringify(dir)};document.documentElement.dataset.locale=${JSON.stringify(locale)};`;

  return (
    <>
      <script dangerouslySetInnerHTML={{ __html: syncHtml }} />
      <div lang={locale} dir={dir} data-locale={locale}>
        {children}
      </div>
    </>
  );
}

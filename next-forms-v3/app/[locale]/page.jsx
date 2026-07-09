import Link from 'next/link';
import { getDictionary } from '@/lib/i18n';
import { localeMeta } from '@/lib/locale-config';

export default async function LocaleHome({ params }) {
  const locale = params.locale;
  const dict = await getDictionary(locale, 'forms');
  const meta = localeMeta[locale];

  return (
    <main className="mx-auto min-h-screen max-w-6xl px-6 py-10">
      <section className="rounded-[28px] border border-slate-200 bg-white/90 p-8 shadow-soft">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="mb-2 text-sm text-slate-500">Amin Forms Studio v3</p>
            <h1 className="text-4xl font-black text-slate-900">{dict.home.title}</h1>
            <p className="mt-3 max-w-3xl text-lg text-slate-600">{dict.home.subtitle}</p>
          </div>
          <div className="rounded-2xl border border-brand-100 bg-brand-50 px-4 py-3 text-sm text-brand-700">
            <div>{meta.label}</div>
            <div>{meta.calendarLabel}</div>
          </div>
        </div>

        <div className="mt-8 grid gap-4 md:grid-cols-3">
          <Link className="rounded-3xl border border-slate-200 bg-slate-50 p-5 font-bold text-slate-900 transition hover:border-brand-300 hover:bg-white" href={`/${locale}/forms/builder`}>
            {dict.home.startBuilder}
          </Link>
          <div className="rounded-3xl border border-slate-200 bg-slate-50 p-5 text-slate-700">
            {dict.home.localAssetsOnly}
          </div>
          <div className="rounded-3xl border border-slate-200 bg-slate-50 p-5 text-slate-700">
            {dict.home.rpcOnly}
          </div>
        </div>
      </section>
    </main>
  );
}

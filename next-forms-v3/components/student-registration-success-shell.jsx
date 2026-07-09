"use client";

import Link from 'next/link';
import LanguageSwitcher from '@/components/language-switcher';
import { localeFontClass, localeMeta } from '@/lib/locale-config';

export default function StudentRegistrationSuccessShell({ locale, labels, forms, payload }) {
  const meta = localeMeta[locale] || localeMeta.ar;

  return (
    <main className={`mx-auto min-h-screen max-w-4xl px-6 py-10 ${localeFontClass(locale)}`} dir={meta.dir}>
      <section className="rounded-[28px] border border-emerald-200 bg-white p-8 shadow-soft">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="mb-2 text-sm text-slate-500">{forms.builder.badge}</p>
            <h1 className="text-3xl font-black text-slate-950">{labels.submitSuccessTitle}</h1>
            <p className="mt-3 max-w-2xl text-base leading-8 text-slate-600">{labels.successPageSubtitle}</p>
          </div>
          <LanguageSwitcher locale={locale} onChange={() => {}} labels={forms.languageSwitcher} />
        </div>

        <div className="mt-8 grid gap-4 md:grid-cols-3">
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
            <div className="text-xs text-slate-500">{labels.submissionReference}</div>
            <div className="mt-2 font-black text-slate-900">{payload.ref || '—'}</div>
          </div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
            <div className="text-xs text-slate-500">{labels.submittedAt}</div>
            <div className="mt-2 font-black text-slate-900">{payload.submittedAt || '—'}</div>
          </div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
            <div className="text-xs text-slate-500">{labels.successApplicant}</div>
            <div className="mt-2 font-black text-slate-900">{payload.applicant || '—'}</div>
          </div>
        </div>

        <div className="mt-8 flex flex-wrap gap-3 no-print">
          <Link href={`/${locale}/forms/student-registration`} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labels.openNewRegistration}</Link>
          <Link href={`/${locale}/forms/builder`} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.returnToBuilder}</Link>
          <button onClick={() => window.print()} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.printReceipt}</button>
        </div>
      </section>
    </main>
  );
}

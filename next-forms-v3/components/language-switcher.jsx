"use client";

export default function LanguageSwitcher({ locale, onChange, labels }) {
  return (
    <div className="flex overflow-hidden rounded-2xl border border-slate-200 bg-white">
      {['ar', 'fa', 'en'].map((code) => (
        <button
          key={code}
          onClick={() => onChange(code)}
          className={`px-4 py-2 text-sm font-bold transition ${locale === code ? 'bg-brand-500 text-white' : 'text-slate-600 hover:bg-slate-50'}`}
        >
          {labels[code]}
        </button>
      ))}
    </div>
  );
}

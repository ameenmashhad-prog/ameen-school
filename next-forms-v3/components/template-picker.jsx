"use client";

export default function TemplatePicker({ templates, locale, labels, onPick }) {
  return (
    <div>
      <h3 className="text-lg font-black text-slate-950">{labels.title}</h3>
      <div className="mt-3 grid gap-2">
        {templates.map((template) => (
          <button
            key={template.key}
            onClick={() => onPick(template.key)}
            className="rounded-2xl border border-slate-200 bg-white px-3 py-3 text-start text-sm text-slate-700 transition hover:border-brand-300 hover:bg-brand-50"
          >
            <div className="font-bold text-slate-950">{template.title[locale]}</div>
            <div className="mt-1 text-xs text-slate-500">{template.description[locale]}</div>
          </button>
        ))}
      </div>
    </div>
  );
}

export default function PreviewSheet({ locale, schema, labels, printable = false }) {
  const forms = labels.forms;

  return (
    <section className={`rounded-[24px] border border-slate-200 bg-white p-6 ${printable ? 'shadow-none' : ''}`}>
      <div className="mb-5 border-b border-slate-200 pb-4 text-center">
        <div className="text-sm text-slate-500">{labels.reports.preview.school}</div>
        <h2 className="mt-2 text-2xl font-black text-slate-950">{schema.title[locale]}</h2>
        <div className="mt-2 text-sm text-slate-500">{labels.reports.preview.orientation}: {forms.builder.printModes.portrait}</div>
      </div>

      <div className="grid gap-4">
        {schema.fields.map((field) => (
          <div key={field.id} className="rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-4">
            <label className="mb-2 block text-sm font-bold text-slate-800">
              {field.label[locale]} {field.required ? '*' : ''}
            </label>
            <div className="rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm text-slate-400">
              {field.placeholder?.[locale] || forms.builder.placeholderPreview}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

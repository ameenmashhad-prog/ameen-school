function renderFieldInput(field, locale, labels) {
  const placeholder = field.placeholder?.[locale] || labels.forms.builder.placeholderPreview;

  if (field.type === 'select') {
    return (
      <select disabled className="w-full rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm text-slate-400">
        <option>{placeholder}</option>
        {(field.options || []).map((option) => (
          <option key={option.id}>{option.label?.[locale] || option.value}</option>
        ))}
      </select>
    );
  }

  if (field.type === 'file') {
    return <div className="rounded-2xl border border-dashed border-slate-300 bg-white px-3 py-6 text-center text-sm text-slate-400">{placeholder}</div>;
  }

  if (field.type === 'signature') {
    return (
      <div className="rounded-2xl border border-dashed border-slate-300 bg-white px-3 py-8 text-center text-sm text-slate-400">
        <div>{placeholder}</div>
        <div className="mt-2 text-xs">{labels.forms.builder.signatureFallbackNote}</div>
      </div>
    );
  }

  return <input disabled className="w-full rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm text-slate-400" placeholder={placeholder} />;
}

export default function PreviewSheet({ locale, schema, labels, printable = false }) {
  const forms = labels.forms;

  return (
    <section className={`rounded-[24px] border border-slate-200 bg-white p-6 ${printable ? 'shadow-none' : ''}`}>
      <div className="mb-5 border-b border-slate-200 pb-4 text-center">
        <div className="text-sm text-slate-500">{labels.reports.preview.school}</div>
        <h2 className="mt-2 text-2xl font-black text-slate-950">{schema.title[locale]}</h2>
        <div className="mt-2 text-sm text-slate-500">{labels.reports.preview.orientation}: {schema.printOrientation === 'landscape' ? forms.builder.printModes.landscape : forms.builder.printModes.portrait}</div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        {schema.fields.map((field) => (
          <div key={field.id} className={`rounded-[18px] border border-slate-200 bg-slate-50 px-4 py-4 ${field.width === 'full' ? 'md:col-span-2' : ''}`}>
            <label className="mb-2 block text-sm font-bold text-slate-800">
              {field.label[locale]} {field.required ? '*' : ''}
            </label>
            {renderFieldInput(field, locale, labels)}
            {field.helpText?.[locale] ? <p className="mt-2 text-xs leading-6 text-slate-500">{field.helpText[locale]}</p> : null}
          </div>
        ))}
      </div>
    </section>
  );
}

"use client";

function FieldCard({ field, locale, selected, onSelect, onRemove }) {
  return (
    <article
      onClick={() => onSelect(field.id)}
      className={`rounded-[20px] border p-4 transition ${selected ? 'border-brand-500 bg-brand-50' : 'border-slate-200 bg-white'}`}
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="font-bold text-slate-950">{field.label[locale]}</div>
          <div className="mt-1 text-xs text-slate-500">{field.type} · {field.required ? 'required' : 'optional'}</div>
        </div>
        <button onClick={(e) => { e.stopPropagation(); onRemove(field.id); }} className="rounded-xl border border-red-200 px-2 py-1 text-xs font-bold text-red-600">×</button>
      </div>
    </article>
  );
}

export default function FormCanvas({ locale, schema, selectedFieldId, onSelect, onDropType, onRemove, labels }) {
  return (
    <div
      onDragOver={(e) => e.preventDefault()}
      onDrop={(e) => {
        e.preventDefault();
        const type = e.dataTransfer.getData('text/plain');
        if (type) onDropType(type);
      }}
      className="rounded-[24px] border border-dashed border-slate-300 bg-slate-50 p-4"
    >
      {schema.fields.length ? (
        <div className="grid gap-3">
          {schema.fields.map((field) => (
            <FieldCard
              key={field.id}
              field={field}
              locale={locale}
              selected={selectedFieldId === field.id}
              onSelect={onSelect}
              onRemove={onRemove}
            />
          ))}
        </div>
      ) : (
        <div className="rounded-[20px] bg-white px-6 py-12 text-center text-sm text-slate-500">
          <b className="block text-slate-900">{labels.builder.emptyCanvasTitle}</b>
          <span className="mt-2 block">{labels.builder.emptyCanvasHint}</span>
        </div>
      )}
    </div>
  );
}

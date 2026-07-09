"use client";

function FieldCard({ field, locale, labels, selected, onSelect, onRemove, onDuplicate, onMoveUp, onMoveDown, onDragField }) {
  return (
    <article
      draggable
      onDragStart={(event) => {
        event.dataTransfer.setData('text/field-id', field.id);
        event.dataTransfer.effectAllowed = 'move';
      }}
      onDragOver={(event) => event.preventDefault()}
      onDrop={(event) => {
        event.preventDefault();
        const draggedId = event.dataTransfer.getData('text/field-id');
        if (draggedId && draggedId !== field.id) onDragField(draggedId, field.id);
      }}
      onClick={() => onSelect(field.id)}
      className={`rounded-[20px] border p-4 transition ${selected ? 'border-brand-500 bg-brand-50' : 'border-slate-200 bg-white'}`}
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="font-bold text-slate-950">{field.label[locale]}</div>
          <div className="mt-1 text-xs text-slate-500">
            {labels.fieldLabels[field.type]} · {field.required ? labels.builder.requiredState : labels.builder.optionalState} · {field.width === 'half' ? labels.builder.widthHalf : labels.builder.widthFull}
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <button onClick={(e) => { e.stopPropagation(); onMoveUp(field.id); }} className="rounded-xl border border-slate-200 px-2 py-1 text-xs font-bold text-slate-600">↑</button>
          <button onClick={(e) => { e.stopPropagation(); onMoveDown(field.id); }} className="rounded-xl border border-slate-200 px-2 py-1 text-xs font-bold text-slate-600">↓</button>
          <button onClick={(e) => { e.stopPropagation(); onDuplicate(field.id); }} className="rounded-xl border border-slate-200 px-2 py-1 text-xs font-bold text-slate-600">⧉</button>
          <button onClick={(e) => { e.stopPropagation(); onRemove(field.id); }} className="rounded-xl border border-red-200 px-2 py-1 text-xs font-bold text-red-600">×</button>
        </div>
      </div>
      {field.helpText?.[locale] ? <p className="mt-3 text-xs leading-6 text-slate-500">{field.helpText[locale]}</p> : null}
    </article>
  );
}

export default function FormCanvas({ locale, schema, selectedFieldId, onSelect, onDropType, onRemove, onDuplicate, onMoveUp, onMoveDown, onReorderField, labels }) {
  return (
    <div
      onDragOver={(event) => event.preventDefault()}
      onDrop={(event) => {
        event.preventDefault();
        const type = event.dataTransfer.getData('text/plain');
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
              labels={labels}
              selected={selectedFieldId === field.id}
              onSelect={onSelect}
              onRemove={onRemove}
              onDuplicate={onDuplicate}
              onMoveUp={onMoveUp}
              onMoveDown={onMoveDown}
              onDragField={onReorderField}
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

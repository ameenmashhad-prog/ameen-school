"use client";

const fieldTypes = ['text', 'number', 'date', 'select', 'file', 'signature'];

export default function FieldPalette({ labels, onAdd, onDragStart }) {
  return (
    <div className="mt-5">
      <h3 className="text-lg font-black text-slate-950">{labels.builder.paletteTitle}</h3>
      <div className="mt-3 grid gap-2">
        {fieldTypes.map((type) => (
          <div
            key={type}
            draggable
            onDragStart={() => onDragStart(type)}
            className="flex items-center justify-between rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm text-slate-700"
          >
            <span>{labels.fieldLabels[type]}</span>
            <button onClick={() => onAdd(type)} className="rounded-xl bg-brand-50 px-3 py-1 font-bold text-brand-700">+</button>
          </div>
        ))}
      </div>
    </div>
  );
}

"use client";

import { useEffect, useMemo, useState } from 'react';
import LanguageSwitcher from '@/components/language-switcher';
import FieldPalette from '@/components/field-palette';
import FormCanvas from '@/components/form-canvas';
import PreviewSheet from '@/components/preview-sheet';
import TemplatePicker from '@/components/template-picker';
import { buildTemplateByKey, formTemplates } from '@/lib/form-templates';
import { localeMeta, localeNumber, localeDateLabel, localeFontClass } from '@/lib/locale-config';
import { saveDraftRpc, restoreVersionRpc, publishFormRpc } from '@/lib/rpc/forms-rpc';
import { cloneForm, makeField, nextVersionStamp } from '@/lib/utils';

export default function FormsStudioShell({ locale, dictionary }) {
  const [activeLocale, setActiveLocale] = useState(locale);
  const [schema, setSchema] = useState(() => buildTemplateByKey('student_registration'));
  const [selectedFieldId, setSelectedFieldId] = useState(null);
  const [saveState, setSaveState] = useState('idle');
  const [versions, setVersions] = useState([]);
  const [dragType, setDragType] = useState(null);

  const forms = dictionary.forms;
  const meta = localeMeta[activeLocale] || localeMeta.ar;

  useEffect(() => {
    const timer = setInterval(async () => {
      setSaveState('saving');
      try {
        const payload = {
          form_slug: schema.slug,
          locale: activeLocale,
          version_label: nextVersionStamp(),
          schema,
          visibility: schema.visibility,
          autosave: true
        };
        const result = await saveDraftRpc(payload);
        setVersions(prev => [{ label: payload.version_label, id: result?.version_id || payload.version_label }, ...prev].slice(0, 6));
        setSaveState('saved');
      } catch (error) {
        console.error(error);
        setSaveState('error');
      }
    }, 15000);
    return () => clearInterval(timer);
  }, [schema, activeLocale]);

  const selectedField = useMemo(() => schema.fields.find(field => field.id === selectedFieldId) || null, [schema, selectedFieldId]);

  function applyTemplate(templateKey) {
    setSchema(buildTemplateByKey(templateKey));
    setSelectedFieldId(null);
  }

  function addField(type) {
    const field = makeField(type, forms.fieldLabels[type] || type);
    setSchema(current => ({ ...current, fields: [...current.fields, field] }));
    setSelectedFieldId(field.id);
  }

  function updateField(fieldId, patch) {
    setSchema(current => ({
      ...current,
      fields: current.fields.map(field => field.id === fieldId ? { ...field, ...patch } : field)
    }));
  }

  function removeField(fieldId) {
    setSchema(current => ({
      ...current,
      fields: current.fields.filter(field => field.id !== fieldId)
    }));
    if (selectedFieldId === fieldId) setSelectedFieldId(null);
  }

  async function publishCurrent() {
    setSaveState('saving');
    try {
      await publishFormRpc({ form_slug: schema.slug, locale: activeLocale, schema, visibility: schema.visibility });
      setSaveState('saved');
    } catch (error) {
      console.error(error);
      setSaveState('error');
    }
  }

  async function restoreLatest() {
    const latest = versions[0];
    if (!latest) return;
    setSaveState('saving');
    try {
      const restored = await restoreVersionRpc({ version_id: latest.id });
      if (restored?.schema) setSchema(cloneForm(restored.schema));
      setSaveState('saved');
    } catch (error) {
      console.error(error);
      setSaveState('error');
    }
  }

  return (
    <main className={`mx-auto min-h-screen max-w-[1500px] px-4 py-6 ${localeFontClass(activeLocale)}`} dir={meta.dir}>
      <section className="rounded-[30px] border border-slate-200 bg-white/90 p-5 shadow-soft">
        <div className="flex flex-wrap items-start justify-between gap-4 border-b border-slate-200 pb-5">
          <div>
            <p className="mb-2 text-sm text-slate-500">{forms.builder.badge}</p>
            <h1 className="text-3xl font-black text-slate-950">{forms.builder.title}</h1>
            <p className="mt-2 max-w-4xl text-sm leading-7 text-slate-600">{forms.builder.subtitle}</p>
            <div className="mt-3 flex flex-wrap gap-2 text-sm">
              <span className="rounded-full bg-brand-50 px-3 py-1 font-bold text-brand-700">{meta.label}</span>
              <span className="rounded-full bg-slate-100 px-3 py-1 text-slate-600">{localeDateLabel(activeLocale)}</span>
              <span className="rounded-full bg-slate-100 px-3 py-1 text-slate-600">{forms.builder.numberMode}: {localeNumber(activeLocale, 123456)}</span>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <LanguageSwitcher locale={activeLocale} onChange={setActiveLocale} labels={forms.languageSwitcher} />
            <button onClick={restoreLatest} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{forms.builder.restoreLatest}</button>
            <button onClick={publishCurrent} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{forms.builder.publish}</button>
          </div>
        </div>

        <div className="mt-5 grid gap-4 xl:grid-cols-[280px_minmax(0,1fr)_420px]">
          <aside className="rounded-[24px] border border-slate-200 bg-slate-50 p-4">
            <TemplatePicker templates={formTemplates} locale={activeLocale} labels={forms.templates} onPick={applyTemplate} />
            <FieldPalette labels={forms.fieldLabels} onAdd={addField} onDragStart={setDragType} />
            <div className="mt-5 rounded-2xl border border-dashed border-slate-300 bg-white p-4 text-sm text-slate-600">
              <b className="block text-slate-900">{forms.builder.autosaveStatusTitle}</b>
              <div className="mt-2">{forms.builder.autosaveEvery15}</div>
              <div className="mt-2 font-bold text-brand-700">{forms.builder.currentSaveState[saveState]}</div>
            </div>
          </aside>

          <section className="space-y-4">
            <div className="rounded-[24px] border border-slate-200 bg-white p-4">
              <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
                <div>
                  <h2 className="text-xl font-black text-slate-950">{schema.title[activeLocale]}</h2>
                  <p className="text-sm text-slate-500">{schema.slug} · {forms.builder.visibilityLabel}: {forms.visibility[schema.visibility]}</p>
                </div>
                <div className="flex flex-wrap gap-2 text-sm">
                  <span className="rounded-full bg-slate-100 px-3 py-1 text-slate-600">{forms.builder.fieldCount}: {schema.fields.length}</span>
                  <span className="rounded-full bg-slate-100 px-3 py-1 text-slate-600">RBAC: {forms.visibility[schema.visibility]}</span>
                </div>
              </div>
              <FormCanvas
                locale={activeLocale}
                schema={schema}
                selectedFieldId={selectedFieldId}
                onSelect={setSelectedFieldId}
                onDropType={addField}
                onRemove={removeField}
                dragType={dragType}
                labels={forms}
              />
            </div>

            <div className="rounded-[24px] border border-slate-200 bg-white p-4 print-only">
              <PreviewSheet locale={activeLocale} schema={schema} labels={dictionary} printable />
            </div>
          </section>

          <aside className="space-y-4">
            <div className="rounded-[24px] border border-slate-200 bg-slate-50 p-4">
              <h3 className="text-lg font-black text-slate-950">{forms.builder.fieldSettings}</h3>
              {selectedField ? (
                <div className="mt-4 space-y-3">
                  <label className="block text-sm font-bold text-slate-700">
                    {forms.builder.fieldLabel}
                    <input
                      className="mt-2 w-full rounded-2xl border border-slate-200 bg-white px-3 py-2"
                      value={selectedField.label[activeLocale]}
                      onChange={(e) => updateField(selectedField.id, {
                        label: { ...selectedField.label, [activeLocale]: e.target.value }
                      })}
                    />
                  </label>
                  <label className="block text-sm font-bold text-slate-700">
                    {forms.builder.placeholder}
                    <input
                      className="mt-2 w-full rounded-2xl border border-slate-200 bg-white px-3 py-2"
                      value={selectedField.placeholder?.[activeLocale] || ''}
                      onChange={(e) => updateField(selectedField.id, {
                        placeholder: { ...(selectedField.placeholder || {}), [activeLocale]: e.target.value }
                      })}
                    />
                  </label>
                  <label className="flex items-center gap-2 rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm text-slate-700">
                    <input
                      type="checkbox"
                      checked={selectedField.required}
                      onChange={(e) => updateField(selectedField.id, { required: e.target.checked })}
                    />
                    {forms.builder.requiredToggle}
                  </label>
                </div>
              ) : (
                <p className="mt-4 text-sm leading-7 text-slate-500">{forms.builder.selectFieldHint}</p>
              )}
            </div>

            <div className="rounded-[24px] border border-slate-200 bg-white p-4">
              <div className="mb-3 flex items-center justify-between gap-3">
                <h3 className="text-lg font-black text-slate-950">{forms.builder.previewTitle}</h3>
                <button onClick={() => window.print()} className="rounded-2xl border border-slate-200 px-3 py-2 text-sm font-bold text-slate-700">{dictionary.reports.preview.print}</button>
              </div>
              <PreviewSheet locale={activeLocale} schema={schema} labels={dictionary} />
            </div>

            <div className="rounded-[24px] border border-slate-200 bg-white p-4">
              <h3 className="text-lg font-black text-slate-950">{dictionary.finance.glossary.title}</h3>
              <div className="mt-3 space-y-2 text-sm text-slate-700">
                {dictionary.finance.glossary.items.slice(0, 6).map((item) => (
                  <div key={item.key} className="rounded-2xl border border-slate-200 px-3 py-3">
                    <div className="font-bold text-slate-950">{item.label}</div>
                    <div className="mt-1 text-slate-500">{item.description}</div>
                  </div>
                ))}
              </div>
            </div>
          </aside>
        </div>
      </section>
    </main>
  );
}

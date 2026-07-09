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
import { cloneForm, generateId, makeField, nextVersionStamp, reorderList } from '@/lib/utils';

const LOCAL_LANGUAGE_KEY = 'amin_forms_v3_locale';

function localDraftKey(slug) {
  return `amin_forms_v3_draft_${slug}`;
}

export default function FormsStudioShell({ locale, dictionary }) {
  const forms = dictionary.forms;
  const [activeLocale, setActiveLocale] = useState(locale);
  const [schema, setSchema] = useState(() => buildTemplateByKey('student_registration'));
  const [selectedFieldId, setSelectedFieldId] = useState(null);
  const [saveState, setSaveState] = useState('idle');
  const [versions, setVersions] = useState([]);
  const [showRestoreNotice, setShowRestoreNotice] = useState(false);

  const meta = localeMeta[activeLocale] || localeMeta.ar;
  const selectedField = useMemo(() => schema.fields.find((field) => field.id === selectedFieldId) || null, [schema, selectedFieldId]);

  useEffect(() => {
    const remembered = window.localStorage.getItem(LOCAL_LANGUAGE_KEY);
    if (remembered && localeMeta[remembered]) {
      setActiveLocale(remembered);
    }
  }, []);

  useEffect(() => {
    window.localStorage.setItem(LOCAL_LANGUAGE_KEY, activeLocale);
  }, [activeLocale]);

  useEffect(() => {
    const raw = window.localStorage.getItem(localDraftKey(schema.slug));
    if (!raw) return;
    try {
      const parsed = JSON.parse(raw);
      if (parsed?.schema?.slug === schema.slug) {
        setSchema(parsed.schema);
        setVersions(parsed.versions || []);
        setShowRestoreNotice(true);
      }
    } catch (error) {
      console.error(error);
    }
  }, []);

  useEffect(() => {
    const timer = setInterval(async () => {
      setSaveState('saving');
      try {
        const versionLabel = nextVersionStamp();
        const payload = {
          form_slug: schema.slug,
          locale: activeLocale,
          version_label: versionLabel,
          schema,
          visibility: schema.visibility,
          autosave: true
        };
        const result = await saveDraftRpc(payload);
        const nextVersions = [{ label: versionLabel, id: result?.data?.version_id || result?.version_id || versionLabel, source: 'rpc' }, ...versions].slice(0, 8);
        setVersions(nextVersions);
        window.localStorage.setItem(localDraftKey(schema.slug), JSON.stringify({ schema, versions: nextVersions }));
        setSaveState('saved');
      } catch (error) {
        console.error(error);
        window.localStorage.setItem(localDraftKey(schema.slug), JSON.stringify({ schema, versions }));
        setSaveState('error');
      }
    }, 15000);
    return () => clearInterval(timer);
  }, [schema, activeLocale, versions]);

  function applyTemplate(templateKey) {
    const next = buildTemplateByKey(templateKey);
    setSchema(next);
    setSelectedFieldId(next.fields[0]?.id || null);
    setVersions([]);
    setShowRestoreNotice(false);
  }

  function updateSchema(patch) {
    setSchema((current) => ({ ...current, ...patch }));
  }

  function addField(type) {
    const field = makeField(type, forms.fieldLabels[type] || type);
    setSchema((current) => ({ ...current, fields: [...current.fields, field] }));
    setSelectedFieldId(field.id);
  }

  function updateField(fieldId, patch) {
    setSchema((current) => ({
      ...current,
      fields: current.fields.map((field) => field.id === fieldId ? { ...field, ...patch } : field)
    }));
  }

  function removeField(fieldId) {
    setSchema((current) => ({ ...current, fields: current.fields.filter((field) => field.id !== fieldId) }));
    if (selectedFieldId === fieldId) setSelectedFieldId(null);
  }

  function duplicateField(fieldId) {
    setSchema((current) => {
      const index = current.fields.findIndex((field) => field.id === fieldId);
      if (index === -1) return current;
      const duplicate = cloneForm(current.fields[index]);
      duplicate.id = generateId('field');
      const nextFields = [...current.fields];
      nextFields.splice(index + 1, 0, duplicate);
      setSelectedFieldId(duplicate.id);
      return { ...current, fields: nextFields };
    });
  }

  function moveField(fieldId, direction) {
    setSchema((current) => {
      const index = current.fields.findIndex((field) => field.id === fieldId);
      const target = direction === 'up' ? index - 1 : index + 1;
      if (index === -1 || target < 0 || target >= current.fields.length) return current;
      const nextFields = [...current.fields];
      const [item] = nextFields.splice(index, 1);
      nextFields.splice(target, 0, item);
      return { ...current, fields: nextFields };
    });
  }

  function reorderField(sourceId, targetId) {
    setSchema((current) => ({ ...current, fields: reorderList(current.fields, sourceId, targetId) }));
  }

  function addSelectOption() {
    if (!selectedField || selectedField.type !== 'select') return;
    const options = [...(selectedField.options || []), {
      id: generateId('option'),
      value: generateId('value'),
      label: {
        ar: 'خيار جديد',
        fa: 'گزینه جدید',
        en: 'New Option'
      }
    }];
    updateField(selectedField.id, { options });
  }

  function updateSelectOption(optionId, localeCode, value) {
    if (!selectedField || selectedField.type !== 'select') return;
    const options = (selectedField.options || []).map((option) => option.id === optionId ? {
      ...option,
      label: {
        ...option.label,
        [localeCode]: value
      }
    } : option);
    updateField(selectedField.id, { options });
  }

  function removeSelectOption(optionId) {
    if (!selectedField || selectedField.type !== 'select') return;
    const options = (selectedField.options || []).filter((option) => option.id !== optionId);
    updateField(selectedField.id, { options });
  }

  async function manualSave() {
    setSaveState('saving');
    try {
      const versionLabel = nextVersionStamp();
      const payload = {
        form_slug: schema.slug,
        locale: activeLocale,
        version_label: versionLabel,
        schema,
        visibility: schema.visibility,
        autosave: false
      };
      const result = await saveDraftRpc(payload);
      const nextVersions = [{ label: versionLabel, id: result?.data?.version_id || result?.version_id || versionLabel, source: 'rpc' }, ...versions].slice(0, 8);
      setVersions(nextVersions);
      window.localStorage.setItem(localDraftKey(schema.slug), JSON.stringify({ schema, versions: nextVersions }));
      setSaveState('saved');
      alert(forms.builder.manualSaveDone);
    } catch (error) {
      console.error(error);
      setSaveState('error');
    }
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
      if (latest.source === 'rpc') {
        const restored = await restoreVersionRpc({ version_id: latest.id });
        if (restored?.data?.schema) setSchema(cloneForm(restored.data.schema));
      } else {
        const raw = window.localStorage.getItem(localDraftKey(schema.slug));
        if (raw) {
          const parsed = JSON.parse(raw);
          if (parsed?.schema) setSchema(parsed.schema);
        }
      }
      setSaveState('saved');
    } catch (error) {
      console.error(error);
      setSaveState('error');
    }
  }

  return (
    <main className={`mx-auto min-h-screen max-w-[1550px] px-4 py-6 ${localeFontClass(activeLocale)}`} dir={meta.dir}>
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
            <button onClick={manualSave} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{forms.builder.saveDraft}</button>
            <button onClick={restoreLatest} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{forms.builder.restoreLatest}</button>
            <button onClick={publishCurrent} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{forms.builder.publish}</button>
          </div>
        </div>

        {showRestoreNotice ? (
          <div className="mt-4 rounded-2xl border border-brand-100 bg-brand-50 px-4 py-3 text-sm text-brand-800">
            {forms.builder.localDraftRecovered}
          </div>
        ) : null}

        <div className="mt-5 grid gap-4 xl:grid-cols-[280px_minmax(0,1fr)_420px]">
          <aside className="rounded-[24px] border border-slate-200 bg-slate-50 p-4">
            <TemplatePicker templates={formTemplates} locale={activeLocale} labels={forms.templates} onPick={applyTemplate} />
            <FieldPalette labels={forms.fieldLabels} onAdd={addField} />
            <div className="mt-5 rounded-2xl border border-dashed border-slate-300 bg-white p-4 text-sm text-slate-600">
              <b className="block text-slate-900">{forms.builder.autosaveStatusTitle}</b>
              <div className="mt-2">{forms.builder.autosaveEvery15}</div>
              <div className="mt-2 font-bold text-brand-700">{forms.builder.currentSaveState[saveState]}</div>
            </div>
            <div className="mt-5 rounded-2xl border border-slate-200 bg-white p-4">
              <h3 className="text-lg font-black text-slate-950">{forms.builder.versionsTitle}</h3>
              <div className="mt-3 space-y-2 text-sm text-slate-600">
                {versions.length ? versions.map((version) => (
                  <div key={version.id} className="rounded-2xl border border-slate-200 px-3 py-3">
                    <div className="font-bold text-slate-900">{version.label}</div>
                    <div className="text-xs text-slate-500">{version.source === 'rpc' ? 'RPC' : 'local'}</div>
                  </div>
                )) : <div>{forms.builder.noVersionsYet}</div>}
              </div>
            </div>
          </aside>

          <section className="space-y-4">
            <div className="rounded-[24px] border border-slate-200 bg-white p-4">
              <div className="grid gap-4 md:grid-cols-2">
                <label className="block text-sm font-bold text-slate-700">
                  {forms.builder.titleLabel}
                  <input className="mt-2 w-full rounded-2xl border border-slate-200 bg-white px-3 py-2" value={schema.title[activeLocale]} onChange={(e) => updateSchema({ title: { ...schema.title, [activeLocale]: e.target.value } })} />
                </label>
                <label className="block text-sm font-bold text-slate-700">
                  {forms.builder.slugLabel}
                  <input className="mt-2 w-full rounded-2xl border border-slate-200 bg-white px-3 py-2" value={schema.slug} onChange={(e) => updateSchema({ slug: e.target.value.trim() })} />
                </label>
                <label className="block text-sm font-bold text-slate-700">
                  {forms.builder.visibilityLabel}
                  <select className="mt-2 w-full rounded-2xl border border-slate-200 bg-white px-3 py-2" value={schema.visibility} onChange={(e) => updateSchema({ visibility: e.target.value })}>
                    {Object.entries(forms.visibility).map(([key, label]) => <option key={key} value={key}>{label}</option>)}
                  </select>
                </label>
                <label className="block text-sm font-bold text-slate-700">
                  {forms.builder.orientationLabel}
                  <select className="mt-2 w-full rounded-2xl border border-slate-200 bg-white px-3 py-2" value={schema.printOrientation || 'portrait'} onChange={(e) => updateSchema({ printOrientation: e.target.value })}>
                    <option value="portrait">{forms.builder.printModes.portrait}</option>
                    <option value="landscape">{forms.builder.printModes.landscape}</option>
                  </select>
                </label>
              </div>
            </div>

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
                onDuplicate={duplicateField}
                onMoveUp={(fieldId) => moveField(fieldId, 'up')}
                onMoveDown={(fieldId) => moveField(fieldId, 'down')}
                onReorderField={reorderField}
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
                      onChange={(e) => updateField(selectedField.id, { label: { ...selectedField.label, [activeLocale]: e.target.value } })}
                    />
                  </label>
                  <label className="block text-sm font-bold text-slate-700">
                    {forms.builder.placeholder}
                    <input
                      className="mt-2 w-full rounded-2xl border border-slate-200 bg-white px-3 py-2"
                      value={selectedField.placeholder?.[activeLocale] || ''}
                      onChange={(e) => updateField(selectedField.id, { placeholder: { ...(selectedField.placeholder || {}), [activeLocale]: e.target.value } })}
                    />
                  </label>
                  <label className="block text-sm font-bold text-slate-700">
                    {forms.builder.helpTextLabel}
                    <textarea
                      className="mt-2 min-h-24 w-full rounded-2xl border border-slate-200 bg-white px-3 py-2"
                      value={selectedField.helpText?.[activeLocale] || ''}
                      onChange={(e) => updateField(selectedField.id, { helpText: { ...(selectedField.helpText || {}), [activeLocale]: e.target.value } })}
                    />
                  </label>
                  <label className="block text-sm font-bold text-slate-700">
                    {forms.builder.widthLabel}
                    <select className="mt-2 w-full rounded-2xl border border-slate-200 bg-white px-3 py-2" value={selectedField.width || 'full'} onChange={(e) => updateField(selectedField.id, { width: e.target.value })}>
                      <option value="full">{forms.builder.widthFull}</option>
                      <option value="half">{forms.builder.widthHalf}</option>
                    </select>
                  </label>
                  <label className="flex items-center gap-2 rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm text-slate-700">
                    <input type="checkbox" checked={selectedField.required} onChange={(e) => updateField(selectedField.id, { required: e.target.checked })} />
                    {forms.builder.requiredToggle}
                  </label>

                  {selectedField.type === 'select' ? (
                    <div className="rounded-2xl border border-slate-200 bg-white p-4">
                      <div className="flex items-center justify-between gap-3">
                        <b className="text-sm text-slate-900">{forms.builder.optionsTitle}</b>
                        <button onClick={addSelectOption} className="rounded-xl bg-brand-50 px-3 py-1 text-xs font-bold text-brand-700">{forms.builder.addOption}</button>
                      </div>
                      <div className="mt-3 space-y-3">
                        {(selectedField.options || []).map((option) => (
                          <div key={option.id} className="rounded-2xl border border-slate-200 p-3">
                            <input className="mb-2 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm" value={option.label?.[activeLocale] || ''} onChange={(e) => updateSelectOption(option.id, activeLocale, e.target.value)} />
                            <div className="flex items-center justify-between gap-3">
                              <span className="text-xs text-slate-500">{option.value}</span>
                              <button onClick={() => removeSelectOption(option.id)} className="rounded-xl border border-red-200 px-2 py-1 text-xs font-bold text-red-600">{forms.builder.removeField}</button>
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  ) : null}
                </div>
              ) : (
                <p className="mt-4 text-sm leading-7 text-slate-500">{forms.builder.selectFieldHint}</p>
              )}
            </div>

            <div className="rounded-[24px] border border-slate-200 bg-white p-4">
              <div className="mb-3 flex items-center justify-between gap-3">
                <div>
                  <h3 className="text-lg font-black text-slate-950">{forms.builder.previewTitle}</h3>
                  <p className="text-sm text-slate-500">{forms.builder.previewDescription}</p>
                </div>
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

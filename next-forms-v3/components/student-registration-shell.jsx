"use client";

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import LanguageSwitcher from '@/components/language-switcher';
import { buildTemplateByKey } from '@/lib/form-templates';
import { formatDateForLocale, localeDateLabel, localeFontClass, localeMeta } from '@/lib/locale-config';
import { nextVersionStamp } from '@/lib/utils';
import { saveDraftRpc, listVersionsRpc, submitStudentRegistrationRpc } from '@/lib/rpc/forms-rpc';

const LOCAL_LANGUAGE_KEY = 'amin_forms_v3_locale';
const LOCAL_FORM_STATE_KEY = 'amin_forms_v3_student_registration_state';

function makeInitialValues(template) {
  return template.fields.reduce((acc, field) => {
    acc[field.id] = field.type === 'file' ? null : '';
    return acc;
  }, {});
}

function SectionCard({ title, children }) {
  return (
    <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
      <h2 className="mb-4 text-xl font-black text-slate-950">{title}</h2>
      <div className="grid gap-4 md:grid-cols-2">{children}</div>
    </section>
  );
}

function InputField({ field, locale, value, onChange, labelMap }) {
  const label = field.label?.[locale] || field.id;
  const placeholder = field.placeholder?.[locale] || '';
  const helpText = field.helpText?.[locale];
  const wrapperClass = field.width === 'full' ? 'md:col-span-2' : '';

  if (field.type === 'select') {
    return (
      <label className={`block ${wrapperClass}`}>
        <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
        <select value={value || ''} onChange={(event) => onChange(field.id, event.target.value)} className="w-full rounded-2xl border border-slate-200 bg-slate-50 px-3 py-3 text-sm text-slate-900">
          <option value="">{labelMap.selectPlaceholder}</option>
          {(field.options || []).map((option) => (
            <option key={option.id} value={option.value}>{option.label?.[locale] || option.value}</option>
          ))}
        </select>
        {helpText ? <small className="mt-2 block text-xs leading-6 text-slate-500">{helpText}</small> : null}
      </label>
    );
  }

  if (field.type === 'file') {
    return (
      <label className={`block ${wrapperClass}`}>
        <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
        <input type="file" accept={field.accept || '*'} onChange={(event) => {
          const file = event.target.files?.[0] || null;
          onChange(field.id, file ? { name: file.name, size: file.size, type: file.type } : null);
        }} className="w-full rounded-2xl border border-dashed border-slate-300 bg-slate-50 px-3 py-3 text-sm text-slate-700" />
        <small className="mt-2 block text-xs leading-6 text-slate-500">{value?.name || labelMap.fileHint}</small>
      </label>
    );
  }

  if (field.type === 'signature') {
    return (
      <label className={`block ${wrapperClass}`}>
        <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
        <input value={value || ''} onChange={(event) => onChange(field.id, event.target.value)} className="w-full rounded-2xl border border-slate-200 bg-slate-50 px-3 py-3 text-sm text-slate-900" placeholder={placeholder} />
        <small className="mt-2 block text-xs leading-6 text-slate-500">{labelMap.signatureHint}</small>
      </label>
    );
  }

  if (field.type === 'date') {
    return (
      <label className={`block ${wrapperClass}`}>
        <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
        <input type="date" value={value || ''} onChange={(event) => onChange(field.id, event.target.value)} className="w-full rounded-2xl border border-slate-200 bg-slate-50 px-3 py-3 text-sm text-slate-900" />
        <small className="mt-2 block text-xs leading-6 text-slate-500">{value ? formatDateForLocale(locale, value) : labelMap.dateHint}</small>
      </label>
    );
  }

  return (
    <label className={`block ${wrapperClass}`}>
      <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
      <input value={value || ''} onChange={(event) => onChange(field.id, event.target.value)} className="w-full rounded-2xl border border-slate-200 bg-slate-50 px-3 py-3 text-sm text-slate-900" placeholder={placeholder} />
      {helpText ? <small className="mt-2 block text-xs leading-6 text-slate-500">{helpText}</small> : null}
    </label>
  );
}

function PreviewCard({ locale, title, rows }) {
  return (
    <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
      <h3 className="mb-4 text-lg font-black text-slate-950">{title}</h3>
      <div className="space-y-3">
        {rows.map((row) => (
          <div key={row.label} className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
            <div className="text-xs text-slate-500">{row.label}</div>
            <div className="mt-1 font-bold text-slate-900">{row.value || '—'}</div>
          </div>
        ))}
      </div>
    </section>
  );
}

export default function StudentRegistrationShell({ locale, dictionary }) {
  const forms = dictionary.forms;
  const labelMap = forms.studentRegistration;
  const template = useMemo(() => buildTemplateByKey('student_registration'), []);
  const [activeLocale, setActiveLocale] = useState(locale);
  const [values, setValues] = useState(() => makeInitialValues(template));
  const [saveState, setSaveState] = useState('idle');
  const [submitState, setSubmitState] = useState('idle');
  const [versions, setVersions] = useState([]);
  const meta = localeMeta[activeLocale] || localeMeta.ar;

  useEffect(() => {
    const remembered = window.localStorage.getItem(LOCAL_LANGUAGE_KEY);
    if (remembered && localeMeta[remembered]) setActiveLocale(remembered);

    const raw = window.localStorage.getItem(LOCAL_FORM_STATE_KEY);
    if (raw) {
      try {
        const parsed = JSON.parse(raw);
        if (parsed?.values) setValues(parsed.values);
      } catch (error) {
        console.error(error);
      }
    }
  }, []);

  useEffect(() => {
    window.localStorage.setItem(LOCAL_LANGUAGE_KEY, activeLocale);
    document.documentElement.lang = activeLocale;
    document.documentElement.dir = meta.dir;
  }, [activeLocale, meta.dir]);

  useEffect(() => {
    let cancelled = false;
    async function loadVersions() {
      try {
        const result = await listVersionsRpc({ form_slug: template.slug });
        if (cancelled) return;
        const list = result?.data?.versions || result?.versions || [];
        setVersions(list);
      } catch (error) {
        console.error(error);
      }
    }
    loadVersions();
    return () => { cancelled = true; };
  }, [template.slug]);

  useEffect(() => {
    const timer = setInterval(async () => {
      window.localStorage.setItem(LOCAL_FORM_STATE_KEY, JSON.stringify({ values }));
      setSaveState('saving');
      try {
        await saveDraftRpc({
          form_slug: template.slug,
          locale: activeLocale,
          version_label: nextVersionStamp(),
          visibility: template.visibility,
          schema: template,
          form_values: values,
          autosave: true
        });
        setSaveState('saved');
      } catch (error) {
        console.error(error);
        setSaveState('error');
      }
    }, 15000);
    return () => clearInterval(timer);
  }, [values, template, activeLocale]);

  const fieldsBySection = useMemo(() => {
    return template.sections.map((section) => ({
      ...section,
      fields: template.fields.filter((field) => field.section === section.key)
    }));
  }, [template]);

  function setFieldValue(fieldId, value) {
    setValues((current) => ({ ...current, [fieldId]: value }));
  }

  function resetForm() {
    const next = makeInitialValues(template);
    setValues(next);
    window.localStorage.setItem(LOCAL_FORM_STATE_KEY, JSON.stringify({ values: next }));
    setSubmitState('idle');
  }

  function validateRequired() {
    return template.fields.filter((field) => field.required).every((field) => {
      const value = values[field.id];
      if (field.type === 'file') return !!value?.name;
      return String(value || '').trim().length > 0;
    });
  }

  async function submitForm() {
    if (!validateRequired()) {
      setSubmitState('validation_error');
      return;
    }

    setSubmitState('submitting');
    try {
      const payload = {
        form_slug: template.slug,
        locale: activeLocale,
        visibility: template.visibility,
        submission_ref: `SR-${Date.now()}`,
        schema: template,
        values
      };
      const result = await submitStudentRegistrationRpc(payload);
      if (result?.ok === false) {
        throw new Error(result.error || 'submit_failed');
      }
      setSubmitState('submitted');
      window.localStorage.setItem(LOCAL_FORM_STATE_KEY, JSON.stringify({ values }));
    } catch (error) {
      console.error(error);
      setSubmitState('submit_error');
    }
  }

  const previewGuardianRows = [
    { label: labelMap.fields.guardian_name, value: values.guardian_name },
    { label: labelMap.fields.guardian_phone, value: values.guardian_phone },
    { label: labelMap.fields.guardian_email, value: values.guardian_email },
    { label: labelMap.fields.guardian_address, value: values.guardian_address }
  ];
  const previewStudentRows = [
    { label: labelMap.fields.student_name, value: values.student_name },
    { label: labelMap.fields.student_birth_date, value: values.student_birth_date ? formatDateForLocale(activeLocale, values.student_birth_date) : '' },
    { label: labelMap.fields.student_grade, value: (template.fields.find((field) => field.id === 'student_grade')?.options || []).find((option) => option.value === values.student_grade)?.label?.[activeLocale] || '' },
    { label: labelMap.fields.student_gender, value: (template.fields.find((field) => field.id === 'student_gender')?.options || []).find((option) => option.value === values.student_gender)?.label?.[activeLocale] || '' },
    { label: labelMap.fields.student_notes, value: values.student_notes }
  ];

  return (
    <main className={`mx-auto min-h-screen max-w-[1480px] px-4 py-6 ${localeFontClass(activeLocale)}`} dir={meta.dir}>
      <section className="rounded-[30px] border border-slate-200 bg-white/90 p-5 shadow-soft">
        <div className="flex flex-wrap items-start justify-between gap-4 border-b border-slate-200 pb-5">
          <div>
            <p className="mb-2 text-sm text-slate-500">{forms.builder.badge}</p>
            <h1 className="text-3xl font-black text-slate-950">{labelMap.pageTitle}</h1>
            <p className="mt-2 max-w-4xl text-sm leading-7 text-slate-600">{labelMap.pageSubtitle}</p>
            <div className="mt-3 flex flex-wrap gap-2 text-sm">
              <span className="rounded-full bg-brand-50 px-3 py-1 font-bold text-brand-700">{meta.label}</span>
              <span className="rounded-full bg-slate-100 px-3 py-1 text-slate-600">{localeDateLabel(activeLocale)}</span>
              <span className="rounded-full bg-slate-100 px-3 py-1 text-slate-600">{labelMap.visibilityLabel}: {forms.visibility[template.visibility]}</span>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <LanguageSwitcher locale={activeLocale} onChange={setActiveLocale} labels={forms.languageSwitcher} />
            <Link href={`/${activeLocale}/forms/builder`} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labelMap.openBuilder}</Link>
            <button onClick={() => window.print()} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labelMap.printPreview}</button>
            <button onClick={submitForm} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labelMap.submit}</button>
          </div>
        </div>

        <div className="mt-5 grid gap-4 xl:grid-cols-[minmax(0,1fr)_420px]">
          <section className="space-y-4">
            <div className="rounded-[24px] border border-slate-200 bg-white p-4">
              <div className="grid gap-3 md:grid-cols-3">
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
                  <div className="text-slate-500">{labelMap.statusDraft}</div>
                  <div className="mt-1 font-bold text-slate-900">{saveState === 'saved' ? labelMap.saved : saveState === 'saving' ? labelMap.saving : saveState === 'error' ? labelMap.saveError : labelMap.notSavedYet}</div>
                </div>
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
                  <div className="text-slate-500">{labelMap.requiredCoverage}</div>
                  <div className="mt-1 font-bold text-slate-900">{template.fields.filter((field) => field.required && String(values[field.id] || '').trim()).length} / {template.fields.filter((field) => field.required).length}</div>
                </div>
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
                  <div className="text-slate-500">{labelMap.versionCount}</div>
                  <div className="mt-1 font-bold text-slate-900">{versions.length}</div>
                </div>
              </div>
            </div>

            {fieldsBySection.map((section) => (
              <SectionCard key={section.key} title={section.title[activeLocale]}>
                {section.fields.map((field) => (
                  <InputField
                    key={field.id}
                    field={field}
                    locale={activeLocale}
                    value={values[field.id]}
                    onChange={setFieldValue}
                    labelMap={{
                      selectPlaceholder: labelMap.selectPlaceholder,
                      fileHint: labelMap.fileHint,
                      signatureHint: labelMap.signatureHint,
                      dateHint: labelMap.dateHint
                    }}
                  />
                ))}
              </SectionCard>
            ))}

            <div className="no-print flex flex-wrap gap-3 rounded-[24px] border border-slate-200 bg-white p-4 shadow-soft">
              <button onClick={resetForm} className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-2 font-bold text-amber-800">{labelMap.reset}</button>
              <button onClick={submitForm} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labelMap.submit}</button>
              {submitState === 'validation_error' ? <span className="self-center text-sm font-bold text-red-600">{labelMap.validationError}</span> : null}
              {submitState === 'submitted' ? <span className="self-center text-sm font-bold text-brand-700">{labelMap.submitSuccess}</span> : null}
              {submitState === 'submit_error' ? <span className="self-center text-sm font-bold text-red-600">{labelMap.submitError}</span> : null}
              {submitState === 'submitting' ? <span className="self-center text-sm font-bold text-slate-700">{labelMap.submitting}</span> : null}
            </div>
          </section>

          <aside className="space-y-4">
            <PreviewCard locale={activeLocale} title={labelMap.guardianPreviewTitle} rows={previewGuardianRows} />
            <PreviewCard locale={activeLocale} title={labelMap.studentPreviewTitle} rows={previewStudentRows} />
            <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
              <h3 className="mb-3 text-lg font-black text-slate-950">{labelMap.printPreviewTitle}</h3>
              <PreviewSheet locale={activeLocale} schema={template} labels={dictionary} />
            </section>
            <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft no-print">
              <h3 className="mb-3 text-lg font-black text-slate-950">{labelMap.versionListTitle}</h3>
              <div className="space-y-2 text-sm text-slate-600">
                {versions.length ? versions.map((version, index) => (
                  <div key={version.version_id || version.version_label || index} className="rounded-2xl border border-slate-200 px-3 py-3">
                    <div className="font-bold text-slate-900">{version.version_label || version.label || version.saved_at || 'version'}</div>
                    <div className="text-xs text-slate-500">{version.saved_at || version.source || 'rpc'}</div>
                  </div>
                )) : <div>{labelMap.noVersions}</div>}
              </div>
            </section>
          </aside>
        </div>
      </section>
    </main>
  );
}

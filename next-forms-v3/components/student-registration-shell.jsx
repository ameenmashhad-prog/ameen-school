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
const MAX_FILE_SIZE = 10 * 1024 * 1024;

function makeInitialValues(template) {
  return template.fields.reduce((acc, field) => {
    acc[field.id] = field.type === 'file' ? null : '';
    return acc;
  }, {});
}

function SectionCard({ title, subtitle, children }) {
  return (
    <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
      <div className="mb-4 border-b border-slate-100 pb-3">
        <h2 className="text-xl font-black text-slate-950">{title}</h2>
        {subtitle ? <p className="mt-1 text-sm leading-7 text-slate-500">{subtitle}</p> : null}
      </div>
      <div className="grid gap-4 md:grid-cols-2">{children}</div>
    </section>
  );
}

function StatusPill({ tone = 'slate', children }) {
  const tones = {
    slate: 'bg-slate-100 text-slate-700',
    brand: 'bg-brand-50 text-brand-700',
    success: 'bg-emerald-50 text-emerald-700',
    warning: 'bg-amber-50 text-amber-700',
    danger: 'bg-rose-50 text-rose-700'
  };
  return <span className={`rounded-full px-3 py-1 text-sm font-bold ${tones[tone] || tones.slate}`}>{children}</span>;
}

function InputField({ field, locale, value, error, onChange, labelMap }) {
  const label = field.label?.[locale] || field.id;
  const placeholder = field.placeholder?.[locale] || '';
  const helpText = field.helpText?.[locale];
  const wrapperClass = field.width === 'full' ? 'md:col-span-2' : '';
  const baseInputClass = `w-full rounded-2xl border px-3 py-3 text-sm ${error ? 'border-rose-300 bg-rose-50 text-rose-900' : 'border-slate-200 bg-slate-50 text-slate-900'}`;

  const metaBlock = (
    <>
      {helpText ? <small className="mt-2 block text-xs leading-6 text-slate-500">{helpText}</small> : null}
      {error ? <small className="mt-2 block text-xs font-bold leading-6 text-rose-600">{error}</small> : null}
    </>
  );

  if (field.type === 'select') {
    return (
      <label className={`block ${wrapperClass}`}>
        <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
        <select value={value || ''} onChange={(event) => onChange(field.id, event.target.value)} className={baseInputClass}>
          <option value="">{labelMap.selectPlaceholder}</option>
          {(field.options || []).map((option) => (
            <option key={option.id} value={option.value}>{option.label?.[locale] || option.value}</option>
          ))}
        </select>
        {metaBlock}
      </label>
    );
  }

  if (field.type === 'file') {
    return (
      <label className={`block ${wrapperClass}`}>
        <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
        <input
          type="file"
          accept={field.accept || '*'}
          onChange={(event) => {
            const file = event.target.files?.[0] || null;
            onChange(field.id, file ? {
              name: file.name,
              size: file.size,
              type: file.type,
              lastModified: file.lastModified
            } : null);
          }}
          className={`${baseInputClass} border-dashed`}
        />
        <small className="mt-2 block text-xs leading-6 text-slate-500">{value?.name || labelMap.fileHint}</small>
        {error ? <small className="mt-2 block text-xs font-bold leading-6 text-rose-600">{error}</small> : null}
      </label>
    );
  }

  if (field.type === 'signature') {
    return (
      <label className={`block ${wrapperClass}`}>
        <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
        <input value={value || ''} onChange={(event) => onChange(field.id, event.target.value)} className={baseInputClass} placeholder={placeholder} />
        <small className="mt-2 block text-xs leading-6 text-slate-500">{labelMap.signatureHint}</small>
        {error ? <small className="mt-2 block text-xs font-bold leading-6 text-rose-600">{error}</small> : null}
      </label>
    );
  }

  if (field.type === 'date') {
    return (
      <label className={`block ${wrapperClass}`}>
        <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
        <input type="date" value={value || ''} onChange={(event) => onChange(field.id, event.target.value)} className={baseInputClass} />
        <small className="mt-2 block text-xs leading-6 text-slate-500">{value ? formatDateForLocale(locale, value) : labelMap.dateHint}</small>
        {error ? <small className="mt-2 block text-xs font-bold leading-6 text-rose-600">{error}</small> : null}
      </label>
    );
  }

  const inputType = field.id === 'guardian_email' ? 'email' : field.id === 'guardian_phone' ? 'tel' : field.type === 'number' ? 'number' : 'text';

  return (
    <label className={`block ${wrapperClass}`}>
      <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
      <input value={value || ''} type={inputType} onChange={(event) => onChange(field.id, event.target.value)} className={baseInputClass} placeholder={placeholder} />
      {metaBlock}
    </label>
  );
}

function PreviewCard({ title, rows }) {
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

function SuccessPanel({ labels, receipt, locale }) {
  if (!receipt) return null;

  return (
    <section className="rounded-[24px] border border-emerald-200 bg-emerald-50 p-5 shadow-soft">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="text-xl font-black text-emerald-800">{labels.submitSuccessTitle}</h3>
          <p className="mt-1 text-sm leading-7 text-emerald-700">{labels.submitSuccess}</p>
        </div>
        <StatusPill tone="success">{receipt.reportId}</StatusPill>
      </div>
      <div className="mt-4 grid gap-3 md:grid-cols-2">
        <div className="rounded-2xl border border-emerald-200 bg-white px-4 py-3">
          <div className="text-xs text-slate-500">{labels.submissionReference}</div>
          <div className="mt-1 font-bold text-slate-900">{receipt.reportId}</div>
        </div>
        <div className="rounded-2xl border border-emerald-200 bg-white px-4 py-3">
          <div className="text-xs text-slate-500">{labels.submittedAt}</div>
          <div className="mt-1 font-bold text-slate-900">{receipt.submittedAtLabel}</div>
        </div>
      </div>
      <div className="mt-4 flex flex-wrap gap-3 no-print">
        <button
          onClick={async () => {
            try {
              await navigator.clipboard.writeText(receipt.reportId);
            } catch (error) {
              console.error(error);
            }
          }}
          className="rounded-2xl border border-emerald-200 bg-white px-4 py-2 text-sm font-bold text-emerald-800"
        >
          {labels.copyTrackingId}
        </button>
        <button onClick={() => window.print()} className="rounded-2xl bg-emerald-700 px-4 py-2 text-sm font-bold text-white">{labels.printReceipt}</button>
      </div>
    </section>
  );
}

function normalizePhone(value) {
  return String(value || '').replace(/[^0-9+]/g, '');
}

function validateValues(template, values, labels, locale) {
  const errors = {};

  template.fields.forEach((field) => {
    const value = values[field.id];

    if (field.required) {
      if (field.type === 'file' && !value?.name) {
        errors[field.id] = labels.requiredField;
        return;
      }
      if (field.type !== 'file' && !String(value || '').trim()) {
        errors[field.id] = labels.requiredField;
        return;
      }
    }

    if (field.id === 'guardian_phone' && value) {
      const normalized = normalizePhone(value);
      if (normalized.length < 8) errors[field.id] = labels.invalidPhone;
    }

    if (field.id === 'guardian_email' && value) {
      const emailOk = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value));
      if (!emailOk) errors[field.id] = labels.invalidEmail;
    }

    if (field.type === 'file' && value) {
      if (value.size > MAX_FILE_SIZE) errors[field.id] = labels.fileTooLarge;
      if (field.accept && value.name) {
        const accepted = field.accept.split(',').map((item) => item.trim().toLowerCase());
        const lowerName = value.name.toLowerCase();
        const matches = accepted.some((item) => lowerName.endsWith(item.replace('*', '')));
        if (!matches) errors[field.id] = labels.invalidFileType;
      }
    }

    if (field.type === 'signature' && value && String(value).trim().length < 3) {
      errors[field.id] = labels.signatureTooShort;
    }
  });

  return errors;
}

export default function StudentRegistrationShell({ locale, dictionary }) {
  const forms = dictionary.forms;
  const labelMap = forms.studentRegistration;
  const template = useMemo(() => buildTemplateByKey('student_registration'), []);
  const [activeLocale, setActiveLocale] = useState(locale);
  const [values, setValues] = useState(() => makeInitialValues(template));
  const [errors, setErrors] = useState({});
  const [saveState, setSaveState] = useState('idle');
  const [submitState, setSubmitState] = useState('idle');
  const [versions, setVersions] = useState([]);
  const [receipt, setReceipt] = useState(null);
  const meta = localeMeta[activeLocale] || localeMeta.ar;

  useEffect(() => {
    const remembered = window.localStorage.getItem(LOCAL_LANGUAGE_KEY);
    if (remembered && localeMeta[remembered]) setActiveLocale(remembered);

    const raw = window.localStorage.getItem(LOCAL_FORM_STATE_KEY);
    if (raw) {
      try {
        const parsed = JSON.parse(raw);
        if (parsed?.values) setValues(parsed.values);
        if (parsed?.receipt) setReceipt(parsed.receipt);
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
      window.localStorage.setItem(LOCAL_FORM_STATE_KEY, JSON.stringify({ values, receipt }));
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
  }, [values, receipt, template, activeLocale]);

  const fieldsBySection = useMemo(() => {
    return template.sections.map((section) => ({
      ...section,
      fields: template.fields.filter((field) => field.section === section.key)
    }));
  }, [template]);

  const validation = useMemo(() => validateValues(template, values, labelMap, activeLocale), [template, values, labelMap, activeLocale]);
  const requiredFields = useMemo(() => template.fields.filter((field) => field.required), [template]);
  const requiredDone = requiredFields.filter((field) => {
    const value = values[field.id];
    if (field.type === 'file') return !!value?.name;
    return String(value || '').trim().length > 0;
  }).length;

  function persistLocal(nextValues, nextReceipt = receipt) {
    window.localStorage.setItem(LOCAL_FORM_STATE_KEY, JSON.stringify({ values: nextValues, receipt: nextReceipt }));
  }

  function setFieldValue(fieldId, value) {
    setValues((current) => {
      const next = { ...current, [fieldId]: fieldId === 'guardian_phone' ? normalizePhone(value) : value };
      persistLocal(next);
      return next;
    });
    setErrors((current) => ({ ...current, [fieldId]: undefined }));
    if (submitState !== 'idle') setSubmitState('idle');
  }

  function resetForm() {
    const next = makeInitialValues(template);
    setValues(next);
    setErrors({});
    setReceipt(null);
    persistLocal(next, null);
    setSubmitState('idle');
  }

  async function saveNow() {
    setSaveState('saving');
    try {
      await saveDraftRpc({
        form_slug: template.slug,
        locale: activeLocale,
        version_label: nextVersionStamp(),
        visibility: template.visibility,
        schema: template,
        form_values: values,
        autosave: false
      });
      setSaveState('saved');
    } catch (error) {
      console.error(error);
      setSaveState('error');
    }
  }

  async function submitForm() {
    const nextErrors = validateValues(template, values, labelMap, activeLocale);
    setErrors(nextErrors);
    if (Object.keys(nextErrors).length) {
      setSubmitState('validation_error');
      return;
    }

    setSubmitState('submitting');
    const reportId = `SR-${Date.now()}`;
    try {
      const payload = {
        form_slug: template.slug,
        locale: activeLocale,
        visibility: template.visibility,
        submission_ref: reportId,
        schema: template,
        values
      };
      const result = await submitStudentRegistrationRpc(payload);
      if (result?.ok === false) {
        throw new Error(result.error || 'submit_failed');
      }
      const nextReceipt = {
        reportId,
        submittedAt: new Date().toISOString(),
        submittedAtLabel: formatDateForLocale(activeLocale, new Date().toISOString().slice(0, 10)),
        response: result
      };
      setReceipt(nextReceipt);
      persistLocal(values, nextReceipt);
      setSubmitState('submitted');
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
              <StatusPill tone="brand">{meta.label}</StatusPill>
              <StatusPill tone="slate">{localeDateLabel(activeLocale)}</StatusPill>
              <StatusPill tone="slate">{labelMap.visibilityLabel}: {forms.visibility[template.visibility]}</StatusPill>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <LanguageSwitcher locale={activeLocale} onChange={setActiveLocale} labels={forms.languageSwitcher} />
            <Link href={`/${activeLocale}/forms/builder`} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labelMap.openBuilder}</Link>
            <button onClick={() => window.print()} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labelMap.printPreview}</button>
            <button onClick={saveNow} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labelMap.saveNow}</button>
            <button onClick={submitForm} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labelMap.submit}</button>
          </div>
        </div>

        <div className="mt-5 grid gap-4 xl:grid-cols-[minmax(0,1fr)_420px]">
          <section className="space-y-4">
            <div className="rounded-[24px] border border-slate-200 bg-white p-4">
              <div className="grid gap-3 md:grid-cols-4">
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
                  <div className="text-slate-500">{labelMap.statusDraft}</div>
                  <div className="mt-1 font-bold text-slate-900">{saveState === 'saved' ? labelMap.saved : saveState === 'saving' ? labelMap.saving : saveState === 'error' ? labelMap.saveError : labelMap.notSavedYet}</div>
                </div>
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
                  <div className="text-slate-500">{labelMap.requiredCoverage}</div>
                  <div className="mt-1 font-bold text-slate-900">{requiredDone} / {requiredFields.length}</div>
                </div>
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
                  <div className="text-slate-500">{labelMap.versionCount}</div>
                  <div className="mt-1 font-bold text-slate-900">{versions.length}</div>
                </div>
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
                  <div className="text-slate-500">{labelMap.errorCount}</div>
                  <div className="mt-1 font-bold text-slate-900">{Object.values(validation).filter(Boolean).length}</div>
                </div>
              </div>
            </div>

            <SuccessPanel labels={labelMap} receipt={receipt} locale={activeLocale} />

            {fieldsBySection.map((section) => (
              <SectionCard key={section.key} title={section.title[activeLocale]} subtitle={labelMap.sectionHints?.[section.key]}>
                {section.fields.map((field) => (
                  <InputField
                    key={field.id}
                    field={field}
                    locale={activeLocale}
                    value={values[field.id]}
                    error={errors[field.id]}
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
              <button onClick={saveNow} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labelMap.saveNow}</button>
              <button onClick={submitForm} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labelMap.submit}</button>
              {submitState === 'validation_error' ? <span className="self-center text-sm font-bold text-red-600">{labelMap.validationError}</span> : null}
              {submitState === 'submitted' ? <span className="self-center text-sm font-bold text-brand-700">{labelMap.submitSuccess}</span> : null}
              {submitState === 'submit_error' ? <span className="self-center text-sm font-bold text-red-600">{labelMap.submitError}</span> : null}
              {submitState === 'submitting' ? <span className="self-center text-sm font-bold text-slate-700">{labelMap.submitting}</span> : null}
            </div>
          </section>

          <aside className="space-y-4">
            <PreviewCard title={labelMap.guardianPreviewTitle} rows={previewGuardianRows} />
            <PreviewCard title={labelMap.studentPreviewTitle} rows={previewStudentRows} />
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

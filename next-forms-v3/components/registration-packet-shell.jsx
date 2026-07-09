"use client";

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import LanguageSwitcher from '@/components/language-switcher';
import { buildTemplateByKey } from '@/lib/form-templates';
import { formatDateForLocale, localeDateLabel, localeFontClass, localeMeta, localeNumber } from '@/lib/locale-config';
import { nextVersionStamp } from '@/lib/utils';
import {
  listVersionsRpc,
  requestUploadTicketRpc,
  saveDraftRpc,
  submitStudentRegistrationPacketRpc,
  uploadAttachmentTransport
} from '@/lib/rpc/forms-rpc';

const LOCAL_LANGUAGE_KEY = 'amin_forms_v3_locale';
const LOCAL_FORM_STATE_KEY = 'amin_forms_v3_student_registration_packet_state';
const MAX_FILE_SIZE = 10 * 1024 * 1024;
const SIBLING_ROWS = 4;
const PAYMENT_ROWS = 5;

function blankSiblingRows() {
  return Array.from({ length: SIBLING_ROWS }, (_, index) => ({ id: index + 1, name: '', grade: '' }));
}

function blankPaymentRows() {
  return Array.from({ length: PAYMENT_ROWS }, (_, index) => ({
    id: index + 1,
    cardNumber: '',
    trackingNumber: '',
    reference: '',
    paymentDate: '',
    amount: '',
    notes: ''
  }));
}

function makeInitialValues(template) {
  const base = template.fields.reduce((acc, field) => {
    if (field.type === 'file') {
      acc[field.id] = null;
    } else if (field.type === 'checkbox') {
      acc[field.id] = false;
    } else {
      acc[field.id] = '';
    }
    return acc;
  }, {});

  return {
    ...base,
    sibling_entries: blankSiblingRows(),
    finance_entries: blankPaymentRows()
  };
}

function normalizePhone(value) {
  return String(value || '').replace(/[^0-9+]/g, '');
}

function getOptionLabel(field, locale, value) {
  return (field?.options || []).find((option) => option.value === value)?.label?.[locale] || '';
}

function parseAmount(value) {
  const parsed = Number(String(value || '').replace(/,/g, '').trim());
  return Number.isFinite(parsed) ? parsed : 0;
}

function totalPayments(rows) {
  return rows.reduce((sum, row) => sum + parseAmount(row.amount), 0);
}

function countPopulatedPayments(rows) {
  return rows.filter((row) => Object.values(row).some((value, index) => index !== 0 && String(value || '').trim())).length;
}

function SectionCard({ title, subtitle, children }) {
  return (
    <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
      <div className="mb-4 border-b border-slate-100 pb-3">
        <h2 className="text-xl font-black text-slate-950">{title}</h2>
        {subtitle ? <p className="mt-1 text-sm leading-7 text-slate-500">{subtitle}</p> : null}
      </div>
      {children}
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

  if (field.type === 'checkbox') {
    return (
      <label className={`flex items-center gap-3 rounded-2xl border px-4 py-3 ${error ? 'border-rose-300 bg-rose-50' : 'border-slate-200 bg-slate-50'} ${wrapperClass}`}>
        <input type="checkbox" checked={Boolean(value)} onChange={(event) => onChange(field.id, event.target.checked)} className="h-4 w-4 accent-[var(--brand-600)]" />
        <span className="text-sm font-bold text-slate-800">{label}</span>
        {error ? <small className="ms-auto text-xs font-bold text-rose-600">{error}</small> : null}
      </label>
    );
  }

  if (field.type === 'textarea') {
    return (
      <label className={`block ${wrapperClass}`}>
        <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
        <textarea value={value || ''} onChange={(event) => onChange(field.id, event.target.value)} className={`${baseInputClass} min-h-[120px]`} placeholder={placeholder} />
        {metaBlock}
      </label>
    );
  }

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
            onChange(field.id, file ? { rawFile: file } : null);
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

  const inputType = field.id.includes('phone') ? 'tel' : field.type === 'number' ? 'number' : 'text';

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

function UploadStatusPanel({ labels, uploadTicket, uploadedAttachment, uploadState }) {
  const tone = uploadState === 'uploaded' ? 'success' : uploadState === 'uploading' ? 'warning' : uploadState === 'ready' ? 'brand' : uploadState === 'error' ? 'danger' : 'slate';
  const statusText = uploadState === 'uploaded'
    ? labels.uploadDone
    : uploadState === 'uploading'
      ? labels.uploadingFile
      : uploadState === 'ready'
        ? labels.uploadPrepared
        : uploadState === 'error'
          ? labels.uploadTicketError
          : labels.uploadTicketPending;

  return (
    <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
      <div className="mb-3 flex items-center justify-between gap-3">
        <h3 className="text-lg font-black text-slate-950">{labels.uploadTicketTitle}</h3>
        <StatusPill tone={tone}>{statusText}</StatusPill>
      </div>
      <div className="space-y-3 text-sm text-slate-700">
        <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
          <div className="text-xs text-slate-500">{labels.uploadTicketId}</div>
          <div className="mt-1 font-bold text-slate-900">{uploadTicket?.ticketId || '—'}</div>
        </div>
        <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
          <div className="text-xs text-slate-500">{labels.uploadTicketExpiry}</div>
          <div className="mt-1 font-bold text-slate-900">{uploadTicket?.expiresAtLabel || '—'}</div>
        </div>
        <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
          <div className="text-xs text-slate-500">{labels.uploadObjectPath}</div>
          <div className="mt-1 break-all font-bold text-slate-900">{uploadedAttachment?.object_path || '—'}</div>
        </div>
      </div>
      <p className="mt-3 text-sm leading-7 text-slate-500">{labels.uploadGuide}</p>
    </section>
  );
}

function FinanceBands({ labels }) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
      <h4 className="mb-3 text-base font-black text-slate-900">{labels.paymentTableTitle}</h4>
      <div className="space-y-2 text-sm text-slate-700">
        {labels.feeBands.map((band) => (
          <div key={`${band.label}-${band.amount}`} className="flex items-center justify-between gap-4 rounded-xl border border-slate-200 bg-white px-3 py-2">
            <span>{band.label}</span>
            <span className="font-black text-slate-900">{band.amount}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function SiblingsEditor({ locale, labels, rows, onChange }) {
  return (
    <div className="mt-5 rounded-2xl border border-slate-200 bg-slate-50 p-4">
      <div className="mb-3 text-sm font-black text-slate-900">{labels.siblingsTitle}</div>
      <div className="grid gap-3 md:grid-cols-2">
        {rows.map((row, index) => (
          <div key={row.id} className="rounded-2xl border border-slate-200 bg-white p-3">
            <div className="mb-2 text-xs font-bold text-slate-500">{localeNumber(locale, index + 1)}</div>
            <div className="grid gap-2 md:grid-cols-[minmax(0,1fr)_140px]">
              <input
                value={row.name}
                onChange={(event) => onChange(index, 'name', event.target.value)}
                className="w-full rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-sm"
                placeholder={labels.siblingNamePlaceholder}
              />
              <input
                value={row.grade}
                onChange={(event) => onChange(index, 'grade', event.target.value)}
                className="w-full rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-sm"
                placeholder={labels.siblingGradePlaceholder}
              />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function PaymentsEditor({ locale, labels, rows, onChange, totalAmount }) {
  return (
    <div className="mt-5 rounded-2xl border border-slate-200 bg-slate-50 p-4">
      <div className="mb-3 text-sm font-black text-slate-900">{labels.paymentTableTitle}</div>
      <div className="overflow-x-auto">
        <table className="min-w-full border-collapse text-sm">
          <thead>
            <tr className="bg-white text-slate-700">
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.row}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.cardNumber}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.trackingNumber}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.reference}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.date}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.amount}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.notes}</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row, index) => (
              <tr key={row.id} className="bg-white">
                <td className="border border-slate-200 px-2 py-2 text-center font-bold">{localeNumber(locale, index + 1)}</td>
                <td className="border border-slate-200 px-2 py-2"><input value={row.cardNumber} onChange={(event) => onChange(index, 'cardNumber', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                <td className="border border-slate-200 px-2 py-2"><input value={row.trackingNumber} onChange={(event) => onChange(index, 'trackingNumber', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                <td className="border border-slate-200 px-2 py-2"><input value={row.reference} onChange={(event) => onChange(index, 'reference', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                <td className="border border-slate-200 px-2 py-2"><input type="date" value={row.paymentDate} onChange={(event) => onChange(index, 'paymentDate', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                <td className="border border-slate-200 px-2 py-2"><input type="number" value={row.amount} onChange={(event) => onChange(index, 'amount', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                <td className="border border-slate-200 px-2 py-2"><input value={row.notes} onChange={(event) => onChange(index, 'notes', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="bg-brand-50">
              <td className="border border-slate-200 px-2 py-2 text-center font-black" colSpan={5}>{labels.paymentTotal}</td>
              <td className="border border-slate-200 px-2 py-2 font-black text-slate-900">{localeNumber(locale, totalAmount)}</td>
              <td className="border border-slate-200 px-2 py-2" />
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  );
}

function validateValues(template, values, labels, options = {}) {
  const errors = {};
  const requirePreparedUpload = options.requirePreparedUpload;

  template.fields.forEach((field) => {
    const value = values[field.id];

    if (field.required) {
      if (field.type === 'file' && !value?.name) {
        errors[field.id] = labels.requiredField;
        return;
      }
      if (field.type === 'checkbox' && !value) {
        errors[field.id] = field.id === 'accept_terms' ? labels.mustAcceptTerms : labels.requiredField;
        return;
      }
      if (field.type !== 'file' && field.type !== 'checkbox' && !String(value || '').trim()) {
        errors[field.id] = labels.requiredField;
        return;
      }
    }

    if (field.id.includes('phone') && value) {
      const normalized = normalizePhone(value);
      if (normalized.length < 8) errors[field.id] = labels.invalidPhone;
    }

    if (field.type === 'file' && value) {
      if (value.size > MAX_FILE_SIZE) errors[field.id] = labels.fileTooLarge;
      if (field.accept && value.name) {
        const accepted = field.accept.split(',').map((item) => item.trim().toLowerCase());
        const lowerName = value.name.toLowerCase();
        const matches = accepted.some((item) => lowerName.endsWith(item.replace('*', '')));
        if (!matches) errors[field.id] = labels.invalidFileType;
      }
      if (requirePreparedUpload && field.id === 'health_attachment') {
        errors[field.id] = labels.uploadTicketRequired;
      }
    }

    if (field.type === 'signature' && value && String(value).trim().length < 3) {
      errors[field.id] = labels.signatureTooShort;
    }
  });

  return errors;
}

function CheckMark({ checked }) {
  return <span className="inline-flex h-5 w-5 items-center justify-center rounded border border-black text-[11px]">{checked ? '✓' : ''}</span>;
}

function PrintField({ label, value, wide = false }) {
  return (
    <div className={`border border-black p-2 ${wide ? 'md:col-span-2' : ''}`}>
      <div className="text-[11px] font-bold">{label}</div>
      <div className="mt-1 min-h-[22px] text-[12px] font-semibold">{value || ' '}</div>
    </div>
  );
}

function PrintableRegistrationPacket({ locale, labels, template, values, totalAmount }) {
  const registrationForField = template.fields.find((field) => field.id === 'registration_for');

  return (
    <div className="space-y-6 text-black">
      <section className="mx-auto w-full max-w-[794px] border-2 border-black bg-white p-4 shadow-sm">
        <div className="grid grid-cols-[180px_minmax(0,1fr)_120px] items-start gap-4">
          <div className="flex h-[88px] items-center justify-center border-2 border-dashed border-black text-center text-sm font-bold">
            {labels.photoPlaceholder}
          </div>
          <div className="text-center">
            <div className="text-[18px] font-black">{labels.schoolName}</div>
            <div className="mt-2 text-[17px] font-black">{labels.printFormTitle || labels.pageTitle}</div>
            <div className="mt-1 text-[18px] font-black">{labels.schoolYear}</div>
          </div>
          <div className="text-center text-[12px] font-black leading-6">
            <div>{labels.schoolName}</div>
          </div>
        </div>

        <div className="mt-4 border border-black p-3 text-[13px] leading-7">
          <span className="font-black">{labels.statementPrefix}:</span> {values.guardian_full_name || '................'}
          {' '}{labels.statementMiddle}{' '}{getOptionLabel(registrationForField, locale, values.registration_for) || '...............'}{' '}{labels.statementSuffix}{' '}{values.target_grade || '...............'}.
        </div>

        <div className="mt-4 grid gap-0 md:grid-cols-2">
          <PrintField label={labels.fields.registration_date} value={values.registration_date ? formatDateForLocale(locale, values.registration_date) : ''} />
          <PrintField label={labels.fields.guardian_full_name} value={values.guardian_full_name} />
          <PrintField label={labels.fields.student_full_name} value={values.student_full_name} />
          <PrintField label={labels.fields.student_passport_number} value={values.student_passport_number} />
          <PrintField label={labels.fields.student_birth_date} value={values.student_birth_date ? formatDateForLocale(locale, values.student_birth_date) : ''} />
          <PrintField label={labels.fields.student_online_study_phone} value={values.student_online_study_phone} />
          <PrintField label={labels.fields.previous_school} value={values.previous_school} />
          <PrintField label={labels.fields.target_grade} value={values.target_grade} />
          <PrintField label={labels.fields.student_address_mashhad} value={values.student_address_mashhad} wide />
          <PrintField label={labels.fields.student_address_iraq} value={values.student_address_iraq} wide />
        </div>

        <div className="mt-4 grid gap-0 md:grid-cols-2">
          <PrintField label={labels.fields.father_full_name} value={values.father_full_name} />
          <PrintField label={labels.fields.father_guardian_phone} value={values.father_guardian_phone} />
          <PrintField label={labels.fields.father_education} value={values.father_education} />
          <PrintField label={labels.fields.father_job_address} value={values.father_job_address} wide />
        </div>

        <div className="mt-4 grid gap-0 md:grid-cols-2">
          <PrintField label={labels.fields.mother_full_name} value={values.mother_full_name} />
          <PrintField label={labels.fields.mother_phone} value={values.mother_phone} />
          <PrintField label={labels.fields.mother_education} value={values.mother_education} />
          <PrintField label={labels.fields.mother_job_address} value={values.mother_job_address} wide />
        </div>

        <div className="mt-4 grid gap-4 md:grid-cols-[280px_minmax(0,1fr)]">
          <div className="rounded-[24px] border-2 border-black p-4 text-center text-[13px] font-black">
            <div>{labels.termsGuardianSignature}:</div>
            <div className="mt-10 min-h-[80px]">{values.parent_signature || ' '}</div>
          </div>
          <div className="border border-black p-3">
            <div className="mb-2 text-[13px] font-black">{labels.paymentTableTitle}</div>
            <div className="space-y-2 text-[12px] leading-6">
              {labels.feeBands.map((band) => (
                <div key={`${band.label}-${band.amount}`} className="flex items-center justify-between gap-4 border-b border-dashed border-black pb-1">
                  <span>{band.label}</span>
                  <span className="font-black">{band.amount}</span>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="mt-4 border border-black p-3 text-[12px] leading-6">
          <div className="font-black">{labels.medicalWarning}</div>
          <div className="mt-2">{labels.fields.medical_condition_notes}: {values.medical_condition_notes || '........................................'}</div>
          <div className="mt-2">{labels.fields.living_with_in_iran}: {values.living_with_in_iran || '........................................'}</div>
          <div className="mt-2">{labels.fields.student_status}: {values.student_status || '........................................'}</div>
        </div>

        <div className="mt-4 border border-black p-3 text-[12px]">
          <div className="mb-2 font-black">{labels.siblingsTitle}</div>
          <div className="grid gap-2 md:grid-cols-2">
            {values.sibling_entries.map((row, index) => (
              <div key={row.id} className="border border-black p-2">
                {localeNumber(locale, index + 1)} / {row.name || '................'} — {row.grade || '................'}
              </div>
            ))}
          </div>
        </div>

        <div className="mt-4 overflow-hidden border border-black">
          <table className="min-w-full border-collapse text-[11px]">
            <thead>
              <tr>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.row}</th>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.cardNumber}</th>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.trackingNumber}</th>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.reference}</th>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.date}</th>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.amount}</th>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.notes}</th>
              </tr>
            </thead>
            <tbody>
              {values.finance_entries.map((row, index) => (
                <tr key={row.id}>
                  <td className="border border-black px-1 py-2 text-center">{localeNumber(locale, index + 1)}</td>
                  <td className="border border-black px-1 py-2">{row.cardNumber || ' '}</td>
                  <td className="border border-black px-1 py-2">{row.trackingNumber || ' '}</td>
                  <td className="border border-black px-1 py-2">{row.reference || ' '}</td>
                  <td className="border border-black px-1 py-2">{row.paymentDate ? formatDateForLocale(locale, row.paymentDate) : ' '}</td>
                  <td className="border border-black px-1 py-2">{row.amount ? localeNumber(locale, parseAmount(row.amount)) : ' '}</td>
                  <td className="border border-black px-1 py-2">{row.notes || ' '}</td>
                </tr>
              ))}
              <tr>
                <td className="border border-black px-1 py-2 text-center font-black" colSpan={5}>{labels.paymentTotal}</td>
                <td className="border border-black px-1 py-2 font-black">{localeNumber(locale, totalAmount)}</td>
                <td className="border border-black px-1 py-2" />
              </tr>
            </tbody>
          </table>
        </div>

        <div className="mt-4 border border-black p-3 text-[12px]">
          <div className="mb-2 font-black">{labels.documentStatusTitle}</div>
          <div className="flex flex-wrap items-center gap-6">
            <div className="flex items-center gap-2"><CheckMark checked={values.document_copy_received} /> <span>{labels.copyReceived}</span></div>
            <div className="flex items-center gap-2"><CheckMark checked={values.document_original_received} /> <span>{labels.originalReceived}</span></div>
          </div>
          <div className="mt-3">{labels.documentNotesLabel}: {values.document_notes || '.................................................................'}</div>
        </div>

        <div className="mt-6 grid gap-4 text-center text-[12px] font-black md:grid-cols-3">
          <div>
            <div>{labels.adminFooter.registeredBy}</div>
            <div className="mt-2 min-h-[26px] border-b border-black">{values.registered_by || ' '}</div>
            <div className="mt-3">{labels.adminFooter.registrationOfficer}</div>
            <div className="mt-2 min-h-[28px] border-b border-black">{values.registration_officer_signature || ' '}</div>
          </div>
          <div>
            <div>{labels.adminFooter.registeredOn}</div>
            <div className="mt-2 min-h-[26px] border-b border-black">{values.registered_on ? formatDateForLocale(locale, values.registered_on) : ' '}</div>
            <div className="mt-3">{labels.adminFooter.financeOfficer}</div>
            <div className="mt-2 min-h-[28px] border-b border-black">{values.finance_officer_signature || ' '}</div>
          </div>
          <div>
            <div>{labels.adminFooter.director}</div>
            <div className="mt-10 min-h-[28px] border-b border-black">{values.director_signature || ' '}</div>
          </div>
        </div>
      </section>

      <section className="mx-auto w-full max-w-[794px] border-2 border-black bg-white p-6 shadow-sm">
        <div className="text-center">
          <div className="text-[18px] font-black">{labels.schoolName}</div>
          <div className="mt-4 text-[17px] font-black underline">{labels.termsTitle}</div>
          <div className="mt-4 text-[14px] font-black">{labels.termsSubtitle}</div>
        </div>

        <ol className="mt-6 space-y-4 text-[13px] leading-7">
          {labels.termsItems.map((item, index) => (
            <li key={`${index}-${item}`} className="flex gap-2">
              <span className="font-black">{localeNumber(locale, index + 1)}.</span>
              <span>{item}</span>
            </li>
          ))}
        </ol>

        <div className="mt-8 grid gap-4 text-[13px] font-black md:grid-cols-2">
          <div>
            <div>{labels.termsGuardianSignature}</div>
            <div className="mt-3 min-h-[28px] border-b border-black">{values.parent_signature || ' '}</div>
          </div>
          <div>
            <div>{labels.termsGuardianPhone}</div>
            <div className="mt-3 min-h-[28px] border-b border-black">{values.terms_guardian_phone || values.father_guardian_phone || ' '}</div>
          </div>
        </div>
      </section>
    </div>
  );
}

export default function RegistrationPacketShell({ locale, dictionary }) {
  const router = useRouter();
  const forms = dictionary.forms;
  const labelMap = forms.registrationPacket;
  const template = useMemo(() => buildTemplateByKey('student_registration_packet'), []);

  const [activeLocale, setActiveLocale] = useState(locale);
  const [values, setValues] = useState(() => makeInitialValues(template));
  const [errors, setErrors] = useState({});
  const [saveState, setSaveState] = useState('idle');
  const [submitState, setSubmitState] = useState('idle');
  const [versions, setVersions] = useState([]);
  const [receipt, setReceipt] = useState(null);
  const [uploadTicket, setUploadTicket] = useState(null);
  const [uploadedAttachment, setUploadedAttachment] = useState(null);
  const [uploadState, setUploadState] = useState('idle');
  const [fileObjects, setFileObjects] = useState({});

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
        if (parsed?.uploadTicket) setUploadTicket(parsed.uploadTicket);
        if (parsed?.uploadedAttachment) setUploadedAttachment(parsed.uploadedAttachment);
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
        setVersions(result?.data?.versions || result?.versions || []);
      } catch (error) {
        console.error(error);
      }
    }

    loadVersions();
    return () => {
      cancelled = true;
    };
  }, [template.slug]);

  useEffect(() => {
    const timer = setInterval(async () => {
      persistLocal(values, receipt, uploadTicket, uploadedAttachment);
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
  }, [values, receipt, uploadTicket, uploadedAttachment, template, activeLocale]);

  const fieldsBySection = useMemo(() => {
    return template.sections.map((section) => ({
      ...section,
      fields: template.fields.filter((field) => field.section === section.key)
    }));
  }, [template]);

  const requiredFields = useMemo(() => template.fields.filter((field) => field.required), [template]);
  const requiredDone = requiredFields.filter((field) => {
    const value = values[field.id];
    if (field.type === 'file') return !!value?.name;
    if (field.type === 'checkbox') return Boolean(value);
    return String(value || '').trim().length > 0;
  }).length;

  const totalAmount = useMemo(() => totalPayments(values.finance_entries || []), [values.finance_entries]);
  const populatedPayments = useMemo(() => countPopulatedPayments(values.finance_entries || []), [values.finance_entries]);
  const validation = useMemo(
    () => validateValues(template, values, labelMap, { requirePreparedUpload: Boolean(values.health_attachment?.name && !uploadTicket) }),
    [template, values, labelMap, uploadTicket]
  );

  function persistLocal(nextValues, nextReceipt = receipt, nextUploadTicket = uploadTicket, nextAttachment = uploadedAttachment) {
    window.localStorage.setItem(LOCAL_FORM_STATE_KEY, JSON.stringify({
      values: nextValues,
      receipt: nextReceipt,
      uploadTicket: nextUploadTicket,
      uploadedAttachment: nextAttachment
    }));
  }

  function setFieldValue(fieldId, value) {
    let normalizedValue = value;

    if (fieldId.includes('phone') && typeof value === 'string') {
      normalizedValue = normalizePhone(value);
    }

    if (fieldId === 'health_attachment') {
      setFileObjects((current) => ({ ...current, health_attachment: value?.rawFile || null }));
      normalizedValue = value?.rawFile ? {
        name: value.rawFile.name,
        size: value.rawFile.size,
        type: value.rawFile.type,
        lastModified: value.rawFile.lastModified
      } : null;
      setUploadTicket(null);
      setUploadedAttachment(null);
      setUploadState('idle');
    }

    setValues((current) => {
      const next = { ...current, [fieldId]: normalizedValue };
      persistLocal(next, receipt, fieldId === 'health_attachment' ? null : uploadTicket, fieldId === 'health_attachment' ? null : uploadedAttachment);
      return next;
    });

    setErrors((current) => ({ ...current, [fieldId]: undefined }));
    if (submitState !== 'idle') setSubmitState('idle');
  }

  function setSiblingValue(index, key, value) {
    setValues((current) => {
      const nextRows = current.sibling_entries.map((row, rowIndex) => rowIndex === index ? { ...row, [key]: value } : row);
      const next = { ...current, sibling_entries: nextRows };
      persistLocal(next);
      return next;
    });
  }

  function setPaymentValue(index, key, value) {
    setValues((current) => {
      const nextRows = current.finance_entries.map((row, rowIndex) => rowIndex === index ? { ...row, [key]: value } : row);
      const next = { ...current, finance_entries: nextRows };
      persistLocal(next);
      return next;
    });
  }

  function resetForm() {
    const next = makeInitialValues(template);
    setValues(next);
    setErrors({});
    setReceipt(null);
    setUploadTicket(null);
    setUploadedAttachment(null);
    setFileObjects({});
    setUploadState('idle');
    persistLocal(next, null, null, null);
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
      persistLocal(values);
      setSaveState('saved');
    } catch (error) {
      console.error(error);
      setSaveState('error');
    }
  }

  async function prepareUploadTicket() {
    if (!values.health_attachment?.name) {
      setErrors((current) => ({ ...current, health_attachment: labelMap.requiredField }));
      return;
    }

    setUploadState('loading');
    try {
      const result = await requestUploadTicketRpc({
        form_slug: template.slug,
        locale: activeLocale,
        field_id: 'health_attachment',
        file_name: values.health_attachment.name,
        content_type: values.health_attachment.type || 'application/octet-stream',
        byte_size: values.health_attachment.size || 0
      });
      if (result?.ok === false) throw new Error(result.error || 'upload_ticket_failed');

      const ticketPayload = result?.data || result;
      const nextTicket = {
        ...ticketPayload,
        ticketId: ticketPayload?.ticket_id || ticketPayload?.upload_token || `UP-${Date.now()}`,
        expiresAtLabel: ticketPayload?.expires_at ? formatDateForLocale(activeLocale, String(ticketPayload.expires_at).slice(0, 10)) : labelMap.uploadTicketPending
      };

      setUploadTicket(nextTicket);
      persistLocal(values, receipt, nextTicket, uploadedAttachment);
      setUploadState('ready');
      setErrors((current) => ({ ...current, health_attachment: undefined }));
    } catch (error) {
      console.error(error);
      setUploadState('error');
      setErrors((current) => ({ ...current, health_attachment: labelMap.uploadTicketError }));
    }
  }

  async function submitForm() {
    const needUploadTicket = Boolean(values.health_attachment?.name && !uploadTicket);
    const nextErrors = validateValues(template, values, labelMap, { requirePreparedUpload: needUploadTicket });
    setErrors(nextErrors);
    if (Object.keys(nextErrors).length) {
      setSubmitState('validation_error');
      return;
    }

    setSubmitState('submitting');
    const reportId = `SRP-${Date.now()}`;

    try {
      let attachmentPayload = uploadedAttachment;

      if (values.health_attachment?.name) {
        if (!uploadTicket?.ticketId) {
          setErrors((current) => ({ ...current, health_attachment: labelMap.uploadTicketRequired }));
          setSubmitState('validation_error');
          return;
        }

        if (!attachmentPayload) {
          const rawFile = fileObjects.health_attachment;
          if (!rawFile) {
            setErrors((current) => ({ ...current, health_attachment: labelMap.fileNeedsReselect }));
            setSubmitState('validation_error');
            return;
          }

          setUploadState('uploading');
          const uploadResult = await uploadAttachmentTransport({
            ticketId: uploadTicket.ticketId,
            formSlug: template.slug,
            fieldId: 'health_attachment',
            file: rawFile
          });
          if (uploadResult?.ok === false) throw new Error(uploadResult.error || 'upload_failed');
          attachmentPayload = uploadResult;
          setUploadedAttachment(uploadResult);
          setUploadState('uploaded');
        }
      }

      const payload = {
        form_slug: template.slug,
        locale: activeLocale,
        visibility: template.visibility,
        submission_ref: reportId,
        schema: template,
        values,
        upload_ticket_id: uploadTicket?.ticketId || null,
        uploaded_attachment: attachmentPayload ? {
          bucket: attachmentPayload.bucket,
          object_path: attachmentPayload.object_path,
          file_name: attachmentPayload.file_name,
          byte_size: attachmentPayload.byte_size
        } : null
      };

      const result = await submitStudentRegistrationPacketRpc(payload);
      if (result?.ok === false) throw new Error(result.error || 'submit_failed');

      const submittedAtIso = new Date().toISOString();
      const nextReceipt = {
        reportId,
        submittedAt: submittedAtIso,
        submittedAtLabel: formatDateForLocale(activeLocale, submittedAtIso.slice(0, 10)),
        response: result
      };

      setReceipt(nextReceipt);
      persistLocal(values, nextReceipt, uploadTicket, attachmentPayload || uploadedAttachment);
      setSubmitState('submitted');

      const params = new URLSearchParams({
        ref: reportId,
        submittedAt: submittedAtIso,
        applicant: values.student_full_name || ''
      });
      router.push(`/${activeLocale}/forms/student-registration-packet/success?${params.toString()}`);
    } catch (error) {
      console.error(error);
      setSubmitState('submit_error');
      setUploadState((current) => (current === 'uploading' ? 'error' : current));
    }
  }

  const studentPreviewRows = [
    { label: labelMap.fields.student_full_name, value: values.student_full_name },
    { label: labelMap.fields.target_grade, value: values.target_grade },
    { label: labelMap.fields.student_birth_date, value: values.student_birth_date ? formatDateForLocale(activeLocale, values.student_birth_date) : '' },
    { label: labelMap.fields.previous_school, value: values.previous_school }
  ];

  const familyPreviewRows = [
    { label: labelMap.fields.guardian_full_name, value: values.guardian_full_name },
    { label: labelMap.fields.father_guardian_phone, value: values.father_guardian_phone },
    { label: labelMap.fields.living_with_in_iran, value: values.living_with_in_iran },
    { label: labelMap.fields.student_status, value: values.student_status }
  ];

  return (
    <main className={`mx-auto min-h-screen max-w-[1500px] px-4 py-6 ${localeFontClass(activeLocale)}`} dir={meta.dir}>
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

        <div className="mt-5 grid gap-4 xl:grid-cols-[minmax(0,1fr)_430px]">
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

            {fieldsBySection.map((section) => (
              <SectionCard key={section.key} title={section.title[activeLocale]} subtitle={labelMap.sectionHints?.[section.key]}>
                <div className="grid gap-4 md:grid-cols-2">
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
                </div>

                {section.key === 'family' ? <SiblingsEditor locale={activeLocale} labels={labelMap} rows={values.sibling_entries} onChange={setSiblingValue} /> : null}
                {section.key === 'finance' ? (
                  <>
                    <div className="mt-5">
                      <FinanceBands labels={labelMap} />
                    </div>
                    <PaymentsEditor locale={activeLocale} labels={labelMap} rows={values.finance_entries} onChange={setPaymentValue} totalAmount={totalAmount} />
                  </>
                ) : null}
                {section.key === 'undertaking' ? (
                  <div className="mt-5 rounded-2xl border border-slate-200 bg-slate-50 p-4">
                    <h3 className="text-base font-black text-slate-900">{labelMap.termsTitle}</h3>
                    <p className="mt-2 text-sm leading-7 text-slate-600">{labelMap.termsSubtitle}</p>
                    <ol className="mt-4 space-y-3 text-sm leading-7 text-slate-700">
                      {labelMap.termsItems.map((item, index) => (
                        <li key={`${index}-${item}`} className="flex gap-2">
                          <span className="font-black text-slate-900">{localeNumber(activeLocale, index + 1)}.</span>
                          <span>{item}</span>
                        </li>
                      ))}
                    </ol>
                  </div>
                ) : null}
              </SectionCard>
            ))}

            <div className="no-print flex flex-wrap gap-3 rounded-[24px] border border-slate-200 bg-white p-4 shadow-soft">
              <button onClick={resetForm} className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-2 font-bold text-amber-800">{labelMap.reset}</button>
              <button onClick={prepareUploadTicket} className="rounded-2xl border border-brand-200 bg-brand-50 px-4 py-2 font-bold text-brand-800">{labelMap.prepareUpload}</button>
              <button onClick={saveNow} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labelMap.saveNow}</button>
              <button onClick={submitForm} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labelMap.submit}</button>
              {submitState === 'validation_error' ? <span className="self-center text-sm font-bold text-red-600">{labelMap.validationError}</span> : null}
              {submitState === 'submitted' ? <span className="self-center text-sm font-bold text-brand-700">{labelMap.submitSuccess}</span> : null}
              {submitState === 'submit_error' ? <span className="self-center text-sm font-bold text-red-600">{labelMap.submitError}</span> : null}
              {submitState === 'submitting' ? <span className="self-center text-sm font-bold text-slate-700">{labelMap.submitting}</span> : null}
              {uploadState === 'uploading' ? <span className="self-center text-sm font-bold text-brand-700">{labelMap.uploadingFile}</span> : null}
            </div>
          </section>

          <aside className="space-y-4 no-print">
            <UploadStatusPanel labels={labelMap} uploadTicket={uploadTicket} uploadedAttachment={uploadedAttachment} uploadState={uploadState} />
            <PreviewCard title={labelMap.overviewStudentTitle} rows={studentPreviewRows} />
            <PreviewCard title={labelMap.overviewFamilyTitle} rows={familyPreviewRows} />
            <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
              <h3 className="mb-3 text-lg font-black text-slate-950">{labelMap.financeSummaryTitle}</h3>
              <div className="grid gap-3 md:grid-cols-2">
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
                  <div className="text-xs text-slate-500">{labelMap.paymentTotal}</div>
                  <div className="mt-1 font-black text-slate-900">{localeNumber(activeLocale, totalAmount)}</div>
                </div>
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
                  <div className="text-xs text-slate-500">{labelMap.paymentTableTitle}</div>
                  <div className="mt-1 font-black text-slate-900">{localeNumber(activeLocale, populatedPayments)}</div>
                </div>
              </div>
              <div className="mt-4">
                <FinanceBands labels={labelMap} />
              </div>
            </section>
            <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
              <h3 className="mb-3 text-lg font-black text-slate-950">{labelMap.printPreviewTitle}</h3>
              <div className="mb-3 text-xs text-slate-500">{labelMap.printSheetHint}</div>
              <div className="rounded-2xl border border-slate-100 bg-slate-50 p-3">
                <div className="mb-3 flex items-center justify-between gap-3 text-xs text-slate-500">
                  <span>{labelMap.printPaperLabel}</span>
                  <StatusPill tone="slate">{forms.builder.printModes.portrait}</StatusPill>
                </div>
                <div className="max-h-[780px] overflow-auto">
                  <div className="origin-top scale-[0.55]">
                    <PrintableRegistrationPacket locale={activeLocale} labels={labelMap} template={template} values={values} totalAmount={totalAmount} />
                  </div>
                </div>
              </div>
            </section>
            <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
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

      <section className="print-only py-6">
        <PrintableRegistrationPacket locale={activeLocale} labels={labelMap} template={template} values={values} totalAmount={totalAmount} />
        <div className="mx-auto mt-4 w-full max-w-[794px] rounded-2xl border border-brand-100 bg-brand-50 px-4 py-3 text-sm text-brand-800">{labelMap.printReceiptBanner}</div>
      </section>
    </main>
  );
}

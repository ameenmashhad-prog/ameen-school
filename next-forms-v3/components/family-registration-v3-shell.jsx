"use client";

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import LanguageSwitcher from '@/components/language-switcher';
import { buildTemplateByKey } from '@/lib/form-templates';
import { formatDateForLocale, localeDateLabel, localeFontClass, localeMeta, localeNumber } from '@/lib/locale-config';
import { generateId, nextVersionStamp } from '@/lib/utils';
import {
  listVersionsRpc,
  requestUploadTicketRpc,
  saveDraftRpc,
  submitFamilyRegistrationV3Rpc,
  uploadAttachmentTransport
} from '@/lib/rpc/forms-rpc';

const LOCAL_LANGUAGE_KEY = 'amin_forms_v3_locale';
const LOCAL_FORM_STATE_KEY = 'amin_forms_v3_family_registration_v3_state';
const MAX_FILE_SIZE = 10 * 1024 * 1024;
const PAYMENT_ROWS = 5;

function blankPaymentRows() {
  return Array.from({ length: PAYMENT_ROWS }, (_, index) => ({
    id: generateId(`payment_${index + 1}`),
    student_ref: '',
    card_number: '',
    tracking_number: '',
    reference: '',
    payment_date: '',
    amount: '',
    notes: ''
  }));
}

function fieldMapFromTemplate(template) {
  const map = new Map();
  template.fields.forEach((field) => map.set(field.id, field));
  (template.studentCardFields || []).forEach((field) => map.set(field.id, field));
  return map;
}

function computeGuardianFullName(values) {
  return [values.guardian_given_name, values.guardian_father_name, values.family_name].map((part) => String(part || '').trim()).filter(Boolean).join(' ');
}

function computeMotherFullName(values) {
  return [values.mother_given_name, values.mother_father_name, values.mother_family_name].map((part) => String(part || '').trim()).filter(Boolean).join(' ');
}

function computeStudentFullName(student) {
  return [student.student_given_name, student.student_father_name, student.student_family_name].map((part) => String(part || '').trim()).filter(Boolean).join(' ');
}

function normalizePhone(value) {
  return String(value || '').replace(/[^0-9+]/g, '');
}

function birthDatePasswordFromISO(iso) {
  if (!iso || typeof iso !== 'string') return '';
  const parts = iso.split('-');
  if (parts.length !== 3) return '';
  return `${parts[2]}${parts[1]}${parts[0]}`;
}

function latinize(raw) {
  let text = String(raw || '').trim().toLowerCase();
  const replacements = [
    [/محمد|محمّد|mohammad|mohammed|muhammad|mohamad/g, 'mhd'],
    [/عبد/g, 'abd'],
    [/علي|ali/g, 'ali'],
    [/حسين|hussain|hussein/g, 'hussain'],
    [/حسن|hasan|hassan/g, 'hasan'],
    [/فاطمة|fatima/g, 'fatima'],
    [/زهراء|zahra/g, 'zahra']
  ];

  replacements.forEach(([pattern, value]) => {
    text = text.replace(pattern, value);
  });

  const map = {
    ا: 'a', أ: 'a', إ: 'i', آ: 'a', ب: 'b', ت: 't', ث: 'th', ج: 'j', ح: 'h', خ: 'kh', د: 'd', ذ: 'th', ر: 'r', ز: 'z',
    س: 's', ش: 'sh', ص: 's', ض: 'd', ط: 't', ظ: 'z', ع: 'a', غ: 'gh', ف: 'f', ق: 'q', ك: 'k', ل: 'l', م: 'm',
    ن: 'n', ه: 'h', ة: 'h', و: 'w', ي: 'y', ى: 'a', ء: '', ئ: 'y', ؤ: 'w'
  };

  text = text.replace(/[\u0600-\u06FF]/g, (character) => map[character] || '');
  return text
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '.')
    .replace(/^\.+|\.+$/g, '')
    .replace(/\.{2,}/g, '.');
}

function cleanUserPart(value) {
  return latinize(value).replace(/[^a-z0-9]/g, '');
}

function uniqueUsername(parts, used, fallbackPrefix = 'user') {
  const base = parts.map(cleanUserPart).filter(Boolean).join('').slice(0, 24) || fallbackPrefix;
  let candidate = base;
  let counter = 2;
  while (used.has(candidate.toLowerCase())) {
    candidate = `${base}${counter}`.slice(0, 28);
    counter += 1;
  }
  used.add(candidate.toLowerCase());
  return candidate;
}

function makeEmptyStudent(template, familyValues) {
  const base = (template.studentCardFields || []).reduce((accumulator, field) => {
    if (field.type === 'file') {
      accumulator[field.id] = null;
    } else {
      accumulator[field.id] = '';
    }
    return accumulator;
  }, {});

  const student = {
    id: generateId('student_card'),
    ...base,
    _meta: {
      fatherManual: false,
      familyManual: false,
      fullNameManual: false,
      usernameManual: false
    }
  };

  student.student_father_name = String(familyValues.guardian_given_name || '');
  student.student_family_name = String(familyValues.family_name || '');
  student.student_full_name = computeStudentFullName(student);
  student.student_initial_password = '';
  return student;
}

function makeInitialValues(template) {
  const base = template.fields.reduce((accumulator, field) => {
    if (field.type === 'file') {
      accumulator[field.id] = null;
    } else if (field.type === 'checkbox') {
      accumulator[field.id] = false;
    } else {
      accumulator[field.id] = '';
    }
    return accumulator;
  }, {});

  const values = {
    ...base,
    payment_entries: blankPaymentRows(),
    students: [],
    _meta: {
      guardianUsernameManual: false,
      motherFamilyManual: false
    }
  };

  values.students = [makeEmptyStudent(template, values)];
  values.mother_family_name = values.family_name || '';
  return normalizeFamilyValues(template, values);
}

function sanitizeFileMeta(value) {
  if (!value) return null;
  return {
    name: value.name,
    size: value.size,
    type: value.type,
    lastModified: value.lastModified
  };
}

function sanitizeStudentsForSubmit(students) {
  return students.map((student) => ({
    id: student.id,
    student_given_name: student.student_given_name,
    student_father_name: student.student_father_name,
    student_family_name: student.student_family_name,
    student_full_name: student.student_full_name,
    student_birth_date: student.student_birth_date,
    student_gender: student.student_gender,
    student_grade: student.student_grade,
    student_section: student.student_section,
    student_birth_place: student.student_birth_place,
    student_passport_number: student.student_passport_number,
    student_passport_expiry_date: student.student_passport_expiry_date,
    student_previous_school: student.student_previous_school,
    student_address_mashhad: student.student_address_mashhad,
    student_address_iraq: student.student_address_iraq,
    student_health_notes: student.student_health_notes,
    student_photo: sanitizeFileMeta(student.student_photo),
    student_username: student.student_username,
    student_initial_password: student.student_initial_password
  }));
}

function normalizeFamilyValues(template, values) {
  const next = {
    ...values,
    _meta: {
      guardianUsernameManual: Boolean(values._meta?.guardianUsernameManual),
      motherFamilyManual: Boolean(values._meta?.motherFamilyManual)
    }
  };

  if (!next._meta.motherFamilyManual) {
    next.mother_family_name = next.family_name || '';
  }

  if (!next._meta.guardianUsernameManual) {
    const used = new Set();
    next.guardian_username = uniqueUsername(
      [next.guardian_given_name, next.guardian_father_name, next.family_name],
      used,
      'guardian'
    );
  }

  const usedStudentUsernames = new Set([String(next.guardian_username || '').toLowerCase()].filter(Boolean));

  next.students = (next.students || []).map((student) => {
    const meta = {
      fatherManual: Boolean(student._meta?.fatherManual),
      familyManual: Boolean(student._meta?.familyManual),
      fullNameManual: Boolean(student._meta?.fullNameManual),
      usernameManual: Boolean(student._meta?.usernameManual)
    };

    const normalizedStudent = {
      ...student,
      _meta: meta
    };

    if (!meta.fatherManual) {
      normalizedStudent.student_father_name = next.guardian_given_name || '';
    }

    if (!meta.familyManual) {
      normalizedStudent.student_family_name = next.family_name || '';
    }

    if (!meta.fullNameManual) {
      normalizedStudent.student_full_name = computeStudentFullName(normalizedStudent);
    }

    if (!meta.usernameManual) {
      normalizedStudent.student_username = uniqueUsername(
        [normalizedStudent.student_given_name, normalizedStudent.student_father_name, normalizedStudent.student_family_name],
        usedStudentUsernames,
        'student'
      );
    } else if (normalizedStudent.student_username) {
      usedStudentUsernames.add(String(normalizedStudent.student_username).toLowerCase());
    }

    normalizedStudent.student_initial_password = birthDatePasswordFromISO(normalizedStudent.student_birth_date) || normalizedStudent.student_initial_password || '';
    return normalizedStudent;
  });

  return next;
}

function duplicateStudentNames(students) {
  const counts = new Map();
  students.forEach((student) => {
    const key = String(student.student_full_name || '').trim().toLowerCase();
    if (!key) return;
    counts.set(key, (counts.get(key) || 0) + 1);
  });

  return Array.from(counts.entries()).filter(([, count]) => count > 1).map(([name]) => name);
}

function countRequiredDone(template, values) {
  let done = 0;
  const familyRequired = template.fields.filter((field) => field.required);
  familyRequired.forEach((field) => {
    const value = values[field.id];
    if (field.type === 'checkbox') {
      if (value) done += 1;
      return;
    }
    if (field.type === 'file') {
      if (value?.name) done += 1;
      return;
    }
    if (String(value || '').trim()) done += 1;
  });

  const studentRequiredFields = (template.studentCardFields || []).filter((field) => field.required);
  values.students.forEach((student) => {
    studentRequiredFields.forEach((field) => {
      const value = student[field.id];
      if (field.type === 'file') {
        if (value?.name) done += 1;
        return;
      }
      if (String(value || '').trim()) done += 1;
    });
  });

  return done;
}

function countRequiredTotal(template, values) {
  const familyRequired = template.fields.filter((field) => field.required).length;
  const studentRequired = (template.studentCardFields || []).filter((field) => field.required).length;
  return familyRequired + (studentRequired * values.students.length);
}

function totalPayments(rows) {
  return rows.reduce((sum, row) => {
    const amount = Number(String(row.amount || '').replace(/,/g, '').trim());
    return sum + (Number.isFinite(amount) ? amount : 0);
  }, 0);
}

function countErrors(fieldErrors, studentErrors, globalErrors) {
  const familyErrorsCount = Object.values(fieldErrors).filter(Boolean).length;
  const studentErrorsCount = Object.values(studentErrors).reduce((sum, errors) => sum + Object.values(errors || {}).filter(Boolean).length, 0);
  return familyErrorsCount + studentErrorsCount + globalErrors.length;
}

function validateValues(template, values, labels, options = {}) {
  const fieldErrors = {};
  const studentErrors = {};
  const globalErrors = [];
  const requirePreparedUpload = options.requirePreparedUpload;

  template.fields.forEach((field) => {
    const value = values[field.id];

    if (field.required) {
      if (field.type === 'file' && !value?.name) {
        fieldErrors[field.id] = labels.requiredField;
        return;
      }
      if (field.type === 'checkbox' && !value) {
        fieldErrors[field.id] = field.id === 'accept_terms' ? labels.mustAcceptTerms : labels.requiredField;
        return;
      }
      if (field.type !== 'file' && field.type !== 'checkbox' && !String(value || '').trim()) {
        fieldErrors[field.id] = labels.requiredField;
        return;
      }
    }

    if (field.id.includes('phone') && value) {
      if (normalizePhone(value).length < 8) fieldErrors[field.id] = labels.invalidPhone;
    }

    if (field.type === 'file' && value) {
      if (value.size > MAX_FILE_SIZE) fieldErrors[field.id] = labels.fileTooLarge;
      if (field.accept && value.name) {
        const accepted = field.accept.split(',').map((item) => item.trim().toLowerCase());
        const lowerName = value.name.toLowerCase();
        const matches = accepted.some((item) => lowerName.endsWith(item.replace('*', '')));
        if (!matches) fieldErrors[field.id] = labels.invalidFileType;
      }
      if (requirePreparedUpload && field.id === 'family_attachment') {
        fieldErrors[field.id] = labels.uploadTicketRequired;
      }
    }

    if (field.type === 'signature' && value && String(value).trim().length < 3) {
      fieldErrors[field.id] = labels.signatureTooShort;
    }
  });

  (values.students || []).forEach((student) => {
    const perStudentErrors = {};
    (template.studentCardFields || []).forEach((field) => {
      const value = student[field.id];
      if (field.required && !String(value || '').trim()) {
        perStudentErrors[field.id] = labels.requiredField;
        return;
      }
      if (field.id === 'student_photo' && value) {
        if (value.size > MAX_FILE_SIZE) perStudentErrors[field.id] = labels.fileTooLarge;
        if (field.accept && value.name) {
          const accepted = field.accept.split(',').map((item) => item.trim().toLowerCase());
          const lowerName = value.name.toLowerCase();
          const matches = accepted.some((item) => lowerName.endsWith(item.replace('*', '')));
          if (!matches) perStudentErrors[field.id] = labels.invalidFileType;
        }
      }
    });

    if (Object.keys(perStudentErrors).length) {
      studentErrors[student.id] = perStudentErrors;
    }
  });

  if (!values.students.length) {
    globalErrors.push(labels.studentsEmpty);
  }

  const duplicates = duplicateStudentNames(values.students || []);
  if (duplicates.length) {
    globalErrors.push(labels.duplicateStudentNames);
  }

  return { fieldErrors, studentErrors, globalErrors };
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

function InputField({ field, locale, value, error, onChange, labels }) {
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
          <option value="">{labels.selectPlaceholder}</option>
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
        <small className="mt-2 block text-xs leading-6 text-slate-500">{value?.name || labels.fileHint}</small>
        {error ? <small className="mt-2 block text-xs font-bold leading-6 text-rose-600">{error}</small> : null}
      </label>
    );
  }

  if (field.type === 'signature') {
    return (
      <label className={`block ${wrapperClass}`}>
        <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
        <input value={value || ''} onChange={(event) => onChange(field.id, event.target.value)} className={baseInputClass} placeholder={placeholder} />
        <small className="mt-2 block text-xs leading-6 text-slate-500">{labels.signatureHint}</small>
        {error ? <small className="mt-2 block text-xs font-bold leading-6 text-rose-600">{error}</small> : null}
      </label>
    );
  }

  if (field.type === 'date') {
    return (
      <label className={`block ${wrapperClass}`}>
        <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
        <input type="date" value={value || ''} onChange={(event) => onChange(field.id, event.target.value)} className={baseInputClass} />
        <small className="mt-2 block text-xs leading-6 text-slate-500">{value ? formatDateForLocale(locale, value) : labels.dateHint}</small>
        {error ? <small className="mt-2 block text-xs font-bold leading-6 text-rose-600">{error}</small> : null}
      </label>
    );
  }

  const inputType = field.id.includes('phone') ? 'tel' : 'text';

  return (
    <label className={`block ${wrapperClass}`}>
      <span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required ? ' *' : ''}</span>
      <input value={value || ''} type={inputType} onChange={(event) => onChange(field.id, event.target.value)} className={baseInputClass} placeholder={placeholder} />
      {metaBlock}
    </label>
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

function SummaryCard({ title, rows }) {
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

function PaymentsEditor({ locale, labels, rows, students, onChange, totalAmount }) {
  return (
    <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
      <div className="mb-3 text-sm font-black text-slate-900">{labels.paymentTableTitle}</div>
      <div className="overflow-x-auto">
        <table className="min-w-full border-collapse text-sm">
          <thead>
            <tr className="bg-white text-slate-700">
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.row}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.student}</th>
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
                <td className="border border-slate-200 px-2 py-2">
                  <select value={row.student_ref || ''} onChange={(event) => onChange(index, 'student_ref', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2">
                    <option value="">{labels.studentLinkAll}</option>
                    {students.map((student) => (
                      <option key={student.id} value={student.id}>{student.student_full_name || labels.studentCardTitle}</option>
                    ))}
                  </select>
                </td>
                <td className="border border-slate-200 px-2 py-2"><input value={row.card_number} onChange={(event) => onChange(index, 'card_number', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                <td className="border border-slate-200 px-2 py-2"><input value={row.tracking_number} onChange={(event) => onChange(index, 'tracking_number', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                <td className="border border-slate-200 px-2 py-2"><input value={row.reference} onChange={(event) => onChange(index, 'reference', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                <td className="border border-slate-200 px-2 py-2"><input type="date" value={row.payment_date} onChange={(event) => onChange(index, 'payment_date', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                <td className="border border-slate-200 px-2 py-2"><input type="number" value={row.amount} onChange={(event) => onChange(index, 'amount', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                <td className="border border-slate-200 px-2 py-2"><input value={row.notes} onChange={(event) => onChange(index, 'notes', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="bg-brand-50">
              <td className="border border-slate-200 px-2 py-2 text-center font-black" colSpan={6}>{labels.paymentTotal}</td>
              <td className="border border-slate-200 px-2 py-2 font-black text-slate-900">{localeNumber(locale, totalAmount)}</td>
              <td className="border border-slate-200 px-2 py-2" />
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  );
}

function StudentCard({ locale, labels, student, index, fieldById, studentErrors, onFieldChange, onRestoreInheritance, onRemove, canRemove }) {
  const inheritedFather = !student._meta?.fatherManual;
  const inheritedFamily = !student._meta?.familyManual;
  const autoFullName = !student._meta?.fullNameManual;
  const editableFields = [
    'student_birth_date',
    'student_gender',
    'student_grade',
    'student_section',
    'student_birth_place',
    'student_passport_number',
    'student_passport_expiry_date',
    'student_previous_school',
    'student_address_mashhad',
    'student_address_iraq',
    'student_health_notes',
    'student_photo'
  ];

  return (
    <div className="rounded-[24px] border border-slate-200 bg-slate-50 p-4">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 pb-3">
        <div>
          <h3 className="text-lg font-black text-slate-950">{labels.studentCardTitle} {localeNumber(locale, index + 1)}</h3>
          <p className="mt-1 text-xs leading-6 text-slate-500">{labels.generatedCredentialsHint}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button type="button" onClick={() => onRestoreInheritance(student.id)} className="rounded-2xl border border-brand-200 bg-brand-50 px-3 py-2 text-xs font-bold text-brand-800">{labels.restoreInheritance}</button>
          {canRemove ? <button type="button" onClick={() => onRemove(student.id)} className="rounded-2xl border border-rose-200 bg-rose-50 px-3 py-2 text-xs font-bold text-rose-700">{labels.removeStudent}</button> : null}
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <InputField field={fieldById.get('student_given_name')} locale={locale} value={student.student_given_name} error={studentErrors?.student_given_name} onChange={(fieldId, value) => onFieldChange(student.id, fieldId, value)} labels={labels} />
        <div>
          <div className="mb-2 flex items-center justify-between gap-3">
            <span className="text-sm font-bold text-slate-800">{fieldById.get('student_father_name')?.label?.[locale]} *</span>
            <StatusPill tone={inheritedFather ? 'brand' : 'warning'}>{inheritedFather ? labels.inheritedFromGuardian : labels.manualOverride}</StatusPill>
          </div>
          <input value={student.student_father_name || ''} onChange={(event) => onFieldChange(student.id, 'student_father_name', event.target.value)} className={`w-full rounded-2xl border px-3 py-3 text-sm ${studentErrors?.student_father_name ? 'border-rose-300 bg-rose-50 text-rose-900' : 'border-slate-200 bg-white text-slate-900'}`} />
          {studentErrors?.student_father_name ? <small className="mt-2 block text-xs font-bold text-rose-600">{studentErrors.student_father_name}</small> : null}
        </div>

        <div>
          <div className="mb-2 flex items-center justify-between gap-3">
            <span className="text-sm font-bold text-slate-800">{fieldById.get('student_family_name')?.label?.[locale]} *</span>
            <StatusPill tone={inheritedFamily ? 'brand' : 'warning'}>{inheritedFamily ? labels.inheritedFromFamily : labels.manualOverride}</StatusPill>
          </div>
          <input value={student.student_family_name || ''} onChange={(event) => onFieldChange(student.id, 'student_family_name', event.target.value)} className={`w-full rounded-2xl border px-3 py-3 text-sm ${studentErrors?.student_family_name ? 'border-rose-300 bg-rose-50 text-rose-900' : 'border-slate-200 bg-white text-slate-900'}`} />
          {studentErrors?.student_family_name ? <small className="mt-2 block text-xs font-bold text-rose-600">{studentErrors.student_family_name}</small> : null}
        </div>

        <div className="md:col-span-2">
          <div className="mb-2 flex items-center justify-between gap-3">
            <span className="text-sm font-bold text-slate-800">{fieldById.get('student_full_name')?.label?.[locale]} *</span>
            <button type="button" onClick={() => onFieldChange(student.id, 'student_full_name', computeStudentFullName(student), { forceAutoFullName: true })} className="rounded-2xl border border-slate-200 px-3 py-2 text-xs font-bold text-slate-700">{autoFullName ? labels.autoComputedName : labels.useComputedName}</button>
          </div>
          <input value={student.student_full_name || ''} onChange={(event) => onFieldChange(student.id, 'student_full_name', event.target.value)} className={`w-full rounded-2xl border px-3 py-3 text-sm ${studentErrors?.student_full_name ? 'border-rose-300 bg-rose-50 text-rose-900' : 'border-slate-200 bg-white text-slate-900'}`} />
          {studentErrors?.student_full_name ? <small className="mt-2 block text-xs font-bold text-rose-600">{studentErrors.student_full_name}</small> : null}
        </div>

        {editableFields.map((fieldId) => {
          const field = fieldById.get(fieldId);
          return (
            <InputField
              key={`${student.id}-${fieldId}`}
              field={field}
              locale={locale}
              value={student[fieldId]}
              error={studentErrors?.[fieldId]}
              onChange={(nextFieldId, value) => onFieldChange(student.id, nextFieldId, value)}
              labels={labels}
            />
          );
        })}

        <InputField field={fieldById.get('student_username')} locale={locale} value={student.student_username} error={studentErrors?.student_username} onChange={(fieldId, value) => onFieldChange(student.id, fieldId, value)} labels={labels} />
        <InputField field={fieldById.get('student_initial_password')} locale={locale} value={student.student_initial_password} error={studentErrors?.student_initial_password} onChange={(fieldId, value) => onFieldChange(student.id, fieldId, value)} labels={labels} />
      </div>
    </div>
  );
}

function PrintableFamilyRegistration({ locale, labels, template, values, totalAmount }) {
  const guardianFullName = computeGuardianFullName(values);
  const motherFullName = computeMotherFullName(values);

  return (
    <div className="space-y-6 text-black">
      <section className="mx-auto w-full max-w-[794px] border-2 border-black bg-white p-5 shadow-sm">
        <div className="text-center">
          <div className="text-[18px] font-black">{labels.familySheetTitle}</div>
          <div className="mt-2 text-[12px]">{template.title[locale]}</div>
        </div>

        <div className="mt-4 grid gap-0 md:grid-cols-2">
          <PrintField label={template.fields.find((field) => field.id === 'guardian_given_name')?.label?.[locale]} value={values.guardian_given_name} />
          <PrintField label={template.fields.find((field) => field.id === 'guardian_father_name')?.label?.[locale]} value={values.guardian_father_name} />
          <PrintField label={template.fields.find((field) => field.id === 'family_name')?.label?.[locale]} value={values.family_name} />
          <PrintField label={template.fields.find((field) => field.id === 'guardian_username')?.label?.[locale]} value={values.guardian_username} />
          <PrintField label={labels.familySummaryTitle} value={guardianFullName} wide />
          <PrintField label={template.fields.find((field) => field.id === 'guardian_phone_primary')?.label?.[locale]} value={values.guardian_phone_primary} />
          <PrintField label={template.fields.find((field) => field.id === 'guardian_phone_whatsapp')?.label?.[locale]} value={values.guardian_phone_whatsapp} />
          <PrintField label={template.fields.find((field) => field.id === 'mother_given_name')?.label?.[locale]} value={values.mother_given_name} />
          <PrintField label={template.fields.find((field) => field.id === 'mother_father_name')?.label?.[locale]} value={values.mother_father_name} />
          <PrintField label={template.fields.find((field) => field.id === 'mother_family_name')?.label?.[locale]} value={values.mother_family_name} />
          <PrintField label={template.fields.find((field) => field.id === 'mother_phone')?.label?.[locale]} value={values.mother_phone} />
          <PrintField label={labels.documentsSummaryTitle} value={motherFullName || '—'} wide />
          <PrintField label={template.fields.find((field) => field.id === 'living_with_in_iran')?.label?.[locale]} value={values.living_with_in_iran} />
          <PrintField label={template.fields.find((field) => field.id === 'residence_type')?.label?.[locale]} value={(template.fields.find((field) => field.id === 'residence_type')?.options || []).find((option) => option.value === values.residence_type)?.label?.[locale] || values.residence_type} />
          <PrintField label={template.fields.find((field) => field.id === 'general_family_health_notes')?.label?.[locale]} value={values.general_family_health_notes} wide />
          <PrintField label={template.fields.find((field) => field.id === 'document_notes')?.label?.[locale]} value={values.document_notes} wide />
        </div>

        <div className="mt-4 overflow-hidden border border-black">
          <table className="min-w-full border-collapse text-[11px]">
            <thead>
              <tr>
                <th className="border border-black px-1 py-2">#</th>
                <th className="border border-black px-1 py-2">{template.studentCardFields.find((field) => field.id === 'student_full_name')?.label?.[locale]}</th>
                <th className="border border-black px-1 py-2">{template.studentCardFields.find((field) => field.id === 'student_grade')?.label?.[locale]}</th>
                <th className="border border-black px-1 py-2">{template.studentCardFields.find((field) => field.id === 'student_gender')?.label?.[locale]}</th>
                <th className="border border-black px-1 py-2">{template.studentCardFields.find((field) => field.id === 'student_username')?.label?.[locale]}</th>
              </tr>
            </thead>
            <tbody>
              {values.students.map((student, index) => (
                <tr key={student.id}>
                  <td className="border border-black px-1 py-2 text-center">{localeNumber(locale, index + 1)}</td>
                  <td className="border border-black px-1 py-2">{student.student_full_name || ' '}</td>
                  <td className="border border-black px-1 py-2">{(template.studentCardFields.find((field) => field.id === 'student_grade')?.options || []).find((option) => option.value === student.student_grade)?.label?.[locale] || ' '}</td>
                  <td className="border border-black px-1 py-2">{(template.studentCardFields.find((field) => field.id === 'student_gender')?.options || []).find((option) => option.value === student.student_gender)?.label?.[locale] || ' '}</td>
                  <td className="border border-black px-1 py-2">{student.student_username || ' '}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="mt-4 overflow-hidden border border-black">
          <table className="min-w-full border-collapse text-[11px]">
            <thead>
              <tr>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.row}</th>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.student}</th>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.cardNumber}</th>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.trackingNumber}</th>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.reference}</th>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.date}</th>
                <th className="border border-black px-1 py-2">{labels.paymentColumns.amount}</th>
              </tr>
            </thead>
            <tbody>
              {values.payment_entries.map((row, index) => (
                <tr key={row.id}>
                  <td className="border border-black px-1 py-2 text-center">{localeNumber(locale, index + 1)}</td>
                  <td className="border border-black px-1 py-2">{values.students.find((student) => student.id === row.student_ref)?.student_full_name || labels.studentLinkAll}</td>
                  <td className="border border-black px-1 py-2">{row.card_number || ' '}</td>
                  <td className="border border-black px-1 py-2">{row.tracking_number || ' '}</td>
                  <td className="border border-black px-1 py-2">{row.reference || ' '}</td>
                  <td className="border border-black px-1 py-2">{row.payment_date ? formatDateForLocale(locale, row.payment_date) : ' '}</td>
                  <td className="border border-black px-1 py-2">{row.amount ? localeNumber(locale, Number(row.amount)) : ' '}</td>
                </tr>
              ))}
              <tr>
                <td className="border border-black px-1 py-2 text-center font-black" colSpan={6}>{labels.paymentTotal}</td>
                <td className="border border-black px-1 py-2 font-black">{localeNumber(locale, totalAmount)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div className="mt-4 grid gap-4 text-[12px] font-black md:grid-cols-2">
          <div className="rounded-xl border border-black p-3">
            {values.document_copy_received ? '☑' : '☐'} {template.fields.find((field) => field.id === 'document_copy_received')?.label?.[locale]}
          </div>
          <div className="rounded-xl border border-black p-3">
            {values.document_original_received ? '☑' : '☐'} {template.fields.find((field) => field.id === 'document_original_received')?.label?.[locale]}
          </div>
        </div>
      </section>

      {values.students.map((student, index) => (
        <section key={student.id} className="mx-auto w-full max-w-[794px] border-2 border-black bg-white p-5 shadow-sm">
          <div className="text-center">
            <div className="text-[18px] font-black">{labels.studentAppendixTitle} {localeNumber(locale, index + 1)}</div>
            <div className="mt-2 text-[13px]">{student.student_full_name || '—'}</div>
          </div>

          <div className="mt-4 grid gap-0 md:grid-cols-2">
            <PrintField label={template.studentCardFields.find((field) => field.id === 'student_full_name')?.label?.[locale]} value={student.student_full_name} />
            <PrintField label={template.studentCardFields.find((field) => field.id === 'student_birth_date')?.label?.[locale]} value={student.student_birth_date ? formatDateForLocale(locale, student.student_birth_date) : ''} />
            <PrintField label={template.studentCardFields.find((field) => field.id === 'student_grade')?.label?.[locale]} value={(template.studentCardFields.find((field) => field.id === 'student_grade')?.options || []).find((option) => option.value === student.student_grade)?.label?.[locale] || student.student_grade} />
            <PrintField label={template.studentCardFields.find((field) => field.id === 'student_section')?.label?.[locale]} value={(template.studentCardFields.find((field) => field.id === 'student_section')?.options || []).find((option) => option.value === student.student_section)?.label?.[locale] || student.student_section} />
            <PrintField label={template.studentCardFields.find((field) => field.id === 'student_passport_number')?.label?.[locale]} value={student.student_passport_number} />
            <PrintField label={template.studentCardFields.find((field) => field.id === 'student_previous_school')?.label?.[locale]} value={student.student_previous_school} />
            <PrintField label={template.studentCardFields.find((field) => field.id === 'student_address_mashhad')?.label?.[locale]} value={student.student_address_mashhad} wide />
            <PrintField label={template.studentCardFields.find((field) => field.id === 'student_address_iraq')?.label?.[locale]} value={student.student_address_iraq} wide />
            <PrintField label={template.studentCardFields.find((field) => field.id === 'student_health_notes')?.label?.[locale]} value={student.student_health_notes} wide />
            <PrintField label={template.studentCardFields.find((field) => field.id === 'student_username')?.label?.[locale]} value={student.student_username} />
            <PrintField label={template.studentCardFields.find((field) => field.id === 'student_initial_password')?.label?.[locale]} value={student.student_initial_password} />
          </div>
        </section>
      ))}
    </div>
  );
}

function PrintField({ label, value, wide = false }) {
  return (
    <div className={`border border-black p-2 ${wide ? 'md:col-span-2' : ''}`}>
      <div className="text-[11px] font-bold">{label}</div>
      <div className="mt-1 min-h-[22px] text-[12px] font-semibold">{value || ' '}</div>
    </div>
  );
}

export default function FamilyRegistrationV3Shell({ locale, dictionary }) {
  const router = useRouter();
  const forms = dictionary.forms;
  const labels = forms.familyRegistrationV3;
  const template = useMemo(() => buildTemplateByKey('family_registration_v3'), []);
  const fieldById = useMemo(() => fieldMapFromTemplate(template), [template]);

  const [activeLocale, setActiveLocale] = useState(locale);
  const [values, setValues] = useState(() => makeInitialValues(template));
  const [fieldErrors, setFieldErrors] = useState({});
  const [studentErrors, setStudentErrors] = useState({});
  const [globalErrors, setGlobalErrors] = useState([]);
  const [saveState, setSaveState] = useState('idle');
  const [submitState, setSubmitState] = useState('idle');
  const [versions, setVersions] = useState([]);
  const [receipt, setReceipt] = useState(null);
  const [uploadTicket, setUploadTicket] = useState(null);
  const [uploadedAttachment, setUploadedAttachment] = useState(null);
  const [uploadState, setUploadState] = useState('idle');
  const [fileObjects, setFileObjects] = useState({ family_attachment: null });

  const meta = localeMeta[activeLocale] || localeMeta.ar;

  useEffect(() => {
    const remembered = window.localStorage.getItem(LOCAL_LANGUAGE_KEY);
    if (remembered && localeMeta[remembered]) setActiveLocale(remembered);

    const raw = window.localStorage.getItem(LOCAL_FORM_STATE_KEY);
    if (raw) {
      try {
        const parsed = JSON.parse(raw);
        if (parsed?.values) setValues(normalizeFamilyValues(template, parsed.values));
        if (parsed?.receipt) setReceipt(parsed.receipt);
        if (parsed?.uploadTicket) setUploadTicket(parsed.uploadTicket);
        if (parsed?.uploadedAttachment) setUploadedAttachment(parsed.uploadedAttachment);
      } catch (error) {
        console.error(error);
      }
    }
  }, [template]);

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

  const requiredDone = useMemo(() => countRequiredDone(template, values), [template, values]);
  const requiredTotal = useMemo(() => countRequiredTotal(template, values), [template, values]);
  const totalAmount = useMemo(() => totalPayments(values.payment_entries || []), [values.payment_entries]);
  const guardianFullName = useMemo(() => computeGuardianFullName(values), [values]);
  const motherFullName = useMemo(() => computeMotherFullName(values), [values]);
  const errorCount = countErrors(fieldErrors, studentErrors, globalErrors);

  function persistLocal(nextValues, nextReceipt = receipt, nextUploadTicket = uploadTicket, nextAttachment = uploadedAttachment) {
    window.localStorage.setItem(LOCAL_FORM_STATE_KEY, JSON.stringify({
      values: nextValues,
      receipt: nextReceipt,
      uploadTicket: nextUploadTicket,
      uploadedAttachment: nextAttachment
    }));
  }

  function setFieldValue(fieldId, value) {
    setValues((current) => {
      const next = {
        ...current,
        _meta: {
          ...current._meta
        }
      };

      let normalizedValue = value;
      if (fieldId.includes('phone') && typeof value === 'string') {
        normalizedValue = normalizePhone(value);
      }

      if (fieldId === 'guardian_username') {
        next._meta.guardianUsernameManual = true;
      }

      if (fieldId === 'mother_family_name') {
        next._meta.motherFamilyManual = String(value || '').trim() !== String(current.family_name || '').trim();
      }

      if (fieldId === 'family_attachment') {
        setFileObjects((files) => ({ ...files, family_attachment: value?.rawFile || null }));
        normalizedValue = value?.rawFile ? sanitizeFileMeta(value.rawFile) : null;
        setUploadTicket(null);
        setUploadedAttachment(null);
        setUploadState('idle');
      }

      next[fieldId] = normalizedValue;
      const normalized = normalizeFamilyValues(template, next);
      persistLocal(normalized, receipt, fieldId === 'family_attachment' ? null : uploadTicket, fieldId === 'family_attachment' ? null : uploadedAttachment);
      return normalized;
    });

    setFieldErrors((current) => ({ ...current, [fieldId]: undefined }));
    setGlobalErrors([]);
    if (submitState !== 'idle') setSubmitState('idle');
  }

  function setStudentValue(studentId, fieldId, value, options = {}) {
    setValues((current) => {
      const next = {
        ...current,
        students: current.students.map((student) => {
          if (student.id !== studentId) return student;
          const updated = {
            ...student,
            _meta: {
              ...student._meta
            }
          };

          let normalizedValue = value;
          if (fieldId === 'student_photo') {
            normalizedValue = value?.rawFile ? sanitizeFileMeta(value.rawFile) : null;
          }

          if (fieldId === 'student_father_name') {
            updated._meta.fatherManual = !options.forceInherited && String(normalizedValue || '').trim() !== String(current.guardian_given_name || '').trim();
          }

          if (fieldId === 'student_family_name') {
            updated._meta.familyManual = !options.forceInherited && String(normalizedValue || '').trim() !== String(current.family_name || '').trim();
          }

          if (fieldId === 'student_full_name') {
            updated._meta.fullNameManual = !options.forceAutoFullName;
          }

          if (fieldId === 'student_username') {
            updated._meta.usernameManual = true;
          }

          updated[fieldId] = normalizedValue;
          return updated;
        })
      };

      const normalized = normalizeFamilyValues(template, next);
      persistLocal(normalized);
      return normalized;
    });

    setStudentErrors((current) => ({
      ...current,
      [studentId]: {
        ...(current[studentId] || {}),
        [fieldId]: undefined
      }
    }));
    setGlobalErrors([]);
    if (submitState !== 'idle') setSubmitState('idle');
  }

  function restoreStudentInheritance(studentId) {
    setValues((current) => {
      const next = {
        ...current,
        students: current.students.map((student) => {
          if (student.id !== studentId) return student;
          return {
            ...student,
            _meta: {
              ...student._meta,
              fatherManual: false,
              familyManual: false,
              fullNameManual: false,
              usernameManual: false
            }
          };
        })
      };

      const normalized = normalizeFamilyValues(template, next);
      persistLocal(normalized);
      return normalized;
    });
  }

  function addStudent() {
    setValues((current) => {
      const next = {
        ...current,
        students: [...current.students, makeEmptyStudent(template, current)]
      };
      const normalized = normalizeFamilyValues(template, next);
      persistLocal(normalized);
      return normalized;
    });
  }

  function removeStudent(studentId) {
    setValues((current) => {
      const nextStudents = current.students.filter((student) => student.id !== studentId);
      const nextPayments = current.payment_entries.map((row) => row.student_ref === studentId ? { ...row, student_ref: '' } : row);
      const next = {
        ...current,
        students: nextStudents.length ? nextStudents : [makeEmptyStudent(template, current)],
        payment_entries: nextPayments
      };
      const normalized = normalizeFamilyValues(template, next);
      persistLocal(normalized);
      return normalized;
    });

    setStudentErrors((current) => {
      const next = { ...current };
      delete next[studentId];
      return next;
    });
  }

  function setPaymentValue(index, key, value) {
    setValues((current) => {
      const next = {
        ...current,
        payment_entries: current.payment_entries.map((row, rowIndex) => rowIndex === index ? { ...row, [key]: value } : row)
      };
      persistLocal(next);
      return next;
    });
  }

  function resetForm() {
    const next = makeInitialValues(template);
    setValues(next);
    setFieldErrors({});
    setStudentErrors({});
    setGlobalErrors([]);
    setReceipt(null);
    setUploadTicket(null);
    setUploadedAttachment(null);
    setFileObjects({ family_attachment: null });
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
    if (!values.family_attachment?.name) {
      setFieldErrors((current) => ({ ...current, family_attachment: labels.requiredField }));
      return;
    }

    setUploadState('loading');
    try {
      const result = await requestUploadTicketRpc({
        form_slug: template.slug,
        locale: activeLocale,
        field_id: 'family_attachment',
        file_name: values.family_attachment.name,
        content_type: values.family_attachment.type || 'application/octet-stream',
        byte_size: values.family_attachment.size || 0
      });

      if (result?.ok === false) throw new Error(result.error || 'upload_ticket_failed');
      const ticketPayload = result?.data || result;
      const nextTicket = {
        ...ticketPayload,
        ticketId: ticketPayload?.ticket_id || ticketPayload?.upload_token || `UP-${Date.now()}`,
        expiresAtLabel: ticketPayload?.expires_at ? formatDateForLocale(activeLocale, String(ticketPayload.expires_at).slice(0, 10)) : labels.uploadTicketPending
      };
      setUploadTicket(nextTicket);
      persistLocal(values, receipt, nextTicket, uploadedAttachment);
      setUploadState('ready');
      setFieldErrors((current) => ({ ...current, family_attachment: undefined }));
    } catch (error) {
      console.error(error);
      setUploadState('error');
      setFieldErrors((current) => ({ ...current, family_attachment: labels.uploadTicketError }));
    }
  }

  async function submitForm() {
    const validation = validateValues(template, values, labels, { requirePreparedUpload: Boolean(values.family_attachment?.name && !uploadTicket) });
    setFieldErrors(validation.fieldErrors);
    setStudentErrors(validation.studentErrors);
    setGlobalErrors(validation.globalErrors);

    if (Object.keys(validation.fieldErrors).length || Object.keys(validation.studentErrors).length || validation.globalErrors.length) {
      setSubmitState('validation_error');
      return;
    }

    setSubmitState('submitting');
    const reportId = `FAM-${Date.now()}`;

    try {
      let attachmentPayload = uploadedAttachment;

      if (values.family_attachment?.name) {
        if (!uploadTicket?.ticketId) {
          setFieldErrors((current) => ({ ...current, family_attachment: labels.uploadTicketRequired }));
          setSubmitState('validation_error');
          return;
        }

        if (!attachmentPayload) {
          const rawFile = fileObjects.family_attachment;
          if (!rawFile) {
            setFieldErrors((current) => ({ ...current, family_attachment: labels.fileNeedsReselect }));
            setSubmitState('validation_error');
            return;
          }

          setUploadState('uploading');
          const uploadResult = await uploadAttachmentTransport({
            ticketId: uploadTicket.ticketId,
            formSlug: template.slug,
            fieldId: 'family_attachment',
            file: rawFile
          });

          if (uploadResult?.ok === false) throw new Error(uploadResult.error || 'upload_failed');
          attachmentPayload = uploadResult;
          setUploadedAttachment(uploadResult);
          setUploadState('uploaded');
        }
      }

      const normalizedStudents = sanitizeStudentsForSubmit(values.students);
      const payloadValues = {
        guardian_name: guardianFullName,
        guardian_full_name: guardianFullName,
        student_name: normalizedStudents[0]?.student_full_name || '',
        student_full_name: normalizedStudents[0]?.student_full_name || '',
        family_name: values.family_name,
        guardian: {
          guardian_given_name: values.guardian_given_name,
          guardian_father_name: values.guardian_father_name,
          family_name: values.family_name,
          guardian_full_name: guardianFullName,
          guardian_username: values.guardian_username,
          guardian_birth_date: values.guardian_birth_date,
          guardian_nationality: values.guardian_nationality,
          guardian_passport_number: values.guardian_passport_number,
          guardian_phone_primary: values.guardian_phone_primary,
          guardian_phone_whatsapp: values.guardian_phone_whatsapp,
          guardian_phone_emergency: values.guardian_phone_emergency,
          guardian_education_level: values.guardian_education_level,
          guardian_education_notes: values.guardian_education_notes,
          guardian_work_type: values.guardian_work_type,
          guardian_work_notes: values.guardian_work_notes,
          residence_type: values.residence_type
        },
        mother: {
          mother_given_name: values.mother_given_name,
          mother_father_name: values.mother_father_name,
          mother_family_name: values.mother_family_name,
          mother_full_name: motherFullName,
          mother_birth_date: values.mother_birth_date,
          mother_nationality: values.mother_nationality,
          mother_passport_number: values.mother_passport_number,
          mother_phone: values.mother_phone,
          mother_whatsapp: values.mother_whatsapp,
          mother_education_level: values.mother_education_level,
          mother_education_notes: values.mother_education_notes,
          mother_work_type: values.mother_work_type,
          mother_work_notes: values.mother_work_notes
        },
        family_context: {
          living_with_in_iran: values.living_with_in_iran,
          general_family_health_notes: values.general_family_health_notes
        },
        students: normalizedStudents,
        payment_entries: values.payment_entries,
        payment_total: totalAmount,
        documents: {
          document_copy_received: values.document_copy_received,
          document_original_received: values.document_original_received,
          document_notes: values.document_notes,
          family_attachment: sanitizeFileMeta(values.family_attachment)
        },
        approval: {
          accept_terms: values.accept_terms,
          guardian_signature: values.guardian_signature
        }
      };

      const result = await submitFamilyRegistrationV3Rpc({
        form_slug: template.slug,
        locale: activeLocale,
        visibility: template.visibility,
        submission_ref: reportId,
        schema: template,
        values: payloadValues,
        upload_ticket_id: uploadTicket?.ticketId || null,
        uploaded_attachment: attachmentPayload ? {
          bucket: attachmentPayload.bucket,
          object_path: attachmentPayload.object_path,
          file_name: attachmentPayload.file_name,
          byte_size: attachmentPayload.byte_size
        } : null
      });

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
        applicant: normalizedStudents[0]?.student_full_name || guardianFullName
      });
      router.push(`/${activeLocale}/forms/family-registration-v3/success?${params.toString()}`);
    } catch (error) {
      console.error(error);
      setSubmitState('submit_error');
      setUploadState((current) => (current === 'uploading' ? 'error' : current));
    }
  }

  const familyRows = [
    { label: template.fields.find((field) => field.id === 'guardian_given_name')?.label?.[activeLocale], value: values.guardian_given_name },
    { label: template.fields.find((field) => field.id === 'guardian_father_name')?.label?.[activeLocale], value: values.guardian_father_name },
    { label: template.fields.find((field) => field.id === 'family_name')?.label?.[activeLocale], value: values.family_name },
    { label: labels.familySummaryTitle, value: guardianFullName }
  ];

  const studentsRows = values.students.map((student, index) => ({
    label: `${labels.studentCardTitle} ${localeNumber(activeLocale, index + 1)}`,
    value: `${student.student_full_name || '—'} — ${(fieldById.get('student_grade')?.options || []).find((option) => option.value === student.student_grade)?.label?.[activeLocale] || '—'}`
  }));

  const familyFieldIds = {
    guardian: template.fields.filter((field) => field.section === 'guardian').map((field) => field.id),
    mother: template.fields.filter((field) => field.section === 'mother').map((field) => field.id),
    family_context: template.fields.filter((field) => field.section === 'family_context').map((field) => field.id),
    documents: template.fields.filter((field) => field.section === 'documents').map((field) => field.id),
    approval: template.fields.filter((field) => field.section === 'approval').map((field) => field.id)
  };

  return (
    <main className={`mx-auto min-h-screen max-w-[1550px] px-4 py-6 ${localeFontClass(activeLocale)}`} dir={meta.dir}>
      <section className="rounded-[30px] border border-slate-200 bg-white/90 p-5 shadow-soft">
        <div className="flex flex-wrap items-start justify-between gap-4 border-b border-slate-200 pb-5">
          <div>
            <p className="mb-2 text-sm text-slate-500">{forms.builder.badge}</p>
            <h1 className="text-3xl font-black text-slate-950">{labels.pageTitle}</h1>
            <p className="mt-2 max-w-4xl text-sm leading-7 text-slate-600">{labels.pageSubtitle}</p>
            <div className="mt-3 flex flex-wrap gap-2 text-sm">
              <StatusPill tone="brand">{meta.label}</StatusPill>
              <StatusPill tone="slate">{localeDateLabel(activeLocale)}</StatusPill>
              <StatusPill tone="slate">{labels.visibilityLabel}: {forms.visibility[template.visibility]}</StatusPill>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <LanguageSwitcher locale={activeLocale} onChange={setActiveLocale} labels={forms.languageSwitcher} />
            <Link href={`/${activeLocale}/forms/builder`} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.openBuilder}</Link>
            <button onClick={() => window.print()} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.printPreview}</button>
            <button onClick={saveNow} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.saveNow}</button>
            <button onClick={submitForm} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labels.submit}</button>
          </div>
        </div>

        <div className="mt-5 grid gap-4 xl:grid-cols-[minmax(0,1fr)_430px]">
          <section className="space-y-4">
            <div className="rounded-[24px] border border-slate-200 bg-white p-4">
              <div className="grid gap-3 md:grid-cols-4">
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
                  <div className="text-slate-500">{labels.statusDraft}</div>
                  <div className="mt-1 font-bold text-slate-900">{saveState === 'saved' ? labels.saved : saveState === 'saving' ? labels.saving : saveState === 'error' ? labels.saveError : labels.notSavedYet}</div>
                </div>
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
                  <div className="text-slate-500">{labels.requiredCoverage}</div>
                  <div className="mt-1 font-bold text-slate-900">{requiredDone} / {requiredTotal}</div>
                </div>
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
                  <div className="text-slate-500">{labels.versionCount}</div>
                  <div className="mt-1 font-bold text-slate-900">{versions.length}</div>
                </div>
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
                  <div className="text-slate-500">{labels.errorCount}</div>
                  <div className="mt-1 font-bold text-slate-900">{errorCount}</div>
                </div>
              </div>
            </div>

            {globalErrors.length ? (
              <div className="rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4 text-sm text-rose-700">
                {globalErrors.map((message) => <div key={message}>• {message}</div>)}
              </div>
            ) : null}

            <SectionCard title={template.sections.find((section) => section.key === 'guardian')?.title?.[activeLocale]} subtitle={labels.sectionHints.guardian}>
              <div className="grid gap-4 md:grid-cols-2">
                {familyFieldIds.guardian.map((fieldId) => (
                  <InputField key={fieldId} field={fieldById.get(fieldId)} locale={activeLocale} value={values[fieldId]} error={fieldErrors[fieldId]} onChange={setFieldValue} labels={labels} />
                ))}
              </div>
            </SectionCard>

            <SectionCard title={template.sections.find((section) => section.key === 'mother')?.title?.[activeLocale]} subtitle={labels.sectionHints.mother}>
              <div className="grid gap-4 md:grid-cols-2">
                {familyFieldIds.mother.map((fieldId) => (
                  <InputField key={fieldId} field={fieldById.get(fieldId)} locale={activeLocale} value={values[fieldId]} error={fieldErrors[fieldId]} onChange={setFieldValue} labels={labels} />
                ))}
              </div>
            </SectionCard>

            <SectionCard title={template.sections.find((section) => section.key === 'students')?.title?.[activeLocale]} subtitle={labels.sectionHints.students}>
              <div className="space-y-4">
                {values.students.map((student, index) => (
                  <StudentCard
                    key={student.id}
                    locale={activeLocale}
                    labels={labels}
                    student={student}
                    index={index}
                    fieldById={fieldById}
                    studentErrors={studentErrors[student.id] || {}}
                    onFieldChange={setStudentValue}
                    onRestoreInheritance={restoreStudentInheritance}
                    onRemove={removeStudent}
                    canRemove={values.students.length > 1}
                  />
                ))}
                <button type="button" onClick={addStudent} className="rounded-2xl border border-brand-200 bg-brand-50 px-4 py-3 font-bold text-brand-800">{labels.addStudent}</button>
              </div>
            </SectionCard>

            <SectionCard title={template.sections.find((section) => section.key === 'family_context')?.title?.[activeLocale]} subtitle={labels.sectionHints.family_context}>
              <div className="grid gap-4 md:grid-cols-2">
                {familyFieldIds.family_context.map((fieldId) => (
                  <InputField key={fieldId} field={fieldById.get(fieldId)} locale={activeLocale} value={values[fieldId]} error={fieldErrors[fieldId]} onChange={setFieldValue} labels={labels} />
                ))}
              </div>
            </SectionCard>

            <SectionCard title={template.sections.find((section) => section.key === 'finance')?.title?.[activeLocale]} subtitle={labels.sectionHints.finance}>
              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                <div className="mb-3 text-sm font-black text-slate-900">{labels.feeBandsTitle}</div>
                <div className="space-y-2 text-sm text-slate-700">
                  {labels.feeBands.map((band) => (
                    <div key={`${band.label}-${band.amount}`} className="flex items-center justify-between gap-4 rounded-xl border border-slate-200 bg-white px-3 py-2">
                      <span>{band.label}</span>
                      <span className="font-black text-slate-900">{band.amount}</span>
                    </div>
                  ))}
                </div>
              </div>
              <div className="mt-4">
                <PaymentsEditor locale={activeLocale} labels={labels} rows={values.payment_entries} students={values.students} onChange={setPaymentValue} totalAmount={totalAmount} />
              </div>
            </SectionCard>

            <SectionCard title={template.sections.find((section) => section.key === 'documents')?.title?.[activeLocale]} subtitle={labels.sectionHints.documents}>
              <div className="grid gap-4 md:grid-cols-2">
                {familyFieldIds.documents.map((fieldId) => (
                  <InputField key={fieldId} field={fieldById.get(fieldId)} locale={activeLocale} value={values[fieldId]} error={fieldErrors[fieldId]} onChange={setFieldValue} labels={labels} />
                ))}
              </div>
            </SectionCard>

            <SectionCard title={template.sections.find((section) => section.key === 'approval')?.title?.[activeLocale]} subtitle={labels.sectionHints.approval}>
              <div className="mb-4 rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700">{labels.termsAcceptanceText}</div>
              <div className="grid gap-4 md:grid-cols-2">
                {familyFieldIds.approval.map((fieldId) => (
                  <InputField key={fieldId} field={fieldById.get(fieldId)} locale={activeLocale} value={values[fieldId]} error={fieldErrors[fieldId]} onChange={setFieldValue} labels={labels} />
                ))}
              </div>
            </SectionCard>

            <div className="no-print flex flex-wrap gap-3 rounded-[24px] border border-slate-200 bg-white p-4 shadow-soft">
              <button onClick={resetForm} className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-2 font-bold text-amber-800">{labels.reset}</button>
              <button onClick={prepareUploadTicket} className="rounded-2xl border border-brand-200 bg-brand-50 px-4 py-2 font-bold text-brand-800">{labels.prepareUpload}</button>
              <button onClick={saveNow} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.saveNow}</button>
              <button onClick={submitForm} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labels.submit}</button>
              {submitState === 'validation_error' ? <span className="self-center text-sm font-bold text-red-600">{labels.validationError}</span> : null}
              {submitState === 'submitted' ? <span className="self-center text-sm font-bold text-brand-700">{labels.submitSuccess}</span> : null}
              {submitState === 'submit_error' ? <span className="self-center text-sm font-bold text-red-600">{labels.submitError}</span> : null}
              {submitState === 'submitting' ? <span className="self-center text-sm font-bold text-slate-700">{labels.submitting}</span> : null}
            </div>
          </section>

          <aside className="space-y-4 no-print">
            <UploadStatusPanel labels={labels} uploadTicket={uploadTicket} uploadedAttachment={uploadedAttachment} uploadState={uploadState} />
            <SummaryCard title={labels.familySummaryTitle} rows={familyRows} />
            <SummaryCard title={labels.studentsSummaryTitle} rows={studentsRows.length ? studentsRows : [{ label: labels.studentCardTitle, value: labels.studentsEmpty }]} />
            <SummaryCard title={labels.financeSummaryTitle} rows={[
              { label: labels.paymentTotal, value: localeNumber(activeLocale, totalAmount) },
              { label: labels.documentsSummaryTitle, value: uploadedAttachment?.file_name || values.family_attachment?.name || '—' },
              { label: labels.versionCount, value: localeNumber(activeLocale, versions.length) },
              { label: labels.studentsSummaryTitle, value: `${localeNumber(activeLocale, values.students.length)} ${labels.studentsCountUnit}` }
            ]} />
            <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
              <h3 className="mb-3 text-lg font-black text-slate-950">{labels.printPreviewTitle}</h3>
              <div className="mb-3 text-xs text-slate-500">{labels.printSheetHint}</div>
              <div className="rounded-2xl border border-slate-100 bg-slate-50 p-3">
                <div className="mb-3 flex items-center justify-between gap-3 text-xs text-slate-500">
                  <span>{labels.printPaperLabel}</span>
                  <StatusPill tone="slate">{forms.builder.printModes.portrait}</StatusPill>
                </div>
                <div className="max-h-[780px] overflow-auto">
                  <div className="origin-top scale-[0.5]">
                    <PrintableFamilyRegistration locale={activeLocale} labels={labels} template={template} values={values} totalAmount={totalAmount} />
                  </div>
                </div>
              </div>
            </section>
            <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
              <h3 className="mb-3 text-lg font-black text-slate-950">{labels.versionListTitle}</h3>
              <div className="space-y-2 text-sm text-slate-600">
                {versions.length ? versions.map((version, index) => (
                  <div key={version.version_id || version.version_label || index} className="rounded-2xl border border-slate-200 px-3 py-3">
                    <div className="font-bold text-slate-900">{version.version_label || version.label || version.saved_at || 'version'}</div>
                    <div className="text-xs text-slate-500">{version.saved_at || version.source || 'rpc'}</div>
                  </div>
                )) : <div>{labels.noVersions}</div>}
              </div>
            </section>
          </aside>
        </div>
      </section>

      <section className="print-only py-6">
        <PrintableFamilyRegistration locale={activeLocale} labels={labels} template={template} values={values} totalAmount={totalAmount} />
        <div className="mx-auto mt-4 w-full max-w-[794px] rounded-2xl border border-brand-100 bg-brand-50 px-4 py-3 text-sm text-brand-800">{labels.printReceiptBanner}</div>
      </section>
    </main>
  );
}

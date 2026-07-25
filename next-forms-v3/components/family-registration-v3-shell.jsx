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
const DEFAULT_PLAN_START_DATE = '2026-09-10';
const PLAN_COUNTS = { two: 2, three: 3, four: 4, six: 6, monthly: 9, quarterly: 3, custom: null };
const PAYMENT_METHOD_OPTIONS = [
  { value: 'cash', label: { ar: 'نقدي', fa: 'نقدی', en: 'Cash' } },
  { value: 'bank_transfer', label: { ar: 'حساب بنكي', fa: 'واریز بانکی', en: 'Bank Transfer' } },
  { value: 'hawala', label: { ar: 'حوالة', fa: 'حواله', en: 'Hawala' } },
  { value: 'card', label: { ar: 'سحب بطاقة', fa: 'کارت‌خوان', en: 'Card / POS' } }
];
const FORM_STEPS = { registration: 'registration', finance: 'finance' };
const SCHOOL_WATERMARK_SRC = '/branding/ameen-school-logo-watermark.png';
const SCHOOL_YEAR_LABEL = '2026-2027';
const PRINT_COPY = {
  ar: {
    schoolName: 'مجمع أمين الرضا التعليمي',
    generatedFrom: 'نموذج احترافي منظم يختصر التكرار ويُبقي بيانات الطالب والماليات مفصولة بوضوح.',
    familyQuickSummary: 'ملخص عائلي سريع',
    studentsCountLabel: 'عدد الطلاب',
    documentStatusTitle: 'حالة الوثائق والاعتماد',
    sharedPaymentsTitle: 'سجل الدفعات المستلمة',
    studentPaymentsTitle: 'دفعات مرتبطة بهذا الطالب',
    noPayments: 'لا توجد دفعات مسجلة حالياً.',
    generatedNotice: 'هذه الصفحات مولدة من التسجيل الجديد: بيانات الطالب مستقلة، والماليات تأتي خلفها في صفحة منفصلة.',
    planScheduleTitle: 'جدول الأقساط المتوقع',
    guardianSignatureLabel: 'توقيع ولي الأمر',
    registrationOfficerLabel: 'اعتماد التسجيل',
    financeOfficerLabel: 'اعتماد المالية',
    pageProfileHint: 'صفحة بيانات الطالب',
    pageFinanceHint: 'صفحة الماليات الخاصة بالطالب',
    requestReferenceLabel: 'مرجع الطلب',
    generatedOnLabel: 'تاريخ الطباعة',
    officialUseTitle: 'اعتماد واستعمال إداري',
    approvalNote: 'هذه النسخة منظمة لتسهيل المراجعة والطباعة دون تكرار أو التباس بين بيانات الطالب والماليات.',
    draftReference: 'مسودة قبل الإرسال',
    studentDataTitle: 'بيانات الطالب الأساسية',
    familyLinkTitle: 'صلة الطالب بالعائلة',
    financeStatusTitle: 'الوضع المالي المختصر',
    remainingForStudentLabel: 'المتبقي على الطالب',
    organizationalNoteLabel: 'ملاحظة تنظيمية'
  },
  fa: {
    schoolName: 'مجتمع آموزشی امین‌الرضا',
    generatedFrom: 'فرم حرفه‌ای و منظم که تکرار را حذف می‌کند و اطلاعات دانش‌آموز و مالی را جدا نگه می‌دارد.',
    familyQuickSummary: 'خلاصه سریع خانواده',
    studentsCountLabel: 'تعداد دانش‌آموزان',
    documentStatusTitle: 'وضعیت مدارک و تأیید',
    sharedPaymentsTitle: 'ثبت پرداخت‌های دریافتی',
    studentPaymentsTitle: 'پرداخت‌های مرتبط با این دانش‌آموز',
    noPayments: 'در حال حاضر پرداختی ثبت نشده است.',
    generatedNotice: 'این صفحات از ثبت‌نام جدید ساخته می‌شوند: اطلاعات دانش‌آموز مستقل است و صفحه مالی جداگانه در پشت آن می‌آید.',
    planScheduleTitle: 'جدول مورد انتظار اقساط',
    guardianSignatureLabel: 'امضای ولی',
    registrationOfficerLabel: 'تأیید ثبت‌نام',
    financeOfficerLabel: 'تأیید مالی',
    pageProfileHint: 'صفحه اطلاعات دانش‌آموز',
    pageFinanceHint: 'صفحه مالی مخصوص دانش‌آموز',
    requestReferenceLabel: 'مرجع درخواست',
    generatedOnLabel: 'تاریخ چاپ',
    officialUseTitle: 'تأیید و استفاده اداری',
    approvalNote: 'این نسخه برای مرور و چاپ شفاف طراحی شده تا بین اطلاعات دانش‌آموز و مالی تداخل ایجاد نشود.',
    draftReference: 'پیش‌نویس قبل از ارسال',
    studentDataTitle: 'اطلاعات اصلی دانش‌آموز',
    familyLinkTitle: 'ارتباط دانش‌آموز با خانواده',
    financeStatusTitle: 'وضعیت مالی خلاصه',
    remainingForStudentLabel: 'مانده دانش‌آموز',
    organizationalNoteLabel: 'یادداشت اجرایی'
  },
  en: {
    schoolName: 'Amin Al-Ridha Educational Complex',
    generatedFrom: 'A professional structured format that removes repetition and keeps student data clearly separated from finance.',
    familyQuickSummary: 'Quick Family Summary',
    studentsCountLabel: 'Students Count',
    documentStatusTitle: 'Documents & Approval Status',
    sharedPaymentsTitle: 'Received Payments Register',
    studentPaymentsTitle: 'Payments Linked to This Student',
    noPayments: 'No payments are recorded yet.',
    generatedNotice: 'These pages are generated from the new registration flow: the student profile is separate and the finance page follows behind it.',
    planScheduleTitle: 'Expected Installment Schedule',
    guardianSignatureLabel: 'Guardian Signature',
    registrationOfficerLabel: 'Registration Approval',
    financeOfficerLabel: 'Finance Approval',
    pageProfileHint: 'Student profile page',
    pageFinanceHint: 'Student finance page',
    requestReferenceLabel: 'Request Reference',
    generatedOnLabel: 'Printed On',
    officialUseTitle: 'Administrative Use & Approval',
    approvalNote: 'This print version is organized for review and filing without duplicating student and finance details.',
    draftReference: 'Draft before submission',
    studentDataTitle: 'Core Student Details',
    familyLinkTitle: 'Student & Family Link',
    financeStatusTitle: 'Finance Snapshot',
    remainingForStudentLabel: 'Student Remaining Balance',
    organizationalNoteLabel: 'Operational Note'
  }
};

function blankPaymentRows() {
  return [];
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

function planCountForType(planType, currentValue = 1) {
  const mapped = PLAN_COUNTS[planType];
  if (mapped == null) return Math.max(1, Number(currentValue) || 1);
  return mapped;
}

function addMonthsToIso(isoDate, monthsToAdd) {
  if (!isoDate) return '';
  const date = new Date(`${isoDate}T00:00:00`);
  if (Number.isNaN(date.getTime())) return '';
  const baseDay = date.getDate();
  date.setMonth(date.getMonth() + monthsToAdd);
  while (date.getDate() < baseDay) {
    date.setDate(date.getDate() - 1);
  }
  return date.toISOString().slice(0, 10);
}

function buildFinanceSchedulePreview(annualFee, planType, installmentsCount, startDate) {
  const safeCount = Math.max(1, Number(installmentsCount) || 1);
  const total = Number(annualFee || 0);
  const rows = [];
  if (!total || !startDate) return rows;
  const intervalMonths = planType === 'quarterly' ? 3 : 1;
  let remaining = Math.round(total * 100) / 100;
  for (let index = 1; index <= safeCount; index += 1) {
    const dueAmount = index === safeCount ? Math.round(remaining * 100) / 100 : Math.round((total / safeCount) * 100) / 100;
    remaining = Math.round((remaining - dueAmount) * 100) / 100;
    rows.push({
      installment_number: index,
      due_date: addMonthsToIso(startDate, (index - 1) * intervalMonths),
      amount_due: dueAmount
    });
  }
  return rows;
}

function normalizePaymentAmountToUsd(row) {
  const amount = Number(String(row?.amount || '').replace(/,/g, '').trim());
  if (!Number.isFinite(amount) || amount <= 0) return 0;
  if (String(row?.currency || 'USD').toUpperCase() === 'IRR') {
    const exchangeRate = Number(String(row?.exchange_rate || '').replace(/,/g, '').trim());
    if (!Number.isFinite(exchangeRate) || exchangeRate <= 0) return 0;
    return Math.round(((amount / exchangeRate) + Number.EPSILON) * 100) / 100;
  }
  return Math.round((amount + Number.EPSILON) * 100) / 100;
}

function buildDynamicPaymentRows(students, existingRows = [], financeCatalogMap = new Map()) {
  const existingMap = new Map((existingRows || []).map((row) => [String(row.id), row]));
  const generated = [];

  (students || []).forEach((student) => {
    const financeItem = financeCatalogMap.get(String(student.student_grade || '')) || null;
    const installmentsCount = planCountForType(student.finance_plan_type || 'monthly', student.finance_installments_count || 1);
    const schedule = buildFinanceSchedulePreview(Number(financeItem?.annual_fee || 0), student.finance_plan_type || 'monthly', installmentsCount, student.finance_plan_start_date || DEFAULT_PLAN_START_DATE);

    if (!schedule.length) {
      const fallbackId = `payment_${student.id}_1`;
      const existing = existingMap.get(fallbackId) || {};
      generated.push({
        id: fallbackId,
        student_ref: student.id,
        installment_number: 1,
        expected_due_date: student.finance_plan_start_date || DEFAULT_PLAN_START_DATE,
        expected_amount_usd: '',
        payment_date: existing.payment_date || '',
        payment_method: existing.payment_method || 'cash',
        currency: existing.currency || 'USD',
        exchange_rate: existing.exchange_rate || '',
        amount: existing.amount || '',
        receiver_name: existing.receiver_name || '',
        card_number: existing.card_number || '',
        tracking_number: existing.tracking_number || '',
        reference: existing.reference || '',
        notes: existing.notes || ''
      });
      return;
    }

    schedule.forEach((item) => {
      const rowId = `payment_${student.id}_${item.installment_number}`;
      const existing = existingMap.get(rowId) || {};
      generated.push({
        id: rowId,
        student_ref: student.id,
        installment_number: item.installment_number,
        expected_due_date: existing.expected_due_date || item.due_date || '',
        expected_amount_usd: item.amount_due,
        payment_date: existing.payment_date || '',
        payment_method: existing.payment_method || 'cash',
        currency: existing.currency || 'USD',
        exchange_rate: existing.exchange_rate || '',
        amount: existing.amount || '',
        receiver_name: existing.receiver_name || '',
        card_number: existing.card_number || '',
        tracking_number: existing.tracking_number || '',
        reference: existing.reference || '',
        notes: existing.notes || ''
      });
    });
  });

  return generated;
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
  // Credentials are generated once by the protected admin activation RPC.
  // Never derive or store a password from a student's birth date.
  delete student.student_initial_password;
  student.finance_plan_type = 'monthly';
  student.finance_installments_count = '9';
  student.finance_plan_start_date = DEFAULT_PLAN_START_DATE;
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

function sanitizeStudentsForSubmit(students, financeCatalogMap = new Map()) {
  return students.map((student) => {
    const finance = financeCatalogMap.get(String(student.student_grade || '')) || null;
    const installmentsCount = planCountForType(student.finance_plan_type, student.finance_installments_count || 1);
    const annualFee = Number(finance?.annual_fee || 0);
    return {
      id: student.id,
      student_given_name: student.student_given_name,
      student_father_name: student.student_father_name,
      student_family_name: student.student_family_name,
      student_full_name: student.student_full_name,
      student_birth_date: student.student_birth_date,
      student_gender: student.student_gender,
      student_grade: student.student_grade,
      student_class_id: student.student_grade || null,
      student_class_label: finance?.class_name || null,
      student_section: student.student_section,
      student_birth_place: student.student_birth_place,
      student_passport_number: student.student_passport_number,
      student_passport_expiry_date: student.student_passport_expiry_date,
      student_previous_school: student.student_previous_school,
      student_address_mashhad: student.student_address_mashhad,
      student_address_iraq: student.student_address_iraq,
      student_health_notes: student.student_health_notes,
      student_photo: sanitizeFileMeta(student.student_photo),
      student_passport_attachment: sanitizeFileMeta(student.student_passport_attachment),
      student_academic_documents: sanitizeFileMeta(student.student_academic_documents),
      student_username: student.student_username,
      finance_fee_structure_id: finance?.fee_structure_id || null,
      finance_currency: finance?.currency || 'USD',
      finance_academic_year: finance?.academic_year || '2026-2027',
      annual_fee_snapshot: annualFee,
      monthly_fee_snapshot: Number(finance?.monthly_fee || 0),
      finance_plan_type: student.finance_plan_type || 'monthly',
      finance_installments_count: installmentsCount,
      finance_plan_start_date: student.finance_plan_start_date || DEFAULT_PLAN_START_DATE,
      finance_installment_schedule: buildFinanceSchedulePreview(annualFee, student.finance_plan_type || 'monthly', installmentsCount, student.finance_plan_start_date || DEFAULT_PLAN_START_DATE)
    };
  });
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

    normalizedStudent.finance_plan_type = normalizedStudent.finance_plan_type || 'monthly';
    normalizedStudent.finance_installments_count = String(planCountForType(normalizedStudent.finance_plan_type, normalizedStudent.finance_installments_count || 1));
    normalizedStudent.finance_plan_start_date = normalizedStudent.finance_plan_start_date || DEFAULT_PLAN_START_DATE;
    delete normalizedStudent.student_initial_password;
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
  return rows.reduce((sum, row) => sum + normalizePaymentAmountToUsd(row), 0);
}

function countErrors(fieldErrors, studentErrors, globalErrors) {
  const familyErrorsCount = Object.values(fieldErrors).filter(Boolean).length;
  const studentErrorsCount = Object.values(studentErrors).reduce((sum, errors) => sum + Object.values(errors || {}).filter(Boolean).length, 0);
  return familyErrorsCount + studentErrorsCount + globalErrors.length;
}

function countReadyStudents(template, students) {
  const requiredStudentFields = (template.studentCardFields || []).filter((field) => field.required).map((field) => field.id);
  return (students || []).filter((student) => requiredStudentFields.every((fieldId) => String(student[fieldId] || '').trim())).length;
}

function countStudentManualOverrides(students) {
  return (students || []).reduce((sum, student) => {
    return sum
      + Number(Boolean(student._meta?.fatherManual))
      + Number(Boolean(student._meta?.familyManual))
      + Number(Boolean(student._meta?.fullNameManual))
      + Number(Boolean(student._meta?.usernameManual));
  }, 0);
}

function countStudentInheritedLinks(students) {
  return (students || []).reduce((sum, student) => {
    return sum
      + Number(!student._meta?.fatherManual)
      + Number(!student._meta?.familyManual);
  }, 0);
}

function optionLabelForValue(field, value, locale) {
  if (!field || value == null || value === '') return '';
  const option = (field.options || []).find((item) => item.value === value);
  return option?.label?.[locale] || String(value || '');
}

function nonEmptyPaymentRows(rows) {
  return (rows || []).filter((row) => [row.card_number, row.tracking_number, row.reference, row.payment_date, row.amount, row.notes, row.receiver_name].some((value) => String(value || '').trim()));
}

function directPaymentRowsForStudent(rows, studentId) {
  return nonEmptyPaymentRows(rows).filter((row) => row.student_ref === studentId);
}

function sharedFamilyPaymentRows(rows) {
  return nonEmptyPaymentRows(rows).filter((row) => !String(row.student_ref || '').trim());
}

function sumPaymentRows(rows) {
  return (rows || []).reduce((sum, row) => sum + (Number(row.amount || 0) || 0), 0);
}

function studentFileKey(studentId, fieldId) {
  return `${studentId}:${fieldId}`;
}

function validateValues(template, values, labels, options = {}) {
  const fieldErrors = {};
  const studentErrors = {};
  const globalErrors = [];
  const requirePreparedUpload = options.requirePreparedUpload;
  const includeSections = Array.isArray(options.includeSections) && options.includeSections.length
    ? new Set(options.includeSections)
    : null;

  template.fields.forEach((field) => {
    if (includeSections && !includeSections.has(field.section)) return;

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

  const relevantStudentFields = (template.studentCardFields || []).filter((field) => !includeSections || includeSections.has(field.section));

  (values.students || []).forEach((student) => {
    const perStudentErrors = {};
    relevantStudentFields.forEach((field) => {
      const value = student[field.id];
      if (field.required && !String(value || '').trim()) {
        perStudentErrors[field.id] = labels.requiredField;
        return;
      }
      if (field.type === 'file' && value) {
        if (value.size > MAX_FILE_SIZE) perStudentErrors[field.id] = labels.fileTooLarge;
        if (field.accept && value.name) {
          const accepted = field.accept.split(',').map((item) => item.trim().toLowerCase());
          const lowerName = value.name.toLowerCase();
          const matches = accepted.some((item) => lowerName.endsWith(item.replace('*', '')));
          if (!matches) perStudentErrors[field.id] = labels.invalidFileType;
        }
      }
      // SEDA code validation - 10 digits
      if (field.id === 'student_seda_code' && value) {
        if (!/^[0-9]{10}$/.test(String(value).trim())) {
          perStudentErrors[field.id] = labels.sedaCodeInvalid || 'كود سيدا يجب أن يكون 10 أرقام';
        }
      }
    });

    if (Object.keys(perStudentErrors).length) {
      studentErrors[student.id] = perStudentErrors;
    }
  });

  if ((!includeSections || includeSections.has('students')) && !values.students.length) {
    globalErrors.push(labels.studentsEmpty);
  }

  if (!includeSections || includeSections.has('students')) {
    const duplicates = duplicateStudentNames(values.students || []);
    if (duplicates.length) {
      globalErrors.push(labels.duplicateStudentNames);
    }
  }

  if ((!includeSections || includeSections.has('approval')) && values.applicant_relation === 'other' && !String(values.applicant_other_relation || '').trim()) {
    fieldErrors.applicant_other_relation = labels.requiredField;
  }

  if (!includeSections || includeSections.has('finance')) {
    (values.payment_entries || []).forEach((row, index) => {
      const hasAmount = Number(String(row.amount || '').replace(/,/g, '').trim()) > 0;
      if (!hasAmount) return;
      if (!String(row.receiver_name || '').trim()) {
        globalErrors.push(`${labels.paymentReceiverRequired} #${index + 1}`);
      }
      if (String(row.currency || 'USD').toUpperCase() === 'IRR' && !(Number(String(row.exchange_rate || '').replace(/,/g, '').trim()) > 0)) {
        globalErrors.push(`${labels.paymentExchangeRateRequired} #${index + 1}`);
      }
    });
  }

  return { fieldErrors, studentErrors, globalErrors };
}

function SectionCard({ title, subtitle, children, anchorId }) {
  return (
    <section id={anchorId} className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
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

  const inputType = field.id.includes('phone') ? 'tel' : field.type === 'number' ? 'number' : 'text';

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
      <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="text-sm font-black text-slate-900">{labels.paymentTableTitle}</div>
          <div className="text-xs leading-6 text-slate-500">{labels.paymentDynamicHint}</div>
        </div>
        <StatusPill tone="brand">{labels.paymentTotal}: {localeNumber(locale, totalAmount)} USD</StatusPill>
      </div>
      <div className="overflow-x-auto rounded-2xl border border-slate-200 bg-white">
        <table className="min-w-[1550px] border-collapse text-sm">
          <thead>
            <tr className="bg-slate-50 text-slate-700">
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.row}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.student}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.installment}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.expectedDate}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.expectedAmountUsd}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.method}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.currency}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.exchangeRate}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.amount}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.amountUsd}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.receiver}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.cardNumber}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.trackingNumber}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.reference}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.date}</th>
              <th className="border border-slate-200 px-2 py-2">{labels.paymentColumns.notes}</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row, index) => {
              const studentName = students.find((student) => student.id === row.student_ref)?.student_full_name || labels.studentCardTitle;
              const amountUsd = normalizePaymentAmountToUsd(row);
              return (
                <tr key={row.id} className="bg-white align-top">
                  <td className="border border-slate-200 px-2 py-2 text-center font-bold">{localeNumber(locale, index + 1)}</td>
                  <td className="border border-slate-200 px-2 py-2 font-semibold text-slate-800">{studentName}</td>
                  <td className="border border-slate-200 px-2 py-2 text-center">{localeNumber(locale, row.installment_number || index + 1)}</td>
                  <td className="border border-slate-200 px-2 py-2"><input type="date" value={row.expected_due_date || ''} onChange={(event) => onChange(index, 'expected_due_date', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                  <td className="border border-slate-200 px-2 py-2 text-center font-semibold text-slate-900">{row.expected_amount_usd ? `${localeNumber(locale, row.expected_amount_usd)} USD` : labels.emptyValue}</td>
                  <td className="border border-slate-200 px-2 py-2">
                    <select value={row.payment_method || 'cash'} onChange={(event) => onChange(index, 'payment_method', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2">
                      {PAYMENT_METHOD_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label?.[locale] || option.value}</option>)}
                    </select>
                  </td>
                  <td className="border border-slate-200 px-2 py-2">
                    <select value={row.currency || 'USD'} onChange={(event) => onChange(index, 'currency', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2">
                      <option value="USD">USD</option>
                      <option value="IRR">IRR</option>
                    </select>
                  </td>
                  <td className="border border-slate-200 px-2 py-2"><input type="number" value={row.exchange_rate || ''} onChange={(event) => onChange(index, 'exchange_rate', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" placeholder={labels.paymentColumns.exchangeRatePlaceholder} /></td>
                  <td className="border border-slate-200 px-2 py-2"><input type="number" value={row.amount || ''} onChange={(event) => onChange(index, 'amount', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                  <td className="border border-slate-200 px-2 py-2 text-center font-semibold text-slate-900">{amountUsd ? `${localeNumber(locale, amountUsd)} USD` : labels.emptyValue}</td>
                  <td className="border border-slate-200 px-2 py-2"><input value={row.receiver_name || ''} onChange={(event) => onChange(index, 'receiver_name', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                  <td className="border border-slate-200 px-2 py-2"><input value={row.card_number || ''} onChange={(event) => onChange(index, 'card_number', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                  <td className="border border-slate-200 px-2 py-2"><input value={row.tracking_number || ''} onChange={(event) => onChange(index, 'tracking_number', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                  <td className="border border-slate-200 px-2 py-2"><input value={row.reference || ''} onChange={(event) => onChange(index, 'reference', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                  <td className="border border-slate-200 px-2 py-2"><input type="date" value={row.payment_date || ''} onChange={(event) => onChange(index, 'payment_date', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                  <td className="border border-slate-200 px-2 py-2"><input value={row.notes || ''} onChange={(event) => onChange(index, 'notes', event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-2 py-2" /></td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
function StudentCard({ locale, labels, student, index, fieldById, financeCatalogMap, studentErrors, onFieldChange, onRestoreInheritance, onRemove, onDuplicate, canRemove }) {
  const inheritedFather = !student._meta?.fatherManual;
  const inheritedFamily = !student._meta?.familyManual;
  const autoFullName = !student._meta?.fullNameManual;
  const selectedGrade = financeCatalogMap.get(String(student.student_grade || ''))?.class_name
    || optionLabelForValue(fieldById.get('student_grade'), student.student_grade, locale)
    || labels.emptyValue;

  const editableFields = [
    'student_seda_code',
    'student_type',
    'student_birth_date',
    'student_birth_date_shamsi_display',
    'student_gender',
    'student_grade',
    'student_section',
    'student_birth_place',
    'student_passport_number',
    'student_passport_expiry_date',
    'student_passport_days_remaining',
    'student_previous_school',
    'student_address_mashhad',
    'student_address_iraq',
    'student_health_notes',
    'student_photo'
  ];

  // Helper: Gregorian to Shamsi conversion using Intl
  function gregorianToShamsi(iso) {
    if (!iso) return '';
    try {
      const d = new Date(iso + 'T00:00:00');
      if (isNaN(d.getTime())) return '';
      return new Intl.DateTimeFormat('fa-IR-u-ca-persian', { year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
    } catch { return ''; }
  }
  
  function calculatePassportDaysRemaining(expiryIso) {
    if (!expiryIso) return '';
    try {
      const today = new Date(); today.setHours(0,0,0,0);
      const expiry = new Date(expiryIso + 'T00:00:00');
      const diff = Math.ceil((expiry - today) / 86400000);
      if (diff < 0) return `منتهي منذ ${Math.abs(diff)} يوم`;
      if (diff < 30) return `${diff} يوم - ينتهي قريباً 🔴`;
      if (diff < 90) return `${diff} يوم - انتبه 🟡`;
      return `${diff} يوم - صالح 🟢`;
    } catch { return ''; }
  }

  function isValidSedaCode(code) {
    if (!code) return true;
    return /^[0-9]{10}$/.test(String(code).trim());
  }

  return (
    <div className="rounded-[24px] border border-slate-200 bg-slate-50 p-4">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 pb-3">
        <div>
          <h3 className="text-lg font-black text-slate-950">{labels.studentCardTitle} {localeNumber(locale, index + 1)}</h3>
          <p className="mt-1 text-xs leading-6 text-slate-500">{labels.generatedCredentialsHint}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button type="button" onClick={() => onRestoreInheritance(student.id)} className="rounded-2xl border border-brand-200 bg-brand-50 px-3 py-2 text-xs font-bold text-brand-800">{labels.restoreInheritance}</button>
          <button type="button" onClick={() => onDuplicate(student.id)} className="rounded-2xl border border-slate-200 bg-white px-3 py-2 text-xs font-bold text-slate-700">{labels.duplicateStudent}</button>
          {canRemove ? <button type="button" onClick={() => onRemove(student.id)} className="rounded-2xl border border-rose-200 bg-rose-50 px-3 py-2 text-xs font-bold text-rose-700">{labels.removeStudent}</button> : null}
        </div>
      </div>

      <div className="mb-4 rounded-2xl border border-blue-100 bg-blue-50 px-4 py-4 text-sm leading-7 text-blue-900">
        <div className="font-black">{labels.stepRegistrationTitle}</div>
        <div className="mt-1 text-xs text-blue-800">{labels.studentDataStepHint}</div>
      </div>

      <div className="mb-4 rounded-2xl border border-slate-200 bg-white px-4 py-4">
        <div className="mb-2 text-xs font-bold text-slate-500">{labels.cardPreviewTitle}</div>
        <div className="flex flex-wrap gap-2">
          <StatusPill tone={autoFullName ? 'brand' : 'warning'}>{labels.cardComputedName}: {student.student_full_name || labels.emptyValue}</StatusPill>
          <StatusPill tone="slate">{labels.cardUsername}: {student.student_username || labels.emptyValue}</StatusPill>
          <StatusPill tone="slate">{labels.cardPassword}: {labels.generatedAtActivation}</StatusPill>
          <StatusPill tone="success">{fieldById.get('student_grade')?.label?.[locale]}: {selectedGrade}</StatusPill>
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
          const originalField = fieldById.get(fieldId);
          const field = fieldId === 'student_grade'
            ? {
                ...originalField,
                options: financeCatalogMap.size
                  ? Array.from(financeCatalogMap.values()).map((item) => ({ id: item.class_id, value: item.class_id, label: { ar: item.class_name, fa: item.class_name, en: item.class_name } }))
                  : (originalField?.options || [])
              }
            : originalField;

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
      </div>
    </div>
  );
}

function FinanceStudentCard({ locale, labels, student, index, fieldById, financeCatalogMap, onFieldChange }) {
  const financeItem = financeCatalogMap.get(String(student.student_grade || '')) || null;
  const financePlanCount = planCountForType(student.finance_plan_type || 'monthly', student.finance_installments_count || 1);
  const financeSchedule = buildFinanceSchedulePreview(Number(financeItem?.annual_fee || 0), student.finance_plan_type || 'monthly', financePlanCount, student.finance_plan_start_date || DEFAULT_PLAN_START_DATE);
  const classLabel = financeItem?.class_name || optionLabelForValue(fieldById.get('student_grade'), student.student_grade, locale) || labels.emptyValue;

  return (
    <div className="rounded-[24px] border border-slate-200 bg-slate-50 p-4">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 pb-3">
        <div>
          <h3 className="text-lg font-black text-slate-950">{labels.studentCardTitle} {localeNumber(locale, index + 1)} — {student.student_full_name || labels.emptyValue}</h3>
          <p className="mt-1 text-xs leading-6 text-slate-500">{labels.financeStepIntroDescription}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <StatusPill tone={financeItem ? 'success' : 'warning'}>{fieldById.get('student_grade')?.label?.[locale]}: {classLabel}</StatusPill>
          <StatusPill tone="slate">{labels.cardUsername}: {student.student_username || labels.emptyValue}</StatusPill>
        </div>
      </div>

      <div className="mb-4 rounded-2xl border border-slate-200 bg-white px-4 py-4">
        <div className="mb-2 text-xs font-bold text-slate-500">{labels.financeIntegrationTitle}</div>
        <div className="flex flex-wrap gap-2">
          <StatusPill tone={financeItem ? 'success' : 'warning'}>{labels.classFeeLabel}: {financeItem ? `${localeNumber(locale, Number(financeItem.annual_fee || 0))} ${financeItem.currency}` : labels.classFeeMissing}</StatusPill>
          <StatusPill tone="slate">{labels.planCountLabel}: {localeNumber(locale, financePlanCount)}</StatusPill>
        </div>
        <div className="mt-3 text-xs leading-6 text-slate-500">
          {financeItem ? labels.classFeeFetchedFromFinance : labels.classFeeCatalogPending}
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <InputField field={fieldById.get('finance_plan_type')} locale={locale} value={student.finance_plan_type} error={null} onChange={(fieldId, value) => onFieldChange(student.id, fieldId, value)} labels={labels} />
        <InputField field={fieldById.get('finance_installments_count')} locale={locale} value={student.finance_installments_count} error={null} onChange={(fieldId, value) => onFieldChange(student.id, fieldId, value)} labels={labels} />
        <InputField field={fieldById.get('finance_plan_start_date')} locale={locale} value={student.finance_plan_start_date} error={null} onChange={(fieldId, value) => onFieldChange(student.id, fieldId, value)} labels={labels} />
      </div>

      <div className="mt-4 rounded-2xl border border-slate-200 bg-white p-4">
        <div className="mb-3 text-sm font-black text-slate-900">{labels.installmentPreviewTitle}</div>
        {financeSchedule.length ? (
          <div className="space-y-2">
            {financeSchedule.map((item) => (
              <div key={`${student.id}-${item.installment_number}`} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-slate-200 bg-slate-50 px-3 py-3 text-xs">
                <span>{labels.installmentLabelPrefix} {localeNumber(locale, item.installment_number)}</span>
                <span>{item.due_date ? formatDateForLocale(locale, item.due_date) : labels.emptyValue}</span>
                <b>{localeNumber(locale, item.amount_due)} {financeItem?.currency || 'USD'}</b>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-xs leading-6 text-slate-500">{labels.installmentPreviewEmpty}</div>
        )}
      </div>
    </div>
  );
}

function PrintPageShell({ locale, title, subtitle, hint, metaLabel, metaValue, children, pageBreak = true }) {
  const copy = PRINT_COPY[locale] || PRINT_COPY.ar;

  return (
    <section
      style={pageBreak ? { breakAfter: 'page', pageBreakAfter: 'always' } : undefined}
      className="relative mx-auto w-full max-w-[794px] overflow-hidden rounded-[30px] border border-[#c9a24b] bg-white px-6 py-6 shadow-sm"
    >
      <div className="pointer-events-none absolute inset-[10px] rounded-[24px] border border-[#ead9aa]" />
      <div className="pointer-events-none absolute inset-0 opacity-50">
        <div className="absolute left-4 top-4 h-8 w-8 rounded-tl-[18px] border-l-2 border-t-2 border-[#c9a24b]" />
        <div className="absolute right-4 top-4 h-8 w-8 rounded-tr-[18px] border-r-2 border-t-2 border-[#c9a24b]" />
        <div className="absolute bottom-4 left-4 h-8 w-8 rounded-bl-[18px] border-b-2 border-l-2 border-[#c9a24b]" />
        <div className="absolute bottom-4 right-4 h-8 w-8 rounded-br-[18px] border-b-2 border-r-2 border-[#c9a24b]" />
      </div>
      <div className="pointer-events-none absolute inset-0 flex items-center justify-center px-10">
        <div className="h-[78%] w-full bg-contain bg-center bg-no-repeat opacity-[0.07]" style={{ backgroundImage: `url(${SCHOOL_WATERMARK_SRC})` }} />
      </div>
      <div className="relative z-10">
        <div className="grid grid-cols-[92px_1fr_92px] items-center gap-3 border-b border-[#e8dcc2] pb-4">
          <div className="flex justify-start">
            <div className="h-16 w-16 bg-contain bg-left bg-no-repeat opacity-90" style={{ backgroundImage: `url(${SCHOOL_WATERMARK_SRC})` }} />
          </div>
          <div className="text-center">
            <div className="text-[12px] font-black tracking-wide text-slate-700">{copy.schoolName}</div>
            <div className="mt-1 text-[10px] font-semibold text-slate-500">{SCHOOL_YEAR_LABEL}</div>
            <div className="mt-3 text-[18px] font-black text-slate-950">{title}</div>
            {subtitle ? <div className="mt-1 text-[11px] font-semibold text-slate-700">{subtitle}</div> : null}
            {hint ? <div className="mt-2 text-[10px] leading-5 text-slate-500">{hint}</div> : null}
          </div>
          <div className="flex justify-end">
            <div className="rounded-[16px] border border-slate-300 bg-white/90 px-3 py-2 text-center">
              <div className="text-[9px] font-black text-slate-500">{metaLabel || copy.generatedOnLabel}</div>
              <div className="mt-1 text-[11px] font-semibold text-slate-800">{metaValue || localeDateLabel(locale)}</div>
            </div>
          </div>
        </div>
        <div className="mt-5">{children}</div>
      </div>
    </section>
  );
}

function PrintMetric({ label, value }) {
  return (
    <div className="rounded-[16px] border border-slate-300 bg-white/90 px-3 py-3">
      <div className="text-[10px] font-black tracking-wide text-slate-500">{label}</div>
      <div className="mt-1 text-[13px] font-semibold leading-6 text-slate-900">{value || '—'}</div>
    </div>
  );
}

function PrintSectionBlock({ title, hint, children }) {
  return (
    <section className="rounded-[22px] border border-slate-300 bg-white/90 p-4">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2 border-b border-slate-200 pb-2">
        <h3 className="text-[13px] font-black text-slate-900">{title}</h3>
        {hint ? <span className="text-[10px] font-bold text-slate-500">{hint}</span> : null}
      </div>
      {children}
    </section>
  );
}

function PrintCheckItem({ checked, label }) {
  return (
    <div className={`rounded-[14px] border px-3 py-3 text-[12px] font-semibold ${checked ? 'border-emerald-300 bg-emerald-50 text-emerald-900' : 'border-slate-300 bg-slate-50 text-slate-700'}`}>
      {checked ? '☑' : '☐'} {label}
    </div>
  );
}

function PrintableFamilyRegistration({ locale, labels, template, values, totalAmount, financeCatalogMap, receipt }) {
  const copy = PRINT_COPY[locale] || PRINT_COPY.ar;
  const guardianFullName = computeGuardianFullName(values);
  const motherFullName = computeMotherFullName(values);
  const familyPaymentRows = nonEmptyPaymentRows(values.payment_entries || []);
  const printReference = receipt?.reportId || copy.draftReference;
  const expectedFamilyFeeTotal = values.students.reduce((sum, student) => sum + Number(financeCatalogMap.get(String(student.student_grade || ''))?.annual_fee || 0), 0);
  const remainingProjected = Math.max(expectedFamilyFeeTotal - totalAmount, 0);

  const familyField = (fieldId) => template.fields.find((field) => field.id === fieldId);
  const studentField = (fieldId) => template.studentCardFields.find((field) => field.id === fieldId);
  const familyValue = (fieldId, value) => {
    const field = familyField(fieldId);
    if (field?.type === 'select') return optionLabelForValue(field, value, locale);
    return value;
  };
  const studentValue = (fieldId, value) => {
    const field = studentField(fieldId);
    if (field?.type === 'select') return optionLabelForValue(field, value, locale);
    return value;
  };
  const applicantRelationDisplay = values.applicant_relation === 'other'
    ? (values.applicant_other_relation || familyValue('applicant_relation', values.applicant_relation))
    : familyValue('applicant_relation', values.applicant_relation);

  return (
    <div className="space-y-6 text-black">
      <PrintPageShell
        locale={locale}
        title={labels.familySheetTitle}
        subtitle={copy.familyQuickSummary}
        hint={copy.generatedFrom}
        metaLabel={copy.requestReferenceLabel}
        metaValue={printReference}
        pageBreak={values.students.length > 0}
      >
        <div className="grid gap-3 md:grid-cols-4">
          <PrintMetric label={labels.familySummaryTitle} value={guardianFullName} />
          <PrintMetric label={copy.studentsCountLabel} value={localeNumber(locale, values.students.length)} />
          <PrintMetric label={labels.expectedFeesLabel} value={localeNumber(locale, expectedFamilyFeeTotal)} />
          <PrintMetric label={labels.projectedRemainingLabel} value={localeNumber(locale, remainingProjected)} />
        </div>

        <div className="mt-5 grid gap-4 md:grid-cols-2">
          <PrintSectionBlock title={template.sections.find((section) => section.key === 'guardian')?.title?.[locale]}>
            <div className="grid gap-3 md:grid-cols-2">
              <PrintField label={familyField('guardian_given_name')?.label?.[locale]} value={values.guardian_given_name} />
              <PrintField label={familyField('guardian_father_name')?.label?.[locale]} value={values.guardian_father_name} />
              <PrintField label={familyField('family_name')?.label?.[locale]} value={values.family_name} />
              <PrintField label={familyField('guardian_username')?.label?.[locale]} value={values.guardian_username} />
              <PrintField label={familyField('guardian_phone_primary')?.label?.[locale]} value={values.guardian_phone_primary} />
              <PrintField label={familyField('guardian_phone_whatsapp')?.label?.[locale]} value={values.guardian_phone_whatsapp} />
              <PrintField label={familyField('guardian_phone_emergency')?.label?.[locale]} value={values.guardian_phone_emergency} />
              <PrintField label={familyField('guardian_nationality')?.label?.[locale]} value={familyValue('guardian_nationality', values.guardian_nationality)} />
              <PrintField label={familyField('residence_type')?.label?.[locale]} value={familyValue('residence_type', values.residence_type)} />
              <PrintField label={familyField('guardian_passport_number')?.label?.[locale]} value={values.guardian_passport_number} />
              <PrintField label={familyField('guardian_work_type')?.label?.[locale]} value={familyValue('guardian_work_type', values.guardian_work_type)} />
              <PrintField label={familyField('guardian_education_level')?.label?.[locale]} value={familyValue('guardian_education_level', values.guardian_education_level)} />
            </div>
          </PrintSectionBlock>

          <PrintSectionBlock title={template.sections.find((section) => section.key === 'mother')?.title?.[locale]}>
            <div className="grid gap-3 md:grid-cols-2">
              <PrintField label={familyField('mother_given_name')?.label?.[locale]} value={values.mother_given_name} />
              <PrintField label={familyField('mother_father_name')?.label?.[locale]} value={values.mother_father_name} />
              <PrintField label={familyField('mother_family_name')?.label?.[locale]} value={values.mother_family_name} />
              <PrintField label={familyField('mother_phone')?.label?.[locale]} value={values.mother_phone} />
              <PrintField label={familyField('mother_whatsapp')?.label?.[locale]} value={values.mother_whatsapp} />
              <PrintField label={familyField('mother_nationality')?.label?.[locale]} value={familyValue('mother_nationality', values.mother_nationality)} />
              <PrintField label={familyField('mother_work_type')?.label?.[locale]} value={familyValue('mother_work_type', values.mother_work_type)} />
              <PrintField label={familyField('mother_education_level')?.label?.[locale]} value={familyValue('mother_education_level', values.mother_education_level)} />
              <PrintField label={labels.documentsSummaryTitle} value={motherFullName || labels.emptyValue} wide />
            </div>
          </PrintSectionBlock>
        </div>

        <div className="mt-4 grid gap-4 md:grid-cols-[1.2fr_.8fr]">
          <PrintSectionBlock title={template.sections.find((section) => section.key === 'family_context')?.title?.[locale]}>
            <div className="grid gap-3">
              <PrintField label={familyField('living_with_in_iran')?.label?.[locale]} value={values.living_with_in_iran} />
              <PrintField label={familyField('general_family_health_notes')?.label?.[locale]} value={values.general_family_health_notes} />
            </div>
          </PrintSectionBlock>

          <PrintSectionBlock title={copy.documentStatusTitle}>
            <div className="grid gap-3">
              <PrintCheckItem checked={values.document_copy_received} label={familyField('document_copy_received')?.label?.[locale]} />
              <PrintCheckItem checked={values.document_original_received} label={familyField('document_original_received')?.label?.[locale]} />
              <PrintField label={familyField('document_notes')?.label?.[locale]} value={values.document_notes} />
              <PrintField label={familyField('applicant_relation')?.label?.[locale]} value={applicantRelationDisplay} />
              <PrintField label={familyField('applicant_name')?.label?.[locale]} value={values.applicant_name} />
            </div>
          </PrintSectionBlock>
        </div>

        <div className="mt-4 grid gap-4 md:grid-cols-[1.15fr_.85fr]">
          <PrintSectionBlock title={copy.officialUseTitle}>
            <div className="grid gap-3 md:grid-cols-2">
              <PrintField label={copy.requestReferenceLabel} value={printReference} />
              <PrintField label={copy.generatedOnLabel} value={localeDateLabel(locale)} />
              <PrintField label={copy.registrationOfficerLabel} value="" />
              <PrintField label={copy.financeOfficerLabel} value="" />
              <PrintField label={copy.organizationalNoteLabel} value={copy.approvalNote} wide />
            </div>
          </PrintSectionBlock>

          <PrintSectionBlock title={labels.financeSummaryTitle}>
            <div className="grid gap-3">
              <PrintField label={labels.paymentTotal} value={localeNumber(locale, totalAmount)} />
              <PrintField label={labels.expectedFeesLabel} value={localeNumber(locale, expectedFamilyFeeTotal)} />
              <PrintField label={labels.projectedRemainingLabel} value={localeNumber(locale, remainingProjected)} />
            </div>
          </PrintSectionBlock>
        </div>

        <div className="mt-4 grid gap-4">
          <PrintSectionBlock title={template.sections.find((section) => section.key === 'students')?.title?.[locale]}>
            <div className="overflow-hidden rounded-[14px] border border-slate-300 bg-white/95">
              <table className="min-w-full border-collapse text-[11px]">
                <thead>
                  <tr className="bg-slate-50 text-slate-700">
                    <th className="border border-slate-300 px-2 py-2">#</th>
                    <th className="border border-slate-300 px-2 py-2">{studentField('student_full_name')?.label?.[locale]}</th>
                    <th className="border border-slate-300 px-2 py-2">{studentField('student_grade')?.label?.[locale]}</th>
                    <th className="border border-slate-300 px-2 py-2">{studentField('student_gender')?.label?.[locale]}</th>
                    <th className="border border-slate-300 px-2 py-2">{studentField('student_username')?.label?.[locale]}</th>
                  </tr>
                </thead>
                <tbody>
                  {values.students.map((student, index) => (
                    <tr key={student.id}>
                      <td className="border border-slate-300 px-2 py-2 text-center">{localeNumber(locale, index + 1)}</td>
                      <td className="border border-slate-300 px-2 py-2 whitespace-pre-wrap break-words">{student.student_full_name || labels.emptyValue}</td>
                      <td className="border border-slate-300 px-2 py-2 whitespace-pre-wrap break-words">{financeCatalogMap.get(String(student.student_grade || ''))?.class_name || studentValue('student_grade', student.student_grade) || labels.emptyValue}</td>
                      <td className="border border-slate-300 px-2 py-2">{studentValue('student_gender', student.student_gender) || labels.emptyValue}</td>
                      <td className="border border-slate-300 px-2 py-2 whitespace-pre-wrap break-words">{student.student_username || labels.emptyValue}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </PrintSectionBlock>

          <PrintSectionBlock title={copy.sharedPaymentsTitle} hint={labels.paymentTableTitle}>
            {familyPaymentRows.length ? (
              <div className="overflow-hidden rounded-[14px] border border-slate-300 bg-white/95">
                <table className="min-w-full border-collapse text-[11px]">
                  <thead>
                    <tr className="bg-slate-50 text-slate-700">
                      <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.row}</th>
                      <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.student}</th>
                      <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.method}</th>
                      <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.currency}</th>
                      <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.amount}</th>
                      <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.amountUsd}</th>
                      <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.receiver}</th>
                      <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.date}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {familyPaymentRows.map((row, index) => (
                      <tr key={row.id}>
                        <td className="border border-slate-300 px-2 py-2 text-center">{localeNumber(locale, index + 1)}</td>
                        <td className="border border-slate-300 px-2 py-2 whitespace-pre-wrap break-words">{values.students.find((student) => student.id === row.student_ref)?.student_full_name || labels.emptyValue}</td>
                        <td className="border border-slate-300 px-2 py-2">{(PAYMENT_METHOD_OPTIONS.find((option) => option.value === row.payment_method)?.label || {})[locale] || row.payment_method || labels.emptyValue}</td>
                        <td className="border border-slate-300 px-2 py-2">{row.currency || labels.emptyValue}</td>
                        <td className="border border-slate-300 px-2 py-2">{row.amount ? localeNumber(locale, Number(row.amount)) : labels.emptyValue}</td>
                        <td className="border border-slate-300 px-2 py-2">{normalizePaymentAmountToUsd(row) ? localeNumber(locale, normalizePaymentAmountToUsd(row)) : labels.emptyValue}</td>
                        <td className="border border-slate-300 px-2 py-2 whitespace-pre-wrap break-words">{row.receiver_name || labels.emptyValue}</td>
                        <td className="border border-slate-300 px-2 py-2">{row.payment_date ? formatDateForLocale(locale, row.payment_date) : labels.emptyValue}</td>
                      </tr>
                    ))}
                    <tr className="bg-brand-50">
                      <td className="border border-slate-300 px-2 py-2 text-center font-black" colSpan={5}>{labels.paymentTotal}</td>
                      <td className="border border-slate-300 px-2 py-2 font-black">{localeNumber(locale, totalAmount)}</td>
                      <td className="border border-slate-300 px-2 py-2" colSpan={2} />
                    </tr>
                  </tbody>
                </table>
              </div>
            ) : (
              <div className="text-[12px] leading-7 text-slate-600">{copy.noPayments}</div>
            )}
          </PrintSectionBlock>
        </div>
      </PrintPageShell>

      {values.students.map((student, index) => {
        const financeItem = financeCatalogMap.get(String(student.student_grade || '')) || null;
        const planCount = planCountForType(student.finance_plan_type || 'monthly', student.finance_installments_count || 1);
        const schedule = buildFinanceSchedulePreview(Number(financeItem?.annual_fee || 0), student.finance_plan_type || 'monthly', planCount, student.finance_plan_start_date || DEFAULT_PLAN_START_DATE);
        const directPayments = directPaymentRowsForStudent(values.payment_entries || [], student.id);
        const classLabel = financeItem?.class_name || studentValue('student_grade', student.student_grade) || labels.emptyValue;

        const studentPaidTotal = sumPaymentRows(directPayments);
        const studentRemainingTotal = Math.max(Number(financeItem?.annual_fee || 0) - studentPaidTotal, 0);

        return (
          <div key={student.id} className="space-y-6">
            <PrintPageShell
              locale={locale}
              title={`${labels.studentAppendixTitle} ${localeNumber(locale, index + 1)}`}
              subtitle={student.student_full_name || labels.emptyValue}
              hint={copy.pageProfileHint}
              metaLabel={copy.requestReferenceLabel}
              metaValue={printReference}
              pageBreak
            >
              <div className="mb-4 rounded-[18px] border border-blue-100 bg-blue-50 px-4 py-3 text-[12px] leading-6 text-blue-900">
                {copy.generatedNotice}
              </div>

              <div className="grid gap-4 md:grid-cols-2">
                <PrintSectionBlock title={copy.studentDataTitle}>
                  <div className="grid gap-3 md:grid-cols-2">
                    <PrintField label={studentField('student_full_name')?.label?.[locale]} value={student.student_full_name} />
                    <PrintField label={studentField('student_birth_date')?.label?.[locale]} value={student.student_birth_date ? formatDateForLocale(locale, student.student_birth_date) : ''} />
                    <PrintField label={studentField('student_gender')?.label?.[locale]} value={studentValue('student_gender', student.student_gender)} />
                    <PrintField label={studentField('student_birth_place')?.label?.[locale]} value={student.student_birth_place} />
                    <PrintField label={studentField('student_father_name')?.label?.[locale]} value={student.student_father_name} />
                    <PrintField label={studentField('student_family_name')?.label?.[locale]} value={student.student_family_name} />
                    <PrintField label={studentField('student_grade')?.label?.[locale]} value={classLabel} />
                    <PrintField label={studentField('student_section')?.label?.[locale]} value={studentValue('student_section', student.student_section)} />
                  </div>
                </PrintSectionBlock>

                <PrintSectionBlock title={copy.familyLinkTitle}>
                  <div className="grid gap-3 md:grid-cols-2">
                    <PrintField label={labels.familySummaryTitle} value={guardianFullName} />
                    <PrintField label={familyField('guardian_phone_primary')?.label?.[locale]} value={values.guardian_phone_primary} />
                    <PrintField label={familyField('guardian_phone_whatsapp')?.label?.[locale]} value={values.guardian_phone_whatsapp} />
                    <PrintField label={familyField('mother_given_name')?.label?.[locale]} value={motherFullName} />
                    <PrintField label={studentField('student_username')?.label?.[locale]} value={student.student_username} />
                    <PrintField label={studentField('student_initial_password')?.label?.[locale]} value={labels.generatedAtActivation} />
                  </div>
                </PrintSectionBlock>
              </div>

              <div className="mt-4 grid gap-4">
                <PrintSectionBlock title={studentField('student_passport_number')?.label?.[locale]}>
                  <div className="grid gap-3 md:grid-cols-2">
                    <PrintField label={studentField('student_passport_number')?.label?.[locale]} value={student.student_passport_number} />
                    <PrintField label={studentField('student_passport_expiry_date')?.label?.[locale]} value={student.student_passport_expiry_date ? formatDateForLocale(locale, student.student_passport_expiry_date) : ''} />
                    <PrintField label={studentField('student_previous_school')?.label?.[locale]} value={student.student_previous_school} wide />
                  </div>
                </PrintSectionBlock>

                <PrintSectionBlock title={template.sections.find((section) => section.key === 'family_context')?.title?.[locale]}>
                  <div className="grid gap-3">
                    <PrintField label={studentField('student_address_mashhad')?.label?.[locale]} value={student.student_address_mashhad} />
                    <PrintField label={studentField('student_address_iraq')?.label?.[locale]} value={student.student_address_iraq} />
                    <PrintField label={studentField('student_health_notes')?.label?.[locale]} value={student.student_health_notes} />
                  </div>
                </PrintSectionBlock>
              </div>
            </PrintPageShell>

            <PrintPageShell
              locale={locale}
              title={`${labels.financeSummaryTitle} — ${student.student_full_name || labels.emptyValue}`}
              subtitle={classLabel}
              hint={copy.pageFinanceHint}
              metaLabel={copy.requestReferenceLabel}
              metaValue={printReference}
              pageBreak={index !== values.students.length - 1}
            >
              <div className="grid gap-3 md:grid-cols-4">
                <PrintMetric label={labels.classFeeLabel} value={financeItem ? `${localeNumber(locale, Number(financeItem.annual_fee || 0))} ${financeItem.currency}` : labels.classFeeMissing} />
                <PrintMetric label={labels.planCountLabel} value={localeNumber(locale, planCount)} />
                <PrintMetric label={labels.paymentTotal} value={localeNumber(locale, studentPaidTotal)} />
                <PrintMetric label={copy.remainingForStudentLabel} value={localeNumber(locale, studentRemainingTotal)} />
              </div>

              <div className="mt-5 grid gap-4 md:grid-cols-[.95fr_1.05fr]">
                <PrintSectionBlock title={copy.financeStatusTitle}>
                  <div className="grid gap-3 md:grid-cols-1">
                    <PrintField label={studentField('finance_plan_type')?.label?.[locale]} value={studentValue('finance_plan_type', student.finance_plan_type)} />
                    <PrintField label={studentField('finance_installments_count')?.label?.[locale]} value={localeNumber(locale, planCount)} />
                    <PrintField label={studentField('finance_plan_start_date')?.label?.[locale]} value={student.finance_plan_start_date ? formatDateForLocale(locale, student.finance_plan_start_date) : ''} />
                    <PrintField label={labels.classFeeLabel} value={financeItem ? `${localeNumber(locale, Number(financeItem.annual_fee || 0))} ${financeItem.currency}` : labels.classFeeMissing} />
                  </div>
                </PrintSectionBlock>

                <PrintSectionBlock title={copy.planScheduleTitle}>
                  <div className="overflow-hidden rounded-[14px] border border-slate-300 bg-white/95">
                    <table className="min-w-full border-collapse text-[11px]">
                      <thead>
                        <tr className="bg-slate-50 text-slate-700">
                          <th className="border border-slate-300 px-2 py-2">#</th>
                          <th className="border border-slate-300 px-2 py-2">{labels.submittedAt}</th>
                          <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.amount}</th>
                        </tr>
                      </thead>
                      <tbody>
                        {schedule.length ? schedule.map((item) => (
                          <tr key={`${student.id}-${item.installment_number}`}>
                            <td className="border border-slate-300 px-2 py-2 text-center">{localeNumber(locale, item.installment_number)}</td>
                            <td className="border border-slate-300 px-2 py-2">{item.due_date ? formatDateForLocale(locale, item.due_date) : labels.emptyValue}</td>
                            <td className="border border-slate-300 px-2 py-2">{localeNumber(locale, item.amount_due)} {financeItem?.currency || 'USD'}</td>
                          </tr>
                        )) : (
                          <tr>
                            <td className="border border-slate-300 px-2 py-3 text-center text-slate-500" colSpan={3}>{labels.installmentPreviewEmpty}</td>
                          </tr>
                        )}
                      </tbody>
                    </table>
                  </div>
                </PrintSectionBlock>
              </div>

              <div className="mt-4 grid gap-4 md:grid-cols-[1.15fr_.85fr]">
                <PrintSectionBlock title={copy.studentPaymentsTitle}>
                  {directPayments.length ? (
                    <div className="overflow-hidden rounded-[14px] border border-slate-300 bg-white/95">
                      <table className="min-w-full border-collapse text-[11px]">
                        <thead>
                          <tr className="bg-slate-50 text-slate-700">
                            <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.row}</th>
                            <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.cardNumber}</th>
                            <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.trackingNumber}</th>
                            <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.date}</th>
                            <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.amount}</th>
                            <th className="border border-slate-300 px-2 py-2">{labels.paymentColumns.notes}</th>
                          </tr>
                        </thead>
                        <tbody>
                          {directPayments.map((row, paymentIndex) => (
                            <tr key={row.id}>
                              <td className="border border-slate-300 px-2 py-2 text-center">{localeNumber(locale, paymentIndex + 1)}</td>
                              <td className="border border-slate-300 px-2 py-2 whitespace-pre-wrap break-words">{row.card_number || labels.emptyValue}</td>
                              <td className="border border-slate-300 px-2 py-2 whitespace-pre-wrap break-words">{row.tracking_number || labels.emptyValue}</td>
                              <td className="border border-slate-300 px-2 py-2">{row.payment_date ? formatDateForLocale(locale, row.payment_date) : labels.emptyValue}</td>
                              <td className="border border-slate-300 px-2 py-2">{row.amount ? localeNumber(locale, Number(row.amount)) : labels.emptyValue}</td>
                              <td className="border border-slate-300 px-2 py-2 whitespace-pre-wrap break-words">{row.notes || row.reference || labels.emptyValue}</td>
                            </tr>
                          ))}
                          <tr className="bg-brand-50">
                            <td className="border border-slate-300 px-2 py-2 text-center font-black" colSpan={4}>{labels.paymentTotal}</td>
                            <td className="border border-slate-300 px-2 py-2 font-black">{localeNumber(locale, sumPaymentRows(directPayments))}</td>
                            <td className="border border-slate-300 px-2 py-2" />
                          </tr>
                        </tbody>
                      </table>
                    </div>
                  ) : (
                    <div className="text-[12px] leading-7 text-slate-600">{copy.noPayments}</div>
                  )}
                </PrintSectionBlock>

                <PrintSectionBlock title={template.sections.find((section) => section.key === 'approval')?.title?.[locale]}>
                  <div className="grid gap-3">
                    <PrintField label={familyField('applicant_relation')?.label?.[locale]} value={applicantRelationDisplay} />
                    <PrintField label={familyField('applicant_name')?.label?.[locale]} value={values.applicant_name} />
                    <PrintField label={familyField('accountant_receiver_name')?.label?.[locale]} value={values.accountant_receiver_name} />
                    <PrintField label={copy.registrationOfficerLabel} value="" />
                    <PrintField label={copy.financeOfficerLabel} value="" />
                  </div>
                </PrintSectionBlock>
              </div>
            </PrintPageShell>
          </div>
        );
      })}
    </div>
  );
}

function PrintField({ label, value, wide = false }) {
  return (
    <div className={wide ? 'md:col-span-2' : ''}>
      <div className="h-full rounded-[16px] border border-slate-300 bg-white/90 px-3 py-3">
        <div className="text-[10px] font-black tracking-wide text-slate-500">{label}</div>
        <div className="mt-1 whitespace-pre-wrap break-words text-[12px] font-semibold leading-6 text-slate-900">{value || '—'}</div>
      </div>
    </div>
  );
}

export default function FamilyRegistrationV3Shell({ locale, dictionary, initialStep = FORM_STEPS.registration }) {
  const router = useRouter();
  const forms = dictionary.forms;
  const labels = forms.familyRegistrationV3;
  const template = useMemo(() => buildTemplateByKey('family_registration_v3'), []);
  const fieldById = useMemo(() => fieldMapFromTemplate(template), [template]);
  const registrationPath = `/${locale}/forms/family-registration-v3`;
  const financePath = `/${locale}/forms/family-registration-v3/finance`;

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
  const [fileObjects, setFileObjects] = useState({ family_attachment: null, studentFiles: {} });
  const [actionFlash, setActionFlash] = useState('');
  const [financeCatalog, setFinanceCatalog] = useState([]);
  const [financeCatalogState, setFinanceCatalogState] = useState('loading');
  const [currentStep, setCurrentStep] = useState(initialStep);

  const meta = localeMeta[activeLocale] || localeMeta.ar;
  // Must be initialized before the effects that reference it. Keeping this below
  // those effects caused a production-only TDZ crash in the browser.
  const financeCatalogMap = useMemo(
    () => new Map(financeCatalog.map((item) => [String(item.class_id), item])),
    [financeCatalog]
  );

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

    setCurrentStep(initialStep);
  }, [template, initialStep]);

  useEffect(() => {
    window.localStorage.setItem(LOCAL_LANGUAGE_KEY, activeLocale);
    document.documentElement.lang = activeLocale;
    document.documentElement.dir = meta.dir;
  }, [activeLocale, meta.dir]);

  useEffect(() => {
    let cancelled = false;

    async function loadFinanceCatalog() {
      setFinanceCatalogState('loading');
      try {
        const response = await fetch('/api/forms/data/family-registration-finance', { cache: 'no-store' });
        const result = await response.json();
        if (cancelled) return;
        if (!response.ok || result?.ok === false) throw new Error(result?.error || `finance_catalog_${response.status}`);
        setFinanceCatalog(result.items || []);
        setFinanceCatalogState('ready');
      } catch (error) {
        console.error(error);
        if (cancelled) return;
        setFinanceCatalog([]);
        setFinanceCatalogState('error');
      }
    }

    loadFinanceCatalog();
    return () => { cancelled = true; };
  }, []);

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
    return () => { cancelled = true; };
  }, [template.slug]);

  useEffect(() => {
    setValues((current) => {
      const nextPaymentEntries = buildDynamicPaymentRows(current.students, current.payment_entries, financeCatalogMap);
      if (JSON.stringify(nextPaymentEntries) === JSON.stringify(current.payment_entries)) {
        return current;
      }
      const next = { ...current, payment_entries: nextPaymentEntries };
      persistLocal(next);
      return next;
    });
  }, [values.students, financeCatalogMap]);

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
  const expectedFamilyFeeTotal = useMemo(() => values.students.reduce((sum, student) => sum + Number(financeCatalogMap.get(String(student.student_grade || ''))?.annual_fee || 0), 0), [values.students, financeCatalogMap]);
  const remainingProjected = Math.max(expectedFamilyFeeTotal - totalAmount, 0);
  const guardianFullName = useMemo(() => computeGuardianFullName(values), [values]);
  const errorCount = countErrors(fieldErrors, studentErrors, globalErrors);
  const guardianCoreFields = ['guardian_given_name', 'guardian_father_name', 'family_name', 'guardian_phone_primary', 'guardian_birth_date'];
  const guardianCoreDone = guardianCoreFields.filter((fieldId) => String(values[fieldId] || '').trim()).length;
  const studentReadyCount = useMemo(() => countReadyStudents(template, values.students), [template, values.students]);
  const duplicateNames = useMemo(() => duplicateStudentNames(values.students), [values.students]);
  const studentManualOverrides = useMemo(() => countStudentManualOverrides(values.students), [values.students]);
  const studentInheritedLinks = useMemo(() => countStudentInheritedLinks(values.students), [values.students]);
  const isRegistrationStep = currentStep === FORM_STEPS.registration;
  const isFinanceStep = currentStep === FORM_STEPS.finance;

  function persistLocal(nextValues, nextReceipt = receipt, nextUploadTicket = uploadTicket, nextAttachment = uploadedAttachment) {
    window.localStorage.setItem(LOCAL_FORM_STATE_KEY, JSON.stringify({ values: nextValues, receipt: nextReceipt, uploadTicket: nextUploadTicket, uploadedAttachment: nextAttachment }));
  }

  function updateStep(nextStep) {
    setCurrentStep(nextStep);

    const targetPath = nextStep === FORM_STEPS.finance ? financePath : registrationPath;
    if (window.location.pathname !== targetPath) {
      router.push(targetPath);
      return;
    }

    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function flashAction(message) {
    setActionFlash(message);
    window.setTimeout(() => setActionFlash(''), 2200);
  }

  function copyPrimaryPhoneToWhatsapp() {
    if (!String(values.guardian_phone_primary || '').trim()) return;
    setValues((current) => {
      const next = { ...current, guardian_phone_whatsapp: current.guardian_phone_primary };
      persistLocal(next);
      return next;
    });
    flashAction(labels.quickActionDonePrimaryWhatsapp);
  }

  function syncMotherFamilyName() {
    setValues((current) => {
      const next = {
        ...current,
        mother_family_name: current.family_name || '',
        _meta: { ...current._meta, motherFamilyManual: false }
      };
      const normalized = normalizeFamilyValues(template, next);
      persistLocal(normalized);
      return normalized;
    });
    flashAction(labels.quickActionDoneMotherFamily);
  }

  function applyFamilyInheritanceToStudents() {
    setValues((current) => {
      const next = {
        ...current,
        students: current.students.map((student) => ({
          ...student,
          _meta: { ...student._meta, fatherManual: false, familyManual: false, fullNameManual: false }
        }))
      };
      const normalized = normalizeFamilyValues(template, next);
      persistLocal(normalized);
      return normalized;
    });
    flashAction(labels.quickActionDoneStudentsInheritance);
  }

  function duplicateStudentCard(studentId) {
    setValues((current) => {
      const source = current.students.find((student) => student.id === studentId);
      if (!source) return current;
      const duplicate = {
        ...source,
        id: generateId('student_card'),
        student_given_name: '',
        student_full_name: '',
        student_birth_date: '',
        student_passport_number: '',
        student_passport_expiry_date: '',
        student_photo: null,
        student_username: '',
        _meta: { ...source._meta, fullNameManual: false, usernameManual: false }
      };
      const next = { ...current, students: [...current.students, duplicate] };
      const normalized = normalizeFamilyValues(template, next);
      persistLocal(normalized);
      return normalized;
    });
    flashAction(labels.quickActionDoneDuplicateStudent);
  }

  function setFieldValue(fieldId, value) {
    setValues((current) => {
      const next = { ...current, _meta: { ...current._meta } };
      let normalizedValue = value;

      if (fieldId.includes('phone') && typeof value === 'string') normalizedValue = normalizePhone(value);
      if (fieldId === 'guardian_username') next._meta.guardianUsernameManual = true;
      if (fieldId === 'mother_family_name') next._meta.motherFamilyManual = String(value || '').trim() !== String(current.family_name || '').trim();

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
          const updated = { ...student, _meta: { ...student._meta } };
          let normalizedValue = value;

          const studentFieldDefinition = fieldById.get(fieldId);
          if (studentFieldDefinition?.type === 'file') {
            setFileObjects((files) => ({
              ...files,
              studentFiles: {
                ...(files.studentFiles || {}),
                [studentFileKey(studentId, fieldId)]: value?.rawFile || null
              }
            }));
            normalizedValue = value?.rawFile ? sanitizeFileMeta(value.rawFile) : null;
          }
          if (fieldId === 'student_father_name') updated._meta.fatherManual = !options.forceInherited && String(normalizedValue || '').trim() !== String(current.guardian_given_name || '').trim();
          if (fieldId === 'student_family_name') updated._meta.familyManual = !options.forceInherited && String(normalizedValue || '').trim() !== String(current.family_name || '').trim();
          if (fieldId === 'student_full_name') updated._meta.fullNameManual = !options.forceAutoFullName;
          if (fieldId === 'student_username') updated._meta.usernameManual = true;
          if (fieldId === 'finance_plan_type') updated.finance_installments_count = String(planCountForType(String(normalizedValue || 'monthly'), updated.finance_installments_count || 1));
          if (fieldId === 'finance_installments_count') normalizedValue = String(Math.max(1, Number(normalizedValue) || 1));

          updated[fieldId] = normalizedValue;

          // Auto-calculate Shamsi display when Gregorian birth date changes
          if (fieldId === 'student_birth_date' && normalizedValue) {
            try {
              const shamsi = gregorianToShamsi(normalizedValue);
              updated['student_birth_date_shamsi_display'] = shamsi;
            } catch {}
          }
          // Auto-calculate passport days remaining
          if (fieldId === 'student_passport_expiry_date' && normalizedValue) {
            updated['student_passport_days_remaining'] = calculatePassportDaysRemaining(normalizedValue);
          }
          // Also recalc if birth date is changed via shamsi input (reverse)
          if (fieldId === 'student_birth_date_shamsi_display') {
            // If user types Shamsi date, we keep it as display only, but could convert back
            // For now, keep as is - user requested opposite conversion also possible
          }

          return updated;
        })
      };

      const normalized = normalizeFamilyValues(template, next);
      persistLocal(normalized);
      return normalized;
    });

    setStudentErrors((current) => ({ ...current, [studentId]: { ...(current[studentId] || {}), [fieldId]: undefined } }));
    setGlobalErrors([]);
    if (submitState !== 'idle') setSubmitState('idle');
  }

  function restoreStudentInheritance(studentId) {
    setValues((current) => {
      const next = {
        ...current,
        students: current.students.map((student) => student.id !== studentId ? student : ({
          ...student,
          _meta: { ...student._meta, fatherManual: false, familyManual: false, fullNameManual: false, usernameManual: false }
        }))
      };
      const normalized = normalizeFamilyValues(template, next);
      persistLocal(normalized);
      return normalized;
    });
  }

  function addStudent() {
    setValues((current) => {
      const next = { ...current, students: [...current.students, makeEmptyStudent(template, current)] };
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
      const next = { ...current, payment_entries: current.payment_entries.map((row, rowIndex) => rowIndex === index ? { ...row, [key]: value } : row) };
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
    setFileObjects({ family_attachment: null, studentFiles: {} });
    setUploadState('idle');
    persistLocal(next, null, null, null);
    setSubmitState('idle');
    updateStep(FORM_STEPS.registration);
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

  async function requestAndUploadAttachment({ fieldId, fileMeta, rawFile }) {
    if (!fileMeta?.name || !rawFile) return null;
    const ticketResult = await requestUploadTicketRpc({
      form_slug: template.slug,
      locale: activeLocale,
      field_id: fieldId,
      file_name: fileMeta.name,
      content_type: fileMeta.type || 'application/octet-stream',
      byte_size: fileMeta.size || 0
    });
    if (ticketResult?.ok === false) throw new Error(ticketResult.error || `upload_ticket_failed_${fieldId}`);
    const ticketPayload = ticketResult?.data || ticketResult;
    const ticketId = ticketPayload?.ticket_id || ticketPayload?.ticketId || ticketPayload?.upload_token;
    if (!ticketId) throw new Error(`upload_ticket_missing_${fieldId}`);
    const uploadResult = await uploadAttachmentTransport({
      ticketId,
      formSlug: template.slug,
      fieldId,
      file: rawFile
    });
    if (uploadResult?.ok === false) throw new Error(uploadResult.error || `upload_failed_${fieldId}`);
    return {
      bucket: uploadResult.bucket,
      object_path: uploadResult.object_path,
      file_name: uploadResult.file_name,
      content_type: uploadResult.content_type,
      byte_size: uploadResult.byte_size
    };
  }

  function goToFinanceStep() {
    const validation = validateValues(template, values, labels, { includeSections: ['guardian', 'mother', 'students', 'family_context', 'documents'] });
    setFieldErrors(validation.fieldErrors);
    setStudentErrors(validation.studentErrors);
    setGlobalErrors(validation.globalErrors);

    if (Object.keys(validation.fieldErrors).length || Object.keys(validation.studentErrors).length || validation.globalErrors.length) {
      setSubmitState('validation_error');
      return;
    }

    setSubmitState('idle');
    updateStep(FORM_STEPS.finance);
  }

  async function submitForm() {
    const validation = validateValues(template, values, labels);
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

      if (values.family_attachment?.name && !attachmentPayload) {
        const rawFile = fileObjects.family_attachment;
        if (!rawFile) {
          setFieldErrors((current) => ({ ...current, family_attachment: labels.fileNeedsReselect }));
          setSubmitState('validation_error');
          return;
        }

        setUploadState('uploading');
        attachmentPayload = await requestAndUploadAttachment({
          fieldId: 'family_attachment',
          fileMeta: values.family_attachment,
          rawFile
        });
        setUploadedAttachment(attachmentPayload);
        setUploadState('uploaded');
      }

      const normalizedStudents = sanitizeStudentsForSubmit(values.students, financeCatalogMap).map((student) => {
        const passportRawFile = fileObjects.studentFiles?.[studentFileKey(student.id, 'student_passport_attachment')] || null;
        const academicRawFile = fileObjects.studentFiles?.[studentFileKey(student.id, 'student_academic_documents')] || null;
        return {
          ...student,
          _passport_raw_file: passportRawFile,
          _academic_raw_file: academicRawFile
        };
      });

      for (const student of normalizedStudents) {
        if (student.student_passport_attachment?.name && student._passport_raw_file) {
          student.student_passport_attachment = await requestAndUploadAttachment({
            fieldId: `student_passport_attachment_${student.id}`,
            fileMeta: student.student_passport_attachment,
            rawFile: student._passport_raw_file
          });
        }
        if (student.student_academic_documents?.name && student._academic_raw_file) {
          student.student_academic_documents = await requestAndUploadAttachment({
            fieldId: `student_academic_documents_${student.id}`,
            fileMeta: student.student_academic_documents,
            rawFile: student._academic_raw_file
          });
        }
        delete student._passport_raw_file;
        delete student._academic_raw_file;
      }
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
          mother_full_name: computeMotherFullName(values),
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
          applicant_relation: values.applicant_relation,
          applicant_other_relation: values.applicant_other_relation,
          applicant_name: values.applicant_name,
          accountant_receiver_name: values.accountant_receiver_name
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

      const params = new URLSearchParams({ ref: reportId, submittedAt: submittedAtIso, applicant: normalizedStudents[0]?.student_full_name || guardianFullName });
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
    value: `${student.student_full_name || '—'} — ${financeCatalogMap.get(String(student.student_grade || ''))?.class_name || optionLabelForValue(fieldById.get('student_grade'), student.student_grade, activeLocale) || '—'}`
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
            {isRegistrationStep ? (
              <button onClick={goToFinanceStep} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labels.goToFinanceStep}</button>
            ) : (
              <>
                <button onClick={() => updateStep(FORM_STEPS.registration)} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.backToRegistration}</button>
                <button onClick={submitForm} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labels.submit}</button>
              </>
            )}
          </div>
        </div>

        <div className="mt-5 grid gap-4 md:grid-cols-2">
          <button type="button" onClick={() => updateStep(FORM_STEPS.registration)} className={`rounded-[24px] border p-4 text-start ${isRegistrationStep ? 'border-brand-300 bg-brand-50 text-brand-900' : 'border-slate-200 bg-white text-slate-700'}`}>
            <div className="flex items-center gap-3">
              <span className={`flex h-9 w-9 items-center justify-center rounded-full text-sm font-black ${isRegistrationStep ? 'bg-brand-500 text-white' : 'bg-slate-100 text-slate-600'}`}>1</span>
              <div>
                <div className="text-base font-black">{labels.stepRegistrationTitle}</div>
                <div className="mt-1 text-xs leading-6">{labels.stepRegistrationDescription}</div>
              </div>
            </div>
          </button>
          <button type="button" onClick={() => (isRegistrationStep ? goToFinanceStep() : updateStep(FORM_STEPS.finance))} className={`rounded-[24px] border p-4 text-start ${isFinanceStep ? 'border-brand-300 bg-brand-50 text-brand-900' : 'border-slate-200 bg-white text-slate-700'}`}>
            <div className="flex items-center gap-3">
              <span className={`flex h-9 w-9 items-center justify-center rounded-full text-sm font-black ${isFinanceStep ? 'bg-brand-500 text-white' : 'bg-slate-100 text-slate-600'}`}>2</span>
              <div>
                <div className="text-base font-black">{labels.stepFinanceTitle}</div>
                <div className="mt-1 text-xs leading-6">{labels.stepFinanceDescription}</div>
              </div>
            </div>
          </button>
        </div>

        <div className="mt-5 grid gap-4 xl:grid-cols-[minmax(0,1fr)_430px]">
          <section className="space-y-4">
            <div className="rounded-[24px] border border-slate-200 bg-white p-4">
              <div className="grid gap-3 md:grid-cols-4">
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm"><div className="text-slate-500">{labels.statusDraft}</div><div className="mt-1 font-bold text-slate-900">{saveState === 'saved' ? labels.saved : saveState === 'saving' ? labels.saving : saveState === 'error' ? labels.saveError : labels.notSavedYet}</div></div>
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm"><div className="text-slate-500">{labels.requiredCoverage}</div><div className="mt-1 font-bold text-slate-900">{requiredDone} / {requiredTotal}</div></div>
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm"><div className="text-slate-500">{labels.versionCount}</div><div className="mt-1 font-bold text-slate-900">{versions.length}</div></div>
                <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm"><div className="text-slate-500">{labels.errorCount}</div><div className="mt-1 font-bold text-slate-900">{errorCount}</div></div>
              </div>
            </div>

            {isRegistrationStep ? (
              <div className="rounded-[24px] border border-brand-100 bg-brand-50 px-5 py-4 text-brand-900">
                <div className="text-base font-black">{labels.normalizedFlowTitle}</div>
                <p className="mt-2 text-sm leading-7 text-brand-800">{labels.normalizedFlowDescription}</p>
                <div className="mt-3 flex flex-wrap gap-2">{labels.normalizedFlowPoints.map((item) => <StatusPill key={item} tone="brand">{item}</StatusPill>)}</div>
              </div>
            ) : (
              <div className="rounded-[24px] border border-blue-100 bg-blue-50 px-5 py-4 text-blue-900">
                <div className="text-base font-black">{labels.financeStepIntroTitle}</div>
                <p className="mt-2 text-sm leading-7 text-blue-800">{labels.financeStepIntroDescription}</p>
              </div>
            )}

            <div className="rounded-[24px] border border-slate-200 bg-white p-4 shadow-soft">
              <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
                <div>
                  <div className="text-sm font-black text-slate-900">{labels.quickJumpTitle}</div>
                  <div className="text-xs leading-6 text-slate-500">{labels.quickJumpDescription}</div>
                </div>
                <div className="text-xs font-bold text-slate-500">{guardianCoreDone} / {guardianCoreFields.length}</div>
              </div>
              <div className="flex flex-wrap gap-2">
                {isRegistrationStep ? (
                  <>
                    <a href="#family-v3-guardian" className="rounded-full border border-slate-200 bg-slate-50 px-3 py-2 text-xs font-bold text-slate-700">{labels.navGuardian}</a>
                    <a href="#family-v3-mother" className="rounded-full border border-slate-200 bg-slate-50 px-3 py-2 text-xs font-bold text-slate-700">{labels.navMother}</a>
                    <a href="#family-v3-students" className="rounded-full border border-slate-200 bg-slate-50 px-3 py-2 text-xs font-bold text-slate-700">{labels.navStudents}</a>
                    <a href="#family-v3-family-context" className="rounded-full border border-slate-200 bg-slate-50 px-3 py-2 text-xs font-bold text-slate-700">{labels.navFamilyContext}</a>
                    <a href="#family-v3-documents" className="rounded-full border border-slate-200 bg-slate-50 px-3 py-2 text-xs font-bold text-slate-700">{labels.navDocuments}</a>
                  </>
                ) : (
                  <>
                    <a href="#family-v3-finance" className="rounded-full border border-slate-200 bg-slate-50 px-3 py-2 text-xs font-bold text-slate-700">{labels.navFinance}</a>
                    <a href="#family-v3-approval" className="rounded-full border border-slate-200 bg-slate-50 px-3 py-2 text-xs font-bold text-slate-700">{labels.navApproval}</a>
                  </>
                )}
              </div>
            </div>

            {actionFlash ? <div className="rounded-[20px] border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm font-bold text-emerald-800">{actionFlash}</div> : null}
            {globalErrors.length ? <div className="rounded-[24px] border border-rose-200 bg-rose-50 px-4 py-4 text-sm text-rose-700">{globalErrors.map((message) => <div key={message}>• {message}</div>)}</div> : null}

            {isRegistrationStep ? (
              <>
                <SectionCard anchorId="family-v3-guardian" title={template.sections.find((section) => section.key === 'guardian')?.title?.[activeLocale]} subtitle={labels.sectionHints.guardian}>
                  <div className="grid gap-4 md:grid-cols-2">{familyFieldIds.guardian.map((fieldId) => <InputField key={fieldId} field={fieldById.get(fieldId)} locale={activeLocale} value={values[fieldId]} error={fieldErrors[fieldId]} onChange={setFieldValue} labels={labels} />)}</div>
                  <div className="mt-5 rounded-2xl border border-slate-200 bg-slate-50 p-4">
                    <div className="mb-2 text-sm font-black text-slate-900">{labels.quickActionsTitle}</div>
                    <div className="mb-3 text-xs leading-6 text-slate-500">{labels.quickActionsDescription}</div>
                    <div className="flex flex-wrap gap-2">
                      <button type="button" onClick={copyPrimaryPhoneToWhatsapp} className="rounded-2xl border border-slate-200 bg-white px-3 py-2 text-xs font-bold text-slate-700">{labels.copyPrimaryToWhatsapp}</button>
                      <button type="button" onClick={syncMotherFamilyName} className="rounded-2xl border border-slate-200 bg-white px-3 py-2 text-xs font-bold text-slate-700">{labels.syncMotherFamilyName}</button>
                      <button type="button" onClick={applyFamilyInheritanceToStudents} className="rounded-2xl border border-brand-200 bg-brand-50 px-3 py-2 text-xs font-bold text-brand-800">{labels.applyInheritanceToAllStudents}</button>
                    </div>
                  </div>
                </SectionCard>

                <SectionCard anchorId="family-v3-mother" title={template.sections.find((section) => section.key === 'mother')?.title?.[activeLocale]} subtitle={labels.sectionHints.mother}>
                  <div className="grid gap-4 md:grid-cols-2">{familyFieldIds.mother.map((fieldId) => <InputField key={fieldId} field={fieldById.get(fieldId)} locale={activeLocale} value={values[fieldId]} error={fieldErrors[fieldId]} onChange={setFieldValue} labels={labels} />)}</div>
                </SectionCard>

                <SectionCard anchorId="family-v3-students" title={template.sections.find((section) => section.key === 'students')?.title?.[activeLocale]} subtitle={labels.sectionHints.students}>
                  <div className="mb-4 grid gap-3 md:grid-cols-4">
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm"><div className="text-slate-500">{labels.studentReadyLabel}</div><div className="mt-1 font-black text-slate-900">{localeNumber(activeLocale, studentReadyCount)} / {localeNumber(activeLocale, values.students.length)}</div></div>
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm"><div className="text-slate-500">{labels.duplicateWarningLabel}</div><div className="mt-1 font-black text-slate-900">{duplicateNames.length ? labels.duplicateWarningDetected : labels.duplicateWarningClear}</div></div>
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm"><div className="text-slate-500">{labels.manualOverridesLabel}</div><div className="mt-1 font-black text-slate-900">{localeNumber(activeLocale, studentManualOverrides)}</div></div>
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm"><div className="text-slate-500">{labels.inheritedLinksLabel}</div><div className="mt-1 font-black text-slate-900">{localeNumber(activeLocale, studentInheritedLinks)}</div></div>
                  </div>
                  <div className="space-y-4">
                    {values.students.map((student, index) => (
                      <StudentCard key={student.id} locale={activeLocale} labels={labels} student={student} index={index} fieldById={fieldById} financeCatalogMap={financeCatalogMap} studentErrors={studentErrors[student.id] || {}} onFieldChange={setStudentValue} onRestoreInheritance={restoreStudentInheritance} onRemove={removeStudent} onDuplicate={duplicateStudentCard} canRemove={values.students.length > 1} />
                    ))}
                    <button type="button" onClick={addStudent} className="rounded-2xl border border-brand-200 bg-brand-50 px-4 py-3 font-bold text-brand-800">{labels.addStudent}</button>
                  </div>
                </SectionCard>

                <SectionCard anchorId="family-v3-family-context" title={template.sections.find((section) => section.key === 'family_context')?.title?.[activeLocale]} subtitle={labels.sectionHints.family_context}>
                  <div className="grid gap-4 md:grid-cols-2">{familyFieldIds.family_context.map((fieldId) => <InputField key={fieldId} field={fieldById.get(fieldId)} locale={activeLocale} value={values[fieldId]} error={fieldErrors[fieldId]} onChange={setFieldValue} labels={labels} />)}</div>
                </SectionCard>

                <SectionCard anchorId="family-v3-documents" title={template.sections.find((section) => section.key === 'documents')?.title?.[activeLocale]} subtitle={labels.sectionHints.documents}>
                  <div className="grid gap-4 md:grid-cols-2">{familyFieldIds.documents.map((fieldId) => <InputField key={fieldId} field={fieldById.get(fieldId)} locale={activeLocale} value={values[fieldId]} error={fieldErrors[fieldId]} onChange={setFieldValue} labels={labels} />)}</div>
                </SectionCard>
              </>
            ) : (
              <>
                <SectionCard anchorId="family-v3-finance" title={template.sections.find((section) => section.key === 'finance')?.title?.[activeLocale]} subtitle={labels.sectionHints.finance}>
                  <div className={`mb-4 rounded-2xl border px-4 py-3 text-sm ${financeCatalogState === 'ready' ? 'border-emerald-200 bg-emerald-50 text-emerald-800' : financeCatalogState === 'error' ? 'border-amber-200 bg-amber-50 text-amber-800' : 'border-slate-200 bg-slate-50 text-slate-700'}`}>
                    {financeCatalogState === 'ready' ? labels.financeCatalogReady : financeCatalogState === 'error' ? labels.financeCatalogError : labels.financeCatalogLoading}
                  </div>

                  <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                    <div className="mb-3 text-sm font-black text-slate-900">{labels.feeBandsTitle}</div>
                    <div className="space-y-2 text-sm text-slate-700">{labels.feeBands.map((band) => <div key={`${band.label}-${band.amount}`} className="flex items-center justify-between gap-4 rounded-xl border border-slate-200 bg-white px-3 py-2"><span>{band.label}</span><span className="font-black text-slate-900">{band.amount}</span></div>)}</div>
                  </div>

                  <div className="mt-4 space-y-4">
                    {values.students.map((student, index) => (
                      <FinanceStudentCard key={`${student.id}-finance`} locale={activeLocale} labels={labels} student={student} index={index} fieldById={fieldById} financeCatalogMap={financeCatalogMap} onFieldChange={setStudentValue} />
                    ))}
                  </div>

                  <div className="mt-4">
                    <PaymentsEditor locale={activeLocale} labels={labels} rows={values.payment_entries} students={values.students} onChange={setPaymentValue} totalAmount={totalAmount} />
                  </div>
                </SectionCard>

                <SectionCard anchorId="family-v3-approval" title={template.sections.find((section) => section.key === 'approval')?.title?.[activeLocale]} subtitle={labels.sectionHints.approval}>
                  <div className="mb-4 rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-700">{labels.termsAcceptanceText}</div>
                  <div className="grid gap-4 md:grid-cols-2">{familyFieldIds.approval.map((fieldId) => <InputField key={fieldId} field={fieldById.get(fieldId)} locale={activeLocale} value={values[fieldId]} error={fieldErrors[fieldId]} onChange={setFieldValue} labels={labels} />)}</div>
                </SectionCard>
              </>
            )}

            <div className="no-print flex flex-wrap gap-3 rounded-[24px] border border-slate-200 bg-white p-4 shadow-soft">
              <button onClick={resetForm} className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-2 font-bold text-amber-800">{labels.reset}</button>
              <button onClick={prepareUploadTicket} className="rounded-2xl border border-brand-200 bg-brand-50 px-4 py-2 font-bold text-brand-800">{labels.prepareUpload}</button>
              <button onClick={saveNow} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.saveNow}</button>
              <button onClick={() => window.print()} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.printPreview}</button>
              {isRegistrationStep ? (
                <button onClick={goToFinanceStep} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labels.goToFinanceStep}</button>
              ) : (
                <>
                  <button onClick={() => updateStep(FORM_STEPS.registration)} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.backToRegistration}</button>
                  <button onClick={submitForm} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labels.submit}</button>
                </>
              )}
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
              { label: labels.expectedFeesLabel, value: localeNumber(activeLocale, expectedFamilyFeeTotal) },
              { label: labels.projectedRemainingLabel, value: localeNumber(activeLocale, remainingProjected) },
              { label: labels.documentsSummaryTitle, value: uploadedAttachment?.file_name || values.family_attachment?.name || '—' },
              { label: labels.versionCount, value: localeNumber(activeLocale, versions.length) },
              { label: labels.studentsSummaryTitle, value: `${localeNumber(activeLocale, values.students.length)} ${labels.studentsCountUnit}` }
            ]} />
            <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
              <h3 className="mb-3 text-lg font-black text-slate-950">{labels.printPreviewTitle}</h3>
              <div className="mb-3 text-xs text-slate-500">{labels.printSheetHint}</div>
              <div className="rounded-2xl border border-slate-100 bg-slate-50 p-3">
                <div className="mb-3 flex items-center justify-between gap-3 text-xs text-slate-500"><span>{labels.printPaperLabel}</span><StatusPill tone="slate">{forms.builder.printModes.portrait}</StatusPill></div>
                <div className="max-h-[780px] overflow-auto"><div className="origin-top scale-[0.5]"><PrintableFamilyRegistration locale={activeLocale} labels={labels} template={template} values={values} totalAmount={totalAmount} financeCatalogMap={financeCatalogMap} receipt={receipt} /></div></div>
              </div>
            </section>
          </aside>
        </div>
      </section>

      <section className="print-only py-6">
        <PrintableFamilyRegistration locale={activeLocale} labels={labels} template={template} values={values} totalAmount={totalAmount} financeCatalogMap={financeCatalogMap} receipt={receipt} />
        <div className="mx-auto mt-4 w-full max-w-[794px] rounded-2xl border border-brand-100 bg-brand-50 px-4 py-3 text-sm text-brand-800">{labels.printReceiptBanner}</div>
      </section>
    </main>
  );
}

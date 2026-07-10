import StudentRegistrationSuccessShell from '@/components/student-registration-success-shell';
import { getFormsSuccessDictionary } from '@/lib/i18n';
import { formatDateForLocale } from '@/lib/locale-config';

export default async function StudentRegistrationSuccessPage({ params, searchParams }) {
  const locale = params.locale;
  const { forms, labels } = await getFormsSuccessDictionary(locale, 'studentRegistration');

  const payload = {
    ref: searchParams?.ref || '—',
    submittedAt: searchParams?.submittedAt ? formatDateForLocale(locale, String(searchParams.submittedAt).slice(0, 10)) : '—',
    applicant: searchParams?.applicant || '—'
  };

  return <StudentRegistrationSuccessShell locale={locale} labels={labels} forms={forms} payload={payload} formPath={`/${locale}/forms/student-registration`} builderPath={`/${locale}/forms/builder`} />;
}

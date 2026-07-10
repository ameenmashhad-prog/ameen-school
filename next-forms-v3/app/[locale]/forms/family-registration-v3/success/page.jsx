import StudentRegistrationSuccessShell from '@/components/student-registration-success-shell';
import { getFormsSuccessDictionary } from '@/lib/i18n';
import { formatDateForLocale } from '@/lib/locale-config';

export default async function FamilyRegistrationV3SuccessPage({ params, searchParams }) {
  const locale = params.locale;
  const { forms, labels } = await getFormsSuccessDictionary(locale, 'familyRegistrationV3');

  const payload = {
    ref: searchParams?.ref || '—',
    submittedAt: searchParams?.submittedAt ? formatDateForLocale(locale, String(searchParams.submittedAt).slice(0, 10)) : '—',
    applicant: searchParams?.applicant || '—'
  };

  return (
    <StudentRegistrationSuccessShell
      locale={locale}
      labels={labels}
      forms={forms}
      payload={payload}
      formPath={`/${locale}/forms/family-registration-v3`}
      builderPath={`/${locale}/forms/builder`}
    />
  );
}

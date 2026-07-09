import StudentRegistrationShell from '@/components/student-registration-shell';
import { getDictionary } from '@/lib/i18n';

export default async function StudentRegistrationPage({ params }) {
  const locale = params.locale;
  const forms = await getDictionary(locale, 'forms');
  const reports = await getDictionary(locale, 'reports');
  const finance = await getDictionary(locale, 'finance');

  return <StudentRegistrationShell locale={locale} dictionary={{ forms, reports, finance }} />;
}

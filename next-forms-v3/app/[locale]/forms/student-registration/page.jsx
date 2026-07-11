import StudentRegistrationShell from '@/components/student-registration-shell';
import { getFormsPageDictionary } from '@/lib/i18n';

export default async function StudentRegistrationPage({ params }) {
  const { locale } = await params;
  const dictionary = await getFormsPageDictionary(locale, 'studentRegistration');

  return <StudentRegistrationShell locale={locale} dictionary={dictionary} />;
}

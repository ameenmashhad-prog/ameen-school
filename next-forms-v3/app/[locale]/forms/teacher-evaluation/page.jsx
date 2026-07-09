import TeacherEvaluationShell from '@/components/teacher-evaluation-shell';
import { getDictionary } from '@/lib/i18n';

export default async function TeacherEvaluationPage({ params }) {
  const locale = params.locale;
  const forms = await getDictionary(locale, 'forms');
  const reports = await getDictionary(locale, 'reports');
  const finance = await getDictionary(locale, 'finance');

  return <TeacherEvaluationShell locale={locale} dictionary={{ forms, reports, finance }} />;
}

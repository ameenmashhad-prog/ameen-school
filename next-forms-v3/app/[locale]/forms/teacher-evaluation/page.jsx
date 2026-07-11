import TeacherEvaluationShell from '@/components/teacher-evaluation-shell';
import { getFormsPageDictionary } from '@/lib/i18n';

export default async function TeacherEvaluationPage({ params }) {
  const { locale } = await params;
  const dictionary = await getFormsPageDictionary(locale, 'teacherEvaluation');

  return <TeacherEvaluationShell locale={locale} dictionary={dictionary} />;
}

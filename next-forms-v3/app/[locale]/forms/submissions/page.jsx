import FormsSubmissionsShell from '@/components/forms-submissions-shell';
import { getFormsPageDictionary } from '@/lib/i18n';

export default async function FormsSubmissionsPage({ params }) {
  const { locale } = await params;
  const dictionary = await getFormsPageDictionary(locale, 'submissions');

  return <FormsSubmissionsShell locale={locale} dictionary={dictionary} />;
}

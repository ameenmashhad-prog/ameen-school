import { getFormsBuilderDictionary } from '@/lib/i18n';
import FormsStudioShell from '@/components/forms-studio-shell';

export default async function FormsBuilderPage({ params }) {
  const locale = params.locale;
  const dictionary = await getFormsBuilderDictionary(locale);

  return (
    <FormsStudioShell
      locale={locale}
      dictionary={dictionary}
    />
  );
}

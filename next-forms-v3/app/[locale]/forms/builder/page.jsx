import { getDictionary } from '@/lib/i18n';
import FormsStudioShell from '@/components/forms-studio-shell';

export default async function FormsBuilderPage({ params }) {
  const locale = params.locale;
  const forms = await getDictionary(locale, 'forms');
  const reports = await getDictionary(locale, 'reports');
  const finance = await getDictionary(locale, 'finance');

  return (
    <FormsStudioShell
      locale={locale}
      dictionary={{ forms, reports, finance }}
    />
  );
}

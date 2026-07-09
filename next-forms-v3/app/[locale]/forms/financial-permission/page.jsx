import FinancialPermissionShell from '@/components/financial-permission-shell';
import { getDictionary } from '@/lib/i18n';

export default async function FinancialPermissionPage({ params }) {
  const locale = params.locale;
  const forms = await getDictionary(locale, 'forms');
  const reports = await getDictionary(locale, 'reports');
  const finance = await getDictionary(locale, 'finance');

  return <FinancialPermissionShell locale={locale} dictionary={{ forms, reports, finance }} />;
}

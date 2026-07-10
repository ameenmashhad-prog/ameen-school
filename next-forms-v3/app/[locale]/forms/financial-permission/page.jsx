import FinancialPermissionShell from '@/components/financial-permission-shell';
import { getFormsPageDictionary } from '@/lib/i18n';

export default async function FinancialPermissionPage({ params }) {
  const locale = params.locale;
  const dictionary = await getFormsPageDictionary(locale, 'financialPermission');

  return <FinancialPermissionShell locale={locale} dictionary={dictionary} />;
}

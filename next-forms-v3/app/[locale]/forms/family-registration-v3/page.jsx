import FamilyRegistrationV3Shell from '@/components/family-registration-v3-shell';
import { getDictionary } from '@/lib/i18n';

export default async function FamilyRegistrationV3Page({ params }) {
  const locale = params.locale;
  const forms = await getDictionary(locale, 'forms');
  const reports = await getDictionary(locale, 'reports');
  const finance = await getDictionary(locale, 'finance');

  return <FamilyRegistrationV3Shell locale={locale} dictionary={{ forms, reports, finance }} />;
}

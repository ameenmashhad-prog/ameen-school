import FamilyRegistrationV3Shell from '@/components/family-registration-v3-shell';
import { getFormsPageDictionary } from '@/lib/i18n';

export default async function FamilyRegistrationV3Page({ params }) {
  const locale = params.locale;
  const dictionary = await getFormsPageDictionary(locale, 'familyRegistrationV3');

  return <FamilyRegistrationV3Shell locale={locale} dictionary={dictionary} />;
}

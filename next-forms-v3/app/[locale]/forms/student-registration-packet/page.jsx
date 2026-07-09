import RegistrationPacketShell from '@/components/registration-packet-shell';
import { getDictionary } from '@/lib/i18n';

export default async function StudentRegistrationPacketPage({ params }) {
  const locale = params.locale;
  const forms = await getDictionary(locale, 'forms');
  const reports = await getDictionary(locale, 'reports');
  const finance = await getDictionary(locale, 'finance');

  return <RegistrationPacketShell locale={locale} dictionary={{ forms, reports, finance }} />;
}

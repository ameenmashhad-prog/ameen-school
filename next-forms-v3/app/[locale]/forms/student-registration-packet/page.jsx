import RegistrationPacketShell from '@/components/registration-packet-shell';
import { getFormsPageDictionary } from '@/lib/i18n';

export default async function StudentRegistrationPacketPage({ params }) {
  const { locale } = await params;
  const dictionary = await getFormsPageDictionary(locale, 'registrationPacket');

  return <RegistrationPacketShell locale={locale} dictionary={dictionary} />;
}

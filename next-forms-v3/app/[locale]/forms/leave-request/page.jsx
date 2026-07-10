import LeaveRequestShell from '@/components/leave-request-shell';
import { getFormsPageDictionary } from '@/lib/i18n';

export default async function LeaveRequestPage({ params }) {
  const locale = params.locale;
  const dictionary = await getFormsPageDictionary(locale, 'leaveRequest');

  return <LeaveRequestShell locale={locale} dictionary={dictionary} />;
}

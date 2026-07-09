import LeaveRequestShell from '@/components/leave-request-shell';
import { getDictionary } from '@/lib/i18n';

export default async function LeaveRequestPage({ params }) {
  const locale = params.locale;
  const forms = await getDictionary(locale, 'forms');
  const reports = await getDictionary(locale, 'reports');
  const finance = await getDictionary(locale, 'finance');

  return <LeaveRequestShell locale={locale} dictionary={{ forms, reports, finance }} />;
}

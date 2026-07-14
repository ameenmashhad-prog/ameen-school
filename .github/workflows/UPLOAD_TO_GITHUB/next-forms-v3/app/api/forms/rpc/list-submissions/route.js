import { handleAdminRpc } from '@/lib/security/forms-api-security';

export async function POST(request) {
  return handleAdminRpc(request, 'forms_list_submissions_v3');
}

import { handleAdminRpc } from '@/lib/security/forms-api-security';

export async function POST(request) {
  return handleAdminRpc(request, 'forms_update_submission_status_v3');
}

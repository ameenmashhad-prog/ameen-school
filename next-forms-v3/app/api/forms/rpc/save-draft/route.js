import { handleAdminRpc } from '@/lib/security/forms-api-security';

export async function POST(request) {
  return handleAdminRpc(request, 'forms_save_draft_v3');
}

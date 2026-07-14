import { handlePublicRpc } from '@/lib/security/forms-api-security';

export async function POST(request) {
  return handlePublicRpc(request, 'forms_submit_financial_permission_v3', {
    action: 'submit-financial-permission',
    limit: 5,
    windowSeconds: 600,
    maxBytes: 524288
  });
}

import { handlePublicRpc } from '@/lib/security/forms-api-security';

export async function POST(request) {
  return handlePublicRpc(request, 'forms_submit_leave_request_v3', {
    action: 'submit-leave-request',
    limit: 5,
    windowSeconds: 600,
    maxBytes: 524288
  });
}

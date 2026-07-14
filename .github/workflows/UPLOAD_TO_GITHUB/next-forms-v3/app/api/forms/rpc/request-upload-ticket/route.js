import { handlePublicRpc } from '@/lib/security/forms-api-security';

export async function POST(request) {
  return handlePublicRpc(request, 'forms_request_upload_ticket_v3', {
    action: 'request-upload-ticket',
    limit: 20,
    windowSeconds: 60,
    maxBytes: 65536
  });
}

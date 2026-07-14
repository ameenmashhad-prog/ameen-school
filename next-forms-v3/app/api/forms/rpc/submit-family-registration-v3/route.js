import { handlePublicRpc } from '@/lib/security/forms-api-security';

export async function POST(request) {
  return handlePublicRpc(request, 'forms_submit_family_registration_v3', {
    action: 'submit-family-registration-v3',
    limit: 5,
    windowSeconds: 600,
    maxBytes: 2097152
  });
}

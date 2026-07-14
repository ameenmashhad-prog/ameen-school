import { handlePublicRpc } from '@/lib/security/forms-api-security';

export async function POST(request) {
  return handlePublicRpc(request, 'forms_submit_student_registration_packet_v3', {
    action: 'submit-student-registration-packet',
    limit: 5,
    windowSeconds: 600,
    maxBytes: 2097152
  });
}

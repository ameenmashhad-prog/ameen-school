import { handlePublicRpc } from '@/lib/security/forms-api-security';

export async function POST(request) {
  return handlePublicRpc(request, 'forms_submit_student_registration_v3', {
    action: 'submit-student-registration',
    limit: 5,
    windowSeconds: 600,
    maxBytes: 1048576
  });
}

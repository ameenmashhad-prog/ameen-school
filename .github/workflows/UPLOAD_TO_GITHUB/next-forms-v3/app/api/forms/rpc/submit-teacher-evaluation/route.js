import { handlePublicRpc } from '@/lib/security/forms-api-security';

export async function POST(request) {
  return handlePublicRpc(request, 'forms_submit_teacher_evaluation_v3', {
    action: 'submit-teacher-evaluation',
    limit: 5,
    windowSeconds: 600,
    maxBytes: 524288
  });
}

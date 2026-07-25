import { handlePublicRpc } from '@/lib/security/forms-api-security';
export async function POST(request) {
  return handlePublicRpc(request, 'send_teacher_admin_message', {
    action: 'send-teacher-message',
    limit: 20,
    windowSeconds: 600,
    maxBytes: 4096
  });
}

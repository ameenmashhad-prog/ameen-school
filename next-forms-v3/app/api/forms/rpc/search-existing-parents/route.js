import { handlePublicRpc } from '@/lib/security/forms-api-security';

export async function POST(request) {
  return handlePublicRpc(request, 'search_existing_parents', {
    action: 'search-existing-parents',
    limit: 10,
    windowSeconds: 60,
    maxBytes: 1024
  });
}

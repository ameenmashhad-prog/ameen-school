function storedAccessToken() {
  if (typeof window === 'undefined') return '';

  const preferredKeys = [
    'amin-ovcjzsrqqgjsbqswtkro-auth-v2',
    'sb-ovcjzsrqqgjsbqswtkro-auth-token'
  ];
  const keys = [
    ...preferredKeys,
    ...Array.from({ length: window.localStorage.length }, (_, index) => window.localStorage.key(index))
      .filter((key) => key && (key.includes('auth-token') || key.includes('-auth-v2')))
  ];

  for (const key of new Set(keys)) {
    try {
      const value = JSON.parse(window.localStorage.getItem(key) || 'null');
      const token = value?.access_token || value?.currentSession?.access_token || value?.session?.access_token;
      if (token) return token;
    } catch {}
  }
  return '';
}

async function call(endpoint, payload, { admin = false } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (admin) {
    const token = storedAccessToken();
    if (!token) throw new Error('ADMIN_AUTH_REQUIRED');
    headers.Authorization = `Bearer ${token}`;
  }

  const response = await fetch(endpoint, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload)
  });
  const result = await response.json().catch(() => ({ ok: false, error: `HTTP_${response.status}` }));
  if (!response.ok || result?.ok === false) {
    throw new Error(result?.error || `RPC failed: ${response.status}`);
  }
  return result;
}

// Respondent drafts stay local unless the user has an authenticated admin session.
// This prevents public form visitors from writing template versions or form values
// into the privileged Forms Studio tables every 15 seconds.
export function saveDraftRpc(payload) {
  const token = storedAccessToken();
  if (!token) {
    return Promise.resolve({
      ok: true,
      localOnly: true,
      data: { version_id: `local-${Date.now()}`, saved_at: new Date().toISOString() }
    });
  }
  return call('/api/forms/rpc/save-draft', payload, { admin: true });
}

export function restoreVersionRpc(payload) {
  return call('/api/forms/rpc/restore-version', payload, { admin: true });
}

export function publishFormRpc(payload) {
  return call('/api/forms/rpc/publish-form', payload, { admin: true });
}

export function listVersionsRpc(payload) {
  const token = storedAccessToken();
  if (!token) return Promise.resolve({ ok: true, localOnly: true, data: { versions: [] } });
  return call('/api/forms/rpc/list-versions', payload, { admin: true });
}

export function submitStudentRegistrationRpc(payload) {
  return call('/api/forms/rpc/submit-student-registration', payload);
}

export function requestUploadTicketRpc(payload) {
  return call('/api/forms/rpc/request-upload-ticket', payload);
}

export async function uploadAttachmentTransport({ ticketId, formSlug, fieldId, file }) {
  const formData = new FormData();
  formData.append('ticket_id', ticketId);
  formData.append('form_slug', formSlug);
  formData.append('field_id', fieldId);
  formData.append('file', file);

  const response = await fetch('/api/forms/upload-file', {
    method: 'POST',
    body: formData
  });
  const result = await response.json().catch(() => ({ ok: false, error: `HTTP_${response.status}` }));
  if (!response.ok || result?.ok === false) throw new Error(result?.error || `Upload failed: ${response.status}`);
  return result;
}

export function listSubmissionsRpc(payload) {
  return call('/api/forms/rpc/list-submissions', payload, { admin: true });
}

export function getSubmissionRpc(payload) {
  return call('/api/forms/rpc/get-submission', payload, { admin: true });
}

export function updateSubmissionStatusRpc(payload) {
  return call('/api/forms/rpc/update-submission-status', payload, { admin: true });
}

export function submitLeaveRequestRpc(payload) {
  return call('/api/forms/rpc/submit-leave-request', payload);
}

export function submitTeacherEvaluationRpc(payload) {
  return call('/api/forms/rpc/submit-teacher-evaluation', payload);
}

export function submitFinancialPermissionRpc(payload) {
  return call('/api/forms/rpc/submit-financial-permission', payload);
}

export function submitStudentRegistrationPacketRpc(payload) {
  return call('/api/forms/rpc/submit-student-registration-packet', payload);
}

export function submitFamilyRegistrationV3Rpc(payload) {
  return call('/api/forms/rpc/submit-family-registration-v3', payload);
}

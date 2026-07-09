async function call(endpoint, payload) {
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });
  if (!response.ok) throw new Error(`RPC failed: ${response.status}`);
  return response.json();
}

export function saveDraftRpc(payload) {
  return call('/api/forms/rpc/save-draft', payload);
}

export function restoreVersionRpc(payload) {
  return call('/api/forms/rpc/restore-version', payload);
}

export function publishFormRpc(payload) {
  return call('/api/forms/rpc/publish-form', payload);
}

export function listVersionsRpc(payload) {
  return call('/api/forms/rpc/list-versions', payload);
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

  if (!response.ok) throw new Error(`Upload failed: ${response.status}`);
  return response.json();
}

export function listSubmissionsRpc(payload) {
  return call('/api/forms/rpc/list-submissions', payload);
}

export function getSubmissionRpc(payload) {
  return call('/api/forms/rpc/get-submission', payload);
}

export function updateSubmissionStatusRpc(payload) {
  return call('/api/forms/rpc/update-submission-status', payload);
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

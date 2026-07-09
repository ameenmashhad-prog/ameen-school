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

import { createClient } from '@supabase/supabase-js';

export function createServerClient() {
  return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false }
  });
}

function normalizeRpcPayload(payload) {
  return Object.fromEntries(
    Object.entries(payload || {}).map(([key, value]) => [key.startsWith('p_') ? key : `p_${key}`, value])
  );
}

export async function callFormRpc(name, payload) {
  const supabase = createServerClient();
  const { data, error } = await supabase.rpc(name, normalizeRpcPayload(payload));
  if (error) {
    return { ok: false, error: error.message, rpc: name };
  }
  if (data && typeof data === 'object' && data.ok === false) {
    return { ok: false, error: data.error || 'rpc_failed', rpc: name, data };
  }
  return { ok: true, rpc: name, data };
}

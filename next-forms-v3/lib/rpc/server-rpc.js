import { createClient } from '@supabase/supabase-js';

export function createServerClient() {
  return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false }
  });
}

export async function callFormRpc(name, payload) {
  const supabase = createServerClient();
  const { data, error } = await supabase.rpc(name, payload);
  if (error) {
    return { ok: false, error: error.message, rpc: name };
  }
  return { ok: true, rpc: name, data };
}

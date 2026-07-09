import { createClient } from '@supabase/supabase-js';

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !key) {
  console.error('Missing NEXT_PUBLIC_SUPABASE_URL and/or key (SUPABASE_SERVICE_ROLE_KEY or NEXT_PUBLIC_SUPABASE_ANON_KEY).');
  process.exit(1);
}

const supabase = createClient(url, key, { auth: { persistSession: false } });
const { data, error } = await supabase.rpc('forms_v3_health_check');

if (error) {
  console.error('forms_v3_health_check failed');
  console.error(JSON.stringify({ message: error.message, code: error.code, details: error.details, hint: error.hint }, null, 2));
  process.exit(2);
}

console.log(JSON.stringify(data, null, 2));

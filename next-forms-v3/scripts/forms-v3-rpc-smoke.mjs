import { createClient } from '@supabase/supabase-js';

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !key) {
  console.error('Missing NEXT_PUBLIC_SUPABASE_URL and/or key (SUPABASE_SERVICE_ROLE_KEY or NEXT_PUBLIC_SUPABASE_ANON_KEY).');
  process.exit(1);
}

const supabase = createClient(url, key, { auth: { persistSession: false } });
const slug = `smoke-forms-v3-${Date.now()}`;
const schema = {
  slug,
  visibility: 'public',
  printOrientation: 'portrait',
  title: { ar: 'فحص دخان', fa: 'تست سریع', en: 'Smoke Test' },
  sections: [{ key: 'general', title: { ar: 'عام', fa: 'عمومی', en: 'General' } }],
  fields: [
    {
      id: 'sample_name',
      type: 'text',
      required: true,
      width: 'full',
      section: 'general',
      label: { ar: 'اسم', fa: 'نام', en: 'Name' },
      placeholder: { ar: 'اكتب هنا', fa: 'اینجا بنویسید', en: 'Type here' },
      helpText: { ar: '', fa: '', en: '' }
    }
  ]
};

const save = await supabase.rpc('forms_save_draft_v3', {
  p_form_slug: slug,
  p_locale: 'ar',
  p_version_label: `smoke:${new Date().toISOString()}`,
  p_visibility: 'public',
  p_schema: schema,
  p_form_values: { sample_name: 'Smoke Test' },
  p_autosave: false
});

if (save.error) {
  console.error('forms_save_draft_v3 failed');
  console.error(JSON.stringify({ message: save.error.message, code: save.error.code, details: save.error.details, hint: save.error.hint }, null, 2));
  process.exit(2);
}

const versions = await supabase.rpc('forms_list_versions_v3', {
  p_form_slug: slug
});

if (versions.error) {
  console.error('forms_list_versions_v3 failed');
  console.error(JSON.stringify({ message: versions.error.message, code: versions.error.code, details: versions.error.details, hint: versions.error.hint }, null, 2));
  process.exit(3);
}

console.log(JSON.stringify({
  slug,
  save: save.data,
  versions: versions.data
}, null, 2));

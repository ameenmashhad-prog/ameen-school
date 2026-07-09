import { NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const bucketName = process.env.FORMS_UPLOAD_BUCKET || 'forms-v3-uploads';

function serverClient() {
  return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false }
  });
}

export async function POST(request) {
  const formData = await request.formData();
  const file = formData.get('file');
  const ticketId = formData.get('ticket_id');
  const formSlug = formData.get('form_slug');
  const fieldId = formData.get('field_id');

  if (!file || typeof file === 'string') {
    return NextResponse.json({ ok: false, error: 'missing_file' }, { status: 400 });
  }

  if (!ticketId || typeof ticketId !== 'string') {
    return NextResponse.json({ ok: false, error: 'missing_ticket_id' }, { status: 400 });
  }

  const ext = file.name.includes('.') ? file.name.split('.').pop() : 'bin';
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]+/g, '_');
  const objectPath = `${formSlug || 'form'}/${fieldId || 'file'}/${ticketId}_${safeName}`;
  const buffer = Buffer.from(await file.arrayBuffer());

  try {
    const supabase = serverClient();
    const { error } = await supabase.storage.from(bucketName).upload(objectPath, buffer, {
      contentType: file.type || 'application/octet-stream',
      upsert: true
    });

    if (error) {
      return NextResponse.json({ ok: false, error: error.message, bucket: bucketName }, { status: 500 });
    }

    return NextResponse.json({
      ok: true,
      bucket: bucketName,
      object_path: objectPath,
      file_name: file.name,
      content_type: file.type || 'application/octet-stream',
      byte_size: file.size || 0
    });
  } catch (error) {
    return NextResponse.json({ ok: false, error: error.message || 'upload_failed' }, { status: 500 });
  }
}

import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';

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

  try {
    const supabase = serverClient();

    const resolve = await supabase.rpc('forms_resolve_upload_ticket_v3', {
      p_ticket_id: ticketId,
      p_form_slug: String(formSlug || ''),
      p_field_id: String(fieldId || ''),
      p_file_name: file.name
    });

    if (resolve.error || !resolve.data?.ok) {
      return NextResponse.json(
        { ok: false, error: resolve.error?.message || resolve.data?.error || 'upload_ticket_invalid' },
        { status: 400 }
      );
    }

    const objectPath = resolve.data.object_path;
    const buffer = Buffer.from(await file.arrayBuffer());

    const upload = await supabase.storage.from(bucketName).upload(objectPath, buffer, {
      contentType: file.type || 'application/octet-stream',
      upsert: true
    });

    if (upload.error) {
      return NextResponse.json({ ok: false, error: upload.error.message, bucket: bucketName }, { status: 500 });
    }

    const finalize = await supabase.rpc('forms_finalize_upload_ticket_v3', {
      p_ticket_id: ticketId,
      p_object_path: objectPath
    });

    if (finalize.error || !finalize.data?.ok) {
      return NextResponse.json(
        { ok: false, error: finalize.error?.message || finalize.data?.error || 'upload_ticket_finalize_failed' },
        { status: 500 }
      );
    }

    return NextResponse.json({
      ok: true,
      bucket: bucketName,
      object_path: objectPath,
      file_name: file.name,
      content_type: file.type || 'application/octet-stream',
      byte_size: file.size || 0,
      ticket_id: ticketId
    });
  } catch (error) {
    return NextResponse.json({ ok: false, error: error.message || 'upload_failed' }, { status: 500 });
  }
}

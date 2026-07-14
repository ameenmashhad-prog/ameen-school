import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';
import { enforcePublicRateLimit, enforceSameOrigin } from '@/lib/security/forms-api-security';

const bucketName = process.env.FORMS_UPLOAD_BUCKET || 'forms-v3-uploads';
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const ALLOWED_CONTENT_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'application/pdf',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
]);

function serverClient() {
  return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false }
  });
}

function validIdentifier(value, maxLength = 120) {
  return typeof value === 'string'
    && value.length > 0
    && value.length <= maxLength
    && /^[a-zA-Z0-9_-]+$/.test(value);
}

function validFileName(value) {
  return typeof value === 'string'
    && value.length > 0
    && value.length <= 180
    && !/[\\/\0]/.test(value)
    && !/[<>:"|?*]/.test(value);
}

function matchesFileSignature(buffer, contentType) {
  const type = String(contentType || '').toLowerCase();
  if (type === 'image/jpeg') return buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  if (type === 'image/png') return buffer.subarray(0, 8).equals(Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]));
  if (type === 'image/webp') return buffer.subarray(0, 4).toString('ascii') === 'RIFF' && buffer.subarray(8, 12).toString('ascii') === 'WEBP';
  if (type === 'application/pdf') return buffer.subarray(0, 5).toString('ascii') === '%PDF-';
  if (type.includes('openxmlformats-officedocument')) return buffer[0] === 0x50 && buffer[1] === 0x4b && buffer[2] === 0x03 && buffer[3] === 0x04;
  return false;
}

export async function POST(request) {
  const originError = enforceSameOrigin(request);
  if (originError) return originError;

  const rateError = await enforcePublicRateLimit(request, 'upload-file', 20, 3600);
  if (rateError) return rateError;

  const declaredLength = Number(request.headers.get('content-length') || 0);
  if (Number.isFinite(declaredLength) && declaredLength > MAX_FILE_BYTES + (256 * 1024)) {
    return NextResponse.json({ ok: false, error: 'payload_too_large' }, { status: 413 });
  }

  let formData;
  try {
    formData = await request.formData();
  } catch {
    return NextResponse.json({ ok: false, error: 'invalid_multipart_body' }, { status: 400 });
  }

  const file = formData.get('file');
  const ticketId = formData.get('ticket_id');
  const formSlug = formData.get('form_slug');
  const fieldId = formData.get('field_id');

  if (!file || typeof file === 'string') {
    return NextResponse.json({ ok: false, error: 'missing_file' }, { status: 400 });
  }
  if (typeof ticketId !== 'string' || !/^[0-9a-f-]{36}$/i.test(ticketId)) {
    return NextResponse.json({ ok: false, error: 'invalid_ticket_id' }, { status: 400 });
  }
  if (!validIdentifier(formSlug) || !validIdentifier(fieldId, 180)) {
    return NextResponse.json({ ok: false, error: 'invalid_upload_context' }, { status: 400 });
  }
  if (!validFileName(file.name)) {
    return NextResponse.json({ ok: false, error: 'invalid_file_name' }, { status: 400 });
  }
  if (!Number.isFinite(file.size) || file.size <= 0 || file.size > MAX_FILE_BYTES) {
    return NextResponse.json({ ok: false, error: 'invalid_file_size' }, { status: 413 });
  }
  if (!ALLOWED_CONTENT_TYPES.has(String(file.type || '').toLowerCase())) {
    return NextResponse.json({ ok: false, error: 'file_type_not_allowed' }, { status: 415 });
  }

  try {
    const supabase = serverClient();
    const resolve = await supabase.rpc('forms_resolve_upload_ticket_v3', {
      p_ticket_id: ticketId,
      p_form_slug: formSlug,
      p_field_id: fieldId,
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
    if (buffer.byteLength !== file.size || buffer.byteLength > MAX_FILE_BYTES) {
      return NextResponse.json({ ok: false, error: 'file_size_mismatch' }, { status: 400 });
    }
    if (!matchesFileSignature(buffer, file.type)) {
      return NextResponse.json({ ok: false, error: 'file_signature_mismatch' }, { status: 415 });
    }

    const upload = await supabase.storage.from(bucketName).upload(objectPath, buffer, {
      contentType: file.type,
      upsert: false,
      cacheControl: '3600'
    });

    if (upload.error) {
      return NextResponse.json({ ok: false, error: upload.error.message }, { status: 500 });
    }

    const finalize = await supabase.rpc('forms_finalize_upload_ticket_v3', {
      p_ticket_id: ticketId,
      p_object_path: objectPath
    });

    if (finalize.error || !finalize.data?.ok) {
      await supabase.storage.from(bucketName).remove([objectPath]);
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
      content_type: file.type,
      byte_size: file.size,
      ticket_id: ticketId
    }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) {
    console.error('forms upload failed', error);
    return NextResponse.json({ ok: false, error: 'upload_failed' }, { status: 500 });
  }
}

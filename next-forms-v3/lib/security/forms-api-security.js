import { createHmac } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';
import { callFormRpc } from '@/lib/rpc/server-rpc';

const ADMIN_ROLES = new Set(
  String(process.env.FORMS_ADMIN_ROLES || 'admin,academic,academic_admin')
    .split(',')
    .map((role) => role.trim().toLowerCase())
    .filter(Boolean)
);

function envReady() {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL
    && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
    && process.env.SUPABASE_SERVICE_ROLE_KEY
  );
}

function serviceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { persistSession: false, autoRefreshToken: false } }
  );
}

function bearerToken(request) {
  const value = request.headers.get('authorization') || '';
  const match = value.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || '';
}

function requestHost(request) {
  return String(
    request.headers.get('x-forwarded-host')
    || request.headers.get('host')
    || ''
  ).toLowerCase();
}

export function enforceSameOrigin(request) {
  const origin = request.headers.get('origin');
  if (!origin) return null;

  try {
    const originHost = new URL(origin).host.toLowerCase();
    if (originHost === requestHost(request)) return null;
  } catch {}

  return NextResponse.json({ ok: false, error: 'origin_not_allowed' }, { status: 403 });
}

export function enforceJsonBodyLimit(request, maxBytes = 512 * 1024) {
  const length = Number(request.headers.get('content-length') || 0);
  if (Number.isFinite(length) && length > maxBytes) {
    return NextResponse.json({ ok: false, error: 'payload_too_large' }, { status: 413 });
  }
  return null;
}

export async function requireFormsAdmin(request) {
  if (!envReady()) {
    return {
      ok: false,
      response: NextResponse.json({ ok: false, error: 'server_auth_not_configured' }, { status: 503 })
    };
  }

  const token = bearerToken(request);
  if (!token) {
    return {
      ok: false,
      response: NextResponse.json({ ok: false, error: 'authentication_required' }, { status: 401 })
    };
  }

  const authClient = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${token}` } }
    }
  );

  const { data: authData, error: authError } = await authClient.auth.getUser(token);
  const authUser = authData?.user;
  if (authError || !authUser?.id) {
    return {
      ok: false,
      response: NextResponse.json({ ok: false, error: 'invalid_or_expired_session' }, { status: 401 })
    };
  }

  const { data: profile, error: profileError } = await serviceClient()
    .from('users')
    .select('id,role,is_super_admin,active')
    .eq('id', authUser.id)
    .maybeSingle();

  const allowed = !profileError
    && profile
    && profile.active !== false
    && (profile.is_super_admin === true || ADMIN_ROLES.has(String(profile.role || '').toLowerCase()));

  if (!allowed) {
    return {
      ok: false,
      response: NextResponse.json({ ok: false, error: 'forbidden' }, { status: 403 })
    };
  }

  return { ok: true, authUser, profile, token };
}

function requestFingerprint(request) {
  const forwarded = request.headers.get('x-forwarded-for') || '';
  const ip = forwarded.split(',')[0]?.trim()
    || request.headers.get('x-real-ip')
    || 'unknown';
  const userAgent = request.headers.get('user-agent') || 'unknown';
  const secret = process.env.FORMS_RATE_LIMIT_SECRET || process.env.SUPABASE_SERVICE_ROLE_KEY;
  return createHmac('sha256', secret).update(`${ip}|${userAgent}`).digest('hex');
}

export async function enforcePublicRateLimit(request, action, limit, windowSeconds) {
  if (!envReady()) {
    return NextResponse.json({ ok: false, error: 'server_security_not_configured' }, { status: 503 });
  }

  try {
    const { data, error } = await serviceClient().rpc('forms_rate_limit_check_v3', {
      p_key_hash: requestFingerprint(request),
      p_action: action,
      p_limit: limit,
      p_window_seconds: windowSeconds
    });

    if (error) {
      console.error('forms rate-limit RPC failed', error.message);
      return NextResponse.json({ ok: false, error: 'rate_limit_unavailable' }, { status: 503 });
    }

    if (data?.allowed === false) {
      return NextResponse.json(
        { ok: false, error: 'rate_limit_exceeded', retry_after_seconds: data.retry_after_seconds || windowSeconds },
        {
          status: 429,
          headers: { 'Retry-After': String(data.retry_after_seconds || windowSeconds) }
        }
      );
    }
  } catch (error) {
    console.error('forms rate-limit check failed', error);
    return NextResponse.json({ ok: false, error: 'rate_limit_unavailable' }, { status: 503 });
  }

  return null;
}

export async function parseJsonObject(request) {
  try {
    const payload = await request.json();
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
      return { ok: false, response: NextResponse.json({ ok: false, error: 'invalid_json_object' }, { status: 400 }) };
    }
    return { ok: true, payload };
  } catch {
    return { ok: false, response: NextResponse.json({ ok: false, error: 'invalid_json' }, { status: 400 }) };
  }
}

export async function handleAdminRpc(request, rpcName) {
  const originError = enforceSameOrigin(request);
  if (originError) return originError;

  const sizeError = enforceJsonBodyLimit(request, 1024 * 1024);
  if (sizeError) return sizeError;

  const authorization = await requireFormsAdmin(request);
  if (!authorization.ok) return authorization.response;

  const parsed = await parseJsonObject(request);
  if (!parsed.ok) return parsed.response;

  const result = await callFormRpc(rpcName, parsed.payload);
  return NextResponse.json(result, {
    status: result?.ok === false ? 400 : 200,
    headers: { 'Cache-Control': 'no-store' }
  });
}

export async function handlePublicRpc(request, rpcName, options = {}) {
  const originError = enforceSameOrigin(request);
  if (originError) return originError;

  const sizeError = enforceJsonBodyLimit(request, options.maxBytes || 1024 * 1024);
  if (sizeError) return sizeError;

  const rateError = await enforcePublicRateLimit(
    request,
    options.action || rpcName,
    options.limit || 10,
    options.windowSeconds || 60
  );
  if (rateError) return rateError;

  const parsed = await parseJsonObject(request);
  if (!parsed.ok) return parsed.response;

  const result = await callFormRpc(rpcName, parsed.payload);
  return NextResponse.json(result, {
    status: result?.ok === false ? 400 : 200,
    headers: { 'Cache-Control': 'no-store' }
  });
}

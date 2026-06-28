const SUPABASE_URL = 'https://ovcjzsrqqgjsbqswtkro.supabase.co';
const MAX_BODY_BYTES = 6 * 1024 * 1024;
const ALLOWED_PREFIXES = ['/rest/v1/', '/auth/v1/', '/storage/v1/'];

function originAllowed(req) {
  const origin = req.headers.origin;
  if (!origin) return null;
  const host = req.headers['x-forwarded-host'] || req.headers.host;
  const allowed = new Set([
    `https://${host}`,
    `http://${host}`,
    ...(process.env.ALLOWED_ORIGINS || '').split(',').map(x => x.trim()).filter(Boolean)
  ]);
  try {
    const u = new URL(origin);
    if (allowed.has(origin)) return origin;
    // Allow same Vercel preview host only when the request is served from the same host.
    if (String(host || '').endsWith('.vercel.app') && u.host === host) return origin;
  } catch {}
  return false;
}

function normalizeTargetPath(req) {
  let path = req.url || '';
  path = path.replace(/^\/api\/proxy(?=\/|\?|$)/, '');
  path = path.replace(/^\/api(?=\/|\?|$)/, '');
  if (!path.startsWith('/')) path = '/' + path;
  return path;
}

export default async function handler(req, res) {
  const allowedOrigin = originAllowed(req);
  if (allowedOrigin === false) return res.status(403).json({ error: 'origin_not_allowed' });
  if (allowedOrigin) res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'authorization,apikey,content-type,accept,prefer,range,x-client-info');
  res.setHeader('Cache-Control', 'no-store');

  if (req.method === 'OPTIONS') return res.status(200).end();

  const targetPath = normalizeTargetPath(req);
  if (!ALLOWED_PREFIXES.some(p => targetPath.startsWith(p))) {
    return res.status(403).json({ error: 'supabase_path_not_allowed', path: targetPath.split('?')[0] });
  }
  if (targetPath.startsWith('/realtime/')) {
    return res.status(403).json({ error: 'realtime_websocket_not_supported_by_proxy' });
  }

  const len = Number(req.headers['content-length'] || 0);
  if (len > MAX_BODY_BYTES) return res.status(413).json({ error: 'payload_too_large' });

  const targetUrl = SUPABASE_URL + targetPath;
  const headers = {};
  const forward = ['authorization', 'apikey', 'content-type', 'accept', 'prefer', 'range', 'x-client-info'];
  for (const key of forward) {
    const value = req.headers[key];
    if (value) headers[key] = value;
  }

  try {
    let body;
    if (!['GET', 'HEAD'].includes(req.method)) {
      body = typeof req.body === 'string' ? req.body : (req.body ? JSON.stringify(req.body) : undefined);
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    const response = await fetch(targetUrl, { method: req.method, headers, body, signal: controller.signal });
    clearTimeout(timer);

    const text = await response.text();
    const contentType = response.headers.get('content-type') || 'application/json';
    const contentRange = response.headers.get('content-range');
    const rangeUnit = response.headers.get('range-unit');
    res.setHeader('Content-Type', contentType);
    if (contentRange) res.setHeader('Content-Range', contentRange);
    if (rangeUnit) res.setHeader('Range-Unit', rangeUnit);
    res.status(response.status).send(text);
  } catch (e) {
    const aborted = e && e.name === 'AbortError';
    res.status(aborted ? 504 : 500).json({ error: aborted ? 'upstream_timeout' : (e.message || 'proxy_failed') });
  }
}

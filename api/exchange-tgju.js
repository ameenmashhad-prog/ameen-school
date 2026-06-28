function originAllowed(req) {
  const origin = req.headers.origin;
  if (!origin) return null;
  const host = req.headers['x-forwarded-host'] || req.headers.host;
  const allowed = new Set([
    `https://${host}`,
    `http://${host}`,
    ...(process.env.ALLOWED_ORIGINS || '').split(',').map(x => x.trim()).filter(Boolean)
  ]);
  return allowed.has(origin) ? origin : false;
}

export default async function handler(req, res) {
  const allowedOrigin = originAllowed(req);
  if (allowedOrigin === false) return res.status(403).json({ ok: false, error: 'origin_not_allowed' });
  if (allowedOrigin) res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'content-type,accept');
  res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=900');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'method_not_allowed' });

  const sources = [
    { name: 'tgju_profile', url: 'https://www.tgju.org/profile/price_dollar_rl' },
    { name: 'tgju_today', url: 'https://www.tgju.org/profile/price_dollar_rl/today' },
    { name: 'tgju_home', url: 'https://www.tgju.org/' }
  ];

  function parseRate(html) {
    const clean = String(html || '').replace(/&nbsp;/g, ' ');
    const patterns = [
      /نرخ\s*فعلی\s*[:：]?\s*([0-9,]+)/,
      /\|\s*نرخ\s*فعلی\s*\|\s*([0-9,]+)/,
      /price_dollar_rl[^0-9]{0,240}([0-9]{1,3}(?:,[0-9]{3}){1,})/i,
      /دلار[^0-9]{0,120}([0-9]{1,3}(?:,[0-9]{3}){1,})/,
      /([0-9]{1,3}(?:,[0-9]{3}){2,})\s*ریال/
    ];
    for (const p of patterns) {
      const m = clean.match(p);
      if (m && m[1]) {
        const n = Number(String(m[1]).replace(/,/g, ''));
        if (Number.isFinite(n) && n > 0) return n;
      }
    }
    return null;
  }

  const errors = [];
  for (const src of sources) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 9000);
    try {
      const response = await fetch(src.url, {
        signal: controller.signal,
        headers: {
          'user-agent': 'Mozilla/5.0 (compatible; AminSchoolFinance/1.0)',
          'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        }
      });
      clearTimeout(timer);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const html = await response.text();
      const rate = parseRate(html);
      if (!rate) throw new Error('parse_failed');
      return res.status(200).json({ ok: true, source: src.name, rate, currency: 'IRR', fetched_at: new Date().toISOString() });
    } catch (e) {
      clearTimeout(timer);
      errors.push({ source: src.name, error: e.name === 'AbortError' ? 'timeout' : e.message });
    }
  }

  return res.status(502).json({ ok: false, source: 'all_failed', rate: 0, errors, fetched_at: new Date().toISOString() });
}

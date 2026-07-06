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

const SOURCES = [
  { name: 'iranjib_home', label: 'IranJib.ir', url: 'https://www.iranjib.ir/' },
  { name: 'iranjib_price', label: 'IranJib.ir / price', url: 'https://www.iranjib.ir/price/' },
  { name: 'tala_ir', label: 'Tala.ir', url: 'https://www.tala.ir/' },
  { name: 'ice_ir', label: 'ICE.ir', url: 'https://www.ice.ir/' }
];

function faToEnDigits(s) {
  return String(s || '')
    .replace(/[۰-۹]/g, d => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(d)))
    .replace(/[٠-٩]/g, d => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)));
}

function cleanNumber(raw) {
  return Number(String(raw || '').replace(/[٬,\s]/g, ''));
}

function median(values) {
  const sorted = values.slice().sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (!sorted.length) return 0;
  return sorted.length % 2 ? sorted[mid] : Math.round((sorted[mid - 1] + sorted[mid]) / 2);
}

function pickRate(html) {
  const raw = faToEnDigits(String(html || '').replace(/&nbsp;/g, ' '));
  const compact = raw.replace(/\s+/g, ' ');
  const patterns = [
    /(?:قیمت|نرخ)\s*دلار(?:\s*آمریکا)?[^0-9]{0,80}([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i,
    /دلار(?:\s*آمریکا)?[^0-9]{0,40}([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i,
    /usd[^0-9]{0,40}([0-9][0-9٬,]{4,})\s*(toman|rial)?/i,
    /([0-9][0-9٬,]{4,})\s*(تومان|ریال)\s*[^<]{0,30}دلار/i
  ];

  for (const rx of patterns) {
    const m = compact.match(rx);
    if (!m || !m[1]) continue;
    let rate = cleanNumber(m[1]);
    const unit = String(m[2] || '').toLowerCase();
    if (!Number.isFinite(rate) || rate <= 0) continue;
    if (unit.includes('تومان') || unit.includes('toman')) rate *= 10;
    if (rate < 10000 || rate > 50000000) continue;
    return rate;
  }

  const keywordHits = [];
  const generic = [...compact.matchAll(/(?:دلار|usd)[^0-9]{0,60}([0-9][0-9٬,]{4,})/ig)];
  for (const hit of generic) {
    const rate = cleanNumber(hit[1]);
    if (Number.isFinite(rate) && rate >= 10000 && rate <= 50000000) keywordHits.push(rate);
  }
  return keywordHits.length ? keywordHits[0] : null;
}

async function fetchSource(src) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
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
    const rate = pickRate(html);
    if (!rate) throw new Error('parse_failed');
    return { ok: true, ...src, rate };
  } catch (e) {
    clearTimeout(timer);
    return { ok: false, ...src, error: e.name === 'AbortError' ? 'timeout' : e.message };
  }
}

export default async function handler(req, res) {
  const allowedOrigin = originAllowed(req);
  if (allowedOrigin === false) return res.status(403).json({ ok: false, error: 'origin_not_allowed' });
  if (allowedOrigin) res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'content-type,accept');
  res.setHeader('Cache-Control', 's-maxage=180, stale-while-revalidate=600');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'method_not_allowed' });

  const settled = await Promise.all(SOURCES.map(fetchSource));
  const success = settled.filter(x => x.ok && x.rate);
  const errors = settled.filter(x => !x.ok).map(x => ({ source: x.name, label: x.label, error: x.error }));

  if (!success.length) {
    return res.status(502).json({
      ok: false,
      error: 'all_ir_sources_failed',
      source: 'all_failed',
      source_label: 'تعذر الوصول إلى مصادر .ir',
      rate: 0,
      errors,
      fetched_at: new Date().toISOString()
    });
  }

  const usedRate = success.length === 1 ? success[0].rate : median(success.map(x => x.rate));
  const primary = success[0];

  return res.status(200).json({
    ok: true,
    source: success.length === 1 ? primary.name : 'multi_ir_consensus',
    source_label: success.length === 1 ? primary.label : `متوسط ${success.length} مصادر إيرانية (.ir)`,
    url: primary.url,
    rate: usedRate,
    currency: 'IRR',
    sources_checked: success.length,
    sources_used: success.map(x => ({ name: x.name, label: x.label, rate: x.rate, url: x.url })),
    errors,
    fetched_at: new Date().toISOString()
  });
}

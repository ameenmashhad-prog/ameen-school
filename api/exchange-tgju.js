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
  { name: 'tgju_profile', label: 'TGJU.org', url: 'https://www.tgju.org/profile/price_dollar_rl', parser: 'tgju' },
  { name: 'tgju_exchange', label: 'TGJU.org / currency-exchange', url: 'https://www.tgju.org/currency-exchange', parser: 'tgju' },
  { name: 'iranjib_dollar', label: 'IranJib.ir', url: 'https://www.iranjib.ir/showgroup/23/realtime_price/', parser: 'iranjib' },
  { name: 'tala_dollar', label: 'Tala.ir', url: 'https://www.tala.ir/price/dolar', parser: 'tala' }
];

function faToEnDigits(s) {
  return String(s || '')
    .replace(/[۰-۹]/g, d => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(d)))
    .replace(/[٠-٩]/g, d => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)));
}

function cleanNumber(raw) {
  return Number(String(raw || '').replace(/[٬,\s]/g, ''));
}

function normalizeRate(rate, unitHint) {
  let n = cleanNumber(rate);
  if (!Number.isFinite(n) || n <= 0) return null;
  const unit = String(unitHint || '').toLowerCase();
  if (unit.includes('تومان') || unit.includes('toman')) n *= 10;
  if (n < 10000 || n > 50000000) return null;
  return n;
}

function median(values) {
  const sorted = values.slice().sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (!sorted.length) return 0;
  return sorted.length % 2 ? sorted[mid] : Math.round((sorted[mid - 1] + sorted[mid]) / 2);
}

function pickWithPatterns(text, patterns) {
  for (const rx of patterns) {
    const m = text.match(rx);
    if (!m || !m[1]) continue;
    const rate = normalizeRate(m[1], m[2]);
    if (rate) return rate;
  }
  return null;
}

function genericRate(html) {
  const raw = faToEnDigits(String(html || '').replace(/&nbsp;/g, ' '));
  const compact = raw.replace(/\s+/g, ' ');
  return pickWithPatterns(compact, [
    /(?:قیمت|نرخ)\s*دلار(?:\s*آمریکا)?[^0-9]{0,80}([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i,
    /دلار(?:\s*آمریکا)?[^0-9]{0,40}([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i,
    /usd[^0-9]{0,40}([0-9][0-9٬,]{4,})\s*(toman|rial)?/i,
    /([0-9][0-9٬,]{4,})\s*(تومان|ریال)\s*[^<]{0,30}دلار/i,
    /قیمت\s*زنده[^0-9]{0,50}([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i
  ]);
}

function parseRate(html, parser) {
  const raw = faToEnDigits(String(html || '').replace(/&nbsp;/g, ' '));
  const compact = raw.replace(/\s+/g, ' ');

  if (parser === 'tgju') {
    const rate = pickWithPatterns(compact, [
      /price_dollar_rl[^0-9]{0,240}([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i,
      /دلار\s*[^0-9]{0,50}قیمت\s*زنده[^0-9]{0,50}([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i,
      /قیمت\s*زنده[^0-9]{0,50}([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i,
      /currency-exchange[^]{0,500}?([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i
    ]);
    return rate || genericRate(compact);
  }

  if (parser === 'iranjib') {
    const rate = pickWithPatterns(compact, [
      /دلار\s*\/\s*اسکناس[^0-9]{0,60}([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i,
      /دلار\s*\/\s*حواله[^0-9]{0,60}([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i
    ]);
    return rate || genericRate(compact);
  }

  if (parser === 'tala') {
    const rate = pickWithPatterns(compact, [
      /قیمت\s*دلار\s*آمریکا[^0-9]{0,80}([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i,
      /price\/dolar[^0-9]{0,200}([0-9][0-9٬,]{4,})\s*(تومان|ریال)?/i
    ]);
    return rate || genericRate(compact);
  }

  return genericRate(compact);
}

async function fetchSource(src) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch(src.url, {
      signal: controller.signal,
      headers: {
        'user-agent': 'Mozilla/5.0 (compatible; AminSchoolFinance/1.0)',
        'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'accept-language': 'fa-IR,fa;q=0.9,en;q=0.7'
      }
    });
    clearTimeout(timer);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const html = await response.text();
    const rate = parseRate(html, src.parser);
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
      source_label: 'تعذر الوصول إلى TGJU والمصادر الإيرانية',
      rate: 0,
      errors,
      fetched_at: new Date().toISOString()
    });
  }

  const usedRate = success.length === 1 ? success[0].rate : median(success.map(x => x.rate));
  const primary = success[0];

  return res.status(200).json({
    ok: true,
    source: success.length === 1 ? primary.name : 'multi_iran_consensus',
    source_label: success.length === 1 ? primary.label : `متوسط ${success.length} مصادر إيرانية + TGJU`,
    url: primary.url,
    rate: usedRate,
    currency: 'IRR',
    sources_checked: success.length,
    sources_used: success.map(x => ({ name: x.name, label: x.label, rate: x.rate, url: x.url })),
    errors,
    fetched_at: new Date().toISOString()
  });
}

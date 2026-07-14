import { NextResponse } from 'next/server';
import { callFormRpc } from '@/lib/rpc/server-rpc';

function classStageOrder(name) {
  const normalized = String(name || '')
    .replace(/[إأآا]/g, 'ا')
    .replace(/[ىي]/g, 'ي')
    .replace(/ة/g, 'ه')
    .replace(/\s+/g, '')
    .toLowerCase();
  if (normalized.includes('ابتدائي')) return 1;
  if (normalized.includes('متوسط')) return 2;
  if (normalized.includes('اعدادي')) return 3;
  return 9;
}

function classGradeOrder(name) {
  const normalized = String(name || '')
    .replace(/[إأآا]/g, 'ا')
    .replace(/[ىي]/g, 'ي')
    .replace(/ة/g, 'ه')
    .replace(/\s+/g, '')
    .toLowerCase();
  const rules = [
    ['الاول', 1], ['اول', 1], ['الثاني', 2], ['ثاني', 2], ['الثالث', 3], ['ثالث', 3],
    ['الرابع', 4], ['رابع', 4], ['الخامس', 5], ['خامس', 5], ['السادس', 6], ['سادس', 6]
  ];
  const match = rules.find(([token]) => normalized.includes(token));
  return match ? match[1] : 99;
}

export async function GET() {
  try {
    const response = await callFormRpc('forms_get_family_registration_finance_catalog_v3', {
      p_academic_year: '2026-2027'
    });

    if (response?.ok === false) {
      return NextResponse.json({ ok: false, error: response.error || 'finance_catalog_failed' }, { status: 500 });
    }

    const raw = response?.data || {};
    const items = [...(raw.items || [])].sort((a, b) => {
      return (classStageOrder(a.class_name) - classStageOrder(b.class_name))
        || (classGradeOrder(a.class_name) - classGradeOrder(b.class_name))
        || String(a.class_name || '').localeCompare(String(b.class_name || ''), 'ar');
    });

    return NextResponse.json({
      ok: true,
      items,
      updated_at: new Date().toISOString()
    }, {
      headers: { 'Cache-Control': 'public, s-maxage=300, stale-while-revalidate=600' }
    });
  } catch (error) {
    return NextResponse.json({ ok: false, error: error.message || 'finance_catalog_failed' }, { status: 500 });
  }
}

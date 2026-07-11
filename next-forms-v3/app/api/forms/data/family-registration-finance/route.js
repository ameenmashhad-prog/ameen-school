import { NextResponse } from 'next/server';
import { createServerClient } from '@/lib/rpc/server-rpc';

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
    const supabase = createServerClient();

    const [{ data: classes, error: classesError }, { data: fees, error: feesError }] = await Promise.all([
      supabase.from('classes').select('id,name').order('name'),
      supabase.from('fee_structures').select('id,class_id,annual_fee,amount,monthly_fee,currency,academic_year,is_active,updated_at').eq('is_active', true).order('updated_at', { ascending: false })
    ]);

    if (classesError) {
      return NextResponse.json({ ok: false, error: classesError.message, source: 'classes' }, { status: 500 });
    }

    if (feesError) {
      return NextResponse.json({ ok: false, error: feesError.message, source: 'fee_structures' }, { status: 500 });
    }

    const sortedClasses = [...(classes || [])].sort((a, b) => {
      return (classStageOrder(a.name) - classStageOrder(b.name))
        || (classGradeOrder(a.name) - classGradeOrder(b.name))
        || String(a.name || '').localeCompare(String(b.name || ''), 'ar');
    });

    const latestFeeByClass = new Map();
    (fees || []).forEach((fee) => {
      if (!latestFeeByClass.has(String(fee.class_id))) {
        latestFeeByClass.set(String(fee.class_id), fee);
      }
    });

    const items = sortedClasses.map((classItem) => {
      const fee = latestFeeByClass.get(String(classItem.id));
      const annualFee = Number(fee?.annual_fee ?? fee?.amount ?? 0) || 0;
      const monthlyFee = Number(fee?.monthly_fee ?? (annualFee ? annualFee / 9 : 0)) || 0;
      return {
        class_id: classItem.id,
        class_name: classItem.name,
        fee_structure_id: fee?.id || null,
        annual_fee: annualFee,
        monthly_fee: monthlyFee,
        currency: fee?.currency || 'USD',
        academic_year: fee?.academic_year || '2026-2027',
        has_finance_rule: Boolean(fee)
      };
    });

    return NextResponse.json({
      ok: true,
      items,
      updated_at: new Date().toISOString()
    });
  } catch (error) {
    return NextResponse.json({ ok: false, error: error.message || 'finance_catalog_failed' }, { status: 500 });
  }
}

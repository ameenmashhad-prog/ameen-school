-- ============================================================================
-- Family Registration v3 — public fee catalog RPC
-- الهدف:
-- - إتاحة قراءة رسوم الصفوف للنموذج العام family-registration-v3
--   دون كشف بقية صفحات الإدارة المالية
-- - استخدام Security Definer بدل الاعتماد على service role في الواجهة
-- ============================================================================

create or replace function public.forms_get_family_registration_finance_catalog_v3(
  p_academic_year text default '2026-2027'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'class_id', c.id,
          'class_name', c.name,
          'fee_structure_id', fs.id,
          'annual_fee', coalesce(fs.annual_fee, fs.amount, 0),
          'monthly_fee', coalesce(fs.monthly_fee, round((coalesce(fs.annual_fee, fs.amount, 0) / 9.0)::numeric, 2), 0),
          'currency', coalesce(fs.currency, 'USD'),
          'academic_year', coalesce(fs.academic_year, p_academic_year),
          'has_finance_rule', (fs.id is not null)
        )
        order by c.name
      )
      from public.classes c
      left join lateral (
        select *
        from public.fee_structures f
        where f.class_id = c.id
          and coalesce(f.academic_year, p_academic_year) = p_academic_year
          and coalesce(f.is_active, true) = true
        order by f.updated_at desc nulls last, f.created_at desc nulls last
        limit 1
      ) fs on true
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.forms_get_family_registration_finance_catalog_v3(text) to authenticated, anon;

notify pgrst, 'reload schema';

-- ============================================================================
-- Optional compatibility patch for finance visibility
--
-- الهدف:
-- 1) ضمان إمكانية قراءة finance_payment_plans من حسابات الإدارة/المالية
-- 2) إعادة إنشاء v_finance_student_ledger إذا كانت مفقودة في البيئة الحية
-- ============================================================================

alter table public.finance_payment_plans enable row level security;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'finance_payment_plans'
      AND policyname = 'finance_payment_plans_admin_read'
  ) THEN
    CREATE POLICY finance_payment_plans_admin_read
      ON public.finance_payment_plans
      FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.users u
          WHERE u.id = auth.uid()
            AND (u.role IN ('admin','finance') OR COALESCE(u.is_super_admin,false)=true)
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'finance_payment_plans'
      AND policyname = 'finance_payment_plans_admin_write'
  ) THEN
    CREATE POLICY finance_payment_plans_admin_write
      ON public.finance_payment_plans
      FOR ALL TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.users u
          WHERE u.id = auth.uid()
            AND (u.role IN ('admin','finance') OR COALESCE(u.is_super_admin,false)=true)
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1
          FROM public.users u
          WHERE u.id = auth.uid()
            AND (u.role IN ('admin','finance') OR COALESCE(u.is_super_admin,false)=true)
        )
      );
  END IF;
END $$;

drop view if exists public.v_finance_student_ledger;

create or replace view public.v_finance_student_ledger
with (security_invoker=true) as
select
  s.id as student_id,
  s.name as student_name,
  s.father_name,
  s.last_name,
  c.name as class_name,
  p.name as parent_name,
  sf.id as student_fee_id,
  sf.academic_year,
  coalesce(sf.gross_amount, sf.base_amount, 0) as gross_amount,
  coalesce(sf.discount_amount, 0) as discount_amount,
  coalesce(sf.net_amount, sf.base_amount, 0) as net_amount,
  coalesce(sf.total_paid, 0) as total_paid,
  greatest(coalesce(sf.net_amount, sf.base_amount, 0) - coalesce(sf.total_paid, 0), 0) as remaining_amount,
  sf.status
from public.students s
left join public.classes c on c.id = s.class_id
left join public.users p on p.id = s.parent_id
left join public.student_fees sf on sf.student_id = s.id;

grant select on public.v_finance_student_ledger to authenticated;

notify pgrst, 'reload schema';

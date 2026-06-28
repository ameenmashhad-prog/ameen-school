-- =============================================================
-- مدارس أمين الرضا (ع) — تنظيف ملفات الرسوم المكررة بأمان
-- يحذف فقط الملفات المكررة التي لا تحتوي مدفوعات ولا أقساط مدفوعة.
-- يحتفظ بالملف الذي يحتوي أعلى total_paid ثم الأقدم.
-- =============================================================

create extension if not exists pgcrypto;

drop table if exists temp_duplicate_fee_review;
create temporary table temp_duplicate_fee_review as
with ranked as (
  select
    sf.*,
    row_number() over (
      partition by sf.student_id, sf.academic_year
      order by coalesce(sf.total_paid,0) desc, sf.created_at asc nulls last, sf.id
    ) as rn,
    coalesce((select sum(coalesce(fp.amount_usd, fp.amount, 0)) from public.fee_payments fp where fp.student_fee_id = sf.id),0) as payments_sum,
    coalesce((select sum(coalesce(si.amount_paid,0)) from public.student_installments si where si.student_fee_id = sf.id),0) as installments_paid_sum
  from public.student_fees sf
  where sf.student_id is not null
)
select * from ranked where rn > 1;

-- عرض المرشحين قبل الحذف في Notices
-- حذف الأقساط غير المدفوعة التابعة للملفات المكررة الآمنة
with safe_dups as (
  select id
  from temp_duplicate_fee_review
  where coalesce(total_paid,0)=0
    and payments_sum=0
    and installments_paid_sum=0
)
delete from public.student_installments si
using safe_dups d
where si.student_fee_id = d.id;

-- حذف ملفات الرسوم المكررة الآمنة فقط
with safe_dups as (
  select id
  from temp_duplicate_fee_review
  where coalesce(total_paid,0)=0
    and payments_sum=0
    and installments_paid_sum=0
)
delete from public.student_fees sf
using safe_dups d
where sf.id = d.id;

-- تقرير ما بقي من مكررات تحتاج مراجعة يدوية لأنها تحتوي مبالغ
select
  s.name as student_name,
  d.student_id,
  d.academic_year,
  d.id as duplicate_fee_id,
  d.base_amount,
  d.net_amount,
  d.total_paid,
  d.payments_sum,
  d.installments_paid_sum,
  case
    when coalesce(d.total_paid,0)=0 and d.payments_sum=0 and d.installments_paid_sum=0 then 'deleted_if_safe'
    else 'manual_review_required'
  end as cleanup_status
from temp_duplicate_fee_review d
left join public.students s on s.id = d.student_id
order by s.name, d.created_at;

notify pgrst, 'reload schema';

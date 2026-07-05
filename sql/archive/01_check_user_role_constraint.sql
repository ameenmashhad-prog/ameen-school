-- قراءة فقط: افحصي قيد الأدوار في جدول users إذا لم يقبل role='academic'
select conname, pg_get_constraintdef(oid) as constraint_def
from pg_constraint
where conrelid = 'public.users'::regclass
  and pg_get_constraintdef(oid) ilike '%role%';

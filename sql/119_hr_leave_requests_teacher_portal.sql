-- ============================================================================
-- R2 — نظام إجازات المعلمين والموظفين (Leave Requests for Teachers & Staff)
-- يتيح للمعلمين تقديم طلبات الإجازة ومتابعة حالتها عبر دالة get_my_leave_requests،
-- ويطور دالة hr_request_leave لربط الموظف تلقائياً بـ hr_employee_profiles عند التقديم.
--
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

-- 1) دالة جلب طلبات إجازة المستخدم الحالي (للعرض في لوحة المعلم/الموظف)
create or replace function public.get_my_leave_requests()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_res json;
begin
  select coalesce(json_agg(x order by x.created_at desc), '[]'::json) into v_res
  from (
    select l.id, l.leave_type, l.start_date, l.end_date, l.days_count, l.reason, l.status, l.created_at,
           coalesce(e.full_name, 'أنا') as full_name
    from public.hr_leave_requests l
    join public.hr_employee_profiles e on e.id = l.employee_id
    where e.user_id = auth.uid() or l.requested_by = auth.uid()
    limit 100
  ) x;
  return coalesce(v_res, '[]'::json);
end;
$$;

grant execute on function public.get_my_leave_requests() to authenticated, anon;

-- 2) تطوير دالة التقديم على الإجازة لتدعم المعلمين والموظفين ذاتياً بدون وسيط
create or replace function public.hr_request_leave(
  p_employee_id uuid,
  p_leave_type text,
  p_start_date date,
  p_end_date date,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  e record;
  u record;
  leave_id uuid;
  days numeric;
  v_emp_id uuid := p_employee_id;
begin
  -- إذا لم يرسل المعرف، نستخدم المعرف الشخصي للمستخدم الحالي
  if v_emp_id is null then v_emp_id := auth.uid(); end if;

  -- البحث عن ملف الموظف في hr_employee_profiles
  select * into e from public.hr_employee_profiles
  where id = v_emp_id or user_id = v_emp_id or (v_emp_id = auth.uid() and user_id = auth.uid())
  limit 1;

  -- في حال عدم وجود ملف موظف (معلم جديد لم تتم إضافته يدوياً في الموارد البشرية)، نقوم بإنشاء ملف له تلقائياً
  if e.id is null and (v_emp_id = auth.uid() or public.hr_can_manage()) then
    select id, name, phone, role into u from public.users where id = v_emp_id or id = auth.uid() limit 1;
    if u.id is not null then
      insert into public.hr_employee_profiles (user_id, employee_code, full_name, job_title, phone, status, created_by)
      values (u.id, 'EMP-' || upper(substr(u.id::text, 1, 8)), coalesce(nullif(trim(u.name),''), 'معلم/موظف'), coalesce(u.role, 'teacher'), u.phone, 'active', auth.uid())
      returning * into e;
    end if;
  end if;

  if e.id is null then
    return jsonb_build_object('ok', false, 'message', 'لم يتم العثور على ملف موظف لهذا الحساب. يرجى التواصل مع الإدارة.');
  end if;

  if not (public.hr_can_manage() or e.user_id = auth.uid() or e.id = v_emp_id) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية طلب إجازة لهذا الموظف');
  end if;

  if p_end_date < p_start_date then
    return jsonb_build_object('ok', false, 'message', 'تاريخ انتهاء الإجازة لا يمكن أن يكون قبل تاريخ البداية');
  end if;

  if p_leave_type not in ('annual','sick','unpaid','emergency','maternity','other') then p_leave_type := 'annual'; end if;
  days := (p_end_date - p_start_date) + 1;

  insert into public.hr_leave_requests(employee_id, leave_type, start_date, end_date, days_count, reason, requested_by, status)
  values (e.id, p_leave_type, p_start_date, p_end_date, days, p_reason, auth.uid(), 'pending')
  returning id into leave_id;

  return jsonb_build_object('ok', true, 'message', 'تم إرسال طلب الإجازة للموارد البشرية بنجاح', 'leave_id', leave_id, 'employee_id', e.id);
end;
$$;

grant execute on function public.hr_request_leave(uuid,text,date,date,text) to authenticated, anon;

-- إعادة تحميل كاش المخطط في PostgREST فوراً
NOTIFY pgrst, 'reload schema';

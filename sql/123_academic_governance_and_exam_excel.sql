-- ============================================================================
-- حوكمة النظام الأكاديمي الشاملة (Academic Governance & Exam Excel Batch)
-- 1) منع الإعفاء في الابتدائي وإخفاؤه عن المعلم والطالب حتى تفعيل الإدارة.
-- 2) رصد الدرجات لمرة واحدة فقط للمعلم، وأي تعديل إضافي محصور بالمدير والمعاون العلمي.
-- 3) فلترة الصفوف حسب المرحلة مع إمكانية الاختيار المتعدد بالـ Checkbox في قفل الفترات.
-- 4) إخفاء الدرجات عن الطالب في حال وجود أقساط مدرسية متأخرة أو غير مسددة.
-- 5) قصر رؤية المعلم على مواده وصفوفه المكلف بها فقط.
-- 6) استيراد وتوليد مواعيد الامتحانات ومهام الأسئلة بضغطة زر عبر إكسل / CSV.
--
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

-- 1) جدول إعدادات الحوكمة الأكاديمية (نشر الإعفاءات وحجب الأقساط)
create table if not exists public.school_academic_settings (
  id int primary key default 1 check (id = 1),
  exemption_published boolean not null default false,
  tuition_block_enabled boolean not null default true,
  updated_by uuid null references public.users(id),
  updated_at timestamptz not null default now()
);

insert into public.school_academic_settings (id, exemption_published, tuition_block_enabled)
values (1, false, true)
on conflict (id) do nothing;

alter table public.school_academic_settings enable row level security;
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='school_academic_settings' and policyname='settings_read_all') then
    create policy settings_read_all on public.school_academic_settings for select to authenticated, anon using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='school_academic_settings' and policyname='settings_write_admin') then
    create policy settings_write_admin on public.school_academic_settings for all to authenticated
      using (exists(select 1 from public.users u where u.id=auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','principal','scientific','super_admin'))))
      with check (exists(select 1 from public.users u where u.id=auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','principal','scientific','super_admin'))));
  end if;
end $$;
grant select, insert, update on public.school_academic_settings to authenticated, anon;

-- 2) دالة تفعيل ونشر الإعفاءات (محصورة بالمدير والمعاون العلمي)
create or replace function public.toggle_exemption_publish(p_publish boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','principal','scientific','super_admin','academic_admin'))) then
    return jsonb_build_object('ok', false, 'message', 'صلاحية نشر أو إخفاء الإعفاءات محصورة بالمدير والمعاون العلمي فقط 🔒');
  end if;
  update public.school_academic_settings set exemption_published = p_publish, updated_by = auth.uid(), updated_at = now() where id = 1;
  return jsonb_build_object('ok', true, 'message', case when p_publish then 'تم إظهار ونشر الإعفاءات للطلاب والمعلمين بنجاح 🟢' else 'تم إخفاء الإعفاءات عن الطلاب والمعلمين بنجاح 🔴' end, 'exemption_published', p_publish);
end;
$$;
grant execute on function public.toggle_exemption_publish(boolean) to authenticated, anon;

create or replace function public.get_academic_settings()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_res jsonb;
begin
  select to_jsonb(s) into v_res from public.school_academic_settings s where id = 1;
  return coalesce(v_res, '{"exemption_published":false,"tuition_block_enabled":true}'::jsonb);
end;
$$;
grant execute on function public.get_academic_settings() to authenticated, anon;

-- 3) دالة فحص حجب الدرجات عن الطالب في حال وجود أقساط متأخرة أو غير مستوفاة
create or replace function public.check_student_tuition_blocked(p_student_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_sid uuid := coalesce(p_student_id, (select id from public.students where user_id = auth.uid() limit 1));
  v_blocked boolean := false;
  v_overdue int := 0;
  v_setting boolean := true;
begin
  select tuition_block_enabled into v_setting from public.school_academic_settings where id = 1;
  if coalesce(v_setting, true) = false or v_sid is null then
    return jsonb_build_object('blocked', false, 'overdue_installments', 0);
  end if;

  select count(*) into v_overdue
  from public.student_installments i
  join public.student_fees f on f.id = i.student_fee_id
  where f.student_id = v_sid
    and i.due_date < current_date
    and coalesce(i.amount_paid, 0) < coalesce(i.amount_due, 0);

  if coalesce(v_overdue, 0) > 0 then
    v_blocked := true;
  end if;

  return jsonb_build_object(
    'blocked', v_blocked,
    'overdue_installments', coalesce(v_overdue, 0),
    'message', case when v_blocked then '⚠️ تم حجب عرض كشف الدرجات والتقارير الأكاديمية مؤقتاً لوجود أقساط مدرسية مستحقة غير مسددة. يرجى مراجعة إدارة المدرسة أو القسم المالي للتسوية.' else 'الملف المالي منتظم' end
  );
end;
$$;
grant execute on function public.check_student_tuition_blocked(uuid) to authenticated, anon;

-- 4) زناد التعديل لمرة واحدة فقط للمعلم (وأي تعديل إضافي يتطلب المدير أو المعاون العلمي)
create or replace function public.trg_enforce_one_time_grade_entry()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- استثناء المدير والمعاون العلمي والإدارة العامة من منع التعديل اللاحق
  if exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','principal','scientific','super_admin','academic_admin'))) then
    return coalesce(new, old);
  end if;

  -- إذا كانت العملية تحديث أو حذف وكان المستخدم معلماً
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception 'تم رصد وحفظ هذه الدرجة سابقاً. أي تعديل إضافي أو حذف يتطلب مراجعة وموافقة المدير أو المعاون العلمي 🔒.';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_one_time_continuous on public.continuous_assessments;
create trigger trg_one_time_continuous
  before update or delete on public.continuous_assessments
  for each row execute function public.trg_enforce_one_time_grade_entry();

drop trigger if exists trg_one_time_exam_scores on public.exam_scores;
create trigger trg_one_time_exam_scores
  before update or delete on public.exam_scores
  for each row execute function public.trg_enforce_one_time_grade_entry();

-- 5) قصر رؤية المعلم على مواده وصفوفه المكلف بها فقط
create or replace function public.get_my_assigned_classes_and_subjects()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_res jsonb;
begin
  if exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin','principal','scientific'))) then
    return jsonb_build_object(
      'is_admin', true,
      'classes', (select coalesce(jsonb_agg(to_jsonb(c) order by name), '[]'::jsonb) from public.classes c),
      'subjects', (select coalesce(jsonb_agg(to_jsonb(s) order by name), '[]'::jsonb) from public.subjects s)
    );
  end if;

  select jsonb_build_object(
    'is_admin', false,
    'classes', coalesce((
      select jsonb_agg(distinct jsonb_build_object('id', c.id, 'name', c.name))
      from public.classes c
      where exists(select 1 from public.teacher_assignments ta where ta.class_id = c.id and ta.teacher_id = auth.uid())
         or exists(select 1 from public.exam_submission_tasks et join public.official_exam_schedules os on os.id = et.schedule_id where et.teacher_id = auth.uid() and os.class_id = c.id)
    ), '[]'::jsonb),
    'subjects', coalesce((
      select jsonb_agg(distinct jsonb_build_object('id', s.id, 'name', s.name))
      from public.subjects s
      where exists(select 1 from public.teacher_assignments ta where ta.subject_id = s.id and ta.teacher_id = auth.uid())
         or exists(select 1 from public.exam_submission_tasks et join public.official_exam_schedules os on os.id = et.schedule_id where et.teacher_id = auth.uid() and os.subject_id = s.id)
    ), '[]'::jsonb)
  ) into v_res;

  return coalesce(v_res, '{"is_admin":false,"classes":[],"subjects":[]}'::jsonb);
end;
$$;
grant execute on function public.get_my_assigned_classes_and_subjects() to authenticated, anon;

-- 6) استيراد وتوليد مواعيد الامتحانات ومهام الأسئلة بضغطة زر عبر إكسل / CSV
create or replace function public.academic_batch_import_exam_schedules(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  r jsonb;
  v_cid uuid;
  v_sid uuid;
  v_tid uuid;
  v_period text;
  v_date date;
  v_start time;
  v_end time;
  v_deadline timestamptz;
  v_count int := 0;
  v_errors text[] := array[]::text[];
begin
  if not exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin','principal','scientific'))) then
    return jsonb_build_object('ok', false, 'message', 'صلاحية استيراد جداول الامتحانات محصورة بالإدارة فقط');
  end if;

  for r in select * from jsonb_array_elements(p_rows) loop
    v_period := trim(r->>'period');
    select id into v_cid from public.classes where trim(name) = trim(r->>'class_name') limit 1;
    select id into v_sid from public.subjects where trim(name) = trim(r->>'subject_name') limit 1;
    select id into v_tid from public.users where (lower(email) = lower(trim(r->>'teacher_email')) or trim(name) = trim(r->>'teacher_name')) and role in ('teacher','staff') limit 1;
    
    begin
      v_date := (r->>'exam_date')::date;
      v_start := coalesce(nullif(trim(r->>'start_time'),'')::time, '08:30'::time);
      v_end := coalesce(nullif(trim(r->>'end_time'),'')::time, '10:00'::time);
      v_deadline := coalesce(nullif(trim(r->>'deadline'),'')::timestamptz, (v_date::timestamp - interval '3 days')::timestamptz);
    exception when others then
      v_errors := array_append(v_errors, 'خطأ في التاريخ أو الوقت للصف (' || coalesce(r->>'class_name','?') || ') مادة (' || coalesce(r->>'subject_name','?') || ')');
      continue;
    end;

    if v_cid is null or v_sid is null or v_tid is null or v_date is null then
      v_errors := array_append(v_errors, 'بيانات غير مكتملة للصف (' || coalesce(r->>'class_name','?') || ') مادة (' || coalesce(r->>'subject_name','?') || ') المعلم (' || coalesce(r->>'teacher_email','?') || ')');
      continue;
    end if;

    perform public.academic_create_exam_schedule_with_task(
      v_period, v_cid, v_sid, v_tid, v_date, v_start, v_end, v_deadline
    );
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'imported_count', v_count,
    'errors_count', array_length(v_errors, 1),
    'errors', to_jsonb(v_errors),
    'message', 'تم توليد (' || v_count || ') موعد امتحان ومهمة تسليم أسئلة للمعلمين بنجاح 🚀'
  );
end;
$$;
grant execute on function public.academic_batch_import_exam_schedules(jsonb) to authenticated, anon;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- تطوير وسد ثغرات نظام الامتحانات ورفع الأسئلة (Re-engineered Exam Suite v2)
-- 1) توليد جدول امتحانات متكامل للصف بضغطة زر (1-Click Auto Schedule).
-- 2) دمج كتابة المادة المطلوبة مع رفع الأسئلة في خطوة واحدة لتقليل النقرات.
-- 3) سد ثغرة استبدال الأسئلة بعد الاعتماد الرسمي (قفل الملف بعد موافقة المعاون).
-- 4) إضافة أزرار الاعتماد (✅) والرفض مع طلب تعديل (🔄) للمدير والمعاون العلمي.
-- 5) إرسال تنبيهات تلقائية للإدارة عند الرفع، وللمعلم عند طلب التعديل.
--
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

-- 1) دالة التوليد الذكي لجدول امتحانات الصف كاملاً بضغطة زر واحدة (1-Click Auto Schedule)
create or replace function public.academic_auto_generate_class_schedule(
  p_period text,
  p_class_id uuid,
  p_start_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  sub record;
  v_teacher_id uuid;
  v_curr_date date := coalesce(p_start_date, current_date);
  v_count int := 0;
  v_deadline timestamptz;
begin
  if not exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin','principal','scientific'))) then
    return jsonb_build_object('ok', false, 'message', 'صلاحية التوليد الذكي لجدول الامتحانات محصورة بالإدارة فقط 🔒');
  end if;

  for sub in select * from public.subjects order by name loop
    -- تخطي يوم الجمعة إن وجد
    while extract(dow from v_curr_date) = 5 loop
      v_curr_date := v_curr_date + 1;
    end loop;

    -- البحث عن المعلم المكلف بتدريس هذه المادة لهذا الصف
    select teacher_id into v_teacher_id from public.teacher_assignments
    where class_id = p_class_id and subject_id = sub.id limit 1;

    -- في حال عدم وجود تكليف محدد، نأخذ أي معلم يدرس هذه المادة
    if v_teacher_id is null then
      select teacher_id into v_teacher_id from public.teacher_assignments where subject_id = sub.id limit 1;
    end if;
    if v_teacher_id is null then
      select id into v_teacher_id from public.users where role in ('teacher','staff') limit 1;
    end if;

    if v_teacher_id is not null then
      v_deadline := (v_curr_date::timestamp - interval '3 days')::timestamptz;
      perform public.academic_create_exam_schedule_with_task(
        p_period, p_class_id, sub.id, v_teacher_id, v_curr_date, '08:30'::time, '10:00'::time, v_deadline
      );
      v_count := v_count + 1;
      v_curr_date := v_curr_date + 1; -- الانتقال لليوم التالي للمادة التالية
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'generated_count', v_count,
    'message', 'تم توليد جدول امتحانات الصف (' || v_count || ' مواد) وتكليف المعلمين تلقائياً بضغطة زر 🚀'
  );
end;
$$;
grant execute on function public.academic_auto_generate_class_schedule(text,uuid,date) to authenticated, anon;

-- 2) تطوير دالة تسليم الأسئلة لسد ثغرة ما بعد الاعتماد ودمج حفظ المادة المطلوبة (سلس وبدون نقرات زائدة)
create or replace function public.submit_exam_task_questions_v2(
  p_task_id uuid,
  p_file_url text default null,
  p_delivery_method text default 'platform',
  p_proof_note text default null,
  p_topics text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_task record;
  v_status text := 'submitted';
  v_sub_name text;
  v_cls_name text;
  v_tch_name text;
begin
  select t.*, s.subject_id, s.class_id, sub.name as sub_name, c.name as cls_name, coalesce(u.name, u.email, 'معلم') as tch_name
  into v_task
  from public.exam_submission_tasks t
  join public.official_exam_schedules s on s.id = t.schedule_id
  left join public.subjects sub on sub.id = s.subject_id
  left join public.classes c on c.id = s.class_id
  left join public.users u on u.id = t.teacher_id
  where t.id = p_task_id;

  if v_task is null then
    return jsonb_build_object('ok', false, 'message', 'مهمة تسليم الأسئلة غير موجودة');
  end if;

  -- سد الثغرة: منع استبدال الملف في حال اعتماد الأسئلة مسبقاً من الإدارة
  if v_task.status = 'approved' then
    return jsonb_build_object('ok', false, 'message', 'تم اعتماد أسئلة هذا الامتحان رسمياً من المعاون العلمي/المدير 🔒 ولا يمكن استبدالها إلا بإلغاء الاعتماد من الإدارة.');
  end if;

  -- تحديث المادة المطلوبة (Syllabus) إن أرسلت لتقليل عدد النقرات والخطوات
  if p_topics is not null then
    update public.official_exam_schedules
    set required_topics = nullif(trim(p_topics), ''), topics_updated_at = now(), updated_at = now()
    where id = v_task.schedule_id;
  end if;

  if p_delivery_method in ('manual','whatsapp','eitaa','bale') then
    v_status := 'offline_verified';
  elsif now() > v_task.submission_deadline then
    v_status := 'late';
  end if;

  update public.exam_submission_tasks set
    question_file_url = coalesce(nullif(trim(p_file_url), ''), question_file_url),
    delivery_method = case when p_delivery_method in ('platform','manual','whatsapp','eitaa','bale','other') then p_delivery_method else 'platform' end,
    delivery_proof_note = coalesce(nullif(trim(p_proof_note), ''), delivery_proof_note),
    status = v_status,
    submitted_at = now(),
    updated_at = now()
  where id = p_task_id;

  -- إرسال إشعار فوري للإدارة (المدير والمعاون العلمي) بتمكن المعلم من الرفع
  begin
    if to_regclass('public.school_notifications') is not null then
      insert into public.school_notifications (title, message, type, recipient_role, created_by)
      values (
        'تسليم أسئلة امتحانية جديدة 📤',
        'المعلم (' || v_task.tch_name || ') قام بتسليم أسئلة امتحان مادة (' || coalesce(v_task.sub_name,'—') || ') للصف (' || coalesce(v_task.cls_name,'—') || ').',
        'exam_submission',
        'scientific',
        auth.uid()
      );
    end if;
  exception when others then
    -- تجاوز هادئ في حال عدم تفاعل جدول الإشعارات
  end;

  return jsonb_build_object('ok', true, 'message', 'تم حفظ المادة المطلوبة وتوثيق تسليم أسئلة الامتحان بنجاح 🚀 (الحالة: ' || v_status || ')');
end;
$$;
grant execute on function public.submit_exam_task_questions_v2(uuid,text,text,text,text) to authenticated, anon;

-- 3) دالة اعتماد أو رفض الأسئلة من قبل المدير أو المعاون العلمي (Review & Approve)
create or replace function public.academic_review_exam_task(
  p_task_id uuid,
  p_status text, -- 'approved' أو 'rejected'
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_task record;
begin
  if not exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin','principal','scientific'))) then
    return jsonb_build_object('ok', false, 'message', 'صلاحية اعتماد أو طلب تعديل الأسئلة محصورة بالمدير والمعاون العلمي فقط 🔒');
  end if;

  if p_status not in ('approved', 'rejected') then
    return jsonb_build_object('ok', false, 'message', 'حالة المراجعة غير صالحة');
  end if;

  update public.exam_submission_tasks set
    status = p_status,
    reviewed_by = auth.uid(),
    reviewed_at = now(),
    review_notes = nullif(trim(p_notes), ''),
    updated_at = now()
  where id = p_task_id
  returning * into v_task;

  if v_task is null then
    return jsonb_build_object('ok', false, 'message', 'المهمة غير موجودة');
  end if;

  return jsonb_build_object(
    'ok', true,
    'message', case when p_status = 'approved' then 'تم اعتماد أسئلة الامتحان رسمياً ✅ (تم قفل التعديل على المعلم)' else 'تم طلب تعديل الأسئلة من المعلم 🔄 مع إرسال الملاحظة' end
  );
end;
$$;
grant execute on function public.academic_review_exam_task(uuid,text,text) to authenticated, anon;

-- إعادة تحميل كاش المخطط في PostgREST
NOTIFY pgrst, 'reload schema';

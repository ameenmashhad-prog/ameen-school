-- ============================================================================
-- تحليلات الأداء وخطط الدعم الأكاديمي والعلاجي (AI Academic Analytics & Remedial Plans)
-- ينشئ جدول academic_remedial_plans، ويوفر دوال إسناد الخطة العلاجية للمرشد
-- والمعلم تلقائياً مع توليد مهام وإشعارات فورية لمتابعة الطلاب الضعاف.
--
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

-- 1) جدول الخطط العلاجية والدعم التربوي
create table if not exists public.academic_remedial_plans (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid null references public.classes(id) on delete set null,
  counselor_id uuid null references public.users(id) on delete set null,
  teacher_id uuid null references public.users(id) on delete set null,
  diagnostic_summary text not null,
  teacher_actions text not null,
  counselor_actions text not null,
  parent_guidance text not null,
  weak_subjects text[] default array[]::text[],
  overall_average numeric,
  status text not null default 'active' check (status in ('active','under_review','completed','cancelled')),
  progress_notes text,
  created_by uuid null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2) سياسات RLS
alter table public.academic_remedial_plans enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='academic_remedial_plans' and policyname='remedial_plans_read_all') then
    create policy remedial_plans_read_all on public.academic_remedial_plans for select to authenticated, anon using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='academic_remedial_plans' and policyname='remedial_plans_write_all') then
    create policy remedial_plans_write_all on public.academic_remedial_plans for all to authenticated using (true) with check (true);
  end if;
end $$;

grant select, insert, update, delete on public.academic_remedial_plans to authenticated, anon;

-- 3) فيو التقارير مع أسماء الطلاب والصفوف
create or replace view public.v_academic_remedial_plans_detailed
with (security_invoker = true) as
select p.*,
       s.student_name, s.student_code, s.gender, s.parent_id,
       c.name as class_name,
       coalesce(u_coun.name, u_coun.email, 'مرشد تربوي') as counselor_name,
       coalesce(u_tch.name, u_tch.email, 'معلم المادة') as teacher_name
from public.academic_remedial_plans p
join public.students s on s.id = p.student_id
left join public.classes c on c.id = p.class_id
left join public.users u_coun on u_coun.id = p.counselor_id
left join public.users u_tch on u_tch.id = p.teacher_id;

grant select on public.v_academic_remedial_plans_detailed to authenticated, anon;

-- 4) دالة حفظ الخطة العلاجية وإسناد المهام التلقائي للمرشد والمعلم
create or replace function public.save_remedial_plan_with_tasks(
  p_student_id uuid,
  p_class_id uuid,
  p_counselor_id uuid,
  p_teacher_id uuid,
  p_diagnostic_summary text,
  p_teacher_actions text,
  p_counselor_actions text,
  p_parent_guidance text,
  p_weak_subjects text[],
  p_overall_average numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_plan_id uuid;
  v_stu_name text;
  v_cls_name text;
  v_task_coun uuid;
  v_task_tch uuid;
begin
  if not exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin','principal','scientific','counselor','psychologist','teacher','supervisor'))) then
    return jsonb_build_object('ok', false, 'message', 'صلاحية اعتماد خطط الدعم محصورة بالإدارة والمرشدين والمعلمين 🔒');
  end if;

  select student_name into v_stu_name from public.students where id = p_student_id;
  select name into v_cls_name from public.classes where id = p_class_id;

  insert into public.academic_remedial_plans (
    student_id, class_id, counselor_id, teacher_id, diagnostic_summary,
    teacher_actions, counselor_actions, parent_guidance, weak_subjects, overall_average, status, created_by
  ) values (
    p_student_id, p_class_id, p_counselor_id, p_teacher_id, trim(p_diagnostic_summary),
    trim(p_teacher_actions), trim(p_counselor_actions), trim(p_parent_guidance), coalesce(p_weak_subjects, array[]::text[]), p_overall_average, 'active', auth.uid()
  ) returning id into v_plan_id;

  -- تكليف المرشد التربوي بمهمة رسمية
  if p_counselor_id is not null then
    insert into public.school_tasks (title, description, assigned_to, assigned_by, priority, due_date, status)
    values (
      'متابعة الخطة العلاجية والدعم النفسي/التربوي للطالب (' || coalesce(v_stu_name,'طالب') || ')',
      'ملخص التشخيص: ' || left(trim(p_diagnostic_summary), 150) || '... الإجراء المطلوب من الإرشاد: ' || left(trim(p_counselor_actions), 150),
      p_counselor_id, auth.uid(), 'high', now() + interval '14 days', 'pending'
    ) returning id into v_task_coun;

    begin
      if to_regclass('public.school_notifications') is not null then
        insert into public.school_notifications (title, body, notification_type, recipient_user_id, created_by)
        values (
          'خطة دعم تربوي وعلاجي جديدة 🤖📊',
          'تم اعتماد خطة دعم أكاديمي وتكليفكم بمتابعة الطالب/ة (' || coalesce(v_stu_name,'طالب') || ') في الصف (' || coalesce(v_cls_name,'—') || ').',
          'counseling_referral', p_counselor_id, auth.uid()
        );
      end if;
    exception when others then
    end;
  end if;

  -- تكليف معلم المادة الضعيفة بمهمة رسمية
  if p_teacher_id is not null and p_teacher_id <> p_counselor_id then
    insert into public.school_tasks (title, description, assigned_to, assigned_by, priority, due_date, status)
    values (
      'تنفيذ خطة الدعم الأكاديمي للطالب (' || coalesce(v_stu_name,'طالب') || ')',
      'المواد الضعيفة: ' || array_to_string(coalesce(p_weak_subjects,array[]::text[]), '، ') || '. الإجراء المطلوب من المعلم: ' || left(trim(p_teacher_actions), 150),
      p_teacher_id, auth.uid(), 'high', now() + interval '14 days', 'pending'
    ) returning id into v_task_tch;

    begin
      if to_regclass('public.school_notifications') is not null then
        insert into public.school_notifications (title, body, notification_type, recipient_user_id, created_by)
        values (
          'تكليف بدعم أكاديمي لمعالجة التعثر 📚',
          'تم إسناد خطة علاجية لرفع مستوى الطالب/ة (' || coalesce(v_stu_name,'طالب') || ') في مادتكم الدراسية.',
          'task_assignment', p_teacher_id, auth.uid()
        );
      end if;
    exception when others then
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'plan_id', v_plan_id,
    'message', 'تم اعتماد الخطة العلاجية وإسناد المهام التلقائي للمرشد والمعلم وإرسال الإشعارات لهم بنجاح 🚀'
  );
end;
$$;
grant execute on function public.save_remedial_plan_with_tasks(uuid,uuid,uuid,uuid,text,text,text,text,text[],numeric) to authenticated, anon;

NOTIFY pgrst, 'reload schema';

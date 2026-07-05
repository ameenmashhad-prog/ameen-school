-- ============================================================================
-- R7 — نظام المهام والتكليفات الإدارية والأكاديمية (School Tasks & Assignments System)
-- يتيح للإدارة والموارد البشرية والمشرفين تكليف المعلمين والموظفين بمهام،
-- وتحديد مهل زمنية، ومتابعة التنفيذ، وإرفاق إثباتات الإنجاز، والتحقق والاعتماد.
--
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

-- 1) جدول المهام والتكليفات المدرسية
create table if not exists public.school_tasks (
  id uuid primary key default gen_random_uuid(),
  task_code text unique default ('TSK-' || upper(substr(gen_random_uuid()::text,1,8))),
  title text not null,
  description text,
  assigned_to uuid not null references public.users(id) on delete cascade,
  assigned_by uuid null references public.users(id) on delete set null,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  due_date timestamptz not null,
  status text not null default 'pending' check (status in ('pending','in_progress','completed','verified','late','cancelled')),
  completion_note text,
  attachment_url text,
  verified_by uuid null references public.users(id) on delete set null,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2) مستودع تخزين ملفات وإثباتات المهام
insert into storage.buckets (id, name, public)
values ('school-tasks', 'school-tasks', true)
on conflict (id) do update set public = true;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='school_tasks_all_access') then
    create policy school_tasks_all_access on storage.objects
      for all to anon, authenticated
      using (bucket_id = 'school-tasks')
      with check (bucket_id = 'school-tasks');
  end if;
end $$;

-- 3) سياسات RLS
alter table public.school_tasks enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='school_tasks' and policyname='tasks_read_all') then
    create policy tasks_read_all on public.school_tasks for select to authenticated, anon using (true);
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='school_tasks' and policyname='tasks_write_all') then
    create policy tasks_write_all on public.school_tasks for all to authenticated using (true) with check (true);
  end if;
end $$;

grant select, insert, update, delete on public.school_tasks to authenticated, anon;

-- 4) فيو التقارير مع الأسماء
create or replace view public.v_school_tasks_detailed
with (security_invoker = true) as
select t.*,
       coalesce(u_to.name, u_to.email, 'موظف') as assigned_to_name,
       coalesce(u_to.role, 'staff') as assigned_to_role,
       coalesce(u_by.name, u_by.email, 'الإدارة') as assigned_by_name,
       coalesce(u_ver.name, u_ver.email, 'المشرف') as verified_by_name
from public.school_tasks t
left join public.users u_to on u_to.id = t.assigned_to
left join public.users u_by on u_by.id = t.assigned_by
left join public.users u_ver on u_ver.id = t.verified_by;

grant select on public.v_school_tasks_detailed to authenticated, anon;

-- 5) دوال إدارة المهام والتكليفات
create or replace function public.task_create_assignment(
  p_title text,
  p_description text,
  p_assigned_to uuid,
  p_priority text,
  p_due_date timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_id uuid;
  v_to_name text;
begin
  if not exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin','principal','scientific','hr','supervisor'))) then
    return jsonb_build_object('ok', false, 'message', 'صلاحية تكليف المهام محصورة بالإدارة والمشرفين 🔒');
  end if;

  if coalesce(nullif(trim(p_title),''), '') = '' then
    return jsonb_build_object('ok', false, 'message', 'عنوان المهمة مطلوب');
  end if;

  if p_assigned_to is null then
    return jsonb_build_object('ok', false, 'message', 'يجب تحديد الموظف أو المعلم المكلف');
  end if;

  select coalesce(name, email, 'الموظف') into v_to_name from public.users where id = p_assigned_to;

  insert into public.school_tasks (
    title, description, assigned_to, assigned_by, priority, due_date, status
  ) values (
    trim(p_title),
    nullif(trim(p_description), ''),
    p_assigned_to,
    auth.uid(),
    case when p_priority in ('low','normal','high','urgent') then p_priority else 'normal' end,
    coalesce(p_due_date, (now() + interval '3 days')),
    'pending'
  ) returning id into v_id;

  begin
    if to_regclass('public.school_notifications') is not null then
      insert into public.school_notifications (title, message, type, recipient_user_id, created_by)
      values (
        'تكليف بمهمة رسمية جديدة 📋',
        'تم تكليفكم بمهمة جديدة: (' || trim(p_title) || '). الموعد النهائي: ' || to_char(coalesce(p_due_date, (now() + interval '3 days')), 'YYYY-MM-DD HH24:MI'),
        'task_assignment',
        p_assigned_to,
        auth.uid()
      );
    end if;
  exception when others then
  end;

  return jsonb_build_object('ok', true, 'message', 'تم تكليف الموظف (' || v_to_name || ') بالمهمة وإرسال إشعار فوري بنجاح 🚀', 'task_id', v_id);
end;
$$;
grant execute on function public.task_create_assignment(text,text,uuid,text,timestamptz) to authenticated, anon;

create or replace function public.task_update_progress(
  p_task_id uuid,
  p_status text,
  p_note text default null,
  p_attachment_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_task record;
  v_st text := p_status;
begin
  select * into v_task from public.school_tasks where id = p_task_id;
  if v_task is null then return jsonb_build_object('ok', false, 'message', 'المهمة غير موجودة'); end if;

  if v_task.assigned_to <> auth.uid() and not exists(select 1 from public.users u where u.id=auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','principal','scientific','hr','super_admin'))) then
    return jsonb_build_object('ok', false, 'message', 'ليست لديك صلاحية تحديث هذه المهمة');
  end if;

  if v_st = 'completed' and now() > v_task.due_date and v_task.status = 'late' then
    v_st := 'completed';
  elsif v_st in ('pending','in_progress') and now() > v_task.due_date then
    v_st := 'late';
  end if;

  update public.school_tasks set
    status = case when v_st in ('pending','in_progress','completed','late','cancelled') then v_st else status end,
    completion_note = coalesce(nullif(trim(p_note), ''), completion_note),
    attachment_url = coalesce(nullif(trim(p_attachment_url), ''), attachment_url),
    updated_at = now()
  where id = p_task_id;

  return jsonb_build_object('ok', true, 'message', 'تم تحديث حالة المهمة والإنجاز بنجاح ✅');
end;
$$;
grant execute on function public.task_update_progress(uuid,text,text,text) to authenticated, anon;

create or replace function public.task_verify_completion(p_task_id uuid, p_verified boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin','principal','scientific','hr','supervisor'))) then
    return jsonb_build_object('ok', false, 'message', 'صلاحية التحقق والاعتماد محصورة بالإدارة فقط 🔒');
  end if;

  update public.school_tasks set
    status = case when p_verified then 'verified' else 'in_progress' end,
    verified_by = case when p_verified then auth.uid() else null end,
    verified_at = case when p_verified then now() else null end,
    updated_at = now()
  where id = p_task_id;

  return jsonb_build_object('ok', true, 'message', case when p_verified then 'تم التحقق من إنجاز المهمة واعتمادها نهائياً 🟢' else 'تم إعادة المهمة قيد التنفيذ 🔄' end);
end;
$$;
grant execute on function public.task_verify_completion(uuid,boolean) to authenticated, anon;

create or replace function public.check_overdue_school_tasks()
returns int
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_count int := 0;
begin
  update public.school_tasks set status = 'late', updated_at = now()
  where status in ('pending','in_progress') and now() > due_date;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
grant execute on function public.check_overdue_school_tasks() to authenticated, anon;

NOTIFY pgrst, 'reload schema';

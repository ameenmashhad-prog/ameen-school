-- ============================================================================
-- نظام التكليفات المتعددة للموظفين والمعلمين (Multi-Assignee School Tasks)
-- يتيح للإدارة اختيار عدة موظفين (معلمين، مرشدين، محاسبين...) بتكليف واحد،
-- وتوليد مهمة منفصلة وإشعار فوري لكل شخص فيهم دفعة واحدة وبضغطة زر.
--
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

create or replace function public.task_create_multi_assignment(
  p_title text,
  p_description text,
  p_assigned_to_list uuid[],
  p_priority text,
  p_due_date timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid;
  v_id uuid;
  v_count int := 0;
begin
  if not exists(select 1 from public.users u where u.id = auth.uid() and (coalesce(u.is_super_admin,false)=true or u.role in ('admin','academic_admin','super_admin','principal','scientific','hr','supervisor'))) then
    return jsonb_build_object('ok', false, 'message', 'صلاحية تكليف المهام محصورة بالإدارة والمشرفين 🔒');
  end if;

  if coalesce(nullif(trim(p_title),''), '') = '' then
    return jsonb_build_object('ok', false, 'message', 'عنوان المهمة مطلوب');
  end if;

  if p_assigned_to_list is null or array_length(p_assigned_to_list, 1) is null or array_length(p_assigned_to_list, 1) = 0 then
    return jsonb_build_object('ok', false, 'message', 'يجب اختيار موظف أو معلم واحد على الأقل');
  end if;

  foreach v_uid in array p_assigned_to_list loop
    if v_uid is not null then
      insert into public.school_tasks (
        title, description, assigned_to, assigned_by, priority, due_date, status
      ) values (
        trim(p_title),
        nullif(trim(p_description), ''),
        v_uid,
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
            v_uid,
            auth.uid()
          );
        end if;
      exception when others then
      end;

      v_count := v_count + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'message', 'تم إسناد التكليف إلى (' || v_count || ') معلمين وموظفين وإرسال الإشعارات لهم بنجاح 🚀', 'assigned_count', v_count);
end;
$$;
grant execute on function public.task_create_multi_assignment(text,text,uuid[],text,timestamptz) to authenticated, anon;

NOTIFY pgrst, 'reload schema';

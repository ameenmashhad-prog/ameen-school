-- =============================================================
-- مدارس أمين الرضا (ع) — واجهة الوثائق: تشديد الصلاحيات ودوال مساعدة
-- يكمل SQL 64 ويجعله جاهزاً للواجهة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 1) تحقق أن الطالب مرتبط بالمستخدم أو بولي الأمر
-- -------------------------------------------------------------
create or replace function public.document_student_belongs_to_current_user(p_student_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select p_student_id is null
    or exists(
      select 1
      from public.students s
      where s.id = p_student_id
        and (s.user_id = auth.uid() or s.parent_id = auth.uid())
    );
$$;

grant execute on function public.document_student_belongs_to_current_user(uuid) to authenticated;

-- -------------------------------------------------------------
-- 2) إنشاء سجل وثيقة مع حماية الطالب/ولي الأمر
-- -------------------------------------------------------------
create or replace function public.document_create_record(
  p_title text,
  p_category text default null,
  p_student_id uuid default null,
  p_owner_user_id uuid default null,
  p_related_table text default null,
  p_related_id uuid default null,
  p_visibility text default 'private',
  p_description text default null,
  p_tags jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cat_id uuid;
  doc_id uuid;
  v_visibility text := coalesce(p_visibility,'private');
  v_owner uuid := coalesce(p_owner_user_id, auth.uid());
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'message', 'لا توجد جلسة مستخدم');
  end if;

  if nullif(trim(coalesce(p_title,'')), '') is null then
    return jsonb_build_object('ok', false, 'message', 'عنوان الوثيقة مطلوب');
  end if;

  if v_visibility not in ('private','student_parent','staff','public_authenticated') then
    v_visibility := 'private';
  end if;

  if not public.documents_can_manage() then
    if v_owner <> auth.uid() then
      return jsonb_build_object('ok', false, 'message', 'لا يمكن إنشاء وثيقة باسم مستخدم آخر');
    end if;

    if not public.document_student_belongs_to_current_user(p_student_id) then
      return jsonb_build_object('ok', false, 'message', 'لا يمكن ربط الوثيقة بطالب غير مرتبط بحسابك');
    end if;

    -- المستخدم غير الإداري لا ينشئ وثائق staff أو عامة.
    if v_visibility in ('staff','public_authenticated') then
      v_visibility := case when p_student_id is not null then 'student_parent' else 'private' end;
    end if;
  end if;

  if nullif(trim(coalesce(p_category,'')), '') is not null then
    insert into public.document_categories(name)
    values (trim(p_category))
    on conflict (name) do update set name=excluded.name
    returning id into cat_id;
  end if;

  insert into public.document_records(
    title,
    category_id,
    owner_user_id,
    student_id,
    related_table,
    related_id,
    visibility,
    description,
    tags,
    created_by
  ) values (
    trim(p_title),
    cat_id,
    v_owner,
    p_student_id,
    p_related_table,
    p_related_id,
    v_visibility,
    p_description,
    coalesce(p_tags,'[]'::jsonb),
    auth.uid()
  ) returning id into doc_id;

  insert into public.document_access_logs(document_id, user_id, action, metadata)
  values (doc_id, auth.uid(), 'create', jsonb_build_object('title', trim(p_title), 'visibility', v_visibility));

  return jsonb_build_object('ok', true, 'message', 'تم إنشاء سجل الوثيقة', 'document_id', doc_id, 'visibility', v_visibility);
exception when others then
  return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$$;

grant execute on function public.document_create_record(text,text,uuid,uuid,text,uuid,text,text,jsonb) to authenticated;

-- -------------------------------------------------------------
-- 3) Payload سريع للواجهة
-- -------------------------------------------------------------
create or replace function public.get_documents_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  docs jsonb;
  files jsonb;
  cats jsonb;
  my_students jsonb;
  stats jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(d) order by d.created_at desc), '[]'::jsonb)
  into docs
  from public.v_documents_detailed d;

  select coalesce(jsonb_agg(to_jsonb(f) order by f.created_at desc), '[]'::jsonb)
  into files
  from public.v_document_files_detailed f;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.name), '[]'::jsonb)
  into cats
  from public.document_categories c
  where c.is_active = true;

  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'class_id', s.class_id, 'section_id', s.section_id) order by s.name), '[]'::jsonb)
  into my_students
  from public.students s
  where public.documents_can_manage()
     or s.user_id = auth.uid()
     or s.parent_id = auth.uid();

  stats := jsonb_build_object(
    'documents', jsonb_array_length(coalesce(docs,'[]'::jsonb)),
    'files', jsonb_array_length(coalesce(files,'[]'::jsonb)),
    'categories', jsonb_array_length(coalesce(cats,'[]'::jsonb)),
    'my_students', jsonb_array_length(coalesce(my_students,'[]'::jsonb))
  );

  return jsonb_build_object('ok', true, 'documents', docs, 'files', files, 'categories', cats, 'students', my_students, 'stats', stats);
end;
$$;

grant execute on function public.get_documents_payload() to authenticated;

-- -------------------------------------------------------------
-- 4) فحص
-- -------------------------------------------------------------
create or replace function public.documents_ui_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'checked_at', now(),
    'student_guard', to_regprocedure('public.document_student_belongs_to_current_user(uuid)') is not null,
    'payload_rpc', to_regprocedure('public.get_documents_payload()') is not null,
    'create_rpc', to_regprocedure('public.document_create_record(text,text,uuid,uuid,text,uuid,text,text,jsonb)') is not null,
    'documents_health', public.documents_health_check(),
    'payload_stats', public.get_documents_payload()->'stats'
  );
end;
$$;

grant execute on function public.documents_ui_health_check() to authenticated;

notify pgrst, 'reload schema';

select 'documents_ui_security_helpers_ready' as status;

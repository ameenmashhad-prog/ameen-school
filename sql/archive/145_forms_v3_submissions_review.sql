-- ============================================================================
-- Forms v3 — submissions review RPCs
-- ============================================================================

alter table public.forms_v3_submissions add column if not exists review_note text;
alter table public.forms_v3_submissions add column if not exists reviewed_by uuid;
alter table public.forms_v3_submissions add column if not exists updated_at timestamptz not null default now();

create or replace function public.forms_list_submissions_v3(
  p_form_slug text default null,
  p_visibility text default null,
  p_status text default null,
  p_limit int default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 100), 1), 500);
begin
  return jsonb_build_object(
    'ok', true,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'form_slug', s.form_slug,
        'visibility', s.visibility,
        'status', s.status,
        'locale', s.locale,
        'submission_ref', s.submission_ref,
        'created_at', s.created_at,
        'updated_at', s.updated_at,
        'applicant_name', coalesce(s.submission_values->>'student_name', s.submission_values->>'staff_name', s.submission_values->>'teacher_name'),
        'guardian_name', s.submission_values->>'guardian_name'
      ) order by s.created_at desc)
      from (
        select *
        from public.forms_v3_submissions
        where (p_form_slug is null or form_slug = trim(p_form_slug))
          and (p_visibility is null or visibility = trim(p_visibility))
          and (p_status is null or status = trim(p_status))
        order by created_at desc
        limit v_limit
      ) s
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.forms_list_submissions_v3(text,text,text,int) to authenticated, anon;

create or replace function public.forms_get_submission_v3(
  p_submission_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.forms_v3_submissions%rowtype;
begin
  select * into v_item from public.forms_v3_submissions where id = p_submission_id;
  if v_item.id is null then
    return jsonb_build_object('ok', false, 'error', 'submission_not_found');
  end if;

  return jsonb_build_object(
    'ok', true,
    'item', jsonb_build_object(
      'id', v_item.id,
      'form_slug', v_item.form_slug,
      'visibility', v_item.visibility,
      'status', v_item.status,
      'locale', v_item.locale,
      'submission_ref', v_item.submission_ref,
      'created_at', v_item.created_at,
      'updated_at', v_item.updated_at,
      'review_note', v_item.review_note,
      'uploaded_attachment', v_item.uploaded_attachment,
      'schema_snapshot', v_item.schema_snapshot,
      'submission_values', v_item.submission_values,
      'applicant_name', coalesce(v_item.submission_values->>'student_name', v_item.submission_values->>'staff_name', v_item.submission_values->>'teacher_name'),
      'guardian_name', v_item.submission_values->>'guardian_name'
    )
  );
end;
$$;

grant execute on function public.forms_get_submission_v3(uuid) to authenticated, anon;

create or replace function public.forms_update_submission_status_v3(
  p_submission_id uuid,
  p_status text,
  p_review_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text := lower(trim(coalesce(p_status, '')));
begin
  if v_status not in ('received','reviewed','issued','rejected','archived') then
    return jsonb_build_object('ok', false, 'error', 'invalid_status');
  end if;

  update public.forms_v3_submissions
    set status = v_status,
        review_note = nullif(trim(coalesce(p_review_note, '')), ''),
        reviewed_by = auth.uid(),
        updated_at = now()
  where id = p_submission_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'submission_not_found');
  end if;

  return jsonb_build_object(
    'ok', true,
    'submission_id', p_submission_id,
    'status', v_status,
    'updated_at', now()
  );
end;
$$;

grant execute on function public.forms_update_submission_status_v3(uuid,text,text) to authenticated, anon;

notify pgrst, 'reload schema';

-- ============================================================================
-- Forms v3 — submission list/detail name fallbacks
-- الهدف:
-- - تحسين أسماء مقدمي الطلبات في لوحة الطلبات المرسلة
-- - دعم النماذج الجديدة مثل:
--   * student-registration-packet-v3
--   * financial-permission-v3
-- ============================================================================

create or replace function public.forms_list_submissions_v3(
  p_form_slug text default null,
  p_visibility text default null,
  p_status text default null,
  p_created_from date default null,
  p_created_to date default null,
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
        'applicant_name', coalesce(
          s.submission_values->>'student_name',
          s.submission_values->>'student_full_name',
          s.submission_values->>'staff_name',
          s.submission_values->>'teacher_name',
          s.submission_values->>'requester_name',
          s.submission_values->>'requesting_unit'
        ),
        'guardian_name', coalesce(
          s.submission_values->>'guardian_name',
          s.submission_values->>'guardian_full_name',
          s.submission_values->>'father_full_name'
        )
      ) order by s.created_at desc)
      from (
        select *
        from public.forms_v3_submissions
        where (p_form_slug is null or form_slug = trim(p_form_slug))
          and (p_visibility is null or visibility = trim(p_visibility))
          and (p_status is null or status = trim(p_status))
          and (p_created_from is null or created_at::date >= p_created_from)
          and (p_created_to is null or created_at::date <= p_created_to)
        order by created_at desc
        limit v_limit
      ) s
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.forms_list_submissions_v3(text,text,text,date,date,int) to authenticated, anon;

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
      'applicant_name', coalesce(
        v_item.submission_values->>'student_name',
        v_item.submission_values->>'student_full_name',
        v_item.submission_values->>'staff_name',
        v_item.submission_values->>'teacher_name',
        v_item.submission_values->>'requester_name',
        v_item.submission_values->>'requesting_unit'
      ),
      'guardian_name', coalesce(
        v_item.submission_values->>'guardian_name',
        v_item.submission_values->>'guardian_full_name',
        v_item.submission_values->>'father_full_name'
      )
    )
  );
end;
$$;

grant execute on function public.forms_get_submission_v3(uuid) to authenticated, anon;

notify pgrst, 'reload schema';

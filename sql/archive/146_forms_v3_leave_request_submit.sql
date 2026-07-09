-- ============================================================================
-- Forms v3 — leave request submit RPC
-- ============================================================================

create or replace function public.forms_submit_leave_request_v3(
  p_form_slug text,
  p_locale text,
  p_visibility text,
  p_submission_ref text,
  p_schema jsonb,
  p_values jsonb,
  p_upload_ticket_id uuid default null,
  p_uploaded_attachment jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_slug text := trim(coalesce(p_form_slug, ''));
  v_locale text := lower(trim(coalesce(p_locale, 'ar')));
  v_visibility text := lower(trim(coalesce(p_visibility, 'administrative')));
  v_ref text := trim(coalesce(p_submission_ref, ''));
begin
  if v_slug = '' then
    return jsonb_build_object('ok', false, 'error', 'form_slug_required');
  end if;
  if v_ref = '' then
    return jsonb_build_object('ok', false, 'error', 'submission_ref_required');
  end if;
  if v_locale not in ('ar','fa','en') then
    v_locale := 'ar';
  end if;
  if v_visibility not in ('public','administrative','finance_admin') then
    v_visibility := 'administrative';
  end if;

  insert into public.forms_v3_submissions(
    form_slug, locale, visibility, submission_ref, schema_snapshot, submission_values,
    upload_ticket_id, uploaded_attachment, status, created_by
  ) values (
    v_slug,
    v_locale,
    v_visibility,
    v_ref,
    coalesce(p_schema, '{}'::jsonb),
    coalesce(p_values, '{}'::jsonb),
    p_upload_ticket_id,
    p_uploaded_attachment,
    'received',
    auth.uid()
  ) returning id into v_id;

  if p_upload_ticket_id is not null then
    update public.forms_v3_upload_tickets
      set submission_ref = v_ref
    where id = p_upload_ticket_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'submission_id', v_id,
    'submission_ref', v_ref,
    'status', 'received'
  );
end;
$$;

grant execute on function public.forms_submit_leave_request_v3(text,text,text,text,jsonb,jsonb,uuid,jsonb) to authenticated, anon;

notify pgrst, 'reload schema';

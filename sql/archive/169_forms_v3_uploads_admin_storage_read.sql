-- ============================================================================
-- Forms v3 uploads — allow administrative read/signed access
-- الهدف:
-- تمكين الإدارة والمحاسبين والمشرفين من فتح مرفقات forms-v3-uploads
-- عبر createSignedUrl / read object بعد تسجيل الدخول.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('forms-v3-uploads', 'forms-v3-uploads', false)
on conflict (id) do nothing;

do $$ begin
  if not exists(
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'forms_v3_uploads_admin_read'
  ) then
    create policy forms_v3_uploads_admin_read
      on storage.objects
      for select
      to authenticated
      using (
        bucket_id = 'forms-v3-uploads'
        and exists (
          select 1
          from public.users u
          where u.id = auth.uid()
            and (
              coalesce(u.is_super_admin,false) = true
              or u.role in ('admin','academic','academic_admin','finance','finance_admin')
            )
        )
      );
  end if;
end $$;

notify pgrst, 'reload schema';

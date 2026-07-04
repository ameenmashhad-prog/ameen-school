-- ============================================================================
-- حل مشكلة التايم أوت عند رفع الصور (Photo Upload Timeout Fix & Storage Policies)
-- يجعل حاويات التخزين registration-photos و student-photos عامة (public = true)،
-- ويضيف سياسات القراءة والتحديث المفتوحة للمسجلين حتى لا يرفض Supabase الاستعلام أو يعلق.
--
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

-- 1) التأكد من وجود الحاويات وجعلها عامة (public) لتسهيل العرض والرفع بدون تعليق
insert into storage.buckets (id, name, public)
values ('registration-photos', 'registration-photos', true),
       ('student-photos', 'student-photos', true)
on conflict (id) do update set public = true;

-- 2) سياسات الرفع والقراءة والتحديث المفتوحة على حاوية registration-photos
do $$ begin
  -- سياسة الإدراج (الرفع)
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='registration_photos_insert_all') then
    create policy registration_photos_insert_all on storage.objects
      for insert to anon, authenticated
      with check (bucket_id = 'registration-photos');
  end if;

  -- سياسة القراءة (ضرورية لكي يعيد Supabase بيانات الملف المرفوع بدون تايم أوت أو RLS error)
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='registration_photos_select_all') then
    create policy registration_photos_select_all on storage.objects
      for select to anon, authenticated
      using (bucket_id = 'registration-photos');
  end if;

  -- سياسة التحديث (في حال إعادة رفع صورة بنفس الاسم)
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='registration_photos_update_all') then
    create policy registration_photos_update_all on storage.objects
      for update to anon, authenticated
      using (bucket_id = 'registration-photos')
      with check (bucket_id = 'registration-photos');
  end if;

  -- سياسة الحذف (لإلغاء صورة سابقة عند تغييرها)
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='registration_photos_delete_all') then
    create policy registration_photos_delete_all on storage.objects
      for delete to anon, authenticated
      using (bucket_id = 'registration-photos');
  end if;
end $$;

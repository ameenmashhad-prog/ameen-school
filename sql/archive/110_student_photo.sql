-- ============================================================================
-- R4 — تفعيل صورة الطالب عبر النظام (Student photo display)
-- يضيف عمود صورة على جدول users + حاوية تخزين وسياسات RLS، ويُفعّل عرض الصورة
-- في الملف الشخصي وواجهة المعلم/ولي الأمر (المكوّن assets/avatar.js يقرأ
-- العمود avatar_url ويحلّ المسارات عبر /api proxy).
-- شغّل هذا الملف في Supabase → SQL Editor. آمن للتكرار (idempotent).
-- ============================================================================

-- 1) عمود الصورة على users (وولي الأمر/المعلم/الطالب كلهم صفوف في users).
do $$ begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='users' and column_name='avatar_url'
  ) then
    alter table public.users add column avatar_url text;
    comment on column public.users.avatar_url
      is 'مسار الصورة داخل حاوية student-photos، أو رابط كامل، أو data: URI';
  end if;
end $$;

-- 2) فهرس خفيف للبحث/التحقق.
create index if not exists idx_users_avatar on public.users (id) where avatar_url is not null;

-- 3) حاوية التخزين (خاصة — القراءة للمصادَقين حسب الصلاحية).
insert into storage.buckets (id, name, public)
values ('student-photos', 'student-photos', false)
on conflict (id) do nothing;

-- 4) سياسات RLS على الكائنات.
do $$ begin
  -- رفع/تعديل صورة المستخدم الخاصة به فقط.
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='student_photos_owner_write') then
    create policy student_photos_owner_write on storage.objects
      for insert to authenticated
      with check ( bucket_id='student-photos' and (storage.foldername(name))[1] = auth.uid()::text );
  end if;
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='student_photos_owner_update') then
    create policy student_photos_owner_update on storage.objects
      for update to authenticated
      using ( bucket_id='student-photos' and (storage.foldername(name))[1] = auth.uid()::text )
      with check ( bucket_id='student-photos' and (storage.foldername(name))[1] = auth.uid()::text );
  end if;
  -- قراءة: المعلمون/الإدارة/أولياء الأمور المصرّح لهم.
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='student_photos_role_read') then
    create policy student_photos_role_read on storage.objects
      for select to authenticated
      using ( bucket_id='student-photos' and exists (
        select 1 from public.users u where u.id = auth.uid()
          and ( u.role in ('admin','academic','academic_admin','teacher','counselor')
                or coalesce(u.is_super_admin,false)=true )
      ));
  end if;
end $$;

-- 5) دالة مساعدة: رفع/تحديث صورة المستخدم (تُستدعى من الواجهة بعد رفع الملف للحاوية).
create or replace function public.set_user_avatar(p_user_id uuid, p_path text)
returns public.users language plpgsql security definer set search_path = public as $$
declare v_role text;
begin
  select role into v_role from public.users where id = p_user_id;
  if v_role is null then raise exception 'المستخدم غير موجود'; end if;
  update public.users set avatar_url = nullif(trim(p_path),'') where id = p_user_id;
  return (select u from public.users u where u.id = p_user_id);
end $$;

grant execute on function public.set_user_avatar(uuid, text) to authenticated;

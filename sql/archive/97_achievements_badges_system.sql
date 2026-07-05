-- =============================================================
-- مدارس أمين الرضا (ع) — نظام الإنجازات والشارات التحفيزية
-- للطلاب والمعلمين: شارات، نقاط، لوحة صدارة، منح يدوي ومنح تلقائي.
-- آمن وإضافي ويمكن تشغيله أكثر من مرة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) دوال صلاحيات أساسية آمنة
-- -------------------------------------------------------------
create or replace function public.current_user_is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1
    from public.users u
    where u.id = auth.uid()
      and (u.role = 'admin' or coalesce(u.is_super_admin,false)=true)
  );
$$;

grant execute on function public.current_user_is_admin() to authenticated;

create or replace function public.current_user_is_super_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1
    from public.users u
    where u.id = auth.uid()
      and coalesce(u.is_super_admin,false)=true
  );
$$;

grant execute on function public.current_user_is_super_admin() to authenticated;

-- -------------------------------------------------------------
-- 1) الجداول
-- -------------------------------------------------------------
create table if not exists public.achievement_badges (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title_ar text not null,
  title_fa text,
  title_en text,
  description_ar text,
  description_fa text,
  description_en text,
  target_role text not null default 'student' check (target_role in ('student','teacher','both','all')),
  category text not null default 'general',
  icon_key text not null default 'trophy',
  color text not null default 'gold',
  level text not null default 'bronze' check (level in ('bronze','silver','gold','platinum','diamond')),
  points int not null default 10 check (points >= 0),
  trigger_type text not null default 'manual' check (trigger_type in ('manual','auto','hybrid')),
  trigger_metric text,
  threshold numeric,
  sort_order int not null default 100,
  is_active boolean not null default true,
  created_by uuid null references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.achievement_badges add column if not exists title_fa text;
alter table public.achievement_badges add column if not exists title_en text;
alter table public.achievement_badges add column if not exists description_fa text;
alter table public.achievement_badges add column if not exists description_en text;
alter table public.achievement_badges add column if not exists target_role text not null default 'student';
alter table public.achievement_badges add column if not exists category text not null default 'general';
alter table public.achievement_badges add column if not exists icon_key text not null default 'trophy';
alter table public.achievement_badges add column if not exists color text not null default 'gold';
alter table public.achievement_badges add column if not exists level text not null default 'bronze';
alter table public.achievement_badges add column if not exists points int not null default 10;
alter table public.achievement_badges add column if not exists trigger_type text not null default 'manual';
alter table public.achievement_badges add column if not exists trigger_metric text;
alter table public.achievement_badges add column if not exists threshold numeric;
alter table public.achievement_badges add column if not exists sort_order int not null default 100;
alter table public.achievement_badges add column if not exists is_active boolean not null default true;
alter table public.achievement_badges add column if not exists created_by uuid null references public.users(id) on delete set null;
alter table public.achievement_badges add column if not exists updated_at timestamptz not null default now();

create table if not exists public.achievement_awards (
  id uuid primary key default gen_random_uuid(),
  badge_id uuid not null references public.achievement_badges(id) on delete cascade,
  recipient_user_id uuid null references public.users(id) on delete cascade,
  recipient_student_id uuid null references public.students(id) on delete cascade,
  recipient_role text not null check (recipient_role in ('student','teacher')),
  awarded_by uuid null references public.users(id) on delete set null,
  awarded_at timestamptz not null default now(),
  reason text,
  points_awarded int not null default 0 check (points_awarded >= 0),
  source_table text,
  source_id uuid,
  status text not null default 'active' check (status in ('active','revoked')),
  revoked_by uuid null references public.users(id) on delete set null,
  revoked_at timestamptz,
  revoke_reason text,
  created_at timestamptz not null default now(),
  constraint achievement_awards_recipient_required check (recipient_user_id is not null or recipient_student_id is not null)
);

alter table public.achievement_awards add column if not exists recipient_user_id uuid null references public.users(id) on delete cascade;
alter table public.achievement_awards add column if not exists recipient_student_id uuid null references public.students(id) on delete cascade;
alter table public.achievement_awards add column if not exists recipient_role text not null default 'student';
alter table public.achievement_awards add column if not exists awarded_by uuid null references public.users(id) on delete set null;
alter table public.achievement_awards add column if not exists awarded_at timestamptz not null default now();
alter table public.achievement_awards add column if not exists reason text;
alter table public.achievement_awards add column if not exists points_awarded int not null default 0;
alter table public.achievement_awards add column if not exists source_table text;
alter table public.achievement_awards add column if not exists source_id uuid;
alter table public.achievement_awards add column if not exists status text not null default 'active';
alter table public.achievement_awards add column if not exists revoked_by uuid null references public.users(id) on delete set null;
alter table public.achievement_awards add column if not exists revoked_at timestamptz;
alter table public.achievement_awards add column if not exists revoke_reason text;

create index if not exists idx_achievement_badges_active on public.achievement_badges(is_active, target_role, category, sort_order);
create index if not exists idx_achievement_awards_student on public.achievement_awards(recipient_student_id, status, awarded_at desc);
create index if not exists idx_achievement_awards_user on public.achievement_awards(recipient_user_id, status, awarded_at desc);
create index if not exists idx_achievement_awards_badge on public.achievement_awards(badge_id, status);

create unique index if not exists uq_achievement_awards_badge_student_active
  on public.achievement_awards(badge_id, recipient_student_id)
  where recipient_student_id is not null and status = 'active';

create unique index if not exists uq_achievement_awards_badge_user_active
  on public.achievement_awards(badge_id, recipient_user_id)
  where recipient_user_id is not null and status = 'active';

-- -------------------------------------------------------------
-- 2) صلاحيات RLS
-- -------------------------------------------------------------
alter table public.achievement_badges enable row level security;
alter table public.achievement_awards enable row level security;

drop policy if exists achievement_badges_select_all on public.achievement_badges;
drop policy if exists achievement_badges_manage_admin on public.achievement_badges;
drop policy if exists achievement_awards_select_scoped on public.achievement_awards;
drop policy if exists achievement_awards_insert_manage on public.achievement_awards;
drop policy if exists achievement_awards_update_manage on public.achievement_awards;
drop policy if exists achievement_awards_delete_super on public.achievement_awards;

create policy achievement_badges_select_all
on public.achievement_badges
for select
to authenticated
using (is_active = true or public.current_user_is_admin());

create policy achievement_badges_manage_admin
on public.achievement_badges
for all
to authenticated
using (public.current_user_is_admin())
with check (public.current_user_is_admin());

create policy achievement_awards_select_scoped
on public.achievement_awards
for select
to authenticated
using (
  public.current_user_is_admin()
  or awarded_by = auth.uid()
  or recipient_user_id = auth.uid()
  or exists(
    select 1 from public.students s
    where s.id = recipient_student_id
      and (s.user_id = auth.uid() or s.parent_id = auth.uid())
  )
);

create policy achievement_awards_insert_manage
on public.achievement_awards
for insert
to authenticated
with check (
  public.current_user_is_admin()
  or exists(select 1 from public.users u where u.id = auth.uid() and u.role in ('teacher','staff','academic','academic_admin','scientific','supervisor','discipline','counselor','psychologist'))
);

create policy achievement_awards_update_manage
on public.achievement_awards
for update
to authenticated
using (
  public.current_user_is_admin()
  or awarded_by = auth.uid()
  or exists(select 1 from public.users u where u.id = auth.uid() and u.role in ('staff','academic','academic_admin','scientific','supervisor','discipline','counselor','psychologist'))
)
with check (
  public.current_user_is_admin()
  or awarded_by = auth.uid()
  or exists(select 1 from public.users u where u.id = auth.uid() and u.role in ('staff','academic','academic_admin','scientific','supervisor','discipline','counselor','psychologist'))
);

create policy achievement_awards_delete_super
on public.achievement_awards
for delete
to authenticated
using (public.current_user_is_super_admin());

revoke insert, update, delete on public.achievement_badges from authenticated, anon;
revoke insert, update, delete on public.achievement_awards from authenticated, anon;
grant select on public.achievement_badges to authenticated;
grant select on public.achievement_awards to authenticated;

-- -------------------------------------------------------------
-- 3) زرع الشارات الافتراضية
-- -------------------------------------------------------------
create or replace function public.seed_achievement_badges()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_count int := 0;
begin
  insert into public.achievement_badges
    (code,title_ar,title_fa,title_en,description_ar,description_fa,description_en,target_role,category,icon_key,color,level,points,trigger_type,trigger_metric,threshold,sort_order,is_active,created_by)
  values
    ('attendance_star','نجم الحضور','ستاره حضور','Attendance Star','للطالب المنتظم في الحضور.','برای دانش‌آموز منظم در حضور.','For consistent student attendance.','student','attendance','star','emerald','bronze',15,'auto','attendance_present_count',5,10,true,auth.uid()),
    ('homework_hero','بطل الواجبات','قهرمان تکالیف','Homework Hero','تسليم واجبات متتالية بانتظام.','تحویل منظم تکالیف.','Consistent homework submission.','student','homework','medal','orange','silver',25,'auto','homework_submissions_count',3,20,true,auth.uid()),
    ('exam_excellence','تميز الاختبارات','برتری در آزمون','Exam Excellence','متوسط اختبارات مرتفع.','میانگین آزمون بالا.','High exam average.','student','academic','trophy','indigo','gold',40,'auto','exam_average',90,30,true,auth.uid()),
    ('improvement_hero','بطل التحسن','قهرمان پیشرفت','Improvement Hero','تحسن واضح في الأداء أو السلوك.','پیشرفت روشن در عملکرد یا رفتار.','Clear improvement in performance or behavior.','student','growth','sparkle','cyan','silver',25,'manual',null,null,40,true,auth.uid()),
    ('discipline_gem','جوهرة الانضباط','گوهر انضباط','Discipline Gem','التزام وسلوك إيجابي.','تعهد و رفتار مثبت.','Positive discipline and conduct.','student','behavior','medal','violet','silver',25,'manual',null,null,50,true,auth.uid()),
    ('library_reader','قارئ المكتبة','کتابخوان کتابخانه','Library Reader','نشاط مميز في القراءة والمكتبة.','فعالیت برجسته در کتابخوانی.','Outstanding reading/library activity.','student','library','book','orange','bronze',15,'manual',null,null,60,true,auth.uid()),
    ('activity_champion','بطل الأنشطة','قهرمان فعالیت‌ها','Activity Champion','مشاركة مميزة في الأنشطة المدرسية.','مشارکت برجسته در فعالیت‌ها.','Outstanding school activities participation.','student','activities','trophy','pink','silver',25,'manual',null,null,70,true,auth.uid()),
    ('kindness_badge','شارة اللطف','نشان مهربانی','Kindness Badge','مبادرة لطيفة أو تعاون ملحوظ.','ابتکار مهربانانه یا همکاری چشمگیر.','Kindness, support or teamwork.','both','values','sparkle','rose','bronze',20,'manual',null,null,80,true,auth.uid()),
    ('daily_achiever','منجز اليوم','دستاورد روز','Daily Achiever','إنجاز مهام وأهداف متتالية.','انجام پیوسته وظایف و اهداف.','Completing repeated tasks/goals.','both','calendar','check','cyan','bronze',15,'auto','completed_items_count',3,90,true,auth.uid()),
    ('science_lab','باحث المختبر','پژوهشگر آزمایشگاه','Lab Researcher','تميز في التجارب والمختبرات.','برتری در آزمایشگاه و تجربه‌ها.','Excellence in labs and experiments.','student','labs','lab','teal','silver',25,'manual',null,null,100,true,auth.uid()),

    ('inspiring_teacher','المعلم الملهم','معلم الهام‌بخش','Inspiring Teacher','تأثير إيجابي وتحفيز للطلاب.','اثر مثبت و انگیزش دانش‌آموزان.','Positive impact and student motivation.','teacher','teaching','sparkle','emerald','gold',45,'manual',null,null,210,true,auth.uid()),
    ('attendance_master','مايسترو الحضور','استاد حضور','Attendance Master','متابعة حضور الطلاب بانتظام.','پیگیری منظم حضور دانش‌آموزان.','Consistent attendance follow-up.','teacher','attendance','check','emerald','silver',30,'auto','attendance_records_by_teacher',5,220,true,auth.uid()),
    ('homework_mentor','مرشد الواجبات','راهنمای تکالیف','Homework Mentor','إنشاء ومتابعة واجبات فعالة.','ایجاد و پیگیری تکالیف مؤثر.','Creating and following effective homework.','teacher','homework','book','orange','silver',30,'auto','homeworks_created',3,230,true,auth.uid()),
    ('exam_creator','صانع الاختبارات','سازنده آزمون','Exam Creator','بناء اختبارات إلكترونية منظمة.','ساخت آزمون‌های آنلاین منظم.','Building structured online exams.','teacher','exams','exam','cyan','silver',30,'auto','online_exams_created',2,240,true,auth.uid()),
    ('digital_teacher','المعلم الرقمي','معلم دیجیتال','Digital Teacher','استخدام متميز للأدوات الرقمية.','استفاده برجسته از ابزار دیجیتال.','Excellent use of digital tools.','teacher','digital','grid','indigo','silver',30,'manual',null,null,250,true,auth.uid()),
    ('student_supporter','داعم الطلاب','حامی دانش‌آموزان','Student Supporter','متابعة إنسانية ودعم تربوي.','پیگیری انسانی و حمایت آموزشی.','Care, follow-up and student support.','teacher','support','people','rose','gold',45,'manual',null,null,260,true,auth.uid()),
    ('class_builder','باني الصف','سازنده کلاس','Class Builder','تنظيم وتطوير بيئة صفية محفزة.','ساخت محیط کلاسی انگیزشی.','Building a motivating classroom environment.','teacher','classroom','school','violet','gold',45,'manual',null,null,270,true,auth.uid()),
    ('innovation_teacher','معلّم الابتكار','معلم نوآوری','Innovation Teacher','مبادرات تعليمية إبداعية.','ابتکارهای آموزشی خلاقانه.','Creative learning initiatives.','teacher','innovation','sparkle','gold','diamond',70,'manual',null,null,280,true,auth.uid())
  on conflict (code) do update set
    title_ar = excluded.title_ar,
    title_fa = excluded.title_fa,
    title_en = excluded.title_en,
    description_ar = excluded.description_ar,
    description_fa = excluded.description_fa,
    description_en = excluded.description_en,
    target_role = excluded.target_role,
    category = excluded.category,
    icon_key = excluded.icon_key,
    color = excluded.color,
    level = excluded.level,
    points = excluded.points,
    trigger_type = excluded.trigger_type,
    trigger_metric = excluded.trigger_metric,
    threshold = excluded.threshold,
    sort_order = excluded.sort_order,
    is_active = true,
    updated_at = now();

  get diagnostics inserted_count = row_count;
  return jsonb_build_object('ok',true,'badges_upserted',inserted_count,'total_badges',(select count(*) from public.achievement_badges));
end;
$$;

grant execute on function public.seed_achievement_badges() to authenticated;
select public.seed_achievement_badges();

-- -------------------------------------------------------------
-- 4) دوال مساعدة
-- -------------------------------------------------------------
create or replace function public.achievement_can_manage()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (
        coalesce(u.is_super_admin,false)=true
        or u.role in ('admin','teacher','staff','academic','academic_admin','scientific','supervisor','discipline','counselor','psychologist')
      )
  );
$$;

grant execute on function public.achievement_can_manage() to authenticated;

create or replace function public.achievement_can_award_teacher(p_teacher_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from public.users u
    where u.id = auth.uid()
      and (
        coalesce(u.is_super_admin,false)=true
        or u.role in ('admin','staff','academic','academic_admin','scientific','supervisor')
      )
  )
  and exists(select 1 from public.users t where t.id = p_teacher_id and t.role = 'teacher');
$$;

grant execute on function public.achievement_can_award_teacher(uuid) to authenticated;

create or replace function public.achievement_can_award_student(p_student_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  u record;
  ok boolean := false;
begin
  select id, role, is_super_admin into u from public.users where id = auth.uid();
  if u.id is null then return false; end if;

  if coalesce(u.is_super_admin,false) or u.role in ('admin','staff','academic','academic_admin','scientific','supervisor','discipline','counselor','psychologist') then
    return exists(select 1 from public.students s where s.id = p_student_id);
  end if;

  if u.role = 'teacher' then
    if to_regclass('public.v_teacher_students') is not null then
      execute 'select exists(select 1 from public.v_teacher_students where student_id = $1 and teacher_id = $2)'
      into ok using p_student_id, auth.uid();
      return coalesce(ok,false);
    end if;
  end if;

  return false;
end;
$$;

grant execute on function public.achievement_can_award_student(uuid) to authenticated;

create or replace function public._achievement_student_name(p_student_id uuid)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(nullif(trim(concat_ws(' ', s.name, s.last_name)),''), s.name, 'طالب')
  from public.students s
  where s.id = p_student_id;
$$;

grant execute on function public._achievement_student_name(uuid) to authenticated;

-- View تفصيلي للعرض والتقارير
create or replace view public.v_achievement_awards_detailed
with (security_invoker=true) as
select
  a.id,
  a.badge_id,
  b.code as badge_code,
  b.title_ar as badge_title_ar,
  b.title_fa as badge_title_fa,
  b.title_en as badge_title_en,
  b.description_ar as badge_description_ar,
  b.target_role as badge_target_role,
  b.category,
  b.icon_key,
  b.color,
  b.level,
  a.recipient_role,
  a.recipient_user_id,
  a.recipient_student_id,
  case
    when a.recipient_student_id is not null then public._achievement_student_name(a.recipient_student_id)
    else coalesce(u.name,u.email,'معلم')
  end as recipient_name,
  c.name as class_name,
  a.awarded_by,
  coalesce(byu.name, byu.email) as awarded_by_name,
  a.awarded_at,
  a.reason,
  a.points_awarded,
  a.source_table,
  a.source_id,
  a.status,
  a.revoked_at,
  a.revoke_reason
from public.achievement_awards a
join public.achievement_badges b on b.id = a.badge_id
left join public.students s on s.id = a.recipient_student_id
left join public.classes c on c.id = s.class_id
left join public.users u on u.id = a.recipient_user_id
left join public.users byu on byu.id = a.awarded_by;

grant select on public.v_achievement_awards_detailed to authenticated;

-- -------------------------------------------------------------
-- 5) منح/سحب الشارات
-- -------------------------------------------------------------
create or replace function public.award_achievement_badge(
  p_badge_code text,
  p_recipient_type text,
  p_recipient_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b record;
  s record;
  t record;
  new_id uuid;
  existing_id uuid;
  rtype text := lower(coalesce(p_recipient_type,''));
  recipient_user uuid := null;
  recipient_student uuid := null;
  recipient_role text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok',false,'message','يجب تسجيل الدخول');
  end if;

  select * into b from public.achievement_badges where code = p_badge_code and is_active = true;
  if b.id is null then
    return jsonb_build_object('ok',false,'message','الشارة غير موجودة أو غير مفعلة');
  end if;

  if rtype = 'student' then
    if b.target_role not in ('student','both','all') then
      return jsonb_build_object('ok',false,'message','هذه الشارة ليست مخصصة للطلاب');
    end if;
    if not public.achievement_can_award_student(p_recipient_id) then
      return jsonb_build_object('ok',false,'message','لا تملك صلاحية منح شارة لهذا الطالب');
    end if;
    select * into s from public.students where id = p_recipient_id;
    if s.id is null then
      return jsonb_build_object('ok',false,'message','الطالب غير موجود');
    end if;
    recipient_student := s.id;
    recipient_user := s.user_id;
    recipient_role := 'student';

    select id into existing_id
    from public.achievement_awards
    where badge_id = b.id and recipient_student_id = recipient_student and status = 'active'
    limit 1;
  elsif rtype = 'teacher' then
    if b.target_role not in ('teacher','both','all') then
      return jsonb_build_object('ok',false,'message','هذه الشارة ليست مخصصة للمعلمين');
    end if;
    if not public.achievement_can_award_teacher(p_recipient_id) then
      return jsonb_build_object('ok',false,'message','لا تملك صلاحية منح شارة لهذا المعلم');
    end if;
    select * into t from public.users where id = p_recipient_id and role = 'teacher';
    if t.id is null then
      return jsonb_build_object('ok',false,'message','المعلم غير موجود');
    end if;
    recipient_user := t.id;
    recipient_role := 'teacher';

    select id into existing_id
    from public.achievement_awards
    where badge_id = b.id and recipient_user_id = recipient_user and status = 'active'
    limit 1;
  else
    return jsonb_build_object('ok',false,'message','نوع المستلم غير صحيح');
  end if;

  if existing_id is not null then
    return jsonb_build_object('ok',true,'already_awarded',true,'award_id',existing_id,'message','هذه الشارة ممنوحة مسبقاً');
  end if;

  insert into public.achievement_awards(
    badge_id, recipient_user_id, recipient_student_id, recipient_role,
    awarded_by, reason, points_awarded, source_table, source_id
  ) values (
    b.id, recipient_user, recipient_student, recipient_role,
    auth.uid(), nullif(trim(coalesce(p_reason,'')),''), b.points, 'manual', null
  ) returning id into new_id;

  if recipient_user is not null and to_regclass('public.school_notifications') is not null then
    insert into public.school_notifications(recipient_user_id, recipient_role, title, body, notification_type, entity_table, entity_id, created_by)
    values(recipient_user, recipient_role, 'شارة إنجاز جديدة', 'تم منحك شارة: ' || b.title_ar, 'achievement', 'achievement_awards', new_id, auth.uid());
  end if;

  return jsonb_build_object('ok',true,'award_id',new_id,'message','تم منح الشارة بنجاح');
exception when unique_violation then
  return jsonb_build_object('ok',true,'already_awarded',true,'message','هذه الشارة ممنوحة مسبقاً');
when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.award_achievement_badge(text,text,uuid,text) to authenticated;

create or replace function public.revoke_achievement_award(p_award_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
begin
  select * into a from public.achievement_awards where id = p_award_id and status = 'active';
  if a.id is null then
    return jsonb_build_object('ok',false,'message','الشارة غير موجودة أو مسحوبة مسبقاً');
  end if;

  if not (
    public.current_user_is_admin()
    or a.awarded_by = auth.uid()
    or (a.recipient_student_id is not null and public.achievement_can_award_student(a.recipient_student_id))
    or (a.recipient_user_id is not null and public.achievement_can_award_teacher(a.recipient_user_id))
  ) then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية سحب هذه الشارة');
  end if;

  update public.achievement_awards
  set status = 'revoked', revoked_by = auth.uid(), revoked_at = now(), revoke_reason = nullif(trim(coalesce(p_reason,'')),'')
  where id = p_award_id;

  return jsonb_build_object('ok',true,'message','تم سحب الشارة');
end;
$$;

grant execute on function public.revoke_achievement_award(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 6) منح تلقائي من البيانات المتاحة
-- -------------------------------------------------------------
create or replace function public._achievement_award_system(
  p_badge_code text,
  p_student_id uuid default null,
  p_user_id uuid default null,
  p_reason text default null,
  p_source_table text default null,
  p_source_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  b record;
  recipient_user uuid := p_user_id;
  recipient_student uuid := p_student_id;
  recipient_role text;
  existing_id uuid;
begin
  select * into b from public.achievement_badges where code = p_badge_code and is_active = true;
  if b.id is null then return false; end if;

  if recipient_student is not null then
    select s.user_id into recipient_user from public.students s where s.id = recipient_student;
    recipient_role := 'student';
    select id into existing_id from public.achievement_awards where badge_id = b.id and recipient_student_id = recipient_student and status='active' limit 1;
  elsif p_user_id is not null then
    select u.role into recipient_role from public.users u where u.id = p_user_id;

    if recipient_role = 'teacher' then
      select id into existing_id from public.achievement_awards where badge_id = b.id and recipient_user_id = p_user_id and status='active' limit 1;
    else
      select s.id into recipient_student from public.students s where s.user_id = p_user_id limit 1;
      if recipient_student is null then return false; end if;
      recipient_role := 'student';
      select id into existing_id from public.achievement_awards where badge_id = b.id and recipient_student_id = recipient_student and status='active' limit 1;
    end if;
  else
    return false;
  end if;

  if existing_id is not null then return false; end if;
  if recipient_role = 'student' and b.target_role not in ('student','both','all') then return false; end if;
  if recipient_role = 'teacher' and b.target_role not in ('teacher','both','all') then return false; end if;

  insert into public.achievement_awards(badge_id, recipient_user_id, recipient_student_id, recipient_role, awarded_by, reason, points_awarded, source_table, source_id)
  values(b.id, recipient_user, recipient_student, recipient_role, auth.uid(), p_reason, b.points, p_source_table, p_source_id);
  return true;
exception when unique_violation then
  return false;
when others then
  return false;
end;
$$;

revoke all on function public._achievement_award_system(text,uuid,uuid,text,text,uuid) from public;

create or replace function public.achievement_auto_award_now(p_dry_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $auto$
declare
  r record;
  candidate_count int := 0;
  inserted_count int := 0;
begin
  if not public.achievement_can_manage() then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية تشغيل المنح التلقائي');
  end if;

  -- الطلاب: تسليم الواجبات
  if to_regclass('public.homework_submissions') is not null then
    for r in execute $$select student_id, count(*)::int cnt from public.homework_submissions where status in ('submitted','late','graded') group by student_id having count(*) >= 3$$ loop
      candidate_count := candidate_count + 1;
      if not p_dry_run and public._achievement_award_system('homework_hero', r.student_id, null, 'منح تلقائي: تسليم 3 واجبات أو أكثر', 'homework_submissions', null) then
        inserted_count := inserted_count + 1;
      end if;
    end loop;
  end if;

  -- الطلاب: متوسط الاختبارات
  if to_regclass('public.exam_scores') is not null then
    for r in execute $$select student_id, round(avg(score)::numeric,2) avg_score, count(*)::int cnt from public.exam_scores where score is not null group by student_id having count(*) >= 2 and avg(score) >= 90$$ loop
      candidate_count := candidate_count + 1;
      if not p_dry_run and public._achievement_award_system('exam_excellence', r.student_id, null, 'منح تلقائي: متوسط اختبارات 90% أو أكثر', 'exam_scores', null) then
        inserted_count := inserted_count + 1;
      end if;
    end loop;
  end if;

  -- الطلاب: حضور مسجل كحاضر
  if to_regclass('public.attendance') is not null then
    for r in execute $$select student_id, count(*)::int cnt from public.attendance where status in ('present','حاضر') group by student_id having count(*) >= 5$$ loop
      candidate_count := candidate_count + 1;
      if not p_dry_run and public._achievement_award_system('attendance_star', r.student_id, null, 'منح تلقائي: 5 سجلات حضور', 'attendance', null) then
        inserted_count := inserted_count + 1;
      end if;
    end loop;
  end if;

  -- الجميع: إنجازات الأجندة
  if to_regclass('public.completed_items') is not null then
    for r in execute $$select user_id, count(*)::int cnt from public.completed_items where status='completed' and user_id is not null group by user_id having count(*) >= 3$$ loop
      candidate_count := candidate_count + 1;
      if not p_dry_run and public._achievement_award_system('daily_achiever', null, r.user_id, 'منح تلقائي: 3 إنجازات في الأجندة', 'completed_items', null) then
        inserted_count := inserted_count + 1;
      end if;
    end loop;
  end if;

  -- المعلمون: إنشاء الواجبات
  if to_regclass('public.homeworks') is not null then
    for r in execute $$select teacher_id as user_id, count(*)::int cnt from public.homeworks where teacher_id is not null group by teacher_id having count(*) >= 3$$ loop
      candidate_count := candidate_count + 1;
      if not p_dry_run and public._achievement_award_system('homework_mentor', null, r.user_id, 'منح تلقائي: إنشاء 3 واجبات أو أكثر', 'homeworks', null) then
        inserted_count := inserted_count + 1;
      end if;
    end loop;
  end if;

  -- المعلمون: الاختبارات الإلكترونية
  if to_regclass('public.online_exams') is not null then
    for r in execute $$select teacher_id as user_id, count(*)::int cnt from public.online_exams where teacher_id is not null group by teacher_id having count(*) >= 2$$ loop
      candidate_count := candidate_count + 1;
      if not p_dry_run and public._achievement_award_system('exam_creator', null, r.user_id, 'منح تلقائي: إنشاء اختبارين إلكترونيين أو أكثر', 'online_exams', null) then
        inserted_count := inserted_count + 1;
      end if;
    end loop;
  end if;

  -- المعلمون: تسجيل الحضور
  if to_regclass('public.attendance') is not null then
    for r in execute $$select recorded_by as user_id, count(*)::int cnt from public.attendance where recorded_by is not null group by recorded_by having count(*) >= 5$$ loop
      candidate_count := candidate_count + 1;
      if not p_dry_run and public._achievement_award_system('attendance_master', null, r.user_id, 'منح تلقائي: متابعة حضور الطلاب', 'attendance', null) then
        inserted_count := inserted_count + 1;
      end if;
    end loop;
  end if;

  return jsonb_build_object('ok',true,'dry_run',p_dry_run,'candidates',candidate_count,'awards_inserted',inserted_count);
end;
$auto$;

grant execute on function public.achievement_auto_award_now(boolean) to authenticated;

-- -------------------------------------------------------------
-- 7) Payload للواجهة
-- -------------------------------------------------------------
create or replace function public.get_achievements_payload(p_scope text default 'all')
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  u record;
  can_manage boolean := false;
  can_award_teachers boolean := false;
  my_student_ids uuid[] := array[]::uuid[];
  badges jsonb := '[]'::jsonb;
  my_awards jsonb := '[]'::jsonb;
  recent_awards jsonb := '[]'::jsonb;
  leaderboard_students jsonb := '[]'::jsonb;
  leaderboard_teachers jsonb := '[]'::jsonb;
  student_candidates jsonb := '[]'::jsonb;
  teacher_candidates jsonb := '[]'::jsonb;
begin
  select id, name, email, role, is_super_admin into u from public.users where id = auth.uid();
  if u.id is null then
    return jsonb_build_object('ok',false,'message','يجب تسجيل الدخول');
  end if;

  can_manage := public.achievement_can_manage();
  can_award_teachers := exists(select 1 from public.users x where x.id=auth.uid() and (coalesce(x.is_super_admin,false) or x.role in ('admin','staff','academic','academic_admin','scientific','supervisor')));

  select coalesce(array_agg(s.id), array[]::uuid[])
  into my_student_ids
  from public.students s
  where s.user_id = auth.uid() or s.parent_id = auth.uid();

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', b.id,
    'code', b.code,
    'title_ar', b.title_ar,
    'title_fa', b.title_fa,
    'title_en', b.title_en,
    'description_ar', b.description_ar,
    'description_fa', b.description_fa,
    'description_en', b.description_en,
    'target_role', b.target_role,
    'category', b.category,
    'icon_key', b.icon_key,
    'color', b.color,
    'level', b.level,
    'points', b.points,
    'trigger_type', b.trigger_type,
    'trigger_metric', b.trigger_metric,
    'threshold', b.threshold,
    'sort_order', b.sort_order
  ) order by b.sort_order, b.title_ar), '[]'::jsonb)
  into badges
  from public.achievement_badges b
  where b.is_active = true;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.awarded_at desc), '[]'::jsonb)
  into my_awards
  from (
    select *
    from public.v_achievement_awards_detailed v
    where v.status='active'
      and (v.recipient_user_id = auth.uid() or v.recipient_student_id = any(my_student_ids))
    order by v.awarded_at desc
    limit 100
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.awarded_at desc), '[]'::jsonb)
  into recent_awards
  from (
    select *
    from public.v_achievement_awards_detailed v
    where v.status='active'
      and (
        can_manage
        or v.recipient_user_id = auth.uid()
        or v.recipient_student_id = any(my_student_ids)
      )
    order by v.awarded_at desc
    limit 40
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.points desc, x.badges_count desc), '[]'::jsonb)
  into leaderboard_students
  from (
    select
      s.id,
      public._achievement_student_name(s.id) as name,
      c.name as class_name,
      sum(a.points_awarded)::int as points,
      count(*)::int as badges_count,
      max(a.awarded_at) as last_award_at
    from public.achievement_awards a
    join public.students s on s.id = a.recipient_student_id
    left join public.classes c on c.id = s.class_id
    where a.status = 'active'
    group by s.id, c.name
    order by sum(a.points_awarded) desc, count(*) desc, max(a.awarded_at) desc
    limit 20
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.points desc, x.badges_count desc), '[]'::jsonb)
  into leaderboard_teachers
  from (
    select
      u2.id,
      coalesce(u2.name,u2.email,'معلم') as name,
      sum(a.points_awarded)::int as points,
      count(*)::int as badges_count,
      max(a.awarded_at) as last_award_at
    from public.achievement_awards a
    join public.users u2 on u2.id = a.recipient_user_id
    where a.status = 'active' and a.recipient_role = 'teacher'
    group by u2.id, u2.name, u2.email
    order by sum(a.points_awarded) desc, count(*) desc, max(a.awarded_at) desc
    limit 20
  ) x;

  if can_manage then
    if public.current_user_is_admin() or u.role in ('staff','academic','academic_admin','scientific','supervisor','discipline','counselor','psychologist') then
      select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'class_name',q.class_name) order by q.name), '[]'::jsonb)
      into student_candidates
      from (
        select s.id, public._achievement_student_name(s.id) as name, c.name as class_name
        from public.students s
        left join public.classes c on c.id = s.class_id
        order by name
        limit 500
      ) q;
    elsif u.role = 'teacher' and to_regclass('public.v_teacher_students') is not null then
      execute $q$
        select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'class_name',q.class_name) order by q.name), '[]'::jsonb)
        from (
          select distinct student_id as id, student_name as name, class_name
          from public.v_teacher_students
          where teacher_id = $1
          order by student_name
          limit 500
        ) q
      $q$ into student_candidates using auth.uid();
    end if;

    if can_award_teachers then
      select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'email',q.email) order by q.name), '[]'::jsonb)
      into teacher_candidates
      from (
        select id, coalesce(name,email,'معلم') as name, email
        from public.users
        where role = 'teacher'
        order by coalesce(name,email,'معلم')
        limit 300
      ) q;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'profile', jsonb_build_object('id',u.id,'name',u.name,'email',u.email,'role',u.role,'is_super_admin',u.is_super_admin),
    'can_manage', can_manage,
    'can_award_teachers', can_award_teachers,
    'badges', badges,
    'my_awards', my_awards,
    'recent_awards', recent_awards,
    'leaderboard_students', leaderboard_students,
    'leaderboard_teachers', leaderboard_teachers,
    'student_candidates', student_candidates,
    'teacher_candidates', teacher_candidates,
    'summary', jsonb_build_object(
      'badges_count', (select count(*) from public.achievement_badges where is_active=true),
      'active_awards', (select count(*) from public.achievement_awards where status='active'),
      'my_awards_count', jsonb_array_length(my_awards),
      'student_leaders', jsonb_array_length(leaderboard_students),
      'teacher_leaders', jsonb_array_length(leaderboard_teachers)
    )
  );
end;
$$;

grant execute on function public.get_achievements_payload(text) to authenticated;

-- -------------------------------------------------------------
-- 8) إضافة صلاحية achievements إلى البوابة الافتراضية
-- -------------------------------------------------------------
create or replace function public.portal_default_permissions(p_role text, p_is_super_admin boolean default false)
returns text[]
language plpgsql
stable
as $$
declare
  r text := lower(coalesce(p_role,''));
begin
  if coalesce(p_is_super_admin,false) or r = 'admin' then
    return array[
      'admin','staff.dashboard','finance','academic','schedule','sections','grades','attendance','behavior','counseling','users','reports','registrations','system','achievements',
      'teacher','student','parent','homework','homework.reports','homework.audit','question_bank','online_exams','exam_integrity',
      'library','inventory','assets','hr','transport','labs','activities','notifications'
    ];
  end if;

  if r = 'finance' then
    return array['staff.dashboard','finance','reports','homework.reports','library','inventory','assets','achievements','notifications'];
  end if;

  if r in ('academic','scientific','academic_supervisor','academic_admin','educational','education','supervisor') then
    return array['staff.dashboard','academic','schedule','sections','grades','attendance','behavior','reports','registrations','question_bank','online_exams','exam_integrity','homework.reports','library','transport','labs','activities','achievements','notifications'];
  end if;

  if r in ('discipline') then
    return array['staff.dashboard','attendance','behavior','students','reports','transport','homework.reports','achievements','notifications'];
  end if;

  if r in ('counselor','psychologist') then
    return array['staff.dashboard','counseling','behavior','students','attendance','reports','achievements','notifications'];
  end if;

  if r = 'teacher' then
    return array['teacher','attendance','homework','homework.reports','homework.audit','grades','question_bank','online_exams','library','transport','labs','activities','achievements','notifications'];
  end if;

  if r = 'student' then
    return array['student','homework','online_exams','grades','attendance','behavior','library','transport','activities','achievements','notifications'];
  end if;

  if r = 'parent' then
    return array['parent','student','homework','online_exams','grades','attendance','behavior','finance','library','transport','activities','achievements','notifications'];
  end if;

  if r in ('staff') then
    return array['staff.dashboard','attendance','students','reports','library','inventory','assets','transport','activities','achievements','notifications'];
  end if;

  if r in ('hr') then
    return array['staff.dashboard','hr','reports','achievements','notifications'];
  end if;

  if r in ('inventory','procurement') then
    return array['staff.dashboard','inventory','reports','achievements','notifications'];
  end if;

  if r in ('transport','transport_manager') then
    return array['staff.dashboard','transport','reports','achievements','notifications'];
  end if;

  if r in ('librarian') then
    return array['library','reports','achievements','notifications'];
  end if;

  return array['achievements','notifications'];
end;
$$;

grant execute on function public.portal_default_permissions(text,boolean) to authenticated;

-- -------------------------------------------------------------
-- 9) Health Check
-- -------------------------------------------------------------
create or replace function public.achievements_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  rls_badges jsonb;
  rls_awards jsonb;
begin
  select jsonb_build_object('rls_enabled',c.relrowsecurity,'policies',(select count(*) from pg_policies where schemaname='public' and tablename='achievement_badges'))
  into rls_badges
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='achievement_badges';

  select jsonb_build_object('rls_enabled',c.relrowsecurity,'policies',(select count(*) from pg_policies where schemaname='public' and tablename='achievement_awards'))
  into rls_awards
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='achievement_awards';

  return jsonb_build_object(
    'ok', true,
    'checked_at', now(),
    'tables', jsonb_build_object(
      'achievement_badges', to_regclass('public.achievement_badges') is not null,
      'achievement_awards', to_regclass('public.achievement_awards') is not null
    ),
    'functions', jsonb_build_object(
      'get_achievements_payload', to_regprocedure('public.get_achievements_payload(text)') is not null,
      'award_achievement_badge', to_regprocedure('public.award_achievement_badge(text,text,uuid,text)') is not null,
      'achievement_auto_award_now', to_regprocedure('public.achievement_auto_award_now(boolean)') is not null
    ),
    'rls', jsonb_build_object('badges',rls_badges,'awards',rls_awards),
    'stats', jsonb_build_object(
      'badges', (select count(*) from public.achievement_badges),
      'active_badges', (select count(*) from public.achievement_badges where is_active=true),
      'active_awards', (select count(*) from public.achievement_awards where status='active'),
      'student_awards', (select count(*) from public.achievement_awards where status='active' and recipient_role='student'),
      'teacher_awards', (select count(*) from public.achievement_awards where status='active' and recipient_role='teacher')
    )
  );
end;
$$;

grant execute on function public.achievements_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.achievements_health_check() as achievements_health;

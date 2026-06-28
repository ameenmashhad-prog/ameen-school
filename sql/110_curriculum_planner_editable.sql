-- =============================================================
-- مدارس أمين الرضا (ع) — مخطط المنهج الذكي القابل للتعديل
-- استيراد محتوى المنهج من نص مستخرج، توليد خطة تلقائية، ثم تعديل كامل من المعلم.
-- آمن ويمكن تشغيله أكثر من مرة.
-- =============================================================

create extension if not exists pgcrypto;

-- -------------------------------------------------------------
-- 0) صلاحيات
-- -------------------------------------------------------------
create or replace function public.current_user_can_curriculum()
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
      and (
        coalesce(u.is_super_admin,false)=true
        or u.role in ('admin','teacher','academic','academic_admin','scientific','supervisor')
      )
  );
$$;

grant execute on function public.current_user_can_curriculum() to authenticated;

-- -------------------------------------------------------------
-- 1) الجداول
-- -------------------------------------------------------------
create table if not exists public.curriculum_sources (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.users(id) on delete cascade default auth.uid(),
  class_id uuid null references public.classes(id) on delete set null,
  section_id uuid null references public.sections(id) on delete set null,
  subject_id uuid null references public.subjects(id) on delete set null,
  academic_period_id uuid null references public.academic_periods(id) on delete set null,
  title text not null,
  raw_text text,
  file_name text,
  file_type text,
  extraction_status text not null default 'manual_text' check (extraction_status in ('manual_text','file_uploaded','needs_review','reviewed','failed')),
  ai_confidence numeric,
  teacher_reviewed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.curriculum_lessons (
  id uuid primary key default gen_random_uuid(),
  source_id uuid null references public.curriculum_sources(id) on delete cascade,
  teacher_id uuid not null references public.users(id) on delete cascade default auth.uid(),
  class_id uuid null references public.classes(id) on delete set null,
  subject_id uuid null references public.subjects(id) on delete set null,
  sequence_no int not null default 1,
  unit_title text,
  lesson_title text not null,
  page_start int,
  page_end int,
  estimated_sessions numeric not null default 1,
  notes text,
  is_custom boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.curriculum_plans (
  id uuid primary key default gen_random_uuid(),
  source_id uuid null references public.curriculum_sources(id) on delete set null,
  teacher_id uuid not null references public.users(id) on delete cascade default auth.uid(),
  class_id uuid null references public.classes(id) on delete set null,
  section_id uuid null references public.sections(id) on delete set null,
  subject_id uuid null references public.subjects(id) on delete set null,
  academic_period_id uuid null references public.academic_periods(id) on delete set null,
  title text not null,
  academic_year text not null default '2026-2027',
  lessons_per_week int not null default 4 check (lessons_per_week between 1 and 12),
  start_date date not null default current_date,
  end_date date,
  status text not null default 'draft' check (status in ('draft','active','archived','completed')),
  auto_generated boolean not null default true,
  teacher_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.curriculum_plan_slots (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.curriculum_plans(id) on delete cascade,
  lesson_id uuid null references public.curriculum_lessons(id) on delete set null,
  month_index int not null default 1 check (month_index between 1 and 12),
  week_index int not null default 1 check (week_index between 1 and 60),
  day_index int check (day_index between 1 and 7),
  slot_order int not null default 1,
  planned_date date,
  planned_duration_minutes int not null default 45,
  status text not null default 'planned' check (status in ('planned','in_progress','completed','skipped','postponed','cancelled')),
  progress_percent int not null default 0 check (progress_percent between 0 and 100),
  manual_override boolean not null default false,
  teacher_notes text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.curriculum_plan_snapshots (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.curriculum_plans(id) on delete cascade,
  reason text,
  snapshot jsonb not null,
  created_by uuid null references public.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.curriculum_plan_audit (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid null references public.curriculum_plans(id) on delete cascade,
  slot_id uuid null references public.curriculum_plan_slots(id) on delete set null,
  action text not null,
  before_data jsonb,
  after_data jsonb,
  created_by uuid null references public.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists idx_curriculum_sources_teacher on public.curriculum_sources(teacher_id, created_at desc);
create index if not exists idx_curriculum_lessons_source on public.curriculum_lessons(source_id, sequence_no);
create index if not exists idx_curriculum_plans_teacher on public.curriculum_plans(teacher_id, status, created_at desc);
create index if not exists idx_curriculum_slots_plan_week on public.curriculum_plan_slots(plan_id, month_index, week_index, slot_order);
create index if not exists idx_curriculum_slots_status on public.curriculum_plan_slots(plan_id, status);
create index if not exists idx_curriculum_audit_plan on public.curriculum_plan_audit(plan_id, created_at desc);

-- -------------------------------------------------------------
-- 2) RLS
-- -------------------------------------------------------------
alter table public.curriculum_sources enable row level security;
alter table public.curriculum_lessons enable row level security;
alter table public.curriculum_plans enable row level security;
alter table public.curriculum_plan_slots enable row level security;
alter table public.curriculum_plan_snapshots enable row level security;
alter table public.curriculum_plan_audit enable row level security;

drop policy if exists curriculum_sources_access on public.curriculum_sources;
drop policy if exists curriculum_lessons_access on public.curriculum_lessons;
drop policy if exists curriculum_plans_access on public.curriculum_plans;
drop policy if exists curriculum_slots_access on public.curriculum_plan_slots;
drop policy if exists curriculum_snapshots_access on public.curriculum_plan_snapshots;
drop policy if exists curriculum_audit_access on public.curriculum_plan_audit;

create policy curriculum_sources_access on public.curriculum_sources for all to authenticated
using (public.current_user_can_curriculum() and (teacher_id=auth.uid() or public.current_user_is_admin()))
with check (public.current_user_can_curriculum() and (teacher_id=auth.uid() or public.current_user_is_admin()));

create policy curriculum_lessons_access on public.curriculum_lessons for all to authenticated
using (public.current_user_can_curriculum() and (teacher_id=auth.uid() or public.current_user_is_admin()))
with check (public.current_user_can_curriculum() and (teacher_id=auth.uid() or public.current_user_is_admin()));

create policy curriculum_plans_access on public.curriculum_plans for all to authenticated
using (public.current_user_can_curriculum() and (teacher_id=auth.uid() or public.current_user_is_admin()))
with check (public.current_user_can_curriculum() and (teacher_id=auth.uid() or public.current_user_is_admin()));

create policy curriculum_slots_access on public.curriculum_plan_slots for all to authenticated
using (exists(select 1 from public.curriculum_plans p where p.id=plan_id and public.current_user_can_curriculum() and (p.teacher_id=auth.uid() or public.current_user_is_admin())))
with check (exists(select 1 from public.curriculum_plans p where p.id=plan_id and public.current_user_can_curriculum() and (p.teacher_id=auth.uid() or public.current_user_is_admin())));

create policy curriculum_snapshots_access on public.curriculum_plan_snapshots for all to authenticated
using (exists(select 1 from public.curriculum_plans p where p.id=plan_id and public.current_user_can_curriculum() and (p.teacher_id=auth.uid() or public.current_user_is_admin())))
with check (exists(select 1 from public.curriculum_plans p where p.id=plan_id and public.current_user_can_curriculum() and (p.teacher_id=auth.uid() or public.current_user_is_admin())));

create policy curriculum_audit_access on public.curriculum_plan_audit for all to authenticated
using (plan_id is null or exists(select 1 from public.curriculum_plans p where p.id=plan_id and public.current_user_can_curriculum() and (p.teacher_id=auth.uid() or public.current_user_is_admin())))
with check (plan_id is null or exists(select 1 from public.curriculum_plans p where p.id=plan_id and public.current_user_can_curriculum() and (p.teacher_id=auth.uid() or public.current_user_is_admin())));

grant select, insert, update on public.curriculum_sources to authenticated;
grant select, insert, update on public.curriculum_lessons to authenticated;
grant select, insert, update on public.curriculum_plans to authenticated;
grant select, insert, update on public.curriculum_plan_slots to authenticated;
grant select, insert on public.curriculum_plan_snapshots to authenticated;
grant select, insert on public.curriculum_plan_audit to authenticated;

-- -------------------------------------------------------------
-- 3) Views
-- -------------------------------------------------------------
create or replace view public.v_curriculum_plan_slots_detailed
with (security_invoker=true) as
select
  sl.id,
  sl.plan_id,
  sl.lesson_id,
  p.title as plan_title,
  p.teacher_id,
  p.class_id,
  c.name as class_name,
  p.section_id,
  sec.name as section_name,
  p.subject_id,
  sub.name as subject_name,
  p.lessons_per_week,
  p.status as plan_status,
  l.sequence_no,
  l.unit_title,
  l.lesson_title,
  l.page_start,
  l.page_end,
  l.estimated_sessions,
  l.is_custom,
  sl.month_index,
  sl.week_index,
  sl.day_index,
  sl.slot_order,
  sl.planned_date,
  sl.planned_duration_minutes,
  sl.status,
  sl.progress_percent,
  sl.manual_override,
  sl.teacher_notes,
  sl.completed_at,
  sl.updated_at
from public.curriculum_plan_slots sl
join public.curriculum_plans p on p.id = sl.plan_id
left join public.curriculum_lessons l on l.id = sl.lesson_id
left join public.classes c on c.id = p.class_id
left join public.sections sec on sec.id = p.section_id
left join public.subjects sub on sub.id = p.subject_id;

grant select on public.v_curriculum_plan_slots_detailed to authenticated;

create or replace view public.v_curriculum_plan_progress
with (security_invoker=true) as
select
  p.id as plan_id,
  p.title,
  p.teacher_id,
  p.class_id,
  c.name as class_name,
  p.subject_id,
  sub.name as subject_name,
  p.status,
  p.lessons_per_week,
  count(sl.id)::int as total_slots,
  count(sl.id) filter (where sl.status='completed')::int as completed_slots,
  count(sl.id) filter (where sl.status='in_progress')::int as in_progress_slots,
  count(sl.id) filter (where sl.status in ('planned','postponed'))::int as remaining_slots,
  count(sl.id) filter (where sl.manual_override)::int as manual_edits,
  case when count(sl.id)=0 then 0 else round(count(sl.id) filter (where sl.status='completed')::numeric / count(sl.id) * 100)::int end as progress_percent,
  max(sl.updated_at) as last_update
from public.curriculum_plans p
left join public.curriculum_plan_slots sl on sl.plan_id = p.id
left join public.classes c on c.id = p.class_id
left join public.subjects sub on sub.id = p.subject_id
group by p.id, c.name, sub.name;

grant select on public.v_curriculum_plan_progress to authenticated;

-- -------------------------------------------------------------
-- 4) Helpers
-- -------------------------------------------------------------
create or replace function public.curriculum_log(p_plan_id uuid, p_slot_id uuid, p_action text, p_before jsonb default null, p_after jsonb default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.curriculum_plan_audit(plan_id, slot_id, action, before_data, after_data, created_by)
  values(p_plan_id, p_slot_id, p_action, p_before, p_after, auth.uid());
exception when others then
  null;
end;
$$;

revoke all on function public.curriculum_log(uuid,uuid,text,jsonb,jsonb) from public;

-- -------------------------------------------------------------
-- 5) RPC: payload
-- -------------------------------------------------------------
create or replace function public.get_curriculum_planner_payload()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  u record;
  plans jsonb := '[]'::jsonb;
  progress jsonb := '[]'::jsonb;
  slots jsonb := '[]'::jsonb;
  sources jsonb := '[]'::jsonb;
  classes jsonb := '[]'::jsonb;
  subjects jsonb := '[]'::jsonb;
  sections jsonb := '[]'::jsonb;
  periods jsonb := '[]'::jsonb;
  audit jsonb := '[]'::jsonb;
begin
  select id,name,email,role,is_super_admin into u from public.users where id=auth.uid();
  if u.id is null then return jsonb_build_object('ok',false,'message','يجب تسجيل الدخول'); end if;
  if not public.current_user_can_curriculum() then return jsonb_build_object('ok',false,'message','لا تملك صلاحية تخطيط المنهج'); end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into plans
  from (select * from public.curriculum_plans where teacher_id=u.id or public.current_user_is_admin() order by created_at desc limit 100) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.last_update desc nulls last), '[]'::jsonb)
  into progress
  from (select * from public.v_curriculum_plan_progress where teacher_id=u.id or public.current_user_is_admin() order by last_update desc nulls last limit 100) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.month_index, x.week_index, x.slot_order), '[]'::jsonb)
  into slots
  from (select * from public.v_curriculum_plan_slots_detailed where teacher_id=u.id or public.current_user_is_admin() order by month_index, week_index, slot_order limit 1500) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into sources
  from (select * from public.curriculum_sources where teacher_id=u.id or public.current_user_is_admin() order by created_at desc limit 100) x;

  select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name), '[]'::jsonb) into classes from public.classes;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name), '[]'::jsonb) into subjects from public.subjects;
  if to_regclass('public.sections') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code,'class_id',class_id) order by name), '[]'::jsonb) into sections from public.sections;
  end if;
  if to_regclass('public.academic_periods') is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by start_date nulls last, name), '[]'::jsonb) into periods from public.academic_periods;
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  into audit
  from (
    select a.*
    from public.curriculum_plan_audit a
    left join public.curriculum_plans p on p.id=a.plan_id
    where p.teacher_id=u.id or public.current_user_is_admin()
    order by a.created_at desc
    limit 80
  ) x;

  return jsonb_build_object('ok',true,'profile',to_jsonb(u),'plans',plans,'progress',progress,'slots',slots,'sources',sources,'classes',classes,'subjects',subjects,'sections',sections,'periods',periods,'audit',audit);
end;
$$;

grant execute on function public.get_curriculum_planner_payload() to authenticated;

-- -------------------------------------------------------------
-- 6) RPC: إنشاء خطة من نص مستخرج
-- -------------------------------------------------------------
create or replace function public.curriculum_create_from_text(
  p_title text,
  p_class_id uuid,
  p_subject_id uuid,
  p_section_id uuid default null,
  p_academic_period_id uuid default null,
  p_raw_text text default '',
  p_lessons_per_week int default 4,
  p_start_date date default current_date,
  p_file_name text default null,
  p_file_type text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  source_id uuid;
  plan_id uuid;
  line text;
  clean_title text;
  m text[];
  p1 int;
  p2 int;
  seq int := 0;
  lpw int := greatest(1, least(12, coalesce(p_lessons_per_week,4)));
  week_i int;
  month_i int;
  slot_i int;
  lesson_id uuid;
  lesson_count int := 0;
begin
  if not public.current_user_can_curriculum() then
    return jsonb_build_object('ok',false,'message','لا تملك صلاحية تخطيط المنهج');
  end if;
  if nullif(trim(coalesce(p_title,'')),'') is null then
    return jsonb_build_object('ok',false,'message','عنوان الخطة مطلوب');
  end if;

  insert into public.curriculum_sources(teacher_id,class_id,section_id,subject_id,academic_period_id,title,raw_text,file_name,file_type,extraction_status,teacher_reviewed)
  values(auth.uid(),p_class_id,p_section_id,p_subject_id,p_academic_period_id,trim(p_title),p_raw_text,p_file_name,p_file_type,case when p_file_name is not null then 'file_uploaded' else 'manual_text' end,false)
  returning id into source_id;

  insert into public.curriculum_plans(source_id,teacher_id,class_id,section_id,subject_id,academic_period_id,title,lessons_per_week,start_date,status,auto_generated)
  values(source_id,auth.uid(),p_class_id,p_section_id,p_subject_id,p_academic_period_id,trim(p_title),lpw,coalesce(p_start_date,current_date),'active',true)
  returning id into plan_id;

  for line in
    select trim(x) from regexp_split_to_table(coalesce(p_raw_text,''), E'\n+') x
  loop
    if length(line) < 2 then continue; end if;
    seq := seq + 1;
    p1 := null; p2 := null;
    m := regexp_match(line, '([0-9]{1,4})\s*[-–]\s*([0-9]{1,4})');
    if m is not null then
      p1 := m[1]::int; p2 := m[2]::int;
    else
      m := regexp_match(line, '(?:ص|صفحة|page)\s*[:.]?\s*([0-9]{1,4})', 'i');
      if m is not null then p1 := m[1]::int; p2 := p1; end if;
    end if;
    clean_title := regexp_replace(line, '(?:ص|صفحة|page)?\s*[0-9]{1,4}\s*[-–]\s*[0-9]{1,4}', '', 'gi');
    clean_title := regexp_replace(clean_title, '(?:ص|صفحة|page)\s*[:.]?\s*[0-9]{1,4}', '', 'gi');
    clean_title := nullif(trim(regexp_replace(clean_title, '^[\-–:،\s]+|[\-–:،\s]+$', '', 'g')), '');
    if clean_title is null then clean_title := 'درس ' || seq::text; end if;

    insert into public.curriculum_lessons(source_id,teacher_id,class_id,subject_id,sequence_no,lesson_title,page_start,page_end,estimated_sessions,is_custom)
    values(source_id,auth.uid(),p_class_id,p_subject_id,seq,clean_title,p1,p2,1,false)
    returning id into lesson_id;

    week_i := ((seq - 1) / lpw) + 1;
    month_i := ((week_i - 1) / 4) + 1;
    slot_i := ((seq - 1) % lpw) + 1;

    insert into public.curriculum_plan_slots(plan_id,lesson_id,month_index,week_index,day_index,slot_order,planned_date,planned_duration_minutes,status,progress_percent)
    values(plan_id,lesson_id,month_i,week_i,slot_i,slot_i,coalesce(p_start_date,current_date) + (((week_i-1)*7 + (slot_i-1))::int),'45','planned',0);
    lesson_count := lesson_count + 1;
  end loop;

  perform public.curriculum_log(plan_id,null,'create_from_text',null,jsonb_build_object('lessons',lesson_count,'lessons_per_week',lpw));

  return jsonb_build_object('ok',true,'source_id',source_id,'plan_id',plan_id,'lessons_created',lesson_count,'message','تم توليد خطة قابلة للتعديل');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.curriculum_create_from_text(text,uuid,uuid,uuid,uuid,text,int,date,text,text) to authenticated;

-- -------------------------------------------------------------
-- 7) Snapshots
-- -------------------------------------------------------------
create or replace function public.curriculum_snapshot_plan(p_plan_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  snap jsonb;
  sid uuid;
begin
  if not exists(select 1 from public.curriculum_plans p where p.id=p_plan_id and (p.teacher_id=auth.uid() or public.current_user_is_admin())) then
    return jsonb_build_object('ok',false,'message','لا توجد صلاحية على الخطة');
  end if;

  select jsonb_build_object(
    'plan', to_jsonb(p),
    'slots', coalesce((select jsonb_agg(to_jsonb(s) order by s.month_index,s.week_index,s.slot_order) from public.v_curriculum_plan_slots_detailed s where s.plan_id=p_plan_id),'[]'::jsonb)
  ) into snap
  from public.curriculum_plans p
  where p.id=p_plan_id;

  insert into public.curriculum_plan_snapshots(plan_id,reason,snapshot,created_by)
  values(p_plan_id,coalesce(p_reason,'snapshot'),snap,auth.uid())
  returning id into sid;

  perform public.curriculum_log(p_plan_id,null,'snapshot',null,jsonb_build_object('snapshot_id',sid,'reason',p_reason));
  return jsonb_build_object('ok',true,'snapshot_id',sid,'message','تم حفظ نسخة احتياطية');
end;
$$;

grant execute on function public.curriculum_snapshot_plan(uuid,text) to authenticated;

-- -------------------------------------------------------------
-- 8) تحديث slot/lesson من واجهة المعلم
-- -------------------------------------------------------------
create or replace function public.curriculum_update_slot(p_slot_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  old_slot jsonb;
  new_slot jsonb;
  sl record;
  new_status text;
  new_title text;
begin
  select * into sl from public.curriculum_plan_slots where id=p_slot_id;
  if sl.id is null then return jsonb_build_object('ok',false,'message','العنصر غير موجود'); end if;
  if not exists(select 1 from public.curriculum_plans p where p.id=sl.plan_id and (p.teacher_id=auth.uid() or public.current_user_is_admin())) then
    return jsonb_build_object('ok',false,'message','لا توجد صلاحية تعديل');
  end if;
  old_slot := to_jsonb(sl);

  new_status := coalesce(nullif(p_payload->>'status',''), sl.status);
  if new_status not in ('planned','in_progress','completed','skipped','postponed','cancelled') then new_status := sl.status; end if;

  update public.curriculum_plan_slots
  set month_index = coalesce(nullif(p_payload->>'month_index','')::int, month_index),
      week_index = coalesce(nullif(p_payload->>'week_index','')::int, week_index),
      day_index = coalesce(nullif(p_payload->>'day_index','')::int, day_index),
      slot_order = coalesce(nullif(p_payload->>'slot_order','')::int, slot_order),
      planned_date = coalesce(nullif(p_payload->>'planned_date','')::date, planned_date),
      planned_duration_minutes = coalesce(nullif(p_payload->>'planned_duration_minutes','')::int, planned_duration_minutes),
      status = new_status,
      progress_percent = case when new_status='completed' then 100 else coalesce(nullif(p_payload->>'progress_percent','')::int, progress_percent) end,
      teacher_notes = coalesce(p_payload->>'teacher_notes', teacher_notes),
      manual_override = true,
      completed_at = case when new_status='completed' then coalesce(completed_at,now()) else completed_at end,
      updated_at = now()
  where id=p_slot_id
  returning to_jsonb(public.curriculum_plan_slots.*) into new_slot;

  new_title := nullif(trim(coalesce(p_payload->>'lesson_title','')), '');
  if new_title is not null and sl.lesson_id is not null then
    update public.curriculum_lessons
    set lesson_title=new_title,
        page_start=coalesce(nullif(p_payload->>'page_start','')::int,page_start),
        page_end=coalesce(nullif(p_payload->>'page_end','')::int,page_end),
        estimated_sessions=coalesce(nullif(p_payload->>'estimated_sessions','')::numeric,estimated_sessions),
        notes=coalesce(p_payload->>'lesson_notes',notes),
        updated_at=now()
    where id=sl.lesson_id;
  end if;

  perform public.curriculum_log(sl.plan_id,p_slot_id,'update_slot',old_slot,new_slot);
  return jsonb_build_object('ok',true,'slot',new_slot,'message','تم تحديث الخطة');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.curriculum_update_slot(uuid,jsonb) to authenticated;

-- -------------------------------------------------------------
-- 9) إضافة درس مخصص
-- -------------------------------------------------------------
create or replace function public.curriculum_add_custom_lesson(p_plan_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
  lesson_id uuid;
  slot_id uuid;
  title text := coalesce(nullif(trim(p_payload->>'lesson_title'),''),'درس مخصص');
begin
  select * into p from public.curriculum_plans where id=p_plan_id;
  if p.id is null then return jsonb_build_object('ok',false,'message','الخطة غير موجودة'); end if;
  if not (p.teacher_id=auth.uid() or public.current_user_is_admin()) then return jsonb_build_object('ok',false,'message','لا توجد صلاحية'); end if;

  insert into public.curriculum_lessons(source_id,teacher_id,class_id,subject_id,sequence_no,lesson_title,page_start,page_end,estimated_sessions,notes,is_custom)
  values(p.source_id,p.teacher_id,p.class_id,p.subject_id,coalesce((select max(sequence_no)+1 from public.curriculum_lessons where source_id=p.source_id),1),title,nullif(p_payload->>'page_start','')::int,nullif(p_payload->>'page_end','')::int,coalesce(nullif(p_payload->>'estimated_sessions','')::numeric,1),p_payload->>'notes',true)
  returning id into lesson_id;

  insert into public.curriculum_plan_slots(plan_id,lesson_id,month_index,week_index,day_index,slot_order,planned_date,planned_duration_minutes,status,manual_override,teacher_notes)
  values(p.id,lesson_id,coalesce(nullif(p_payload->>'month_index','')::int,1),coalesce(nullif(p_payload->>'week_index','')::int,1),nullif(p_payload->>'day_index','')::int,coalesce(nullif(p_payload->>'slot_order','')::int,1),nullif(p_payload->>'planned_date','')::date,coalesce(nullif(p_payload->>'planned_duration_minutes','')::int,45),'planned',true,p_payload->>'teacher_notes')
  returning id into slot_id;

  perform public.curriculum_log(p.id,slot_id,'add_custom_lesson',null,jsonb_build_object('lesson_id',lesson_id,'title',title));
  return jsonb_build_object('ok',true,'lesson_id',lesson_id,'slot_id',slot_id,'message','تمت إضافة الدرس المخصص');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.curriculum_add_custom_lesson(uuid,jsonb) to authenticated;

-- -------------------------------------------------------------
-- 10) إعادة توزيع الدروس المتبقية فقط
-- -------------------------------------------------------------
create or replace function public.curriculum_redistribute_remaining(p_plan_id uuid, p_lessons_per_week int default null, p_start_week int default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
  lpw int;
  start_w int;
  i int := 0;
  r record;
  before_json jsonb;
  moved int := 0;
begin
  select * into p from public.curriculum_plans where id=p_plan_id;
  if p.id is null then return jsonb_build_object('ok',false,'message','الخطة غير موجودة'); end if;
  if not (p.teacher_id=auth.uid() or public.current_user_is_admin()) then return jsonb_build_object('ok',false,'message','لا توجد صلاحية'); end if;

  perform public.curriculum_snapshot_plan(p_plan_id,'before_redistribute_remaining');

  lpw := greatest(1, least(12, coalesce(p_lessons_per_week,p.lessons_per_week,4)));
  select coalesce(min(week_index),1) into start_w from public.curriculum_plan_slots where plan_id=p_plan_id and status not in ('completed','cancelled');
  start_w := coalesce(p_start_week,start_w,1);

  for r in select * from public.curriculum_plan_slots where plan_id=p_plan_id and status not in ('completed','cancelled') order by week_index, slot_order loop
    before_json := to_jsonb(r);
    update public.curriculum_plan_slots
    set week_index = start_w + (i / lpw),
        month_index = ((start_w + (i / lpw) - 1) / 4) + 1,
        slot_order = (i % lpw) + 1,
        day_index = (i % lpw) + 1,
        planned_date = p.start_date + (((start_w + (i / lpw) - 1)*7 + (i % lpw))::int),
        manual_override = true,
        updated_at = now()
    where id = r.id;
    perform public.curriculum_log(p_plan_id,r.id,'redistribute_remaining',before_json,(select to_jsonb(x) from public.curriculum_plan_slots x where x.id=r.id));
    i := i + 1; moved := moved + 1;
  end loop;

  update public.curriculum_plans set lessons_per_week=lpw, updated_at=now() where id=p_plan_id;
  return jsonb_build_object('ok',true,'moved',moved,'lessons_per_week',lpw,'message','تمت إعادة توزيع الدروس المتبقية');
exception when others then
  return jsonb_build_object('ok',false,'message',sqlerrm);
end;
$$;

grant execute on function public.curriculum_redistribute_remaining(uuid,int,int) to authenticated;

-- -------------------------------------------------------------
-- 11) Health Check
-- -------------------------------------------------------------
create or replace function public.curriculum_planner_health_check()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'checked_at', now(),
    'tables', jsonb_build_object(
      'curriculum_sources', to_regclass('public.curriculum_sources') is not null,
      'curriculum_lessons', to_regclass('public.curriculum_lessons') is not null,
      'curriculum_plans', to_regclass('public.curriculum_plans') is not null,
      'curriculum_plan_slots', to_regclass('public.curriculum_plan_slots') is not null,
      'curriculum_plan_snapshots', to_regclass('public.curriculum_plan_snapshots') is not null,
      'curriculum_plan_audit', to_regclass('public.curriculum_plan_audit') is not null
    ),
    'views', jsonb_build_object(
      'v_curriculum_plan_slots_detailed', to_regclass('public.v_curriculum_plan_slots_detailed') is not null,
      'v_curriculum_plan_progress', to_regclass('public.v_curriculum_plan_progress') is not null
    ),
    'functions', jsonb_build_object(
      'get_curriculum_planner_payload', to_regprocedure('public.get_curriculum_planner_payload()') is not null,
      'curriculum_create_from_text', to_regprocedure('public.curriculum_create_from_text(text,uuid,uuid,uuid,uuid,text,int,date,text,text)') is not null,
      'curriculum_update_slot', to_regprocedure('public.curriculum_update_slot(uuid,jsonb)') is not null,
      'curriculum_add_custom_lesson', to_regprocedure('public.curriculum_add_custom_lesson(uuid,jsonb)') is not null,
      'curriculum_redistribute_remaining', to_regprocedure('public.curriculum_redistribute_remaining(uuid,int,int)') is not null
    ),
    'stats', jsonb_build_object(
      'plans', (select count(*) from public.curriculum_plans),
      'lessons', (select count(*) from public.curriculum_lessons),
      'slots', (select count(*) from public.curriculum_plan_slots),
      'snapshots', (select count(*) from public.curriculum_plan_snapshots)
    )
  );
end;
$$;

grant execute on function public.curriculum_planner_health_check() to authenticated;

notify pgrst, 'reload schema';

select public.curriculum_planner_health_check() as curriculum_planner_health;

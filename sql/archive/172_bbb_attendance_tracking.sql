-- ============================================================================
-- BigBlueButton Attendance Tracking — تسجيل تلقائي لحضور BBB وربطه بالحضور
-- الهدف: معرفة من دخل الحصة وكم بقي وربطه تلقائياً بجدول attendance و daily_followup
-- ============================================================================

-- 1) جدول اجتماعات BBB
CREATE TABLE IF NOT EXISTS public.bbb_meetings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id text NOT NULL UNIQUE,
  class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL,
  subject_id uuid REFERENCES public.subjects(id) ON DELETE SET NULL,
  title text NOT NULL,
  created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  bbb_server_url text,
  moderator_pw text,
  attendee_pw text,
  status text DEFAULT 'created' CHECK (status IN ('created','running','ended','archived')),
  started_at timestamptz,
  ended_at timestamptz,
  duration_minutes int,
  recording_url text,
  summary text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bbb_meetings_class ON public.bbb_meetings(class_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bbb_meetings_meeting_id ON public.bbb_meetings(meeting_id);
CREATE INDEX IF NOT EXISTS idx_bbb_meetings_status ON public.bbb_meetings(status);

-- 2) جدول حضور BBB التفصيلي — من دخل وكم بقي
CREATE TABLE IF NOT EXISTS public.bbb_attendance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id text NOT NULL REFERENCES public.bbb_meetings(meeting_id) ON DELETE CASCADE,
  bbb_meeting_id uuid REFERENCES public.bbb_meetings(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  student_id uuid REFERENCES public.students(id) ON DELETE SET NULL,
  full_name text NOT NULL,
  role text CHECK (role IN ('moderator','attendee','viewer')),
  join_time timestamptz NOT NULL DEFAULT now(),
  leave_time timestamptz,
  duration_minutes int DEFAULT 0,
  -- تفاصيل إضافية من BBB
  is_presenter boolean DEFAULT false,
  has_video boolean DEFAULT false,
  has_audio boolean DEFAULT false,
  -- ربط بالمتابعة اليومية
  daily_followup_id uuid REFERENCES public.daily_followup(id) ON DELETE SET NULL,
  attendance_id uuid REFERENCES public.attendance(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bbb_attendance_meeting ON public.bbb_attendance(meeting_id, join_time);
CREATE INDEX IF NOT EXISTS idx_bbb_attendance_student ON public.bbb_attendance(student_id);
CREATE INDEX IF NOT EXISTS idx_bbb_attendance_user ON public.bbb_attendance(user_id);
CREATE INDEX IF NOT EXISTS idx_bbb_attendance_full_name ON public.bbb_attendance(full_name);

-- 3) RLS
ALTER TABLE public.bbb_meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bbb_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bbb_meetings_select_all ON public.bbb_meetings;
CREATE POLICY bbb_meetings_select_all ON public.bbb_meetings FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS bbb_meetings_insert_teacher_admin ON public.bbb_meetings;
CREATE POLICY bbb_meetings_insert_teacher_admin ON public.bbb_meetings FOR INSERT TO authenticated WITH CHECK (
  EXISTS(SELECT 1 FROM public.users u WHERE u.id=auth.uid() AND (u.role IN ('teacher','admin','academic') OR u.is_super_admin))
);

DROP POLICY IF EXISTS bbb_meetings_update_author_admin ON public.bbb_meetings;
CREATE POLICY bbb_meetings_update_author_admin ON public.bbb_meetings FOR UPDATE TO authenticated USING (
  created_by=auth.uid() OR EXISTS(SELECT 1 FROM public.users u WHERE u.id=auth.uid() AND (u.role='admin' OR u.is_super_admin))
);

DROP POLICY IF EXISTS bbb_attendance_select_all ON public.bbb_attendance;
CREATE POLICY bbb_attendance_select_all ON public.bbb_attendance FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS bbb_attendance_insert_all ON public.bbb_attendance;
CREATE POLICY bbb_attendance_insert_all ON public.bbb_attendance FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS bbb_attendance_update_own_admin ON public.bbb_attendance;
CREATE POLICY bbb_attendance_update_own_admin ON public.bbb_attendance FOR UPDATE TO authenticated USING (
  user_id=auth.uid() OR EXISTS(SELECT 1 FROM public.users u WHERE u.id=auth.uid() AND (u.role IN ('admin','teacher') OR u.is_super_admin))
);

GRANT SELECT, INSERT, UPDATE ON public.bbb_meetings TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.bbb_attendance TO authenticated;

-- 4) دالة تسجيل دخول الطالب لحصة BBB
CREATE OR REPLACE FUNCTION public.log_bbb_join(
  p_meeting_id text,
  p_full_name text,
  p_role text DEFAULT 'attendee'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_student_id uuid;
  v_meeting_uuid uuid;
  v_attendance_id uuid;
BEGIN
  -- جلب معرف الطالب
  SELECT id INTO v_student_id FROM public.students WHERE user_id=v_user_id LIMIT 1;
  IF v_student_id IS NULL THEN
    SELECT id INTO v_student_id FROM public.students WHERE parent_id=v_user_id LIMIT 1;
  END IF;

  -- جلب معرف الاجتماع الداخلي
  SELECT id INTO v_meeting_uuid FROM public.bbb_meetings WHERE meeting_id=p_meeting_id LIMIT 1;

  -- تسجيل الدخول
  INSERT INTO public.bbb_attendance(meeting_id, bbb_meeting_id, user_id, student_id, full_name, role, join_time)
  VALUES (p_meeting_id, v_meeting_uuid, v_user_id, v_student_id, p_full_name, p_role, now())
  RETURNING id INTO v_attendance_id;

  -- تحديث المتابعة اليومية تلقائياً: حاضر + حضر حصة BBB
  IF v_student_id IS NOT NULL THEN
    INSERT INTO public.daily_followup(student_id, class_id, followup_date, attendance_status, behavior_note, created_by)
    SELECT 
      v_student_id,
      s.class_id,
      CURRENT_DATE,
      'present',
      'حضر حصة BBB: ' || p_meeting_id,
      v_user_id
    FROM public.students s WHERE s.id=v_student_id
    ON CONFLICT (student_id, followup_date) 
    DO UPDATE SET 
      attendance_status='present',
      behavior_note=COALESCE(public.daily_followup.behavior_note,'') || ' | حضر BBB: ' || p_meeting_id,
      updated_at=now();

    -- أيضاً سجل في attendance العام
    INSERT INTO public.attendance(student_id, date, status, note, recorded_by, attendance_type)
    VALUES (v_student_id, CURRENT_DATE, 'present', 'حضر حصة BBB: ' || p_meeting_id, v_user_id, 'online')
    ON CONFLICT (student_id, date, attendance_type) DO UPDATE SET status='present', note=EXCLUDED.note;
  END IF;

  RETURN v_attendance_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_bbb_join(text,text,text) TO authenticated;

-- 5) دالة تسجيل خروج الطالب من BBB وحساب المدة
CREATE OR REPLACE FUNCTION public.log_bbb_leave(
  p_attendance_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_duration int;
  v_meeting_id text;
BEGIN
  UPDATE public.bbb_attendance
  SET leave_time=now(),
      duration_minutes=EXTRACT(EPOCH FROM (now() - join_time))/60
  WHERE id=p_attendance_id AND user_id=auth.uid()
  RETURNING duration_minutes, meeting_id INTO v_duration, v_meeting_id;

  RETURN jsonb_build_object('ok', true, 'duration_minutes', v_duration, 'meeting_id', v_meeting_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_bbb_leave(uuid) TO authenticated;

-- 6) دالة إنهاء الاجتماع وتحديث حضور الجميع تلقائياً
CREATE OR REPLACE FUNCTION public.end_bbb_meeting(
  p_meeting_id text,
  p_summary text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int;
  v_meeting_uuid uuid;
BEGIN
  -- تحديث الاجتماع
  UPDATE public.bbb_meetings
  SET status='ended', ended_at=now(), 
      duration_minutes=EXTRACT(EPOCH FROM (now() - started_at))/60,
      summary=COALESCE(p_summary, summary),
      updated_at=now()
  WHERE meeting_id=p_meeting_id
  RETURNING id INTO v_meeting_uuid;

  -- تحديث كل الحضور الذين لم يسجلوا خروج
  UPDATE public.bbb_attendance
  SET leave_time=now(),
      duration_minutes=EXTRACT(EPOCH FROM (now() - join_time))/60
  WHERE meeting_id=p_meeting_id AND leave_time IS NULL;

  -- إحصائية
  SELECT COUNT(*) INTO v_count FROM public.bbb_attendance WHERE meeting_id=p_meeting_id;

  RETURN jsonb_build_object('ok', true, 'meeting_id', p_meeting_id, 'attendance_count', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.end_bbb_meeting(text,text) TO authenticated;

-- 7) View لحضور BBB مع الملخص
CREATE OR REPLACE VIEW public.v_bbb_attendance_summary
WITH (security_invoker=true) AS
SELECT 
  m.meeting_id,
  m.title,
  m.class_id,
  c.name as class_name,
  m.status,
  m.started_at,
  m.ended_at,
  m.duration_minutes as meeting_duration,
  COUNT(a.id) as total_attendees,
  COUNT(a.id) FILTER (WHERE a.role='moderator') as moderators_count,
  COUNT(a.id) FILTER (WHERE a.role='attendee') as students_count,
  COUNT(a.id) FILTER (WHERE a.duration_minutes >= 5) as valid_attendance_count,
  ROUND(AVG(a.duration_minutes),1) as avg_duration,
  STRING_AGG(DISTINCT a.full_name, '، ' ORDER BY a.full_name) as attendee_names,
  m.created_at
FROM public.bbb_meetings m
LEFT JOIN public.bbb_attendance a ON a.meeting_id=m.meeting_id
LEFT JOIN public.classes c ON c.id=m.class_id
GROUP BY m.meeting_id, m.title, m.class_id, c.name, m.status, m.started_at, m.ended_at, m.duration_minutes, m.created_at
ORDER BY m.created_at DESC;

GRANT SELECT ON public.v_bbb_attendance_summary TO authenticated;

-- 8) Webhook endpoint لاستقبال callbacks من BBB (اختياري)
-- BBB يمكنه إرسال POST إلى /api/bbb/webhook عند انتهاء الاجتماع
-- هذا الجدول يحفظ الـ webhooks الخام
CREATE TABLE IF NOT EXISTS public.bbb_webhooks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id text,
  event_type text,
  payload jsonb,
  processed boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.bbb_webhooks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bbb_webhooks_admin_all ON public.bbb_webhooks;
CREATE POLICY bbb_webhooks_admin_all ON public.bbb_webhooks FOR ALL TO authenticated USING (
  EXISTS(SELECT 1 FROM public.users u WHERE u.id=auth.uid() AND (u.role='admin' OR u.is_super_admin))
);
GRANT SELECT, INSERT ON public.bbb_webhooks TO authenticated;

SELECT 'bbb_attendance_tracking_done' as status;

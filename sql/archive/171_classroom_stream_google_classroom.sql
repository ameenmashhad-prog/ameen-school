-- ============================================================================
-- Google Classroom Reference - Enhanced Assignments, Posts, Daily Follow-up
-- تطوير الواجبات والمنشورات والمتابعة اليومية على نمط Google Classroom
-- ============================================================================

-- 1) جدول منشورات الصف (Stream) - مثل Google Classroom Stream
CREATE TABLE IF NOT EXISTS public.classroom_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid REFERENCES public.classes(id) ON DELETE CASCADE,
  section_id uuid REFERENCES public.sections(id) ON DELETE SET NULL,
  subject_id uuid REFERENCES public.subjects(id) ON DELETE SET NULL,
  author_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  post_type text NOT NULL CHECK (post_type IN ('announcement','assignment','material','question','repost')),
  title text NOT NULL,
  content text,
  -- للواجبات
  due_date date,
  due_time time DEFAULT '23:59',
  max_points int DEFAULT 100,
  allow_resubmit boolean DEFAULT true,
  allow_comments boolean DEFAULT true,
  -- للمرفقات
  attachments jsonb DEFAULT '[]'::jsonb,
  -- للنشر
  is_pinned boolean DEFAULT false,
  is_scheduled boolean DEFAULT false,
  scheduled_at timestamptz,
  -- للمتابعة اليومية
  daily_summary jsonb DEFAULT '{}'::jsonb,
  -- إحصائيات
  views_count int DEFAULT 0,
  comments_count int DEFAULT 0,
  -- حالة
  status text DEFAULT 'published' CHECK (status IN ('draft','published','archived','scheduled')),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_classroom_posts_class ON public.classroom_posts(class_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_classroom_posts_author ON public.classroom_posts(author_id);
CREATE INDEX IF NOT EXISTS idx_classroom_posts_type ON public.classroom_posts(post_type);
CREATE INDEX IF NOT EXISTS idx_classroom_posts_due ON public.classroom_posts(due_date) WHERE due_date IS NOT NULL;

-- 2) جدول تعليقات المنشورات (مثل تعليقات Google Classroom)
CREATE TABLE IF NOT EXISTS public.classroom_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.classroom_posts(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  parent_comment_id uuid REFERENCES public.classroom_comments(id) ON DELETE CASCADE,
  content text NOT NULL,
  is_private boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_classroom_comments_post ON public.classroom_comments(post_id, created_at);
CREATE INDEX IF NOT EXISTS idx_classroom_comments_author ON public.classroom_comments(author_id);

-- 3) جدول متابعة يومية للطلاب (Daily Follow-up)
CREATE TABLE IF NOT EXISTS public.daily_followup (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL,
  followup_date date NOT NULL DEFAULT CURRENT_DATE,
  attendance_status text CHECK (attendance_status IN ('present','absent','late','excused')),
  mood text CHECK (mood IN ('excellent','good','neutral','tired','upset')),
  participation_score int CHECK (participation_score BETWEEN 1 AND 5),
  homework_done boolean DEFAULT false,
  behavior_note text,
  teacher_note text,
  parent_visible boolean DEFAULT true,
  created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE(student_id, followup_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_followup_student_date ON public.daily_followup(student_id, followup_date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_followup_class_date ON public.daily_followup(class_id, followup_date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_followup_date ON public.daily_followup(followup_date DESC);

-- 4) تحديث جدول homeworks ليتوافق مع Classroom (إضافة حقول Google Classroom)
ALTER TABLE public.homeworks ADD COLUMN IF NOT EXISTS post_id uuid REFERENCES public.classroom_posts(id) ON DELETE SET NULL;
ALTER TABLE public.homeworks ADD COLUMN IF NOT EXISTS classroom_stream_visible boolean DEFAULT true;
ALTER TABLE public.homeworks ADD COLUMN IF NOT EXISTS allow_comments boolean DEFAULT true;
ALTER TABLE public.homeworks ADD COLUMN IF NOT EXISTS max_points int DEFAULT 100;
ALTER TABLE public.homeworks ADD COLUMN IF NOT EXISTS grading_type text DEFAULT 'points' CHECK (grading_type IN ('points','letter','rubric','ungraded'));

-- 5) RLS للجداول الجديدة
ALTER TABLE public.classroom_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classroom_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_followup ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS classroom_posts_select_all ON public.classroom_posts;
CREATE POLICY classroom_posts_select_all ON public.classroom_posts FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS classroom_posts_insert_teacher_admin ON public.classroom_posts;
CREATE POLICY classroom_posts_insert_teacher_admin ON public.classroom_posts FOR INSERT TO authenticated WITH CHECK (
  EXISTS(SELECT 1 FROM public.users u WHERE u.id=auth.uid() AND (u.role IN ('teacher','admin','academic','academic_admin') OR u.is_super_admin))
);

DROP POLICY IF EXISTS classroom_posts_update_author_admin ON public.classroom_posts;
CREATE POLICY classroom_posts_update_author_admin ON public.classroom_posts FOR UPDATE TO authenticated USING (
  author_id=auth.uid() OR EXISTS(SELECT 1 FROM public.users u WHERE u.id=auth.uid() AND (u.role='admin' OR u.is_super_admin))
);

DROP POLICY IF EXISTS classroom_posts_delete_author_admin ON public.classroom_posts;
CREATE POLICY classroom_posts_delete_author_admin ON public.classroom_posts FOR DELETE TO authenticated USING (
  author_id=auth.uid() OR EXISTS(SELECT 1 FROM public.users u WHERE u.id=auth.uid() AND (u.role='admin' OR u.is_super_admin))
);

DROP POLICY IF EXISTS classroom_comments_select_all ON public.classroom_comments;
CREATE POLICY classroom_comments_select_all ON public.classroom_comments FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS classroom_comments_insert_all ON public.classroom_comments;
CREATE POLICY classroom_comments_insert_all ON public.classroom_comments FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS classroom_comments_update_own ON public.classroom_comments;
CREATE POLICY classroom_comments_update_own ON public.classroom_comments FOR UPDATE TO authenticated USING (author_id=auth.uid() OR EXISTS(SELECT 1 FROM public.users u WHERE u.id=auth.uid() AND (u.role='admin' OR u.is_super_admin)));

DROP POLICY IF EXISTS daily_followup_select_own_admin ON public.daily_followup;
CREATE POLICY daily_followup_select_own_admin ON public.daily_followup FOR SELECT TO authenticated USING (
  student_id IN (SELECT id FROM public.students WHERE user_id=auth.uid() OR parent_id=auth.uid()) OR
  EXISTS(SELECT 1 FROM public.users u WHERE u.id=auth.uid() AND (u.role IN ('teacher','admin','academic') OR u.is_super_admin))
);

DROP POLICY IF EXISTS daily_followup_insert_teacher_admin ON public.daily_followup;
CREATE POLICY daily_followup_insert_teacher_admin ON public.daily_followup FOR INSERT TO authenticated WITH CHECK (
  EXISTS(SELECT 1 FROM public.users u WHERE u.id=auth.uid() AND (u.role IN ('teacher','admin','academic') OR u.is_super_admin))
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.classroom_posts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.classroom_comments TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.daily_followup TO authenticated;

-- 6) Views للإحصائيات
CREATE OR REPLACE VIEW public.v_classroom_stream_enhanced
WITH (security_invoker=true) AS
SELECT 
  p.id,
  p.class_id,
  c.name as class_name,
  p.post_type,
  p.title,
  p.content,
  p.due_date,
  p.max_points,
  p.is_pinned,
  p.status,
  p.views_count,
  p.comments_count,
  p.created_at,
  u.name as author_name,
  u.role as author_role,
  (SELECT COUNT(*) FROM public.classroom_comments cc WHERE cc.post_id=p.id) as actual_comments_count,
  CASE 
    WHEN p.due_date IS NOT NULL AND p.due_date < CURRENT_DATE THEN 'overdue'
    WHEN p.due_date = CURRENT_DATE THEN 'due_today'
    WHEN p.due_date IS NOT NULL AND p.due_date <= CURRENT_DATE + interval '3 days' THEN 'due_soon'
    ELSE 'active'
  END as due_status
FROM public.classroom_posts p
LEFT JOIN public.classes c ON c.id=p.class_id
LEFT JOIN public.users u ON u.id=p.author_id
WHERE p.status='published'
ORDER BY p.is_pinned DESC, p.created_at DESC;

GRANT SELECT ON public.v_classroom_stream_enhanced TO authenticated;

CREATE OR REPLACE VIEW public.v_daily_followup_summary
WITH (security_invoker=true) AS
SELECT 
  df.followup_date,
  df.class_id,
  c.name as class_name,
  COUNT(*) as total_students,
  COUNT(*) FILTER (WHERE df.attendance_status='present') as present_count,
  COUNT(*) FILTER (WHERE df.attendance_status='absent') as absent_count,
  COUNT(*) FILTER (WHERE df.attendance_status='late') as late_count,
  COUNT(*) FILTER (WHERE df.homework_done=true) as homework_done_count,
  ROUND(AVG(df.participation_score),1) as avg_participation,
  COUNT(*) FILTER (WHERE df.mood='excellent') as excellent_mood_count,
  COUNT(*) FILTER (WHERE df.mood IN ('tired','upset')) as needs_attention_count
FROM public.daily_followup df
LEFT JOIN public.classes c ON c.id=df.class_id
GROUP BY df.followup_date, df.class_id, c.name
ORDER BY df.followup_date DESC;

GRANT SELECT ON public.v_daily_followup_summary TO authenticated;

-- 7) دالة إنشاء منشور مع إشعارات تلقائية
CREATE OR REPLACE FUNCTION public.create_classroom_post_with_notifications(
  p_class_id uuid,
  p_post_type text,
  p_title text,
  p_content text,
  p_due_date date DEFAULT NULL,
  p_max_points int DEFAULT 100
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_post_id uuid;
  v_student record;
BEGIN
  INSERT INTO public.classroom_posts(class_id, author_id, post_type, title, content, due_date, max_points)
  VALUES (p_class_id, auth.uid(), p_post_type, p_title, p_content, p_due_date, p_max_points)
  RETURNING id INTO v_post_id;

  -- إرسال إشعارات للطلاب في الصف
  FOR v_student IN SELECT id, user_id, parent_id FROM public.students WHERE class_id=p_class_id AND user_id IS NOT NULL LOOP
    PERFORM public.send_smart_notification(
      v_student.user_id,
      p_title,
      LEFT(p_content, 200),
      CASE p_post_type WHEN 'assignment' THEN 'homework_published' WHEN 'announcement' THEN 'announcement' ELSE 'info' END,
      CASE WHEN p_post_type='assignment' THEN 'high' ELSE 'medium' END,
      'classroom_posts',
      v_post_id,
      '/classroom.html?post=' || v_post_id::text,
      'فتح المنشور'
    );
    IF v_student.parent_id IS NOT NULL THEN
      PERFORM public.send_smart_notification(
        v_student.parent_id,
        p_title || ' - لابنك',
        LEFT(p_content, 200),
        'homework_published',
        'medium',
        'classroom_posts',
        v_post_id,
        '/classroom.html?post=' || v_post_id::text,
        'فتح المنشور'
      );
    END IF;
  END LOOP;

  RETURN v_post_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_classroom_post_with_notifications(uuid,text,text,text,date,int) TO authenticated;

SELECT 'classroom_google_classroom_enhancement_done' as status;

-- ============================================================================
-- Notifications & Importance Enhancement — معالجة فعالة وممتازة للإشعارات وأهميتها
-- الهدف: إضافة نظام أهمية متكامل + توصيل ذكي + تصعيد + تفضيلات
-- ============================================================================

-- 1) إضافة عمود الأهمية إلى school_notifications
ALTER TABLE public.school_notifications ADD COLUMN IF NOT EXISTS importance text DEFAULT 'medium' CHECK (importance IN ('critical','high','medium','low'));
ALTER TABLE public.school_notifications ADD COLUMN IF NOT EXISTS priority int DEFAULT 2 CHECK (priority BETWEEN 1 AND 4);
ALTER TABLE public.school_notifications ADD COLUMN IF NOT EXISTS delivery_methods text[] DEFAULT ARRAY['in_app'];
ALTER TABLE public.school_notifications ADD COLUMN IF NOT EXISTS expires_at timestamptz;
ALTER TABLE public.school_notifications ADD COLUMN IF NOT EXISTS action_url text;
ALTER TABLE public.school_notifications ADD COLUMN IF NOT EXISTS action_label text;
ALTER TABLE public.school_notifications ADD COLUMN IF NOT EXISTS icon text DEFAULT 'bell';
ALTER TABLE public.school_notifications ADD COLUMN IF NOT EXISTS color text DEFAULT 'blue';

COMMENT ON COLUMN public.school_notifications.importance IS 'critical=حرج (واتساب+SMS+داخلي), high=مهم (واتساب+داخلي), medium=متوسط (داخلي فقط), low=منخفض (ملخص يومي)';
COMMENT ON COLUMN public.school_notifications.priority IS '1=حرج, 2=مهم, 3=متوسط, 4=منخفض - للترتيب';

-- تحديث البيانات الموجودة حسب النوع
UPDATE public.school_notifications SET importance = CASE
  WHEN notification_type IN ('homework_not_viewed','exam_integrity','absence','overdue') THEN 'high'
  WHEN notification_type IN ('penalty','warning','danger') THEN 'critical'
  WHEN notification_type IN ('announcement','info') THEN 'medium'
  ELSE 'medium'
END WHERE importance IS NULL OR importance = 'medium';

UPDATE public.school_notifications SET priority = CASE importance
  WHEN 'critical' THEN 1
  WHEN 'high' THEN 2
  WHEN 'medium' THEN 3
  WHEN 'low' THEN 4
  ELSE 2
END;

UPDATE public.school_notifications SET delivery_methods = CASE importance
  WHEN 'critical' THEN ARRAY['in_app','whatsapp','sms']
  WHEN 'high' THEN ARRAY['in_app','whatsapp']
  WHEN 'medium' THEN ARRAY['in_app']
  WHEN 'low' THEN ARRAY['in_app']
  ELSE ARRAY['in_app']
END WHERE delivery_methods IS NULL OR delivery_methods = ARRAY['in_app'];

-- فهارس للأداء مع الأهمية
CREATE INDEX IF NOT EXISTS idx_notifications_importance ON public.school_notifications(recipient_user_id, importance, read_at, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_priority ON public.school_notifications(recipient_user_id, priority, read_at, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread_critical ON public.school_notifications(recipient_user_id, importance) WHERE read_at IS NULL AND importance IN ('critical','high');

-- 2) جدول تفضيلات الإشعارات لكل مستخدم
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- تفعيل/تعطيل حسب الأهمية
  critical_enabled boolean DEFAULT true,
  high_enabled boolean DEFAULT true,
  medium_enabled boolean DEFAULT true,
  low_enabled boolean DEFAULT false,
  -- طرق التوصيل المفضلة
  whatsapp_enabled boolean DEFAULT true,
  sms_enabled boolean DEFAULT false,
  email_enabled boolean DEFAULT false,
  in_app_enabled boolean DEFAULT true,
  -- أوقات عدم الإزعاج
  quiet_hours_start time DEFAULT '22:00',
  quiet_hours_end time DEFAULT '07:00',
  quiet_hours_enabled boolean DEFAULT false,
  -- تجميع منخفض الأهمية
  digest_low_enabled boolean DEFAULT true,
  digest_time time DEFAULT '08:00',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id)
);

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS notif_prefs_own ON public.notification_preferences;
CREATE POLICY notif_prefs_own ON public.notification_preferences FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
GRANT SELECT, INSERT, UPDATE ON public.notification_preferences TO authenticated;

-- إنشاء تفضيلات افتراضية لكل المستخدمين الحاليين
INSERT INTO public.notification_preferences (user_id)
SELECT id FROM public.users
ON CONFLICT (user_id) DO NOTHING;

-- 3) View محسن للإشعارات مع الأهمية وترتيب ذكي
CREATE OR REPLACE VIEW public.v_my_notifications_enhanced
WITH (security_invoker=true) AS
SELECT 
  n.*,
  CASE n.importance
    WHEN 'critical' THEN 1
    WHEN 'high' THEN 2
    WHEN 'medium' THEN 3
    WHEN 'low' THEN 4
    ELSE 3
  END as computed_priority,
  CASE 
    WHEN n.read_at IS NULL AND n.importance = 'critical' AND n.created_at < now() - interval '2 hours' THEN 'escalated'
    WHEN n.read_at IS NULL AND n.importance = 'high' AND n.created_at < now() - interval '6 hours' THEN 'pending_attention'
    WHEN n.read_at IS NULL THEN 'unread'
    ELSE 'read'
  END as status,
  CASE WHEN n.read_at IS NULL THEN true ELSE false END as is_unread,
  EXTRACT(EPOCH FROM (now() - n.created_at))/3600 as hours_since_created,
  u.name as created_by_name
FROM public.school_notifications n
LEFT JOIN public.users u ON u.id = n.created_by
WHERE n.recipient_user_id = auth.uid()
ORDER BY 
  CASE n.importance WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 WHEN 'low' THEN 4 ELSE 3 END,
  n.created_at DESC;

GRANT SELECT ON public.v_my_notifications_enhanced TO authenticated;

-- 4) دالة إرسال إشعار ذكي مع تحديد أهمية تلقائي حسب النوع
CREATE OR REPLACE FUNCTION public.send_smart_notification(
  p_recipient_id uuid,
  p_title text,
  p_body text,
  p_type text DEFAULT 'info',
  p_importance text DEFAULT NULL,
  p_entity_table text DEFAULT NULL,
  p_entity_id uuid DEFAULT NULL,
  p_action_url text DEFAULT NULL,
  p_action_label text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_importance text;
  v_priority int;
  v_delivery text[];
  v_icon text;
  v_color text;
  v_id uuid;
BEGIN
  -- تحديد الأهمية تلقائياً إذا لم تحدد
  IF p_importance IS NULL THEN
    v_importance := CASE p_type
      WHEN 'penalty' THEN 'critical'
      WHEN 'absence' THEN 'high'
      WHEN 'overdue' THEN 'high'
      WHEN 'exam_integrity' THEN 'critical'
      WHEN 'homework_not_viewed' THEN 'high'
      WHEN 'homework_published' THEN 'medium'
      WHEN 'announcement' THEN 'medium'
      WHEN 'thank_you' THEN 'low'
      ELSE 'medium'
    END;
  ELSE
    v_importance := p_importance;
  END IF;

  v_priority := CASE v_importance WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 WHEN 'low' THEN 4 ELSE 3 END;
  v_delivery := CASE v_importance WHEN 'critical' THEN ARRAY['in_app','whatsapp','sms'] WHEN 'high' THEN ARRAY['in_app','whatsapp'] ELSE ARRAY['in_app'] END;
  v_icon := CASE p_type WHEN 'penalty' THEN 'warning' WHEN 'thank_you' THEN 'trophy' WHEN 'absence' THEN 'calendar' WHEN 'overdue' THEN 'wallet' ELSE 'bell' END;
  v_color := CASE v_importance WHEN 'critical' THEN 'red' WHEN 'high' THEN 'orange' WHEN 'medium' THEN 'blue' WHEN 'low' THEN 'slate' ELSE 'blue' END;

  INSERT INTO public.school_notifications(
    recipient_user_id, title, body, notification_type, importance, priority, delivery_methods,
    entity_table, entity_id, action_url, action_label, icon, color, created_by
  ) VALUES (
    p_recipient_id, p_title, p_body, p_type, v_importance, v_priority, v_delivery,
    p_entity_table, p_entity_id, p_action_url, p_action_label, v_icon, v_color, auth.uid()
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_smart_notification(uuid,text,text,text,text,text,uuid,text,text) TO authenticated;

-- 5) دالة تصعيد الإشعارات الحرجة غير المقروءة
CREATE OR REPLACE FUNCTION public.escalate_unread_critical_notifications()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int := 0;
BEGIN
  -- تصعيد الإشعارات الحرجة التي لم تقرأ لأكثر من ساعتين → إرسال لولي الأمر أو الإدارة
  -- حالياً نحدث فقط حالة، التوصيل عبر واتساب يتم من التطبيق
  UPDATE public.school_notifications
  SET metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object('escalated_at', now(), 'escalation_level', 1)
  WHERE read_at IS NULL 
    AND importance = 'critical' 
    AND created_at < now() - interval '2 hours'
    AND NOT (metadata ? 'escalated_at');

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'escalated_count', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.escalate_unread_critical_notifications() TO authenticated;

-- 6) تحديث v_my_notifications القديم ليشمل الأهمية (للتوافق)
DROP VIEW IF EXISTS public.v_my_notifications;
CREATE VIEW public.v_my_notifications
WITH (security_invoker=true) AS
SELECT 
  n.*,
  (n.read_at IS NULL) as is_unread,
  u.name as created_by_name
FROM public.school_notifications n
LEFT JOIN public.users u ON u.id = n.created_by
WHERE n.recipient_user_id = auth.uid()
ORDER BY 
  CASE n.importance WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 ELSE 4 END,
  n.created_at DESC;

GRANT SELECT ON public.v_my_notifications TO authenticated;

SELECT 'notifications_importance_enhancement_done' as status;

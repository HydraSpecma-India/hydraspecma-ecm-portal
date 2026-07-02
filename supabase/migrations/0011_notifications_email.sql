-- =============================================================================
-- 0011_notifications_email.sql
-- Module 1 / Module 11: Notifications (realtime bell), notification rules,
-- per-user preferences, and email templates.
-- =============================================================================

CREATE TABLE IF NOT EXISTS email_templates (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       citext NOT NULL UNIQUE,
  name       text NOT NULL,
  subject    text NOT NULL,
  body_html  text NOT NULL,
  body_text  text,
  variables  jsonb NOT NULL DEFAULT '[]'::jsonb,               -- documented merge fields
  channel    notification_channel NOT NULL DEFAULT 'email',
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE email_templates IS 'Reusable templates for approval, reminder, escalation and assignment emails.';

CREATE TABLE IF NOT EXISTS notification_rules (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                 citext NOT NULL UNIQUE,
  event_type           text NOT NULL,                          -- e.g. 'ecm.transition','task.assigned','approval.pending'
  description          text,
  channel              notification_channel NOT NULL DEFAULT 'in_app',
  template_id          uuid REFERENCES email_templates(id) ON DELETE SET NULL,
  recipient_expression text NOT NULL DEFAULT 'owner',          -- owner|requestor|assignee|role:CODE|mentions|manager
  is_active            boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE notification_rules IS 'Declarative mapping of events to channels, templates and recipients (Admin-editable).';
CREATE INDEX IF NOT EXISTS idx_notif_rules_event ON notification_rules (event_type) WHERE is_active;

CREATE TABLE IF NOT EXISTS notifications (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  type         text NOT NULL,
  title        text NOT NULL,
  body         text,
  entity_type  entity_type,
  entity_id    uuid,
  priority     priority_level NOT NULL DEFAULT 'medium',
  channel      notification_channel NOT NULL DEFAULT 'in_app',
  action_url   text,
  meta         jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_read      boolean NOT NULL DEFAULT false,
  read_at      timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE notifications IS 'In-app / multi-channel notifications; realtime via Supabase (Module 11).';
CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON notifications (recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread    ON notifications (recipient_id) WHERE NOT is_read;

CREATE TABLE IF NOT EXISTS notification_preferences (
  user_id    uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  channel    notification_channel NOT NULL,
  enabled    boolean NOT NULL DEFAULT true,
  PRIMARY KEY (user_id, event_type, channel)
);

CREATE TRIGGER trg_email_templates_updated BEFORE UPDATE ON email_templates    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_notif_rules_updated     BEFORE UPDATE ON notification_rules FOR EACH ROW EXECUTE FUNCTION set_updated_at();

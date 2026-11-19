-- WellBridge AI migration 003: private administrative verification workflow
-- VALIDATION ONLY. Apply only to the disposable WellBridge pathway-validation Neon DB.
-- Do not connect this schema to Azure App Service or a public API.
-- No patient, symptom, check-in, conversation, or crisis-event data is introduced.

BEGIN;

CREATE TABLE admin_identities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  identity_issuer text NOT NULL,
  identity_subject text NOT NULL,
  email_address text,
  display_name text,
  account_status text NOT NULL DEFAULT 'invited'
    CHECK (account_status IN ('invited','active','suspended','revoked')),
  last_sign_in_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (identity_issuer, identity_subject)
);

COMMENT ON TABLE admin_identities IS
  'Internal administrator mapping for validated external identities. Never use email as the identity key; store no passwords or bearer tokens.';

CREATE TABLE admin_role_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_identity_id uuid NOT NULL REFERENCES admin_identities(id),
  role_name text NOT NULL CHECK (role_name IN
    ('platform_owner','pathway_administrator','verifier','approver','auditor')),
  granted_by_admin_id uuid REFERENCES admin_identities(id),
  granted_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  revoked_by_admin_id uuid REFERENCES admin_identities(id),
  revoked_at timestamptz,
  grant_reason text NOT NULL,
  CHECK (expires_at IS NULL OR expires_at > granted_at),
  CHECK ((revoked_at IS NULL AND revoked_by_admin_id IS NULL)
      OR (revoked_at IS NOT NULL AND revoked_by_admin_id IS NOT NULL))
);

CREATE UNIQUE INDEX uq_admin_active_role
  ON admin_role_assignments(admin_identity_id, role_name)
  WHERE revoked_at IS NULL;

CREATE INDEX idx_admin_roles_validity
  ON admin_role_assignments(admin_identity_id, expires_at)
  WHERE revoked_at IS NULL;

CREATE TABLE verification_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL CHECK (entity_type IN
    ('organisation','facility','service','facility_service','service_contact_channel',
     'referral_relationship','professional_credential','administrative_area_authority')),
  entity_id uuid NOT NULL,
  claim_to_verify text NOT NULL,
  review_status text NOT NULL DEFAULT 'queued' CHECK (review_status IN
    ('queued','assigned','in_progress','submitted','changes_requested',
     'approved','rejected','cancelled')),
  priority text NOT NULL DEFAULT 'normal'
    CHECK (priority IN ('low','normal','high','critical')),
  assigned_to_admin_id uuid REFERENCES admin_identities(id),
  created_by_admin_id uuid NOT NULL REFERENCES admin_identities(id),
  due_at timestamptz,
  submitted_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (length(trim(claim_to_verify)) > 0),
  CHECK (closed_at IS NULL OR review_status IN ('approved','rejected','cancelled'))
);

CREATE INDEX idx_verification_reviews_queue
  ON verification_reviews(review_status, priority, due_at);
CREATE INDEX idx_verification_reviews_assignee
  ON verification_reviews(assigned_to_admin_id, review_status);

CREATE TABLE verification_review_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id uuid NOT NULL REFERENCES verification_reviews(id),
  evidence_id uuid NOT NULL REFERENCES evidence_sources(id),
  relevance_note text NOT NULL,
  linked_by_admin_id uuid NOT NULL REFERENCES admin_identities(id),
  linked_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(review_id, evidence_id)
);

CREATE TABLE evidence_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id uuid NOT NULL REFERENCES verification_reviews(id),
  evidence_id uuid REFERENCES evidence_sources(id),
  storage_provider text NOT NULL CHECK (storage_provider IN ('private_object_storage')),
  storage_object_key text NOT NULL UNIQUE,
  original_filename text NOT NULL,
  media_type text NOT NULL CHECK (media_type IN
    ('application/pdf','image/jpeg','image/png','text/plain')),
  byte_size bigint NOT NULL CHECK (byte_size > 0 AND byte_size <= 20971520),
  sha256_hex char(64) NOT NULL CHECK (sha256_hex ~ '^[0-9a-fA-F]{64}$'),
  malware_scan_status text NOT NULL DEFAULT 'pending'
    CHECK (malware_scan_status IN ('pending','clean','quarantined','failed')),
  uploaded_by_admin_id uuid NOT NULL REFERENCES admin_identities(id),
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  retention_until timestamptz,
  deleted_at timestamptz,
  CHECK (deleted_at IS NULL OR deleted_at >= uploaded_at)
);

CREATE INDEX idx_evidence_attachments_review
  ON evidence_attachments(review_id, uploaded_at);

CREATE TABLE verification_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id uuid NOT NULL REFERENCES verification_reviews(id),
  decision text NOT NULL CHECK (decision IN ('approved','rejected','changes_requested')),
  rationale text NOT NULL,
  decided_by_admin_id uuid NOT NULL REFERENCES admin_identities(id),
  decided_at timestamptz NOT NULL DEFAULT now(),
  CHECK (length(trim(rationale)) > 0)
);

CREATE INDEX idx_verification_decisions_review
  ON verification_decisions(review_id, decided_at DESC);

CREATE TABLE audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  actor_admin_id uuid REFERENCES admin_identities(id) ON DELETE SET NULL,
  actor_source text NOT NULL DEFAULT 'application',
  request_id text,
  action text NOT NULL,
  target_table text NOT NULL,
  target_id text,
  changed_fields text[] NOT NULL DEFAULT '{}'
);

COMMENT ON TABLE audit_log IS
  'Append-only metadata audit trail. Deliberately records changed field names, not before/after field values or uploaded evidence contents.';

CREATE INDEX idx_audit_log_time ON audit_log(occurred_at DESC);
CREATE INDEX idx_audit_log_actor_time ON audit_log(actor_admin_id, occurred_at DESC);
CREATE INDEX idx_audit_log_target ON audit_log(target_table, target_id, occurred_at DESC);

-- A reviewer cannot approve their own review. The approver must hold an active
-- approver or platform_owner role at decision time.
CREATE OR REPLACE FUNCTION enforce_verification_decision_rules()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_assignee uuid;
  v_review_status text;
  v_has_approval_role boolean;
BEGIN
  SELECT assigned_to_admin_id, review_status
    INTO v_assignee, v_review_status
  FROM verification_reviews
  WHERE id = NEW.review_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Verification review does not exist';
  END IF;

  IF v_assignee IS NOT NULL AND v_assignee = NEW.decided_by_admin_id THEN
    RAISE EXCEPTION 'A reviewer cannot decide their own verification review';
  END IF;

  IF v_review_status NOT IN ('submitted','changes_requested') THEN
    RAISE EXCEPTION 'A decision can only be recorded for a submitted review';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM admin_role_assignments r
    JOIN admin_identities a ON a.id = r.admin_identity_id
    WHERE r.admin_identity_id = NEW.decided_by_admin_id
      AND r.role_name IN ('approver','platform_owner')
      AND r.revoked_at IS NULL
      AND (r.expires_at IS NULL OR r.expires_at > now())
      AND a.account_status = 'active'
  ) INTO v_has_approval_role;

  IF NOT v_has_approval_role THEN
    RAISE EXCEPTION 'Approver must have an active approver or platform_owner role';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_verification_decision_rules
BEFORE INSERT ON verification_decisions
FOR EACH ROW EXECUTE FUNCTION enforce_verification_decision_rules();

-- A review cannot be submitted until it has an assignee and at least one
-- linked evidence source. The evidence source itself must already exist.
CREATE OR REPLACE FUNCTION enforce_review_submission_rules()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.review_status = 'submitted'
     AND OLD.review_status IS DISTINCT FROM 'submitted' THEN
    IF NEW.assigned_to_admin_id IS NULL THEN
      RAISE EXCEPTION 'A review must be assigned before submission';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM verification_review_evidence e
      WHERE e.review_id = NEW.id
    ) THEN
      RAISE EXCEPTION 'A review must have at least one linked evidence source before submission';
    END IF;
    IF NEW.submitted_at IS NULL THEN
      NEW.submitted_at := now();
    END IF;
  END IF;

  IF NEW.review_status IN ('approved','rejected','cancelled')
     AND NEW.closed_at IS NULL THEN
    NEW.closed_at := now();
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_review_submission_rules
BEFORE UPDATE OF review_status ON verification_reviews
FOR EACH ROW EXECUTE FUNCTION enforce_review_submission_rules();

-- Generic audit trigger: records actor context, target, operation and changed
-- column names only. The trusted application server sets app.actor_admin_id
-- and app.request_id transaction-locally after validating the Entra identity.
CREATE OR REPLACE FUNCTION write_admin_audit_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old jsonb;
  v_new jsonb;
  v_target_id text;
  v_changed_fields text[];
  v_actor_text text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_new := to_jsonb(NEW);
    v_target_id := v_new ->> 'id';
    SELECT COALESCE(array_agg(k ORDER BY k), '{}') INTO v_changed_fields
    FROM jsonb_object_keys(v_new) AS x(k);
  ELSIF TG_OP = 'UPDATE' THEN
    v_old := to_jsonb(OLD);
    v_new := to_jsonb(NEW);
    v_target_id := v_new ->> 'id';
    SELECT COALESCE(array_agg(n.k ORDER BY n.k), '{}') INTO v_changed_fields
    FROM jsonb_object_keys(v_new) AS n(k)
    WHERE v_old -> n.k IS DISTINCT FROM v_new -> n.k;
  ELSE
    v_old := to_jsonb(OLD);
    v_target_id := v_old ->> 'id';
    SELECT COALESCE(array_agg(k ORDER BY k), '{}') INTO v_changed_fields
    FROM jsonb_object_keys(v_old) AS x(k);
  END IF;

  v_actor_text := nullif(current_setting('app.actor_admin_id', true), '');

  INSERT INTO audit_log (
    actor_admin_id, actor_source, request_id, action,
    target_table, target_id, changed_fields
  ) VALUES (
    CASE WHEN v_actor_text IS NULL THEN NULL ELSE v_actor_text::uuid END,
    COALESCE(nullif(current_setting('app.actor_source', true), ''), 'application'),
    nullif(current_setting('app.request_id', true), ''),
    TG_OP, TG_TABLE_NAME, v_target_id, v_changed_fields
  );

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION write_admin_audit_event() FROM PUBLIC;

CREATE OR REPLACE FUNCTION prevent_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'audit_log is append-only; UPDATE and DELETE are prohibited';
END;
$$;

CREATE TRIGGER trg_audit_log_immutable
BEFORE UPDATE OR DELETE ON audit_log
FOR EACH ROW EXECUTE FUNCTION prevent_audit_mutation();

-- Audit administrator, verification, evidence and pathway record changes.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'admin_identities',
    'admin_role_assignments',
    'verification_reviews',
    'verification_review_evidence',
    'evidence_attachments',
    'verification_decisions',
    'organisations',
    'facilities',
    'services',
    'facility_services',
    'service_contact_channels',
    'referral_relationships',
    'professional_credentials',
    'administrative_area_authorities',
    'evidence_sources',
    'verification_events'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION write_admin_audit_event()',
      'trg_audit_' || t, t
    );
  END LOOP;
END;
$$;

-- Default deny for non-owner database roles. No application policies or grants
-- are created in this migration. Access is intentionally unavailable until a
-- separately reviewed server-side authorisation/RLS policy migration is applied.
ALTER TABLE admin_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_role_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE verification_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE verification_review_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE evidence_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE verification_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Also protect the pathway records that the administrative interface will edit.
ALTER TABLE organisations ENABLE ROW LEVEL SECURITY;
ALTER TABLE facilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE services ENABLE ROW LEVEL SECURITY;
ALTER TABLE facility_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_contact_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE referral_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE professional_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE administrative_area_authorities ENABLE ROW LEVEL SECURITY;
ALTER TABLE evidence_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE verification_events ENABLE ROW LEVEL SECURITY;

COMMIT;

-- WellBridge AI migration 005: signed actor context and stricter review isolation
-- VALIDATION ONLY. Apply only after migrations 001-004 to a disposable PostgreSQL database.
-- No production, Neon, or Azure deployment is authorised by this file.
--
-- Provisioning prerequisite: an authorised DBA must insert a random 32-byte-or-longer
-- HMAC key into wellbridge_private.actor_assertion_keys and configure the identical
-- hex key in the trusted server's WELLBRIDGE_ACTOR_ASSERTION_SECRET_HEX secret.
-- Never put the key in source control, SQL migration text, browser code, or logs.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS wellbridge_private;
REVOKE ALL ON SCHEMA wellbridge_private FROM PUBLIC, wellbridge_app;

CREATE TABLE IF NOT EXISTS wellbridge_private.actor_assertion_keys (
  key_id text PRIMARY KEY CHECK (key_id ~ '^[a-zA-Z0-9_-]{1,40}$'),
  secret bytea NOT NULL CHECK (octet_length(secret) >= 32),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  retired_at timestamptz,
  CHECK ((active AND retired_at IS NULL) OR (NOT active))
);

CREATE TABLE IF NOT EXISTS wellbridge_private.actor_assertion_nonces (
  nonce text PRIMARY KEY CHECK (nonce ~ '^[a-f0-9-]{36}$'),
  actor_admin_id uuid NOT NULL REFERENCES public.admin_identities(id),
  transaction_id bigint NOT NULL,
  issued_at timestamptz NOT NULL,
  first_seen_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
CREATE INDEX IF NOT EXISTS idx_actor_assertion_nonces_seen
  ON wellbridge_private.actor_assertion_nonces(first_seen_at);

REVOKE ALL ON ALL TABLES IN SCHEMA wellbridge_private FROM PUBLIC, wellbridge_app;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA wellbridge_private FROM PUBLIC, wellbridge_app;


-- Resolve only the immutable Entra issuer/subject pair. No email or other PII
-- is returned; application role membership is checked after signed context exists.
CREATE OR REPLACE FUNCTION wellbridge_resolve_admin_identity(
  p_identity_issuer text,
  p_identity_subject text
)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $resolve_identity$
  SELECT id FROM public.admin_identities
  WHERE identity_issuer = p_identity_issuer
    AND identity_subject = p_identity_subject
    AND account_status = 'active'
  LIMIT 1;
$resolve_identity$;
REVOKE ALL ON FUNCTION wellbridge_resolve_admin_identity(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION wellbridge_resolve_admin_identity(text,text) TO wellbridge_app;

-- Verify the exact canonical payload:
-- key_id|actor_uuid|issued_at_epoch_seconds|nonce_uuid
-- The nonce is accepted repeatedly only inside the same PostgreSQL transaction.
CREATE OR REPLACE FUNCTION wellbridge_private.verify_actor_assertion()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, wellbridge_private, pg_temp
AS $actor_verify$
DECLARE
  v_actor uuid;
  v_key_id text;
  v_issued_epoch bigint;
  v_nonce text;
  v_signature text;
  v_secret bytea;
  v_payload text;
  v_expected text;
  v_existing_tx bigint;
BEGIN
  BEGIN
    v_actor := nullif(current_setting('app.actor_admin_id', true), '')::uuid;
    v_key_id := nullif(current_setting('app.actor_key_id', true), '');
    v_issued_epoch := nullif(current_setting('app.actor_issued_at', true), '')::bigint;
    v_nonce := nullif(current_setting('app.actor_nonce', true), '');
    v_signature := lower(nullif(current_setting('app.actor_signature', true), ''));
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN NULL;
  END;

  IF v_actor IS NULL OR v_key_id IS NULL OR v_issued_epoch IS NULL
     OR v_nonce IS NULL OR v_signature IS NULL
     OR v_nonce !~ '^[a-f0-9-]{36}$'
     OR v_signature !~ '^[a-f0-9]{64}$'
     OR abs(extract(epoch FROM statement_timestamp())::bigint - v_issued_epoch) > 60 THEN
    RETURN NULL;
  END IF;

  SELECT secret INTO v_secret
  FROM wellbridge_private.actor_assertion_keys
  WHERE key_id = v_key_id AND active = true AND retired_at IS NULL;

  IF v_secret IS NULL THEN RETURN NULL; END IF;

  v_payload := v_key_id || '|' || v_actor::text || '|' ||
               v_issued_epoch::text || '|' || v_nonce;
  v_expected := encode(public.hmac(convert_to(v_payload, 'UTF8'), v_secret, 'sha256'), 'hex');
  IF v_expected <> v_signature THEN RETURN NULL; END IF;

  INSERT INTO wellbridge_private.actor_assertion_nonces
    (nonce, actor_admin_id, transaction_id, issued_at)
  VALUES (v_nonce, v_actor, txid_current(), to_timestamp(v_issued_epoch))
  ON CONFLICT (nonce) DO NOTHING;

  SELECT transaction_id INTO v_existing_tx
  FROM wellbridge_private.actor_assertion_nonces
  WHERE nonce = v_nonce AND actor_admin_id = v_actor;

  IF v_existing_tx IS DISTINCT FROM txid_current() THEN RETURN NULL; END IF;

  RETURN v_actor;
END;
$actor_verify$;

REVOKE ALL ON FUNCTION wellbridge_private.verify_actor_assertion() FROM PUBLIC, wellbridge_app;

CREATE OR REPLACE FUNCTION wellbridge_set_actor_context(
  p_actor_admin_id uuid,
  p_key_id text,
  p_issued_at_epoch bigint,
  p_nonce text,
  p_signature_hex text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, wellbridge_private, pg_temp
AS $actor_set$
BEGIN
  PERFORM set_config('app.actor_admin_id', p_actor_admin_id::text, true);
  PERFORM set_config('app.actor_key_id', p_key_id, true);
  PERFORM set_config('app.actor_issued_at', p_issued_at_epoch::text, true);
  PERFORM set_config('app.actor_nonce', p_nonce, true);
  PERFORM set_config('app.actor_signature', lower(p_signature_hex), true);

  IF wellbridge_private.verify_actor_assertion() IS NULL THEN
    RAISE EXCEPTION 'Invalid, expired, replayed or unauthorised administrator assertion'
      USING ERRCODE = '28000';
  END IF;
END;
$actor_set$;
REVOKE ALL ON FUNCTION wellbridge_set_actor_context(uuid,text,bigint,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION wellbridge_set_actor_context(uuid,text,bigint,text,text) TO wellbridge_app;

CREATE OR REPLACE FUNCTION wellbridge_current_admin_id()
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, wellbridge_private, pg_temp
AS $current_admin$
DECLARE v_actor uuid;
BEGIN
  v_actor := wellbridge_private.verify_actor_assertion();
  IF v_actor IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.admin_identities a
    WHERE a.id = v_actor AND a.account_status = 'active'
  ) THEN
    RETURN NULL;
  END IF;
  RETURN v_actor;
END;
$current_admin$;
REVOKE ALL ON FUNCTION wellbridge_current_admin_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION wellbridge_current_admin_id() TO wellbridge_app;

-- Rebuild role helpers so every role decision requires a valid signed assertion.
CREATE OR REPLACE FUNCTION wellbridge_has_role(p_role text)
RETURNS boolean
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, wellbridge_private, pg_temp
AS $has_role$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_role_assignments r
    JOIN public.admin_identities a ON a.id = r.admin_identity_id
    WHERE r.admin_identity_id = public.wellbridge_current_admin_id()
      AND r.role_name = p_role AND r.revoked_at IS NULL
      AND (r.expires_at IS NULL OR r.expires_at > statement_timestamp())
      AND a.account_status = 'active'
  );
$has_role$;

CREATE OR REPLACE FUNCTION wellbridge_has_any_role(VARIADIC p_roles text[])
RETURNS boolean
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, wellbridge_private, pg_temp
AS $has_any_role$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_role_assignments r
    JOIN public.admin_identities a ON a.id = r.admin_identity_id
    WHERE r.admin_identity_id = public.wellbridge_current_admin_id()
      AND r.role_name = ANY(p_roles) AND r.revoked_at IS NULL
      AND (r.expires_at IS NULL OR r.expires_at > statement_timestamp())
      AND a.account_status = 'active'
  );
$has_any_role$;
REVOKE ALL ON FUNCTION wellbridge_has_role(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION wellbridge_has_any_role(text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION wellbridge_has_role(text) TO wellbridge_app;
GRANT EXECUTE ON FUNCTION wellbridge_has_any_role(text[]) TO wellbridge_app;


-- Strengthen role governance: never grant roles to inactive identities and
-- prevent concurrent removal of the final active platform owner.
CREATE OR REPLACE FUNCTION wellbridge_grant_admin_role(
  p_admin_identity_id uuid,
  p_role_name text,
  p_grant_reason text,
  p_expires_at timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $grant_hardened$
DECLARE v_actor uuid; v_assignment_id uuid; v_target_status text;
BEGIN
  v_actor := public.wellbridge_current_admin_id();
  IF v_actor IS NULL OR NOT public.wellbridge_has_role('platform_owner') THEN
    RAISE EXCEPTION 'Only an active platform owner may grant administrator roles';
  END IF;
  IF p_role_name NOT IN ('platform_owner','pathway_administrator','pathway_verifier','pathway_approver','audit_reviewer')
     OR nullif(btrim(p_grant_reason), '') IS NULL
     OR (p_expires_at IS NOT NULL AND p_expires_at <= statement_timestamp()) THEN
    RAISE EXCEPTION 'Invalid role, grant reason or expiry';
  END IF;
  IF p_role_name = 'platform_owner' THEN
    PERFORM pg_advisory_xact_lock(hashtext('wellbridge:platform_owner_governance'));
  END IF;
  SELECT account_status INTO v_target_status
  FROM public.admin_identities WHERE id = p_admin_identity_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Target administrator identity does not exist'; END IF;
  IF v_target_status <> 'active' THEN
    RAISE EXCEPTION 'Roles cannot be granted to an inactive administrator identity';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.admin_role_assignments
    WHERE admin_identity_id = p_admin_identity_id AND role_name = p_role_name
      AND revoked_at IS NULL
      AND (expires_at IS NULL OR expires_at > statement_timestamp())
  ) THEN
    RAISE EXCEPTION 'An active assignment for this role already exists';
  END IF;
  INSERT INTO public.admin_role_assignments
    (admin_identity_id, role_name, granted_by_admin_id, expires_at, grant_reason)
  VALUES (p_admin_identity_id, p_role_name, v_actor, p_expires_at, btrim(p_grant_reason))
  RETURNING id INTO v_assignment_id;
  RETURN v_assignment_id;
END;
$grant_hardened$;

CREATE OR REPLACE FUNCTION wellbridge_revoke_admin_role(
  p_assignment_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $revoke_hardened$
DECLARE
  v_actor uuid;
  v_target uuid;
  v_role text;
  v_active_owners bigint;
BEGIN
  v_actor := public.wellbridge_current_admin_id();
  IF v_actor IS NULL OR NOT public.wellbridge_has_role('platform_owner') THEN
    RAISE EXCEPTION 'Only an active platform owner may revoke administrator roles';
  END IF;
  IF nullif(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A revocation reason is required';
  END IF;

  SELECT admin_identity_id, role_name INTO v_target, v_role
  FROM public.admin_role_assignments
  WHERE id = p_assignment_id AND revoked_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active role assignment not found'; END IF;

  IF v_role = 'platform_owner' THEN
    PERFORM pg_advisory_xact_lock(hashtext('wellbridge:platform_owner_governance'));
    SELECT count(*) INTO v_active_owners
    FROM public.admin_role_assignments r
    JOIN public.admin_identities a ON a.id = r.admin_identity_id
    WHERE r.role_name = 'platform_owner'
      AND r.revoked_at IS NULL
      AND (r.expires_at IS NULL OR r.expires_at > statement_timestamp())
      AND a.account_status = 'active'
      AND r.admin_identity_id <> v_target;
    IF v_active_owners = 0 THEN
      RAISE EXCEPTION 'Cannot revoke the final active platform owner';
    END IF;
  END IF;

  UPDATE public.admin_role_assignments
  SET revoked_by_admin_id = v_actor, revoked_at = statement_timestamp(),
      grant_reason = grant_reason || E'\nRevocation: ' || btrim(p_reason)
  WHERE id = p_assignment_id AND revoked_at IS NULL;
END;
$revoke_hardened$;

-- Review visibility: verifier sees assigned work only; pathway administrators,
-- approvers, auditors and platform owners retain their distinct operational scopes.
CREATE OR REPLACE FUNCTION wellbridge_can_read_review(p_review_id uuid)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, wellbridge_private, pg_temp
AS $review_access$
DECLARE v_actor uuid; v_assignee uuid; v_status text;
BEGIN
  v_actor := public.wellbridge_current_admin_id();
  IF v_actor IS NULL THEN RETURN false; END IF;

  SELECT assigned_to_admin_id, review_status
    INTO v_assignee, v_status
  FROM public.verification_reviews WHERE id = p_review_id;

  IF NOT FOUND THEN RETURN false; END IF;
  IF public.wellbridge_has_role('platform_owner')
     OR public.wellbridge_has_role('pathway_administrator')
     OR public.wellbridge_has_role('audit_reviewer') THEN RETURN true; END IF;
  IF public.wellbridge_has_role('pathway_verifier') THEN
    RETURN v_assignee = v_actor;
  END IF;
  IF public.wellbridge_has_role('pathway_approver') THEN
    RETURN v_status IN ('submitted','changes_requested','approved','rejected');
  END IF;
  RETURN false;
END;
$review_access$;
REVOKE ALL ON FUNCTION wellbridge_can_read_review(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION wellbridge_can_read_review(uuid) TO wellbridge_app;

DROP POLICY IF EXISTS reviews_read_authorised ON public.verification_reviews;
CREATE POLICY reviews_read_authorised ON public.verification_reviews
  FOR SELECT TO wellbridge_app
  USING (public.wellbridge_can_read_review(id));

DROP POLICY IF EXISTS review_evidence_read_authorised ON public.verification_review_evidence;
CREATE POLICY review_evidence_read_authorised ON public.verification_review_evidence
  FOR SELECT TO wellbridge_app
  USING (public.wellbridge_can_read_review(review_id));

DROP POLICY IF EXISTS attachments_read_authorised ON public.evidence_attachments;
CREATE POLICY attachments_read_authorised ON public.evidence_attachments
  FOR SELECT TO wellbridge_app
  USING (public.wellbridge_can_read_review(review_id));

-- Verifier updates are constrained to their currently assigned review; an
-- administrator may manage assignments. Existing trigger guards still enforce
-- workflow transitions and independent decision creation.
DROP POLICY IF EXISTS reviews_update_administrator_or_assignee ON public.verification_reviews;
CREATE POLICY reviews_update_administrator_or_assignee ON public.verification_reviews
  FOR UPDATE TO wellbridge_app
  USING (
    public.wellbridge_has_any_role('platform_owner','pathway_administrator')
    OR (assigned_to_admin_id = public.wellbridge_current_admin_id()
        AND public.wellbridge_has_role('pathway_verifier'))
  )
  WITH CHECK (
    public.wellbridge_has_any_role('platform_owner','pathway_administrator')
    OR (assigned_to_admin_id = public.wellbridge_current_admin_id()
        AND public.wellbridge_has_role('pathway_verifier'))
  );



DROP POLICY IF EXISTS decisions_read_authorised ON public.verification_decisions;
CREATE POLICY decisions_read_authorised ON public.verification_decisions
  FOR SELECT TO wellbridge_app
  USING (public.wellbridge_can_read_review(review_id));

-- Pathway administrators need a minimal directory of eligible verifier IDs
-- for assignment. Do not expose email addresses through this lookup.
CREATE OR REPLACE FUNCTION wellbridge_list_verifier_admins()
RETURNS TABLE(admin_id uuid, display_name text)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, wellbridge_private, pg_temp
AS $verifier_directory$
BEGIN
  IF NOT public.wellbridge_has_any_role('platform_owner','pathway_administrator') THEN
    RAISE EXCEPTION 'Pathway administrator permission is required';
  END IF;
  RETURN QUERY
    SELECT a.id, a.display_name
    FROM public.admin_identities a
    WHERE a.account_status = 'active'
      AND EXISTS (
        SELECT 1 FROM public.admin_role_assignments r
        WHERE r.admin_identity_id = a.id
          AND r.role_name = 'pathway_verifier'
          AND r.revoked_at IS NULL
          AND (r.expires_at IS NULL OR r.expires_at > statement_timestamp())
      )
    ORDER BY a.display_name NULLS LAST, a.id;
END;
$verifier_directory$;
REVOKE ALL ON FUNCTION wellbridge_list_verifier_admins() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION wellbridge_list_verifier_admins() TO wellbridge_app;

-- Evidence rows inherit the same assignment-aware visibility as their review.
DROP POLICY IF EXISTS review_evidence_insert_authorised ON public.verification_review_evidence;
CREATE POLICY review_evidence_insert_authorised ON public.verification_review_evidence
  FOR INSERT TO wellbridge_app
  WITH CHECK (
    linked_by_admin_id = public.wellbridge_current_admin_id()
    AND public.wellbridge_can_read_review(review_id)
    AND public.wellbridge_has_any_role('platform_owner','pathway_administrator','pathway_verifier')
  );
DROP POLICY IF EXISTS attachments_insert_authorised ON public.evidence_attachments;
CREATE POLICY attachments_insert_authorised ON public.evidence_attachments
  FOR INSERT TO wellbridge_app
  WITH CHECK (
    uploaded_by_admin_id = public.wellbridge_current_admin_id()
    AND public.wellbridge_can_read_review(review_id)
    AND public.wellbridge_has_any_role('platform_owner','pathway_administrator','pathway_verifier')
  );

-- Audit attribution is derived from a verified assertion, never a raw GUC.
CREATE OR REPLACE FUNCTION write_admin_audit_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, wellbridge_private, pg_temp
AS $audit_verified$
DECLARE
  v_old jsonb;
  v_new jsonb;
  v_target_id text;
  v_changed_fields text[];
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

  INSERT INTO public.audit_log (
    actor_admin_id, actor_source, request_id, action,
    target_table, target_id, changed_fields
  ) VALUES (
    public.wellbridge_current_admin_id(),
    COALESCE(nullif(current_setting('app.actor_source', true), ''), 'application'),
    nullif(current_setting('app.request_id', true), ''),
    TG_OP, TG_TABLE_NAME, v_target_id, v_changed_fields
  );

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$audit_verified$;

-- App role must not own protected objects or be able to assume elevated roles.
DO $role_hardening$
DECLARE v_role record;
BEGIN
  SELECT r.rolsuper, r.rolbypassrls, r.rolcreatedb, r.rolcreaterole,
         r.rolreplication, r.rolinherit, r.rolcanlogin
  INTO v_role FROM pg_catalog.pg_roles r WHERE r.rolname = 'wellbridge_app';
  IF NOT FOUND THEN RAISE EXCEPTION 'wellbridge_app role is missing'; END IF;
  IF v_role.rolsuper OR v_role.rolbypassrls OR v_role.rolcreatedb
     OR v_role.rolcreaterole OR v_role.rolreplication OR v_role.rolcanlogin THEN
    RAISE EXCEPTION 'wellbridge_app has prohibited elevated role attributes';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_roles r ON r.oid = c.relowner
    WHERE r.rolname = 'wellbridge_app'
      AND c.relnamespace IN ('public'::regnamespace, 'wellbridge_private'::regnamespace)
  ) THEN
    RAISE EXCEPTION 'wellbridge_app must not own protected tables or sequences';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_namespace n
    JOIN pg_catalog.pg_roles r ON r.oid = n.nspowner
    WHERE r.rolname = 'wellbridge_app'
      AND n.nspname IN ('public','wellbridge_private')
  ) THEN
    RAISE EXCEPTION 'wellbridge_app must not own protected schemas';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE r.rolname = 'wellbridge_app'
      AND n.nspname IN ('public','wellbridge_private')
  ) THEN
    RAISE EXCEPTION 'wellbridge_app must not own protected functions';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles granted_role ON granted_role.oid = m.roleid
    JOIN pg_catalog.pg_roles member_role ON member_role.oid = m.member
    WHERE member_role.rolname = 'wellbridge_app'
  ) THEN
    RAISE EXCEPTION 'wellbridge_app must not be a member of another database role';
  END IF;
END;
$role_hardening$;

COMMENT ON FUNCTION wellbridge_set_actor_context(uuid,text,bigint,text,text) IS
  'Sets transaction-local actor context only after validating a signed HMAC assertion. Requires server-side secret and a transaction-scoped nonce.';

COMMIT;

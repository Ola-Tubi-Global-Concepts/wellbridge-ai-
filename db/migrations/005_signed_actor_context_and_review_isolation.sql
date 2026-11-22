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
STABLE
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
STABLE
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
STABLE
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

-- Review visibility: verifier sees assigned work only; pathway administrators,
-- approvers, auditors and platform owners retain their distinct operational scopes.
CREATE OR REPLACE FUNCTION wellbridge_can_read_review(p_review_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
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

-- App role must not own protected objects or be able to assume elevated roles.
DO $role_hardening$
DECLARE v_role record;
BEGIN
  SELECT r.rolsuper, r.rolbypassrls, r.rolcreatedb, r.rolcreaterole,
         r.rolreplication, r.rolinherit
  INTO v_role FROM pg_catalog.pg_roles r WHERE r.rolname = 'wellbridge_app';
  IF NOT FOUND THEN RAISE EXCEPTION 'wellbridge_app role is missing'; END IF;
  IF v_role.rolsuper OR v_role.rolbypassrls OR v_role.rolcreatedb
     OR v_role.rolcreaterole OR v_role.rolreplication THEN
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

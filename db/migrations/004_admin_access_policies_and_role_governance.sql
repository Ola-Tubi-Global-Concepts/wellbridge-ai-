-- WellBridge AI migration 004: least-privilege administrator access and role governance
-- VALIDATION ONLY. Apply only after migrations 001-003 to the disposable
-- wellbridge-pathway-validation database. Never apply to production/Azure.
-- Requires a pre-created, non-owner, non-superuser PostgreSQL role: wellbridge_app.
-- The trusted server must set app.actor_admin_id transaction-locally only after
-- validating Entra issuer, audience, signature, tenant, expiry and subject.
-- This GUC is trusted-server context, NOT cryptographic proof against a leaked
-- database credential or arbitrary SQL execution. Never expose SQL/DB credentials.

BEGIN;

DO $$
DECLARE r record;
BEGIN
  SELECT rolname, rolsuper, rolbypassrls, rolinherit INTO r
  FROM pg_roles WHERE rolname = 'wellbridge_app';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Create the dedicated wellbridge_app database role before migration 004';
  END IF;
  IF r.rolsuper OR r.rolbypassrls THEN
    RAISE EXCEPTION 'wellbridge_app must not be SUPERUSER or BYPASSRLS';
  END IF;
END;
$$;

-- Expired assignments are historical, not active. The grant function serialises
-- grants on the identity row and rejects duplicate currently-valid assignments.
DROP INDEX IF EXISTS uq_admin_active_role;
CREATE INDEX IF NOT EXISTS idx_admin_role_assignment_lookup
  ON admin_role_assignments(admin_identity_id, role_name, granted_at DESC);

CREATE OR REPLACE FUNCTION wellbridge_current_admin_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE v_id uuid;
BEGIN
  BEGIN
    v_id := nullif(current_setting('app.actor_admin_id', true), '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN NULL;
  END;
  IF v_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.admin_identities a
    WHERE a.id = v_id AND a.account_status = 'active'
  ) THEN
    RETURN NULL;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION wellbridge_has_role(p_role text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_role_assignments r
    JOIN public.admin_identities a ON a.id = r.admin_identity_id
    WHERE r.admin_identity_id = public.wellbridge_current_admin_id()
      AND r.role_name = p_role
      AND r.revoked_at IS NULL
      AND (r.expires_at IS NULL OR r.expires_at > statement_timestamp())
      AND a.account_status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION wellbridge_has_any_role(VARIADIC p_roles text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_role_assignments r
    JOIN public.admin_identities a ON a.id = r.admin_identity_id
    WHERE r.admin_identity_id = public.wellbridge_current_admin_id()
      AND r.role_name = ANY(p_roles)
      AND r.revoked_at IS NULL
      AND (r.expires_at IS NULL OR r.expires_at > statement_timestamp())
      AND a.account_status = 'active'
  );
$$;

-- Only a current platform owner can grant/revoke roles. Identity-row locking
-- prevents concurrent duplicate active grants; expired history is retained.
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
AS $$
DECLARE v_actor uuid; v_assignment_id uuid;
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
  PERFORM 1 FROM public.admin_identities WHERE id = p_admin_identity_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Target administrator identity does not exist'; END IF;
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
$$;

CREATE OR REPLACE FUNCTION wellbridge_revoke_admin_role(
  p_assignment_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE v_actor uuid;
BEGIN
  v_actor := public.wellbridge_current_admin_id();
  IF v_actor IS NULL OR NOT public.wellbridge_has_role('platform_owner') THEN
    RAISE EXCEPTION 'Only an active platform owner may revoke administrator roles';
  END IF;
  IF nullif(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A revocation reason is required';
  END IF;
  UPDATE public.admin_role_assignments
  SET revoked_by_admin_id = v_actor, revoked_at = statement_timestamp(),
      grant_reason = grant_reason || E'\nRevocation: ' || btrim(p_reason)
  WHERE id = p_assignment_id AND revoked_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active role assignment not found'; END IF;
END;
$$;

-- The existing AFTER INSERT trigger runs with this tightly scoped definer
-- function so an approver need not receive direct UPDATE rights on review rows.
CREATE OR REPLACE FUNCTION apply_verification_decision_to_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $
BEGIN
  UPDATE public.verification_reviews
  SET review_status = NEW.decision,
      closed_at = CASE WHEN NEW.decision IN ('approved','rejected') THEN statement_timestamp() ELSE NULL END,
      updated_at = statement_timestamp()
  WHERE id = NEW.review_id;
  RETURN NEW;
END;
$;

-- A decision must be made by the authenticated database actor, who must be
-- an active approver/owner and must differ from the assigned verifier.
CREATE OR REPLACE FUNCTION enforce_verification_decision_rules()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE v_assignee uuid; v_review_status text; v_actor uuid;
BEGIN
  v_actor := public.wellbridge_current_admin_id();
  IF v_actor IS NULL OR NEW.decided_by_admin_id IS DISTINCT FROM v_actor THEN
    RAISE EXCEPTION 'Decision actor must match the authenticated administrator context';
  END IF;
  SELECT assigned_to_admin_id, review_status
    INTO v_assignee, v_review_status
  FROM public.verification_reviews
  WHERE id = NEW.review_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Verification review does not exist'; END IF;
  IF v_assignee IS NOT NULL AND v_assignee = v_actor THEN
    RAISE EXCEPTION 'A reviewer cannot decide their own verification review';
  END IF;
  IF v_review_status NOT IN ('submitted','changes_requested') THEN
    RAISE EXCEPTION 'A decision can only be recorded for a submitted review';
  END IF;
  IF NOT public.wellbridge_has_any_role('pathway_approver','platform_owner') THEN
    RAISE EXCEPTION 'An active pathway approver or platform owner role is required';
  END IF;
  RETURN NEW;
END;
$$;

-- Replace the original policy-free state with explicit default-deny RLS.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'admin_identities','admin_role_assignments','verification_reviews',
    'verification_review_evidence','evidence_attachments','verification_decisions',
    'audit_log','organisations','facilities','services','facility_services',
    'service_contact_channels','referral_relationships','professional_credentials',
    'administrative_area_authorities','evidence_sources','verification_events'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    -- Table owners retain controlled migration/trigger administration; the non-owner
    -- wellbridge_app role remains subject to RLS.
  END LOOP;
END;
$$;

CREATE POLICY admin_identities_read_self_or_owner ON admin_identities
  FOR SELECT TO wellbridge_app
  USING (id = wellbridge_current_admin_id() OR wellbridge_has_role('platform_owner'));

CREATE POLICY admin_roles_read_self_or_owner ON admin_role_assignments
  FOR SELECT TO wellbridge_app
  USING (admin_identity_id = wellbridge_current_admin_id() OR wellbridge_has_role('platform_owner'));

CREATE POLICY reviews_read_authorised ON verification_reviews
  FOR SELECT TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator','pathway_verifier','pathway_approver','audit_reviewer'));

CREATE POLICY reviews_insert_administrator ON verification_reviews
  FOR INSERT TO wellbridge_app
  WITH CHECK (
    created_by_admin_id = wellbridge_current_admin_id()
    AND wellbridge_has_any_role('platform_owner','pathway_administrator')
  );

CREATE POLICY reviews_update_administrator_or_assignee ON verification_reviews
  FOR UPDATE TO wellbridge_app
  USING (
    wellbridge_has_any_role('platform_owner','pathway_administrator')
    OR (assigned_to_admin_id = wellbridge_current_admin_id()
        AND wellbridge_has_role('pathway_verifier'))
  )
  WITH CHECK (
    wellbridge_has_any_role('platform_owner','pathway_administrator')
    OR (assigned_to_admin_id = wellbridge_current_admin_id()
        AND wellbridge_has_role('pathway_verifier'))
  );

CREATE POLICY review_evidence_read_authorised ON verification_review_evidence
  FOR SELECT TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator','pathway_verifier','pathway_approver','audit_reviewer'));
CREATE POLICY review_evidence_insert_authorised ON verification_review_evidence
  FOR INSERT TO wellbridge_app
  WITH CHECK (
    linked_by_admin_id = wellbridge_current_admin_id()
    AND wellbridge_has_any_role('platform_owner','pathway_administrator','pathway_verifier')
  );

CREATE POLICY attachments_read_authorised ON evidence_attachments
  FOR SELECT TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator','pathway_verifier','pathway_approver','audit_reviewer'));
CREATE POLICY attachments_insert_authorised ON evidence_attachments
  FOR INSERT TO wellbridge_app
  WITH CHECK (
    uploaded_by_admin_id = wellbridge_current_admin_id()
    AND wellbridge_has_any_role('platform_owner','pathway_administrator','pathway_verifier')
  );
CREATE POLICY attachments_update_administrator ON evidence_attachments
  FOR UPDATE TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator'))
  WITH CHECK (wellbridge_has_any_role('platform_owner','pathway_administrator'));

CREATE POLICY decisions_read_authorised ON verification_decisions
  FOR SELECT TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator','pathway_verifier','pathway_approver','audit_reviewer'));
CREATE POLICY decisions_insert_approver ON verification_decisions
  FOR INSERT TO wellbridge_app
  WITH CHECK (
    decided_by_admin_id = wellbridge_current_admin_id()
    AND wellbridge_has_any_role('platform_owner','pathway_approver')
  );

CREATE POLICY audit_read_owner_or_reviewer ON audit_log
  FOR SELECT TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','audit_reviewer'));

-- Pathway data is readable only to authenticated, active administrators with
-- a recognised role. Mutations are restricted to pathway administrators/owners.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'organisations','facilities','services','facility_services',
    'service_contact_channels','referral_relationships',
    'professional_credentials','administrative_area_authorities',
    'evidence_sources','verification_events'
  ] LOOP
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT TO wellbridge_app USING (public.wellbridge_has_any_role(''platform_owner'',''pathway_administrator'',''pathway_verifier'',''pathway_approver'',''audit_reviewer''))',
      t || '_read_admin', t
    );
  END LOOP;
END;
$$;

CREATE POLICY organisations_write_pathway_admin ON organisations
  FOR ALL TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator'))
  WITH CHECK (wellbridge_has_any_role('platform_owner','pathway_administrator'));
CREATE POLICY facilities_write_pathway_admin ON facilities
  FOR ALL TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator'))
  WITH CHECK (wellbridge_has_any_role('platform_owner','pathway_administrator'));
CREATE POLICY services_write_pathway_admin ON services
  FOR ALL TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator'))
  WITH CHECK (wellbridge_has_any_role('platform_owner','pathway_administrator'));
CREATE POLICY facility_services_write_pathway_admin ON facility_services
  FOR ALL TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator'))
  WITH CHECK (wellbridge_has_any_role('platform_owner','pathway_administrator'));
CREATE POLICY service_contact_channels_write_pathway_admin ON service_contact_channels
  FOR ALL TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator'))
  WITH CHECK (wellbridge_has_any_role('platform_owner','pathway_administrator'));
CREATE POLICY referral_relationships_write_pathway_admin ON referral_relationships
  FOR ALL TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator'))
  WITH CHECK (wellbridge_has_any_role('platform_owner','pathway_administrator'));
CREATE POLICY professional_credentials_write_pathway_admin ON professional_credentials
  FOR ALL TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator'))
  WITH CHECK (wellbridge_has_any_role('platform_owner','pathway_administrator'));
CREATE POLICY administrative_area_authorities_write_pathway_admin ON administrative_area_authorities
  FOR ALL TO wellbridge_app
  USING (wellbridge_has_any_role('platform_owner','pathway_administrator'))
  WITH CHECK (wellbridge_has_any_role('platform_owner','pathway_administrator'));
CREATE POLICY evidence_sources_write_verifier_or_admin ON evidence_sources
  FOR INSERT TO wellbridge_app
  WITH CHECK (wellbridge_has_any_role('platform_owner','pathway_administrator','pathway_verifier'));
CREATE POLICY verification_events_write_verifier_or_admin ON verification_events
  FOR INSERT TO wellbridge_app
  WITH CHECK (wellbridge_has_any_role('platform_owner','pathway_administrator','pathway_verifier'));


-- Restrict verifier status transitions to work they are assigned to perform.
CREATE OR REPLACE FUNCTION guard_review_workflow_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $
BEGIN
  IF NEW.review_status IS NOT DISTINCT FROM OLD.review_status THEN
    RETURN NEW;
  END IF;
  IF NEW.review_status = 'cancelled'
     AND NOT public.wellbridge_has_any_role('platform_owner','pathway_administrator') THEN
    RAISE EXCEPTION 'Only a pathway administrator or platform owner may cancel a review';
  END IF;
  IF public.wellbridge_has_role('pathway_verifier')
     AND NOT public.wellbridge_has_any_role('platform_owner','pathway_administrator')
     AND NEW.review_status NOT IN ('in_progress','submitted') THEN
    RAISE EXCEPTION 'A verifier may only move an assigned review into progress or submit it';
  END IF;
  IF public.wellbridge_has_role('pathway_verifier')
     AND NOT public.wellbridge_has_any_role('platform_owner','pathway_administrator')
     AND OLD.review_status NOT IN ('assigned','in_progress','changes_requested') THEN
    RAISE EXCEPTION 'This review is not in a verifier-editable state';
  END IF;
  RETURN NEW;
END;
$;
CREATE TRIGGER trg_guard_review_workflow_transition
BEFORE UPDATE OF review_status ON verification_reviews
FOR EACH ROW EXECUTE FUNCTION guard_review_workflow_transition();

-- A client cannot set a review to an approval outcome directly. Such a state
-- must be backed by the independently validated decision row inserted first.
CREATE OR REPLACE FUNCTION guard_review_decision_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $
BEGIN
  IF NEW.review_status IN ('approved','rejected','changes_requested')
     AND OLD.review_status IS DISTINCT FROM NEW.review_status
     AND NOT EXISTS (
       SELECT 1 FROM public.verification_decisions d
       WHERE d.review_id = NEW.id AND d.decision = NEW.review_status
     ) THEN
    RAISE EXCEPTION 'Review decision states must be created through verification_decisions';
  END IF;
  RETURN NEW;
END;
$;
CREATE TRIGGER trg_guard_review_decision_state
BEFORE UPDATE OF review_status ON verification_reviews
FOR EACH ROW EXECUTE FUNCTION guard_review_decision_state();

-- No direct role-table writes, audit writes, or deletes from the application role.
REVOKE ALL ON admin_identities, admin_role_assignments, verification_reviews,
  verification_review_evidence, evidence_attachments, verification_decisions,
  audit_log, organisations, facilities, services, facility_services,
  service_contact_channels, referral_relationships, professional_credentials,
  administrative_area_authorities, evidence_sources, verification_events
FROM PUBLIC, wellbridge_app;

REVOKE CREATE ON SCHEMA public FROM PUBLIC, wellbridge_app;
GRANT USAGE ON SCHEMA public TO wellbridge_app;
GRANT SELECT ON admin_identities, admin_role_assignments, verification_reviews,
  verification_review_evidence, evidence_attachments, verification_decisions,
  audit_log, organisations, facilities, services, facility_services,
  service_contact_channels, referral_relationships, professional_credentials,
  administrative_area_authorities, evidence_sources, verification_events
TO wellbridge_app;
GRANT INSERT ON verification_reviews, verification_review_evidence,
  evidence_attachments, verification_decisions, evidence_sources, verification_events
TO wellbridge_app;
GRANT UPDATE ON verification_reviews, evidence_attachments,
  organisations, facilities, services, facility_services, service_contact_channels,
  referral_relationships, professional_credentials, administrative_area_authorities
TO wellbridge_app;

REVOKE ALL ON FUNCTION wellbridge_current_admin_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION wellbridge_has_role(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION wellbridge_has_any_role(text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION wellbridge_grant_admin_role(uuid,text,text,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION wellbridge_revoke_admin_role(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION wellbridge_current_admin_id() TO wellbridge_app;
GRANT EXECUTE ON FUNCTION wellbridge_has_role(text) TO wellbridge_app;
GRANT EXECUTE ON FUNCTION wellbridge_has_any_role(text[]) TO wellbridge_app;
GRANT EXECUTE ON FUNCTION wellbridge_grant_admin_role(uuid,text,text,timestamptz) TO wellbridge_app;
GRANT EXECUTE ON FUNCTION wellbridge_revoke_admin_role(uuid,text) TO wellbridge_app;

-- Avoid accidental use of owner credentials by the application.
COMMENT ON ROLE wellbridge_app IS
  'Non-owner application role. Must not be SUPERUSER or BYPASSRLS. Trusted server only; never expose credentials to clients.';

COMMIT;

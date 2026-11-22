-- Migration 004 security regression tests.
-- Run only against a disposable PostgreSQL database after migrations 001-004.
-- The script creates fixtures and rolls the entire test transaction back.
BEGIN;

DO $$
DECLARE
  v_owner uuid := gen_random_uuid();
  v_verifier uuid := gen_random_uuid();
  v_approver uuid := gen_random_uuid();
  v_auditor uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_target uuid := gen_random_uuid();
  v_country uuid := gen_random_uuid();
  v_org uuid := gen_random_uuid();
  v_evidence uuid := gen_random_uuid();
  v_review uuid := gen_random_uuid();
BEGIN
  INSERT INTO admin_identities(id, identity_issuer, identity_subject, account_status)
  VALUES
    (v_owner, 'https://issuer.test', 'owner-' || v_owner, 'active'),
    (v_verifier, 'https://issuer.test', 'verifier-' || v_verifier, 'active'),
    (v_approver, 'https://issuer.test', 'approver-' || v_approver, 'active'),
    (v_auditor, 'https://issuer.test', 'auditor-' || v_auditor, 'active'),
    (v_admin, 'https://issuer.test', 'admin-' || v_admin, 'active'),
    (v_target, 'https://issuer.test', 'target-' || v_target, 'active');

  INSERT INTO admin_role_assignments(admin_identity_id, role_name, granted_by_admin_id, grant_reason)
  VALUES
    (v_owner, 'platform_owner', v_owner, 'test fixture'),
    (v_verifier, 'pathway_verifier', v_owner, 'test fixture'),
    (v_approver, 'pathway_approver', v_owner, 'test fixture'),
    (v_auditor, 'audit_reviewer', v_owner, 'test fixture'),
    (v_admin, 'pathway_administrator', v_owner, 'test fixture');

  INSERT INTO countries(id, iso2, name) VALUES (v_country, 'ZZ', 'Test Country');
  INSERT INTO organisations(id, country_id, name, organisation_type, notes)
  VALUES (v_org, v_country, 'Migration 004 Test Organisation', 'other', 'initial');

  INSERT INTO evidence_sources(id, source_title, source_url, source_type, evidence_summary)
  VALUES (v_evidence, 'Test evidence', 'https://example.invalid/evidence', 'other', 'Synthetic security test fixture');

  PERFORM set_config('app.actor_admin_id', v_admin::text, true);
  INSERT INTO verification_reviews(
    id, entity_type, entity_id, claim_to_verify, review_status,
    assigned_to_admin_id, created_by_admin_id
  ) VALUES (
    v_review, 'organisation', v_org, 'Synthetic claim for security regression testing',
    'queued', NULL, v_admin
  );
  INSERT INTO verification_review_evidence(review_id, evidence_id, relevance_note, linked_by_admin_id)
  VALUES (v_review, v_evidence, 'Synthetic fixture evidence', v_verifier);
  UPDATE verification_reviews
  SET assigned_to_admin_id = v_verifier, review_status = 'submitted'
  WHERE id = v_review;

  PERFORM set_config('test.owner_id', v_owner::text, true);
  PERFORM set_config('test.verifier_id', v_verifier::text, true);
  PERFORM set_config('test.approver_id', v_approver::text, true);
  PERFORM set_config('test.auditor_id', v_auditor::text, true);
  PERFORM set_config('test.admin_id', v_admin::text, true);
  PERFORM set_config('test.target_id', v_target::text, true);
  PERFORM set_config('test.review_id', v_review::text, true);
  PERFORM set_config('test.org_id', v_org::text, true);
END;
$$;

-- Verifier: own assignment visibility, no audit access, no approval powers.
SET LOCAL ROLE wellbridge_app;
SELECT set_config('app.actor_admin_id', current_setting('test.verifier_id'), true);
DO $$
DECLARE n integer;
BEGIN
  IF NOT wellbridge_has_role('pathway_verifier') THEN RAISE EXCEPTION 'Verifier role was not resolved'; END IF;
  SELECT count(*) INTO n FROM admin_role_assignments;
  IF n <> 1 THEN RAISE EXCEPTION 'Verifier should see only its own role assignment; saw %', n; END IF;
  SELECT count(*) INTO n FROM audit_log;
  IF n <> 0 THEN RAISE EXCEPTION 'Verifier must not read audit log'; END IF;
  BEGIN
    UPDATE verification_reviews SET review_status = 'approved'
      WHERE id = current_setting('test.review_id')::uuid;
    RAISE EXCEPTION 'Verifier unexpectedly changed a review to approved';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'Verifier unexpectedly changed a review to approved' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE verification_reviews SET review_status = 'cancelled'
      WHERE id = current_setting('test.review_id')::uuid;
    RAISE EXCEPTION 'Verifier unexpectedly cancelled a review';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'Verifier unexpectedly cancelled a review' THEN RAISE; END IF;
  END;
  SELECT count(*) INTO n FROM verification_reviews
    WHERE id = current_setting('test.review_id')::uuid AND review_status = 'submitted';
  IF n <> 1 THEN RAISE EXCEPTION 'Verifier changed a review to approved without a decision'; END IF;
  BEGIN
    INSERT INTO verification_decisions(review_id, decision, rationale, decided_by_admin_id)
    VALUES (current_setting('test.review_id')::uuid, 'approved', 'forbidden test', current_setting('test.verifier_id')::uuid);
    RAISE EXCEPTION 'Verifier unexpectedly inserted an approval decision';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  UPDATE organisations SET notes = 'verifier must not change this'
    WHERE id = current_setting('test.org_id')::uuid;
  SELECT count(*) INTO n FROM organisations
    WHERE id = current_setting('test.org_id')::uuid AND notes = 'initial';
  IF n <> 1 THEN RAISE EXCEPTION 'Verifier unexpectedly changed pathway organisation data'; END IF;
END;
$$;
RESET ROLE;

-- Approver: can record a decision for another verifier's submitted review.
SET LOCAL ROLE wellbridge_app;
SELECT set_config('app.actor_admin_id', current_setting('test.approver_id'), true);
INSERT INTO verification_decisions(review_id, decision, rationale, decided_by_admin_id)
VALUES (current_setting('test.review_id')::uuid, 'approved', 'Synthetic independent approval test', current_setting('test.approver_id')::uuid);
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM verification_reviews
  WHERE id = current_setting('test.review_id')::uuid AND review_status = 'approved';
  IF n <> 1 THEN RAISE EXCEPTION 'Decision did not update review state'; END IF;
  SELECT count(*) INTO n FROM audit_log;
  IF n <> 0 THEN RAISE EXCEPTION 'Approver must not read audit log'; END IF;
END;
$$;
RESET ROLE;

-- Auditor: read-only audit access; cannot mutate the log.
SET LOCAL ROLE wellbridge_app;
SELECT set_config('app.actor_admin_id', current_setting('test.auditor_id'), true);
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM audit_log;
  IF n < 1 THEN RAISE EXCEPTION 'Auditor should read audit events'; END IF;
  BEGIN
    UPDATE audit_log SET action = 'tampered' WHERE id = (SELECT min(id) FROM audit_log);
    RAISE EXCEPTION 'Auditor unexpectedly updated the audit log';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;
RESET ROLE;

-- Pathway administrator: can maintain pathway records but cannot administer roles.
SET LOCAL ROLE wellbridge_app;
SELECT set_config('app.actor_admin_id', current_setting('test.admin_id'), true);
DO $$
DECLARE n integer;
BEGIN
  UPDATE organisations SET notes = 'administrator update permitted'
    WHERE id = current_setting('test.org_id')::uuid;
  SELECT count(*) INTO n FROM organisations
    WHERE id = current_setting('test.org_id')::uuid AND notes = 'administrator update permitted';
  IF n <> 1 THEN RAISE EXCEPTION 'Pathway administrator could not update pathway record'; END IF;
  BEGIN
    PERFORM wellbridge_grant_admin_role(
      current_setting('test.target_id')::uuid, 'pathway_verifier', 'unauthorised grant test', NULL
    );
    RAISE EXCEPTION 'Pathway administrator unexpectedly granted a role';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'Pathway administrator unexpectedly granted a role' THEN RAISE; END IF;
  END;
END;
$$;
RESET ROLE;

-- Platform owner: controlled role grant/revocation; target history is retained.
SET LOCAL ROLE wellbridge_app;
SELECT set_config('app.actor_admin_id', current_setting('test.owner_id'), true);
SELECT set_config(
  'test.assignment_id',
  wellbridge_grant_admin_role(
    current_setting('test.target_id')::uuid,
    'pathway_verifier',
    'security regression grant',
    statement_timestamp() + interval '1 day'
  )::text,
  true
);
SELECT wellbridge_revoke_admin_role(current_setting('test.assignment_id')::uuid, 'security regression revoke');
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM admin_role_assignments
  WHERE id = current_setting('test.assignment_id')::uuid
    AND revoked_at IS NOT NULL AND revoked_by_admin_id = current_setting('test.owner_id')::uuid;
  IF n <> 1 THEN RAISE EXCEPTION 'Platform owner role revocation was not recorded'; END IF;
END;
$$;
RESET ROLE;

ROLLBACK;

-- Migration 004 security regression tests.
-- Run only against a disposable PostgreSQL database after migrations 001-005.
-- The script creates fixtures and rolls the entire test transaction back.
BEGIN;

-- Disposable CI-only signing key and SECURITY DEFINER test helper. This helper
-- exists only in pg_temp and is rolled back; it must never enter application code.
INSERT INTO wellbridge_private.actor_assertion_keys(key_id, secret, active)
VALUES ('ci-test', decode(repeat('ab', 32), 'hex'), true);

CREATE FUNCTION pg_temp.test_set_actor(p_actor uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, wellbridge_private, pg_temp
AS $test_sign$
DECLARE
  v_epoch bigint := extract(epoch FROM clock_timestamp())::bigint;
  v_nonce text := gen_random_uuid()::text;
  v_secret bytea;
  v_payload text;
  v_signature text;
BEGIN
  SELECT secret INTO STRICT v_secret
  FROM wellbridge_private.actor_assertion_keys
  WHERE key_id = 'ci-test' AND active;
  v_payload := 'ci-test|' || p_actor::text || '|' || v_epoch::text || '|' || v_nonce;
  v_signature := encode(public.hmac(convert_to(v_payload, 'UTF8'), v_secret, 'sha256'), 'hex');
  PERFORM public.wellbridge_set_actor_context(p_actor, 'ci-test', v_epoch, v_nonce, v_signature);
END;
$test_sign$;

CREATE FUNCTION pg_temp.test_set_expired_actor(p_actor uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, wellbridge_private, pg_temp
AS $test_expired$
DECLARE
  v_epoch bigint := extract(epoch FROM clock_timestamp())::bigint - 600;
  v_nonce text := gen_random_uuid()::text;
  v_secret bytea;
  v_payload text;
  v_signature text;
BEGIN
  SELECT secret INTO STRICT v_secret
  FROM wellbridge_private.actor_assertion_keys
  WHERE key_id = 'ci-test' AND active;
  v_payload := 'ci-test|' || p_actor::text || '|' || v_epoch::text || '|' || v_nonce;
  v_signature := encode(public.hmac(convert_to(v_payload, 'UTF8'), v_secret, 'sha256'), 'hex');
  PERFORM set_config('app.actor_admin_id', p_actor::text, true);
  PERFORM set_config('app.actor_key_id', 'ci-test', true);
  PERFORM set_config('app.actor_issued_at', v_epoch::text, true);
  PERFORM set_config('app.actor_nonce', v_nonce, true);
  PERFORM set_config('app.actor_signature', v_signature, true);
END;
$test_expired$;

CREATE FUNCTION pg_temp.test_set_replayed_actor(p_actor uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, wellbridge_private, pg_temp
AS $test_replay$
DECLARE
  v_epoch bigint := extract(epoch FROM clock_timestamp())::bigint;
  v_nonce text := gen_random_uuid()::text;
  v_secret bytea;
  v_payload text;
  v_signature text;
BEGIN
  SELECT secret INTO STRICT v_secret
  FROM wellbridge_private.actor_assertion_keys
  WHERE key_id = 'ci-test' AND active;
  v_payload := 'ci-test|' || p_actor::text || '|' || v_epoch::text || '|' || v_nonce;
  v_signature := encode(public.hmac(convert_to(v_payload, 'UTF8'), v_secret, 'sha256'), 'hex');
  INSERT INTO wellbridge_private.actor_assertion_nonces
    (nonce, actor_admin_id, transaction_id, issued_at)
  VALUES (v_nonce, p_actor, txid_current() - 1, to_timestamp(v_epoch));
  PERFORM set_config('app.actor_admin_id', p_actor::text, true);
  PERFORM set_config('app.actor_key_id', 'ci-test', true);
  PERFORM set_config('app.actor_issued_at', v_epoch::text, true);
  PERFORM set_config('app.actor_nonce', v_nonce, true);
  PERFORM set_config('app.actor_signature', v_signature, true);
END;
$test_replay$;

DO $fixtures$
DECLARE
  v_owner uuid := gen_random_uuid();
  v_verifier uuid := gen_random_uuid();
  v_approver uuid := gen_random_uuid();
  v_auditor uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_target uuid := gen_random_uuid();
  v_suspended uuid := gen_random_uuid();
  v_owner_assignment uuid;
  v_country uuid := gen_random_uuid();
  v_org uuid := gen_random_uuid();
  v_evidence uuid := gen_random_uuid();
  v_review uuid := gen_random_uuid();
  v_other_review uuid := gen_random_uuid();
BEGIN
  INSERT INTO admin_identities(id, identity_issuer, identity_subject, account_status)
  VALUES
    (v_owner, 'https://issuer.test', 'owner-' || v_owner, 'active'),
    (v_verifier, 'https://issuer.test', 'verifier-' || v_verifier, 'active'),
    (v_approver, 'https://issuer.test', 'approver-' || v_approver, 'active'),
    (v_auditor, 'https://issuer.test', 'auditor-' || v_auditor, 'active'),
    (v_admin, 'https://issuer.test', 'admin-' || v_admin, 'active'),
    (v_target, 'https://issuer.test', 'target-' || v_target, 'active'),
    (v_suspended, 'https://issuer.test', 'suspended-' || v_suspended, 'suspended');

  INSERT INTO admin_role_assignments(admin_identity_id, role_name, granted_by_admin_id, grant_reason)
  VALUES
    (v_owner, 'platform_owner', v_owner, 'test fixture'),
    (v_verifier, 'pathway_verifier', v_owner, 'test fixture'),
    (v_approver, 'pathway_approver', v_owner, 'test fixture'),
    (v_auditor, 'audit_reviewer', v_owner, 'test fixture'),
    (v_admin, 'pathway_administrator', v_owner, 'test fixture');
  SELECT id INTO v_owner_assignment FROM admin_role_assignments
    WHERE admin_identity_id = v_owner AND role_name = 'platform_owner';

  INSERT INTO countries(id, iso2, name) VALUES (v_country, 'ZZ', 'Test Country');
  INSERT INTO organisations(id, country_id, name, organisation_type, notes)
  VALUES (v_org, v_country, 'Migration 004 Test Organisation', 'other', 'initial');

  INSERT INTO evidence_sources(id, source_title, source_url, source_type, evidence_summary)
  VALUES (v_evidence, 'Test evidence', 'https://example.invalid/evidence', 'other', 'Synthetic security test fixture');

  PERFORM pg_temp.test_set_actor(v_admin);
  INSERT INTO verification_reviews(
    id, entity_type, entity_id, claim_to_verify, review_status,
    assigned_to_admin_id, created_by_admin_id
  ) VALUES (
    v_review, 'organisation', v_org, 'Synthetic claim for security regression testing',
    'queued', NULL, v_admin
  );
  UPDATE verification_reviews
  SET assigned_to_admin_id = v_verifier, review_status = 'assigned'
  WHERE id = v_review;
  PERFORM pg_temp.test_set_actor(v_verifier);
  INSERT INTO verification_review_evidence(review_id, evidence_id, relevance_note, linked_by_admin_id)
  VALUES (v_review, v_evidence, 'Synthetic fixture evidence', v_verifier);
  UPDATE verification_reviews SET review_status = 'in_progress' WHERE id = v_review;
  UPDATE verification_reviews SET review_status = 'submitted' WHERE id = v_review;

  PERFORM pg_temp.test_set_actor(v_admin);
  INSERT INTO verification_reviews(
    id, entity_type, entity_id, claim_to_verify, review_status,
    assigned_to_admin_id, created_by_admin_id
  ) VALUES (
    v_other_review, 'organisation', v_org, 'Second synthetic claim for isolation testing',
    'queued', NULL, v_admin
  );
  UPDATE verification_reviews
    SET assigned_to_admin_id = v_admin, review_status = 'assigned'
    WHERE id = v_other_review;

  PERFORM pg_temp.test_set_actor(v_verifier);
  PERFORM set_config('test.owner_id', v_owner::text, true);
  PERFORM set_config('test.verifier_id', v_verifier::text, true);
  PERFORM set_config('test.approver_id', v_approver::text, true);
  PERFORM set_config('test.auditor_id', v_auditor::text, true);
  PERFORM set_config('test.admin_id', v_admin::text, true);
  PERFORM set_config('test.target_id', v_target::text, true);
  PERFORM set_config('test.suspended_id', v_suspended::text, true);
  PERFORM set_config('test.owner_assignment_id', v_owner_assignment::text, true);
  PERFORM set_config('test.review_id', v_review::text, true);
  PERFORM set_config('test.org_id', v_org::text, true);
END;
$fixtures$;

-- Verifier: own assignment visibility, no audit access, no approval powers.
SET LOCAL ROLE wellbridge_app;
SELECT pg_temp.test_set_actor(current_setting('test.verifier_id')::uuid);
DO $$
DECLARE n integer;
BEGIN
  IF NOT wellbridge_has_role('pathway_verifier') THEN RAISE EXCEPTION 'Verifier role was not resolved'; END IF;
  SELECT count(*) INTO n FROM verification_reviews;
  IF n <> 1 THEN RAISE EXCEPTION 'Verifier must see only their assigned review; saw %', n; END IF;
  PERFORM set_config('app.actor_admin_id', current_setting('test.owner_id'), true);
  IF wellbridge_current_admin_id() IS NOT NULL THEN
    RAISE EXCEPTION 'Unsigned actor GUC unexpectedly authenticated as platform owner';
  END IF;
  PERFORM pg_temp.test_set_expired_actor(current_setting('test.verifier_id')::uuid);
  IF wellbridge_current_admin_id() IS NOT NULL THEN
    RAISE EXCEPTION 'Expired actor assertion unexpectedly authenticated';
  END IF;
  PERFORM pg_temp.test_set_replayed_actor(current_setting('test.verifier_id')::uuid);
  IF wellbridge_current_admin_id() IS NOT NULL THEN
    RAISE EXCEPTION 'A nonce bound to another transaction was replayed successfully';
  END IF;
  PERFORM pg_temp.test_set_actor(current_setting('test.verifier_id')::uuid);
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
  EXCEPTION WHEN insufficient_privilege OR raise_exception THEN
    IF SQLERRM = 'Verifier unexpectedly inserted an approval decision' THEN RAISE; END IF;
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
SELECT pg_temp.test_set_actor(current_setting('test.approver_id')::uuid);
INSERT INTO verification_decisions(review_id, decision, rationale, decided_by_admin_id)
VALUES (current_setting('test.review_id')::uuid, 'approved', 'Synthetic independent approval test', current_setting('test.approver_id')::uuid);
DO $approver_test$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM verification_reviews;
  IF n <> 1 THEN RAISE EXCEPTION 'Approver must see only submitted/decision-lifecycle reviews; saw %', n; END IF;
  SELECT count(*) INTO n FROM verification_review_evidence;
  IF n <> 1 THEN RAISE EXCEPTION 'Approver evidence visibility did not follow review visibility'; END IF;
  SELECT count(*) INTO n FROM verification_reviews
  WHERE id = current_setting('test.review_id')::uuid AND review_status = 'approved';
  IF n <> 1 THEN RAISE EXCEPTION 'Decision did not update review state'; END IF;
  SELECT count(*) INTO n FROM audit_log;
  IF n <> 0 THEN RAISE EXCEPTION 'Approver must not read audit log'; END IF;
END;
$approver_test$;
RESET ROLE;

-- Auditor: read-only audit access; cannot mutate the log.
SET LOCAL ROLE wellbridge_app;
SELECT pg_temp.test_set_actor(current_setting('test.auditor_id')::uuid);
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
SELECT pg_temp.test_set_actor(current_setting('test.admin_id')::uuid);
DO $$
DECLARE n integer;
BEGIN
  UPDATE organisations SET notes = 'administrator update permitted'
    WHERE id = current_setting('test.org_id')::uuid;
  SELECT count(*) INTO n FROM organisations
    WHERE id = current_setting('test.org_id')::uuid AND notes = 'administrator update permitted';
  IF n <> 1 THEN RAISE EXCEPTION 'Pathway administrator could not update pathway record'; END IF;
  BEGIN
    UPDATE verification_reviews
      SET assigned_to_admin_id = current_setting('test.suspended_id')::uuid
      WHERE id = current_setting('test.review_id')::uuid;
    RAISE EXCEPTION 'Pathway administrator unexpectedly assigned a suspended identity';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'Pathway administrator unexpectedly assigned a suspended identity' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE verification_reviews
      SET assigned_to_admin_id = current_setting('test.target_id')::uuid
      WHERE id = current_setting('test.review_id')::uuid;
    RAISE EXCEPTION 'Pathway administrator unexpectedly assigned a non-verifier';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'Pathway administrator unexpectedly assigned a non-verifier' THEN RAISE; END IF;
  END;
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
SELECT pg_temp.test_set_actor(current_setting('test.owner_id')::uuid);
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
DO $owner_test$
DECLARE n integer;
BEGIN
  IF public.wellbridge_resolve_admin_identity(
    'https://issuer.test',
    'suspended-' || current_setting('test.suspended_id')
  ) IS NOT NULL THEN
    RAISE EXCEPTION 'Suspended administrator identity was resolved';
  END IF;
  BEGIN
    PERFORM wellbridge_grant_admin_role(
      current_setting('test.suspended_id')::uuid,
      'pathway_verifier',
      'must reject inactive identity',
      NULL
    );
    RAISE EXCEPTION 'Platform owner unexpectedly granted a role to a suspended identity';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'Platform owner unexpectedly granted a role to a suspended identity' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM wellbridge_revoke_admin_role(
      current_setting('test.owner_assignment_id')::uuid,
      'must retain final owner'
    );
    RAISE EXCEPTION 'Platform owner unexpectedly revoked the final platform owner';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'Platform owner unexpectedly revoked the final platform owner' THEN RAISE; END IF;
  END;
  SELECT count(*) INTO n FROM admin_role_assignments
  WHERE id = current_setting('test.assignment_id')::uuid
    AND revoked_at IS NOT NULL AND revoked_by_admin_id = current_setting('test.owner_id')::uuid;
  IF n <> 1 THEN RAISE EXCEPTION 'Platform owner role revocation was not recorded'; END IF;
END;
$owner_test$;
RESET ROLE;

ROLLBACK;

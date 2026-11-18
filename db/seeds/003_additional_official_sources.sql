-- Supplementary authoritative source records for agency/emergency directory claims.
-- Public-source review only; does not indicate operational testing.

DO $$
DECLARE
  v_lasema_service uuid;
  v_lsp_hcb uuid;
  v_citizens_gate uuid;
  v_agency_directory uuid;
BEGIN
  INSERT INTO evidence_sources
    (source_title,source_url,source_type,publisher,evidence_summary,limitations)
  SELECT 'Lagos State Citizens Gate — emergency services','https://citizensgate.lagosstate.gov.ng/','government',
    'Lagos State Government','Additional Lagos State public-service source cited for LASEMA emergency contact information.',
    'Published listing does not prove current call answering, dispatch coverage or mental-health emergency handling.'
  WHERE NOT EXISTS (SELECT 1 FROM evidence_sources WHERE source_url='https://citizensgate.lagosstate.gov.ng/');

  INSERT INTO evidence_sources
    (source_title,source_url,source_type,publisher,evidence_summary,limitations)
  SELECT 'Lagos State Government — agency directory','https://citizensgate.lagosstate.gov.ng/lasg_das.php','government',
    'Lagos State Government','Agency directory identifies Lagos State Primary Health Care Board as a state agency.',
    'Agency listing does not confirm current PHC facility allocation, service availability or referral relationships.'
  WHERE NOT EXISTS (SELECT 1 FROM evidence_sources WHERE source_url='https://citizensgate.lagosstate.gov.ng/lasg_das.php');

  SELECT id INTO v_lasema_service FROM services
    WHERE service_name='Lagos State LASEMA emergency lines 767 / 112' LIMIT 1;
  SELECT id INTO v_lsp_hcb FROM organisations
    WHERE name='Lagos State Primary Health Care Board' LIMIT 1;
  SELECT id INTO v_citizens_gate FROM evidence_sources
    WHERE source_url='https://citizensgate.lagosstate.gov.ng/' LIMIT 1;
  SELECT id INTO v_agency_directory FROM evidence_sources
    WHERE source_url='https://citizensgate.lagosstate.gov.ng/lasg_das.php' LIMIT 1;

  UPDATE service_contact_channels
  SET evidence_id=v_citizens_gate,
      notes='Lagos State public-service listing; current operation and dispatch capability remain unconfirmed.'
  WHERE service_id=v_lasema_service AND channel_type='telephone'
    AND channel_value IN ('767','112') AND v_citizens_gate IS NOT NULL;

  IF v_lasema_service IS NOT NULL AND v_citizens_gate IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM verification_events
      WHERE entity_type='service' AND entity_id=v_lasema_service
        AND evidence_id=v_citizens_gate AND verification_method='public_source_review')
  THEN
    INSERT INTO verification_events
      (entity_type,entity_id,verification_method,outcome,confirming_organisation,evidence_id,details,limitations)
    VALUES ('service',v_lasema_service,'public_source_review','supports_claim',
      'Lagos State Government',v_citizens_gate,
      'Additional Lagos State public-service source publishes emergency contact information associated with LASEMA.',
      'This is not a live test and does not confirm dispatch coverage or specialist mental-health response.');
  END IF;

  IF v_lsp_hcb IS NOT NULL AND v_agency_directory IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM verification_events
      WHERE entity_type='organisation' AND entity_id=v_lsp_hcb
        AND evidence_id=v_agency_directory AND verification_method='public_source_review')
  THEN
    INSERT INTO verification_events
      (entity_type,entity_id,verification_method,outcome,confirming_organisation,evidence_id,details,limitations)
    VALUES ('organisation',v_lsp_hcb,'public_source_review','supports_claim',
      'Lagos State Government',v_agency_directory,
      'Lagos State agency directory identifies the Lagos State Primary Health Care Board.',
      'This does not confirm current facility-level supervisory assignments or a live mental-health service roster.');
  END IF;
END $$;

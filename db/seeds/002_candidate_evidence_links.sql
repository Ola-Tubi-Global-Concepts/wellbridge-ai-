-- Link the candidate records to their public-source evidence.
-- These events document desk research only, not direct operator confirmation.

DO $$
BEGIN
  INSERT INTO verification_events
    (entity_type,entity_id,verification_method,outcome,confirming_organisation,evidence_id,details,limitations)
  SELECT 'facility', f.id, 'public_source_review', 'supports_claim',
    e.publisher, e.id,
    'Facility identity and/or directory listing appears in the cited public source.',
    'This public-source review does not confirm current operation, mental-health staffing, service availability, opening hours, fees, eligibility or referral acceptance.'
  FROM facilities f
  JOIN evidence_sources e ON e.source_url='https://www.lagosmind.org/facilities/'
  WHERE f.official_name IN (
    'Onilekere PHC','Oregun PHC','Ojodu PHC',
    'Alimosho General Hospital','Gbagada General Hospital',
    'Lagos Island General Hospital','Ikorodu General Hospital',
    'Epe General Hospital','Lagos State University Teaching Hospital (LASUTH)'
  )
  AND NOT EXISTS (
    SELECT 1 FROM verification_events v
    WHERE v.entity_type='facility' AND v.entity_id=f.id
      AND v.evidence_id=e.id AND v.verification_method='public_source_review'
  );

  INSERT INTO verification_events
    (entity_type,entity_id,verification_method,outcome,confirming_organisation,evidence_id,details,limitations)
  SELECT 'facility', f.id, 'public_source_review', 'supports_claim',
    e.publisher, e.id,
    'Specialist facility identity and published patient information/contact details appear in the hospital source.',
    'The source does not constitute direct confirmation to WellBridge AI of current capacity, intake, fees, age eligibility, emergency access or contact routing.'
  FROM facilities f
  JOIN evidence_sources e ON e.source_url='https://fnphyaba.gov.ng/health-information/'
  WHERE f.official_name='Federal Neuro-Psychiatric Hospital Yaba'
    AND NOT EXISTS (
      SELECT 1 FROM verification_events v
      WHERE v.entity_type='facility' AND v.entity_id=f.id
        AND v.evidence_id=e.id AND v.verification_method='public_source_review'
    );

  INSERT INTO verification_events
    (entity_type,entity_id,verification_method,outcome,confirming_organisation,evidence_id,details,limitations)
  SELECT 'service', s.id, 'public_source_review',
    CASE WHEN s.service_name='MeHPriC primary-care mental-health programme'
      THEN 'partially_supports_claim' ELSE 'supports_claim' END,
    e.publisher, e.id,
    CASE
      WHEN s.service_name='Nigeria national emergency number 112'
        THEN 'The NCC source lists 112 as a national emergency number.'
      WHEN s.service_name='Lagos State LASEMA emergency lines 767 / 112'
        THEN 'Lagos State public information publishes 767 and 112 as emergency lines.'
      WHEN s.service_name='Lagos Lifeline'
        THEN 'Lagos MiND publishes Lifeline contact channels and describes the service.'
      ELSE 'Lagos MiND describes the MeHPriC programme and its flagship PHC network.'
    END,
    s.scope_limitations
  FROM services s
  JOIN evidence_sources e ON
    (s.service_name='Nigeria national emergency number 112' AND e.source_url='https://ncc.gov.ng/media/836/view')
    OR (s.service_name='Lagos State LASEMA emergency lines 767 / 112' AND e.source_url='https://www.lagosstate.gov.ng/')
    OR (s.service_name='Lagos Lifeline' AND e.source_url='https://www.lagosmind.org/lagos-lifeline/')
    OR (s.service_name='MeHPriC primary-care mental-health programme' AND e.source_url='https://www.lagosmind.org/mehpric')
  WHERE NOT EXISTS (
    SELECT 1 FROM verification_events v
    WHERE v.entity_type='service' AND v.entity_id=s.id
      AND v.evidence_id=e.id AND v.verification_method='public_source_review'
  );

  INSERT INTO verification_events
    (entity_type,entity_id,verification_method,outcome,confirming_organisation,evidence_id,details,limitations)
  SELECT 'organisation', o.id, 'public_source_review', 'supports_claim',
    e.publisher, e.id,
    'Organisation or public administrative role is identified in the cited official/public source.',
    'This does not confirm a named contact person, current operational responsibility, service-level availability or a formal relationship with WellBridge AI.'
  FROM organisations o
  JOIN evidence_sources e ON
    (o.name='Lagos State Primary Health Care Board' AND e.source_url='https://lagosministryofhealth.org/primary-health-facilities/')
    OR (o.name='Lagos State Health District VI' AND e.source_url='https://lshdvi.org/about')
    OR (o.name='Lagos MiND' AND e.source_url='https://www.lagosmind.org/contact')
    OR (o.name='Nigerian Communications Commission' AND e.source_url='https://ncc.gov.ng/media/836/view')
    OR (o.name='Lagos State Emergency Management Agency (LASEMA)' AND e.source_url='https://www.lagosstate.gov.ng/')
    OR (o.name='Federal Neuro-Psychiatric Hospital Yaba' AND e.source_url='https://fnphyaba.gov.ng/contact-us/')
  WHERE NOT EXISTS (
    SELECT 1 FROM verification_events v
    WHERE v.entity_type='organisation' AND v.entity_id=o.id
      AND v.evidence_id=e.id AND v.verification_method='public_source_review'
  );
END $$;

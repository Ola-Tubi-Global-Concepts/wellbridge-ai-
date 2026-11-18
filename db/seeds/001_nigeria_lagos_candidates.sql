-- WellBridge AI initial Nigeria/Lagos candidate data.
-- Apply only after migrations 001 and 002 in a disposable development database.
-- This is NOT an instruction to create/provision a database or enable a public directory.
-- All entries are candidates/public claims; no service is marked verified_active.

DO $$
DECLARE
  v_country uuid;
  v_lagos uuid;
  v_ikeja uuid;
  v_onigbongbo uuid;
  v_ojodu uuid;
  v_phc_district6 uuid;
  v_health_district6 uuid;
  v_lsp_hcb uuid;
  v_health_district_org uuid;
  v_lagos_mind uuid;
  v_lifeline uuid;
  v_ncc uuid;
  v_lasema uuid;
  v_fnp_yaba uuid;
  v_112 uuid;
  v_lasema_emergency uuid;
  v_lifeline_service uuid;
  v_mehpric uuid;
BEGIN
  INSERT INTO countries (iso2, name)
  VALUES ('NG', 'Nigeria')
  ON CONFLICT (iso2) DO UPDATE SET name = EXCLUDED.name
  RETURNING id INTO v_country;

  INSERT INTO administrative_areas (country_id, area_type, name, source_note)
  SELECT v_country, 'state', 'Lagos State',
    'State-level pilot geography; source: Lagos State Government.'
  WHERE NOT EXISTS (
    SELECT 1 FROM administrative_areas
    WHERE country_id = v_country AND area_type = 'state'
      AND name = 'Lagos State' AND parent_area_id IS NULL
  );
  SELECT id INTO v_lagos FROM administrative_areas
    WHERE country_id = v_country AND area_type = 'state'
      AND name = 'Lagos State' AND parent_area_id IS NULL LIMIT 1;

  INSERT INTO administrative_areas (country_id, parent_area_id, area_type, name, source_note)
  SELECT v_country, v_lagos, 'lga', 'Ikeja',
    'Candidate locality from Lagos MiND facilities directory.'
  WHERE NOT EXISTS (SELECT 1 FROM administrative_areas WHERE country_id=v_country AND parent_area_id=v_lagos AND area_type='lga' AND name='Ikeja');
  SELECT id INTO v_ikeja FROM administrative_areas WHERE country_id=v_country AND parent_area_id=v_lagos AND area_type='lga' AND name='Ikeja' LIMIT 1;

  INSERT INTO administrative_areas (country_id, parent_area_id, area_type, name, source_note)
  SELECT v_country, v_lagos, 'lcda', 'Onigbongbo',
    'Candidate locality from Lagos MiND facilities directory and Health District VI coverage page.'
  WHERE NOT EXISTS (SELECT 1 FROM administrative_areas WHERE country_id=v_country AND parent_area_id=v_lagos AND area_type='lcda' AND name='Onigbongbo');
  SELECT id INTO v_onigbongbo FROM administrative_areas WHERE country_id=v_country AND parent_area_id=v_lagos AND area_type='lcda' AND name='Onigbongbo' LIMIT 1;

  INSERT INTO administrative_areas (country_id, parent_area_id, area_type, name, source_note)
  SELECT v_country, v_lagos, 'lcda', 'Ojodu',
    'Candidate locality from Lagos MiND facilities directory and Health District VI coverage page.'
  WHERE NOT EXISTS (SELECT 1 FROM administrative_areas WHERE country_id=v_country AND parent_area_id=v_lagos AND area_type='lcda' AND name='Ojodu');
  SELECT id INTO v_ojodu FROM administrative_areas WHERE country_id=v_country AND parent_area_id=v_lagos AND area_type='lcda' AND name='Ojodu' LIMIT 1;

  INSERT INTO administrative_areas (country_id, parent_area_id, area_type, name, source_note)
  SELECT v_country, v_lagos, 'district', 'PHC Board District 6',
    'Older Lagos Ministry of Health PHC directory; current allocation requires written confirmation.'
  WHERE NOT EXISTS (SELECT 1 FROM administrative_areas WHERE country_id=v_country AND parent_area_id=v_lagos AND area_type='district' AND name='PHC Board District 6');
  SELECT id INTO v_phc_district6 FROM administrative_areas WHERE country_id=v_country AND parent_area_id=v_lagos AND area_type='district' AND name='PHC Board District 6' LIMIT 1;

  INSERT INTO administrative_areas (country_id, parent_area_id, area_type, name, source_note)
  SELECT v_country, v_lagos, 'district', 'Lagos State Health District VI',
    'Current Health District VI coverage page; do not conflate with PHC Board District 6.'
  WHERE NOT EXISTS (SELECT 1 FROM administrative_areas WHERE country_id=v_country AND parent_area_id=v_lagos AND area_type='district' AND name='Lagos State Health District VI');
  SELECT id INTO v_health_district6 FROM administrative_areas WHERE country_id=v_country AND parent_area_id=v_lagos AND area_type='district' AND name='Lagos State Health District VI' LIMIT 1;

  -- Evidence source records: public-source evidence only, not direct operator confirmation.
  INSERT INTO evidence_sources (source_title, source_url, source_type, publisher, evidence_summary, limitations)
  SELECT x.title, x.url, x.kind, x.publisher, x.summary, x.limitations
  FROM (VALUES
    ('Lagos Ministry of Health — Primary Health Facilities','https://lagosministryofhealth.org/primary-health-facilities/','government','Lagos State Ministry of Health','Older PHC directory listing PHC Board district structure and candidate facilities including Onilekere, Oregun and Ojodu.','Older directory; current district allocation and facility operation require written confirmation.'),
    ('Lagos State Health District VI — About','https://lshdvi.org/about','government','Lagos State Health District VI','Publishes Health District VI coverage including Ikeja, Onigbongbo and Ojodu.','Does not establish PHC Board district allocation or mental-health service availability at named PHCs.'),
    ('Lagos State Health District VI — Contact','https://lshdvi.org/contact','government','Lagos State Health District VI','Publishes district contact emails and office address.','Contact channels have not been independently tested by WellBridge AI.'),
    ('Lagos MiND — Facilities','https://www.lagosmind.org/facilities/','operator','Lagos MiND','Publishes MeHPriC flagship PHC directory and five general-hospital referral hubs.','Directory and programme claims; no individual PHC-to-hospital assignment matrix captured.'),
    ('Lagos MiND — MeHPriC','https://www.lagosmind.org/mehpric','operator','Lagos MiND','Describes MeHPriC mental-health support model across 57 flagship PHCs.','System/programme claim does not prove current operation at a particular facility.'),
    ('Lagos MiND — Lagos Lifeline','https://www.lagosmind.org/lagos-lifeline/','operator','Lagos MiND','Publishes Lifeline channels and describes the service.','Operator-published claims; direct confirmation and agreed non-emergency test pending.'),
    ('Lagos MiND — Contact','https://www.lagosmind.org/contact','operator','Lagos MiND','Publishes organisation contact channels.','No formal partnership or direct service confirmation established.'),
    ('Nigerian Communications Commission — Emergency Numbers','https://ncc.gov.ng/media/836/view','regulator','Nigerian Communications Commission','Lists 112 as a national emergency number.','Does not establish current call-answering or dispatch coverage in every locality.'),
    ('Lagos State Government','https://www.lagosstate.gov.ng/','government','Lagos State Government','Public source for Lagos State emergency information.','Current LASEMA line operation and mental-health dispatch process require confirmation.'),
    ('Federal Neuro-Psychiatric Hospital Yaba — Patient Information','https://fnphyaba.gov.ng/health-information/','facility','Federal Neuro-Psychiatric Hospital Yaba','Publishes patient information including emergency-unit access claims.','Provider-published information; direct confirmation to WellBridge AI remains pending.'),
    ('Federal Neuro-Psychiatric Hospital Yaba — Contact','https://fnphyaba.gov.ng/contact-us/','facility','Federal Neuro-Psychiatric Hospital Yaba','Publishes hospital contact details.','General contacts are not confirmed as direct emergency-unit lines.')
  ) AS x(title,url,kind,publisher,summary,limitations)
  WHERE NOT EXISTS (SELECT 1 FROM evidence_sources e WHERE e.source_url=x.url AND e.source_title=x.title);

  INSERT INTO organisations (country_id, name, organisation_type, official_website, status, notes)
  SELECT v_country, x.name, x.kind, x.website, x.status, x.notes
  FROM (VALUES
    ('Lagos State Primary Health Care Board','government_authority','https://lagosstate.gov.ng/health/','officially_published','Responsible state PHC agency identified by Lagos State sources; current PHC roster and allocations requested, confirmation pending.'),
    ('Lagos State Health District VI','health_district','https://lshdvi.org/','officially_published','Separate health district administration; published coverage includes Ikeja, Onigbongbo and Ojodu. Its precise role for each PHC requires written clarification.'),
    ('Lagos MiND','helpline_operator','https://www.lagosmind.org/','officially_published','Publishes MeHPriC and Lagos Lifeline information; direct service/operator confirmation pending.'),
    ('Nigerian Communications Commission','professional_regulator','https://ncc.gov.ng/','officially_published','Publishes national emergency numbering information; not an emergency dispatch operator.'),
    ('Lagos State Emergency Management Agency (LASEMA)','government_authority','https://www.lagosstate.gov.ng/','officially_published','Lagos State publishes emergency lines associated with LASEMA; live operation and mental-health dispatch details pending.'),
    ('Federal Neuro-Psychiatric Hospital Yaba','hospital_operator','https://fnphyaba.gov.ng/','officially_published','Specialist mental-health facility candidate; verification email response pending.')
  ) AS x(name,kind,website,status,notes)
  WHERE NOT EXISTS (SELECT 1 FROM organisations o WHERE o.country_id=v_country AND lower(o.name)=lower(x.name));

  SELECT id INTO v_lsp_hcb FROM organisations WHERE country_id=v_country AND name='Lagos State Primary Health Care Board' LIMIT 1;
  SELECT id INTO v_health_district_org FROM organisations WHERE country_id=v_country AND name='Lagos State Health District VI' LIMIT 1;
  SELECT id INTO v_lagos_mind FROM organisations WHERE country_id=v_country AND name='Lagos MiND' LIMIT 1;
  SELECT id INTO v_ncc FROM organisations WHERE country_id=v_country AND name='Nigerian Communications Commission' LIMIT 1;
  SELECT id INTO v_lasema FROM organisations WHERE country_id=v_country AND name='Lagos State Emergency Management Agency (LASEMA)' LIMIT 1;
  SELECT id INTO v_fnp_yaba FROM organisations WHERE country_id=v_country AND name='Federal Neuro-Psychiatric Hospital Yaba' LIMIT 1;

  INSERT INTO facilities (organisation_id,country_id,administrative_area_id,official_name,facility_type,address,verification_status,operating_status)
  SELECT NULL,v_country,x.area_id,x.name,x.kind,x.address,'officially_published','unknown'
  FROM (VALUES
    (v_ikeja,'Onilekere PHC','primary_health_centre','11 Ogunsolu Street, Cement Bus-Stop, Ikeja'),
    (v_onigbongbo,'Oregun PHC','primary_health_centre','32/34 Kudirat Abiola Way, Oregun, Lagos'),
    (v_ojodu,'Ojodu PHC','primary_health_centre','31 Gbadamosi Street, Ojodu'),
    (NULL::uuid,'Alimosho General Hospital','general_hospital','Igando Road, Ikotun, Lagos'),
    (NULL::uuid,'Gbagada General Hospital','general_hospital','Hospital Road, Gbagada, Lagos'),
    (NULL::uuid,'Lagos Island General Hospital','general_hospital','Broad Street, Lagos Island, Lagos'),
    (NULL::uuid,'Ikorodu General Hospital','general_hospital','TOS Benson Road, Ikorodu, Lagos'),
    (NULL::uuid,'Epe General Hospital','general_hospital','Hospital Road, Epe, Lagos'),
    (NULL::uuid,'Lagos State University Teaching Hospital (LASUTH)','teaching_hospital','1 Oba Akinjobi Way, GRA, Ikeja, Lagos'),
    (NULL::uuid,'Federal Neuro-Psychiatric Hospital Yaba','specialist_hospital','8 Harvey Road, Yaba, Lagos')
  ) AS x(area_id,name,kind,address)
  WHERE NOT EXISTS (SELECT 1 FROM facilities f WHERE f.country_id=v_country AND lower(f.official_name)=lower(x.name) AND coalesce(lower(f.address),'')=lower(x.address));

  INSERT INTO services (organisation_id,service_name,service_category,description,verification_status,scope_limitations)
  SELECT x.org_id,x.name,x.category,x.description,'officially_published',x.limitations
  FROM (VALUES
    (v_ncc,'Nigeria national emergency number 112','emergency_response','112 is published as Nigeria national emergency number.','Number allocation/publication does not establish local call answering, coverage, dispatch capability or response time.'),
    (v_lasema,'Lagos State LASEMA emergency lines 767 / 112','emergency_response','Lagos State publishes 767 and 112 as emergency contact numbers associated with LASEMA.','Current call-answering, dispatch coverage and mental-health emergency handling remain unconfirmed.'),
    (v_lagos_mind,'Lagos Lifeline','crisis_helpline','Lagos MiND publishes voice, WhatsApp and email channels and describes free, confidential 24-hour support.','Operator claims have not been directly confirmed or live-tested by WellBridge AI; no partnership is implied.'),
    (v_lagos_mind,'MeHPriC primary-care mental-health programme','screening','Lagos MiND describes screening, individual care and group therapy through a network of flagship PHCs.','Programme-level description only; no facility-level service is confirmed by this seed.')
  ) AS x(org_id,name,category,description,limitations)
  WHERE NOT EXISTS (SELECT 1 FROM services s WHERE lower(s.service_name)=lower(x.name) AND s.service_category=x.category);

  SELECT id INTO v_112 FROM services WHERE service_name='Nigeria national emergency number 112' LIMIT 1;
  SELECT id INTO v_lasema_emergency FROM services WHERE service_name='Lagos State LASEMA emergency lines 767 / 112' LIMIT 1;
  SELECT id INTO v_lifeline_service FROM services WHERE service_name='Lagos Lifeline' LIMIT 1;
  SELECT id INTO v_mehpric FROM services WHERE service_name='MeHPriC primary-care mental-health programme' LIMIT 1;

  -- Contact channels are explicitly marked as public-source claims, not live-tested.
  INSERT INTO service_contact_channels (service_id,channel_type,channel_value,display_label,availability_claim,verification_status,evidence_id,notes)
  SELECT x.service_id,x.channel,x.value,x.label,x.claim,'officially_published',
    (SELECT e.id FROM evidence_sources e WHERE e.source_url=x.source_url ORDER BY e.accessed_at DESC LIMIT 1),
    x.notes
  FROM (VALUES
    (v_112,'telephone','112','Nigeria emergency number','National number published; operational coverage not established.','https://ncc.gov.ng/media/836/view','Do not imply guaranteed connection or response.'),
    (v_lasema_emergency,'telephone','767','Lagos State emergency line','Published by Lagos State; current operation pending confirmation.','https://www.lagosstate.gov.ng/','Do not present as a specialist mental-health helpline.'),
    (v_lasema_emergency,'telephone','112','Lagos State emergency line','Published by Lagos State; current operation pending confirmation.','https://www.lagosstate.gov.ng/','Do not imply mental-health dispatch capability.'),
    (v_lifeline_service,'telephone','070 0000 6463','Lagos Lifeline voice','Lagos MiND website describes 24-hour availability; direct confirmation pending.','https://www.lagosmind.org/lagos-lifeline/','Operator-published claim; not tested by WellBridge AI.'),
    (v_lifeline_service,'telephone','020 1410 6463','Lagos Lifeline voice','Lagos MiND website describes 24-hour availability; direct confirmation pending.','https://www.lagosmind.org/lagos-lifeline/','Operator-published claim; not tested by WellBridge AI.'),
    (v_lifeline_service,'whatsapp','090 9000 6463','Lagos Lifeline WhatsApp','Published as WhatsApp channel; response availability pending confirmation.','https://www.lagosmind.org/lagos-lifeline/','Do not infer that WhatsApp is an emergency dispatch channel.'),
    (v_lifeline_service,'email','help@lagosmind.org','Lagos MiND contact email','Published contact channel; response time not established.','https://www.lagosmind.org/contact','Not an emergency response channel.')
  ) AS x(service_id,channel,value,label,claim,source_url,notes)
  WHERE x.service_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM service_contact_channels c WHERE c.service_id=x.service_id AND c.channel_type=x.channel AND c.channel_value=x.value);

  -- Administrative relationships remain separate and provisional.
  INSERT INTO administrative_area_authorities (administrative_area_id,organisation_id,responsibility_type,verification_status,evidence_id,responsibility_notes)
  SELECT x.area_id,x.org_id,x.kind,'officially_published',
    (SELECT e.id FROM evidence_sources e WHERE e.source_url=x.source_url LIMIT 1),x.notes
  FROM (VALUES
    (v_phc_district6,v_lsp_hcb,'phc_board_district','https://lagosministryofhealth.org/primary-health-facilities/','Older Ministry PHC directory describes PHC Board District 6 and lists the three candidate PHCs; current allocation requires written confirmation.'),
    (v_health_district6,v_health_district_org,'health_district_supervision','https://lshdvi.org/about','Health District VI publishes its own coverage; do not conflate its structure with PHC Board District 6.')
  ) AS x(area_id,org_id,kind,source_url,notes)
  WHERE x.area_id IS NOT NULL AND x.org_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM administrative_area_authorities a WHERE a.administrative_area_id=x.area_id AND a.organisation_id=x.org_id AND a.responsibility_type=x.kind);

  -- Record facility-to-district coverage claims separately; these do not assert
  -- which administrative body has final PHC Board or facility supervisory authority.
  INSERT INTO administrative_area_authorities (administrative_area_id,organisation_id,responsibility_type,verification_status,evidence_id,responsibility_notes)
  SELECT x.area_id,v_health_district_org,'health_district_supervision','officially_published',
    (SELECT e.id FROM evidence_sources e WHERE e.source_url='https://lshdvi.org/about' LIMIT 1),x.notes
  FROM (VALUES
    (v_ikeja,'Health District VI coverage page includes Ikeja; supervisory role for Onilekere PHC specifically requires written confirmation.'),
    (v_onigbongbo,'Health District VI coverage page includes Onigbongbo; supervisory role for Oregun PHC specifically requires written confirmation.'),
    (v_ojodu,'Health District VI coverage page includes Ojodu; supervisory role for Ojodu PHC specifically requires written confirmation.')
  ) AS x(area_id,notes)
  WHERE x.area_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM administrative_area_authorities a WHERE a.administrative_area_id=x.area_id AND a.organisation_id=v_health_district_org AND a.responsibility_type='health_district_supervision');

END $$;

-- Intentionally no facility_services or referral_relationship rows are inserted:
-- the current evidence does not confirm facility-level service availability or
-- the formal PHC-to-hospital cluster assignments.

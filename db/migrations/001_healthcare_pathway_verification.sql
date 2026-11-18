-- WellBridge AI healthcare pathway verification register
-- Internal administrative metadata only. No patient, check-in, symptom, or crisis records.
-- This migration is a reviewed starter: do not apply to production until privacy,
-- security, identity, access-control, backup, and clinical-governance approvals exist.

CREATE TABLE countries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  iso2 char(2) NOT NULL UNIQUE,
  name text NOT NULL,
  enabled_for_research boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE administrative_areas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country_id uuid NOT NULL REFERENCES countries(id),
  parent_area_id uuid REFERENCES administrative_areas(id),
  area_type text NOT NULL CHECK (area_type IN ('state','region','province','lga','lcda','district','county','other')),
  name text NOT NULL,
  official_code text,
  source_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(country_id, parent_area_id, area_type, name)
);

CREATE TABLE organisations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country_id uuid NOT NULL REFERENCES countries(id),
  name text NOT NULL,
  organisation_type text NOT NULL CHECK (organisation_type IN
    ('government_authority','health_district','hospital_operator','clinic_operator','helpline_operator','professional_regulator','ngo','other')),
  official_website text,
  general_contact_email text,
  general_contact_phone text,
  status text NOT NULL DEFAULT 'research_only' CHECK (status IN
    ('research_only','officially_published','direct_confirmation_pending','verified_active','temporarily_unavailable','expired','rejected')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE facilities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organisation_id uuid REFERENCES organisations(id),
  country_id uuid NOT NULL REFERENCES countries(id),
  administrative_area_id uuid REFERENCES administrative_areas(id),
  official_name text NOT NULL,
  facility_type text NOT NULL CHECK (facility_type IN
    ('primary_health_centre','general_hospital','specialist_hospital','teaching_hospital','community_service','helpline','other')),
  address text,
  public_website text,
  public_phone text,
  public_email text,
  operating_status text NOT NULL DEFAULT 'unknown' CHECK (operating_status IN
    ('unknown','reported_open','confirmed_open','temporarily_closed','closed')),
  verification_status text NOT NULL DEFAULT 'research_only' CHECK (verification_status IN
    ('research_only','officially_published','direct_confirmation_pending','verified_active','temporarily_unavailable','expired','rejected')),
  last_verified_at timestamptz,
  next_review_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organisation_id uuid REFERENCES organisations(id),
  service_name text NOT NULL,
  service_category text NOT NULL CHECK (service_category IN
    ('wellbeing_support','counselling','screening','clinical_assessment','psychotherapy','psychiatry','inpatient','emergency_response','crisis_helpline','referral_coordination','other')),
  description text,
  age_min integer CHECK (age_min IS NULL OR age_min >= 0),
  age_max integer CHECK (age_max IS NULL OR age_max >= age_min),
  cost_description text,
  languages text[] NOT NULL DEFAULT '{}',
  eligibility_notes text,
  scope_limitations text,
  verification_status text NOT NULL DEFAULT 'research_only' CHECK (verification_status IN
    ('research_only','officially_published','direct_confirmation_pending','verified_active','temporarily_unavailable','expired','rejected')),
  last_verified_at timestamptz,
  next_review_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE facility_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id uuid NOT NULL REFERENCES facilities(id),
  service_id uuid NOT NULL REFERENCES services(id),
  availability_notes text,
  opening_hours text,
  appointment_required boolean,
  walk_in_allowed boolean,
  fee_notes text,
  verification_status text NOT NULL DEFAULT 'research_only' CHECK (verification_status IN
    ('research_only','officially_published','direct_confirmation_pending','verified_active','temporarily_unavailable','expired','rejected')),
  last_verified_at timestamptz,
  next_review_at timestamptz,
  UNIQUE(facility_id, service_id)
);

CREATE TABLE referral_relationships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_facility_id uuid NOT NULL REFERENCES facilities(id),
  to_facility_id uuid NOT NULL REFERENCES facilities(id),
  relationship_type text NOT NULL CHECK (relationship_type IN
    ('formal_cluster_assignment','clinical_referral','urgent_transfer','advice_only','other')),
  assignment_scope text,
  acceptance_process text,
  required_documents text,
  out_of_hours_process text,
  fallback_process text,
  verification_status text NOT NULL DEFAULT 'research_only' CHECK (verification_status IN
    ('research_only','officially_published','direct_confirmation_pending','verified_active','temporarily_unavailable','expired','rejected')),
  last_verified_at timestamptz,
  next_review_at timestamptz,
  CHECK (from_facility_id <> to_facility_id)
);

CREATE TABLE professional_credentials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organisation_id uuid REFERENCES organisations(id),
  facility_id uuid REFERENCES facilities(id),
  professional_role text NOT NULL,
  regulator_name text,
  regulator_register_url text,
  registration_reference text,
  credential_status text NOT NULL DEFAULT 'not_checked' CHECK (credential_status IN
    ('not_checked','pending','verified','expired','not_applicable','rejected')),
  checked_at timestamptz,
  check_evidence_id uuid,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (organisation_id IS NOT NULL OR facility_id IS NOT NULL)
);

CREATE TABLE evidence_sources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_title text NOT NULL,
  source_url text NOT NULL,
  source_type text NOT NULL CHECK (source_type IN
    ('government','regulator','facility','operator','peer_reviewed','other')),
  publisher text,
  published_at date,
  accessed_at timestamptz NOT NULL DEFAULT now(),
  evidence_summary text NOT NULL,
  limitations text,
  archived_reference text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE verification_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL CHECK (entity_type IN
    ('organisation','facility','service','facility_service','referral_relationship','professional_credential')),
  entity_id uuid NOT NULL,
  verification_method text NOT NULL CHECK (verification_method IN
    ('public_source_review','official_email','official_letter','telephone_confirmation','agreed_non_emergency_test','regulator_register_check','site_visit','other')),
  outcome text NOT NULL CHECK (outcome IN
    ('supports_claim','partially_supports_claim','not_confirmed','contradicts_claim','temporarily_unavailable')),
  confirmed_by_role text,
  confirming_organisation text,
  confirmation_date date,
  evidence_id uuid REFERENCES evidence_sources(id),
  details text NOT NULL,
  limitations text,
  reviewer text,
  reviewed_at timestamptz NOT NULL DEFAULT now(),
  next_review_at timestamptz
);

CREATE INDEX idx_facilities_area ON facilities(administrative_area_id);
CREATE INDEX idx_facilities_status ON facilities(verification_status);
CREATE INDEX idx_services_status ON services(verification_status);
CREATE INDEX idx_referrals_status ON referral_relationships(verification_status);
CREATE INDEX idx_verification_due ON verification_events(next_review_at);
CREATE INDEX idx_evidence_accessed ON evidence_sources(accessed_at);

-- Link credential checks to their evidence after both tables exist.
ALTER TABLE professional_credentials
  ADD CONSTRAINT fk_professional_credential_evidence
  FOREIGN KEY (check_evidence_id) REFERENCES evidence_sources(id);

-- IMPORTANT:
-- * No patient/user/check-in/conversation tables are included.
-- * No public API or directory query should expose these records by default.
-- * "verified_active" is a data-review state, not permission for automated clinical
--   triage or emergency dispatch. Separate clinical and operational approval is required.
-- * Before use, implement least-privilege operator access, row-level security where
--   appropriate, immutable audit logging, retention/deletion rules, encrypted backups,
--   secrets management, and tested restore/incident procedures.

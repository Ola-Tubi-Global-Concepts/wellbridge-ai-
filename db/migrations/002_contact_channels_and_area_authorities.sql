-- WellBridge AI migration 002: contact channels and administrative oversight
-- Internal directory metadata only; no patient or wellbeing data.

CREATE TABLE service_contact_channels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id uuid NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  channel_type text NOT NULL CHECK (channel_type IN
    ('telephone','whatsapp','email','website','physical_address','other')),
  channel_value text NOT NULL,
  display_label text,
  availability_claim text,
  verification_status text NOT NULL DEFAULT 'research_only' CHECK (verification_status IN
    ('research_only','officially_published','direct_confirmation_pending','verified_active','temporarily_unavailable','expired','rejected')),
  evidence_id uuid REFERENCES evidence_sources(id),
  last_verified_at timestamptz,
  next_review_at timestamptz,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(service_id, channel_type, channel_value)
);

-- Keep the different public-health administrative responsibilities explicit.
-- This does not imply a clinical referral or facility-level service assignment.
CREATE TABLE administrative_area_authorities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  administrative_area_id uuid NOT NULL REFERENCES administrative_areas(id) ON DELETE CASCADE,
  organisation_id uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
  responsibility_type text NOT NULL CHECK (responsibility_type IN
    ('phc_board_district','health_district_supervision','local_facility_management','other')),
  verification_status text NOT NULL DEFAULT 'officially_published' CHECK (verification_status IN
    ('research_only','officially_published','direct_confirmation_pending','verified_active','temporarily_unavailable','expired','rejected')),
  evidence_id uuid REFERENCES evidence_sources(id),
  responsibility_notes text NOT NULL,
  last_verified_at timestamptz,
  next_review_at timestamptz,
  UNIQUE(administrative_area_id, organisation_id, responsibility_type)
);

-- Prevent duplicate seed identities while preserving distinct facilities that
-- may share a name or address in different jurisdictions.
CREATE UNIQUE INDEX IF NOT EXISTS uq_organisations_country_name
  ON organisations(country_id, lower(name));
CREATE UNIQUE INDEX IF NOT EXISTS uq_facilities_country_name_address
  ON facilities(country_id, lower(official_name), coalesce(lower(address), ''));
CREATE UNIQUE INDEX IF NOT EXISTS uq_services_name_category
  ON services(lower(service_name), service_category);

CREATE INDEX idx_service_channels_status ON service_contact_channels(verification_status);
CREATE INDEX idx_area_authorities_area ON administrative_area_authorities(administrative_area_id);

-- Starter schema only. Do not apply to production before privacy, security
-- and clinical governance approval. No patient data is seeded.
CREATE TYPE directory_status AS ENUM (
  'pending_confirmation', 'source_verified', 'provider_confirmed',
  'clinically_approved', 'active'
);
CREATE TABLE provider_directory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  country_code CHAR(2) NOT NULL,
  display_name TEXT NOT NULL,
  service_type TEXT NOT NULL,
  official_source_url TEXT,
  verification_status directory_status NOT NULL DEFAULT 'pending_confirmation',
  verified_at TIMESTAMPTZ,
  verified_by TEXT,
  provider_acceptance_confirmed_at TIMESTAMPTZ,
  clinical_approval_reference TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT active_requires_approval CHECK (
    verification_status <> 'active' OR
    (verified_at IS NOT NULL AND provider_acceptance_confirmed_at IS NOT NULL AND clinical_approval_reference IS NOT NULL)
  )
);
CREATE INDEX provider_directory_country_status_idx ON provider_directory(country_code, verification_status);

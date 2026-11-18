# WellBridge AI pathway register — database setup notes

**Current state:** SQL files committed; database not provisioned or connected; no migration has been applied.

## Files and execution order

1. `migrations/001_healthcare_pathway_verification.sql` — core register tables.
2. `migrations/002_contact_channels_and_area_authorities.sql` — multiple service contact channels and separate administrative oversight records.
3. `seeds/001_nigeria_lagos_candidates.sql` — cautious Nigeria/Lagos desk-research candidates.
4. `seeds/002_candidate_evidence_links.sql` — attaches public-source review events to the candidate organisations, facilities and services.
5. `seeds/003_additional_official_sources.sql` — adds Lagos State agency-directory and emergency-contact evidence.

Apply only to a disposable PostgreSQL development database after reviewing the SQL. Do not run against production.

## Expected initial candidate contents

The seed script is designed to create, if absent:
- 1 country: Nigeria.
- 6 administrative areas: Lagos State, Ikeja, Onigbongbo, Ojodu, PHC Board District 6 and Lagos State Health District VI.
- 6 organisations: LSPHCB, Health District VI, Lagos MiND, NCC, LASEMA and Federal Neuro-Psychiatric Hospital Yaba.
- 10 facility candidates: three PHCs, five general-hospital hubs, LASUTH and Federal Neuro-Psychiatric Hospital Yaba.
- 4 service records: national 112, Lagos LASEMA emergency lines, Lagos Lifeline and MeHPriC.
- 7 contact channels: 112, 767, Lagos Lifeline's two voice numbers, WhatsApp and email (the emergency service rows include both national and Lagos 112 as separate records).
- Public evidence-source records for the relevant government, programme and facility pages.
- Public-source review events linked to the relevant candidate entities; these are not direct confirmations.

The script is intended to be repeatable and checks for existing records before inserting. Review it against the actual database state before execution.

## Initial quality checks

After applying migrations 001 and 002, then seed scripts 001, 002 and 003, use read-only checks:

```sql
SELECT iso2, name FROM countries WHERE iso2 = 'NG';

SELECT official_name, facility_type, address, verification_status, operating_status
FROM facilities
ORDER BY facility_type, official_name;

SELECT service_name, service_category, verification_status
FROM services
ORDER BY service_category, service_name;

SELECT s.service_name, c.channel_type, c.channel_value, c.verification_status
FROM service_contact_channels c
JOIN services s ON s.id = c.service_id
ORDER BY s.service_name, c.channel_type, c.channel_value;

SELECT a.name AS area, o.name AS authority, x.responsibility_type, x.verification_status
FROM administrative_area_authorities x
JOIN administrative_areas a ON a.id = x.administrative_area_id
JOIN organisations o ON o.id = x.organisation_id
ORDER BY a.name, o.name;

SELECT count(*) AS referral_relationships FROM referral_relationships;
SELECT count(*) AS facility_service_links FROM facility_services;
SELECT entity_type, outcome, count(*)
FROM verification_events
GROUP BY entity_type, outcome
ORDER BY entity_type, outcome;
```

The last two counts should be zero in this initial seed. That is intentional: the current evidence does not establish facility-level mental-health service availability or formal PHC-to-hospital cluster assignments.

## Safety and deployment boundary

- No patient, user, symptom, check-in, conversation or crisis-event data is stored.
- No pathway is seeded as `verified_active`.
- Publicly published contact details are not represented as live-tested.
- No referral relationship is inferred from geographic proximity.
- No API, user-facing directory, AI decision-making or crisis escalation is connected to these tables.
- Do not provision a paid database or connect the app until budget, privacy, security, identity/access, backup, retention, clinical governance and operational ownership are approved.

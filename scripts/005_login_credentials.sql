-- Demo users for a new environment: one user per BRD role (section 4.3), with their
-- role and login. Run after the Liquibase migration, as one transaction:
--   psql -v ON_ERROR_STOP=1 -1 -f scripts/005_login_credentials.sql
-- Safe to re-run; existing rows are left unchanged.
-- Password format: PBKDF2-HMAC-SHA256, 600000 iterations, 16-byte salt, 32-byte hash.
SET standard_conforming_strings = on;

-- Liquibase seeds Admin, ClaimsSpecialist, ProgramManager and CashPosting.
INSERT INTO entitlement.app_role (role_key, description)
VALUES
    ('BenefitsSpecialist', 'Confirms program eligibility and registers patients'),
    ('Management', 'Manages the specialist teams, sets up users and completes all transaction types'),
    ('ReportingSpecialist', 'Generates reports'),
    ('ITAdmin', 'Manages system functionality and configuration')
ON CONFLICT (role_key) DO NOTHING;

INSERT INTO entitlement.app_user (user_id, first_name, last_name, email)
VALUES
    ('ceca53af-52d1-40dd-ae1c-00fd6392ebbc', 'Admin', 'User', 'admin@anovorx.com'),
    ('6e961609-adc1-4b32-9219-d3616aa27631', 'Super', 'User', 'superuser@anovorx.com'),
    ('4b8102de-0941-4276-95d0-b13c2cd0cb47', 'Benefits', 'Specialist', 'benefits.specialist@anovorx.com'),
    ('18dbb09f-5c77-4bd6-976a-3d7700f931ee', 'Claims', 'Specialist', 'claims.specialist@anovorx.com'),
    ('910c336b-ebfa-4f9e-aadf-c23fe4f491f6', 'Cash', 'Posting', 'cash.posting@anovorx.com'),
    ('b5aaecd6-40e8-4af4-97bf-2b5490b8d561', 'Management', 'User', 'management@anovorx.com'),
    ('f92ba237-b794-4804-8df8-5755693f2f2b', 'Reporting', 'Specialist', 'reporting.specialist@anovorx.com'),
    ('894766bb-b26d-4c86-891b-3e23a6957c6d', 'Program', 'Manager', 'program.manager@anovorx.com')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO entitlement.role_assignment (user_id, role_id, effective_from, assigned_by)
SELECT v.user_id::uuid, r.role_id, current_date, 'environment-setup'
FROM (VALUES
    ('ceca53af-52d1-40dd-ae1c-00fd6392ebbc', 'Admin'),
    ('6e961609-adc1-4b32-9219-d3616aa27631', 'ITAdmin'),
    ('4b8102de-0941-4276-95d0-b13c2cd0cb47', 'BenefitsSpecialist'),
    ('18dbb09f-5c77-4bd6-976a-3d7700f931ee', 'ClaimsSpecialist'),
    ('910c336b-ebfa-4f9e-aadf-c23fe4f491f6', 'CashPosting'),
    ('b5aaecd6-40e8-4af4-97bf-2b5490b8d561', 'Management'),
    ('f92ba237-b794-4804-8df8-5755693f2f2b', 'ReportingSpecialist'),
    ('894766bb-b26d-4c86-891b-3e23a6957c6d', 'ProgramManager')
) AS v (user_id, role_key)
JOIN entitlement.app_role r ON r.role_key = v.role_key
WHERE NOT EXISTS (
    SELECT 1 FROM entitlement.role_assignment a
    WHERE a.user_id = v.user_id::uuid AND a.role_id = r.role_id AND a.revoked_at IS NULL);

INSERT INTO entitlement.user_credential (user_id, username, password_salt, password_hash)
VALUES ('ceca53af-52d1-40dd-ae1c-00fd6392ebbc', 'admin@anovorx.com', decode('34D47727549BABE129A4AE0A7EA86D77', 'hex'), decode('913AAB546662D6B4C52352FD5711D3064DB81898D5923BE6951CCED278FF89A1', 'hex'))
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO entitlement.user_credential (user_id, username, password_salt, password_hash)
VALUES ('6e961609-adc1-4b32-9219-d3616aa27631', 'superuser@anovorx.com', decode('D6AA4BCA81D757738FEA0E5CD1E9B7A5', 'hex'), decode('7CA7E1FC1CE52B59F62056D9A18D452EEAF00C86EC7E92CE45D3C74893A96E12', 'hex'))
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO entitlement.user_credential (user_id, username, password_salt, password_hash)
VALUES ('4b8102de-0941-4276-95d0-b13c2cd0cb47', 'benefits.specialist@anovorx.com', decode('F8CEA4BB326903A50BD70BD48A196297', 'hex'), decode('5DF4018A0DB82861B842A5C515BE0C75213F4E588042520BB91E00E3F9C90919', 'hex'))
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO entitlement.user_credential (user_id, username, password_salt, password_hash)
VALUES ('18dbb09f-5c77-4bd6-976a-3d7700f931ee', 'claims.specialist@anovorx.com', decode('AAD07DB9708C063A80B5216B7A3AE5D3', 'hex'), decode('1E1C2D092D5F27E9B45749D8460ED1C054FE0F114CD3DAD29ACFB3AA78D9A935', 'hex'))
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO entitlement.user_credential (user_id, username, password_salt, password_hash)
VALUES ('910c336b-ebfa-4f9e-aadf-c23fe4f491f6', 'cash.posting@anovorx.com', decode('066FE4932979EABA983DD4A40F3EAE2E', 'hex'), decode('48C9C8F08AE54F30219159585C84B09D2010BB8D932ECAD9376014AF0F3499A7', 'hex'))
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO entitlement.user_credential (user_id, username, password_salt, password_hash)
VALUES ('b5aaecd6-40e8-4af4-97bf-2b5490b8d561', 'management@anovorx.com', decode('CF02C5C8026E094D0A9F4741C90C2C88', 'hex'), decode('459BC3065AE4345870DD92ED1792D8E8152C97032B8811477C725C84D4060C82', 'hex'))
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO entitlement.user_credential (user_id, username, password_salt, password_hash)
VALUES ('f92ba237-b794-4804-8df8-5755693f2f2b', 'reporting.specialist@anovorx.com', decode('0687BFE5F59BA696F78E947461D617FD', 'hex'), decode('4E20FF39BBC0205818AB167008F3F7C418E3AFAFB755EF5C22B17151A108158E', 'hex'))
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO entitlement.user_credential (user_id, username, password_salt, password_hash)
VALUES ('894766bb-b26d-4c86-891b-3e23a6957c6d', 'program.manager@anovorx.com', decode('8513D7B2E8669EE0CB884E7154C25532', 'hex'), decode('FCF0850237B2FEB9B8C68396ED679A83D4AB6AD165C21DD2793F48E1C9D5CFA9', 'hex'))
ON CONFLICT (user_id) DO NOTHING;


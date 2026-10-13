-- Removes the demo users created by 005_login_credentials.sql, with their logins and
-- role assignments. Run as one transaction:
--   psql -v ON_ERROR_STOP=1 -1 -f scripts/005_login_credentials_rollback.sql
-- The four roles it added are removed only when no other user holds them.
DELETE FROM entitlement.user_credential WHERE user_id IN (
    'ceca53af-52d1-40dd-ae1c-00fd6392ebbc',
    '6e961609-adc1-4b32-9219-d3616aa27631',
    '4b8102de-0941-4276-95d0-b13c2cd0cb47',
    '18dbb09f-5c77-4bd6-976a-3d7700f931ee',
    '910c336b-ebfa-4f9e-aadf-c23fe4f491f6',
    'b5aaecd6-40e8-4af4-97bf-2b5490b8d561',
    'f92ba237-b794-4804-8df8-5755693f2f2b',
    '894766bb-b26d-4c86-891b-3e23a6957c6d');

DELETE FROM entitlement.role_assignment WHERE user_id IN (
    'ceca53af-52d1-40dd-ae1c-00fd6392ebbc',
    '6e961609-adc1-4b32-9219-d3616aa27631',
    '4b8102de-0941-4276-95d0-b13c2cd0cb47',
    '18dbb09f-5c77-4bd6-976a-3d7700f931ee',
    '910c336b-ebfa-4f9e-aadf-c23fe4f491f6',
    'b5aaecd6-40e8-4af4-97bf-2b5490b8d561',
    'f92ba237-b794-4804-8df8-5755693f2f2b',
    '894766bb-b26d-4c86-891b-3e23a6957c6d');

DELETE FROM entitlement.app_user WHERE user_id IN (
    'ceca53af-52d1-40dd-ae1c-00fd6392ebbc',
    '6e961609-adc1-4b32-9219-d3616aa27631',
    '4b8102de-0941-4276-95d0-b13c2cd0cb47',
    '18dbb09f-5c77-4bd6-976a-3d7700f931ee',
    '910c336b-ebfa-4f9e-aadf-c23fe4f491f6',
    'b5aaecd6-40e8-4af4-97bf-2b5490b8d561',
    'f92ba237-b794-4804-8df8-5755693f2f2b',
    '894766bb-b26d-4c86-891b-3e23a6957c6d');

DELETE FROM entitlement.app_role r
WHERE r.role_key IN ('BenefitsSpecialist', 'Management', 'ReportingSpecialist', 'ITAdmin')
  AND NOT EXISTS (SELECT 1 FROM entitlement.role_assignment a WHERE a.role_id = r.role_id);

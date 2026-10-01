-- Run against the existing Entitlements database after 001_entitlement_schema.sql.
-- Password format: PBKDF2-HMAC-SHA256, 600000 iterations, 16-byte salt, 32-byte hash.
BEGIN;
CREATE TABLE IF NOT EXISTS entitlement.user_credential (
    user_id uuid PRIMARY KEY REFERENCES entitlement.app_user(user_id),
    username varchar(320) NOT NULL UNIQUE
        CHECK (username = lower(btrim(username)) AND length(username) > 0),
    password_salt bytea NOT NULL CHECK (octet_length(password_salt) = 16),
    password_hash bytea NOT NULL CHECK (octet_length(password_hash) = 32)
);
COMMIT;

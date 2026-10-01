-- Passwords are application-generated PBKDF2 hashes; no credentials are seeded.
CREATE TABLE entitlement.user_credential (
    user_id uuid PRIMARY KEY REFERENCES entitlement.app_user(user_id),
    username varchar(320) NOT NULL UNIQUE
        CHECK (username = lower(btrim(username)) AND length(username) > 0),
    password_salt bytea NOT NULL CHECK (octet_length(password_salt) = 16),
    password_hash bytea NOT NULL CHECK (octet_length(password_hash) = 32)
);

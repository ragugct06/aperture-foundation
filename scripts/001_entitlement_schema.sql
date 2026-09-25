-- Run with psql connected to an existing database (for example, -d postgres).
-- Override the target with -v database_name=your_database.
-- Requires CREATEDB permission when the target database does not exist.
-- Do not use --single-transaction: CREATE DATABASE must run outside a transaction.
\set ON_ERROR_STOP on
\if :{?database_name}
\else
\set database_name aperture_entitlement_dev;
\endif

SELECT format('CREATE DATABASE %I', :'database_name')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'database_name')
\gexec

\connect :database_name

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS entitlement;

CREATE TABLE IF NOT EXISTS entitlement.app_user (
    user_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name text NOT NULL,
    last_name text NOT NULL,
    email text NOT NULL,
    status text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'suspended', 'deprovisioned')),
    context_version bigint NOT NULL DEFAULT 1
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_app_user_email
    ON entitlement.app_user (lower(email));

CREATE TABLE IF NOT EXISTS entitlement.app_role (
    role_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    role_key text NOT NULL UNIQUE,
    description text NOT NULL,
    status text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'retired')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS entitlement.role_assignment (
    assignment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES entitlement.app_user(user_id),
    role_id uuid NOT NULL REFERENCES entitlement.app_role(role_id),
    effective_from date NOT NULL,
    effective_to date,
    assigned_by text NOT NULL,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    revoked_by text,
    CONSTRAINT ck_assignment_effective_range
        CHECK (effective_to IS NULL OR effective_to > effective_from),
    CONSTRAINT ck_assignment_revocation_pair
        CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);

CREATE INDEX IF NOT EXISTS ix_role_assignment_lookup
    ON entitlement.role_assignment (user_id, role_id, effective_from);

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_role_assignment
    ON entitlement.role_assignment (user_id, role_id, effective_from)
    WHERE revoked_at IS NULL;

COMMIT;

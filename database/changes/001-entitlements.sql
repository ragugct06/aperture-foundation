-- New-database baseline. Existing tables deliberately fail instead of being
-- silently adopted. Liquibase owns transactions and migration history.
CREATE SCHEMA IF NOT EXISTS entitlement;

CREATE TABLE entitlement.app_user (
    user_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name varchar(100) NOT NULL,
    last_name varchar(100) NOT NULL,
    email varchar(320) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'suspended', 'deprovisioned')),
    context_version bigint NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX uq_app_user_email ON entitlement.app_user (lower(email));

CREATE TABLE entitlement.app_role (
    role_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    role_key varchar(100) NOT NULL,
    description varchar(500) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'retired')),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_app_role_key ON entitlement.app_role (role_key);

CREATE TABLE entitlement.role_assignment (
    assignment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES entitlement.app_user(user_id),
    role_id uuid NOT NULL REFERENCES entitlement.app_role(role_id),
    effective_from date NOT NULL,
    effective_to date,
    assigned_by varchar(200) NOT NULL,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    revoked_by varchar(200),
    CONSTRAINT ck_assignment_effective_range CHECK (effective_to IS NULL OR effective_to > effective_from),
    CONSTRAINT ck_assignment_revocation_pair CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);
CREATE INDEX ix_role_assignment_lookup ON entitlement.role_assignment (user_id, role_id, effective_from);
CREATE INDEX ix_role_assignment_role_id ON entitlement.role_assignment (role_id);
CREATE UNIQUE INDEX uq_active_role_assignment ON entitlement.role_assignment (user_id, role_id, effective_from)
    WHERE revoked_at IS NULL;

CREATE TABLE entitlement.entitlement_outbox (
    event_id uuid PRIMARY KEY,
    event_type varchar(100) NOT NULL,
    user_id uuid NOT NULL,
    payload_json jsonb NOT NULL,
    occurred_at timestamptz NOT NULL,
    published_at timestamptz
);
CREATE INDEX ix_entitlement_outbox_pending ON entitlement.entitlement_outbox (published_at, occurred_at);

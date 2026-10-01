-- Preserve the schema because CREATE SCHEMA IF NOT EXISTS may reuse an existing one.
-- Table drops also remove their indexes and constraints.
DROP TABLE entitlement.entitlement_outbox;
DROP TABLE entitlement.role_assignment;
DROP TABLE entitlement.app_role;
DROP TABLE entitlement.app_user;

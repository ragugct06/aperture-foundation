DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'aperture_entitlement_runtime') THEN
        CREATE ROLE aperture_entitlement_runtime NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'aperture_entitlement_migrator') THEN
        CREATE ROLE aperture_entitlement_migrator NOLOGIN;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA entitlement TO aperture_entitlement_runtime;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA entitlement
    TO aperture_entitlement_runtime;
REVOKE DELETE ON entitlement.app_user,
                 entitlement.role_assignment
    FROM aperture_entitlement_runtime;

GRANT USAGE, CREATE ON SCHEMA entitlement TO aperture_entitlement_migrator;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA entitlement
    TO aperture_entitlement_migrator;

ALTER DEFAULT PRIVILEGES IN SCHEMA entitlement
    GRANT SELECT, INSERT, UPDATE ON TABLES TO aperture_entitlement_runtime;

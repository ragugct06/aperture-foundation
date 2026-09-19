INSERT INTO entitlement.app_role (role_key, description)
VALUES
    ('Admin', 'Entitlement administrator'),
    ('ClaimsSpecialist', 'Copay claims specialist'),
    ('ProgramManager', 'Therapy program manager'),
    ('CashPosting', 'Cash posting operator')
ON CONFLICT (role_key) DO UPDATE
    SET description = EXCLUDED.description;

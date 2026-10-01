-- Reference data only. User/admin assignments remain an operational action.
INSERT INTO entitlement.app_role (role_key, description)
VALUES
    ('Admin', 'Entitlement administrator'),
    ('ClaimsSpecialist', 'Copay claims specialist'),
    ('ProgramManager', 'Therapy program manager'),
    ('CashPosting', 'Cash posting operator');

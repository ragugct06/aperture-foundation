-- Reference data only. User/admin assignments remain an operational action.
INSERT INTO entitlement.app_role (role_key, description)
VALUES
    ('Admin', 'Entitlement administrator'),
    ('ClaimsSpecialist', 'Copay claims specialist'),
    ('ProgramManager', 'Therapy program manager'),
    ('CashPosting', 'Cash posting operator'),
    ('BenefitsSpecialist', 'Confirms program eligibility and registers patients'),
    ('Management', 'Manages the specialist teams, sets up users and completes all transaction types'),
    ('ReportingSpecialist', 'Generates reports'),
    ('ITAdmin', 'Manages system functionality and configuration');

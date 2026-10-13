-- Assigned roles must have their assignments removed before rolling back this seed.
DELETE FROM entitlement.app_role
WHERE role_key IN ('Admin', 'ClaimsSpecialist', 'ProgramManager', 'CashPosting',
    'BenefitsSpecialist', 'Management', 'ReportingSpecialist', 'ITAdmin');

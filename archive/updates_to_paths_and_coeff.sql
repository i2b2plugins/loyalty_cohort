/* FIXES TO _paths and _coeff tables for making joining to the table more consistent with the cohort table's variable names */

UPDATE DBO.xref_LoyaltyCode_paths
SET Feature_name = 'FecalOccultTest'
WHERE Feature_name = 'Fecal occult blood test'

UPDATE DBO.xref_LoyaltyCode_paths
SET Feature_name = 'FluShot'
WHERE Feature_name = 'Flu shot'

UPDATE DBO.xref_LoyaltyCode_paths
SET Feature_name = 'MedicalExam'
WHERE Feature_name = 'Medical Exam'

UPDATE DBO.xref_LoyaltyCode_paths
SET Feature_name = 'PapTest'
WHERE Feature_name = 'Pap test'

UPDATE DBO.xref_LoyaltyCode_paths
SET Feature_name = 'PneumococcalVaccine'
WHERE Feature_name = 'Pneumococcal vaccine'

UPDATE DBO.xref_LoyaltyCode_paths
SET Feature_name = 'PSATest'
WHERE Feature_name = 'PSA Test'

update DBO.xref_LoyaltyCode_PSCoeff
set field_name = 'Num_DX1'
where UPPER(field_name) = 'NUM_DX1'

update DBO.xref_LoyaltyCode_PSCoeff
set field_name = 'Num_DX2'
where UPPER(field_name) = 'NUM_DX2'



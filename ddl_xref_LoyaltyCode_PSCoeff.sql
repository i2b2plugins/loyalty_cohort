DROP TABLE IF EXISTS XREF_LoyaltyCode_PSCoeff
GO

CREATE TABLE XREF_LoyaltyCode_PSCoeff (
  FIELD_NAME VARCHAR(50),
  COEFF NUMERIC(4,3)
)

INSERT INTO XREF_LoyaltyCode_PSCoeff (FIELD_NAME, COEFF)
VALUES ('MDVisit_pname2',0.049)
,('MDVisit_pname3',0.087)
,('MedicalExam',0.078)
,('Mammography',0.075)
,('PapTest',0.009)
,('PSATest',0.103)
,('Colonoscopy',0.064)
,('FecalOccultTest',0.034)
,('FluShot',0.102)
,('PneumococcalVaccine',0.031)
,('BMI',0.017)
,('A1C',0.018)
,('meduse1',0.002)
,('meduse2',0.074)
,('INP1_OPT1_Visit',0.091)
,('OPT2_Visit',0.050)
,('Num_Dx1',-0.026)
,('NUM_DX2',0.037)
,('ED_Visit',0.078)
,('Routine_Care_2',0.049);
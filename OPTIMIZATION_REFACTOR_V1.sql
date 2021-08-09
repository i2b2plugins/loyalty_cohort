IF OBJECT_ID(N'DBO.usp_LoyaltyCohort_opt') IS NOT NULL DROP PROCEDURE DBO.usp_LoyaltyCohort_opt
GO

CREATE PROC DBO.usp_LoyaltyCohort_opt
    @indexDate datetime
AS

/* 
   CHECK ANY CUSTOM LOCAL CODES ADDED TO xref_LoyaltyCode_paths AT <PE.1> AND <PE.2> - PLEASE SEE COMMENTS
*/

SET NOCOUNT ON
SET XACT_ABORT ON

/* UNCOMMENT IF TESTING PROC BODY ALONE */
--DECLARE @indexDate DATE='20210201'

IF OBJECT_ID(N'tempdb..#NONDEMCONCEPT', N'U') IS NOT NULL DROP TABLE #NONDEMCONCEPT;
IF OBJECT_ID(N'tempdb..#cohort', N'U') IS NOT NULL DROP TABLE #cohort;
IF OBJECT_ID(N'tempdb..#cohort_agegrp', N'U') IS NOT NULL DROP TABLE #cohort_agegrp;
IF OBJECT_ID(N'tempdb..#COHORT_CHARLSON', N'U') IS NOT NULL DROP TABLE #COHORT_CHARLSON;
IF OBJECT_ID(N'tempdb..#CHARLSON_STATS', N'U') IS NOT NULL DROP TABLE #CHARLSON_STATS;
IF OBJECT_ID(N'DBO.loyalty_dev_summary', N'U') IS NOT NULL DROP TABLE DBO.loyalty_dev_summary;

DECLARE @STARTTS DATETIME = GETDATE()
DECLARE @STEPTTS DATETIME 
DECLARE @ENDRUNTIMEms INT, @STEPRUNTIMEms INT
DECLARE @ROWS INT

SELECT DISTINCT CONCEPT_CD
INTO #NONDEMCONCEPT
FROM CONCEPT_DIMENSION
WHERE CONCEPT_PATH NOT LIKE '\ACT\Demographics%'
/* ANY NUMBER OF PATHS COULD BE ADDED HERE TO EXCLUDE FROM THE CHECK FOR "FACTS SINCE 2012" IN THE VISIT PULL */

CREATE TABLE #cohort (
patient_num INT NOT NULL PRIMARY KEY,
age int null,
Num_Dx1 bit not null DEFAULT 0,
Num_Dx2 bit not null DEFAULT 0,
MedUse1 bit not null DEFAULT 0,
MedUse2 bit not null DEFAULT 0,
Mammography bit not null DEFAULT 0,
PapTest bit not null DEFAULT 0,
PSATest bit not null DEFAULT 0,
Colonoscopy bit not null DEFAULT 0,
FecalOccultTest bit not null DEFAULT 0,
FluShot bit not null DEFAULT 0,
PneumococcalVaccine bit not null DEFAULT 0,
BMI bit not null DEFAULT 0,
A1C bit not null DEFAULT 0,
MedicalExam bit not null DEFAULT 0,
INP1_OPT1_Visit bit not null DEFAULT 0,
OPT2_Visit bit not null DEFAULT 0,
ED_Visit bit not null DEFAULT 0,
MDVisit_pname2 bit not null DEFAULT 0,
MDVisit_pname3 bit not null DEFAULT 0,
Routine_Care_2 bit not null DEFAULT 0,
Predicted_score FLOAT not null DEFAULT 0
)

/* EXTRACT COHORT AND VISIT TYPE FLAGS */
SET @STEPTTS = GETDATE()

;WITH VISITTYPE AS (
select distinct feature_name, c_basecode
    from NCATS_VISIT_DETAILS N,
    (select distinct feature_name, act_path 
        from [DBO].[xref_LoyaltyCode_paths]
        where [code_type] = 'visit' and feature_name in ('inpatient encounter','outpatient encounter','ED encounter')
        and act_path is not null) X
      where X.ACT_PATH like N.C_FULLNAME+'%'
      and C_BASECODE is not null
)
INSERT INTO #COHORT (PATIENT_NUM, AGE, INP1_OPT1_Visit, OPT2_Visit, ED_Visit)
SELECT V.PATIENT_NUM
    , FLOOR(DATEDIFF(DD,BIRTH_DATE,@indexDate)/365.25) AS AGE
    , CAST(MAX(CASE WHEN VT.feature_name = 'inpatient encounter' THEN 1 ELSE 0 END) AS BIT) | CAST(MAX(CASE WHEN VT.feature_name = 'outpatient encounter' THEN 1 ELSE 0 END) AS BIT) INP1_OPT1_VISIT
    , CASE WHEN COUNT(DISTINCT CASE WHEN VT.feature_name = 'outpatient encounter' THEN CONVERT(DATE,V.START_DATE) ELSE NULL END) >= 2 THEN 1 ELSE 0 END AS OPT2_VISIT
    , MAX(CASE WHEN VT.feature_name = 'ED encounter' THEN 1 ELSE 0 END) ED_VISIT
FROM VISIT_DIMENSION V
  JOIN PATIENT_DIMENSION P
    ON V.PATIENT_NUM = P.PATIENT_NUM
  JOIN (SELECT DISTINCT PATIENT_NUM FROM OBSERVATION_FACT O,#NONDEMCONCEPT C WHERE O.CONCEPT_CD = C.CONCEPT_CD AND CONVERT(DATE,O.START_DATE) >= '20120101') NONDEMFACT /* AT LEAST ONE NON-DEMOGRAPHIC FACT AFTER 2012 */
    ON V.PATIENT_NUM = NONDEMFACT.PATIENT_NUM
  LEFT JOIN VISITTYPE VT
    ON V.INOUT_CD = VT.C_BASECODE 
      AND CONVERT(DATE,V.START_DATE) >= dateadd(YY,-1, @indexDate) AND CONVERT(DATE,V.START_DATE) < @indexDate
      /* RESTRICT LEFT JOIN TO VISIT TYPE ON LAST YEAR OF VISITS FOR NUMERATOR OF THOSE THREE VARIABLES 
         REST OF THE VISITS WILL HAVE NULL AND GET CONVERTED TO 0 IN MAX(CASE STATEMENTS ABOVE 
         SO WE WILL STILL GET RECORDS FROM 2012-2019 WITH 0,0,0 FOR THE THREE FLAGS WE'RE MAKING IF
         THAT PATIENT NEVER HAD A VISIT IN THE YEAR BEFORE THE INDEX DATE */
WHERE P.BIRTH_DATE IS NOT NULL /* ENSURE BIRTH_DATE IS NOT NULL FOR SUMMARY TABLE ISSUES LATER */
  --AND EXISTS (SELECT 1 FROM OBSERVATION_FACT WHERE PATIENT_NUM = P.PATIENT_NUM AND CONVERT(DATE,START_DATE) >= '20120101' AND CONCEPT_CD NOT LIKE 'DEM|%') /* AT LEAST ONE NON-DEMOGRAPHIC FACT AFTER 2012 */
  AND (CONVERT(DATE,V.START_DATE) >= '20120101' AND CONVERT(DATE,V.START_DATE) < @indexDate)
GROUP BY V.PATIENT_NUM, FLOOR(DATEDIFF(DD,BIRTH_DATE,@indexDate)/365.25)

SELECT @ROWS=@@ROWCOUNT,@ENDRUNTIMEms = DATEDIFF(MILLISECOND,@STARTTS,GETDATE()),@STEPRUNTIMEms = DATEDIFF(MILLISECOND,@STEPTTS,GETDATE())
RAISERROR(N'Cohort and Visit Type variables - Rows: %d - Total Execution (ms): %d - Step Runtime (ms): %d', 1, 1, @ROWS, @ENDRUNTIMEms, @STEPRUNTIMEms) with nowait;

/* COHORT FLAGS SANS Num_Dx and MedUse */
SET @STEPTTS = GETDATE()

;WITH CTE_PARAMS AS (
select distinct Feature_name, concept_cd, code_type --[ACT_PATH], 
from DBO.xref_LoyaltyCode_paths L, CONCEPT_DIMENSION c
where C.CONCEPT_PATH like L.Act_path+'%'  --jgk: must support local children
AND code_type IN ('DX','PX','lab','SITE') /* <PE.1> IF YOUR SITE IS MANAGING ANY SITE SPECIFIC CODES FOR THE FOLLOWING DOMAINS SET THEIR CODE_TYPE = 'SITE' IN dbo.xref_LoyaltyCode_paths </PE.1> */
and (act_path <> '**Not Found' and act_path is not null)
)
UPDATE #COHORT
SET MDVisit_pname2       = CF.MDVisit_pname2
, MDVisit_pname3         = CF.MDVisit_pname3
, Mammography            = CF.Mammography
, BMI                    = CF.BMI
, FluShot                = CF.FluShot
, PneumococcalVaccine    = CF.PneumococcalVaccine
, MedicalExam            = CF.MedicalExam
, FecalOccultTest        = CF.FecalOccultTest
, Paptest                = CF.Paptest
, Colonoscopy            = CF.Colonoscopy
, PSATest                = CF.PSATest
, A1C                    = CF.A1C
, Routine_Care_2         = CF.Routine_Care_2
FROM #COHORT C,
(
  SELECT PATIENT_NUM, MDVisit_pname2, MDVisit_pname3, Mammography, BMI, FluShot, PneumococcalVaccine, MedicalExam, FecalOccultTest, Paptest, Colonoscopy, PSATest, A1C
    , CASE WHEN (MedicalExam+Mammography+PSATest+Colonoscopy+FecalOccultTest+FluShot+PneumococcalVaccine+A1C+BMI)>=2 THEN 1 ELSE 0 END AS Routine_Care_2
  FROM (
    SELECT PATIENT_NUM, MAX(MDVisit_pname2) as MDVisit_pname2, MAX(MDVisit_pname3) as MDVisit_pname3, MAX(Mammography) as Mammography, MAX(BMI) as BMI, MAX(FluShot) as FluShot
    , MAX(PneumococcalVaccine) as PneumococcalVaccine, MAX(MedicalExam) as MedicalExam, MAX(FecalOccultTest) as FecalOccultTest, MAX(Paptest) as Paptest, MAX(Colonoscopy) as Colonoscopy
    , MAX(PSATest) as PSATest, MAX(A1C) as A1C
    FROM (
      SELECT O.PATIENT_NUM
      , CASE WHEN COUNT(DISTINCT CASE WHEN P.code_type = 'PX' AND (O.PROVIDER_ID is not null and O.provider_id <> '' and O.provider_id <> '@') THEN CONVERT(DATE,O.START_DATE) ELSE NULL END)  = 2 THEN 1 ELSE 0 END AS MDVisit_pname2
      , CASE WHEN COUNT(DISTINCT CASE WHEN P.code_type = 'PX' AND (O.PROVIDER_ID is not null and O.provider_id <> '' and O.provider_id <> '@') THEN CONVERT(DATE,O.START_DATE) ELSE NULL END)  > 2 THEN 1 ELSE 0 END AS MDVisit_pname3
      , MAX(CASE WHEN P.Feature_name = 'Mammography' THEN 1 ELSE 0 END) AS Mammography
      , MAX(CASE WHEN P.Feature_name = 'BMI' THEN 1 ELSE 0 END) AS BMI
      , MAX(CASE WHEN P.Feature_name = 'Flu Shot' THEN 1 ELSE 0 END) AS FluShot
      , MAX(CASE WHEN P.Feature_name = 'Pneumococcal vaccine' THEN 1 ELSE 0 END) AS PneumococcalVaccine
      , MAX(CASE WHEN P.Feature_name = 'Medical Exam' THEN 1 ELSE 0 END) AS MedicalExam
      , MAX(CASE WHEN P.Feature_name = 'Fecal occult blood test' THEN 1 ELSE 0 END) AS FecalOccultTest
      , MAX(CASE WHEN P.Feature_name = 'Pap test' THEN 1 ELSE 0 END) AS Paptest
      , MAX(CASE WHEN P.Feature_name = 'Colonoscopy' THEN 1 ELSE 0 END) AS Colonoscopy
      , MAX(CASE WHEN P.Feature_name = 'PSA Test' THEN 1 ELSE 0 END) AS PSATest
      , MAX(CASE WHEN P.Feature_name = 'A1C' THEN 1 ELSE 0 END) AS A1C
      from OBSERVATION_FACT o, CTE_PARAMS p
      where o.CONCEPT_CD = p.CONCEPT_CD
      AND o.START_DATE >=  dateadd(yy,-1, @indexDate)
      AND o.START_DATE < @indexDate
      GROUP BY O.PATIENT_NUM, O.PROVIDER_ID /* AGG AT PROVIDER_ID FIRST LEVEL FOR THE MDVisit_pname VARIABLES */
    )PA /* PROVIDER GRAIN AGG->BASELINE -- AGG AT PATIENT_NUM GRAIN */
    GROUP BY PA.PATIENT_NUM
  )BL /* BASELINE COLLECTED FOR ALL DOMAINS */
)CF /* COHORT FLAGS INCLUDED ROUTINE_CARE_2 */
WHERE C.PATIENT_NUM = CF.PATIENT_NUM;

SELECT @ROWS=@@ROWCOUNT,@ENDRUNTIMEms = DATEDIFF(MILLISECOND,@STARTTS,GETDATE()),@STEPRUNTIMEms = DATEDIFF(MILLISECOND,@STEPTTS,GETDATE())
RAISERROR(N'Cohort Flags (first pass) - Rows: %d - Total Execution (ms): %d  - Step Runtime (ms): %d', 1, 1, @ROWS, @ENDRUNTIMEms, @STEPRUNTIMEms) with nowait;

/* Num_Dx1, Num_Dx2, MedUse1, MedUse2 */
SET @STEPTTS = GETDATE()

;with DxCodes as (
Select distinct concept_cd
from ACT_ICD10CM_DX_2018AA d, concept_dimension c
where d.C_FULLNAME = C.CONCEPT_PATH
  and (c_basecode is not null and c_basecode <> '')
UNION
Select distinct concept_cd 
from ACT_ICD9CM_DX_2018AA d, concept_dimension c
where d.C_FULLNAME = C.CONCEPT_PATH
  and (c_basecode is not null and c_basecode <> '')
UNION
/* <PE.2> Check that this subquery returns the concept codes your site added to 
  xref_LoyaltyCode_paths are returned correctly */
Select distinct c.concept_cd
from CONCEPT_DIMENSION c, DBO.xref_LoyaltyCode_paths x 
where c.CONCEPT_PATH LIKE x.ACT_PATH+'%'  ----- > This block of code handles any local dx codes
  and (NULLIF(c.CONCEPT_CD,'') is not null)
  and (NULLIF(x.SiteSpecificCode,'') is not null)
  and x.[code_type] = 'DX'
/* </PE.2> */
)
, MedCodes as (
Select  distinct c_basecode as CONCEPT_CD
from ACT_MED_VA_V2_092818
where c_basecode is not null and c_basecode  <> ''
UNION
select  distinct c_basecode  as CONCEPT_CD 
from ACT_MED_ALPHA_V2_121318
where c_basecode is not null and c_basecode <> ''
)
, CTE_CATGRY AS (
SELECT DISTINCT 'DX' AS CATGRY, CONCEPT_CD
FROM DxCodes
WHERE CHARINDEX(':',CONCEPT_CD) > 0
UNION ALL
SELECT DISTINCT 'MED' AS CATGRY, CONCEPT_CD
FROM MedCodes
WHERE CHARINDEX(':',CONCEPT_CD) > 0
)
, CTE_CNTDSVCDT_VARS AS (
  SELECT PATIENT_NUM
    , MAX(CASE WHEN CATGRY = 'DX' AND CATCNT > 0 THEN 1 ELSE 0 END  ) AS Num_Dx1 
    , MAX(CASE WHEN CATGRY = 'DX' AND CATCNT > 1 THEN 1 ELSE 0 END  ) AS Num_Dx2
    , MAX(CASE WHEN CATGRY = 'MED' AND CATCNT > 0 THEN 1 ELSE 0 END ) AS MedUse1
    , MAX(CASE WHEN CATGRY = 'MED' AND CATCNT > 1 THEN 1 ELSE 0 END ) AS MedUse2
  FROM (
  SELECT O.PATIENT_NUM, P.CATGRY
    , COUNT(DISTINCT CONVERT(DATE,O.START_DATE)) AS CATCNT
  FROM OBSERVATION_FACT O, CTE_CATGRY p
        where o.CONCEPT_CD = P.CONCEPT_CD
        AND o.START_DATE >=  dateadd(yy,-1, @indexDate)
        AND o.START_DATE < @indexDate
  GROUP BY O.PATIENT_NUM, P.CATGRY
  )CA
  GROUP BY CA.PATIENT_NUM
)
UPDATE #cohort
SET Num_Dx1 = CSD.Num_Dx1,
  Num_Dx2 = CSD.Num_Dx2,
  MedUse1 = CSD.MedUse1,
  MedUse2 = CSD.MedUse2
FROM #cohort C, CTE_CNTDSVCDT_VARS CSD
WHERE C.PATIENT_NUM = CSD.PATIENT_NUM;

SELECT @ROWS=@@ROWCOUNT,@ENDRUNTIMEms = DATEDIFF(MILLISECOND,@STARTTS,GETDATE()),@STEPRUNTIMEms = DATEDIFF(MILLISECOND,@STEPTTS,GETDATE())
RAISERROR(N'Num_Dx and MedUse flags - Rows: %d - Total Execution (ms): %d - Step Runtime (ms): %d', 1, 1, @ROWS, @ENDRUNTIMEms, @STEPRUNTIMEms) with nowait;

/* Predicated Score Calculation v2*/
SET @STEPTTS = GETDATE()

UPDATE #cohort
SET Predicted_score = PS.Predicted_score
FROM #cohort C,
(
SELECT PATIENT_NUM, -0.010+(p.MDVisit_pname2*CAST(c.MDVisit_pname2 AS INT))+(p.MDVisit_pname3*CAST(c.MDVisit_pname3 AS INT))+(p.MedicalExam*CAST(C.MedicalExam AS INT))
  +(p.Mammography*CAST(c.Mammography AS INT))+(p.PapTest*CAST(c.PapTest as INT))+(p.PSATest*CAST(c.PSATest AS INT))+(p.Colonoscopy*CAST(c.Colonoscopy AS INT))
  +(p.FecalOccultTest*CAST(c.FecalOccultTest AS INT))+(p.FluShot*CAST(c.FluShot AS INT))+(p.PneumococcalVaccine*CAST(c.PneumococcalVaccine AS INT))
  +(p.BMI*CAST(c.BMI AS INT))+(p.A1C*CAST(c.A1C as INT))+(p.MedUse1*CAST(c.MedUse1 AS INT))+(p.MedUse2*CAST(c.MedUse2 AS INT))+(p.INP1_OPT1_Visit*CAST(c.INP1_OPT1_Visit AS INT))
  +(p.OPT2_Visit*CAST(c.OPT2_Visit AS INT))+(p.ED_Visit*CAST(c.ED_Visit AS INT))+(p.Num_Dx1*CAST(c.Num_Dx1 AS INT))
  +(p.Num_Dx2*CAST(c.Num_Dx2 AS INT))+(p.Routine_Care_2*CAST(c.Routine_Care_2 AS INT))
  AS Predicted_score
FROM (
select FIELD_NAME, COEFF
from xref_LoyaltyCode_PSCoeff
)U
PIVOT /* ORACLE EQUIV : https://www.oracletutorial.com/oracle-basics/oracle-unpivot/ */
(MAX(COEFF) for FIELD_NAME in (MDVisit_pname2, MDVisit_pname3, MedicalExam, Mammography, PapTest, PSATest, Colonoscopy, FecalOccultTest, FluShot, PneumococcalVaccine
  , BMI, A1C, MedUse1, MedUse2, INP1_OPT1_Visit, OPT2_Visit, Num_Dx1, Num_Dx2, ED_Visit, Routine_Care_2))p, #COHORT c
)PS
WHERE C.PATIENT_NUM = PS.PATIENT_NUM;

SELECT @ROWS=@@ROWCOUNT,@ENDRUNTIMEms = DATEDIFF(MILLISECOND,@STARTTS,GETDATE()),@STEPRUNTIMEms = DATEDIFF(MILLISECOND,@STEPTTS,GETDATE())
RAISERROR(N'Predicated Score v2 - Rows: %d - Total Execution (ms): %d  - Step Runtime (ms): %d', 1, 1, @ROWS, @ENDRUNTIMEms, @STEPRUNTIMEms) with nowait;

/* OPTIONAL CHARLSON COMORBIDITY INDEX -- ADDS APPROX. 1m in UKY environment. 
   REQUIRES SITE TO LOAD LU_CHARLSON FROM REPO 
*/
--SET @STEPTTS = GETDATE()

--;WITH CTE_VISIT_BASE AS (
--SELECT PATIENT_NUM, AGE, LAST_DATE
--  , CASE  WHEN AGE < 50 THEN 0
--          WHEN AGE BETWEEN 50 AND 59 THEN 1
--          WHEN AGE BETWEEN 60 AND 69 THEN 2
--          WHEN AGE >= 70 THEN 3 END AS CHARLSON_AGE_BASE
--FROM (
--SELECT V.PATIENT_NUM
--  , FLOOR(DATEDIFF(DD,P.BIRTH_DATE,@indexDate)/365.25) AS AGE
--  , MAX(CONVERT(DATE,V.START_DATE)) LAST_DATE
--FROM ACT.VISIT_DIMENSION V 
--  JOIN ACT.PATIENT_DIMENSION P
--    ON V.PATIENT_NUM = P.PATIENT_NUM
--WHERE CONVERT(DATE,V.START_DATE) >= DATEADD(MM,-12,@indexDate) AND CONVERT(DATE,V.START_DATE) < @indexDate
--  AND P.BIRTH_DATE IS NOT NULL
--  AND EXISTS (SELECT 1 FROM OBSERVATION_FACT WHERE PATIENT_NUM = P.PATIENT_NUM AND CONVERT(DATE,START_DATE) > '20120101' AND CONCEPT_CD NOT LIKE 'DEM|%')
--GROUP BY V.PATIENT_NUM, FLOOR(DATEDIFF(DD,P.BIRTH_DATE,@indexDate)/365.25)
--) VISITS
--)
--SELECT PATIENT_NUM
--  , LAST_DATE
--  , AGE
--  , CAST(case when AGE < 65 then 'Under 65' 
--     when age>=65           then 'Over 65' else '-' end AS VARCHAR(20)) AS AGEGRP
--  , CHARLSON_INDEX
--  , POWER( 0.983
--      , POWER(2.71828, (CASE WHEN CHARLSON_INDEX > 7 THEN 7 ELSE CHARLSON_INDEX END) * 0.9)
--      ) * 100.0 AS CHARLSON_10YR_SURVIVAL_PROB
--  , MI, CHF, CVD, PVD, DEMENTIA, COPD, RHEUMDIS, PEPULCER, MILDLIVDIS, DIABETES_NOCC, DIABETES_WTCC, HEMIPARAPLEG, RENALDIS, CANCER, MSVLIVDIS, METASTATIC, AIDSHIV
--INTO #COHORT_CHARLSON
--FROM (
--SELECT PATIENT_NUM, LAST_DATE, AGE
--  , CHARLSON_AGE_BASE
--      + MI + CHF + CVD + PVD + DEMENTIA + COPD + RHEUMDIS + PEPULCER 
--      + (CASE WHEN MSVLIVDIS > 0 THEN 0 ELSE MILDLIVDIS END)
--      + (CASE WHEN DIABETES_WTCC > 0 THEN 0 ELSE DIABETES_NOCC END)
--      + DIABETES_WTCC + HEMIPARAPLEG + RENALDIS + CANCER + MSVLIVDIS + METASTATIC + AIDSHIV AS CHARLSON_INDEX
--  , MI, CHF, CVD, PVD, DEMENTIA, COPD, RHEUMDIS, PEPULCER, MILDLIVDIS, DIABETES_NOCC, DIABETES_WTCC, HEMIPARAPLEG, RENALDIS, CANCER, MSVLIVDIS, METASTATIC, AIDSHIV
--FROM (
--SELECT PATIENT_NUM, AGE, LAST_DATE, CHARLSON_AGE_BASE
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'MI'            THEN CHARLSON_WT ELSE 0 END) AS MI
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'CHF'           THEN CHARLSON_WT ELSE 0 END) AS CHF
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'CVD'           THEN CHARLSON_WT ELSE 0 END) AS CVD
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'PVD'           THEN CHARLSON_WT ELSE 0 END) AS PVD
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'DEMENTIA'      THEN CHARLSON_WT ELSE 0 END) AS DEMENTIA
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'COPD'          THEN CHARLSON_WT ELSE 0 END) AS COPD
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'RHEUMDIS'      THEN CHARLSON_WT ELSE 0 END) AS RHEUMDIS
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'PEPULCER'      THEN CHARLSON_WT ELSE 0 END) AS PEPULCER
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'MILDLIVDIS'    THEN CHARLSON_WT ELSE 0 END) AS MILDLIVDIS
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'DIABETES_NOCC' THEN CHARLSON_WT ELSE 0 END) AS DIABETES_NOCC
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'DIABETES_WTCC' THEN CHARLSON_WT ELSE 0 END) AS DIABETES_WTCC
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'HEMIPARAPLEG'  THEN CHARLSON_WT ELSE 0 END) AS HEMIPARAPLEG
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'RENALDIS'      THEN CHARLSON_WT ELSE 0 END) AS RENALDIS
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'CANCER'        THEN CHARLSON_WT ELSE 0 END) AS CANCER
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'MSVLIVDIS'     THEN CHARLSON_WT ELSE 0 END) AS MSVLIVDIS
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'METASTATIC'    THEN CHARLSON_WT ELSE 0 END) AS METASTATIC
--  , MAX(CASE WHEN CHARLSON_CATGRY = 'AIDSHIV'       THEN CHARLSON_WT ELSE 0 END) AS AIDSHIV
--FROM (
--  /* FOR EACH VISIT - PULL PREVIOUS YEAR OF DIAGNOSIS FACTS JOINED TO CHARLSON CATEGORIES - EXTRACTING CHARLSON CATGRY/WT */
--  SELECT V.PATIENT_NUM, V.AGE, V.LAST_DATE, V.CHARLSON_AGE_BASE, C.CHARLSON_CATGRY, C.CHARLSON_WT
--  FROM CTE_VISIT_BASE V
--    JOIN OBSERVATION_FACT F
--      ON V.PATIENT_NUM = F.PATIENT_NUM
--      AND F.START_DATE BETWEEN DATEADD(YY,-1,V.LAST_DATE) AND V.LAST_DATE
--    JOIN LU_CHARLSON C
--      ON F.CONCEPT_CD LIKE DIAGPATTERN
--  GROUP BY V.PATIENT_NUM, V.AGE, V.LAST_DATE, CHARLSON_AGE_BASE, C.CHARLSON_CATGRY, C.CHARLSON_WT
--  UNION /* IF NO CHARLSON DX FOUND IN ABOVE INNER JOINS WE CAN UNION TO JUST THE ENCOUNTER+AGE_BASE RECORD WITH CHARLSON FIELDS NULLED OUT
--           THIS IS MORE PERFORMANT (SHORTCUT) THAN A LEFT JOIN IN THE OBSERVATION-CHARLSON JOIN ABOVE */
--  SELECT V2.PATIENT_NUM, V2.AGE, V2.LAST_DATE, V2.CHARLSON_AGE_BASE, NULL, NULL
--  FROM CTE_VISIT_BASE V2
--  )DXU
--  GROUP BY PATIENT_NUM, AGE, LAST_DATE, CHARLSON_AGE_BASE
--)cci
--)ccisum

--SELECT @ROWS=@@ROWCOUNT,@ENDRUNTIMEms = DATEDIFF(MILLISECOND,@STARTTS,GETDATE()),@STEPRUNTIMEms = DATEDIFF(MILLISECOND,@STEPTTS,GETDATE())
--RAISERROR(N'Charlson Index and weighted flags - Rows: %d - Total Execution (ms): %d  - Step Runtime (ms): %d', 1, 1, @ROWS, @ENDRUNTIMEms, @STEPRUNTIMEms) with nowait;

--/* CHARLSON 10YR PROB MEDIAN/MEAN/MODE/STDEV */
--SET @STEPTTS = GETDATE()

--;WITH CTE_MODE AS (
--SELECT ISNULL(A.AGEGRP,'All Patients') AGEGRP
--  , CHARLSON_10YR_SURVIVAL_PROB
--  , RANK() OVER (PARTITION BY ISNULL(A.AGEGRP,'All Patients') ORDER BY N DESC) MR_AG
--FROM (
--SELECT AGEGRP, CHARLSON_10YR_SURVIVAL_PROB, COUNT(*) N
--FROM #COHORT_CHARLSON
--GROUP BY GROUPING SETS ((AGEGRP, CHARLSON_10YR_SURVIVAL_PROB),(CHARLSON_10YR_SURVIVAL_PROB))
--)A
--GROUP BY ISNULL(A.AGEGRP,'All Patients'), CHARLSON_10YR_SURVIVAL_PROB, N
--)
--, CTE_MEAN_STDEV_MODE AS (
--SELECT ISNULL(GS.AGEGRP,'All Patients') AGEGRP, MEAN_10YRPROB, STDEV_10YRPROB
--  , (SELECT CHARLSON_10YR_SURVIVAL_PROB FROM CTE_MODE WHERE AGEGRP = ISNULL(GS.AGEGRP,'All Patients') AND (MR_AG = 1)) AS MODE_10YRPROB
--FROM (
--SELECT AGEGRP, AVG(CHARLSON_10YR_SURVIVAL_PROB) MEAN_10YRPROB, STDEV(CHARLSON_10YR_SURVIVAL_PROB) STDEV_10YRPROB
--FROM #COHORT_CHARLSON
--GROUP BY GROUPING SETS ((AGEGRP),())
--)GS
--)
--SELECT MS.AGEGRP
--  , MEDIAN_10YR_SURVIVAL
--  , S.MEAN_10YRPROB
--  , S.STDEV_10YRPROB
--  , S.MODE_10YRPROB
--INTO #CHARLSON_STATS
--FROM (
--SELECT AGEGRP, CHARLSON_10YR_SURVIVAL_PROB
--  , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CHARLSON_10YR_SURVIVAL_PROB) OVER (PARTITION BY AGEGRP) AS MEDIAN_10YR_SURVIVAL
--FROM #COHORT_CHARLSON
--WHERE AGEGRP != '-'
--UNION ALL
--SELECT 'All Patients' as AGEGRP, CHARLSON_10YR_SURVIVAL_PROB
--  , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CHARLSON_10YR_SURVIVAL_PROB) OVER (PARTITION BY 1) AS MEDIAN_10YR_SURVIVAL
--FROM #COHORT_CHARLSON
--WHERE AGEGRP != '-'
--)MS, CTE_MEAN_STDEV_MODE S
--WHERE MS.AGEGRP = S.AGEGRP
--GROUP BY MS.AGEGRP, MEDIAN_10YR_SURVIVAL, S.MODE_10YRPROB, S.STDEV_10YRPROB, S.MEAN_10YRPROB

--SELECT @ROWS=@@ROWCOUNT,@ENDRUNTIMEms = DATEDIFF(MILLISECOND,@STARTTS,GETDATE()),@STEPRUNTIMEms = DATEDIFF(MILLISECOND,@STEPTTS,GETDATE())
--RAISERROR(N'Charlson Stats - Rows: %d - Total Execution (ms): %d  - Step Runtime (ms): %d', 1, 1, @ROWS, @ENDRUNTIMEms, @STEPRUNTIMEms) with nowait;

/* Cohort Agegrp - Makes Predictive Score filtering easier in final step if pre-calculated */
SET @STEPTTS = GETDATE()

SELECT * 
INTO #cohort_agegrp
FROM (
select patient_num
,CAST(case when ISNULL(AGE,0)< 65 then 'Under 65' 
     when AGE>=65 then 'Over 65' else null end AS VARCHAR(20)) as AGEGRP
,Num_Dx1              AS Num_Dx1            
,Num_Dx2              AS Num_Dx2            
,MedUse1              AS MedUse1            
,MedUse2              AS MedUse2            
,Mammography          AS Mammography        
,PapTest              AS PapTest            
,PSATest              AS PSATest            
,Colonoscopy          AS Colonoscopy        
,FecalOccultTest      AS FecalOccultTest    
,FluShot              AS FluShot            
,PneumococcalVaccine  AS PneumococcalVaccine
,BMI                  AS BMI                
,A1C                  AS A1C                
,MedicalExam          AS MedicalExam        
,INP1_OPT1_Visit      AS INP1_OPT1_Visit    
,OPT2_Visit           AS OPT2_Visit         
,ED_Visit             AS ED_Visit           
,MDVisit_pname2       AS MDVisit_pname2     
,MDVisit_pname3       AS MDVisit_pname3     
,Routine_Care_2       AS Routine_Care_2     
,Predicted_score      AS Predicted_score
from #cohort
UNION 
select patient_num
,'All Patients' AS AGEGRP
,Num_Dx1              AS Num_Dx1            
,Num_Dx2              AS Num_Dx2            
,MedUse1              AS MedUse1            
,MedUse2              AS MedUse2            
,Mammography          AS Mammography        
,PapTest              AS PapTest            
,PSATest              AS PSATest            
,Colonoscopy          AS Colonoscopy        
,FecalOccultTest      AS FecalOccultTest    
,FluShot              AS FluShot            
,PneumococcalVaccine  AS PneumococcalVaccine
,BMI                  AS BMI                
,A1C                  AS A1C                
,MedicalExam          AS MedicalExam        
,INP1_OPT1_Visit      AS INP1_OPT1_Visit    
,OPT2_Visit           AS OPT2_Visit         
,ED_Visit             AS ED_Visit           
,MDVisit_pname2       AS MDVisit_pname2     
,MDVisit_pname3       AS MDVisit_pname3     
,Routine_Care_2       AS Routine_Care_2     
,Predicted_score      AS Predicted_score
from #cohort
)cag;

SELECT @ROWS=@@ROWCOUNT,@ENDRUNTIMEms = DATEDIFF(MILLISECOND,@STARTTS,GETDATE()),@STEPRUNTIMEms = DATEDIFF(MILLISECOND,@STEPTTS,GETDATE())
RAISERROR(N'Prepare #cohort_agegrp - Rows: %d - Total Execution (ms): %d  - Step Runtime (ms): %d', 1, 1, @ROWS, @ENDRUNTIMEms, @STEPRUNTIMEms) with nowait;


/* FINAL SUMMARIZATION OF RESULTS */
SET @STEPTTS = GETDATE()

;WITH CTE_PREDICTIVE AS (
SELECT AGEGRP, MIN(PREDICTED_SCORE) PredictiveScoreCutoff
FROM (
SELECT AGEGRP, Predicted_score, NTILE(5) OVER (PARTITION BY AGEGRP ORDER BY PREDICTED_SCORE DESC) AS ScoreRank
FROM(
--SELECT CAST(case when ISNULL(AGE,0)< 65 then 'Under 65' 
--     when AGE>=65           then 'Over 65' else null end AS VARCHAR(20)) as AGEGRP,
SELECT AGEGRP, predicted_score
from #cohort_agegrp
--UNION ALL
--SELECT 'All Patients' as AGEGRP, predicted_score
--from #cohort
)SCORES
)M
WHERE ScoreRank=1
GROUP BY AGEGRP
)
SELECT CUTOFF_FILTER_YN, Summary_Description, COHORTAGG.AGEGRP as tablename, TotalSubjects, Num_DX1, Num_DX2, MedUSe1, MedUse2, Mammography, PapTest, PSATest, Colonoscopy, FecalOccultTest
  , FluShot, PneumococcalVaccine, BMI, A1C, MedicalExam, INP1_OPT1_Visit, OPT2_Visit, ED_Visit, MDVisit_pname2, MDVisit_pname3, Routine_care_2, Subjects_NoCriteria, CP.PredictiveScoreCutoff
  --, CS.MEAN_10YRPROB, CS.MEDIAN_10YR_SURVIVAL, CS.MODE_10YRPROB, CS.STDEV_10YRPROB
INTO DBO.loyalty_dev_summary
FROM (
/* FILTERED BY PREDICTIVE CUTOFF */
SELECT
'Y' AS CUTOFF_FILTER_YN,
'Patient Counts' as Summary_Description,
CAG.AGEGRP, 
count(distinct patient_num) as TotalSubjects,
sum(cast([Num_Dx1] as int)) as Num_DX1,
sum(cast([Num_Dx2] as int)) as Num_DX2,
sum(cast([MedUse1] as int))  as MedUSe1,
sum(cast([MedUse2] as int)) as MedUse2,
sum(cast([Mammography] as int)) as Mammography,
sum(cast([PapTest] as int)) as PapTest,
sum(cast([PSATest] as int)) as PSATest,
sum(cast([Colonoscopy] as int)) as Colonoscopy,
sum(cast([FecalOccultTest] as int)) as FecalOccultTest,
sum(cast([FluShot] as int)) as  FluShot,
sum(cast([PneumococcalVaccine] as int)) as PneumococcalVaccine,
sum(cast([BMI] as int))  as BMI,
sum(cast([A1C] as int)) as A1C,
sum(cast([MedicalExam] as int)) as MedicalExam,
sum(cast([INP1_OPT1_Visit] as int)) as INP1_OPT1_Visit,
sum(cast([OPT2_Visit] as int)) as OPT2_Visit,
sum(cast([ED_Visit] as int))  as ED_Visit,
sum(cast([MDVisit_pname2] as int)) as MDVisit_pname2,
sum(cast([MDVisit_pname3] as int)) as MDVisit_pname3,
sum(cast([Routine_Care_2] as int)) as Routine_care_2,
SUM(CAST(~(Num_Dx1|Num_Dx2|MedUse1|Mammography|PapTest|PSATest|Colonoscopy|FecalOccultTest|FluShot|PneumococcalVaccine|BMI|
  A1C|MedicalExam|INP1_OPT1_Visit|OPT2_Visit|ED_Visit|MDVisit_pname2|MDVisit_pname3|Routine_Care_2) AS INT)) as Subjects_NoCriteria /* inverted bitwise OR of all bit flags */
from #cohort_agegrp CAG JOIN CTE_PREDICTIVE P ON CAG.AGEGRP = P.AGEGRP AND CAG.Predicted_score >= P.PredictiveScoreCutoff
group by CAG.AGEGRP
UNION ALL
SELECT
'Y' AS CUTOFF_FILTER_YN,
'PercentOfSubjects' as Summary_Description,
CAG.AGEGRP, 
count(distinct patient_num) as TotalSubjects,
100*avg(cast([Num_Dx1] as numeric(2,1))) as Num_DX1,
100*avg(cast([Num_Dx2] as numeric(2,1))) as Num_DX2,
100*avg(cast([MedUse1] as numeric(2,1)))  as MedUSe1,
100*avg(cast([MedUse2] as numeric(2,1))) as MedUse2,
100*avg(cast([Mammography] as numeric(2,1))) as Mammography,
100*avg(cast([PapTest] as numeric(2,1))) as PapTest,
100*avg(cast([PSATest] as numeric(2,1))) as PSATest,
100*avg(cast([Colonoscopy] as numeric(2,1))) as Colonoscopy,
100*avg(cast([FecalOccultTest] as numeric(2,1))) as FecalOccultTest,
100*avg(cast([FluShot] as numeric(2,1))) as  FluShot,
100*avg(cast([PneumococcalVaccine] as numeric(2,1))) as PneumococcalVaccine,
100*avg(cast([BMI] as numeric(2,1)))  as BMI,
100*avg(cast([A1C] as numeric(2,1))) as A1C,
100*avg(cast([MedicalExam] as numeric(2,1))) as MedicalExam,
100*avg(cast([INP1_OPT1_Visit] as numeric(2,1))) as INP1_OPT1_Visit,
100*avg(cast([OPT2_Visit] as numeric(2,1))) as OPT2_Visit,
100*avg(cast([ED_Visit] as numeric(2,1)))  as ED_Visit,
100*avg(cast([MDVisit_pname2] as numeric(2,1))) as MDVisit_pname2,
100*avg(cast([MDVisit_pname3] as numeric(2,1))) as MDVisit_pname3,
100*avg(cast([Routine_Care_2] as numeric(2,1))) as Routine_care_2,
100*AVG(CAST(~(Num_Dx1|Num_Dx2|MedUse1|Mammography|PapTest|PSATest|Colonoscopy|FecalOccultTest|FluShot|PneumococcalVaccine|BMI|
  A1C|MedicalExam|INP1_OPT1_Visit|OPT2_Visit|ED_Visit|MDVisit_pname2|MDVisit_pname3|Routine_Care_2) AS NUMERIC(2,1))) as Subjects_NoCriteria /* inverted bitwise OR of all bit flags */
from #cohort_agegrp CAG JOIN CTE_PREDICTIVE P ON CAG.AGEGRP = P.AGEGRP AND CAG.Predicted_score >= P.PredictiveScoreCutoff
group by CAG.AGEGRP
UNION ALL
/* UNFILTERED */
SELECT
'N' AS CUTOFF_FILTER_YN,
'Patient Counts' as Summary_Description,
CAG.AGEGRP, 
count(distinct patient_num) as TotalSubjects,
sum(cast([Num_Dx1] as int)) as Num_DX1,
sum(cast([Num_Dx2] as int)) as Num_DX2,
sum(cast([MedUse1] as int))  as MedUSe1,
sum(cast([MedUse2] as int)) as MedUse2,
sum(cast([Mammography] as int)) as Mammography,
sum(cast([PapTest] as int)) as PapTest,
sum(cast([PSATest] as int)) as PSATest,
sum(cast([Colonoscopy] as int)) as Colonoscopy,
sum(cast([FecalOccultTest] as int)) as FecalOccultTest,
sum(cast([FluShot] as int)) as  FluShot,
sum(cast([PneumococcalVaccine] as int)) as PneumococcalVaccine,
sum(cast([BMI] as int))  as BMI,
sum(cast([A1C] as int)) as A1C,
sum(cast([MedicalExam] as int)) as MedicalExam,
sum(cast([INP1_OPT1_Visit] as int)) as INP1_OPT1_Visit,
sum(cast([OPT2_Visit] as int)) as OPT2_Visit,
sum(cast([ED_Visit] as int))  as ED_Visit,
sum(cast([MDVisit_pname2] as int)) as MDVisit_pname2,
sum(cast([MDVisit_pname3] as int)) as MDVisit_pname3,
sum(cast([Routine_Care_2] as int)) as Routine_care_2,
SUM(CAST(~(Num_Dx1|Num_Dx2|MedUse1|Mammography|PapTest|PSATest|Colonoscopy|FecalOccultTest|FluShot|PneumococcalVaccine|BMI|
  A1C|MedicalExam|INP1_OPT1_Visit|OPT2_Visit|ED_Visit|MDVisit_pname2|MDVisit_pname3|Routine_Care_2) AS INT)) as Subjects_NoCriteria /* inverted bitwise OR of all bit flags */
from #cohort_agegrp CAG JOIN CTE_PREDICTIVE P ON CAG.AGEGRP = P.AGEGRP AND CAG.Predicted_score >= P.PredictiveScoreCutoff
group by CAG.AGEGRP
UNION ALL
SELECT
'N' AS PREDICTIVE_CUTOFF_FILTER_YN,
'PercentOfSubjects' as Summary_Description,
CAG.AGEGRP, 
count(distinct patient_num) as TotalSubjects,
100*avg(cast([Num_Dx1] as numeric(2,1))) as Num_DX1,
100*avg(cast([Num_Dx2] as numeric(2,1))) as Num_DX2,
100*avg(cast([MedUse1] as numeric(2,1)))  as MedUSe1,
100*avg(cast([MedUse2] as numeric(2,1))) as MedUse2,
100*avg(cast([Mammography] as numeric(2,1))) as Mammography,
100*avg(cast([PapTest] as numeric(2,1))) as PapTest,
100*avg(cast([PSATest] as numeric(2,1))) as PSATest,
100*avg(cast([Colonoscopy] as numeric(2,1))) as Colonoscopy,
100*avg(cast([FecalOccultTest] as numeric(2,1))) as FecalOccultTest,
100*avg(cast([FluShot] as numeric(2,1))) as  FluShot,
100*avg(cast([PneumococcalVaccine] as numeric(2,1))) as PneumococcalVaccine,
100*avg(cast([BMI] as numeric(2,1)))  as BMI,
100*avg(cast([A1C] as numeric(2,1))) as A1C,
100*avg(cast([MedicalExam] as numeric(2,1))) as MedicalExam,
100*avg(cast([INP1_OPT1_Visit] as numeric(2,1))) as INP1_OPT1_Visit,
100*avg(cast([OPT2_Visit] as numeric(2,1))) as OPT2_Visit,
100*avg(cast([ED_Visit] as numeric(2,1)))  as ED_Visit,
100*avg(cast([MDVisit_pname2] as numeric(2,1))) as MDVisit_pname2,
100*avg(cast([MDVisit_pname3] as numeric(2,1))) as MDVisit_pname3,
100*avg(cast([Routine_Care_2] as numeric(2,1))) as Routine_care_2,
100*AVG(CAST(~(Num_Dx1|Num_Dx2|MedUse1|Mammography|PapTest|PSATest|Colonoscopy|FecalOccultTest|FluShot|PneumococcalVaccine|BMI|
  A1C|MedicalExam|INP1_OPT1_Visit|OPT2_Visit|ED_Visit|MDVisit_pname2|MDVisit_pname3|Routine_Care_2) AS NUMERIC(2,1))) as Subjects_NoCriteria /* inverted bitwise OR of all bit flags */
from #cohort_agegrp CAG
group by CAG.AGEGRP
)COHORTAGG
  JOIN CTE_PREDICTIVE CP
    ON ISNULL(COHORTAGG.AGEGRP,'All Patients') = CP.AGEGRP
  --JOIN #CHARLSON_STATS CS
  --  ON ISNULL(COHORTAGG.AGEGRP,'All Patients') = CS.AGEGRP

SELECT @ROWS=@@ROWCOUNT,@ENDRUNTIMEms = DATEDIFF(MILLISECOND,@STARTTS,GETDATE()),@STEPRUNTIMEms = DATEDIFF(MILLISECOND,@STEPTTS,GETDATE())
RAISERROR(N'Final Summary Table - Rows: %d - Total Execution (ms): %d - Step Runtime (ms): %d', 1, 1, @ROWS, @ENDRUNTIMEms, @STEPRUNTIMEms) with nowait;

SELECT * FROM DBO.loyalty_dev_summary WHERE Summary_Description = 'PercentOfSubjects' ORDER BY TABLENAME;
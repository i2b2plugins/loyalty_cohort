
--prepare user-defined type (table variable for cohort filtering) 
-- THESE LINES MUST BE EXECUTED ONCE - uncomment and run

--CREATE TYPE udt_CohortFilter AS TABLE (PATIENT_NUM INT, COHORT_NAME VARCHAR(100))
--GO

--CREATE TYPE udt_CohortFilter_vIDt AS TABLE (PATIENT_NUM INT, COHORT_NAME VARCHAR(100), INDEX_DT DATE)
--GO


/* Implements a loyalty cohort algorithm with the same general design defined in 
  "External Validation of an Algorithm to Identify Patients with High Data-Completeness in Electronic Health Records for Comparative Effectiveness Research" by Lin et al.
Written primarily by Darren Henderson with contributions from: Jeff Klann, PhD; Andrew Cagan; Barbara Benoit

Calculates 20 variables over the baseline period and computes an overall score, the highest scoring individuals are an approximation of those most likely present for future follow-up
This script accepts an index_date and looks back n years previous to that date (baseline period). For consistency across sites, let us all use the index date of 2/1/2021

This PCSONLY version stops after creating a temporary patient-level table called #COHORT and does not calculate summary data. Save the temporary table to do more calculations on it.

To run, EXEC usp_LoyaltyCohort_PCSONLY @indexDate = '20220201', @site='UKY', @lookbackYears=2, @gendered=1, @filter_by_existing_cohort=1, @cohort_filter=@cfilter, @output=1, @indexDate_OVERRIDE=1;
This will create two tables on your db, loyalty_dev (line level data with variables and score presented for each patient) and loyalty_dev_summary (summary table).

It is ok under the SHRINE IRB to export this: select * from loyalty_dev_summary where Summary_Description='PercentOfSubjects'
It is percentages, a predictive score, and an obfuscated count of total patients.

***** Standard i2b2 table naming conventions are used - Observation_fact, concept_dimension, patient_dimension.
***** Follow the README located here for more information on installing and running: https://github.com/i2b2plugins/loyalty_cohort 
*/
IF OBJECT_ID(N'DBO.usp_LoyaltyCohort_PCSONLY') IS NOT NULL DROP PROCEDURE DBO.usp_LoyaltyCohort_PCSONLY
GO

CREATE PROC [dbo].[usp_LoyaltyCohort_PCSONLY]
     @indexDate datetime
    ,@site varchar(10) 
    ,@lookbackYears int = 1 /* DEFAULT TO 1 YEAR */
    ,@gendered bit = 0 /* DEFAULT TO NON GENDER VERSION */
    ,@filter_by_existing_cohort bit = 0 /* DEFAULT FALSE -- IF YOU WANT TO FILTER THE LOYALTY COHORT BY AN EXISTING COHORT PASS THE @cohort_filter parameter a table variable of type udt_CohortFilter */
    ,@cohort_filter udt_CohortFilter_vIDt READONLY /* Table variable to filter output by an existing cohort */
    ,@output bit = 1
    ,@indexDate_OVERRIDE bit = 0/* DEFAULT TO SHOW FINAL OUTPUT */
AS

/* 
   CHECK ANY CUSTOM LOCAL CODES ADDED TO xref_LoyaltyCode_paths AT <PE.1> AND <PE.2> - PLEASE SEE COMMENTS
*/

SET NOCOUNT ON
SET XACT_ABORT ON

/* UNCOMMENT IF TESTING PROC BODY ALONE */
--DECLARE @indexDate DATE='20210201'
--DECLARE @site VARCHAR(10) = 'UKY' /* ALTER TO YOUR DESIRED SITE CODE */
--DECLARE @lookbackYears INT = 1
--DECLARE @gendered BIT = 0
--DECLARE @output BIT = 1

--DECLARE @filter_by_existing_cohort BIT = 0
--DECLARE @cohort_filter udt_CohortFilter

--INSERT INTO @cohort_filter (PATIENT_NUM, COHORT_NAME)
--SELECT DISTINCT PATIENT_NUM, cohort
--FROM [I2B2ACT].[4CEX2].[FourCE_LocalPatientSummary]

/* create the target summary table if not exists */
IF OBJECT_ID(N'dbo.loyalty_dev_summary', N'U') IS NULL
  CREATE TABLE dbo.[loyalty_dev_summary](
    [COHORT_NAME] VARCHAR(100) NOT NULL,
    [SITE] VARCHAR(10) NOT NULL,
    [GENDER_DENOMINATORS_YN] char(1) NOT NULL,
    [CUTOFF_FILTER_YN] char(1) NOT NULL,
	  [Summary_Description] varchar(20) NOT NULL,
	  [tablename] [varchar](20) NULL,
	  [Num_DX1] float NULL,
	  [Num_DX2] float NULL,
	  [MedUse1] float NULL,
	  [MedUse2] float NULL,
	  [Mammography] float NULL,
	  [PapTest] float NULL,
	  [PSATest] float NULL,
	  [Colonoscopy] float NULL,
	  [FecalOccultTest] float NULL,
	  [FluShot] float NULL,
	  [PneumococcalVaccine] float NULL,
	  [BMI] float NULL,
	  [A1C] float NULL,
	  [MedicalExam] float NULL,
	  [INP1_OPT1_Visit] float NULL,
	  [OPT2_Visit] float NULL,
	  [ED_Visit] float NULL,
	  [MDVisit_pname2] float NULL,
	  [MDVisit_pname3] float NULL,
	  [Routine_care_2] float NULL,
	  [Subjects_NoCriteria] float NULL,
	  [PredictiveScoreCutoff] float NULL,
	  [MEAN_10YRPROB] float NULL,
	  [MEDIAN_10YR_SURVIVAL] float NULL,
	  [MODE_10YRPROB] float NULL,
	  [STDEV_10YRPROB] float NULL,
    [TotalSubjects] int NULL,
    [TotalSubjectsFemale] int NULL,
    [TotalSubjectsMale] int NULL,
    [AverageFactCount] float NULL,
    [EXTRACT_DTTM] DATETIME NOT NULL DEFAULT GETDATE(),
    [LOOKBACK_YR] INT NOT NULL,
    [RUNTIMEms] int NULL
  )

/* CONVERT TABLE VARIABLE TO TEMP TABLE AND INDEX */
IF OBJECT_ID(N'tempdb..#COHORT_FILTER',N'U') IS NOT NULL DROP TABLE #COHORT_FILTER;

SELECT * INTO #COHORT_FILTER FROM @cohort_filter;

CREATE CLUSTERED INDEX CIDX_CF ON #COHORT_FILTER (PATIENT_NUM, INDEX_DT, COHORT_NAME);


/* ENSURE TEMP IS CLEAR FROM PREVIOUS RUNS */
IF OBJECT_ID(N'tempdb..#DEMCONCEPT', N'U') IS NOT NULL DROP TABLE #DEMCONCEPT;
IF OBJECT_ID(N'tempdb..#INLCPAT_MULTIVISIT', N'U') IS NOT NULL DROP TABLE #INLCPAT_MULTIVISIT;
IF OBJECT_ID(N'tempdb..#INCLPAT', N'U') IS NOT NULL DROP TABLE #INCLPAT;
IF OBJECT_ID(N'tempdb..#cohort', N'U') IS NOT NULL DROP TABLE #cohort;
IF OBJECT_ID(N'tempdb..#MDVISIT_OBSERVATIONS', N'U') IS NOT NULL DROP TABLE #MDVISIT_OBSERVATIONS;
IF OBJECT_ID(N'tempdb..#ET_AL_OBSERVATIONS', N'U') IS NOT NULL DROP TABLE #ET_AL_OBSERVATIONS;
IF OBJECT_ID(N'tempdb..#COHORT_FLAGS_PSC', N'U') IS NOT NULL DROP TABLE #COHORT_FLAGS_PSC;
IF OBJECT_ID(N'tempdb..#COHORT_FLAGS_AFC', N'U') IS NOT NULL DROP TABLE #COHORT_FLAGS_AFC;
IF OBJECT_ID(N'tempdb..#cohort_agegrp', N'U') IS NOT NULL DROP TABLE #cohort_agegrp;
IF OBJECT_ID(N'tempdb..#AGEGRP_PSC', N'U') IS NOT NULL DROP TABLE #AGEGRP_PSC;
IF OBJECT_ID(N'tempdb..#AGEGRP_AFC', N'U') IS NOT NULL DROP TABLE #AGEGRP_AFC;
IF OBJECT_ID(N'tempdb..#CHARLSON_VISIT_BASE', N'U') IS NOT NULL DROP TABLE #CHARLSON_VISIT_BASE;
IF OBJECT_ID(N'tempdb..#CHARLSON_DX', N'U') IS NOT NULL DROP TABLE #CHARLSON_DX;
IF OBJECT_ID(N'tempdb..#COHORT_CHARLSON', N'U') IS NOT NULL DROP TABLE #COHORT_CHARLSON;
IF OBJECT_ID(N'tempdb..#CHARLSON_STATS', N'U') IS NOT NULL DROP TABLE #CHARLSON_STATS;

DECLARE @STARTTS DATETIME = GETDATE()
DECLARE @STEPTTS DATETIME 
DECLARE @ENDRUNTIMEms INT, @STEPRUNTIMEms INT
DECLARE @ROWS INT

/* PRE-BUILD AN PATIENT INCLUSION TABLE FOR `HAVING A NON-DEMOGRAPHIC FACT AFTER 20120101` */
/* include only patients with non-demographic concepts after 20120101 
*/

  RAISERROR(N'Starting #INCLPAT phase.', 1, 1) with nowait;

  /* NEW MULTI-VISIT FILTER - 20220228 DWH */
  ;WITH CTE_MULTVISIT AS (
  SELECT PATIENT_NUM, ENCOUNTER_NUM, CONVERT(DATE,START_DATE) START_DATE, CONVERT(DATE,END_DATE) END_DATE 
  /* CONVERTING TO DATE TO AGGRESSIVELY DROP OUT ADMIN-LIKE ENCOUNTERS ON SAME DAY AND TREAT THEM AS OVERLAPPING */ 
  FROM DBO.VISIT_DIMENSION
  WHERE PATIENT_NUM NOT IN (SELECT PATIENT_NUM FROM DBO.VISIT_DIMENSION GROUP BY PATIENT_NUM HAVING COUNT(DISTINCT ENCOUNTER_NUM) = 1) /* EXCLUDES EPHEMERAL ONE-VISIT PATIENTS */
  )
  SELECT DISTINCT A.PATIENT_NUM
  INTO #INLCPAT_MULTIVISIT
  FROM CTE_MULTVISIT A
    LEFT JOIN CTE_MULTVISIT B
      ON A.PATIENT_NUM = B.PATIENT_NUM
      AND A.ENCOUNTER_NUM != B.ENCOUNTER_NUM
      AND (A.START_DATE <= B.END_DATE AND A.END_DATE >= B.START_DATE) /* VISIT DATES OVERLAP IN SOME WAY */
  WHERE B.ENCOUNTER_NUM IS NULL /* NO OVERLAPS - GOAL HERE IS TO ONLY INCLUDE PATIENTS THAT HAVE MULTIPLE ENCOUNTERS */
  /* DON'T NEED TO COUNT ENCOUNTERS HERE.
     IF THE PATIENT STILL HAS AT LEAST ONE ENCOUNTER AFTER DROPPING OUT THEIR ENCOUNTER THAT DID OVERLAP,
     THEN WE CAN INFER THEY HAVE MULTIPLE ENCOUNTERS IN THE HEALTH CARE SYSTEM. THE FIRST PREDICATE IN CTE_MULTVISIT
     REQUIRED THE PATIENT NOT BE IN THE "EPHEMERAL" PATIENT GROUP (PATIENTS WITH ONE ENCOUNTER_NUM IN ALL TIME).
     SO BY THIS STEP, IF ENCOUNTERS THAT DO OVERLAP ARE DROPPED, THERE IS STILL AT LEAST ONE STANDALONE ENCOUNTER IN ADDITION
     TO THOSE OVERLAPPED ENCOUNTERS - THUS AT MINIMUM >=3 ENCOUNTERS IN THE EHR. 
  */

  /* EXTRACT DEMOGRAPHIC CONCEPTS */
  SELECT DISTINCT CONCEPT_CD
    , SUBSTRING(CONCEPT_CD,1,CHARINDEX(':',CONCEPT_CD)-1) AS CONCEPT_PREFIX 
  INTO #DEMCONCEPT
  FROM CONCEPT_DIMENSION
  WHERE CONCEPT_PATH LIKE '\ACT\Demographics%'
    AND CONCEPT_CD != ''
  
  SET @STEPTTS = GETDATE()

  CREATE TABLE #INCLPAT (PATIENT_NUM INT)
  
  IF(@indexDate_OVERRIDE=0)
  BEGIN
    IF(@filter_by_existing_cohort=0)
      INSERT INTO #INCLPAT (PATIENT_NUM)
      SELECT DISTINCT F.PATIENT_NUM
      FROM TABLE_ACCESS TA
        JOIN CONCEPT_DIMENSION CD
          ON CD.CONCEPT_PATH LIKE CONCAT(TA.C_DIMCODE,'%')
          AND CD.CONCEPT_CD != ''
        JOIN OBSERVATION_FACT F
          ON CD.CONCEPT_CD = F.CONCEPT_CD
      WHERE F.START_DATE >= CAST('20120101' AS DATETIME) AND F.START_DATE < @indexDate
        AND TA.C_TABLE_NAME NOT IN ('ACT_DEM_V4')
      INTERSECT
      (SELECT PATIENT_NUM FROM #INLCPAT_MULTIVISIT)
      /* REPLACE THIS - SEEMS TO BE A MAJOR BOTTLENECK THAT IS UNPREDICTABLE */
      --SELECT DISTINCT PATIENT_NUM
      --/* distinct list of patients left over from except operation would be patient-concept_cd key pairs for any other fact type */
      --FROM (
      --/* all patient-concept_cd key pairs between 2012 and index */
      --SELECT F.PATIENT_NUM, F.CONCEPT_CD
      --FROM DBO.OBSERVATION_FACT F
      --  JOIN CONCEPT_DIMENSION CD
      --    ON F.CONCEPT_CD = CD.CONCEPT_CD
      --  JOIN TABLE_ACCESS TA 
      --    ON CD.CONCEPT_PATH LIKE TA.C_DIMCODE+'%'
      --    AND (TA.C_NAME LIKE 'ACT%') /* ACT ONTOLOGY ONLY -- EXCLUDE ANY LOCAL EXTRA ONTOLOGIES A SITE MIGHT BE MANAGING */
      --WHERE F.START_DATE >= CAST('20120101' AS DATETIME) AND F.START_DATE < @indexDate
      --EXCEPT
      --/* exclude patient-concept_cd demographic pairs */
      --SELECT PATIENT_NUM, F.CONCEPT_CD
      --FROM DBO.OBSERVATION_FACT F
      --  JOIN #DEMCONCEPT D
      --    ON F.CONCEPT_CD = D.CONCEPT_CD
      --WHERE F.START_DATE >= CAST('20120101' AS DATETIME) AND F.START_DATE < @indexDate
      --)OFMINUSDEM
      --INTERSECT
      --(SELECT PATIENT_NUM FROM #INLCPAT_MULTIVISIT)
    ELSE
      INSERT INTO #INCLPAT (PATIENT_NUM)
      SELECT DISTINCT F.PATIENT_NUM
      FROM TABLE_ACCESS TA
        JOIN CONCEPT_DIMENSION CD
          ON CD.CONCEPT_PATH LIKE CONCAT(TA.C_DIMCODE,'%')
          AND CD.CONCEPT_CD != ''
        JOIN OBSERVATION_FACT F
          ON CD.CONCEPT_CD = F.CONCEPT_CD
      WHERE F.START_DATE >= CAST('20120101' AS DATETIME) AND F.START_DATE < @indexDate
        AND TA.C_TABLE_NAME NOT IN ('ACT_DEM_V4')
      --SELECT DISTINCT PATIENT_NUM
      --/* distinct list of patients left over from except operation would be patient-concept_cd key pairs for any other fact type */
      --FROM (
      --/* all patient-concept_cd key pairs between 2012 and index */
      --SELECT F.PATIENT_NUM, F.CONCEPT_CD
      --FROM DBO.OBSERVATION_FACT F
      --  JOIN CONCEPT_DIMENSION CD
      --    ON F.CONCEPT_CD = CD.CONCEPT_CD
      --  JOIN TABLE_ACCESS TA 
      --    ON CD.CONCEPT_PATH LIKE TA.C_DIMCODE+'%'
      --    AND (TA.C_NAME LIKE 'ACT%') /* ACT ONTOLOGY ONLY -- EXCLUDE ANY LOCAL EXTRA ONTOLOGIES A SITE MIGHT BE MANAGING */
      --WHERE F.START_DATE >= CAST('20120101' AS DATETIME) AND F.START_DATE < @indexDate
      --EXCEPT
      --/* exclude patient-concept_cd demographic pairs */
      --SELECT PATIENT_NUM, F.CONCEPT_CD
      --FROM DBO.OBSERVATION_FACT F
      --  JOIN #DEMCONCEPT D
      --    ON F.CONCEPT_CD = D.CONCEPT_CD
      --WHERE F.START_DATE >= CAST('20120101' AS DATETIME) AND F.START_DATE < @indexDate
      INTERSECT 
      (SELECT PATIENT_NUM FROM @cohort_filter)
      INTERSECT
      (SELECT PATIENT_NUM FROM #INLCPAT_MULTIVISIT)
  END

  IF(@indexDate_OVERRIDE=1)
  BEGIN
    IF(@filter_by_existing_cohort=0)
      BEGIN
        RAISERROR(N'The parameters filter_by_existing_cohort=0 and indexDate_OVERRIDE = 1, must not be set in this manner. If overriding a static indexDate, a cohort filter must be used.',1,1) WITH NOWAIT;
      --INSERT INTO #INCLPAT (PATIENT_NUM)
      --SELECT DISTINCT PATIENT_NUM
      --/* distinct list of patients left over from except operation would be patient-concept_cd key pairs for any other fact type */
      --FROM (
      --/* all patient-concept_cd key pairs between 2012 and index */
      --SELECT F.PATIENT_NUM, F.CONCEPT_CD
      --FROM DBO.OBSERVATION_FACT F
      --  JOIN CONCEPT_DIMENSION CD
      --    ON F.CONCEPT_CD = CD.CONCEPT_CD
      --  JOIN TABLE_ACCESS TA 
      --    ON CD.CONCEPT_PATH LIKE TA.C_DIMCODE+'%'
      --    AND (TA.C_NAME LIKE 'ACT%') /* ACT ONTOLOGY ONLY -- EXCLUDE ANY LOCAL EXTRA ONTOLOGIES A SITE MIGHT BE MANAGING */
      --  JOIN @cohort_filter CF
      --    ON F.PATIENT_NUM = CF.PATIENT_NUM
      --    AND F.START_DATE >= CAST('20120101' AS DATETIME) AND F.START_DATE <= CF.INDEX_DT 
      --EXCEPT
      --/* exclude patient-concept_cd demographic pairs */
      --SELECT F.PATIENT_NUM, F.CONCEPT_CD
      --FROM DBO.OBSERVATION_FACT F
      --  JOIN #DEMCONCEPT D
      --    ON F.CONCEPT_CD = D.CONCEPT_CD
      --  JOIN @cohort_filter CF
      --    ON F.PATIENT_NUM = CF.PATIENT_NUM
      --    AND F.START_DATE >= CAST('20120101' AS DATETIME) AND F.START_DATE <= CF.INDEX_DT 
      --)OFMINUSDEM
      --INTERSECT
      --(SELECT PATIENT_NUM FROM #INLCPAT_MULTIVISIT)
      END
    ELSE
      INSERT INTO #INCLPAT (PATIENT_NUM)
      SELECT DISTINCT PATIENT_NUM
      /* distinct list of patients left over from except operation would be patient-concept_cd key pairs for any other fact type */
      FROM (
      /* all patient-concept_cd key pairs between 2012 and index */
      SELECT DISTINCT F.PATIENT_NUM
      FROM TABLE_ACCESS TA
        JOIN CONCEPT_DIMENSION CD
          ON CD.CONCEPT_PATH LIKE CONCAT(TA.C_DIMCODE,'%')
          AND CD.CONCEPT_CD != ''
        JOIN OBSERVATION_FACT F
          ON CD.CONCEPT_CD = F.CONCEPT_CD
        JOIN #COHORT_FILTER CF
          ON F.PATIENT_NUM = CF.PATIENT_NUM
      WHERE F.START_DATE >= CAST('20120101' AS DATETIME) AND F.START_DATE <= CF.INDEX_DT
        AND TA.C_TABLE_NAME NOT IN ('ACT_DEM_V4')
      )OFMINUSDEM
      INTERSECT 
      (SELECT PATIENT_NUM FROM @cohort_filter)
      INTERSECT
      (SELECT PATIENT_NUM FROM #INLCPAT_MULTIVISIT)
  END
  
  SELECT @ROWS=@@ROWCOUNT,@ENDRUNTIMEms = DATEDIFF(MILLISECOND,@STARTTS,GETDATE()),@STEPRUNTIMEms = DATEDIFF(MILLISECOND,@STEPTTS,GETDATE())
  RAISERROR(N'Build #INCLPAT - Rows: %d - Total Execution (ms): %d - Step Runtime (ms): %d', 1, 1, @ROWS, @ENDRUNTIMEms, @STEPRUNTIMEms) with nowait;


/* FINISH PRE-BUILD ACT MODEL */

CREATE TABLE #cohort (
cohort_name VARCHAR(100) NOT NULL,
patient_num INT NOT NULL,
sex varchar(50) null,
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
Predicted_score FLOAT not null DEFAULT -0.010, /* default is intercept */
LAST_VISIT DATE NULL,
CONSTRAINT PKCOHORT PRIMARY KEY (cohort_name, patient_num)
)


/* EXTRACT COHORT AND VISIT TYPE FLAGS */
SET @STEPTTS = GETDATE()

IF(@filter_by_existing_cohort=1)
BEGIN
  IF(@indexDate_OVERRIDE=0)
    BEGIN
      INSERT INTO #COHORT (COHORT_NAME, PATIENT_NUM, INP1_OPT1_Visit, OPT2_Visit, ED_Visit, LAST_VISIT)
      SELECT COHORT_NAME, PATIENT_NUM
        , MAX(CASE WHEN Feature_name = 'INP1_OPT1_Visit' THEN 1 ELSE 0 END) AS INP1_OPT1_VISIT
        , MAX(CASE WHEN Feature_name = 'OPT2_Visit' AND N >= 2 THEN 1 ELSE 0 END) AS OPT2_Visit
        , MAX(CASE WHEN Feature_name = 'ED_Visit' THEN 1 ELSE 0 END) AS ED_Visit
        , LAST_VISIT
      FROM(
      SELECT CF.COHORT_NAME, INP.PATIENT_NUM, P.Feature_name
        , COUNT(DISTINCT CONVERT(DATE, V.START_DATE)) N
        , LV.LAST_VISIT
      FROM @cohort_filter CF
      JOIN #INCLPAT INP
        ON CF.PATIENT_NUM = INP.PATIENT_NUM
      LEFT JOIN VISIT_DIMENSION V
        ON CF.PATIENT_NUM = V.PATIENT_NUM
        AND V.START_DATE >= DATEADD(YY,-@lookbackYears,@indexDate) AND V.START_DATE < @indexDate
        JOIN CONCEPT_DIMENSION CDV
          ON V.INOUT_CD = CDV.CONCEPT_CD
        JOIN xref_LoyaltyCode_paths P
          ON P.code_type = 'VISIT'
          AND CDV.CONCEPT_PATH LIKE P.ACT_PATH+'%'
        CROSS APPLY (SELECT MAX(CONVERT(DATE, START_DATE)) AS LAST_VISIT FROM VISIT_DIMENSION WHERE PATIENT_NUM = CF.PATIENT_NUM) LV
      --WHERE CF.PATIENT_NUM NOT IN (SELECT PATIENT_NUM FROM PATIENT_DIMENSION WHERE DEATH_DATE IS NOT NULL) /* EXCLUDE DECEASED */
      GROUP BY CF.COHORT_NAME, INP.PATIENT_NUM, P.Feature_name, LV.LAST_VISIT
      )V
      GROUP BY COHORT_NAME, PATIENT_NUM, LAST_VISIT;
    END
  ELSE /* @indexDate_OVERRIDE=1 */
    BEGIN
      INSERT INTO #COHORT (COHORT_NAME, PATIENT_NUM, INP1_OPT1_Visit, OPT2_Visit, ED_Visit, LAST_VISIT)
      SELECT COHORT_NAME, PATIENT_NUM
        , MAX(CASE WHEN Feature_name = 'INP1_OPT1_Visit' THEN 1 ELSE 0 END) AS INP1_OPT1_VISIT
        , MAX(CASE WHEN Feature_name = 'OPT2_Visit' AND N >= 2 THEN 1 ELSE 0 END) AS OPT2_Visit
        , MAX(CASE WHEN Feature_name = 'ED_Visit' THEN 1 ELSE 0 END) AS ED_Visit
        , LAST_VISIT
      FROM(
      SELECT CF.COHORT_NAME, INP.PATIENT_NUM, P.Feature_name
        , COUNT(DISTINCT CONVERT(DATE, V.START_DATE)) N
        , LV.LAST_VISIT
      FROM @cohort_filter CF
      JOIN #INCLPAT INP
        ON CF.PATIENT_NUM = INP.PATIENT_NUM
      LEFT JOIN VISIT_DIMENSION V
        ON CF.PATIENT_NUM = V.PATIENT_NUM
        AND V.START_DATE >= DATEADD(YY,-@lookbackYears,@indexDate) AND V.START_DATE <= CF.INDEX_DT
        JOIN CONCEPT_DIMENSION CDV
          ON V.INOUT_CD = CDV.CONCEPT_CD
        JOIN xref_LoyaltyCode_paths P
          ON P.code_type = 'VISIT'
          AND CDV.CONCEPT_PATH LIKE P.ACT_PATH+'%'
        CROSS APPLY (SELECT MAX(CONVERT(DATE, START_DATE)) AS LAST_VISIT FROM VISIT_DIMENSION WHERE PATIENT_NUM = CF.PATIENT_NUM) LV
      --WHERE CF.PATIENT_NUM NOT IN (SELECT PATIENT_NUM FROM PATIENT_DIMENSION WHERE DEATH_DATE IS NOT NULL) /* EXCLUDE DECEASED */
      GROUP BY CF.COHORT_NAME, INP.PATIENT_NUM, P.Feature_name, LV.LAST_VISIT
      )V
      GROUP BY COHORT_NAME, PATIENT_NUM, LAST_VISIT;
    END

  /* INCLUDE PATIENTS THAT HAD A FACT SINCE 2012 (#INCLPAT) BUT DIDN'T FIND A VISIT IN THE LOOKBACK PERIOD */
  INSERT INTO #cohort (cohort_name, patient_num, INP1_OPT1_Visit, OPT2_Visit, ED_Visit, LAST_VISIT)
  SELECT CF.COHORT_NAME, INP.PATIENT_NUM, 0, 0, 0, LV.LAST_VISIT
    FROM #INCLPAT INP
      JOIN @cohort_filter CF
        ON INP.PATIENT_NUM = CF.PATIENT_NUM
      CROSS APPLY (SELECT MAX(CONVERT(DATE, START_DATE)) AS LAST_VISIT FROM VISIT_DIMENSION WHERE PATIENT_NUM = INP.PATIENT_NUM) LV
  WHERE INP.PATIENT_NUM NOT IN (SELECT PATIENT_NUM FROM #cohort);


END

IF(@filter_by_existing_cohort=0)
BEGIN
  IF(@indexDate_OVERRIDE=1)
  BEGIN
    RAISERROR(N'The parameters filter_by_existing_cohort=0 and indexDate_OVERRIDE = 1, must not be set in this manner. If overriding a static indexDate, a cohort filter must be used.',1,1) WITH NOWAIT

  END
  ELSE
  BEGIN
    INSERT INTO #COHORT (COHORT_NAME, PATIENT_NUM, INP1_OPT1_Visit, OPT2_Visit, ED_Visit, LAST_VISIT)
    SELECT 'N/A' AS COHORT_NAME, PATIENT_NUM
      , MAX(CASE WHEN Feature_name = 'INP1_OPT1_Visit' THEN 1 ELSE 0 END) AS INP1_OPT1_VISIT
      , MAX(CASE WHEN Feature_name = 'OPT2_Visit' AND N >= 2 THEN 1 ELSE 0 END) AS OPT2_Visit
      , MAX(CASE WHEN Feature_name = 'ED_Visit' THEN 1 ELSE 0 END) AS ED_Visit
      , LAST_VISIT
    FROM(
    SELECT INP.PATIENT_NUM, P.Feature_name
      , COUNT(DISTINCT CONVERT(DATE, V.START_DATE)) N
      , LV.LAST_VISIT
    FROM #INCLPAT INP
    LEFT JOIN VISIT_DIMENSION V
      ON INP.PATIENT_NUM = V.PATIENT_NUM
        AND V.START_DATE >= DATEADD(YY,-@lookbackYears,@indexDate) AND V.START_DATE < @indexDate
      JOIN CONCEPT_DIMENSION CDV
        ON V.INOUT_CD = CDV.CONCEPT_CD
      JOIN xref_LoyaltyCode_paths P
        ON P.code_type = 'VISIT'
        AND CDV.CONCEPT_PATH LIKE P.ACT_PATH+'%'
    CROSS APPLY (SELECT MAX(CONVERT(DATE, START_DATE)) AS LAST_VISIT FROM VISIT_DIMENSION WHERE PATIENT_NUM = INP.PATIENT_NUM) LV
    --WHERE CF.PATIENT_NUM NOT IN (SELECT PATIENT_NUM FROM PATIENT_DIMENSION WHERE DEATH_DATE IS NOT NULL) /* EXCLUDE DECEASED */
    GROUP BY INP.PATIENT_NUM, P.Feature_name, LV.LAST_VISIT
    )V
    GROUP BY PATIENT_NUM, LAST_VISIT;
   
    /* INCLUDE PATIENTS THAT HAD A FACT SINCE 2012 (#INCLPAT) BUT DIDN'T FIND A VISIT IN THE LOOKBACK PERIOD */
    INSERT INTO #cohort (cohort_name, patient_num, INP1_OPT1_Visit, OPT2_Visit, ED_Visit, LAST_VISIT)
    SELECT 'N/A' AS COHORT_NAME, PATIENT_NUM, 0, 0, 0, LV.LAST_VISIT
    FROM #INCLPAT INP
      CROSS APPLY (SELECT MAX(CONVERT(DATE, START_DATE)) AS LAST_VISIT FROM VISIT_DIMENSION WHERE PATIENT_NUM = INP.PATIENT_NUM) LV
    WHERE INP.PATIENT_NUM NOT IN (SELECT PATIENT_NUM FROM #cohort);
  END
END

UPDATE #COHORT
SET SEX = REPLACE(P.SEX_CD,'DEM|SEX:','')
  , AGE = FLOOR(DATEDIFF(DD,P.BIRTH_DATE,@indexDate)/365.25)
FROM #COHORT C, PATIENT_DIMENSION P
WHERE C.PATIENT_NUM = P.PATIENT_NUM

SELECT @ROWS=@@ROWCOUNT,@ENDRUNTIMEms = DATEDIFF(MILLISECOND,@STARTTS,GETDATE()),@STEPRUNTIMEms = DATEDIFF(MILLISECOND,@STEPTTS,GETDATE())
RAISERROR(N'Cohort and Visit Type variables - Rows: %d - Total Execution (ms): %d - Step Runtime (ms): %d', 1, 1, @ROWS, @ENDRUNTIMEms, @STEPRUNTIMEms) with nowait;

ALTER TABLE #COHORT ADD INDEX_DT DATE;

IF(@indexDate_OVERRIDE=1)
BEGIN

  UPDATE #COHORT SET INDEX_DT = B.INDEX_DT FROM #COHORT A JOIN @cohort_filter B ON A.PATIENT_NUM = B.PATIENT_NUM AND A.COHORT_NAME = B.COHORT_NAME

  SELECT @ROWS=@@ROWCOUNT;
  RAISERROR(N'Adding INDEX_DT TO COHORT :: @indexDate_OVERRIDE=1 - Rows: %d', 1, 1, @ROWS) with nowait;
END


/* HAVE TO CENSOR BAD BIRTH_DATE DATA FOR AGEGRP STEPS LATER */
DELETE FROM #COHORT WHERE AGE IS NULL

SELECT @ROWS=@@ROWCOUNT

IF @ROWS > 0
  RAISERROR(N'Dropping patients with null birth_date - Rows: %d', 1, 1, @ROWS) with nowait;


/* NEW COHORT FLAGS PSC BLOCK */
SET @STEPTTS = GETDATE()

CREATE TABLE #MDVISIT_OBSERVATIONS(COHORT_NAME VARCHAR(100), FEATURE_NAME VARCHAR(100), PATIENT_NUM INT)
CREATE TABLE #ET_AL_OBSERVATIONS(COHORT_NAME VARCHAR(100), FEATURE_NAME VARCHAR(100), PATIENT_NUM INT)
CREATE TABLE #COHORT_FLAGS_PSC (COHORT_NAME VARCHAR(100), PATIENT_NUM INT, SEX VARCHAR(10), AGE INT
    , [Num_DX1] FLOAT, [Num_DX2] FLOAT, [MedUse1] FLOAT, [MedUse2] FLOAT, [Mammography] FLOAT, [PapTest] FLOAT, [PSATest] FLOAT, [Colonoscopy] FLOAT, [FecalOccultTest] FLOAT, [FluShot] FLOAT, [PneumococcalVaccine]
    FLOAT, [BMI] FLOAT, [A1C] FLOAT, [MedicalExam] FLOAT, [INP1_OPT1_Visit] FLOAT, [OPT2_Visit] FLOAT, [ED_Visit] FLOAT, [MDVisit_pname2] FLOAT, [MDVisit_pname3] FLOAT,[Routine_Care_2] FLOAT
    , [Predicted_Score] FLOAT
    , LAST_VISIT DATE)

if(@indexDate_OVERRIDE=0)
BEGIN

  ;WITH MDVISIT_FEATURES AS (
  select Feature_name, CD.CONCEPT_CD
  FROM xref_LoyaltyCode_paths P
    JOIN CONCEPT_DIMENSION CD
      ON CD.CONCEPT_PATH LIKE P.ACT_PATH+'%'
  WHERE Feature_name IN ('MDVisit_pname2','MDVisit_pname3')
  ) 
  INSERT INTO #MDVISIT_OBSERVATIONS WITH(TABLOCK)(COHORT_NAME,FEATURE_NAME,PATIENT_NUM)
  SELECT DISTINCT COHORT_NAME, Feature_name, PATIENT_NUM
  FROM (
  SELECT COHORT_NAME, O.PATIENT_NUM, O.PROVIDER_ID, MF.FEATURE_NAME, COUNT(DISTINCT CONVERT(DATE, O.START_DATE)) N
  FROM OBSERVATION_FACT O
    JOIN #cohort C
      ON O.PATIENT_NUM = C.patient_num
    JOIN MDVISIT_FEATURES MF
      ON O.CONCEPT_CD = MF.CONCEPT_CD
  WHERE CONVERT(DATE,O.START_DATE) BETWEEN DATEADD(YY,-@lookbackYears,@indexDate) and @indexDate
  GROUP BY COHORT_NAME, O.PATIENT_NUM, O.PROVIDER_ID, MF.FEATURE_NAME
  )RAWFREQ
  WHERE (Feature_name = 'MDVisit_pname2' AND N=2) OR (Feature_name = 'MDVisit_pname3' AND N >= 3)
  
  ;WITH ET_AL_FEATURES AS (
  select distinct Feature_name, concept_cd, 1 AS THRESHOLD
  from DBO.xref_LoyaltyCode_paths L, CONCEPT_DIMENSION c
  where C.CONCEPT_PATH like L.Act_path+'%'  --jgk: must support local children
  AND code_type IN ('DX','PX','lab','SITE') /* <PE.1> IF YOUR SITE IS MANAGING ANY SITE SPECIFIC CODES FOR THE FOLLOWING DOMAINS SET THEIR CODE_TYPE = 'SITE' IN dbo.xref_LoyaltyCode_paths </PE.1> */
  and (act_path <> '**Not Found' and act_path is not null)
  AND Feature_name NOT IN ('Num_DX1','Num_DX2','MedUse1','MedUse2','MDVisit_pname2','MDVisit_pname3', 'MD Visit')
  UNION 
  select distinct 'Routine_Care_2' as Feature_name, concept_cd, 2 AS THRESHOLD--[ACT_PATH], 
  from DBO.xref_LoyaltyCode_paths L, CONCEPT_DIMENSION c
  where C.CONCEPT_PATH like L.Act_path+'%'  --jgk: must support local children
  AND code_type IN ('DX','PX','lab','SITE') /* <PE.1> IF YOUR SITE IS MANAGING ANY SITE SPECIFIC CODES FOR THE FOLLOWING DOMAINS SET THEIR CODE_TYPE = 'SITE' IN dbo.xref_LoyaltyCode_paths </PE.1> */
  and (act_path <> '**Not Found' and act_path is not null)
  AND Feature_name IN ('MedicalExam','Mammography','PSATest','Colonoscopy','FecalOccultTest','FluShot','PneumococcalVaccine','A1C','BMI')
  UNION
  SELECT Feature_name, CD.CONCEPT_CD, REPLACE(REPLACE(FEATURE_NAME,'Num_DX',''),'MedUse','') as THRESHOLD
  FROM xref_LoyaltyCode_paths P
    JOIN CONCEPT_DIMENSION CD
      ON CD.CONCEPT_PATH LIKE P.ACT_PATH+'%'
  WHERE Feature_name in ('Num_DX1','Num_DX2','MedUse1','MedUse2')
  )
  INSERT INTO #ET_AL_OBSERVATIONS WITH(TABLOCK) (COHORT_NAME, FEATURE_NAME, PATIENT_NUM)
  SELECT COHORT_NAME, F.Feature_name, C.patient_num
  FROM OBSERVATION_FACT O
    JOIN #cohort C
      ON O.PATIENT_NUM = C.patient_num
    JOIN ET_AL_FEATURES F
      ON O.CONCEPT_CD = F.CONCEPT_CD
  WHERE CONVERT(DATE,O.START_DATE) BETWEEN DATEADD(YY,-@lookbackYears,@indexDate) and @indexDate
  GROUP BY COHORT_NAME, F.Feature_name, C.patient_num, F.THRESHOLD
  HAVING COUNT(DISTINCT CONVERT(DATE, O.START_DATE)) >= F.THRESHOLD
  
  ;WITH PATIENT_FEATURES AS (
  SELECT COHORT_NAME, FEATURE_NAME, PATIENT_NUM FROM #MDVISIT_OBSERVATIONS
  UNION ALL
  SELECT COHORT_NAME, FEATURE_NAME, PATIENT_NUM FROM #ET_AL_OBSERVATIONS
  UNION ALL
  SELECT COHORT_NAME, 'INP1_OPT1_Visit' AS FEATURE_NAME, PATIENT_NUM FROM #COHORT WHERE INP1_OPT1_VISIT != 0
  UNION ALL
  SELECT COHORT_NAME, 'OPT2_Visit' AS FEATURE_NAME, PATIENT_NUM FROM #COHORT WHERE OPT2_Visit != 0
  UNION ALL
  SELECT COHORT_NAME, 'ED_Visit' AS FEATURE_NAME, PATIENT_NUM FROM #COHORT WHERE ED_Visit != 0
  )
  , PATIENT_PSC_COEFF AS (
  SELECT PF.*, CF.COEFF
  FROM PATIENT_FEATURES PF
    JOIN xref_LoyaltyCode_PSCoeff CF
      ON PF.Feature_name = CF.FIELD_NAME
  )
  INSERT INTO #COHORT_FLAGS_PSC WITH(TABLOCK) (COHORT_NAME, PATIENT_NUM, SEX, AGE, [Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], [FecalOccultTest], [FluShot], [PneumococcalVaccine]
    , [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3],[Routine_Care_2],[Predicted_Score]
    , LAST_VISIT)
  SELECT cohort_name, PATIENT_NUM,
  MAX(SEX) AS SEX,
  MAX(AGE) AS AGE,
  MAX([Num_DX1]) AS [Num_DX1],
  MAX([Num_DX2]) AS [Num_DX2],
  MAX([MedUse1]) AS [MedUse1],
  MAX([MedUse2]) AS [MedUse2],
  MAX([Mammography]) AS [Mammography],
  MAX([PapTest]) AS [PapTest],
  MAX([PSATest]) AS [PSATest],
  MAX([Colonoscopy]) AS [Colonoscopy],
  MAX(FecalOccultTest) AS FecalOccultTest,
  MAX([FluShot]) AS [FluShot],
  MAX([PneumococcalVaccine]) AS [PneumococcalVaccine],
  MAX([BMI]) AS [BMI],
  MAX([A1C]) AS [A1C],
  MAX([MedicalExam]) AS [MedicalExam],
  MAX([INP1_OPT1_Visit]) AS [INP1_OPT1_Visit],
  MAX([OPT2_Visit]) AS [OPT2_Visit],
  MAX([ED_Visit]) AS [ED_Visit],
  MAX([MDVisit_pname2]) AS [MDVisit_pname2],
  MAX([MDVisit_pname3]) AS [MDVisit_pname3],
  MAX([Routine_Care_2]) AS [Routine_Care_2],
  MAX([Predicted_Score]) AS [Predicted_Score],
  MAX(LAST_VISIT) AS LAST_VISIT
  FROM (
  SELECT COHORT_NAME, PATIENT_NUM, NULL AS SEX, NULL AS AGE
    , [Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], [FecalOccultTest], [FluShot], [PneumococcalVaccine]
    , [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3],[Routine_Care_2],[Predicted_Score]
    , NULL AS LAST_VISIT
  FROM (
  SELECT COHORT_NAME, 'Predicted_score' AS FEATURE_NAME, PATIENT_NUM, -0.010+SUM(COEFF) AS VAL FROM PATIENT_PSC_COEFF GROUP BY COHORT_NAME, PATIENT_NUM
  UNION ALL
  SELECT COHORT_NAME, FEATURE_NAME, PATIENT_NUM, IIF(COEFF<>0,1,0) AS VAL FROM PATIENT_PSC_COEFF
  )O
  PIVOT
  (MAX(VAL) FOR FEATURE_NAME IN ([Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], [FecalOccultTest], [FluShot], [PneumococcalVaccine]
  , [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3],[Routine_Care_2],[Predicted_Score]))P
  UNION ALL 
  /* UNION THE PIVOT RESULTS WITH THE HOLDING TABLE CONTENTS THAT HAVE THE AGE/SEX/LAST_VISIT DATA -- TAKE THE MAX OUTSIDE THIS SUBQUERY TO COMBINE THE RESULTS */
  SELECT COHORT_NAME, PATIENT_NUM, SEX, AGE
    , [Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], [FecalOccultTest], [FluShot], [PneumococcalVaccine]
    , [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3],[Routine_Care_2],[Predicted_Score]
    , LAST_VISIT
  FROM #COHORT
  )PSC
  GROUP BY COHORT_NAME, PATIENT_NUM
  
  TRUNCATE TABLE #COHORT /* PREPARE TO REPLACE CONTENTS WITH NEW PSC CONTENTS FROM PREVIOUS STEP */
  
  INSERT INTO #COHORT (cohort_name, PATIENT_NUM, SEX, AGE, [Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], FecalOccultTest, [FluShot], [PneumococcalVaccine], [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3] , Routine_Care_2 , Predicted_Score , LAST_VISIT)
  SELECT COHORT_NAME, PATIENT_NUM, SEX, AGE, [Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], FecalOccultTest, [FluShot], [PneumococcalVaccine], [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3]
    , Routine_Care_2, Predicted_Score, LAST_VISIT
  FROM #COHORT_FLAGS_PSC
  
  SELECT @ROWS=@@ROWCOUNT,@ENDRUNTIMEms = DATEDIFF(MILLISECOND,@STARTTS,GETDATE()),@STEPRUNTIMEms = DATEDIFF(MILLISECOND,@STEPTTS,GETDATE())
  RAISERROR(N'Cohort Flags - Rows: %d - Total Execution (ms): %d  - Step Runtime (ms): %d', 1, 1, @ROWS, @ENDRUNTIMEms, @STEPRUNTIMEms) with nowait;
END

if(@indexDate_OVERRIDE=1)
BEGIN

  ;WITH MDVISIT_FEATURES AS (
  select Feature_name, CD.CONCEPT_CD
  FROM xref_LoyaltyCode_paths P
    JOIN CONCEPT_DIMENSION CD
      ON CD.CONCEPT_PATH LIKE P.ACT_PATH+'%'
  WHERE Feature_name IN ('MDVisit_pname2','MDVisit_pname3')
  ) 
  INSERT INTO #MDVISIT_OBSERVATIONS WITH(TABLOCK)(COHORT_NAME,FEATURE_NAME,PATIENT_NUM)
  SELECT DISTINCT COHORT_NAME, Feature_name, PATIENT_NUM
  FROM (
  SELECT COHORT_NAME, O.PATIENT_NUM, O.PROVIDER_ID, MF.FEATURE_NAME, COUNT(DISTINCT CONVERT(DATE, O.START_DATE)) N
  FROM OBSERVATION_FACT O
    JOIN #cohort C
      ON O.PATIENT_NUM = C.patient_num
    JOIN MDVISIT_FEATURES MF
      ON O.CONCEPT_CD = MF.CONCEPT_CD
  WHERE CONVERT(DATE,O.START_DATE) BETWEEN DATEADD(YY,-@lookbackYears,INDEX_DT) and INDEX_DT
  GROUP BY COHORT_NAME, O.PATIENT_NUM, O.PROVIDER_ID, MF.FEATURE_NAME
  )RAWFREQ
  WHERE (Feature_name = 'MDVisit_pname2' AND N=2) OR (Feature_name = 'MDVisit_pname3' AND N >= 3)
  
  ;WITH ET_AL_FEATURES AS (
  select distinct Feature_name, concept_cd, 1 AS THRESHOLD
  from DBO.xref_LoyaltyCode_paths L, CONCEPT_DIMENSION c
  where C.CONCEPT_PATH like L.Act_path+'%'  --jgk: must support local children
  AND code_type IN ('DX','PX','lab','SITE') /* <PE.1> IF YOUR SITE IS MANAGING ANY SITE SPECIFIC CODES FOR THE FOLLOWING DOMAINS SET THEIR CODE_TYPE = 'SITE' IN dbo.xref_LoyaltyCode_paths </PE.1> */
  and (act_path <> '**Not Found' and act_path is not null)
  AND Feature_name NOT IN ('Num_DX1','Num_DX2','MedUse1','MedUse2','MDVisit_pname2','MDVisit_pname3', 'MD Visit')
  UNION 
  select distinct 'Routine_Care_2' as Feature_name, concept_cd, 2 AS THRESHOLD--[ACT_PATH], 
  from DBO.xref_LoyaltyCode_paths L, CONCEPT_DIMENSION c
  where C.CONCEPT_PATH like L.Act_path+'%'  --jgk: must support local children
  AND code_type IN ('DX','PX','lab','SITE') /* <PE.1> IF YOUR SITE IS MANAGING ANY SITE SPECIFIC CODES FOR THE FOLLOWING DOMAINS SET THEIR CODE_TYPE = 'SITE' IN dbo.xref_LoyaltyCode_paths </PE.1> */
  and (act_path <> '**Not Found' and act_path is not null)
  AND Feature_name IN ('MedicalExam','Mammography','PSATest','Colonoscopy','FecalOccultTest','FluShot','PneumococcalVaccine','A1C','BMI')
  UNION
  SELECT Feature_name, CD.CONCEPT_CD, REPLACE(REPLACE(FEATURE_NAME,'Num_DX',''),'MedUse','') as THRESHOLD
  FROM xref_LoyaltyCode_paths P
    JOIN CONCEPT_DIMENSION CD
      ON CD.CONCEPT_PATH LIKE P.ACT_PATH+'%'
  WHERE Feature_name in ('Num_DX1','Num_DX2','MedUse1','MedUse2')
  )
  INSERT INTO #ET_AL_OBSERVATIONS WITH(TABLOCK) (COHORT_NAME, FEATURE_NAME, PATIENT_NUM)
  SELECT COHORT_NAME, F.Feature_name, C.patient_num
  FROM OBSERVATION_FACT O
    JOIN #cohort C
      ON O.PATIENT_NUM = C.patient_num
    JOIN ET_AL_FEATURES F
      ON O.CONCEPT_CD = F.CONCEPT_CD
  WHERE CONVERT(DATE,O.START_DATE) BETWEEN DATEADD(YY,-@lookbackYears,INDEX_DT) and INDEX_DT
  GROUP BY COHORT_NAME, F.Feature_name, C.patient_num, F.THRESHOLD
  HAVING COUNT(DISTINCT CONVERT(DATE, O.START_DATE)) >= F.THRESHOLD
  
  ;WITH PATIENT_FEATURES AS (
  SELECT COHORT_NAME, FEATURE_NAME, PATIENT_NUM FROM #MDVISIT_OBSERVATIONS
  UNION ALL
  SELECT COHORT_NAME, FEATURE_NAME, PATIENT_NUM FROM #ET_AL_OBSERVATIONS
  UNION ALL
  SELECT COHORT_NAME, 'INP1_OPT1_Visit' AS FEATURE_NAME, PATIENT_NUM FROM #COHORT WHERE INP1_OPT1_VISIT != 0
  UNION ALL
  SELECT COHORT_NAME, 'OPT2_Visit' AS FEATURE_NAME, PATIENT_NUM FROM #COHORT WHERE OPT2_Visit != 0
  UNION ALL
  SELECT COHORT_NAME, 'ED_Visit' AS FEATURE_NAME, PATIENT_NUM FROM #COHORT WHERE ED_Visit != 0
  )
  , PATIENT_PSC_COEFF AS (
  SELECT PF.*, CF.COEFF
  FROM PATIENT_FEATURES PF
    JOIN xref_LoyaltyCode_PSCoeff CF
      ON PF.Feature_name = CF.FIELD_NAME
  )
  INSERT INTO #COHORT_FLAGS_PSC WITH(TABLOCK) (COHORT_NAME, PATIENT_NUM, SEX, AGE, [Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], [FecalOccultTest], [FluShot], [PneumococcalVaccine]
    , [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3],[Routine_Care_2],[Predicted_Score]
    , LAST_VISIT)
  SELECT cohort_name, PATIENT_NUM,
  MAX(SEX) AS SEX,
  MAX(AGE) AS AGE,
  MAX([Num_DX1]) AS [Num_DX1],
  MAX([Num_DX2]) AS [Num_DX2],
  MAX([MedUse1]) AS [MedUse1],
  MAX([MedUse2]) AS [MedUse2],
  MAX([Mammography]) AS [Mammography],
  MAX([PapTest]) AS [PapTest],
  MAX([PSATest]) AS [PSATest],
  MAX([Colonoscopy]) AS [Colonoscopy],
  MAX(FecalOccultTest) AS FecalOccultTest,
  MAX([FluShot]) AS [FluShot],
  MAX([PneumococcalVaccine]) AS [PneumococcalVaccine],
  MAX([BMI]) AS [BMI],
  MAX([A1C]) AS [A1C],
  MAX([MedicalExam]) AS [MedicalExam],
  MAX([INP1_OPT1_Visit]) AS [INP1_OPT1_Visit],
  MAX([OPT2_Visit]) AS [OPT2_Visit],
  MAX([ED_Visit]) AS [ED_Visit],
  MAX([MDVisit_pname2]) AS [MDVisit_pname2],
  MAX([MDVisit_pname3]) AS [MDVisit_pname3],
  MAX([Routine_Care_2]) AS [Routine_Care_2],
  MAX([Predicted_Score]) AS [Predicted_Score],
  MAX(LAST_VISIT) AS LAST_VISIT
  FROM (
  SELECT COHORT_NAME, PATIENT_NUM, NULL AS SEX, NULL AS AGE
    , [Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], [FecalOccultTest], [FluShot], [PneumococcalVaccine]
    , [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3],[Routine_Care_2],[Predicted_Score]
    , NULL AS LAST_VISIT
  FROM (
  SELECT COHORT_NAME, 'Predicted_score' AS FEATURE_NAME, PATIENT_NUM, -0.010+SUM(COEFF) AS VAL FROM PATIENT_PSC_COEFF GROUP BY COHORT_NAME, PATIENT_NUM
  UNION ALL
  SELECT COHORT_NAME, FEATURE_NAME, PATIENT_NUM, IIF(COEFF<>0,1,0) AS VAL FROM PATIENT_PSC_COEFF
  )O
  PIVOT
  (MAX(VAL) FOR FEATURE_NAME IN ([Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], [FecalOccultTest], [FluShot], [PneumococcalVaccine]
  , [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3],[Routine_Care_2],[Predicted_Score]))P
  UNION ALL 
  /* UNION THE PIVOT RESULTS WITH THE HOLDING TABLE CONTENTS THAT HAVE THE AGE/SEX/LAST_VISIT DATA -- TAKE THE MAX OUTSIDE THIS SUBQUERY TO COMBINE THE RESULTS */
  SELECT COHORT_NAME, PATIENT_NUM, SEX, AGE
    , [Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], [FecalOccultTest], [FluShot], [PneumococcalVaccine]
    , [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3],[Routine_Care_2],[Predicted_Score]
    , LAST_VISIT
  FROM #COHORT
  )PSC
  GROUP BY COHORT_NAME, PATIENT_NUM
  
  TRUNCATE TABLE #COHORT /* PREPARE TO REPLACE CONTENTS WITH NEW PSC CONTENTS FROM PREVIOUS STEP */
  
  INSERT INTO #COHORT (cohort_name, PATIENT_NUM, SEX, AGE, [Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], FecalOccultTest, [FluShot], [PneumococcalVaccine], [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3] , Routine_Care_2 , Predicted_Score , LAST_VISIT)
  SELECT COHORT_NAME, PATIENT_NUM, SEX, AGE, [Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], FecalOccultTest, [FluShot], [PneumococcalVaccine], [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3]
    , Routine_Care_2, Predicted_Score, LAST_VISIT
  FROM #COHORT_FLAGS_PSC
  
  SELECT @ROWS=@@ROWCOUNT,@ENDRUNTIMEms = DATEDIFF(MILLISECOND,@STARTTS,GETDATE()),@STEPRUNTIMEms = DATEDIFF(MILLISECOND,@STEPTTS,GETDATE())
  RAISERROR(N'Cohort Flags - Rows: %d - Total Execution (ms): %d  - Step Runtime (ms): %d', 1, 1, @ROWS, @ENDRUNTIMEms, @STEPRUNTIMEms) with nowait;
END


SELECT COHORT_NAME, PATIENT_NUM, SEX, AGE, [Num_DX1], [Num_DX2], [MedUse1], [MedUse2], [Mammography], [PapTest], [PSATest], [Colonoscopy], FecalOccultTest, [FluShot], [PneumococcalVaccine], [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit], [MDVisit_pname2], [MDVisit_pname3]
    , Routine_Care_2, Predicted_Score, LAST_VISIT
FROM #COHORT
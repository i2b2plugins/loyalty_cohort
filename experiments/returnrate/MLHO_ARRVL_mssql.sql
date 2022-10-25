 /* Prepare return-rate analysis using loyalty cohort script. Output is views that will be utilized by an R program.
   Author: Darren Henderson with edits by Jeff Klann, PhD
 
 To use:
   * Set site id in EXEC line below.
   * Add or modify the code marked "-- Note: You can add site-specific checks" to filter out visit_dimension entries that are not real visits
   * Sections beginning with a comment labeled "output" are optional statistics and are for checking or cross-site sharing.
   * Run the script and verify the views were created
 */
 /* optional truncate 
TRUNCATE TABLE [dbo].[loyalty_dev_summary] 

*/

DELETE FROM LOYALTY_DEV WHERE COHORT_NAME = 'MLHO_ARRVL'
GO

/* jgk - added an ephemeral filter to the cohort selection step. is much faster for some reason. can be disabled in the loyalty script. */
select patient_num, 'MLHO_ARRVL' AS cohort, max(start_date) as index_dt, min(start_date) as ephemeral_dt/* index_dt is their last visit in the capture period */
into #precohort
FROM VISIT_DIMENSION
WHERE START_DATE >= '20140101' AND START_DATE <= '20181231'
GROUP BY PATIENT_NUM;


DECLARE @cfilter udt_CohortFilter

INSERT INTO @cfilter (PATIENT_NUM, COHORT_NAME, INDEX_DT)
select patient_num, cohort, index_dt from #precohort where index_dt!=ephemeral_dt


EXEC [dbo].[usp_LoyaltyCohort_opt] @site='XXX', @lookbackYears=5,  @demographic_facts=1, @gendered=1, @cohort_filter=@cfilter, @output=0
--EXEC [dbo].[usp_LoyaltyCohort_opt] @site='UKY', @lookbackYears=2, @demographic_facts=1, @gendered=2, @cohort_filter=@cfilter, @output=0
--EXEC [dbo].[usp_LoyaltyCohort_opt] @site='MGB', @lookbackYears=5, @demographic_facts=0, @gendered=1, @cohort_filter=@cfilter, @output=1

/* OUTPUT: share percentage data */
/* this query is the output that should be shared across sites */
/* do not share patient level data from the Summary_Description = 'Patient Counts' records */
--/* these are for your internal use only */
/*SELECT DISTINCT LDS.COHORT_NAME, LDS.[SITE], LDS.[EXTRACT_DTTM], LDS.[LOOKBACK_YR], LDS.GENDER_DENOMINATORS_YN, LDS.[CUTOFF_FILTER_YN], LDS.[Summary_Description], LDS.[tablename], LDS.[Num_DX1], LDS.[Num_DX2], LDS.[MedUse1], LDS.[MedUse2]
, LDS.[Mammography], LDS.[PapTest], LDS.[PSATest], LDS.[Colonoscopy], LDS.[FecalOccultTest], LDS.[FluShot], LDS.[PneumococcalVaccine], LDS.[BMI], LDS.[A1C], LDS.[MedicalExam], LDS.[INP1_OPT1_Visit], LDS.[OPT2_Visit], LDS.[ED_Visit]
, LDS.[MDVisit_pname2], LDS.[MDVisit_pname3], LDS.[Routine_care_2], LDS.[Subjects_NoCriteria], LDS.[PredictiveScoreCutoff]
, LDS.[MEAN_10YRPROB], LDS.[MEDIAN_10YR_SURVIVAL], LDS.[MODE_10YRPROB], LDS.[STDEV_10YRPROB]
, LDS.PercentPopulation
, LDS.PercentSubjectsFemale
, LDS.PercentSubjectsMale
, LDS.AverageFactCount
, LDS.[RUNTIMEms]
FROM [dbo].[loyalty_dev_summary] LDS
WHERE LDS.Summary_Description = 'PercentOfSubjects'
  AND COHORT_NAME = 'MLHO_ARRVL'
ORDER BY LDS.COHORT_NAME, LDS.LOOKBACK_YR, LDS.GENDER_DENOMINATORS_YN, LDS.CUTOFF_FILTER_YN, LDS.TABLENAME;*/

/* PULLING THE RETURN VISIT DATA POINTS FOR 6MO AND 1YR */

DROP TABLE DBO.LOYALTY_MLHO_ARRVL
GO


;WITH COHORT AS (
SELECT LD.*
  , [CHARLSON_INDEX], [CHARLSON_10YR_PROB], [MI], [CHF], [CVD], [PVD], [DEMENTIA], [COPD], [RHEUMDIS], [PEPULCER], [MILDLIVDIS], [DIABETES_NOCC], [DIABETES_WTCC], [HEMIPARAPLEG], [RENALDIS], [CANCER], [MSVLIVDIS], [METASTATIC], [AIDSHIV]
FROM DBO.LOYALTY_DEV LD
  JOIN DBO.LOYALTY_CHARLSON_DEV LCD
    ON LD.PATIENT_NUM = LCD.PATIENT_NUM
    AND LD.COHORT_NAME = LCD.COHORT_NAME
    AND LD.LOOKBACK_YEARS = LCD.LOOKBACK_YEARS
    AND LD.GENDER_DENOMINATORS_YN = LCD.GENDER_DENOMINATORS_YN
    AND isnull(LD.DEATH_DT,'20990101')>dateadd(year, 1, INDEX_DT) --- remove pts that died before end of measure period plus one year
WHERE LD.COHORT_NAME = 'MLHO_ARRVL'
)
, CTE_1Y AS (
SELECT V.PATIENT_NUM
  , MIN(V.START_DATE) AS FIRST_VISIT_1Y
  , DATEDIFF(DD,C.index_dt,MIN(V.START_DATE)) AS DELTA_FIRST_VISIT_1Y
  , COUNT(DISTINCT V.ENCOUNTER_NUM) AS CNTD_VISITS_1Y
FROM COHORT C
  JOIN DBO.VISIT_DIMENSION V
    ON C.patient_num = V.PATIENT_NUM
    AND V.START_DATE BETWEEN DATEADD(DD,1,C.index_dt) AND DATEADD(YY,1,C.INDEX_DT)
    -- JGK filter out false visits
	and start_date!=end_date -- filter out instantaneous visits, which are usually lab results (jgk)
	and sourcesystem_cd not like '%PB' -- jgk Professional billing, which is listed as a visit. This works because such stays have only one sourcesystem, from victor's analysis.
GROUP BY V.PATIENT_NUM, C.INDEX_DT
)
, CTE_6MO AS (
SELECT V.PATIENT_NUM
  , MIN(V.START_DATE) AS FIRST_VISIT_6MO
  , DATEDIFF(DD,C.INDEX_DT,MIN(V.START_DATE)) AS DELTA_FIRST_VISIT_6MO
  , COUNT(DISTINCT V.ENCOUNTER_NUM) AS CNTD_VISITS_6MO
FROM COHORT C
  JOIN DBO.VISIT_DIMENSION V
    ON C.PATIENT_NUM = V.PATIENT_NUM
    AND V.START_DATE BETWEEN DATEADD(DD,1,C.INDEX_DT) AND DATEADD(MM,6,C.INDEX_DT)
	-- Note: You can add site-specific checks here to ensure the visit is a real encounter
	-- These filters are MGB specific
	--	and start_date!=end_date -- filter out instantaneous visits, which are usually lab results (jgk)
	--	and sourcesystem_cd not like '%PB' -- jgk Professional billing, which is listed as a visit. This works because such stays have only one sourcesystem, from victor's analysis.
GROUP BY V.PATIENT_NUM, C.INDEX_DT
)
SELECT C.*, C6.FIRST_VISIT_6MO, C6.DELTA_FIRST_VISIT_6MO, C6.CNTD_VISITS_6MO, C1.FIRST_VISIT_1Y, C1.DELTA_FIRST_VISIT_1Y, C1.CNTD_VISITS_1Y
INTO DBO.LOYALTY_MLHO_ARRVL
FROM COHORT C
  LEFT JOIN CTE_6MO C6
    ON C.PATIENT_NUM = C6.PATIENT_NUM
  LEFT JOIN CTE_1Y C1
    ON C.PATIENT_NUM = C1.PATIENT_NUM
GO

/* OUTPUT SOME FREQUENCIES TO CHECK THE ABOVE RESULTS */
/*SELECT DECILE, DENOMINATOR, N_6MO, N_1Y
  , 1.0*N_6MO/DENOMINATOR AS RATE_6MO
  , 1.0*N_1Y/DENOMINATOR AS RATE_1Y
FROM (
SELECT DECILE, COUNT(DISTINCT PATIENT_NUM) DENOMINATOR
  , SUM(CASE WHEN FIRST_VISIT_6MO IS NOT NULL THEN 1 ELSE NULL END) AS N_6MO
  , SUM(CASE WHEN FIRST_VISIT_1Y IS NOT NULL THEN 1 ELSE NULL END) AS N_1Y
FROM (
SELECT PATIENT_NUM, Predicted_score
  , NTILE(10) OVER (ORDER BY PREDICTED_SCORE DESC) AS DECILE
  , FIRST_VISIT_6MO, FIRST_VISIT_1Y
FROM DBO.LOYALTY_MLHO_ARRVL
)D
GROUP BY DECILE
)S
ORDER BY 1 ASC*/

/* OUTPUT min/max score by  decile */
/*select min(predicted_score),max(predicted_score),decile from
(SELECT PATIENT_NUM, Predicted_score
  , NTILE(10) OVER (ORDER BY PREDICTED_SCORE DESC) AS DECILE
  , FIRST_VISIT_6MO, FIRST_VISIT_1Y
FROM DBO.LOYALTY_MLHO_ARRVL) x
group by decile
*/

--SELECT QUINTILE, DENOMINATOR, N_6MO, N_1Y
--  , 1.0*N_6MO/DENOMINATOR AS RATE_6MO
--  , 1.0*N_1Y/DENOMINATOR AS RATE_1Y
--FROM (
--SELECT QUINTILE, COUNT(DISTINCT PATIENT_NUM) DENOMINATOR
--  , SUM(CASE WHEN FIRST_VISIT_6MO IS NOT NULL THEN 1 ELSE NULL END) AS N_6MO
--  , SUM(CASE WHEN FIRST_VISIT_1Y IS NOT NULL THEN 1 ELSE NULL END) AS N_1Y
--FROM (
--SELECT PATIENT_NUM, Predicted_score
--  , NTILE(5) OVER (ORDER BY PREDICTED_SCORE DESC) AS QUINTILE
--  , FIRST_VISIT_6MO, FIRST_VISIT_1Y
--FROM DBO.LOYALTY_MLHO_ARRVL
--)D
--GROUP BY QUINTILE
--)S
--ORDER BY 1 ASC

--SELECT NAME, CONCAT(', NULLIF([',C.NAME,'],0) AS ',C.NAME,' ')
--FROM sys.columns C
--where object_id = object_id(N'DBO.LOYALTY_MLHO_ARRVL')
--ORDER BY column_id
--GO
-- ** THIS IS THE MAIN SECTION THAT BUILDS VIEWS FOR THE R ANALYSIS! **
 
CREATE OR ALTER VIEW LOYALTY_MLHO_LABELDT_VW AS --dbmart
SELECT PATIENT_NUM, INDEX_DT AS START_DT, FEAT AS PHENX
FROM (
SELECT PATIENT_NUM
, INDEX_DT
, CONVERT(NVARCHAR(50),NULLIF([NUM_DX1],0)) AS NUM_DX1
, CONVERT(NVARCHAR(50),NULLIF([NUM_DX2],0)) AS NUM_DX2
, CONVERT(NVARCHAR(50),NULLIF([MED_USE1],0)) AS MED_USE1
, CONVERT(NVARCHAR(50),NULLIF([MED_USE2],0)) AS MED_USE2
, CONVERT(NVARCHAR(50),NULLIF([MAMMOGRAPHY],0)) AS MAMMOGRAPHY
, CONVERT(NVARCHAR(50),NULLIF([PAP_TEST],0)) AS PAP_TEST
, CONVERT(NVARCHAR(50),NULLIF([PSA_TEST],0)) AS PSA_TEST
, CONVERT(NVARCHAR(50),NULLIF([COLONOSCOPY],0)) AS COLONOSCOPY
, CONVERT(NVARCHAR(50),NULLIF([FECAL_OCCULT_TEST],0)) AS FECAL_OCCULT_TEST
, CONVERT(NVARCHAR(50),NULLIF([FLU_SHOT],0)) AS FLU_SHOT
, CONVERT(NVARCHAR(50),NULLIF([PNEUMOCOCCAL_VACCINE],0)) AS PNEUMOCOCCAL_VACCINE
, CONVERT(NVARCHAR(50),NULLIF([BMI],0)) AS BMI 
, CONVERT(NVARCHAR(50),NULLIF([A1C],0)) AS A1C 
, CONVERT(NVARCHAR(50),NULLIF([MEDICAL_EXAM],0)) AS MEDICAL_EXAM
, CONVERT(NVARCHAR(50),NULLIF([INP1_OPT1_VISIT],0)) AS INP1_OPT1_VISIT
, CONVERT(NVARCHAR(50),NULLIF([OPT2_VISIT],0)) AS OPT2_VISIT
, CONVERT(NVARCHAR(50),NULLIF([ED_VISIT],0)) AS ED_VISIT
, CONVERT(NVARCHAR(50),NULLIF([MDVISIT_PNAME2],0)) AS MDVISIT_PNAME2
, CONVERT(NVARCHAR(50),NULLIF([MDVISIT_PNAME3],0)) AS MDVISIT_PNAME3
, CONVERT(NVARCHAR(50),NULLIF([ROUTINE_CARE_2],0)) AS ROUTINE_CARE2
FROM DBO.LOYALTY_MLHO_ARRVL
)O
UNPIVOT
(VALUE FOR FEAT IN ([NUM_DX1], [NUM_DX2], [MED_USE1], [MED_USE2], [MAMMOGRAPHY], [PAP_TEST], [PSA_TEST], [COLONOSCOPY], [FECAL_OCCULT_TEST], [FLU_SHOT], [PNEUMOCOCCAL_VACCINE], [BMI], [A1C], [MEDICAL_EXAM], [INP1_OPT1_VISIT], [OPT2_VISIT], [ED_VISIT], [MDVISIT_PNAME2], [MDVISIT_PNAME3], [ROUTINE_CARE2]))U
GO
CREATE OR ALTER VIEW LOYALTY_MLHO_DBMART6MO_VW AS -- labeldt6mo
SELECT PATIENT_NUM, isnull(CNTD_VISITS_6MO,0) AS LABEL
FROM DBO.LOYALTY_MLHO_ARRVL
GO

CREATE OR ALTER VIEW LOYALTY_MLHO_DBMART1Y_VW AS -- labeldt1y
SELECT PATIENT_NUM, isnull(CNTD_VISITS_1Y,0) AS LABEL
FROM DBO.LOYALTY_MLHO_ARRVL
GO

CREATE OR ALTER VIEW LOYALTY_MLHO_DEMOGRAPHIC_VW AS
SELECT patient_num, age, sex as gender, [LOOKBACK_YEARS], [SITE], [cohort_name], [index_dt], [AGE_GRP]
  , [Predicted_score], [CHARLSON_INDEX], [CHARLSON_10YR_PROB], [MI], [CHF], [CVD], [PVD], [DEMENTIA], [COPD], [RHEUMDIS]
  , [PEPULCER], [MILDLIVDIS], [DIABETES_NOCC], [DIABETES_WTCC], [HEMIPARAPLEG], [RENALDIS], [CANCER], [MSVLIVDIS], [METASTATIC], [AIDSHIV]
  , [FIRST_VISIT_6MO], [DELTA_FIRST_VISIT_6MO], [CNTD_VISITS_6MO], [FIRST_VISIT_1Y], [DELTA_FIRST_VISIT_1Y], [CNTD_VISITS_1Y]
FROM DBO.LOYALTY_MLHO_ARRVL
GO





s
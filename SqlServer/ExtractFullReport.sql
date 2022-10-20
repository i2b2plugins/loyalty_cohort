/* optional truncate 
TRUNCATE TABLE [dbo].[loyalty_dev_summary] 

*/

DECLARE @cfilter udt_CohortFilter

INSERT INTO @cfilter (PATIENT_NUM, COHORT_NAME, INDEX_DT)
SELECT DISTINCT PATIENT_NUM, SUBSTRING(COHORT,1,CHARINDEX('202',COHORT)-1) COHORT, ADMISSION_DATE /* grouping cohorts without YYYYQ# */
FROM [I2B2ACT].[4CEX2].[FourCE_LocalPatientSummary] /* SOURCE OF YOUR COHORT TO FILTER BY -- 4CE X.2 COHORT FOR EXAMPLE */


/* if you want to use a static index_dt for all patient */
--INSERT INTO @cfilter (PATIENT_NUM, COHORT_NAME, INDEX_DT)
--select distinct patient_num, substring(cohort,1,charindex('202',cohort)-1) cohort, '20220331' /* grouping cohorts without YYYYQ# */
--FROM [I2B2ACT].[4CEX2].[FourCE_LocalPatientSummary] /* SOURCE OF YOUR COHORT TO FILTER BY -- 4CE X.2 COHORT FOR EXAMPLE */

/* Alter @site parameter to your site */
/* If your site stores demographic facts set @demographics_facts=1, if there are no demographic facts in observation_fact set @demographic_facts=0 */
EXEC [DBO].[USP_LOYALTYCOHORT_OPT] @SITE='UKY', @LOOKBACK_YEARS=1,  @DEMOGRAPHIC_FACTS=1, @GENDERED=0, @COHORT_FILTER=@CFILTER, @OUTPUT=0
EXEC [DBO].[USP_LOYALTYCOHORT_OPT] @SITE='UKY', @LOOKBACK_YEARS=1,  @DEMOGRAPHIC_FACTS=1, @GENDERED=1, @COHORT_FILTER=@CFILTER, @OUTPUT=0
EXEC [DBO].[USP_LOYALTYCOHORT_OPT] @SITE='UKY', @LOOKBACK_YEARS=2,  @DEMOGRAPHIC_FACTS=1, @GENDERED=0, @COHORT_FILTER=@CFILTER, @OUTPUT=0
EXEC [DBO].[USP_LOYALTYCOHORT_OPT] @SITE='UKY', @LOOKBACK_YEARS=2,  @DEMOGRAPHIC_FACTS=1, @GENDERED=1, @COHORT_FILTER=@CFILTER, @OUTPUT=0
EXEC [DBO].[USP_LOYALTYCOHORT_OPT] @SITE='UKY', @LOOKBACK_YEARS=5,  @DEMOGRAPHIC_FACTS=1, @GENDERED=0, @COHORT_FILTER=@CFILTER, @OUTPUT=0
EXEC [DBO].[USP_LOYALTYCOHORT_OPT] @SITE='UKY', @LOOKBACK_YEARS=5,  @DEMOGRAPHIC_FACTS=1, @GENDERED=1, @COHORT_FILTER=@CFILTER, @OUTPUT=0
EXEC [DBO].[USP_LOYALTYCOHORT_OPT] @SITE='UKY', @LOOKBACK_YEARS=10, @DEMOGRAPHIC_FACTS=1, @GENDERED=0, @COHORT_FILTER=@CFILTER, @OUTPUT=0
EXEC [DBO].[USP_LOYALTYCOHORT_OPT] @SITE='UKY', @LOOKBACK_YEARS=10, @DEMOGRAPHIC_FACTS=1, @GENDERED=1, @COHORT_FILTER=@CFILTER, @OUTPUT=0

/* share percentage data */
/* this query is the output that should be shared across sites */
/* do not share patient level data from the Summary_Description = 'Patient Counts' records */
/* these are for your internal use only */
SELECT DISTINCT LDS.COHORT_NAME, LDS.[SITE], LDS.[EXTRACT_DTTM], LDS.[LOOKBACK_YR], LDS.GENDER_DENOMINATORS_YN, LDS.[CUTOFF_FILTER_YN], LDS.[SUMMARY_DESCRIPTION], LDS.[TABLE_NAME], LDS.[NUM_DX1], LDS.[NUM_DX2], LDS.[MED_USE1], LDS.[MED_USE2]
, LDS.[MAMMOGRAPHY], LDS.[PAP_TEST], LDS.[PSA_TEST], LDS.[COLONOSCOPY], LDS.[FECAL_OCCULT_TEST], LDS.[FLU_SHOT], LDS.[PNEUMOCOCCAL_VACCINE], LDS.[BMI], LDS.[A1C], LDS.[MEDICAL_EXAM], LDS.[INP1_OPT1_VISIT], LDS.[OPT2_VISIT], LDS.[ED_VISIT]
, LDS.[MDVISIT_PNAME2], LDS.[MDVISIT_PNAME3], LDS.[ROUTINE_CARE_2], LDS.[SUBJECTS_NOCRITERIA], LDS.[PREDICTIVESCORECUTOFF]
, LDS.[MEAN_10YR_PROB], LDS.[MEDIAN_10YR_PROB], LDS.[MODE_10YR_PROB], LDS.[STDEV_10YR_PROB]
, LDS.PERCENT_POPULATION
, LDS.PERCENT_SUBJECTS_FEMALE
, LDS.PERCENT_SUBJECTS_MALE
, LDS.AVERAGE_FACT_COUNT
, LDS.[RUNTIME_MS]
FROM [DBO].[LOYALTY_DEV_SUMMARY] LDS
WHERE LDS.SUMMARY_DESCRIPTION = 'PERCENT SUBJECTS' 
ORDER BY LDS.COHORT_NAME, LDS.LOOKBACK_YR, LDS.GENDER_DENOMINATORS_YN, LDS.CUTOFF_FILTER_YN, LDS.TABLENAME;

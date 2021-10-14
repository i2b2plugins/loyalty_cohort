/* optional truncate 
TRUNCATE TABLE [dbo].[loyalty_dev_summary] 

*/

DECLARE @cfilter udt_CohortFilter

INSERT INTO @cfilter (PATIENT_NUM, COHORT_NAME)
select distinct patient_num, substring(cohort,1,charindex('202',cohort)-1) cohort /* grouping cohorts without YYYYQ# */
FROM [I2B2ACT].[4CEX2].[FourCE_LocalPatientSummary] /* SOURCE OF YOUR COHORT TO FILTER BY -- 4CE X.2 COHORT FOR EXAMPLE */

/* Alter @site parameter to your site */
/* If your site stores demographic facts set @demographics_facts=1, if there are no demographic facts in observation_fact set @demographic_facts=0 */
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=1,  @demographic_facts=1, @gendered=0, @filter_by_existing_cohort=0, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=1,  @demographic_facts=1, @gendered=1, @filter_by_existing_cohort=0, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=2,  @demographic_facts=1, @gendered=0, @filter_by_existing_cohort=0, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=2,  @demographic_facts=1, @gendered=1, @filter_by_existing_cohort=0, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=5,  @demographic_facts=1, @gendered=0, @filter_by_existing_cohort=0, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=5,  @demographic_facts=1, @gendered=1, @filter_by_existing_cohort=0, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=10, @demographic_facts=1, @gendered=0, @filter_by_existing_cohort=0, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=10, @demographic_facts=1, @gendered=1, @filter_by_existing_cohort=0, @cohort_filter=@cfilter, @output=0

/* Filtered by existing cohort */
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=1,  @demographic_facts=1, @gendered=0, @filter_by_existing_cohort=1, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=1,  @demographic_facts=1, @gendered=1, @filter_by_existing_cohort=1, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=2,  @demographic_facts=1, @gendered=0, @filter_by_existing_cohort=1, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=2,  @demographic_facts=1, @gendered=1, @filter_by_existing_cohort=1, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=5,  @demographic_facts=1, @gendered=0, @filter_by_existing_cohort=1, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=5,  @demographic_facts=1, @gendered=1, @filter_by_existing_cohort=1, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=10, @demographic_facts=1, @gendered=0, @filter_by_existing_cohort=1, @cohort_filter=@cfilter, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=10, @demographic_facts=1, @gendered=1, @filter_by_existing_cohort=1, @cohort_filter=@cfilter, @output=0


SELECT distinct LDS. FILTER_BY_COHORT_YN, LDS.COHORT_NAME, LDS.[SITE], LDS.[EXTRACT_DTTM], LDS.[LOOKBACK_YR], LDS.GENDER_DENOMINATORS_YN, LDS.[CUTOFF_FILTER_YN], LDS.[Summary_Description], LDS.[tablename], LDS.[Num_DX1], LDS.[Num_DX2], LDS.[MedUse1], LDS.[MedUse2]
, LDS.[Mammography], LDS.[PapTest], LDS.[PSATest], LDS.[Colonoscopy], LDS.[FecalOccultTest], LDS.[FluShot], LDS.[PneumococcalVaccine], LDS.[BMI], LDS.[A1C], LDS.[MedicalExam], LDS.[INP1_OPT1_Visit], LDS.[OPT2_Visit], LDS.[ED_Visit]
, LDS.[MDVisit_pname2], LDS.[MDVisit_pname3], LDS.[Routine_care_2], LDS.[Subjects_NoCriteria], LDS.[PredictiveScoreCutoff]
, LDS.[MEAN_10YRPROB], LDS.[MEDIAN_10YR_SURVIVAL], LDS.[MODE_10YRPROB], LDS.[STDEV_10YRPROB]
, FORMAT(1.0*LDS.TotalSubjects/T.TotalSubjects,'P') AS PercPopulation
, FORMAT(1.0*LDS.[TotalSubjectsFemale]/LDS.[TotalSubjects],'P') AS PercentFemale
, FORMAT(1.0*LDS.[TotalSubjectsMale]/LDS.[TotalSubjects],'P') AS PercentMale
, ROUND(LDS.AverageFactCount,4) AS AverageFactCount
, LDS.[RUNTIMEms]
FROM [dbo].[loyalty_dev_summary] lds
  JOIN [dbo].[loyalty_dev_summary] T 
  ON T.COHORT_NAME = LDS.COHORT_NAME
    AND T.SITE = LDS.SITE 
    AND T.EXTRACT_DTTM = LDS.EXTRACT_DTTM 
    AND T.LOOKBACK_YR = LDS.LOOKBACK_YR
    AND T.GENDER_DENOMINATORS_YN = LDS.GENDER_DENOMINATORS_YN
    AND T.CUTOFF_FILTER_YN = LDS.CUTOFF_FILTER_YN
    AND T.Summary_Description = 'PercentOfSubjects'
    AND T.tablename = 'All Patients'
WHERE LDS.Summary_Description = 'PercentOfSubjects' 
ORDER BY LDS.FILTER_BY_COHORT_YN, LDS.COHORT_NAME, LDS.GENDER_DENOMINATORS_YN, LDS.LOOKBACK_YR, LDS.CUTOFF_FILTER_YN, LDS.TABLENAME;




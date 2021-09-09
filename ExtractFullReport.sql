/* optional truncate 
TRUNCATE TABLE [dbo].[loyalty_dev_summary] 

*/

/* Alter @site parameter to your site */
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=1, @gendered=0, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=1, @gendered=1, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=2, @gendered=0, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=2, @gendered=1, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=5, @gendered=0, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=5, @gendered=1, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=10, @gendered=0, @output=0
EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=10, @gendered=1, @output=0

SELECT [SITE], [EXTRACT_DTTM], [LOOKBACK_YR], GENDER_DENOMINATORS_YN, [CUTOFF_FILTER_YN], [Summary_Description], [tablename], [Num_DX1], [Num_DX2], [MedUse1], [MedUse2]
, [Mammography], [PapTest], [PSATest], [Colonoscopy], [FecalOccultTest], [FluShot], [PneumococcalVaccine], [BMI], [A1C], [MedicalExam], [INP1_OPT1_Visit], [OPT2_Visit], [ED_Visit]
, [MDVisit_pname2], [MDVisit_pname3], [Routine_care_2], [Subjects_NoCriteria], [PredictiveScoreCutoff]
, [MEAN_10YRPROB], [MEDIAN_10YR_SURVIVAL], [MODE_10YRPROB], [STDEV_10YRPROB]
, [TotalSubjects], [TotalSubjectsFemale], [TotalSubjectsMale]
, FORMAT(1.0*[TotalSubjectsFemale]/[TotalSubjects],'P') AS PercentFemale
, FORMAT(1.0*[TotalSubjectsMale]/[TotalSubjects],'P') AS PercentMale
, [RUNTIMEms]
FROM [dbo].[loyalty_dev_summary] 
WHERE Summary_Description = 'PercentOfSubjects' and convert(date,EXTRACT_DTTM) = convert(date,getdate())
ORDER BY GENDER_DENOMINATORS_YN, LOOKBACK_YR, CUTOFF_FILTER_YN, TABLENAME;


-- 465s not complete
-- optional truncate
--set define on
--select * from loyalty_dev_summary;
TRUNCATE TABLE loyalty_dev_summary;
--set echo on;
declare
v_sql LONG;
begin

v_sql:='create table LOYALTY_COHORT
  (
    PATIENT_NUM NUMBER NOT NULL,
    COHORT_NAME varchar2(30) NULL,
    INDEXDATE DATE NOT NULL
  )';
execute immediate v_sql;

EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -955 THEN
        NULL; -- suppresses ORA-00955 exception
      ELSE
         RAISE;
      END IF;
END;
/
TRUNCATE TABLE LOYALTY_COHORT;
INSERT INTO LOYALTY_COHORT (PATIENT_NUM, COHORT_NAME, INDEXDATE)
SELECT DISTINCT PATIENT_NUM, 'LOYALTY_TEST_DATA', TO_DATE('31-MAR-2022') FROM SYNTHEA_ADDON_PAT_DIM;
COMMIT;
-- create a cohort table - this can be your entire data mart
--INSERT INTO @cfilter (PATIENT_NUM, COHORT_NAME, INDEX_DT)
--select distinct patient_num, substring(cohort,1,charindex('202',cohort)-1) cohort, admission_date /* grouping cohorts without YYYYQ# */
--FROM I2B2ACT.4CEX2.FourCE_LocalPatientSummary /* SOURCE OF YOUR COHORT TO FILTER BY -- 4CE X.2 COHORT FOR EXAMPLE */


/* if you want to use a static index_dt for all patient */
--INSERT INTO @cfilter (PATIENT_NUM, COHORT_NAME, INDEX_DT)
--select distinct patient_num, substring(cohort,1,charindex('202',cohort)-1) cohort, '20220331' /* grouping cohorts without YYYYQ# */
--FROM I2B2ACT.4CEX2.FourCE_LocalPatientSummary /* SOURCE OF YOUR COHORT TO FILTER BY -- 4CE X.2 COHORT FOR EXAMPLE */

/* Alter @site parameter to your site */
/* If your site stores demographic facts set @demographics_facts=1, if there are no demographic facts in observation_fact set @demographic_facts=0 */
--@C:\DevTools\NCATS\ACT\Research\LoyaltyCohortOracleSynthea.sql INDEXDATE LOOKBACKYEARS SHOWOUTPUT DEMFACTDATE SITE GENDERED cutoff
@C:\DevTools\NCATS\ACT\Research\LoyaltyCohortOracleSynthea.sql "31-MAR-2022" 10 2 "31-MAR-2012" "UPITT" 1

commit;

--select * from loyalty_dev_summary;
/* share percentage data */
/* this query is the output that should be shared across sites */
/* do not share patient level data from the Summary_Description = 'Patient Counts' records */
/* these are for your internal use only */
/*
SELECT DISTINCT 
LOYALTY_COHORT_SCHEMA.COHORT_NAME, 
LOYALTY_COHORT_SCHEMA.SITE, 
LOYALTY_COHORT_SCHEMA.EXTRACT_DTTM, 
LOYALTY_COHORT_SCHEMA.LOOKBACK_YR, 
LOYALTY_COHORT_SCHEMA.GENDER_DENOMINATORS_YN, 
LOYALTY_COHORT_SCHEMA.CUTOFF_FILTER_YN, 
LOYALTY_COHORT_SCHEMA.Summary_Description, LOYALTY_COHORT_SCHEMA.tablename, 
LOYALTY_COHORT_SCHEMA.Num_DX1, 
LOYALTY_COHORT_SCHEMA.Num_DX2, LOYALTY_COHORT_SCHEMA.MedUse1, 
LOYALTY_COHORT_SCHEMA.MedUse2,
LOYALTY_COHORT_SCHEMA.Mammography, LOYALTY_COHORT_SCHEMA.PapTest, 
LOYALTY_COHORT_SCHEMA.PSATest, LOYALTY_COHORT_SCHEMA.Colonoscopy, 
LOYALTY_COHORT_SCHEMA.FecalOccultTest, LOYALTY_COHORT_SCHEMA.FluShot, 
LOYALTY_COHORT_SCHEMA.PneumococcalVaccine, LOYALTY_COHORT_SCHEMA.BMI, 
LOYALTY_COHORT_SCHEMA.A1C, LOYALTY_COHORT_SCHEMA.MedicalExam, 
LOYALTY_COHORT_SCHEMA.INP1_OPT1_Visit, LOYALTY_COHORT_SCHEMA.OPT2_Visit, 
LOYALTY_COHORT_SCHEMA.ED_Visit, LOYALTY_COHORT_SCHEMA.MDVisit_pname2, 
LOYALTY_COHORT_SCHEMA.MDVisit_pname3, 
LOYALTY_COHORT_SCHEMA.Routine_care_2, 
LOYALTY_COHORT_SCHEMA.Subjects_NoCriteria,
LOYALTY_COHORT_SCHEMA.PredictiveScoreCutoff,
LOYALTY_COHORT_SCHEMA.MEAN_10YRPROB, LOYALTY_COHORT_SCHEMA.MEDIAN_10YR_SURVIVAL,
LOYALTY_COHORT_SCHEMA.MODE_10YRPROB, LOYALTY_COHORT_SCHEMA.STDEV_10YRPROB, 
LOYALTY_COHORT_SCHEMA.PercentPopulation,
LOYALTY_COHORT_SCHEMA.PercentSubjectsFemale,
LOYALTY_COHORT_SCHEMA.PercentSubjectsMale,
LOYALTY_COHORT_SCHEMA.AverageFactCount,
NULL RUNTIMEms
FROM dbo.loyalty_dev_summary LOYALTY_COHORT_SCHEMA
WHERE LOYALTY_COHORT_SCHEMA.Summary_Description = 'PercentOfSubjects' --ONLY SHARE PERCENTAGE DATA
ORDER BY LOYALTY_COHORT_SCHEMA.COHORT_NAME, LOYALTY_COHORT_SCHEMA.LOOKBACK_YR, 
LOYALTY_COHORT_SCHEMA.GENDER_DENOMINATORS_YN, LOYALTY_COHORT_SCHEMA.CUTOFF_FILTER_YN,
LOYALTY_COHORT_SCHEMA.TABLENAME;
*/
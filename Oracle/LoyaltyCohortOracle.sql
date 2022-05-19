--select * from observation_fact where concept_cd like 'ICD10%';
-- is pname2 = 2 and pname3 >-3?
-- Explicitly clear out table when you are ready
--select * from loyalty_dev_summary;

declare
v_sql LONG;
begin

v_sql:='create table loyalty_dev_summary
  (
    COHORT_NAME varchar2(30) NULL,
    SITE VARCHAR(10) NOT NULL,
    LOOKBACK_YR number(10) NOT NULL,
    GENDER_DENOMINATORS_YN char(1) NOT NULL,
    CUTOFF_FILTER_YN char(1) NOT NULL,
    Summary_Description varchar(20) NOT NULL,
	tablename varchar(20) NULL,
	Num_DX1 number NULL,
	Num_DX2 number NULL,
	MedUse1 number NULL,
	MedUse2 number NULL,
	Mammography number NULL,
	PapTest number NULL,
	  PSATest number NULL,
	  Colonoscopy number NULL,
	  FecalOccultTest number NULL,
	  FluShot number NULL,
	  PneumococcalVaccine number NULL,
	  BMI number NULL,
	  A1C number NULL,
	  MedicalExam number NULL,
	  INP1_OPT1_Visit number NULL,
	  OPT2_Visit number NULL,
	  ED_Visit number NULL,
	  MDVisit_pname2 number NULL,
	  MDVisit_pname3 number NULL,
	  Routine_care_2 number NULL,
	  Subjects_NoCriteria number NULL,
	  PredictiveScoreCutoff number NULL,
	  MEAN_10YRPROB number NULL,
	  MEDIAN_10YR_SURVIVAL number NULL,
	  MODE_10YRPROB number NULL,
	  STDEV_10YRPROB number NULL,
    TotalSubjects number NULL,
    TotalSubjectsFemale number NULL,
    TotalSubjectsMale number NULL,
    percentsubjectsfemale char(10),
    percentsubjectsmale  char(10))';
    --percentpopulatin
    --averagefactcount
    --extract_dttm
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
-- Set variables

drop table constants;
CREATE TABLE 
CONSTANTS (
INDEXDATE DATE,
LOOKBACKYEARS NUMBER(2),
SHOWOUTPUT NUMBER(1),
DEMFACTDATE DATE,
SITE VARCHAR2(100),
GENDERED NUMBER(1)
);
--20220331
truncate table constants;
INSERT INTO CONSTANTS 
SELECT 
TO_DATE('&1') AS INDEXDATE, --TO_DATE('31-MAR-2022') AS INDEXDATE,
TO_NUMBER('&2') AS lookbackYears,
TO_NUMBER('&3') AS  showOutput,
TO_DATE('&4') AS demFactDate,
'&5' AS Site,
TO_NUMBER('&6') AS GENDERED
FROM DUAL;
COMMIT;
select * from constants;
commit;
--set define off
--TODO: Audit the xref tables for typos and new paths
--when to drop dead - don't drop - add another column to table to filter on later 
--if 2 and 3 do you only get the one flag is 2 = keep provider not null 
--when do dem only pts get dropped

DROP TABLE LOYALTY_COHORT_AGEGRP;
--select count(*) from LOYALTY_COHORT_AGEGRP; --460850
--select count(*) from LOYALTY_COHORT_AGEGRP where predicted_score = -0.010; --460850 -- i don't have any patients with predicted score 0, 20901 -0.01 means they have no features
--select sum(freq) from (
--select predicted_score, count(*) freq from LOYALTY_COHORT_AGEGRP group by predicted_score order by predicted_score;
--);-- where predicted_score = -0.010; --460850 -- i don't have any patients with predicted score 0, 20901 -0.01 means they have no features
--select * from LOYALTY_COHORT_AGEGRP order by predicted_score desc;
--LOYALTY_DEV
--207 sec
DROP TABLE LOYALTY_COHORT_AGEGRP;
CREATE TABLE LOYALTY_COHORT_AGEGRP AS 
SELECT * FROM (
--The cohort is any patient that has had a visit during the time period
--Get patient's last visit during time period
--MICHELE change this to match darrens cohort and then eliminate the effemoral patiens
WITH VISIT_ONTOLOGY AS 
( 
SELECT * FROM NCATS_VISIT_DETAILS  --ACT_VISIT_DETAILS_V4 c -- THIS NEEDS TO POINT TO METADATA SCHEMA
),
--select * from visit_ontology;
COHORT_IN_PERIOD AS
(
-- in covid_crcdata
SELECT V.PATIENT_NUM, MAX(V.START_DATE) LAST_VISIT, COHORT_NAME
FROM LOYALTY_COHORT c
JOIN synthea_addon_vis_dim V ON V.PATIENT_NUM = C.PATIENT_NUM
CROSS JOIN CONSTANTS x
--WHERE V.START_DATE between add_months( trunc(to_date('&indexDate')), -12*X.LOOKBACKYEARS) and to_date('&indexDate')
WHERE V.START_DATE between add_months( trunc(X.INDEXDATE), -12*X.LOOKBACKYEARS) and X.INDEXDATE
GROUP BY C.COHORT_NAME, V.PATIENT_NUM

),
--select * from LOYALTY_COHORT; 
--select * from constants;
--select count(*) from LOYALTY_COHORT; --433334
--436482
--select count(*) from COHORT_IN_PERIOD;
--Get codes for observation_fact facts
SIMPLE_FEATURES AS ( 
select distinct Feature_name, concept_cd, code_type --[ACT_PATH], 
from xref_LoyaltyCode_paths L, CONCEPT_DIMENSION c
where C.CONCEPT_PATH like L.Act_path||'%'  
--AND FEATURE_NAME = 'PapTest'
AND code_type IN ('DX','PX','LAB','MEDS','SITE','DEM') 
and (act_path <> '**Not Found' and act_path is not null)
ORDER BY FEATURE_NAME),
--select count(*) from SIMPLE_FEATURES; --1377645
--select * from xref_LoyaltyCode_paths;

-- Get codes for visit_dimension facts
VISIT_FEATURES AS ( 
select distinct FEATURE_NAME, C_BASECODE CONCEPT_CD, code_type  
from xref_LoyaltyCode_paths L, VISIT_ONTOLOGY C
where C.C_FULLNAME like L.Act_path||'%'  
AND code_type IN ('VISIT') 
and (act_path <> '**Not Found' and act_path is not null)
ORDER BY FEATURE_NAME),-- select * from visit_features;--, 

--FIX THIS these features are fact based not visit based
-- Get codes for visit_dimension facts
MD_VISIT_FEATURES AS ( 
select distinct FEATURE_NAME, CONCEPT_CD, code_type  
from xref_LoyaltyCode_paths L, CONCEPT_DIMENSION c -- THIS NEEDS TO POINT TO METADATA SCHEMA
where C.CONCEPT_PATH like L.Act_path||'%'  
AND feature_name in ('MDVisit_pname2', 'MDVisit_pname3')
and (act_path <> '**Not Found' and act_path is not null)
--and (provider_id <> '@' and provider_id is not null)
ORDER BY FEATURE_NAME),-- select * from MD_VISIT_FEATURES;--,

--routine_care_2 is two of any of the following features
--('MedicalExam','Mammography','PSATest','Colonoscopy','FecalOccultTest','FluShot','PneumococcalVaccine','A1C','BMI')
ROUTINE_CARE_codes AS (
select distinct Feature_name, concept_cd, code_type --[ACT_PATH], 
from xref_LoyaltyCode_paths L, CONCEPT_DIMENSION c
where C.CONCEPT_PATH like L.Act_path||'%'  
AND feature_name IN ('MedicalExam','Mammography','PSATest','Colonoscopy','FecalOccultTest','FluShot','PneumococcalVaccine','A1C','BMI' ) 
and (act_path <> '**Not Found' and act_path is not null)
ORDER BY FEATURE_NAME
),-- select * from ROUTINE_CARE_codes;
--Create a routine care feature 
ROUTINE_CARE_FEATURES AS
(
select 'Routine_Care_2' feature_name, concept_cd, code_type  from ROUTINE_CARE_codes
),-- select * from ROUTINE_CARE_FEATURES; --,
-- Add routine_care_2 to the list of features
FEATURES AS 
(
select feature_name, concept_cd, code_type  from ROUTINE_CARE_FEATURES
union 
select feature_name, concept_cd, code_type  from SIMPLE_FEATURES
), --select * from FEATURES;
--Create demographic feature codes - do not use dates because demographic facts are not date based
PT_DEM_FEATURE_COUNT_BY_DATE AS ( 
SELECT PATIENT_NUM, FEATURE_NAME,  COUNT(DISTINCT TRUNC(O.START_DATE)) DISTINCT_ENCOUNTERS, COEFF
FROM synthea_obs_fact O
JOIN FEATURES F ON F.CONCEPT_CD = O.CONCEPT_CD
JOIN xref_LoyaltyCode_PSCoeff C ON C.FIELD_NAME = F.FEATURE_NAME
WHERE FEATURE_NAME = 'Demographics' 
GROUP BY PATIENT_NUM, FEATURE_NAME, C.COEFF
ORDER BY PATIENT_NUM, FEATURE_NAME
), --select * from PT_DEM_FEATURE_COUNT_BY_DATE;

--Get visit counts and the coefficients
PT_VIS_FEATURE_COUNT_BY_DATE AS ( -- VISIT WITHIN TIME FRAME OF INTEREST
SELECT PATIENT_NUM, FEATURE_NAME,  COUNT(DISTINCT TRUNC(V.START_DATE)) DISTINCT_ENCOUNTERS, C.COEFF
FROM synthea_addon_vis_dim V
JOIN VISIT_FEATURES F ON F.CONCEPT_CD = V.INOUT_CD
JOIN xref_LoyaltyCode_PSCoeff C ON C.FIELD_NAME = F.FEATURE_NAME
CROSS JOIN CONSTANTS x
WHERE CODE_TYPE = 'VISIT' AND 
--V.START_DATE between '01-JAN-16' and '01-JAN-21' --add_months( trunc(X.INDEXDATE), -12*X.LOOKBACKYEARS) and X.INDEXDATE
V.START_DATE between add_months( trunc(X.INDEXDATE), -12*X.LOOKBACKYEARS) and X.INDEXDATE
GROUP BY PATIENT_NUM, FEATURE_NAME, C.COEFF
ORDER BY PATIENT_NUM, FEATURE_NAME
), 
--select * from PT_VIS_FEATURE_COUNT_BY_DATE;
-- Adjust the outpatient visit coeff. Make it zero if outpatient visits less than 2
ADJ_PT_VIS_FEATURE_COUNT_BY_DATE as (
SELECT PATIENT_NUM, 
FEATURE_NAME, 
DISTINCT_ENCOUNTERS,
CASE 
    WHEN FEATURE_NAME = 'OPT2_Visit' AND DISTINCT_ENCOUNTERS < 2 THEN 0
    ELSE COEFF
END COEFF
FROM PT_VIS_FEATURE_COUNT_BY_DATE
),
--select * from ADJ_PT_VIS_FEATURE_COUNT_BY_DATE);-- where patient_num = 82146

--Get the observation_fact feature counts and the coefficients
PT_FEATURE_COUNT_BY_DATE AS (
SELECT PATIENT_NUM, FEATURE_NAME,  COUNT(DISTINCT TRUNC(O.START_DATE)) DISTINCT_ENCOUNTERS, COEFF
FROM synthea_obs_fact O
CROSS JOIN CONSTANTS x
JOIN FEATURES F ON F.CONCEPT_CD = O.CONCEPT_CD
JOIN xref_LoyaltyCode_PSCoeff C ON C.FIELD_NAME = F.FEATURE_NAME
WHERE TRUNC(O.START_DATE) between add_months( X.INDEXDATE, -12*X.LOOKBACKYEARS) and X.INDEXDATE
GROUP BY PATIENT_NUM, FEATURE_NAME, C.COEFF
ORDER BY PATIENT_NUM, FEATURE_NAME
),
--select * from PT_FEATURE_COUNT_BY_DATE order by patient_num; --2105 s

--Adjust procedure visits since they need to have 2 or 3 and they require non null providers. 
--If they do not satisfy those conditions the coeff is zero and the feature will be omitted
MD_PX_VISITS_WITH_PROVIDER as (
SELECT PATIENT_NUM, 
FEATURE_NAME, 
DISTINCT_ENCOUNTERS,
CASE 
    WHEN FEATURE_NAME = 'MDVisit_pname2' AND DISTINCT_ENCOUNTERS <> 2  THEN 0
    WHEN FEATURE_NAME = 'MDVisit_pname3' AND DISTINCT_ENCOUNTERS < 3 THEN 0
    ELSE COEFF
END COEFF,
COEFF OLD_COEFF
FROM PT_FEATURE_COUNT_BY_DATE
), 
--select * from MD_PX_VISITS_WITH_PROVIDER where feature_name like 'MDV%');

--Adjust the rest of the count based features when condition is not met coeff = 0
-- can this be reordered so all of these are in one block
ADJ_PT_FEATURE_COUNT_BY_DATE as (
SELECT PATIENT_NUM, 
FEATURE_NAME, 
DISTINCT_ENCOUNTERS,
CASE 
    WHEN FEATURE_NAME = 'Routine_Care_2' AND DISTINCT_ENCOUNTERS < 2 THEN 0
    WHEN FEATURE_NAME = 'Num_DX1' AND DISTINCT_ENCOUNTERS > 1 THEN 0
    WHEN FEATURE_NAME = 'MedUse1' AND DISTINCT_ENCOUNTERS > 1 THEN 0
    WHEN FEATURE_NAME = 'Num_DX2' AND DISTINCT_ENCOUNTERS < 2 THEN 0
    WHEN FEATURE_NAME = 'MedUse2' AND DISTINCT_ENCOUNTERS < 2 THEN 0
    ELSE COEFF
END COEFF,
COEFF OLD_COEFF
FROM PT_FEATURE_COUNT_BY_DATE
),
--select * from ADJ_PT_FEATURE_COUNT_BY_DATE);

--merge all features from demographics (always zero coeff) + visit based features + observation_fact based features
ALL_FEATURE_COUNT_BY_DATE AS (
select PATIENT_NUM, FEATURE_NAME, DISTINCT_ENCOUNTERS, COEFF from (
select PATIENT_NUM, FEATURE_NAME, DISTINCT_ENCOUNTERS, COEFF from ADJ_PT_FEATURE_COUNT_BY_DATE
union 
select PATIENT_NUM, FEATURE_NAME, DISTINCT_ENCOUNTERS, COEFF from PT_DEM_FEATURE_COUNT_BY_DATE
union 
select PATIENT_NUM, FEATURE_NAME, DISTINCT_ENCOUNTERS, COEFF from ADJ_PT_VIS_FEATURE_COUNT_BY_DATE
)
order by patient_num
) , 
-- Sum coefficients for predicted score
COEFF_SUMS AS
(
select patient_num, 
SUM(COEFF) AS RAW_COEFF, -- used to determine facts that have none of the features coeff exactly zero
-0.010+SUM(COEFF) as sum_of_coeff
from ALL_FEATURE_COUNT_BY_DATE
group by patient_num
),--select * from coeff_sums order by patient_num);--,

--Pivot the rows to columns - make the WIDE table
PIVOT_PATIENTS AS 
(
SELECT * FROM 
  ( 
    SELECT patient_num,  feature_name, case when coeff <> 0 then 1 else 0 end coeff -- with coeffs turned to flags
    FROM ALL_FEATURE_COUNT_BY_DATE 
    --WHERE patient_num in (60,64,68) --for testing on small set
  ) 
  PIVOT ( 
    MAX(coeff) 
    FOR feature_name in
        ('Demographics' demographics,
        'MD visit' MD_visit,
        'Num_DX1' Num_DX1,
        'Num_DX2' Num_DX2,
        'MedUse1' MedUse1,
        'MedUse2' MedUse2,
        'MedicalExam' MedicalExam,
        'MDVisit_pname2' MDVisit_pname2,
        'MDVisit_pname3' MDVisit_pname3,
        'Mammography' Mammography,
        'BMI' BMI,
        'FluShot' FluShot,
        'PneumococcalVaccine' PneumococcalVaccine,
        'FecalOccultTest' FecalOccultTest,
        'PapTest' Paptest,
        'Colonoscopy' Colonoscopy,
        'PSATest' PSATest,
        'A1C' A1C,
        'Routine_Care_2' Routine_Care_2,
        'ED_Visit' ED_Visit,
        'INP1_OPT1_Visit' INP1_OPT1_Visit,
        'OPT2_Visit' OPT2_Visit
        ))
),

--Start building the final table
PREDICTIVE_SCORE AS 
(
select 
V.COHORT_NAME,
S.PATIENT_NUM,
case when raw_coeff <> 0 then 1 else 0 end as Subjects_NoCriteria,
--raw_coeff as Subjects_NoCriteria,  when showing full coeff
nvl(sum_of_coeff,0) AS Predicted_score,
last_visit AS LAST_VISIT,
D.BIRTH_DATE,
TRUNC(NVL(((to_date('01-FEB-21')-TRUNC(D.BIRTH_DATE))/365.25), 0)) AGE,
CASE WHEN TRUNC(NVL(((to_date('01-FEB-21')-TRUNC(D.BIRTH_DATE))/365.25), 0)) < 65 THEN 'Under 65'
     WHEN TRUNC(NVL(((to_date('01-FEB-21')-TRUNC(D.BIRTH_DATE))/365.25), 0)) >= 65 THEN 'Over 65'
     ELSE NULL
     END AGEGRP,
decode(D.SEX_CD,'DEM|SEX:F', 'F', 'DEM|SEX:M', 'M', NULL) SEX_CD,
nvl(Num_Dx1    ,0)          AS Num_Dx1            
,nvl(Num_Dx2    ,0)          AS Num_Dx2            
,nvl(MedUse1    ,0)          AS MedUse1            
,nvl(MedUse2    ,0)          AS MedUse2            
,nvl(Mammography,0)          AS Mammography        
,nvl(PapTest    ,0)          AS PapTest            
,nvl(PSATest    ,0)          AS PSATest            
,nvl(Colonoscopy,0)          AS Colonoscopy        
,nvl(FecalOccultTest,0)      AS FecalOccultTest    
,nvl(FluShot    ,0)          AS FluShot            
,nvl(PneumococcalVaccine,0)  AS PneumococcalVaccine
,nvl(BMI        ,0)          AS BMI                
,nvl(A1C        ,0)          AS A1C                
,nvl(MedicalExam,0)          AS MedicalExam        
,nvl(INP1_OPT1_Visit,0)      AS INP1_OPT1_Visit    
,nvl(OPT2_Visit ,0)          AS OPT2_Visit      
,nvl(ED_Visit   ,0)          AS ED_Visit           
,nvl(MDVisit_pname2,0)       AS MDVisit_pname2     
,nvl(MDVisit_pname3,0)       AS MDVisit_pname3     
,nvl(Routine_Care_2,0)       AS Routine_Care_2     
from COEFF_SUMS S 
LEFT JOIN COHORT_IN_PERIOD V ON V.PATIENT_NUM = S.PATIENT_NUM
LEFT JOIN SYNTHEA_ADDON_PAT_DIM D ON D.PATIENT_NUM = S.PATIENT_NUM
LEFT JOIN PIVOT_PATIENTS P ON P.PATIENT_NUM = S.PATIENT_NUM
),

-- get patient totals - subjects without any criteria have been filtered out - is this correct? TODO: Check in the meeting
TOTAL_PATIENTS AS 
(
select count(distinct patient_num) TOTAL_PATIENT from PREDICTIVE_SCORE  where Subjects_NoCriteria <> 0
),
TOTAL_PATIENTS_FEMALE AS 
(
select count(distinct patient_num) TOTAL_PATIENT_FEMALE from PREDICTIVE_SCORE where SEX_CD = 'F'  and Subjects_NoCriteria <> 0
),
TOTAL_PATIENTS_MALE AS --189482
(
select count(distinct patient_num) TOTAL_PATIENT_MALE from PREDICTIVE_SCORE where SEX_CD =  'M' and Subjects_NoCriteria <> 0
),
TOTAL_NO_CRITERIA AS --189482
(
select count(distinct patient_num) TOTAL_NO_CRITERIA from PREDICTIVE_SCORE where Subjects_NoCriteria = 0
)

--Final table
SELECT
    COHORT_NAME,
    p.patient_num,
    birth_date,
    Subjects_NoCriteria,
    predicted_score,
    TOTAL_NO_CRITERIA,
    TOTAL_PATIENT,
    TOTAL_PATIENT_MALE,
    TOTAL_PATIENT_FEMALE,
    last_visit,
    age,
    agegrp,
    sex_cd,
    num_dx1,
    num_dx2,
    meduse1,
    meduse2,
    mammography,
    paptest,
    psatest,
    colonoscopy,
    fecalocculttest,
    flushot,
    pneumococcalvaccine,
    bmi,
    a1c,
    medicalexam,
    inp1_opt1_visit,
    opt2_visit,
    ed_visit,
    mdvisit_pname2,
    mdvisit_pname3,
    routine_care_2
FROM
    PREDICTIVE_SCORE p
    CROSS JOIN TOTAL_PATIENTS
    CROSS JOIN TOTAL_PATIENTS_MALE
    CROSS JOIN TOTAL_PATIENTS_FEMALE
    CROSS JOIN TOTAL_NO_CRITERIA
); --END CREATE TABLE LOYALTY_COHORT_AGEGRP

COMMIT;
--SELECT * FROM LOYALTY_COHORT_AGEGRP ;--where rownum < 10;
-- Calculate Predictive Score Cutoff by over Agegroups  QUINTILE of DECILE???
drop table LOYALTY_AGEGRP_PSC;
CREATE TABLE LOYALTY_AGEGRP_PSC AS SELECT AGEGRP, MIN(PREDICTED_SCORE) PredictiveScoreCutoff
FROM (
SELECT AGEGRP, Predicted_score, NTILE(5) OVER (PARTITION BY AGEGRP ORDER BY PREDICTED_SCORE DESC) AS ScoreRank
FROM(
SELECT AGEGRP, predicted_score
from LOYALTY_cohort_agegrp
)SCORES
)M
WHERE ScoreRank=1
GROUP BY AGEGRP;
COMMIT;
--select * from LOYALTY_AGEGRP_PSC;

-- Calculate average fact counts over Agegroups 
--71SEC
drop table LOYALTY_AGEGRP_AFC;
--select * from LOYALTY_AGEGRP_AFC;
CREATE TABLE LOYALTY_AGEGRP_AFC AS 
SELECT CUTOFF_FILTER_YN, AGEGRP, TRUNC(AVG_FACT_COUNT,2) AVG_FACT_CNT
FROM
(
SELECT CAST('N' AS CHAR(1)) AS CUTOFF_FILTER_YN, cag.AGEGRP, 1.0*count(o.concept_cd)/count(distinct cag.patient_num) as AVG_FACT_COUNT
FROM LOYALTY_cohort_agegrp cag
CROSS JOIN CONSTANTS x
  join synthea_obs_fact O  ON cag.patient_num = O.PATIENT_NUM
WHERE    O.START_DATE between add_months( trunc(X.INDEXDATE), -12*X.LOOKBACKYEARS) and X.INDEXDATE
group by cag.AGEGRP
UNION ALL
SELECT CAST('Y' AS CHAR(1)) AS CUTOFF_FILTER_YN, cag.AGEGRP, 
1.0*count(o.concept_cd)/count(distinct cag.patient_num) as AVG_FACT_COUNT
FROM LOYALTY_cohort_agegrp cag
CROSS JOIN CONSTANTS x
  JOIN loyalty_AGEGRP_PSC PSC
    ON cag.AGEGRP = PSC.AGEGRP
      AND cag.Predicted_score >= PSC.PredictiveScoreCutoff
  join synthea_obs_fact O
    ON cag.patient_num = O.PATIENT_NUM
WHERE    O.START_DATE between add_months( trunc(X.INDEXDATE), -12*X.LOOKBACKYEARS) and X.INDEXDATE
group by cag.AGEGRP
)AFC;


--select count(*) from synthea_obs_fact; --71511691
--SELECT * FROM LOYALTY_AGEGRP_AFC;
--***********************************************************************************************************

/* OPTIONAL CHARLSON COMORBIDITY INDEX -- ADDS APPROX. 1m in UKY environment. 
   REQUIRES SITE TO LOAD LU_CHARLSON FROM REPO 
*/
-- NEED TO ADD INCLUSION OF LOCAL CODE SYNONYMS
DEFINE STEPTTS = sysdate;
--SELECT * FROM ncatstest2_metadata.aCT_ICD10CM_DX_V4;
--SELECT * FROM LOYALTY_CHARLSON_DX;

DROP TABLE LOYALTY_CHARLSON_DX;
CREATE INDEX LU_CHARLSON_pat ON LU_CHARLSON(DIAGPATTERN);
--SELECT * FROM LU_CHARLSON;
create table LU_CHARLSON_ORACLE AS SELECT CHARLSON_CATGRY, CHARLSON_WT, REGEXP_REPLACE(DIAGPATTERN, '%','') DIAGPATTERN FROM LU_CHARLSON;
COMMIT;
--SELECT * FROM LU_CHARLSON_ORACLE;
RENAME LOYALTY_CHARLSON_DX TO LOYALTY_CHARLSON_DX_CD;
CREATE TABLE LOYALTY_CHARLSON_DX AS
SELECT DISTINCT CHARLSON_CATGRY, CHARLSON_WT, C_BASECODE AS CONCEPT_CD
FROM (
SELECT C.CHARLSON_CATGRY, C.CHARLSON_WT, DX10.C_BASECODE
FROM LU_CHARLSON_ORACLE C
  JOIN ncatstest_metadata.ACT_ICD10CM_DX_V4 DX10
    ON REGEXP_LIKE(DX10.C_BASECODE, C.DIAGPATTERN));

insert into LOYALTY_CHARLSON_DX
SELECT C.CHARLSON_CATGRY, C.CHARLSON_WT, DX9.C_BASECODE CONCEPT_CD
FROM LU_CHARLSON_ORACLE C
  JOIN ncatstest_metadata.ACT_ICD9CM_DX_V4 DX9
    ON REGEXP_LIKE(DX9.C_BASECODE, C.DIAGPATTERN);

commit;
--SELECT * FROM LOYALTY_CHARLSON_DX;
DROP TABLE LOYALTY_CHARLSON_VISIT_BASE;
CREATE TABLE  LOYALTY_CHARLSON_VISIT_BASE AS
SELECT * FROM (
WITH CTE_VISIT_BASE AS (
    SELECT PATIENT_NUM, AGE, LAST_VISIT
    , CASE  WHEN AGE < 50 THEN 0
          WHEN AGE BETWEEN 50 AND 59 THEN 1
          WHEN AGE BETWEEN 60 AND 69 THEN 2
          WHEN AGE >= 70 THEN 3 END AS CHARLSON_AGE_BASE
    FROM (
        SELECT V.PATIENT_NUM
        , V.AGE
        , LAST_VISIT
        FROM LOYALTY_COHORT_AGEGRP V 
    ) VISITS
)
SELECT PATIENT_NUM, AGE, LAST_VISIT, CHARLSON_AGE_BASE
FROM CTE_VISIT_BASE
);

DROP TABLE LOYALTY_COHORT_CHARLSON;
CREATE TABLE LOYALTY_COHORT_CHARLSON AS SELECT * FROM (
SELECT PATIENT_NUM
  , LAST_VISIT
  , AGE
  , CAST(case when AGE < 65 then 'Under 65' 
     when age>=65           then 'Over 65' else '-' end AS VARCHAR(20)) AS AGEGRP
  , CHARLSON_INDEX
  , POWER( 0.983
      , POWER(2.71828, (CASE WHEN CHARLSON_INDEX > 7 THEN 7 ELSE CHARLSON_INDEX END) * 0.9)
      ) * 100.0 AS CHARLSON_10YR_SURVIVAL_PROB
  , MI, CHF, CVD, PVD, DEMENTIA, COPD, RHEUMDIS, PEPULCER, MILDLIVDIS, DIABETES_NOCC, 
  DIABETES_WTCC, HEMIPARAPLEG, RENALDIS, CANCER, MSVLIVDIS, METASTATIC, AIDSHIV
FROM (
SELECT PATIENT_NUM, LAST_VISIT, AGE
  , CHARLSON_AGE_BASE
      + MI + CHF + CVD + PVD + DEMENTIA + COPD + RHEUMDIS + PEPULCER 
      + (CASE WHEN MSVLIVDIS > 0 THEN 0 ELSE MILDLIVDIS END)
      + (CASE WHEN DIABETES_WTCC > 0 THEN 0 ELSE DIABETES_NOCC END)
      + DIABETES_WTCC + HEMIPARAPLEG + RENALDIS + CANCER + MSVLIVDIS + METASTATIC + AIDSHIV AS CHARLSON_INDEX
  , MI, CHF, CVD, PVD, DEMENTIA, COPD, RHEUMDIS, PEPULCER, MILDLIVDIS, DIABETES_NOCC, DIABETES_WTCC, HEMIPARAPLEG, RENALDIS, CANCER, MSVLIVDIS, METASTATIC, AIDSHIV
FROM (
SELECT PATIENT_NUM, AGE, LAST_VISIT, CHARLSON_AGE_BASE
  , MAX(CASE WHEN CHARLSON_CATGRY = 'MI'            THEN CHARLSON_WT ELSE 0 END) AS MI
  , MAX(CASE WHEN CHARLSON_CATGRY = 'CHF'           THEN CHARLSON_WT ELSE 0 END) AS CHF
  , MAX(CASE WHEN CHARLSON_CATGRY = 'CVD'           THEN CHARLSON_WT ELSE 0 END) AS CVD
  , MAX(CASE WHEN CHARLSON_CATGRY = 'PVD'           THEN CHARLSON_WT ELSE 0 END) AS PVD
  , MAX(CASE WHEN CHARLSON_CATGRY = 'DEMENTIA'      THEN CHARLSON_WT ELSE 0 END) AS DEMENTIA
  , MAX(CASE WHEN CHARLSON_CATGRY = 'COPD'          THEN CHARLSON_WT ELSE 0 END) AS COPD
  , MAX(CASE WHEN CHARLSON_CATGRY = 'RHEUMDIS'      THEN CHARLSON_WT ELSE 0 END) AS RHEUMDIS
  , MAX(CASE WHEN CHARLSON_CATGRY = 'PEPULCER'      THEN CHARLSON_WT ELSE 0 END) AS PEPULCER
  , MAX(CASE WHEN CHARLSON_CATGRY = 'MILDLIVDIS'    THEN CHARLSON_WT ELSE 0 END) AS MILDLIVDIS
  , MAX(CASE WHEN CHARLSON_CATGRY = 'DIABETES_NOCC' THEN CHARLSON_WT ELSE 0 END) AS DIABETES_NOCC
  , MAX(CASE WHEN CHARLSON_CATGRY = 'DIABETES_WTCC' THEN CHARLSON_WT ELSE 0 END) AS DIABETES_WTCC
  , MAX(CASE WHEN CHARLSON_CATGRY = 'HEMIPARAPLEG'  THEN CHARLSON_WT ELSE 0 END) AS HEMIPARAPLEG
  , MAX(CASE WHEN CHARLSON_CATGRY = 'RENALDIS'      THEN CHARLSON_WT ELSE 0 END) AS RENALDIS
  , MAX(CASE WHEN CHARLSON_CATGRY = 'CANCER'        THEN CHARLSON_WT ELSE 0 END) AS CANCER
  , MAX(CASE WHEN CHARLSON_CATGRY = 'MSVLIVDIS'     THEN CHARLSON_WT ELSE 0 END) AS MSVLIVDIS
  , MAX(CASE WHEN CHARLSON_CATGRY = 'METASTATIC'    THEN CHARLSON_WT ELSE 0 END) AS METASTATIC
  , MAX(CASE WHEN CHARLSON_CATGRY = 'AIDSHIV'       THEN CHARLSON_WT ELSE 0 END) AS AIDSHIV
FROM (
  /* FOR EACH VISIT - PULL PREVIOUS YEAR OF DIAGNOSIS FACTS JOINED TO CHARLSON CATEGORIES - EXTRACTING CHARLSON CATGRY/WT */
  SELECT O.PATIENT_NUM, O.AGE, O.LAST_VISIT, O.CHARLSON_AGE_BASE, C.CHARLSON_CATGRY, C.CHARLSON_WT
  FROM (SELECT DISTINCT F.PATIENT_NUM, CONCEPT_CD, V.AGE, V.LAST_VISIT, V.CHARLSON_AGE_BASE 
        FROM synthea_obs_fact F 
          JOIN LOYALTY_CHARLSON_VISIT_BASE V ON F.PATIENT_NUM = V.PATIENT_NUM
            --AND F.START_DATE BETWEEN DATEADD(YY,-1,V.LAST_VISIT) AND V.LAST_VISIT
            AND F.START_DATE BETWEEN  ADD_MONTHS( TRUNC(V.LAST_VISIT), -12) AND  V.LAST_VISIT
       )O
    JOIN LOYALTY_CHARLSON_DX C
      ON O.CONCEPT_CD = C.CONCEPT_CD
  GROUP BY O.PATIENT_NUM, O.AGE, O.LAST_VISIT, O.CHARLSON_AGE_BASE, C.CHARLSON_CATGRY, C.CHARLSON_WT
  UNION /* IF NO CHARLSON DX FOUND IN ABOVE INNER JOINS WE CAN UNION TO JUST THE ENCOUNTER+AGE_BASE RECORD WITH CHARLSON FIELDS NULLED OUT
           THIS IS MORE PERFORMANT (SHORTCUT) THAN A LEFT JOIN IN THE OBSERVATION-CHARLSON JOIN ABOVE */
  SELECT V2.PATIENT_NUM, V2.AGE, V2.LAST_VISIT, V2.CHARLSON_AGE_BASE, NULL, NULL
  FROM LOYALTY_CHARLSON_VISIT_BASE V2
  )DXU
  GROUP BY PATIENT_NUM, AGE, LAST_VISIT, CHARLSON_AGE_BASE
)cci
)ccisum
);

/* CHARLSON 10YR PROB MEDIAN/MEAN/MODE/STDEV */
--SET @STEPTTS = GETDATE();
--SELECT * FROM LOYALTY_COHORT_CHARLSON;
/* UNFILTERED BY PSC */
DROP TABLE LOYALTY_CHARLSON_STATS;
CREATE TABLE LOYALTY_CHARLSON_STATS AS 
SELECT * FROM (
WITH CTE_MODE AS (
SELECT NVL(A.AGEGRP,'All Patients') AGEGRP
  , CHARLSON_10YR_SURVIVAL_PROB
  , RANK() OVER (PARTITION BY NVL(A.AGEGRP,'All Patients') ORDER BY N DESC) MR_AG
FROM (
SELECT AGEGRP, CHARLSON_10YR_SURVIVAL_PROB, COUNT(*) N
FROM LOYALTY_COHORT_CHARLSON
GROUP BY GROUPING SETS ((AGEGRP, CHARLSON_10YR_SURVIVAL_PROB),(CHARLSON_10YR_SURVIVAL_PROB))
)A
GROUP BY NVL(A.AGEGRP,'All Patients'), CHARLSON_10YR_SURVIVAL_PROB, N
)
, CTE_MEAN_STDEV_MODE AS (
SELECT NVL(GS.AGEGRP,'All Patients') AGEGRP, MEAN_10YRPROB, STDEV_10YRPROB
  , (SELECT CHARLSON_10YR_SURVIVAL_PROB FROM CTE_MODE WHERE AGEGRP = NVL(GS.AGEGRP,'All Patients') AND (MR_AG = 1)) AS MODE_10YRPROB
FROM (
SELECT AGEGRP, AVG(CHARLSON_10YR_SURVIVAL_PROB) MEAN_10YRPROB, STDDEV(CHARLSON_10YR_SURVIVAL_PROB) STDEV_10YRPROB
FROM LOYALTY_COHORT_CHARLSON
GROUP BY GROUPING SETS ((AGEGRP),())
)GS
)
SELECT MS.AGEGRP
  , CAST('N' AS CHAR(1)) CUTOFF_FILTER_YN
  , CAST(MEDIAN_10YR_SURVIVAL AS NUMBER(3,1))  MEDIAN_10YR_SURVIVAL
  , CAST(S.MEAN_10YRPROB AS NUMBER(3,1)) MEAN_10YRPROB 
  , CAST(S.STDEV_10YRPROB AS NUMBER(3,1))STDEV_10YRPROB
  , CAST(S.MODE_10YRPROB AS NUMBER(3,1)) MODE_10YRPROB
FROM (
SELECT AGEGRP, CHARLSON_10YR_SURVIVAL_PROB
  , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CHARLSON_10YR_SURVIVAL_PROB) OVER (PARTITION BY AGEGRP) AS MEDIAN_10YR_SURVIVAL
FROM LOYALTY_COHORT_CHARLSON
WHERE AGEGRP <> '-'
UNION ALL
SELECT 'All Patients' as AGEGRP, CHARLSON_10YR_SURVIVAL_PROB
  , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CHARLSON_10YR_SURVIVAL_PROB) OVER (PARTITION BY 1) AS MEDIAN_10YR_SURVIVAL
FROM LOYALTY_COHORT_CHARLSON
WHERE AGEGRP <> '-'
)MS, CTE_MEAN_STDEV_MODE S
WHERE MS.AGEGRP = S.AGEGRP
GROUP BY MS.AGEGRP, MEDIAN_10YR_SURVIVAL, S.MODE_10YRPROB, S.STDEV_10YRPROB, S.MEAN_10YRPROB);
SELECT * FROM LOYALTY_CHARLSON_STATS;
/* FILTERED BY PSC */
INSERT INTO LOYALTY_CHARLSON_STATS
SELECT AGEGRP,CUTOFF_FILTER_YN,MEDIAN_10YR_SURVIVAL,MEAN_10YRPROB,
STDEV_10YRPROB,MODE_10YRPROB FROM (
WITH CTE_MODE AS (
SELECT --NVL(A.AGEGRP,'All Patients') AGEGRP
    AGEGRP
  , CHARLSON_10YR_SURVIVAL_PROB
  , RANK() OVER (PARTITION BY NVL(A.AGEGRP,'All Patients') ORDER BY N DESC) MR_AG
FROM (
SELECT C.AGEGRP, CHARLSON_10YR_SURVIVAL_PROB, COUNT(*) N
FROM LOYALTY_COHORT_CHARLSON CC
  JOIN LOYALTY_cohort_agegrp C
    ON CC.PATIENT_NUM = C.patient_num
  JOIN LOYALTY_AGEGRP_PSC PSC
    ON C.AGEGRP = PSC.AGEGRP
    AND C.Predicted_score >= PSC.PredictiveScoreCutoff
GROUP BY C.AGEGRP,CHARLSON_10YR_SURVIVAL_PROB
)A
GROUP BY AGEGRP, CHARLSON_10YR_SURVIVAL_PROB, N
)
, CTE_MEAN_STDEV_MODE AS (
SELECT AGEGRP, MEAN_10YRPROB, STDEV_10YRPROB
  , (SELECT CHARLSON_10YR_SURVIVAL_PROB FROM CTE_MODE WHERE AGEGRP = NVL(GS.AGEGRP,'All Patients') AND (MR_AG = 1)) AS MODE_10YRPROB
FROM (
SELECT C.AGEGRP, AVG(CHARLSON_10YR_SURVIVAL_PROB) MEAN_10YRPROB, STDDEV(CHARLSON_10YR_SURVIVAL_PROB) STDEV_10YRPROB
FROM LOYALTY_COHORT_CHARLSON CC
  JOIN LOYALTY_cohort_agegrp C
    ON CC.PATIENT_NUM = C.patient_num
  JOIN LOYALTY_AGEGRP_PSC PSC
    ON C.AGEGRP = PSC.AGEGRP
    AND C.Predicted_score >= PSC.PredictiveScoreCutoff
GROUP BY C.AGEGRP
)GS
)
SELECT MS.AGEGRP
  , CAST('Y' AS CHAR(1)) AS CUTOFF_FILTER_YN
  , MEDIAN_10YR_SURVIVAL
  , S.MEAN_10YRPROB
  , S.STDEV_10YRPROB
  , S.MODE_10YRPROB
FROM (
SELECT C.AGEGRP, CHARLSON_10YR_SURVIVAL_PROB
  , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CHARLSON_10YR_SURVIVAL_PROB) OVER (PARTITION BY C.AGEGRP) AS MEDIAN_10YR_SURVIVAL
FROM LOYALTY_COHORT_CHARLSON CC
  JOIN LOYALTY_cohort_agegrp C
    ON CC.PATIENT_NUM = C.patient_num
  JOIN LOYALTY_AGEGRP_PSC PSC
    ON C.AGEGRP = PSC.AGEGRP
    AND C.Predicted_score >= PSC.PredictiveScoreCutoff
WHERE CC.AGEGRP <> '-'
)MS, CTE_MEAN_STDEV_MODE S
WHERE MS.AGEGRP = S.AGEGRP
GROUP BY MS.AGEGRP, MEDIAN_10YR_SURVIVAL, S.MODE_10YRPROB, S.STDEV_10YRPROB, S.MEAN_10YRPROB
);
COMMIT;
SELECT * FROM LOYALTY_CHARLSON_STATS;

--TODO: make this conditional
-- create summary table
--drop table loyalty_dev_summary;
--select * from loyalty_dev_summary;

    
-- Add to summary table for output
--INSERT INTO loyalty_dev_summary 
select 
    COHORT_NAME,
    site,
    lookback_yr,
    gender_denominators_yn,
    cutoff_filter_yn,
    summary_description,
    tablename,
    num_dx1,
    num_dx2,
    meduse1,
    meduse2,
    mammography,
    paptest,
    psatest,
    colonoscopy,
    fecalocculttest,
    flushot,
    pneumococcalvaccine,
    bmi,
    a1c,
    medicalexam,
    inp1_opt1_visit,
    opt2_visit,
    ed_visit,
    mdvisit_pname2,
    mdvisit_pname3,
    routine_care_2,
    subjects_nocriteria,
    predictivescorecutoff,
    mean_10yrprob,
    median_10yr_survival,
    mode_10yrprob,
    stdev_10yrprob,
    totalsubjects,
    totalsubjectsfemale,
    totalsubjectsmale,
    percentfemale,
    percentmale from (
with cohortagg as (
--FILTERED BY PREDICTIVE CUTOFF 
SELECT
COHORT_NAME,
'Y' AS CUTOFF_FILTER_YN,
'Patient Counts' as Summary_Description,
CAG.AGEGRP, 
count(distinct patient_num) as TotalSubjects,
sum(Num_DX1) as Num_DX1,
sum(Num_DX2) as Num_DX2,
sum(MedUse1)  as MedUse1,
sum(MedUse2)  as MedUse2,
sum(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN  Mammography  
           WHEN X.GENDERED=0 THEN Mammography ELSE NULL END ) AS Mammography,
sum(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN PapTest 
           WHEN X.GENDERED=0 THEN PapTest ELSE NULL END ) AS PapTest,
sum(CASE WHEN X.GENDERED=1 and sex_cd='M' THEN PSATEST 
           WHEN X.GENDERED=0 THEN PSATEST ELSE NULL END) AS PSATEST,
sum(Colonoscopy)  as Colonoscopy,
sum(FecalOccultTest)  as FecalOccultTest,
sum(FluShot)  as FluShot,
sum(PneumococcalVaccine)  as PneumococcalVaccine,
sum(BMI)  as BMI,
sum(A1C)  as A1C,
sum(MedicalExam)  as MedicalExam,
sum(INP1_OPT1_Visit)  as INP1_OPT1_Visit,
sum(OPT2_Visit)  as OPT2_Visit,
sum(ED_Visit)  as ED_Visit,
sum(MDVisit_pname2)  as MDVisit_pname2,
sum(MDVisit_pname3)  as MDVisit_pname3,
sum(Routine_Care_2)  as Routine_Care_2,
sum(Subjects_NoCriteria) as Subjects_NoCriteria, 
sum(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN 1 END) AS TotalSubjectsFemale,
sum(CASE WHEN X.GENDERED=1 and sex_cd='M' THEN 1 END) AS TotalSubjectsMale
from loyalty_cohort_agegrp CAG 
CROSS JOIN CONSTANTS X
JOIN loyalty_AGEGRP_PSC P ON CAG.AGEGRP = P.AGEGRP AND CAG.Predicted_score >= P.PredictiveScoreCutoff
group by COHORT_NAME, CAG.AGEGRP
UNION ALL
SELECT
COHORT_NAME,
'Y' AS CUTOFF_FILTER_YN,
'PercentOfSubjects' as Summary_Description,
CAG.AGEGRP, 
count(distinct patient_num) as TotalSubjects,
100*avg(Num_Dx1) as Num_DX1,
100*avg(Num_Dx2) as Num_DX2,
100*avg(MedUse1)  as MedUse1,
100*avg(MedUse2) as MedUse2,
100*avg(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN  Mammography  
           WHEN X.GENDERED=0 THEN Mammography ELSE NULL END ) AS Mammography,
100*avg(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN PapTest 
           WHEN X.GENDERED=0 THEN PapTest ELSE NULL END ) AS PapTest,
100*avg(CASE WHEN X.GENDERED=1 and sex_cd='M' THEN PSATEST 
           WHEN X.GENDERED=0 THEN PSATEST ELSE NULL END) AS PSATEST,
100*avg(Colonoscopy) as Colonoscopy,
100*avg(FecalOccultTest) as FecalOccultTest,
100*avg(FluShot) as  FluShot,
100*avg(PneumococcalVaccine) as PneumococcalVaccine,
100*avg(BMI)  as BMI,
100*avg(A1C) as A1C,
100*avg(MedicalExam) as MedicalExam,
100*avg(INP1_OPT1_Visit) as INP1_OPT1_Visit,
100*avg(OPT2_Visit) as OPT2_Visit,
100*avg(ED_Visit)  as ED_Visit,
100*avg(MDVisit_pname2) as MDVisit_pname2,
100*avg(MDVisit_pname3) as MDVisit_pname3,
100*avg(Routine_Care_2) as Routine_care_2,
100*avg(Subjects_NoCriteria) as Subjects_NoCriteria,  
count(CASE WHEN sex_cd='F' THEN  patient_num ELSE NULL END) AS TotalSubjectsFemale,
count(CASE WHEN sex_cd='M' THEN  patient_num ELSE NULL END) AS TotalSubjectsMale
from loyalty_cohort_agegrp CAG 
CROSS JOIN CONSTANTS X
JOIN loyalty_AGEGRP_PSC P ON CAG.AGEGRP = P.AGEGRP AND CAG.Predicted_score >= P.PredictiveScoreCutoff
group by COHORT_NAME, CAG.AGEGRP
UNION ALL
--UNFILTERED -- ALL QUINTILES 
SELECT
COHORT_NAME,
'N' AS CUTOFF_FILTER_YN,
'Patient Counts' as Summary_Description,
CAG.AGEGRP, 
count(distinct patient_num) as TotalSubjects,
sum(Num_Dx1) as Num_DX1,
sum(Num_Dx2) as Num_DX2,
sum(MedUse1)  as MedUse1,
sum(MedUse2) as MedUse2,
SUM(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN Mammography 
           WHEN X.GENDERED=0 THEN Mammography  ELSE NULL END) AS Mammography,
SUM(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN  PapTest 
           WHEN X.GENDERED=0 THEN PapTest ELSE NULL END) AS PapTest,
SUM(CASE WHEN X.GENDERED=1 and sex_cd='M' THEN PSATEST 
           WHEN X.GENDERED=0 THEN PSATEST  ELSE NULL END) AS PSATEST,
sum(Colonoscopy) as Colonoscopy,
sum(FecalOccultTest) as FecalOccultTest,
sum(FluShot) as  FluShot,
sum(PneumococcalVaccine) as PneumococcalVaccine,
sum(BMI)  as BMI,
sum(A1C) as A1C,
sum(MedicalExam) as MedicalExam,
sum(INP1_OPT1_Visit) as INP1_OPT1_Visit,
sum(OPT2_Visit) as OPT2_Visit,
sum(ED_Visit)  as ED_Visit,
sum(MDVisit_pname2) as MDVisit_pname2,
sum(MDVisit_pname3) as MDVisit_pname3,
sum(Routine_Care_2) as Routine_care_2,
SUM(Subjects_NoCriteria) as Subjects_NoCriteria, --inverted bitwise OR of all bit flags 
count(CASE WHEN sex_cd='F' THEN  patient_num ELSE NULL END) AS TotalSubjectsFemale,
count(CASE WHEN sex_cd='M' THEN  patient_num ELSE NULL END) AS TotalSubjectsMale
from loyalty_cohort_agegrp CAG
CROSS JOIN CONSTANTS X
group by COHORT_NAME, CAG.AGEGRP
UNION ALL
SELECT
COHORT_NAME,
'N' AS PREDICTIVE_CUTOFF_FILTER_YN,
'PercentOfSubjects' as Summary_Description,
CAG.AGEGRP, 
count(distinct patient_num) as TotalSubjects,
100*avg(Num_Dx1) as Num_DX1,
100*avg(Num_Dx2) as Num_DX2,
100*avg(MedUse1)  as MedUse1,
100*avg(MedUse2) as MedUse2,
100*AVG(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN Mammography 
           WHEN X.GENDERED=0 THEN Mammography  ELSE NULL END) AS Mammography,
100*AVG(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN  PapTest 
           WHEN X.GENDERED=0 THEN PapTest ELSE NULL END) AS PapTest,
100*AVG(CASE WHEN X.GENDERED=1 and sex_cd='M' THEN PSATEST 
           WHEN X.GENDERED=0 THEN PSATEST  ELSE NULL END) AS PSATEST,
100*avg(Colonoscopy) as Colonoscopy,
100*avg(FecalOccultTest) as FecalOccultTest,
100*avg(FluShot) as  FluShot,
100*avg(PneumococcalVaccine) as PneumococcalVaccine,
100*avg(BMI)  as BMI,
100*avg(A1C) as A1C,
100*avg(MedicalExam) as MedicalExam,
100*avg(INP1_OPT1_Visit) as INP1_OPT1_Visit,
100*avg(OPT2_Visit) as OPT2_Visit,
100*avg(ED_Visit)  as ED_Visit,
100*avg(MDVisit_pname2) as MDVisit_pname2,
100*avg(MDVisit_pname3) as MDVisit_pname3,
100*avg(Routine_Care_2) as Routine_care_2,
SUM(Subjects_NoCriteria) as Subjects_NoCriteria,  
sum(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN 1 END) AS TotalSubjectsFemale,
sum(CASE WHEN X.GENDERED=1 and sex_cd='M' THEN 1 END) AS TotalSubjectsMale
from loyalty_cohort_agegrp CAG
CROSS JOIN CONSTANTS X
group by COHORT_NAME, CAG.AGEGRP  -- 4 unioned
),
--select TotalSubjectsFemale from cohortagg;
loyalty_table as (
SELECT 
COHORT_NAME,
    x.site site, 
    x.lookbackyears lookback_yr, 
    x.gendered GENDER_DENOMINATORS_YN, 
    COHORTAGG.CUTOFF_FILTER_YN, 
    Summary_Description, 
    CS.AGEGRP as tablename, Num_DX1, Num_DX2, MedUse1, MedUse2
  , Mammography, PapTest, PSATest, Colonoscopy, FecalOccultTest, FluShot, PneumococcalVaccine, 
    BMI, A1C, MedicalExam, INP1_OPT1_Visit, OPT2_Visit, ED_Visit
  , MDVisit_pname2, MDVisit_pname3, Routine_care_2, Subjects_NoCriteria
  , CASE WHEN COHORTAGG.CUTOFF_FILTER_YN = 'Y' THEN CP.PredictiveScoreCutoff ELSE NULL END AS PredictiveScoreCutoff
  , CS.MEAN_10YRPROB
  , CS.MEDIAN_10YR_SURVIVAL
  , CS.MODE_10YRPROB
  , CS.STDEV_10YRPROB
  , COHORTAGG.TotalSubjects
  , COHORTAGG.TotalSubjectsFemale
  , COHORTAGG.TotalSubjectsMale
FROM COHORTAGG 
  cross join constants x
  JOIN loyalty_AGEGRP_PSC CP    ON COHORTAGG.AGEGRP = CP.AGEGRP
  JOIN loyalty_CHARLSON_STATS CS ON COHORTAGG.AGEGRP = CS.AGEGRP AND COHORTAGG.CUTOFF_FILTER_YN = CS.CUTOFF_FILTER_YN),
  --select * from loyalty_table;

FINAL_LOYALTY_TABLE as
(
SELECT
COHORT_NAME,
    site,
    lookback_yr,
    gender_denominators_yn,
    cutoff_filter_yn,
    summary_description,
    tablename,
    trunc(num_dx1,2) num_dx1,
    trunc(num_dx2,2) num_dx2,
    trunc(meduse1,2) meduse1,
    trunc(meduse2,2) meduse2,
    trunc(mammography,2) mammography,
    trunc(paptest,2) paptest,
    trunc(psatest,2) psatest,
    trunc(colonoscopy,2) colonoscopy,
    trunc(fecalocculttest,2) fecalocculttest,
    trunc(flushot,2) flushot,
    trunc(pneumococcalvaccine,2) pneumococcalvaccine,
    trunc(bmi,2) bmi,
    trunc(a1c,2) a1c,
    trunc(medicalexam,2) medicalexam,
    trunc(inp1_opt1_visit,2) inp1_opt1_visit,
    trunc(opt2_visit,2) opt2_visit,
    trunc(ed_visit,2) ed_visit,
    trunc(mdvisit_pname2,2) mdvisit_pname2,
    trunc(mdvisit_pname3,2) mdvisit_pname3,
    trunc(routine_care_2,2) routine_care_2,
    trunc(subjects_nocriteria,2) subjects_nocriteria,
    trunc(predictivescorecutoff,3) predictivescorecutoff,
    mean_10yrprob mean_10yrprob,
    median_10yr_survival median_10yr_survival,
    mode_10yrprob mode_10yrprob,
    stdev_10yrprob stdev_10yrprob,
    totalsubjects,
    totalsubjectsfemale,
    totalsubjectsmale,
    trunc(100*TotalSubjectsFemale/TotalSubjects,1) || '%' AS PercentFemale,
    trunc(100*TotalSubjectsMale/TotalSubjects,1)  || '%' AS PercentMale
FROM
    LOYALTY_TABLE
)
SELECT    
COHORT_NAME,
    site,
    lookback_yr,
    gender_denominators_yn,
    cutoff_filter_yn,
    summary_description,
    tablename,
    num_dx1,
    num_dx2,
    meduse1,
    meduse2,
    mammography,
    paptest,
    psatest,
    colonoscopy,
    fecalocculttest,
    flushot,
    pneumococcalvaccine,
    bmi,
    a1c,
    medicalexam,
    inp1_opt1_visit,
    opt2_visit,
    ed_visit,
    mdvisit_pname2,
    mdvisit_pname3,
    routine_care_2,
    subjects_nocriteria,
    predictivescorecutoff,
    mean_10yrprob,
    median_10yr_survival,
    mode_10yrprob,
    stdev_10yrprob,
    totalsubjects,
    totalsubjectsfemale,
    totalsubjectsmale,
    percentfemale,
    percentmale 
FROM FINAL_LOYALTY_TABLE
order by LOOKBACK_YR, summary_description, CUTOFF_FILTER_YN, TABLENAME
);
COMMIT;
--select * from loyalty_cohort_agegrp where cohort_name = 'LOYALTY_TEST_DATA';
--select count(*) from loyalty_cohort_agegrp where cohort_name is null; --705209

--select * from loyalty_dev_summary;
--describe loyalty_dev_summary;


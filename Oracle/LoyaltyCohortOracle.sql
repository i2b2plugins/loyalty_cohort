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
    TotalSubjects number NULL,
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
    TotalSubjectsFemale number NULL,
    TotalSubjectsMale number NULL,
    PERCENTPOPULATION NUMBER NULL,
    percentsubjectsfemale char(10),
    percentsubjectsmale  char(10),
    AVERAGEFACTCOUNT number NULL
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

declare
v_sql LONG;
begin

v_sql:='create table LOYALTY_DEV_SUMMARY_PRELIM
  (
    COHORT_NAME varchar2(30) NULL,
    SITE VARCHAR(10) NOT NULL,
    LOOKBACK_YR number(10) NOT NULL,
    GENDER_DENOMINATORS_YN char(1) NOT NULL,
    CUTOFF_FILTER_YN char(1) NOT NULL,
    Summary_Description varchar(20) NOT NULL,
	tablename varchar(20) NULL,
    TotalSubjects number NULL,
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
    MEAN_10YRPROB number NULL,
    MEDIAN_10YR_SURVIVAL number NULL,
	MODE_10YRPROB number NULL,
	STDEV_10YRPROB number NULL,
    TotalSubjectsFemale number NULL,
    TotalSubjectsMale number NULL,
    percentsubjectsfemale char(10),
    percentsubjectsmale  char(10))';

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

DROP TABLE LOYALTY_CONSTANTS;
CREATE TABLE 
LOYALTY_CONSTANTS (
INDEXDATE DATE,
LOOKBACKYEARS NUMBER(2),
SHOWOUTPUT NUMBER(1),
DEMFACTDATE DATE,
SITE VARCHAR2(100),
GENDERED NUMBER(1)
);

INSERT INTO LOYALTY_CONSTANTS 
SELECT 
TO_DATE('&1') AS INDEXDATE, --TO_DATE('31-MAR-2022') AS INDEXDATE,
TO_NUMBER('&2') AS lookbackYears,
TO_NUMBER('&3') AS  showOutput,
TO_DATE('&4') AS demFactDate,
'&5' AS Site,
TO_NUMBER('&6') AS GENDERED
FROM DUAL;

COMMIT;
select * from LOYALTY_CONSTANTS; --31-MAR-22	1	2	31-MAR-12	UPITT	1

-- CREATE COHORT TABLE THAT REMOVES PEOPLE UNDER 18, 'EFFEMORAL' PATIENTS 
CREATE TABLE LOYALTY_MULTVISIT_PATIENTS AS SELECT * FROM (
WITH CTE_MULTVISIT AS (
SELECT v.PATIENT_NUM, ENCOUNTER_NUM, TRUNC(START_DATE) START_DATE, TRUNC(END_DATE) END_DATE 
/* CONVERTING TO DATE TO AGGRESSIVELY DROP OUT ADMIN-LIKE ENCOUNTERS ON SAME DAY AND TREAT THEM AS OVERLAPPING */ 
FROM VISIT_DIMENSION v
inner join LOYALTY_COHORT c on c.patient_num=v.patient_num
WHERE v.PATIENT_NUM NOT IN (SELECT v.PATIENT_NUM 
FROM VISIT_DIMENSION v inner join LOYALTY_COHORT c on c.patient_num=v.patient_num 
GROUP BY v.PATIENT_NUM HAVING COUNT(DISTINCT ENCOUNTER_NUM) = 1) /* EXCLUDES EPHEMERAL ONE-VISIT PATIENTS */
)
SELECT DISTINCT A.PATIENT_NUM
FROM CTE_MULTVISIT A
  LEFT JOIN CTE_MULTVISIT B
    ON A.PATIENT_NUM = B.PATIENT_NUM
    AND A.ENCOUNTER_NUM != B.ENCOUNTER_NUM
    AND (trunc(A.START_DATE) <= trunc(B.END_DATE) AND trunc(A.END_DATE) >= trunc(B.START_DATE)) /* VISIT DATES OVERLAP IN SOME WAY */
WHERE B.ENCOUNTER_NUM IS NULL
);

--SELECT * FROM LOYALTY_COHORT WHERE PATIENT_NUM NOT IN ( SELECT PATIENT_NUM FROM LOYALTY_MULTVISIT_PATIENTS);

--SELECT * FROM VISIT_DIMENSION WHERE PATIENT_NUM = 683302;
/* NO OVERLAPS - GOAL HERE IS TO ONLY INCLUDE PATIENTS THAT HAVE MULTIPLE ENCOUNTERS */
/* DON'T NEED TO COUNT ENCOUNTERS HERE.
    IF THE PATIENT STILL HAS AT LEAST ONE ENCOUNTER AFTER DROPPING OUT THEIR ENCOUNTER THAT DID OVERLAP,
    THEN WE CAN INFER THEY HAVE MULTIPLE ENCOUNTERS IN THE HEALTH CARE SYSTEM. THE FIRST PREDICATE IN CTE_MULTVISIT
    REQUIRED THE PATIENT NOT BE IN THE "EPHEMERAL" PATIENT GROUP (PATIENTS WITH ONE ENCOUNTER_NUM IN ALL TIME).
    SO BY THIS STEP, IF ENCOUNTERS THAT DO OVERLAP ARE DROPPED, THERE IS STILL AT LEAST ONE STANDALONE ENCOUNTER IN ADDITION
    TO THOSE OVERLAPPED ENCOUNTERS - THUS AT MINIMUM >=3 ENCOUNTERS IN THE EHR. 
*/

--FIND PATIENTS THAT HAVE MORE THAN DEMOGRAPHIC FACTS
--DROP TABLE LOYALTY_MORE_THAN_DEMO_FACT_PTS;
CREATE TABLE LOYALTY_MORE_THAN_DEMO_FACT_PTS AS SELECT * FROM (
WITH DEM_FEATURES AS ( 
select distinct Feature_name, concept_cd, code_type --[ACT_PATH], 
from xref_LoyaltyCode_paths L, CONCEPT_DIMENSION c
where C.CONCEPT_PATH like L.Act_path||'%'  
--AND FEATURE_NAME = 'PapTest'
AND code_type = 'DEM' 
and (act_path <> '**Not Found' and act_path is not null)
ORDER BY FEATURE_NAME)
SELECT DISTINCT PATIENT_NUM
FROM OBSERVATION_FACT O
WHERE CONCEPT_CD NOT IN ( SELECT CONCEPT_CD FROM DEM_FEATURES)
);


SELECT COUNT(*) FROM LOYALTY_MORE_THAN_DEMO_FACT_PTS;  --955734
SELECT COUNT(*) FROM LOYALTY_MULTVISIT_PATIENTS;  --951095
/*
DELETE FROM LOYALTY_COHORT WHERE PATIENT_NUM NOT IN (
SELECT PATIENT_NUM FROM LOYALTY_MORE_THAN_DEMO_FACT_PTS
INTERSECT 
SELECT PATIENT_NUM FROM LOYALTY_MULTVISIT_PATIENTS
); --951095
*/
CREATE TABLE LOYALTY_COHORT_FINAL AS SELECT * FROM (
WITH FILTERED_PATIENTS AS (
SELECT PATIENT_NUM FROM LOYALTY_MORE_THAN_DEMO_FACT_PTS
INTERSECT 
SELECT PATIENT_NUM FROM LOYALTY_MULTVISIT_PATIENTS
)
SELECT F.PATIENT_NUM, COHORT_NAME, INDEXDATE
FROM FILTERED_PATIENTS F
INNER JOIN LOYALTY_COHORT L ON L.PATIENT_NUM = F.PATIENT_NUM
INNER JOIN PATIENT_DIMENSION P ON P.PATIENT_NUM = F.PATIENT_NUM --951095
WHERE P.AGE_IN_YEARS_NUM > 18
--AND P.VITAL_STATUS_CD IS NULL
);

select count(*) from LOYALTY_COHORT_FINAL; --820004
--select * from LOYALTY_COHORT_AGEGRP where num_dx1 = 1 and num_dx2 = 1;
--select * from LOYALTY_COHORT_AGEGRP where meduse1 = 1 and meduse2 = 1;
--select * from LOYALTY_COHORT_AGEGRP where mdvisit_pname2 = 1 and mdvisit_pname3 = 1;
-- THIS IS THE DIFFERENCE BETWEEN ORACLE AND MSSQL
CREATE TABLE LOYALTY_COHORT_IN_PERIOD AS
WITH COHORT_DEM AS
(
SELECT 
    C.COHORT_NAME, 
    P.PATIENT_NUM, 
    C.INDEXDATE, 
    DECODE(P.SEX_CD,'DEM|SEX:F', 'F', 'DEM|SEX:M', 'M', NULL) SEX,
    TRUNC((C.INDEXDATE - P.BIRTH_DATE)/365) AGE -- AGE AT INDEX DATE
FROM LOYALTY_COHORT_FINAL c
JOIN PATIENT_DIMENSION P ON P.PATIENT_NUM = C.PATIENT_NUM
)
SELECT 
    C.COHORT_NAME, 
    V.PATIENT_NUM, 
    C.INDEXDATE, 
    C.SEX,
    C.AGE,
    MAX(V.START_DATE) LAST_VISIT
FROM COHORT_DEM C
CROSS JOIN LOYALTY_CONSTANTS X
JOIN OBSERVATION_FACT V ON V.PATIENT_NUM = C.PATIENT_NUM --OR VISIT_DIMENSION
--WHERE V.START_DATE between '01-JAN-2012' and C.INDEXDATE --SQL SERVER SCRIPT
--WHERE V.START_DATE between add_months( trunc(C.INDEXDATE), -12*X.LOOKBACKYEARS) and C.INDEXDATE
GROUP BY C.COHORT_NAME, V.PATIENT_NUM, C.INDEXDATE,C.AGE, C.SEX ;

SELECT COUNT(*) FROM LOYALTY_COHORT_IN_PERIOD; 

--LOYALTY_DEV
--207 sec
CREATE TABLE LOYALTY_COHORT_BY_AGEGRP AS 
SELECT * FROM (
--The cohort is any patient that has had a visit during the time period
--Get patient's last visit during time period
WITH VISIT_ONTOLOGY AS 
( 
SELECT * FROM ACT_VISIT_DETAILS_V4 c -- THIS NEEDS TO POINT TO METADATA SCHEMA
),
--select * from visit_ontology;
--LOYALTY_COHORT_IN_PERIOD AS
--(
-- in covid_crcdata
--SELECT V.PATIENT_NUM, C.INDEXDATE, MAX(V.START_DATE) LAST_VISIT, COHORT_NAME
--FROM LOYALTY_COHORT_FINAL c
--JOIN OBSERVATION_FACT V ON V.PATIENT_NUM = C.PATIENT_NUM --OR VISIT_DIMENSION
--CROSS JOIN LOYALTY_CONSTANTS x
--WHERE V.START_DATE between add_months( trunc(C.INDEXDATE), -12*X.LOOKBACKYEARS) and C.INDEXDATE
--GROUP BY C.COHORT_NAME, V.PATIENT_NUM, C.INDEXDATE
--),
--select COUNT(*) from LOYALTY_COHORT_IN_PERIOD; 
--146825  FROM 800K ONLY 146825 HAVE A VISIT IN THE LOOKBACK PERIOD MAYBE VISIT DATA AND FACT DATA OUT OF SYNC - NOPE
--select * from LOYALTY_CONSTANTS;
--select count(*) from LOYALTY_COHORT; --433334
--436482
--select count(*) from LOYALTY_COHORT_IN_PERIOD;
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
AND UPPER(feature_name) in ('MDVISIT_PNAME2', 'MDVISIT_PNAME3')
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
--SELECT COUNT(*) FROM OBSERVATION_FACT ; --WHERE CONCEPT_CD LIKE 'DEM%'; -- NO DEMOGRAPHICS ONLY 612 FACTS IN _ADD_ON 71511691 
PT_DEM_FEATURE_COUNT_BY_DATE AS ( 
SELECT LC.PATIENT_NUM, FEATURE_NAME,  COUNT(DISTINCT TRUNC(O.START_DATE)) DISTINCT_ENCOUNTERS, COEFF
FROM LOYALTY_COHORT_IN_PERIOD LC
JOIN OBSERVATION_FACT O ON O.PATIENT_NUM = LC.PATIENT_NUM
JOIN FEATURES F ON F.CONCEPT_CD = O.CONCEPT_CD
JOIN xref_LoyaltyCode_PSCoeff C ON C.FIELD_NAME = F.FEATURE_NAME
WHERE FEATURE_NAME = 'Demographics' 
GROUP BY LC.PATIENT_NUM, FEATURE_NAME, C.COEFF
ORDER BY LC.PATIENT_NUM, FEATURE_NAME
),
--select COUNT(*) from PT_DEM_FEATURE_COUNT_BY_DATE; --999976 FROM ALL PATIENTS NOT JUST THE COHORT NEED TO JOIN TO LOYALTY_COHORT_FINAL

--Get visit counts and the coefficients
PT_VIS_FEATURE_COUNT_BY_DATE AS ( -- VISIT WITHIN TIME FRAME OF INTEREST
SELECT LC.PATIENT_NUM, FEATURE_NAME,  COUNT(DISTINCT TRUNC(V.START_DATE)) DISTINCT_ENCOUNTERS, C.COEFF
FROM LOYALTY_COHORT_IN_PERIOD LC
JOIN VISIT_DIMENSION V ON V.PATIENT_NUM = LC.PATIENT_NUM
JOIN VISIT_FEATURES F ON F.CONCEPT_CD = V.INOUT_CD
JOIN xref_LoyaltyCode_PSCoeff C ON C.FIELD_NAME = F.FEATURE_NAME
CROSS JOIN LOYALTY_CONSTANTS x
WHERE CODE_TYPE = 'VISIT' AND 
V.START_DATE between add_months( trunc(LC.INDEXDATE), -12*X.LOOKBACKYEARS) and LC.INDEXDATE 
GROUP BY LC.PATIENT_NUM, FEATURE_NAME, C.COEFF
ORDER BY LC.PATIENT_NUM, FEATURE_NAME
),
--select COUNT(DISTINCT PATIENT_NUM) from PT_VIS_FEATURE_COUNT_BY_DATE; --146825 FROM COHORT IN PERIOD HAVE A VIS FEATURE
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
--select COUNT(DISTINCT PATIENT_NUM) from ADJ_PT_VIS_FEATURE_COUNT_BY_DATE;

--Get the observation_fact feature counts and the coefficients
PT_FEATURE_COUNT_BY_DATE AS (
SELECT LC.PATIENT_NUM, FEATURE_NAME,  COUNT(DISTINCT TRUNC(O.START_DATE)) DISTINCT_ENCOUNTERS, COEFF
FROM LOYALTY_COHORT_IN_PERIOD LC
CROSS JOIN LOYALTY_CONSTANTS x
JOIN OBSERVATION_FACT O ON O.PATIENT_NUM = LC.PATIENT_NUM
JOIN FEATURES F ON F.CONCEPT_CD = O.CONCEPT_CD
JOIN xref_LoyaltyCode_PSCoeff C ON C.FIELD_NAME = F.FEATURE_NAME
WHERE TRUNC(O.START_DATE) between add_months( LC.INDEXDATE, -12*X.LOOKBACKYEARS) and LC.INDEXDATE
GROUP BY LC.PATIENT_NUM, FEATURE_NAME, C.COEFF
ORDER BY LC.PATIENT_NUM, FEATURE_NAME
),
--select COUNT(DISTINCT PATIENT_NUM) from PT_FEATURE_COUNT_BY_DATE order by patient_num; --2105 s 146804 21 PATIENTS DON'T HAVE A FACT

--Adjust procedure visits since they need to have 2 or 3 and they require non null providers. 
--If they do not satisfy those conditions the coeff is zero and the feature will be omitted
MD_PX_VISITS_WITH_PROVIDER as (
SELECT PATIENT_NUM, 
FEATURE_NAME, 
DISTINCT_ENCOUNTERS,
CASE 
    WHEN UPPER(FEATURE_NAME) = 'MDVISIT_PNAME2' AND DISTINCT_ENCOUNTERS <> 2  THEN 0
    WHEN UPPER(FEATURE_NAME) = 'MDVISIT_PNAME3' AND DISTINCT_ENCOUNTERS < 3 THEN 0
    ELSE COEFF
END COEFF,
COEFF OLD_COEFF
FROM PT_FEATURE_COUNT_BY_DATE
),
--select * from MD_PX_VISITS_WITH_PROVIDER where distinct_encounters >= 2 and feature_name like 'MD%';--); --147681,250251
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
FROM MD_PX_VISITS_WITH_PROVIDER
),
--select * from ADJ_PT_FEATURE_COUNT_BY_DATE ORDER BY PATIENT_NUM; --);

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
),
--select * from coeff_sums order by patient_num;--,

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
V.INDEXDATE,
case when raw_coeff = 0 then 1 else 0 end as Subjects_NoCriteria,
--raw_coeff as Subjects_NoCriteria,  when showing full coeff
nvl(sum_of_coeff,0) AS Predicted_score,
last_visit AS LAST_VISIT,
D.BIRTH_DATE,
TRUNC(NVL(((V.INDEXDATE-TRUNC(D.BIRTH_DATE))/365.25), 0)) AGE,
CASE WHEN TRUNC(NVL(((V.INDEXDATE-TRUNC(D.BIRTH_DATE))/365.25), 0)) < 65 THEN 'Under 65'
     WHEN TRUNC(NVL(((V.INDEXDATE-TRUNC(D.BIRTH_DATE))/365.25), 0)) >= 65 THEN 'Over 65'
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
from LOYALTY_COHORT_IN_PERIOD V 
LEFT JOIN COEFF_SUMS S ON S.PATIENT_NUM = V.PATIENT_NUM
LEFT JOIN PATIENT_DIMENSION D ON D.PATIENT_NUM = S.PATIENT_NUM
LEFT JOIN PIVOT_PATIENTS P ON P.PATIENT_NUM = S.PATIENT_NUM
), 
-- SELECT * FROM PREDICTIVE_SCORE order by raw_coeff;--,
--select count(distinct patient_num) from PREDICTIVE_SCORE;
-- get patient totals - subjects without any criteria have been filtered out - is this correct? TODO: Check in the meeting
TOTAL_PATIENTS AS 
(
select count(distinct patient_num) TOTAL_PATIENT from PREDICTIVE_SCORE -- where Subjects_NoCriteria = 0
),
TOTAL_PATIENTS_FEMALE AS 
(
select count(distinct patient_num) TOTAL_PATIENT_FEMALE from PREDICTIVE_SCORE where SEX_CD = 'F' --  and Subjects_NoCriteria = 0
),
TOTAL_PATIENTS_MALE AS --189482
(
select count(distinct patient_num) TOTAL_PATIENT_MALE from PREDICTIVE_SCORE where SEX_CD =  'M' -- and Subjects_NoCriteria = 0
),
TOTAL_NO_CRITERIA AS --189482
(
select count(distinct patient_num) TOTAL_NO_CRITERIA from PREDICTIVE_SCORE where Subjects_NoCriteria = 1
)
--select *  from PREDICTIVE_SCORE where Subjects_NoCriteria = 1;
--Final table
SELECT
    COHORT_NAME,
    p.patient_num,
    INDEXDATE,
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
); --END CREATE TABLE LOYALTY_COHORT_BY_AGEGRP

SELECT COUNT(*) FROM LOYALTY_COHORT_BY_AGEGRP; --146825

--rename LOYALTY_COHORT_AGEGRP to LOYALTY_COHORT_BY_AGEGRP;
--TODO MICHELE DO YOU DOUBLE TABLE SIZE -- improve this later
-- ALL PATIENTS
CREATE TABLE LOYALTY_COHORT_AGEGRP AS 
SELECT
    COHORT_NAME,
    patient_num,
    INDEXDATE,
    birth_date,
    Subjects_NoCriteria,
    predicted_score,
    TOTAL_NO_CRITERIA,
    TOTAL_PATIENT,
    TOTAL_PATIENT_MALE,
    TOTAL_PATIENT_FEMALE,
    last_visit,
    age,
    'All Patients' as agegrp,
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
FROM LOYALTY_COHORT_BY_AGEGRP;

SELECT COUNT(*) ALL_PATIENTS FROM LOYALTY_COHORT_AGEGRP; --ALL PATIENTS

--BY AGEGROUP
INSERT INTO LOYALTY_COHORT_AGEGRP
SELECT
    COHORT_NAME,
    patient_num,
    INDEXDATE,
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
FROM LOYALTY_COHORT_BY_AGEGRP;
COMMIT;
SELECT COUNT(*) ALL_PATIENTS_AND_AGEGRP FROM LOYALTY_COHORT_AGEGRP; 

--select * from OBSERVATION_FACT where patient_num = 496587 order by start_date desc;
--SELECT * FROM LOYALTY_COHORT_AGEGRP order by patient_num;--where rownum < 10;
-- Calculate Predictive Score Cutoff by over Agegroups  QUINTILE of DECILE???
CREATE TABLE LOYALTY_AGEGRP_PSC AS SELECT COHORT_NAME, AGEGRP, MIN(PREDICTED_SCORE) PredictiveScoreCutoff
FROM (
SELECT COHORT_NAME, AGEGRP, Predicted_score, NTILE(10) OVER (PARTITION BY COHORT_NAME, AGEGRP ORDER BY PREDICTED_SCORE DESC) AS ScoreRank
FROM(
SELECT COHORT_NAME, AGEGRP, predicted_score
from LOYALTY_cohort_agegrp
)SCORES
)M
WHERE ScoreRank=1
GROUP BY COHORT_NAME, AGEGRP;
COMMIT;

select COUNT(*) from LOYALTY_AGEGRP_PSC;

-- Calculate average fact counts over Agegroups 
--71SEC
CREATE TABLE LOYALTY_AGEGRP_AFC AS 
SELECT COHORT_NAME, CUTOFF_FILTER_YN, AGEGRP, TRUNC(AVG_FACT_COUNT,2) AVG_FACT_CNT
FROM
(
SELECT CAG.COHORT_NAME, CAST('N' AS CHAR(1)) AS CUTOFF_FILTER_YN, cag.AGEGRP, 1.0*count(o.concept_cd)/count(distinct cag.patient_num) as AVG_FACT_COUNT
FROM LOYALTY_cohort_agegrp cag
CROSS JOIN LOYALTY_CONSTANTS x
  join OBSERVATION_FACT O  ON cag.patient_num = O.PATIENT_NUM
WHERE    O.START_DATE between add_months( trunc(CAG.INDEXDATE), -12*X.LOOKBACKYEARS) and CAG.INDEXDATE
group by CAG.COHORT_NAME, cag.AGEGRP
UNION ALL
SELECT CAG.COHORT_NAME, CAST('Y' AS CHAR(1)) AS CUTOFF_FILTER_YN, cag.AGEGRP, 
1.0*count(o.concept_cd)/count(distinct cag.patient_num) as AVG_FACT_COUNT
FROM LOYALTY_cohort_agegrp cag
CROSS JOIN LOYALTY_CONSTANTS x
  JOIN loyalty_AGEGRP_PSC PSC
    ON cag.AGEGRP = PSC.AGEGRP
      AND cag.Predicted_score >= PSC.PredictiveScoreCutoff
  join OBSERVATION_FACT O
    ON cag.patient_num = O.PATIENT_NUM
WHERE    O.START_DATE between add_months( trunc(CAG.INDEXDATE), -12*X.LOOKBACKYEARS) and CAG.INDEXDATE
group by CAG.COHORT_NAME, cag.AGEGRP
)AFC;
COMMIT;

--select count(*) from OBSERVATION_FACT; --71511691
SELECT COUNT(*) FROM LOYALTY_AGEGRP_AFC;
--***********************************************************************************************************
/* OPTIONAL CHARLSON COMORBIDITY INDEX -- ADDS APPROX. 1m in UKY environment. 
   REQUIRES SITE TO LOAD xref_LoyaltyCode_CHARLSON FROM REPO 
*/

-- TODO REFEREANCE create table LU_CHARLSON_ORACLE AS SELECT CHARLSON_CATGRY, CHARLSON_WT, REGEXP_REPLACE(DIAGPATTERN, '%','') DIAGPATTERN FROM LU_CHARLSON;
-- CREATE INDEX LU_CHARLSON_pat ON LU_CHARLSON_ORACLE(DIAGPATTERN);

COMMIT;
--SELECT * FROM LU_CHARLSON_ORACLE;

-- TODO MICHELE THIS IS REFERENCE TABLE MOVE TO TOP AND MAKE CONDITIONAL

DROP TABLE LOYALTY_CHARLSON_DX;
CREATE TABLE LOYALTY_CHARLSON_DX AS
SELECT DISTINCT CHARLSON_CATGRY, CHARLSON_WT, C_BASECODE AS CONCEPT_CD
FROM (
SELECT C.CHARLSON_CATGRY, C.CHARLSON_WT, DX10.C_BASECODE
FROM LU_CHARLSON_ORACLE C
  JOIN ACT_ICD10CM_DX_V4 DX10
    ON REGEXP_LIKE(DX10.C_BASECODE, C.DIAGPATTERN));

insert into LOYALTY_CHARLSON_DX
SELECT C.CHARLSON_CATGRY, C.CHARLSON_WT, DX9.C_BASECODE CONCEPT_CD
FROM LU_CHARLSON_ORACLE C
  JOIN ACT_ICD9CM_DX_V4 DX9
    ON REGEXP_LIKE(DX9.C_BASECODE, C.DIAGPATTERN);

commit;


CREATE TABLE  LOYALTY_CHARLSON_VISIT_BASE AS
WITH CTE_VISIT_BASE AS (
SELECT cohort_name, PATIENT_NUM, SEX, AGE, LAST_VISIT
  , CASE  WHEN AGE < 50 THEN 0
          WHEN AGE BETWEEN 50 AND 59 THEN 1
          WHEN AGE BETWEEN 60 AND 69 THEN 2
          WHEN AGE >= 70 THEN 3 END AS CHARLSON_AGE_BASE
FROM (
SELECT cohort_name, V.PATIENT_NUM
  , SEX
  , V.AGE
  , LAST_VISIT
FROM LOYALTY_COHORT_IN_PERIOD V 
) VISITS
)
SELECT cohort_name, PATIENT_NUM, SEX, AGE, LAST_VISIT, CHARLSON_AGE_BASE
FROM CTE_VISIT_BASE;

commit;

CREATE TABLE LOYALTY_COHORT_CHARLSON AS
SELECT X.site as SITE, 
cohort_name,
PATIENT_NUM
  , LAST_VISIT
  , SEX
  , AGE
  , CAST(case when AGE < 65 then 'Under 65' 
     when age>=65           then 'Over 65' else '-' end AS VARCHAR(20)) AS AGEGRP
  , CHARLSON_INDEX
  , POWER( 0.983
      , POWER(2.71828, (CASE WHEN CHARLSON_INDEX > 7 THEN 7 ELSE CHARLSON_INDEX END) * 0.9)
      ) * 100.0 AS CHARLSON_10YR_SURVIVAL_PROB
  , MI, CHF, CVD, PVD, DEMENTIA, COPD, RHEUMDIS, PEPULCER, MILDLIVDIS, DIABETES_NOCC, DIABETES_WTCC, HEMIPARAPLEG, RENALDIS, CANCER, MSVLIVDIS, METASTATIC, AIDSHIV
FROM (
SELECT cohort_name, PATIENT_NUM, LAST_VISIT, SEX, AGE
  , CHARLSON_AGE_BASE
      + MI + CHF + CVD + PVD + DEMENTIA + COPD + RHEUMDIS + PEPULCER 
      + (CASE WHEN MSVLIVDIS > 0 THEN 0 ELSE MILDLIVDIS END)
      + (CASE WHEN DIABETES_WTCC > 0 THEN 0 ELSE DIABETES_NOCC END)
      + DIABETES_WTCC + HEMIPARAPLEG + RENALDIS + CANCER + MSVLIVDIS + METASTATIC + AIDSHIV AS CHARLSON_INDEX
  , MI, CHF, CVD, PVD, DEMENTIA, COPD, RHEUMDIS, PEPULCER, MILDLIVDIS, DIABETES_NOCC, DIABETES_WTCC, HEMIPARAPLEG, RENALDIS, CANCER, MSVLIVDIS, METASTATIC, AIDSHIV
FROM (
SELECT cohort_name, PATIENT_NUM, SEX, AGE, LAST_VISIT, CHARLSON_AGE_BASE
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
  SELECT cohort_name, O.PATIENT_NUM, O.SEX, O.AGE, O.LAST_VISIT, O.CHARLSON_AGE_BASE, C.CHARLSON_CATGRY, C.CHARLSON_WT
  FROM (SELECT DISTINCT cohort_name, F.PATIENT_NUM, CONCEPT_CD, V.SEX, V.AGE, V.LAST_VISIT, V.CHARLSON_AGE_BASE 
        FROM OBSERVATION_FACT F 
          JOIN LOYALTY_CHARLSON_VISIT_BASE V 
            ON F.PATIENT_NUM = V.PATIENT_NUM
            AND F.START_DATE BETWEEN  ADD_MONTHS( TRUNC(V.LAST_VISIT), -12) AND  V.LAST_VISIT
       )O
    JOIN LOYALTY_CHARLSON_DX C
      ON O.CONCEPT_CD = C.CONCEPT_CD
  GROUP BY cohort_name, O.PATIENT_NUM, O.SEX, O.AGE, O.LAST_VISIT, O.CHARLSON_AGE_BASE, C.CHARLSON_CATGRY, C.CHARLSON_WT
  UNION /* IF NO CHARLSON DX FOUND IN ABOVE INNER JOINS WE CAN UNION TO JUST THE ENCOUNTER+AGE_BASE RECORD WITH CHARLSON FIELDS NULLED OUT
           THIS IS MORE PERFORMANT (SHORTCUT) THAN A LEFT JOIN IN THE OBSERVATION-CHARLSON JOIN ABOVE */
  SELECT cohort_name, V2.PATIENT_NUM, V2.SEX, V2.AGE, V2.LAST_VISIT, V2.CHARLSON_AGE_BASE, NULL, NULL
  FROM LOYALTY_CHARLSON_VISIT_BASE V2
  )DXU
  GROUP BY cohort_name, PATIENT_NUM, SEX, AGE, LAST_VISIT, CHARLSON_AGE_BASE
)cci
)ccisum
CROSS JOIN LOYALTY_CONSTANTS X;

--SELECT * FROM LOYALTY_CHARLSON_VISIT_BASE;

/* CHARLSON 10YR PROB MEDIAN/MEAN/MODE/STDEV */

--select * from LOYALTY_CHARLSON_STATS;
/* UNFILTERED BY PSC */
CREATE TABLE LOYALTY_CHARLSON_STATS AS
WITH CTE_MODE AS (
SELECT cohort_name, NVL(A.AGEGRP,'All Patients') AGEGRP
  , CHARLSON_10YR_SURVIVAL_PROB
  , RANK() OVER (PARTITION BY cohort_name, NVL(A.AGEGRP,'All Patients') ORDER BY N DESC) MR_AG
FROM (
SELECT cohort_name, AGEGRP, CHARLSON_10YR_SURVIVAL_PROB, COUNT(*) N
FROM LOYALTY_COHORT_CHARLSON
GROUP BY GROUPING SETS ((cohort_name, AGEGRP, CHARLSON_10YR_SURVIVAL_PROB),(cohort_name, CHARLSON_10YR_SURVIVAL_PROB))
)A 
GROUP BY cohort_name, NVL(A.AGEGRP,'All Patients'), CHARLSON_10YR_SURVIVAL_PROB, N
)
, CTE_MEAN_STDEV_MODE AS (
SELECT GS.cohort_name, NVL(GS.AGEGRP,'All Patients') AGEGRP, MEAN_10YRPROB, STDEV_10YRPROB
  , AVG(CHARLSON_10YR_SURVIVAL_PROB) AS MODE_10YRPROB /* ONLY MEANINGFUL WHEN THERE IS A TIE FOR MODE */
FROM (
SELECT cohort_name, AGEGRP, AVG(CHARLSON_10YR_SURVIVAL_PROB) MEAN_10YRPROB, STDDEV(CHARLSON_10YR_SURVIVAL_PROB) STDEV_10YRPROB
FROM LOYALTY_COHORT_CHARLSON
GROUP BY GROUPING SETS ((cohort_name, AGEGRP),(cohort_name))
)GS JOIN CTE_MODE M
  ON GS.cohort_name = M.cohort_name
  AND NVL(GS.AGEGRP,'All Patients') = M.AGEGRP
  AND M.MR_AG = 1
GROUP BY GS.cohort_name, NVL(GS.AGEGRP,'All Patients'), MEAN_10YRPROB, STDEV_10YRPROB
)
SELECT MS.cohort_name, MS.AGEGRP
  , CAST('N' AS CHAR(1)) CUTOFF_FILTER_YN
  , MEDIAN_10YR_SURVIVAL
  , S.MEAN_10YRPROB
  , S.STDEV_10YRPROB
  , S.MODE_10YRPROB
FROM (
SELECT cohort_name, AGEGRP, CHARLSON_10YR_SURVIVAL_PROB
  , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CHARLSON_10YR_SURVIVAL_PROB) OVER (PARTITION BY cohort_name, AGEGRP) AS MEDIAN_10YR_SURVIVAL
FROM LOYALTY_COHORT_CHARLSON
WHERE AGEGRP != '-'
UNION ALL
SELECT cohort_name, 'All Patients' as AGEGRP, CHARLSON_10YR_SURVIVAL_PROB
  , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CHARLSON_10YR_SURVIVAL_PROB) OVER (PARTITION BY cohort_name) AS MEDIAN_10YR_SURVIVAL
FROM LOYALTY_COHORT_CHARLSON
WHERE AGEGRP != '-'
)MS JOIN CTE_MEAN_STDEV_MODE S
  ON MS.AGEGRP = S.AGEGRP
  AND MS.cohort_name = S.cohort_name
GROUP BY MS.cohort_name, MS.AGEGRP, MEDIAN_10YR_SURVIVAL, S.MODE_10YRPROB, S.STDEV_10YRPROB, S.MEAN_10YRPROB;

SELECT * FROM LOYALTY_CHARLSON_STATS;

/* FILTERED BY PSC - AGEGRP*/
INSERT INTO LOYALTY_CHARLSON_STATS(cohort_name, AGEGRP,CUTOFF_FILTER_YN,MEDIAN_10YR_SURVIVAL,MEAN_10YRPROB,STDEV_10YRPROB,MODE_10YRPROB)
WITH CTE_MODE AS (
SELECT cohort_name
  , AGEGRP
  , CHARLSON_10YR_SURVIVAL_PROB
  , RANK() OVER (PARTITION BY COHORT_NAME, NVL(A.AGEGRP,'All Patients') ORDER BY N DESC) MR_AG
FROM (
SELECT CC.cohort_name, C.AGEGRP, CHARLSON_10YR_SURVIVAL_PROB, COUNT(*) N
FROM LOYALTY_COHORT_CHARLSON CC
  JOIN LOYALTY_cohort_agegrp C
    ON CC.PATIENT_NUM = C.patient_num
    AND CC.cohort_name = C.cohort_name
  JOIN LOYALTY_AGEGRP_PSC PSC
    ON C.AGEGRP = PSC.AGEGRP
    AND C.Predicted_score >= PSC.PredictiveScoreCutoff
    AND C.cohort_name = PSC.cohort_name
GROUP BY CC.cohort_name, C.AGEGRP,CHARLSON_10YR_SURVIVAL_PROB
)A
GROUP BY cohort_name, AGEGRP, CHARLSON_10YR_SURVIVAL_PROB, N
)
, CTE_MEAN_STDEV_MODE AS (
SELECT GS.cohort_name, NVL(GS.AGEGRP,'All Patients') AS AGEGRP, MEAN_10YRPROB, STDEV_10YRPROB
  , AVG(CHARLSON_10YR_SURVIVAL_PROB) AS MODE_10YRPROB
FROM (
SELECT CC.cohort_name, C.AGEGRP, AVG(CHARLSON_10YR_SURVIVAL_PROB) MEAN_10YRPROB, STDDEV(CHARLSON_10YR_SURVIVAL_PROB) STDEV_10YRPROB
FROM LOYALTY_COHORT_CHARLSON CC
  JOIN LOYALTY_cohort_agegrp C
    ON CC.PATIENT_NUM = C.patient_num
    AND CC.cohort_name = C.cohort_name
  JOIN LOYALTY_AGEGRP_PSC PSC
    ON C.AGEGRP = PSC.AGEGRP
    AND C.Predicted_score >= PSC.PredictiveScoreCutoff
    AND C.cohort_name = C.cohort_name
GROUP BY CC.cohort_name, C.AGEGRP
)GS JOIN CTE_MODE M
  ON GS.cohort_name = M.cohort_name
  AND NVL(GS.AGEGRP,'All Patients') = M.AGEGRP
  AND M.MR_AG = 1
GROUP BY GS.cohort_name, NVL(GS.AGEGRP,'All Patients'), MEAN_10YRPROB, STDEV_10YRPROB
)
SELECT MS.COHORT_NAME, MS.AGEGRP
  , CAST('Y' AS CHAR(1)) AS CUTOFF_FILTER_YN
  , MEDIAN_10YR_SURVIVAL
  , S.MEAN_10YRPROB
  , S.STDEV_10YRPROB
  , S.MODE_10YRPROB
FROM (
SELECT CC.cohort_name, C.AGEGRP, CHARLSON_10YR_SURVIVAL_PROB
  , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CHARLSON_10YR_SURVIVAL_PROB) OVER (PARTITION BY CC.COHORT_NAME, C.AGEGRP) AS MEDIAN_10YR_SURVIVAL
FROM LOYALTY_COHORT_CHARLSON CC
  JOIN LOYALTY_cohort_agegrp C
    ON CC.PATIENT_NUM = C.patient_num
      AND CC.cohort_name = C.cohort_name
  JOIN LOYALTY_AGEGRP_PSC PSC
    ON C.AGEGRP = PSC.AGEGRP
    AND C.Predicted_score >= PSC.PredictiveScoreCutoff
    AND CC.cohort_name = PSC.cohort_name
WHERE CC.AGEGRP != '-'
)MS JOIN CTE_MEAN_STDEV_MODE S
  ON MS.AGEGRP = S.AGEGRP
  AND MS.cohort_name = S.cohort_name
GROUP BY MS.cohort_name, MS.AGEGRP, MEDIAN_10YR_SURVIVAL, S.MODE_10YRPROB, S.STDEV_10YRPROB, S.MEAN_10YRPROB;
COMMIT;

SELECT * FROM LOYALTY_CHARLSON_STATS;

--TODO: make this conditional
-- create summary table
--drop table loyalty_dev_summary;
--select * from loyalty_dev_summary;

--select * from loyalty_dev_summary where cohort_name is null;
--select * from loyalty_dev_summary where cohort_name is not null;
--Create temp table cohortagg
--select * from loyalty_cohort_agegrp where subjects_nocriteria = 0;
--delete table LOYALTY_COHORT_AGG;
declare
v_sql LONG;
begin

v_sql:='create table LOYALTY_COHORT_AGG
(
    COHORT_NAME varchar2(30) NULL,
    CUTOFF_FILTER_YN char(1) NOT NULL,
    Summary_Description varchar(20) NOT NULL,
	agegrp varchar(20) NULL,
    totalsubjects number NULL,
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
    TotalSubjectsFemale number NULL,
    TotalSubjectsMale number NULL)';

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
-- INSERT PATIENT COUNTS FILTERED OVER/UNDER
--TRUNCATE TABLE LOYALTY_COHORT_AGG;
--COMMIT;
SELECT * FROM LOYALTY_COHORT_AGG ORDER BY SUMMARY_DESCRIPTION, AGEGRP;
insert into LOYALTY_COHORT_AGG
SELECT
CAG.COHORT_NAME,
'Y' AS CUTOFF_FILTER_YN,
'Patient Counts' as Summary_Description,
CAG.AGEGRP agegrp, 
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
CROSS JOIN LOYALTY_CONSTANTS X
JOIN loyalty_AGEGRP_PSC P ON CAG.AGEGRP = P.AGEGRP AND CAG.Predicted_score >= P.PredictiveScoreCutoff
group by CAG.COHORT_NAME, CAG.AGEGRP;
COMMIT;
--truncate table LOYALTY_COHORT_AGG; TODO should this be emptied out each run
--SELECT * FROM LOYALTY_COHORT_AGG;
--DROP TABLE LOYALTY_COHORT_AGG;
--select * from LOYALTY_CONSTANTS;
-- INSERT PATIENT PERCENT FILTERED OVER/UNDER
INSERT INTO LOYALTY_COHORT_AGG
SELECT
CAG.COHORT_NAME,
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
CROSS JOIN LOYALTY_CONSTANTS X
JOIN loyalty_AGEGRP_PSC P ON CAG.AGEGRP = P.AGEGRP AND CAG.Predicted_score >= P.PredictiveScoreCutoff
group by CAG.COHORT_NAME, CAG.AGEGRP;

COMMIT;
--SELECT * FROM LOYALTY_COHORT_AGG;

-- INSERT PATIENT COUNTS UNFILTERED OVER/UNDER

INSERT INTO LOYALTY_COHORT_AGG
--UNFILTERED -- ALL QUINTILES 
SELECT
CAG.COHORT_NAME,
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
CROSS JOIN LOYALTY_CONSTANTS X
group by CAG.COHORT_NAME, CAG.AGEGRP;
COMMIT;
--SELECT * FROM LOYALTY_COHORT_AGG;
-- INSERT PATIENT PERCENTS FILTERED OVER/UNDER

INSERT INTO LOYALTY_COHORT_AGG
SELECT
CAG.COHORT_NAME,
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
CROSS JOIN LOYALTY_CONSTANTS X
group by CAG.COHORT_NAME, CAG.AGEGRP;  -- 4 unioned
COMMIT;
SELECT * FROM LOYALTY_COHORT_AGG;

--TRUNCATE TABLE loyalty_dev_summary;
--TRUNCATE TABLE loyalty_dev_summary_PRELIM;
--  , CASE WHEN COHORTAGG.CUTOFF_FILTER_YN = 'Y' THEN CP.PredictiveScoreCutoff ELSE NULL END AS PredictiveScoreCutoff

-- START BUILDING THE SUMMARY TABLE
insert into loyalty_dev_summary_PRELIM
SELECT 
cag.cohort_name, 
X.SITE,
X.LOOKBACKYEARS,
CASE WHEN X.GENDERED=1 THEN 'Y' ELSE 'N'END AS GENDER_DENOMINATORS_YN,
'Y' AS CUTOFF_FILTER_YN,
'Patient Counts' as Summary_Description,
CAG.AGEGRP as tablename, 
count(patient_num) as TotalSubjects,
sum(cast(Num_Dx1 as int)) as Num_DX1,
sum(cast(Num_Dx2 as int)) as Num_DX2,
sum(cast(MedUse1 as int))  as MedUse1,
sum(cast(MedUse2 as int)) as MedUse2,
sum(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN mammography ELSE 0 END) AS Mammography,
sum(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN paptest ELSE 0 END) AS paptest,
sum(CASE WHEN X.GENDERED=1 and sex_cd='M' THEN psatest ELSE 0 END) AS psatest,
sum(cast(Colonoscopy as int)) as Colonoscopy,
sum(cast(FecalOccultTest as int)) as FecalOccultTest,
sum(cast(FluShot as int)) as  FluShot,
sum(cast(PneumococcalVaccine as int)) as PneumococcalVaccine,
sum(cast(BMI as int))  as BMI,
sum(cast(A1C as int)) as A1C,
sum(cast(MedicalExam as int)) as MedicalExam,
sum(cast(INP1_OPT1_Visit as int)) as INP1_OPT1_Visit,
sum(cast(OPT2_Visit as int)) as OPT2_Visit,
sum(cast(ED_Visit as int))  as ED_Visit,
sum(cast(MDVisit_pname2 as int)) as MDVisit_pname2,
sum(cast(MDVisit_pname3 as int)) as MDVisit_pname3,
sum(cast(Routine_Care_2 as int)) as Routine_care_2,
SUM(Subjects_NoCriteria) as Subjects_NoCriteria,

SUM(Subjects_NoCriteria) MEAN_10YRPROB, 
SUM(Subjects_NoCriteria) MEDIAN_10YR_SURVIVAL, 
SUM(Subjects_NoCriteria) MODE_10YRPROB, 
SUM(Subjects_NoCriteria)STDEV_10YRPROB, 
sum(CASE WHEN sex_cd='F' THEN 1 ELSE 0 END) AS TotalSubjectsFemale,
sum(CASE WHEN sex_cd='M' THEN 1 ELSE 0 END) AS TotalSubjectsMale,
trunc(sum(CASE WHEN sex_cd='F' THEN 1 ELSE 0 END) / count(patient_num)) AS PercentSubjectsFemale,
trunc(sum(CASE WHEN sex_cd='M' THEN 1 ELSE 0 END) / count(patient_num)) AS PercentSubjectsMale
from LOYALTY_COHORT_AGEGRP CAG 
CROSS JOIN LOYALTY_CONSTANTS X
JOIN LOYALTY_AGEGRP_PSC P ON CAG.AGEGRP = P.AGEGRP AND CAG.Predicted_score >= P.PredictiveScoreCutoff AND CAG.cohort_name = P.cohort_name
group by CAG.cohort_name, CAG.AGEGRP, X.SITE, X.LOOKBACKYEARS, X.GENDERED;

commit;

insert into loyalty_dev_summary_PRELIM
SELECT 
cag.cohort_name, 
X.SITE,
X.LOOKBACKYEARS,
CASE WHEN X.GENDERED=1 THEN 'Y' ELSE 'N'END AS GENDER_DENOMINATORS_YN,
'Y' AS CUTOFF_FILTER_YN,
'Percent Of Subjects' as Summary_Description,
CAG.AGEGRP, 
count(patient_num) as TotalSubjects,
100*(sum(cast(Num_Dx1 as int))/count(patient_num)) as Num_DX1,
100*(sum(cast(Num_Dx2 as int))/count(patient_num)) as Num_DX2,
100*(sum(cast(MedUse1 as int))/count(patient_num))  as MedUse1,
100*(sum(cast(MedUse2 as int))/count(patient_num)) as MedUse2,
100*(sum(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN mammography ELSE 0 END)/count(patient_num)) AS Mammography,
100*(sum(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN paptest ELSE 0 END)/count(patient_num)) AS paptest,
100*(sum(CASE WHEN X.GENDERED=1 and sex_cd='M' THEN psatest ELSE 0 END)/count(patient_num)) AS psatest,
100*(sum(cast(Colonoscopy as int))/count(patient_num)) as Colonoscopy,
100*(sum(cast(FecalOccultTest as int))/count(patient_num)) as FecalOccultTest,
100*(sum(cast(FluShot as int))/count(patient_num)) as  FluShot,
100*(sum(cast(PneumococcalVaccine as int))/count(patient_num)) as PneumococcalVaccine,
100*(sum(cast(BMI as int))/count(patient_num))  as BMI,
100*(sum(cast(A1C as int))/count(patient_num)) as A1C,
100*(sum(cast(MedicalExam as int))/count(patient_num)) as MedicalExam,
100*(sum(cast(INP1_OPT1_Visit as int))/count(patient_num)) as INP1_OPT1_Visit,
100*(sum(cast(OPT2_Visit as int))/count(patient_num)) as OPT2_Visit,
100*(sum(cast(ED_Visit as int))/count(patient_num))  as ED_Visit,
100*(sum(cast(MDVisit_pname2 as int))/count(patient_num)) as MDVisit_pname2,
100*(sum(cast(MDVisit_pname3 as int))/count(patient_num)) as MDVisit_pname3,
100*(sum(cast(Routine_Care_2 as int))/count(patient_num)) as Routine_care_2,
100*(sum(Subjects_NoCriteria)/count(patient_num)) as Subjects_NoCriteria,

SUM(Subjects_NoCriteria) MEAN_10YRPROB, 
SUM(Subjects_NoCriteria) MEDIAN_10YR_SURVIVAL, 
SUM(Subjects_NoCriteria) MODE_10YRPROB, 
SUM(Subjects_NoCriteria)STDEV_10YRPROB, 
TRUNC(100*(sum(CASE WHEN sex_cd='F' THEN 1 ELSE 0 END)/count(patient_num))) AS TotalSubjectsFemale,
TRUNC(100*(sum(CASE WHEN sex_cd='M' THEN 1 ELSE 0 END)/count(patient_num))) AS TotalSubjectsMale,
TRUNC(100*(sum(CASE WHEN sex_cd='F' THEN 1 ELSE 0 END) / count(patient_num))) AS PercentSubjectsFemale,
TRUNC(100*(sum(CASE WHEN sex_cd='M' THEN 1 ELSE 0 END) / count(patient_num))) AS PercentSubjectsMale
from LOYALTY_COHORT_AGEGRP CAG 
CROSS JOIN LOYALTY_CONSTANTS X
JOIN LOYALTY_AGEGRP_PSC P ON CAG.AGEGRP = P.AGEGRP AND CAG.Predicted_score >= P.PredictiveScoreCutoff AND CAG.cohort_name = P.cohort_name
group by CAG.cohort_name, CAG.AGEGRP, X.SITE, X.LOOKBACKYEARS, X.GENDERED;
COMMIT;

--UNFILTERED
INSERT INTO loyalty_dev_summary_PRELIM
SELECT 
cag.cohort_name, 
X.SITE,
X.LOOKBACKYEARS,
CASE WHEN X.GENDERED=1 THEN 'Y' ELSE 'N'END AS GENDER_DENOMINATORS_YN,
'N' AS CUTOFF_FILTER_YN,
'Patient Counts' as Summary_Description,
CAG.AGEGRP, 
count(patient_num) as TotalSubjects,
sum(cast(Num_Dx1 as int)) as Num_DX1,
sum(cast(Num_Dx2 as int)) as Num_DX2,
sum(cast(MedUse1 as int))  as MedUse1,
sum(cast(MedUse2 as int)) as MedUse2,
sum(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN mammography ELSE 0 END) AS Mammography,
sum(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN paptest ELSE 0 END) AS paptest,
sum(CASE WHEN X.GENDERED=1 and sex_cd='M' THEN psatest ELSE 0 END) AS psatest,
sum(cast(Colonoscopy as int)) as Colonoscopy,
sum(cast(FecalOccultTest as int)) as FecalOccultTest,
sum(cast(FluShot as int)) as  FluShot,
sum(cast(PneumococcalVaccine as int)) as PneumococcalVaccine,
sum(cast(BMI as int))  as BMI,
sum(cast(A1C as int)) as A1C,
sum(cast(MedicalExam as int)) as MedicalExam,
sum(cast(INP1_OPT1_Visit as int)) as INP1_OPT1_Visit,
sum(cast(OPT2_Visit as int)) as OPT2_Visit,
sum(cast(ED_Visit as int))  as ED_Visit,
sum(cast(MDVisit_pname2 as int)) as MDVisit_pname2,
sum(cast(MDVisit_pname3 as int)) as MDVisit_pname3,
sum(cast(Routine_Care_2 as int)) as Routine_care_2,
SUM(Subjects_NoCriteria) as Subjects_NoCriteria,
SUM(Subjects_NoCriteria) MEAN_10YRPROB, 
SUM(Subjects_NoCriteria) MEDIAN_10YR_SURVIVAL, 
SUM(Subjects_NoCriteria) MODE_10YRPROB, 
SUM(Subjects_NoCriteria)STDEV_10YRPROB, 
sum(CASE WHEN sex_cd='F' THEN 1 ELSE 0 END) AS TotalSubjectsFemale,
sum(CASE WHEN sex_cd='M' THEN 1 ELSE 0 END) AS TotalSubjectsMale,
trunc(sum(CASE WHEN sex_cd='F' THEN 1 ELSE 0 END) / count(patient_num)) AS PercentSubjectsFemale,
trunc(sum(CASE WHEN sex_cd='M' THEN 1 ELSE 0 END) / count(patient_num)) AS PercentSubjectsMale
from LOYALTY_COHORT_AGEGRP CAG 
CROSS JOIN LOYALTY_CONSTANTS X
JOIN LOYALTY_AGEGRP_PSC P ON CAG.AGEGRP = P.AGEGRP  AND CAG.cohort_name = P.cohort_name
group by CAG.cohort_name, CAG.AGEGRP, X.SITE, X.LOOKBACKYEARS, X.GENDERED;
COMMIT;
SELECT * FROM LOYALTY_DEV_SUMMARY_PRELIM order by summary_description, gender_denominators_yn, cutoff_filter_yn, tablename;


INSERT INTO loyalty_dev_summary_PRELIM
SELECT 
cag.cohort_name, 
X.SITE,
X.LOOKBACKYEARS,
CASE WHEN X.GENDERED=1 THEN 'Y' ELSE 'N'END AS GENDER_DENOMINATORS_YN,
'N' AS CUTOFF_FILTER_YN,
'Percent Of Subjects' as Summary_Description,
CAG.AGEGRP, 
count(patient_num) as TotalSubjects,
100*(sum(cast(Num_Dx1 as int))/count(patient_num)) as Num_DX1,
100*(sum(cast(Num_Dx2 as int))/count(patient_num)) as Num_DX2,
100*(sum(cast(MedUse1 as int))/count(patient_num))  as MedUse1,
100*(sum(cast(MedUse2 as int))/count(patient_num)) as MedUse2,
100*(sum(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN mammography ELSE 0 END)/count(patient_num)) AS Mammography,
100*(sum(CASE WHEN X.GENDERED=1 and sex_cd='F' THEN paptest ELSE 0 END)/count(patient_num)) AS paptest,
100*(sum(CASE WHEN X.GENDERED=1 and sex_cd='M' THEN psatest ELSE 0 END)/count(patient_num)) AS psatest,
100*(sum(cast(Colonoscopy as int))/count(patient_num)) as Colonoscopy,
100*(sum(cast(FecalOccultTest as int))/count(patient_num)) as FecalOccultTest,
100*(sum(cast(FluShot as int))/count(patient_num)) as  FluShot,
100*(sum(cast(PneumococcalVaccine as int))/count(patient_num)) as PneumococcalVaccine,
100*(sum(cast(BMI as int))/count(patient_num))  as BMI,
100*(sum(cast(A1C as int))/count(patient_num)) as A1C,
100*(sum(cast(MedicalExam as int))/count(patient_num)) as MedicalExam,
100*(sum(cast(INP1_OPT1_Visit as int))/count(patient_num)) as INP1_OPT1_Visit,
100*(sum(cast(OPT2_Visit as int))/count(patient_num)) as OPT2_Visit,
100*(sum(cast(ED_Visit as int))/count(patient_num))  as ED_Visit,
100*(sum(cast(MDVisit_pname2 as int))/count(patient_num)) as MDVisit_pname2,
100*(sum(cast(MDVisit_pname3 as int))/count(patient_num)) as MDVisit_pname3,
100*(sum(cast(Routine_Care_2 as int))/count(patient_num)) as Routine_care_2,
SUM(Subjects_NoCriteria) as Subjects_NoCriteria,
SUM(Subjects_NoCriteria) MEAN_10YRPROB, 
SUM(Subjects_NoCriteria) MEDIAN_10YR_SURVIVAL, 
SUM(Subjects_NoCriteria) MODE_10YRPROB, 
SUM(Subjects_NoCriteria)STDEV_10YRPROB, 
TRUNC(100*(sum(CASE WHEN sex_cd='F' THEN 1 ELSE 0 END)/count(patient_num))) AS TotalSubjectsFemale,
TRUNC(100*(sum(CASE WHEN sex_cd='M' THEN 1 ELSE 0 END)/count(patient_num))) AS TotalSubjectsMale,
TRUNC(100*(sum(CASE WHEN sex_cd='F' THEN 1 ELSE 0 END) / count(patient_num))) AS PercentSubjectsFemale,
TRUNC(100*(sum(CASE WHEN sex_cd='M' THEN 1 ELSE 0 END) / count(patient_num))) AS PercentSubjectsMale
from LOYALTY_COHORT_AGEGRP CAG 
CROSS JOIN LOYALTY_CONSTANTS X
JOIN LOYALTY_AGEGRP_PSC P ON CAG.AGEGRP = P.AGEGRP  AND CAG.cohort_name = P.cohort_name
group by CAG.cohort_name, CAG.AGEGRP, X.SITE, X.LOOKBACKYEARS, X.GENDERED;
COMMIT;

--SELECT * FROM LOYALTY_DEV_SUMMARY;
--SELECT * FROM LOYALTY_CHARLSON_STATS;
--SELECT * FROM LOYALTY_AGEGRP_AFC;
--SELECT * FROM LOYALTY_AGEGRP_PSC;
--SELECT * FROM LOYALTY_COHORT_AGEGRP;

SELECT * FROM LOYALTY_DEV_SUMMARY_PRELIM order by summary_description, gender_denominators_yn, cutoff_filter_yn, tablename;

/*
INSERT INTO LOYALTY_DEV_SUMMARY 
SELECT 
    CP.cohort_name, 
    COHORTAGG.SITE, 
    COHORTAGG.LOOKBACK_YR, 
    COHORTAGG.GENDER_DENOMINATORS_YN, 
    COHORTAGG.CUTOFF_FILTER_YN, 
    COHORTAGG.Summary_Description, 
    COHORTAGG.tablename, 
    Num_DX1, 
    Num_DX2, 
    MedUse1, 
    MedUse2,
    Mammography, 
    PapTest, 
    PSATest, 
    Colonoscopy, 
    FecalOccultTest, 
    FluShot, 
    PneumococcalVaccine, 
    BMI, 
    A1C, 
    MedicalExam, 
    INP1_OPT1_Visit, 
    OPT2_Visit, 
    ED_Visit,
    MDVisit_pname2, 
    MDVisit_pname3, 
    Routine_care_2, 
    Subjects_NoCriteria, 
    CASE WHEN COHORTAGG.CUTOFF_FILTER_YN = 'Y' THEN CP.PredictiveScoreCutoff ELSE NULL END AS PredictiveScoreCutoff,
    CS.MEAN_10YRPROB, 
    CS.MEDIAN_10YR_SURVIVAL, 
    CS.MODE_10YRPROB, 
    CS.STDEV_10YRPROB, 
    COHORTAGG.TotalSubjects,
    TotalSubjectsFemale, 
    TotalSubjectsMale, 
    PercentSubjectsFemale, 
    PercentSubjectsMale, 
    AVG_FACT_CNT AverageFactCount
FROM LOYALTY_DEV_SUMMARY_PRELIM COHORTAGG
left outer JOIN LOYALTY_AGEGRP_PSC CP
    ON cohortagg.tablename = CP.AGEGRP
    AND COHORTAGG.cohort_name = CP.cohort_name
left outer JOIN LOYALTY_CHARLSON_STATS CS
    ON COHORTAGG.tablename = CS.AGEGRP
      AND COHORTAGG.CUTOFF_FILTER_YN = CS.CUTOFF_FILTER_YN
      AND COHORTAGG.cohort_name = CS.cohort_name
left outer JOIN LOYALTY_AGEGRP_AFC FC
    ON COHORTAGG.tablename = FC.AGEGRP
      AND COHORTAGG.CUTOFF_FILTER_YN = FC.CUTOFF_FILTER_YN
      AND COHORTAGG.cohort_name = FC.cohort_name;
commit;
*/
/*
select * from LOYALTY_CHARLSON_STATS;
select * from LOYALTY_AGEGRP_PSC;
select * from LOYALTY_AGEGRP_AFC;
select * from LOYALTY_DEV_SUMMARY;
SELECT * FROM LOYALTY_DEV_SUMMARY_PRELIM order by summary_description, gender_denominators_yn, cutoff_filter_yn, tablename;
*/

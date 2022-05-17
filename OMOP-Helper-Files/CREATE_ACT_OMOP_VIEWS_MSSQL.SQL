--select 'DROP VIEW ' || view_name || ';' from user_views;-- add blob to ALL views?
DROP VIEW CONDITION_VIEW;
DROP VIEW DRUG_VIEW;
DROP VIEW MEASUREMENT_VIEW;
DROP VIEW OBSERVATION_VIEW;
DROP VIEW PROCEDURE_VIEW;
DROP VIEW COVID_LAB_VIEW;
DROP VIEW ALL_SOURCE_CONCEPTS;
DROP VIEW PATIENT_DIMENSION;
DROP VIEW VISIT_DIMENSION;
DROP VIEW DEVICE_VIEW;
-- OMOP View to consolidate all non standard concept_ids
CREATE  VIEW ALL_SOURCE_CONCEPTS (ENCOUNTER_NUM, PATIENT_NUM, CONCEPT_CD, PROVIDER_ID, START_DATE, END_DATE, MODIFIER_CD, 
INSTANCE_NUM, VALTYPE_CD, LOCATION_CD, TVAL_CHAR, NVAL_NUM, VALUEFLAG_CD, UNITS_CD, STANDARD_CONCEPT_ID, SOURCE_VALUE, DOMAIN_ID) AS 
  SELECT
			ENCOUNTER_NUM, 
 			PATIENT_NUM, 
   			CONCEPT_CD, 
   			PROVIDER_ID, 
   			START_DATE, 
			END_DATE, 
            MODIFIER_CD,
            INSTANCE_NUM,
            valtype_cd,
            location_cd,
            tval_char,
            nval_num,
            valueflag_cd,
            units_cd,
            STANDARD_CONCEPT_ID,
            SOURCE_VALUE,
            DOMAIN_ID
FROM (
 SELECT  
			visit_occurrence_id AS ENCOUNTER_NUM, 
 			PERSON_ID AS PATIENT_NUM, 
   			cast(condition_source_concept_id as varchar(50)) AS CONCEPT_CD, 
   			CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
   			condition_start_datetime AS START_DATE, 
			condition_end_datetime AS END_DATE, 
            NULL AS MODIFIER_CD,
            NULL AS INSTANCE_NUM,
            NULL AS valtype_cd,
            NULL AS location_cd,
            NULL AS tval_char,
            NULL AS nval_num,
            NULL AS valueflag_cd,
            NULL AS units_cd,
   			condition_concept_id AS STANDARD_CONCEPT_ID,
            condition_source_value AS SOURCE_VALUE,
            'CONDITION' AS DOMAIN_ID
--			condition_occurrence_id integer NOT NULL, 
--			condition_start_datetime TIMESTAMP NULL, 
--			condition_end_datetime TIMESTAMP NULL, 
--			condition_type_concept_id integer NOT NULL, --modifier?
--			stop_reason varchar(20) NULL, 
--			visit_detail_id integer NULL, 
--			condition_status_source_value varchar(50) NULL );  
FROM CONDITION_OCCURRENCE 
UNION
--HINT DISTRIBUTE ON KEY (person_id)
 SELECT 
 			visit_occurrence_id AS ENCOUNTER_NUM, 
 			PERSON_ID AS PATIENT_NUM, 
   			cast(drug_source_concept_id as varchar(50)) AS CONCEPT_CD, 
   			CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
   			drug_exposure_start_datetime AS START_DATE, 
			drug_exposure_END_datetime AS END_DATE, 
            NULL AS MODIFIER_CD,
            NULL AS INSTANCE_NUM,
            NULL AS valtype_cd,
            NULL AS location_cd,
            NULL AS tval_char,
            NULL AS nval_num,
            NULL AS valueflag_cd,
            NULL AS units_cd,
   			drug_concept_id AS STANDARD_CONCEPT_ID,
            drug_source_value AS SOURCE_VALUE,
            'DRUG' AS DOMAIN_ID
--			drug_exposure_start_datetime TIMESTAMP NULL, 
--			drug_exposure_end_datetime TIMESTAMP NULL, 
--			verbatim_end_date date NULL, 
--			drug_type_concept_id integer NOT NULL, 
--			stop_reason varchar(20) NULL, 
--			refills integer NULL, 
--			quantity float NULL, 
--			days_supply integer NULL, 
--			sig CLOB NULL, 
--			route_concept_id integer NULL, 
--			lot_number varchar(50) NULL, 
--			visit_detail_id integer NULL, 
--			route_source_value varchar(50) NULL, 
--			dose_unit_source_value varchar(50) NULL );  
FROM DRUG_EXPOSURE
UNION
--HINT DISTRIBUTE ON KEY (person_id)
SELECT
 			visit_occurrence_id AS ENCOUNTER_NUM, 
 			PERSON_ID AS PATIENT_NUM, 
   			cast(procedure_source_concept_id as varchar(50)) AS CONCEPT_CD, 
   			CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
   			procedure_datetime AS START_DATE, 
			NULL AS END_DATE, 
            NULL AS MODIFIER_CD,
            NULL AS INSTANCE_NUM,
            NULL AS valtype_cd,
            NULL AS location_cd,
            NULL AS tval_char,
            NULL AS nval_num,
            NULL AS valueflag_cd,
            NULL AS units_cd,
            procedure_concept_id AS STANDARD_CONCEPT_ID,
            procedure_source_value AS SOURCE_VALUE,
            'PROCEDURE' AS DOMAIN_ID
--			procedure_occurrence_id integer NOT NULL, 
--			procedure_datetime TIMESTAMP NULL, 
--			procedure_type_concept_id integer NOT NULL, 
--			modifier_concept_id integer NULL, 
--			quantity integer NULL, 
--			visit_detail_id integer NULL, 
--			modifier_source_value varchar(50) NULL );  
FROM PROCEDURE_OCCURRENCE
UNION
SELECT 
			visit_occurrence_id AS ENCOUNTER_NUM, 
 			PERSON_ID AS PATIENT_NUM, 
   			cast(device_source_concept_id as varchar(50)) AS CONCEPT_CD, 
   			CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
   			device_exposure_start_datetime AS START_DATE, 
			device_exposure_end_datetime AS END_DATE, 
            device_type_concept_id AS MODIFIER_CD,
            NULL AS INSTANCE_NUM,
            NULL AS valtype_cd,
            NULL AS location_cd,
            NULL AS tval_char,
            NULL AS nval_num,
            NULL AS valueflag_cd,
            NULL AS units_cd,
   			device_exposure_id AS STANDARD_CONCEPT_ID, --device_concept_id??
            device_source_value AS SOURCE_VALUE,
            'DEVICE' AS DOMAIN_ID
--			device_exposure_start_datetime TIMESTAMP NULL, 
--			device_exposure_end_datetime TIMESTAMP NULL, 
--			unique_device_id varchar(50) NULL, 
--			quantity integer NULL, 
--			visit_detail_id integer NULL, 
FROM DEVICE_EXPOSURE
UNION
SELECT
			visit_occurrence_id AS ENCOUNTER_NUM, 
 			PERSON_ID AS PATIENT_NUM, 
   			cast(measurement_source_concept_id as varchar(50)) AS CONCEPT_CD, 
   			CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
   			measurement_datetime AS START_DATE, 
			NULL AS END_DATE, 
            measurement_type_concept_id AS MODIFIER_CD,
            NULL AS INSTANCE_NUM,
            CASE 
                WHEN VALUE_AS_NUMBER IS NOT NULL 
                THEN 'N' 
                ELSE 'T' 
            END AS valtype_cd, --DECODE THIS IS THE FUTURE operator_concept_id
            NULL AS location_cd,
            CASE 
                WHEN OPERATOR_CONCEPT_ID = 4172703 THEN 'E' 
                WHEN OPERATOR_CONCEPT_ID = 4171756 THEN 'LT' 
                WHEN OPERATOR_CONCEPT_ID = 4172704 THEN 'GT' 
                WHEN OPERATOR_CONCEPT_ID = 4171754 THEN 'LE' 
                WHEN OPERATOR_CONCEPT_ID = 4171755 THEN 'GE' 
                WHEN OPERATOR_CONCEPT_ID IS NULL AND VALUE_AS_NUMBER IS NOT NULL THEN 'E' 
                ELSE VALUE_SOURCE_VALUE 
            END AS TVAL_CHAR,
            VALUE_AS_NUMBER AS NVAL_NUM,
           	CAST(VALUE_AS_CONCEPT_ID AS VARCHAR(50) ) AS VALUEFLAG_CD,
            UNIT_SOURCE_VALUE AS UNITS_CD, -- DECODE THIS TO QUERY BY VALUE unit_concept_id IN THE FUTURE FOR NOW JUST USE THE UNIT SOURCE VALUE
   			measurement_concept_id AS STANDARD_CONCEPT_ID, 
            measurement_source_value AS SOURCE_VALUE,
            'MEASUREMENT' AS DOMAIN_ID
--            value_source_value as value_source_value
--			measurement_id integer NOT NULL, 
--			measurement_datetime TIMESTAMP NULL, 
--			measurement_time varchar(10) NULL, 
--			operator_concept_id integer NULL, -- CHANGE OPERATOR TO OMOP CONCEPT_ID IN ONTOLOGY <, <=, =, >=, >.
--			value_as_concept_id integer NULL
--			range_low float NULL, 
--			range_high float NULL, 
--			visit_detail_id integer NULL, 
--			value_source_value varchar(50) NULL );  
FROM MEASUREMENT --where value_source_value like 'Not%' order by tval_char;
UNION
SELECT 
			visit_occurrence_id AS ENCOUNTER_NUM, 
 			PERSON_ID AS PATIENT_NUM, 
   			CAST(observation_source_concept_id AS VARCHAR(50)) AS CONCEPT_CD, 
   			CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
   			observation_datetime AS START_DATE, 
			NULL AS END_DATE, 
            observation_type_concept_id AS MODIFIER_CD,
            1 AS INSTANCE_NUM,
            CASE 
                WHEN VALUE_AS_NUMBER IS NOT NULL 
                THEN 'N' 
                ELSE 'T' 
            END AS valtype_cd, --DECODE THIS IS THE FUTURE operator_concept_id
            NULL AS location_cd,
            VALUE_AS_STRING AS TVAL_CHAR,
            VALUE_AS_NUMBER AS NVAL_NUM,
            CAST(QUALIFIER_CONCEPT_ID AS VARCHAR(50)) AS VALUEFLAG_CD,
            UNIT_SOURCE_VALUE AS UNITS_CD,  -- DECODE THIS TO QUERY BY VALUE unit_concept_id IN THE FUTURE FOR NOW JUST USE THE UNIT SOURCE VALUE
   			observation_concept_id AS STANDARD_CONCEPT_ID, --device_concept_id??
            observation_source_value AS SOURCE_VALUE,
            'OBSERVATION' AS DOMAIN_ID
--            value_source_value as value_source_value
--          value_as_concept_id Integer NULL, 
--			qualifier_concept_id integer NULL, 
--			unit_concept_id integer NULL, 
--			visit_detail_id integer NULL, 
--			qualifier_source_value varchar(50) NULL );  
FROM OBSERVATION
); 
--SELECT * FROM ALL_SOURCE_CONCEPTS;
--SELECT * FROM DRUG_EXPOSURE WHERE DRUG_SOURCE_VALUE = '140';
--SELECT DISTINCT CONCEPT_CLASS_ID FROM omop_CONCEPT; --cvx
--select * from condition_view;
CREATE  VIEW CONDITION_VIEW AS 
SELECT  
			visit_occurrence_id AS ENCOUNTER_NUM, 
 			PERSON_ID AS PATIENT_NUM, 
   			cast(condition_concept_id as varchar(50)) AS CONCEPT_CD, 
   			CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
   			condition_start_datetime AS START_DATE, 
			condition_end_datetime AS END_DATE, 
            NULL AS MODIFIER_CD,
            NULL AS INSTANCE_NUM,
            NULL AS valtype_cd,
            NULL AS location_cd,
            NULL AS tval_char,
            NULL AS nval_num,
            NULL AS valueflag_cd,
            NULL AS units_cd,
            NULL CONFIDENCE_NUM, 
            NULL SOURCESYSTEM_CD, 
            NULL UPDATE_DATE, 
            NULL DOWNLOAD_DATE, 
            NULL IMPORT_DATE, 
            NULL UPLOAD_ID,
   			condition_SOURCE_concept_id AS SOURCE_CONCEPT_ID,
            condition_source_value AS SOURCE_VALUE,
            'CONDITION' AS DOMAIN_ID
--			condition_occurrence_id integer NOT NULL, 
--			condition_start_datetime TIMESTAMP NULL, 
--			condition_end_datetime TIMESTAMP NULL, 
--			condition_type_concept_id integer NOT NULL, --modifier?
--			stop_reason varchar(20) NULL, 
--			visit_detail_id integer NULL, 
--			condition_status_source_value varchar(50) NULL );  
FROM CONDITION_OCCURRENCE;

CREATE  VIEW PROCEDURE_VIEW AS 
SELECT
 			visit_occurrence_id AS ENCOUNTER_NUM, 
 			PERSON_ID AS PATIENT_NUM, 
   			cast(procedure_concept_id as varchar(50)) AS CONCEPT_CD, 
   			CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
   			procedure_datetime AS START_DATE, 
			NULL AS END_DATE, 
            NULL AS MODIFIER_CD,
            NULL AS INSTANCE_NUM,
            NULL AS valtype_cd,
            NULL AS location_cd,
            NULL AS tval_char,
            NULL AS nval_num,
            NULL AS valueflag_cd,
            NULL AS units_cd,
            NULL CONFIDENCE_NUM, 
            NULL SOURCESYSTEM_CD, 
            NULL UPDATE_DATE, 
            NULL DOWNLOAD_DATE, 
            NULL IMPORT_DATE, 
            NULL UPLOAD_ID,
            procedure_source_concept_id AS SOURCE_CONCEPT_ID,
            procedure_source_value AS SOURCE_VALUE,
            'PROCEDURE' AS DOMAIN_ID
--			procedure_occurrence_id integer NOT NULL, 
--			procedure_datetime TIMESTAMP NULL, 
--			procedure_type_concept_id integer NOT NULL, 
--			modifier_concept_id integer NULL, 
--			quantity integer NULL, 
--			visit_detail_id integer NULL, 
--			modifier_source_value varchar(50) NULL );  
FROM PROCEDURE_OCCURRENCE;

CREATE  VIEW DRUG_VIEW AS 
SELECT 
 			visit_occurrence_id AS ENCOUNTER_NUM, 
 			PERSON_ID AS PATIENT_NUM, 
   			cast(drug_concept_id as varchar(50)) AS CONCEPT_CD, 
   			CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
   			drug_exposure_start_datetime AS START_DATE, 
			drug_exposure_END_datetime AS END_DATE, 
            NULL AS MODIFIER_CD,
            NULL AS INSTANCE_NUM,
            NULL AS valtype_cd,
            NULL AS location_cd,
            NULL AS tval_char,
            NULL AS nval_num,
            NULL AS valueflag_cd,
            NULL AS units_cd,
            NULL CONFIDENCE_NUM, 
            NULL SOURCESYSTEM_CD, 
            NULL UPDATE_DATE, 
            NULL DOWNLOAD_DATE, 
            NULL IMPORT_DATE, 
            NULL UPLOAD_ID,
   			drug_source_concept_id AS SOURCE_CONCEPT_ID,
            drug_source_value AS SOURCE_VALUE,
            'DRUG' AS DOMAIN_ID
--			drug_exposure_start_datetime TIMESTAMP NULL, 
--			drug_exposure_end_datetime TIMESTAMP NULL, 
--			verbatim_end_date date NULL, 
--			drug_type_concept_id integer NOT NULL, 
--			stop_reason varchar(20) NULL, 
--			refills integer NULL, 
--			quantity float NULL, 
--			days_supply integer NULL, 
--			sig CLOB NULL, 
--			route_concept_id integer NULL, 
--			lot_number varchar(50) NULL, 
--			visit_detail_id integer NULL, 
--			route_source_value varchar(50) NULL, 
--			dose_unit_source_value varchar(50) NULL );  
FROM DRUG_EXPOSURE;

CREATE  VIEW DEVICE_VIEW AS 
SELECT 
			visit_occurrence_id AS ENCOUNTER_NUM, 
 			PERSON_ID AS PATIENT_NUM, 
   			CAST(device_exposure_id AS VARCHAR(50)) AS CONCEPT_CD, 
   			CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
   			device_exposure_start_datetime AS START_DATE, 
			device_exposure_end_datetime AS END_DATE, 
            device_type_concept_id AS MODIFIER_CD,
            NULL AS INSTANCE_NUM,
            NULL AS valtype_cd,
            NULL AS location_cd,
            NULL AS tval_char,
            NULL AS nval_num,
            NULL AS valueflag_cd,
            NULL AS units_cd,
            NULL CONFIDENCE_NUM, 
            NULL SOURCESYSTEM_CD, 
            NULL UPDATE_DATE, 
            NULL DOWNLOAD_DATE, 
            NULL IMPORT_DATE, 
            NULL UPLOAD_ID,
   			DEVICE_SOURCE_CONCEPT_ID AS SOURCE_CONCEPT_ID, --device_concept_id??
            device_source_value AS SOURCE_VALUE,
            'DEVICE' AS DOMAIN_ID
--			device_exposure_start_datetime TIMESTAMP NULL, 
--			device_exposure_end_datetime TIMESTAMP NULL, 
--			unique_device_id varchar(50) NULL, 
--			quantity integer NULL, 
--			visit_detail_id integer NULL, 
FROM DEVICE_EXPOSURE;

-- Replace the default i2b2 OMOP scripts with these OBSERVATION_VIEW AND MEASUREMENT_VIEW
-- These add value_concept_id to the view in the valueflag_cd field
-- This will allow valueflag_cd to be harmonized.
-- This enables the ACT COVID POSITIVE/NEGATIVE/PENDING/EQUIVOCAL codes to be
-- harmonized
--SELECT * FROM OBSERVATION_VIEW;
CREATE  VIEW OBSERVATION_VIEW AS
SELECT
	PERSON_ID AS PATIENT_NUM,
    CAST(OBSERVATION_CONCEPT_ID AS VARCHAR(50)) AS CONCEPT_CD, 
	VISIT_OCCURRENCE_ID AS ENCOUNTER_NUM,
	1 as INSTANCE_NUM,
    CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
	OBSERVATION_DATE AS START_DATE,
    NULL AS END_DATE,
	'@' AS MODIFIER_CD,
	NULL AS LOCATION_CD,
    CASE 
       WHEN VALUE_AS_NUMBER IS NOT NULL 
       THEN 'N' 
       ELSE 'T' 
    END AS valtype_cd, --DECODE THIS IS THE FUTURE operator_concept_id
    CASE 
        WHEN VALUE_AS_NUMBER IS NOT NULL THEN 'E' 
        ELSE VALUE_AS_STRING 
        END AS TVAL_CHAR,
    VALUE_AS_NUMBER AS NVAL_NUM,
    CAST(VALUE_AS_CONCEPT_ID AS VARCHAR(50)) AS VALUEFLAG_CD,
    UNIT_SOURCE_VALUE AS UNITS_CD,
    NULL CONFIDENCE_NUM, 
            NULL SOURCESYSTEM_CD, 
            NULL UPDATE_DATE, 
            NULL DOWNLOAD_DATE, 
            NULL IMPORT_DATE, 
            NULL UPLOAD_ID,
    observation_SOURCE_concept_id AS SOURCE_CONCEPT_ID, 
    observation_source_value AS SOURCE_VALUE,
    'OBSERVATION' AS DOMAIN_ID
FROM
	OBSERVATION;

--SELECT * FROM MEASUREMENT_VIEW;
  CREATE  VIEW MEASUREMENT_VIEW as
  SELECT
	PERSON_ID PATIENT_NUM,
	CAST(MEASUREMENT_CONCEPT_ID AS VARCHAR(50)) CONCEPT_CD,
	VISIT_OCCURRENCE_ID ENCOUNTER_NUM,
	CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
	MEASUREMENT_DATE AS START_DATE,
    NULL AS end_DATE,
	'@' AS MODIFIER_CD,
	1 INSTANCE_NUM,
    NULL AS LOCATION_CD,
	CASE 
		WHEN VALUE_AS_NUMBER IS NOT NULL 
		THEN 'N' 
		ELSE 'T' 
	END AS VALTYPE_CD,
	CASE 
		WHEN OPERATOR_CONCEPT_ID = 4172703 
		THEN 'E' 
		WHEN OPERATOR_CONCEPT_ID = 4171756 
		THEN 'LT' 
		WHEN OPERATOR_CONCEPT_ID = 4172704 
		THEN 'GT' 
		WHEN OPERATOR_CONCEPT_ID = 4171754 
		THEN 'LE' 
		WHEN OPERATOR_CONCEPT_ID = 4171755 
		THEN 'GE' 
		WHEN OPERATOR_CONCEPT_ID IS NULL 
		THEN 'E' 
		ELSE NULL 
	END AS TVAL_CHAR ,
	VALUE_AS_NUMBER AS NVAL_NUM,
   	CAST(VALUE_AS_CONCEPT_ID AS VARCHAR(50)) AS VALUEFLAG_CD,
    UNIT_SOURCE_VALUE AS UNITS_CD, 
    NULL CONFIDENCE_NUM, 
    NULL SOURCESYSTEM_CD, 
    NULL UPDATE_DATE, 
    NULL DOWNLOAD_DATE, 
    NULL IMPORT_DATE, 
    NULL UPLOAD_ID,
	measurement_source_concept_id AS SOURCE_CONCEPT_ID, 
    measurement_source_value AS SOURCE_VALUE,
    'MEASUREMENT' AS DOMAIN_ID
FROM
	MEASUREMENT;

--SELECT * FROM COVID_LAB_VIEW;
CREATE  FORCE EDITIONABLE VIEW COVID_LAB_VIEW 
(PATIENT_NUM, CONCEPT_CD, ENCOUNTER_NUM, INSTANCE_NUM, PROVIDER_ID, START_DATE, MODIFIER_CD, 
OBSERVATION_BLOB, VALTYPE_CD, TVAL_CHAR, 
NVAL_NUM, VALUEFLAG_CD, QUANTITY_NUM, UNITS_CD, 
END_DATE, LOCATION_CD, CONFIDENCE_NUM, SOURCESYSTEM_CD, UPDATE_DATE, DOWNLOAD_DATE, IMPORT_DATE, UPLOAD_ID, STANDARD_CONCEPT_ID, SOURCE_VALUE, DOMAIN_ID) as
SELECT
 			PERSON_ID AS PATIENT_NUM, 
   			CAST(measurement_source_concept_id AS VARCHAR(25)) || ' ' || CAST(VALUE_AS_CONCEPT_ID AS VARCHAR(24)) AS CONCEPT_CD,
            visit_occurrence_id AS ENCOUNTER_NUM, 
            1 AS INSTANCE_NUM,
   			CAST(provider_id AS VARCHAR(50)) AS PROVIDER_ID, 
   			measurement_datetime AS START_DATE,
            '@' AS MODIFIER_CD, --measurement_type_concept_id
            NULL AS OBSERVATION_BLOB,
            CASE 
               WHEN VALUE_AS_NUMBER IS NOT NULL 
               THEN 'N' 
               ELSE 'T' 
            END AS valtype_cd, --DECODE THIS IS THE FUTURE operator_concept_id
            CASE 
                WHEN OPERATOR_CONCEPT_ID = 4172703 THEN 'E' 
                WHEN OPERATOR_CONCEPT_ID = 4171756 THEN 'LT' 
                WHEN OPERATOR_CONCEPT_ID = 4172704 THEN 'GT' 
                WHEN OPERATOR_CONCEPT_ID = 4171754 THEN 'LE' 
                WHEN OPERATOR_CONCEPT_ID = 4171755 THEN 'GE' 
                WHEN OPERATOR_CONCEPT_ID IS NULL AND VALUE_AS_NUMBER IS NOT NULL THEN 'E' 
                ELSE VALUE_SOURCE_VALUE 
            END AS TVAL_CHAR,
            VALUE_AS_NUMBER AS NVAL_NUM,
           	CAST(VALUE_AS_CONCEPT_ID AS VARCHAR(50)) AS VALUEFLAG_CD,
            NULL AS QUANTITY_NUM,
            UNIT_SOURCE_VALUE AS UNITS_CD, -- DECODE THIS TO QUERY BY VALUE unit_concept_id IN THE FUTURE FOR NOW JUST USE THE UNIT SOURCE VALUE
            NULL END_DATE, 
            NULL LOCATION_CD, 
            NULL CONFIDENCE_NUM, 
            NULL SOURCESYSTEM_CD, 
            NULL UPDATE_DATE, 
            NULL DOWNLOAD_DATE, 
            NULL IMPORT_DATE, 
            NULL UPLOAD_ID,
           	measurement_concept_id AS STANDARD_CONCEPT_ID, 
            measurement_source_value AS SOURCE_VALUE,
            'MEASUREMENT' AS DOMAIN_ID  
FROM MEASUREMENT 
WHERE MEASUREMENT_SOURCE_CONCEPT_ID IN (586515,586516,586517,586518,586519,586520,586521,586522,586523,586524,586525,586526,
586527,586528,586529,706154,706155,706156,706157,706159,706160,706161,706163,706165,706166,706167,706168,706170,706171,706172,
706173,706174,706175,706177,706178,706180,706181,715260,715261,715262,715272,723459,723463,723464,723465,723466,723467,723468,
723469,723470,723471,723472,723473,723474,723475,723476,723477,723478,723479,723480,757677,757678,757679,757680,757685,757686,
36659631,36661369,36661370,36661371,36661372,36661373,36661374,36661375,36661377,36661378) ;
commit;

-- PATIENT_DIMENSION
--rename patient_dimension to patient_dimension_table;
--rename visit_dimension to visit_dimension_table;
commit;

CREATE  VIEW PATIENT_DIMENSION
	(
		PATIENT_NUM,
		VITAL_STATUS_CD,
		BIRTH_DATE,
		DEATH_DATE,
		SEX_CD,
		AGE_IN_YEARS_NUM,
		LANGUAGE_CD,
		RACE_CD,
		MARITAL_STATUS_CD,
		RELIGION_CD,
		ZIP_CD,
		STATECITYZIP_PATH,
		INCOME_CD,
		PATIENT_BLOB,
		UPDATE_DATE,
		DOWNLOAD_DATE,
		IMPORT_DATE,
		SOURCESYSTEM_CD,
		UPLOAD_ID,
		ETHNICITY_CD 
	)
	AS 
SELECT
	PERSON_ID ,
	CASE 
    WHEN DEATH_DATETIME IS NULL THEN '0'
    ELSE '45885033' 
    END,
	TO_DATE(CONCAT(CONCAT(CONCAT(CONCAT(YEAR_OF_BIRTH, '/'), MONTH_OF_BIRTH) , 
	'/') ,DAY_OF_BIRTH), 'YYYY/MM/DD'),
	CAST(DEATH_DATETIME AS DATE),
	TO_CHAR(GENDER_CONCEPT_ID),
	TO_NUMBER(NULL),
	NULL,
	TO_CHAR(RACE_CONCEPT_ID),
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	CAST(NULL AS DATE),
	CAST(NULL AS DATE),
	CAST(NULL AS DATE),
	NULL,
	TO_NUMBER(NULL),
	TO_CHAR(ETHNICITY_CONCEPT_ID) 
FROM
	PERSON;


-- VISIT_DIMENSION

CREATE  VIEW VISIT_DIMENSION
	(
		ENCOUNTER_NUM,
		PATIENT_NUM,
		ACTIVE_STATUS_CD,
		START_DATE,
		END_DATE,
		INOUT_CD,
		LOCATION_CD,
		LOCATION_PATH,
		LENGTH_OF_STAY,
		VISIT_BLOB,
		UPDATE_DATE,
		DOWNLOAD_DATE,
		IMPORT_DATE,
		SOURCESYSTEM_CD,
		UPLOAD_ID 
	)
	AS 
SELECT
	VISIT_OCCURRENCE_ID,
	PERSON_ID,
	NULL,
	VISIT_START_DATE,
	VISIT_END_DATE,
	VISIT_CONCEPT_ID,
	CARE_SITE_ID,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL 
FROM
	VISIT_OCCURRENCE;
commit;

--REPLACE I2B2/OMOP VIEWS
SELECT TOP (10) FROM CONDITION_VIEW ;
SELECT TOP (10) FROM PROCEDURE_VIEW ;
SELECT TOP (10) FROM DEVICE_VIEW ;
SELECT TOP (10) FROM MEASUREMENT_VIEW ;
SELECT TOP (10) FROM OBSERVATION_VIEW ;
--ADD GENERIC I2B2/OMOP_VIEW
SELECT TOP (10) FROM DRUG_VIEW ;
--ADD ACT SPECIFIC VIEWS
SELECT TOP (10) FROM COVID_LAB_VIEW ;
SELECT TOP (10) FROM ALL_SOURCE_CONCEPTS ;
select TOP (10) from COVID_LAB_VIEW ;

select TOP (10) from patient_dimension ;
select TOP (10) from visit_dimension ;




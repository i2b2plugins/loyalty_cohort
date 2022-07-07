--------------------------------------------------------
--  File created - Thursday-January-13-2022   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for View ALL_SOURCE_CONCEPTS_OBS
--------------------------------------------------------

  CREATE OR REPLACE FORCE EDITIONABLE VIEW "NCATSTEST_CRCDATA"."ALL_SOURCE_CONCEPTS_OBS" ("ENCOUNTER_NUM", "PATIENT_NUM", "CONCEPT_CD", "PROVIDER_ID", "START_DATE", "END_DATE", "MODIFIER_CD", "INSTANCE_NUM", "VALTYPE_CD", "LOCATION_CD", "TVAL_CHAR", "NVAL_NUM", "VALUEFLAG_CD", "UNITS_CD", "STANDARD_CONCEPT_ID", "SOURCE_VALUE", "DOMAIN_ID") AS 
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
)
;

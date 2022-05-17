--------------------------------------------------------
--  File created - Thursday-January-13-2022   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for View ALL_SOURCE_CONCEPTS_PROC
--------------------------------------------------------

  CREATE OR REPLACE FORCE EDITIONABLE VIEW "NCATSTEST_CRCDATA"."ALL_SOURCE_CONCEPTS_PROC" ("ENCOUNTER_NUM", "PATIENT_NUM", "CONCEPT_CD", "PROVIDER_ID", "START_DATE", "END_DATE", "MODIFIER_CD", "INSTANCE_NUM", "VALTYPE_CD", "LOCATION_CD", "TVAL_CHAR", "NVAL_NUM", "VALUEFLAG_CD", "UNITS_CD", "STANDARD_CONCEPT_ID", "SOURCE_VALUE", "DOMAIN_ID") AS 
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
FROM PROCEDURE_OCCURRENCE)
;

--------------------------------------------------------
--  File created - Thursday-January-13-2022   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for View ALL_SOURCE_CONCEPTS_DEVICE
--------------------------------------------------------

  CREATE OR REPLACE FORCE EDITIONABLE VIEW "NCATSTEST_CRCDATA"."ALL_SOURCE_CONCEPTS_DEVICE" ("ENCOUNTER_NUM", "PATIENT_NUM", "CONCEPT_CD", "PROVIDER_ID", "START_DATE", "END_DATE", "MODIFIER_CD", "INSTANCE_NUM", "VALTYPE_CD", "LOCATION_CD", "TVAL_CHAR", "NVAL_NUM", "VALUEFLAG_CD", "UNITS_CD", "STANDARD_CONCEPT_ID", "SOURCE_VALUE", "DOMAIN_ID") AS 
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
FROM DEVICE_EXPOSURE)
;

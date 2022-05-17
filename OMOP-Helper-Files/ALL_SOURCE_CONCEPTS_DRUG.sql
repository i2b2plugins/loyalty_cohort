--------------------------------------------------------
--  File created - Thursday-January-13-2022   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for View ALL_SOURCE_CONCEPTS_DRUG
--------------------------------------------------------

  CREATE OR REPLACE FORCE EDITIONABLE VIEW "NCATSTEST_CRCDATA"."ALL_SOURCE_CONCEPTS_DRUG" ("ENCOUNTER_NUM", "PATIENT_NUM", "CONCEPT_CD", "PROVIDER_ID", "START_DATE", "END_DATE", "MODIFIER_CD", "INSTANCE_NUM", "VALTYPE_CD", "LOCATION_CD", "TVAL_CHAR", "NVAL_NUM", "VALUEFLAG_CD", "UNITS_CD", "STANDARD_CONCEPT_ID", "SOURCE_VALUE", "DOMAIN_ID") AS 
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
FROM ( SELECT 
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
FROM DRUG_EXPOSURE)
;

/****** Object:  StoredProcedure [dbo].[usp_LoyaltyCohort]    Script Date: 4/14/2021 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

if object_id('usp_LoyaltyCohort') is not null drop proc usp_LoyaltyCohort
GO

CREATE PROC [dbo].[usp_LoyaltyCohort] (
    
    @indexDate datetime

			)
AS

SET NOCOUNT ON
SET XACT_ABORT ON

/*
Implements the loyalty cohort algorithm defined in 
  "External Validation of an Algorithm to Identify Patients with High Data-Completeness in Electronic Health Records for Comparative Effectiveness Research" by Lin et al.

Written primarily by Andrew Cagan with contributions from: Jeff Klann, PhD; Barbara Benoit

Calculating 20 variables over the baseline period, attempting to predict the # of subjects who will most likely present for future follow-up

This script accepts an index_date and looks back 365 days previous to that date (baseline period). For consistency across sites, let us all use the index date of 2/1/2020

To run, exec usp_LoyaltyCohort @indexDate <---- Insert date here
        e.g., exec usp_LoyaltyCohort '2/01/2020'

This will create two tables on your db, loyalty_dev and loyalty_dev_summary

It is ok under the SHRINE IRB to export this: select * from loyalty_dev_summary where Summary_Decsription='PercentOfSubjects'
This is the output at the end of the script or you can run it manually. It is percentages, a predictive score, and an obfuscated count of total patients.

***** Standard i2b2 table naming conventions are used - Observation_fact, concept_dimension, patient_dimension.
***** Table names will need to be changed appropriately if using different naming conventions

***** The table 'XREF_LoyaltyCode_Paths' contains the paths for the concepts used in this script and is required in order to run.

***** AC - added datetime for raiserror
		 - removed  repeating  ‘convert’ on the index date throughout the procedure, so now only performing it once at the beginning of the script when setting the indexdate 
		 - no need to remove timestamps throughout the script using 'CONVERT', this was slowing things down.
		 - the UPDATE CASE for the provider count variables was using an 'In' which could cause a larger data set to perform the update slowly, changed to 2 different join statements instead
		 - Update to perform procedure code over already retrieved baseline period instead of going against full fact table
	 JGK - added code to calculate summary stats and cutoff for Over 65 and Under 65

*/

IF (@indexDate is not null and isdate(@indexDate) = 1 ) 


    BEGIN
		
		SET @indexDate = CONVERT(date,@indexDate)

		DECLARE @MessageText varchar(65)
		Declare @MessageCnt smallint
		SET @MessageCnt = 0


        --Create master temp table
		if object_id('tempdb..#cohort') is not null drop table #cohort
			
			CREATE TABLE #cohort (
			patient_num INT NOT NULL PRIMARY KEY,
			age int null,
			Num_Dx1 bit not null DEFAULT 0,
			Num_Dx2 bit not null DEFAULT 0,
			MedUse1 bit not null DEFAULT 0,
			MedUse2 bit not null DEFAULT 0,
			Mammography bit not null DEFAULT 0,
			PapTest bit not null DEFAULT 0,
			PSATest bit not null DEFAULT 0,
			Colonoscopy bit not null DEFAULT 0,
            FecalOccultTest bit not null DEFAULT 0,
			FluShot bit not null DEFAULT 0,
			PneumococcalVaccine bit not null DEFAULT 0,
			BMI bit not null DEFAULT 0,
			A1C bit not null DEFAULT 0,
			MedicalExam bit not null DEFAULT 0,
			INP1_OPT1_Visit bit not null DEFAULT 0,
			OPT2_Visit bit not null DEFAULT 0,
			ED_Visit bit not null DEFAULT 0,
			MDVisit_pname2 bit not null DEFAULT 0,
			MDVisit_pname3 bit not null DEFAULT 0,
			Routine_Care_2 bit not null DEFAULT 0,
			Predicted_score FLOAT not null DEFAULT 0
				)
			
	        -- Change 4/15: Josh's paper limits to patients with at least one encounter during the entire 7 year study period, so we limit to patient with an encounter (ever)
			INSERT INTO #Cohort (patient_num,age)
			select distinct p.patient_num,datediff(YEAR,BIRTH_DATE,@indexDate) age  from patient_dimension p -- (Note that age could be off by one)
			 inner join visit_dimension v on v.patient_num=p.patient_num

			 --Primary key in Create statement above creates  a clusterd index so not sure if index below is needed-AC
			 create index cohort_pnum on #cohort(patient_num); -- jgk add an index on cohort


set @MessageText = cast(@MessageCnt as varchar) + ' ' + CONVERT(CHAR(20),  GETDATE(), 120)
RAISERROR(@MessageText,0,1) WITH NOWAIT;

-----------------------------------------------------------------------
-----1. Get all facts for loyalty cohort diagnosis codes for baseline year
-----------------------------------------------------------------------

if object_id('tempdb..#DX_baseline_FULL') is not null drop table #DX_baseline_FULL
	
	;with n as (			
	Select distinct concept_cd
	from [dbo].[ACT_ICD10CM_DX_2018AA] d, concept_dimension c
	where d.C_FULLNAME = C.CONCEPT_PATH
	and (c_basecode is not null and c_basecode <> '')
			
		UNION
	
	Select distinct concept_cd 
	from [dbo].[ACT_ICD9CM_DX_2018AA] d, concept_dimension c
	where d.C_FULLNAME = C.CONCEPT_PATH
	and (c_basecode is not null and c_basecode <> '')

		UNION

	Select distinct c.concept_cd												-----
	from [dbo].[i2b2metadata] d, concept_dimension c, xref_LoyaltyCode_paths x  -----
	where d.C_FULLNAME = C.CONCEPT_PATH and										-----
			C.Concept_path = x.act_path											----- > This block of code handles any local dx codes
	and (d.c_basecode is not null and d.c_basecode <> '')						-----
	and x.SiteSpecificCode is not null											-----
	and x.[code type] = 'DX'		
	)	

    ----a. Get count of any diagnosis for the baseline period
	Select o.patient_num, count(distinct(convert(date,o.start_date))) as Count
	Into #DX_baseline_FULL
	From observation_fact o, n 
	Where o.CONCEPT_CD = n.CONCEPT_CD
		AND o.START_DATE >=  dateadd(dd,-365, @indexDate)
		AND o.START_DATE < @indexDate	
	group by patient_num
	
		---------------------------------
	--DX1 	--Subjects with at least one dx code
	--DX2	--Subjcts with 2 or more dx codes
	
	Update #cohort
	set Num_Dx1 = 1,
		Num_Dx2  = Case when d.count>=2 then 1 else 0 end
	from #cohort c, #dx_baseline_full d
	where c.patient_num = d.PATIENT_NUM


	---b. Get Feature DX concepts for site using ACT concept_path in xref table
	if object_id('tempdb..#DX_params') is not null drop table #DX_params

	select distinct Feature_name, concept_cd, 'DX' as CodeType --[ACT_PATH], 
	into #DX_params
	from [dbo].[xref_LoyaltyCode_paths] L, concept_dimension c
	where C.CONCEPT_PATH like L.Act_path+'%'  --jgk: must support local children
	AND [code type] = 'DX'
	and (act_path <> '**Not Found' and act_path is not null)
	

	CREATE CLUSTERED INDEX ndx_DX_param ON #DX_params ([concept_cd]);


	if object_id('tempdb..#DX_baseline') is not null drop table #DX_baseline

	select o.patient_num,  o.start_date as DX_Date, p.Feature_name
	into #DX_baseline
	from observation_fact o, #DX_params p
	where o.Concept_cd = p.CONCEPT_CD
		AND o.START_DATE >=  dateadd(dd,-365, @indexDate)
		AND o.START_DATE < @indexDate
   
Set @MessageCnt = @MessageCnt + 1 
set @MessageText = cast(@MessageCnt as varchar) + ' ' + CONVERT(CHAR(20),  GETDATE(), 120)
RAISERROR(@MessageText,0,1) WITH NOWAIT;

	-----------------------------------------------------------------------
	-----2. Procedure facts for loyalty cohort baseline year
	-----------------------------------------------------------------------
	if object_id('tempdb..#PX_params') is not null drop table #PX_params

	-- a.  Get concepts using act concept_path in xref table
	select Distinct Feature_name, concept_cd, 'PX' as CodeType--[ACT_PATH], 
	into #PX_params
	from [dbo].[xref_LoyaltyCode_paths] L, concept_dimension c
	where  C.CONCEPT_PATH like L.Act_path+'%' -- jgk
	AND [code type] = 'PX'
	and (act_path <> '**Not Found' and act_path is not null)
	
	
	CREATE CLUSTERED INDEX ndx_PX_param ON #PX_params ([concept_cd]);


	-- b. get date for fact table

	if object_id('tempdb..#PX_baseline') is not null drop table #PX_baseline
	select o.patient_num,  convert(date,o.start_date) as PX_Date, p.Feature_name,o.concept_cd, o.PROVIDER_ID
	into #PX_baseline
	from observation_fact o, #PX_params p
	where o.CONCEPT_CD = p.CONCEPT_CD
		AND o.START_DATE >=  dateadd(dd,-365, @indexDate)
		AND o.START_DATE < @indexDate

	CREATE CLUSTERED INDEX ndx_PX_bl ON #PX_baseline (patient_num, concept_cd, provider_id );

Set @MessageCnt = @MessageCnt + 1 
set @MessageText = cast(@MessageCnt as varchar) + ' ' + CONVERT(CHAR(20),  GETDATE(), 120)
RAISERROR(@MessageText,0,1) WITH NOWAIT;

	-----------------------------------------------------------------------
	-----3. Lab facts for loyalty cohort baseline year
	-----------------------------------------------------------------------
	if object_id('tempdb..#Lab_params') is not null drop table #Lab_params
	-- a. Get concepts using act concept_path in xref table
	select distinct Feature_name, concept_cd, 'Lab' as CodeType --[ACT_PATH], 
	into #Lab_params
	from [dbo].[xref_LoyaltyCode_paths] L, concept_dimension c
	where  C.CONCEPT_PATH like L.Act_path+'%' -- jgk
	AND [code type] = 'lab'
	and (act_path <> '**Not Found' and act_path is not null)
	

	CREATE CLUSTERED INDEX ndx_lab_param ON #Lab_params ([concept_cd]);


	-- b. get date for fact table

	select o.patient_num,  convert(date,o.start_date) as Lab_Date, p.Feature_name
	into #lab_baseline
	from observation_fact o, #Lab_params p
	where o.CONCEPT_CD = p.CONCEPT_CD
		AND o.START_DATE >=  dateadd(dd,-365, @indexDate)
		AND o.START_DATE < @indexDate


Set @MessageCnt = @MessageCnt + 1 
set @MessageText = cast(@MessageCnt as varchar) + ' ' + CONVERT(CHAR(20),  GETDATE(), 120)
RAISERROR(@MessageText,0,1) WITH NOWAIT;

	-----------------------------------------------------------------------
	-----4. Medication facts for loyalty cohort baseline year
	-----------------------------------------------------------------------

	---get Medications for time period
	--- ** there are 2 ACT Medication metadata tables,  Barb suggests to use both
	if object_id('tempdb..#MedLookup') is not null drop table #MedLookup

	;with MedCodes as (			
	Select  distinct c_basecode 
	from ACT_MED_VA_V2_092818
	where c_basecode is not null and c_basecode  <> ''
							UNION								
	select  distinct c_basecode from ACT_MED_ALPHA_V2_121318
	where c_basecode is not null and c_basecode  <> ''
	)

	Update #cohort
	Set MedUse1 = 1,
		MedUse2 = CASE WHEN X.Counts >=2 THEN 1 ELSE 0 END
		from #cohort c, 
						(						
							Select o.patient_num, count(distinct(convert(date,o.start_date))) as Counts 
							From observation_fact o, MedCodes M
							Where o.CONCEPT_CD = M.C_BASECODE
									AND o.START_DATE >=  dateadd(dd,-365, @indexDate)
									AND o.START_DATE < @indexDate
							group by patient_num
							)  X
	where c.patient_num = X.PATIENT_NUM

Set @MessageCnt = @MessageCnt + 1 
set @MessageText = cast(@MessageCnt as varchar) + ' ' + CONVERT(CHAR(20),  GETDATE(), 120)
RAISERROR(@MessageText,0,1) WITH NOWAIT;

	--Subjects with at least two outpatient encounters
	if object_id('tempdb..#visit_outpatient') is not null drop table #visit_outpatient

	select patient_num , count(distinct convert(date, start_date)) as cnt  --count(distinct encounter_num) as cnt 
	into #visit_outpatient
	from visit_dimension 
	where (START_DATE >=  dateadd(dd,-365, @indexDate)
			AND START_DATE < @indexDate
			)
	AND 	[INOUT_CD] in (select distinct c_basecode
							from [dbo].[NCATS_VISIT_DETAILS] N,
							
									(select distinct act_path 
									from [dbo].[xref_LoyaltyCode_paths]
									where [code type] = 'visit' and feature_name = 'outpatient encounter'
									and act_path is not null) X
							where X.ACT_PATH like N.C_FULLNAME+'%' -- jgk
							)
	Group by patient_num

	--ED Encounter
	if object_id('tempdb..#visit_ED') is not null drop table #visit_ED

	select patient_num , count(distinct convert(date, start_date)) as cnt  --count(distinct encounter_num) as cnt 
	into #visit_ED
	from visit_dimension 
	where (	START_DATE >=  dateadd(dd,-365, @indexDate)
			AND START_DATE < @indexDate
			)
	AND 	[INOUT_CD] in (select distinct c_basecode
							from [dbo].[NCATS_VISIT_DETAILS] N,
							
									(select distinct act_path 
									from [dbo].[xref_LoyaltyCode_paths]
									where [code type] = 'visit' and feature_name = 'ED encounter'
									and act_path is not null) X
							where X.ACT_PATH like N.C_FULLNAME+'%' -- jgk
							)
	Group by patient_num

	--Inpatient_encounter
	if object_id('tempdb..#visit_inpatient') is not null drop table #visit_inpatient

	select patient_num , count(distinct encounter_num) as cnt --count(distinct convert(date, start_date)) as cnt
	into #visit_inpatient
	from visit_dimension 
	where ( START_DATE >=  dateadd(dd,-365, @indexDate)
			AND START_DATE < @indexDate
			)
	AND 	[INOUT_CD] in (select distinct c_basecode
							from [dbo].[NCATS_VISIT_DETAILS] N,
							
									(select distinct act_path 
									from [dbo].[xref_LoyaltyCode_paths]
									where [code type] = 'visit' and feature_name = 'inpatient encounter'
									and act_path is not null) X
							where X.ACT_PATH like N.C_FULLNAME+'%' -- jgk
							)
	Group by patient_num

	UPDATE #cohort
	SET INP1_OPT1_Visit = CASE WHEN patient_num in (select patient_num from #visit_inpatient) 
								OR patient_num in (select patient_num from #visit_outpatient) THEN 1 ELSE 0 END,
		OPT2_Visit = CASE WHEN patient_num in (select patient_num from #visit_outpatient 
												where cnt >= 2) THEN 1 ELSE 0 END,
		ED_Visit = CASE WHEN patient_num  in (select patient_num from #visit_ED) THEN 1 ELSE 0 END

Set @MessageCnt = @MessageCnt + 1 
set @MessageText = cast(@MessageCnt as varchar) + ' ' + CONVERT(CHAR(20),  GETDATE(), 120)
RAISERROR(@MessageText,0,1) WITH NOWAIT;
	----------------------------------------------------------------
	---MD VISIT / PROV NAME

	--******* This variable may need to be customized per site depending on whether *********
	--******* the site populates the provider_id field in the Observation_fact table ********

	-- get counts of providers by patient (only count 1 provider per day)
	-- remove unknown provider '@', null, and ''


----4/6/2020
----Update to perform code over already retrieved baseline period instead of going against full fact table
	
	---original code 

	--select  patient_num,   PROVIDER_ID , count(distinct convert(date, start_date)) as cnt 
	--into #ProviderCount
	--from observation_fact O, (Select concept_cd 
	--							From #px_params -- jgk isn't this only pts with a procedure code?
	--							Where feature_name =  'MD visit') X					
	--where O.CONCEPT_CD = X.CONCEPT_CD
	--		AND (convert(date, START_DATE) >=  dateadd(dd,-365,convert(date,@indexDate))
	--		AND convert(date, START_DATE) <= dateadd(dd,-1,convert(date,@indexDate))
	--		)
	--		AND (O.PROVIDER_ID is not null and O.provider_id <> '' and O.provider_id <> '@')
	--group by patient_num, provider_id

if object_id('tempdb..#ProviderCount') is not null drop table #ProviderCount
;With MDVISIT as (
	Select concept_cd 
	From #px_params 
	Where feature_name =  'MD visit'
)
	select  patient_num,   PROVIDER_ID , count(distinct PX_Date) as cnt 
	into #ProviderCount
	from #PX_baseline O, 	MDVISIT				
	where O.CONCEPT_CD = MDVISIT.CONCEPT_CD		
	AND (O.PROVIDER_ID is not null and O.provider_id <> '' and O.provider_id <> '@')
	group by patient_num, provider_id

------AC : I think this will run a little faster than the previous 'case' , 'In' statement
	Update #cohort
	Set MDVisit_pname2 = 1
	from #cohort c, (   select  patient_num
						from #providercount
						 where cnt = 2) Prov2
	where c.patient_num = Prov2.patient_num
	
								
	Update #cohort
	Set MDVisit_pname3 = 1
	from #cohort c, (	select  patient_num
						from #providercount
						where cnt > 2) Prov3
	where c.patient_num = Prov3.patient_num
	
set @MessageText = 'MDVisit ' + CONVERT(CHAR(20),  GETDATE(), 120)
RAISERROR(@MessageText,0,1) WITH NOWAIT;

	--Set variables based on DX codes during baseline period 
	--Mammography composed of both proc and dx codes

	UPDATE #cohort
	SET Mammography= case when patient_num in (select patient_num from #DX_baseline where feature_name = 'Mammography') then 1 else 0 end,
		BMI = case when patient_num in (select patient_num from #DX_baseline where feature_name = 'BMI') then 1 else 0 end,
		FluShot = case when patient_num in (select patient_num from #DX_baseline where feature_name = 'Flu Shot') then 1 else 0 end,
		PneumococcalVaccine = case when patient_num in (select patient_num from #DX_baseline where feature_name = 'Pneumococcal vaccine') then 1 else 0 end,
		MedicalExam = case when patient_num in (select patient_num from #DX_baseline where feature_name = 'Medical Exam') then 1 else 0 end

	--Set variables based on Procedure codes during baseline period 
	UPDATE #cohort
	SET Mammography = case when patient_num in (select patient_num from #PX_baseline where feature_name = 'Mammography') then 1 else 0 end,
		FecalOccultTest = case when patient_num in (select patient_num from #PX_baseline where feature_name = 'Fecal occult blood test') then 1 else 0 end,
		FluShot = case when patient_num in (select patient_num from #PX_baseline where feature_name = 'Flu Shot') then 1 else 0 end,
		PneumococcalVaccine = case when patient_num in (select patient_num from #PX_baseline where feature_name = 'Pneumococcal vaccine') then 1 else 0 end,
		A1C = case when patient_num in (select patient_num from #PX_baseline where feature_name = 'A1C') then 1 else 0 end,
		Paptest = case when patient_num in (select patient_num from #PX_baseline where feature_name = 'Pap test') then 1 else 0 end,
		Colonoscopy = case when patient_num in (select patient_num from #PX_baseline where feature_name = 'Colonoscopy') then 1 else 0 end,
		PSATest = case when patient_num in (select patient_num from #PX_baseline where feature_name = 'PSA Test') then 1 else 0 end

	--A1C composed of both procedure and lab codes
	-- jgk: this needs to be AFTER the other A1C set
	Update #cohort
	Set A1C = 1
	from #cohort c, #lab_baseline p 
	where c.patient_num = p.PATIENT_NUM
	and  p.Feature_name = 'A1C'

set @MessageText = 'vars ' + CONVERT(CHAR(20),  GETDATE(), 120)
RAISERROR(@MessageText,0,1) WITH NOWAIT;

	-- set routine care bit 
	-- based on the sum of at least 2 routine care varaibales being set during the baseline period

	 UPDATE #cohort
	 set Routine_Care_2 = case when
			(cast(MedicalExam as int) + cast(Mammography as int) + cast(PSATest as int) + cast(colonoscopy as int) + cast(FecalOccultTest as int) + cast(fluShot as int)
			+ cast(PneumococcalVaccine as int) + cast(A1C as int) + cast(BMI as int) ) >=2 THEN 1 ELSE 0 END
		
	--------Perform predictive score


UPDATE #cohort
SET Predicted_score = PS.Predicted_score
FROM #cohort C,
(
SELECT PATIENT_NUM, -0.010+(p.MDVisit_pname2*CAST(c.MDVisit_pname2 AS INT))+(p.MDVisit_pname3*CAST(c.MDVisit_pname3 AS INT))+(p.MedicalExam*CAST(C.MedicalExam AS INT))
  +(p.Mammography*CAST(c.Mammography AS INT))+(p.PapTest*CAST(c.PapTest as INT))+(p.PSATest*CAST(c.PSATest AS INT))+(p.Colonoscopy*CAST(c.Colonoscopy AS INT))
  +(p.FecalOccultTest*CAST(c.FecalOccultTest AS INT))+(p.FluShot*CAST(c.FluShot AS INT))+(p.PneumococcalVaccine*CAST(c.PneumococcalVaccine AS INT))
  +(p.BMI*CAST(c.BMI AS INT))+(p.A1C*CAST(c.A1C as INT))+(p.MedUse1*CAST(c.MedUse1 AS INT))+(p.MedUse2*CAST(c.MedUse2 AS INT))+(p.INP1_OPT1_Visit*CAST(c.INP1_OPT1_Visit AS INT))
  +(p.OPT2_Visit*CAST(c.OPT2_Visit AS INT))+(p.INP1_OPT1_Visit*CAST(c.INP1_OPT1_Visit AS INT))+(p.ED_Visit*CAST(c.ED_Visit AS INT))+(p.Num_Dx1*CAST(c.Num_Dx1 AS INT))
  +(p.Num_Dx2*CAST(c.Num_Dx2 AS INT))+(p.Routine_Care_2*CAST(c.Routine_Care_2 AS INT))
  AS Predicted_score
FROM (
select FIELD_NAME, COEFF
from XREF_LoyaltyCode_PSCoeff
)U
PIVOT /* ORACLE EQUIV : https://www.oracletutorial.com/oracle-basics/oracle-unpivot/ */
(MAX(COEFF) for FIELD_NAME in (MDVisit_pname2, MDVisit_pname3, MedicalExam, Mammography, PapTest, PSATest, Colonoscopy, FecalOccultTest, FluShot, PneumococcalVaccine
  , BMI, A1C, MedUse1, MedUse2, INP1_OPT1_Visit, OPT2_Visit, Num_Dx1, Num_Dx2, ED_Visit, Routine_Care_2))p, #COHORT c
)PS
WHERE C.PATIENT_NUM = PS.PATIENT_NUM;



	--perform cleanup
	drop table #visit_ED
	drop table #visit_inpatient
	drop table #visit_outpatient
	drop table #ProviderCount
	drop table #PX_params
	drop table #DX_params
	drop table #Lab_params

set @MessageText = 'ready to complete ' + CONVERT(CHAR(20),  GETDATE(), 120)
RAISERROR(@MessageText,0,1) WITH NOWAIT;	

	if object_id('loyalty_dev') is not null drop table loyalty_dev   --------->>>Change db name to your specific db
	select * into loyalty_dev from #cohort  --------->>>Change db name to your specific db

	--select * from #cohort   ---> comment out after testing


	-----Get Summary Data for testing. 
			CREATE TABLE #cohort_summary (
			Summary_Decsription nvarchar(50) null,
			tablename nvarchar(50),
			TotalSubjects int null,
			Num_Dx1 Decimal(16,2) NOT null DEFAULT 0,
			Num_Dx2 Decimal(16,2) not null DEFAULT 0,
			MedUse1 Decimal(16,2) not null DEFAULT 0,
			MedUse2 Decimal(16,2) not null DEFAULT 0,
			Mammography Decimal(16,2) not null DEFAULT 0,
			PapTest Decimal(16,2) not null DEFAULT 0,
			PSATest Decimal(16,2) not null DEFAULT 0,
			Colonoscopy Decimal(16,2) not null DEFAULT 0,
            FecalOccultTest Decimal(16,2) not null DEFAULT 0,
			FluShot Decimal(16,2) not null DEFAULT 0,
			PneumococcalVaccine Decimal(16,2) not null DEFAULT 0,
			BMI Decimal(16,2) not null DEFAULT 0,
			A1C Decimal(16,2) not null DEFAULT 0,
			MedicalExam Decimal(16,2) not null DEFAULT 0,
			INP1_OPT1_Visit Decimal(16,2) not null DEFAULT 0,
			OPT2_Visit Decimal(16,2) not null DEFAULT 0,
			ED_Visit Decimal(16,2) not null DEFAULT 0,
			MDVisit_pname2 Decimal(16,2) not null DEFAULT 0,
			MDVisit_pname3 Decimal(16,2) not null DEFAULT 0,
			Routine_Care_2 Decimal(16,2) not null DEFAULT 0,
			Subjects_NoCriteria Decimal(16,2) not null DEFAULT 0,
			PredictiveScoreCutoff Float not null DEFAULT 0
				)

	INSERT INTO  #cohort_summary (Summary_Decsription, tablename, TotalSubjects, Num_Dx1, Num_Dx2, MedUse1, MedUse2, Mammography, PapTest, PSATest, Colonoscopy, FecalOccultTest, FluShot, 
					PneumococcalVaccine, BMI, A1C, MedicalExam, INP1_OPT1_Visit, OPT2_Visit, ED_Visit, MDVisit_pname2, MDVisit_pname3, Routine_Care_2, Subjects_NoCriteria)
	SELECT
		'Patient Counts' as Summary_Description, 'All Patients' as tablename,
		(select count(distinct patient_num) from #cohort) as TotalSubjects,
		(select count(distinct patient_num) from #cohort where [Num_Dx1] = 1 ) as Num_DX,
        (select count(distinct patient_num) from #cohort where [Num_Dx2] = 1 ) as Num_DX2,
        (select count(distinct patient_num) from #cohort where [MedUse1] = 1 ) as MedUSe1,
        (select count(distinct patient_num) from #cohort where [MedUse2] = 1 ) as MedUse2,
        (select count(distinct patient_num) from #cohort where [Mammography] = 1 ) as Mammography,
        (select count(distinct patient_num) from #cohort where [PapTest] = 1 ) as PapTest,
        (select count(distinct patient_num) from #cohort where [PSATest] = 1 ) as PSATest,
        (select count(distinct patient_num) from #cohort where [Colonoscopy] = 1 ) as Colonoscopy,
        (select count(distinct patient_num) from #cohort where [FecalOccultTest] = 1 ) as FecalOccultTest,
        (select count(distinct patient_num) from #cohort where [FluShot] = 1 ) as  FluShot,
        (select count(distinct patient_num) from #cohort where [PneumococcalVaccine] = 1 ) as PneumococcalVaccine,
        (select count(distinct patient_num) from #cohort where [BMI] = 1 )  as BMI,
        (select count(distinct patient_num) from #cohort where [A1C] = 1 ) as A1C,
        (select count(distinct patient_num) from #cohort where [MedicalExam] = 1 ) as MedicalExam,
        (select count(distinct patient_num) from #cohort where [INP1_OPT1_Visit] = 1 ) as INP1_OPT1_Visit,
        (select count(distinct patient_num) from #cohort where [OPT2_Visit] = 1 ) as OutPT2_visit,
        (select count(distinct patient_num) from #cohort where [ED_Visit] = 1 )  as ED_Visit,
        (select count(distinct patient_num) from #cohort where [MDVisit_pname2] = 1 ) as SameProvider_2x,
        (select count(distinct patient_num) from #cohort where [MDVisit_pname3] = 1 ) as SameProvider_3x,
        (select count(distinct patient_num) from #cohort where [Routine_Care_2] = 1 ) as Routine_care,
		(select count(distinct patient_num) from #cohort 
			where Num_Dx1 =0 and Num_Dx2 = 0 and MedUse1  = 0 and  MedUse2 = 0 and  Mammography = 0
			and  PapTest  = 0 and PSATest  = 0 and Colonoscopy = 0 and  FecalOccultTest = 0 and FluShot = 0 
			and PneumococcalVaccine = 0 and BMI  = 0 and A1C = 0 and  MedicalExam  = 0 and INP1_OPT1_Visit  = 0 
			and OPT2_Visit = 0 and ED_Visit = 0 and MDVisit_pname2 = 0 and MDVisit_pname3 = 0 and Routine_Care_2 = 0) as Subjects_NoCriteria
 

	INSERT INTO #cohort_summary (Summary_Decsription,  tablename, TotalSubjects, Num_Dx1, Num_Dx2, MedUse1, MedUse2, Mammography, PapTest, PSATest, Colonoscopy, FecalOccultTest, FluShot, 
						PneumococcalVaccine, BMI, A1C, MedicalExam, INP1_OPT1_Visit, OPT2_Visit, ED_Visit, MDVisit_pname2, MDVisit_pname3, Routine_Care_2, Subjects_NoCriteria)
	select  'PercentOfSubjects', 'All Patients'
	   , (select count(distinct patient_num) from #cohort) as TotalSubjects
	   ,CASE When Num_Dx1 > 0 then ([Num_Dx1] / [TotalSubjects]) *100 else 0 end
      , CASE When Num_Dx2 > 0 then ([Num_Dx2] / [TotalSubjects]) *100 else 0 end
      , CASE When MedUse1 > 0 then ([MedUse1] / [TotalSubjects]) *100 else 0 end
      , CASE When MedUse2 > 0 then ([MedUse2] / [TotalSubjects]) *100 else 0 end
      , CASE When Mammography > 0 then ([Mammography] / [TotalSubjects]) *100 else 0 end
      , CASE When PapTest > 0 then ([PapTest]/ [TotalSubjects]) *100 else 0 end
      , CASE When PSATest > 0 then ([PSATest]/ [TotalSubjects]) *100 else 0 end
      , CASE When Colonoscopy > 0 then ([Colonoscopy]/ [TotalSubjects]) *100 else 0 end
      , CASE When FecalOccultTest > 0 then ([FecalOccultTest]/ [TotalSubjects]) *100 else 0 end
      , CASE When FluShot > 0 then ([FluShot]/ [TotalSubjects]) *100 else 0 end
      , CASE When PneumococcalVaccine > 0 then ([PneumococcalVaccine]/ [TotalSubjects]) *100 else 0 end
      , CASE When BMI > 0 then ([BMI]/ [TotalSubjects]) *100 else 0 end
      , CASE When A1C > 0 then ([A1C]/ [TotalSubjects]) *100 else 0 end
      , CASE When MedicalExam > 0 then ([MedicalExam]/ [TotalSubjects]) *100 else 0 end
      , CASE When INP1_OPT1_Visit > 0 then ([INP1_OPT1_Visit]/ [TotalSubjects]) *100 else 0 end
      , CASE When OPT2_Visit > 0  then ([OPT2_Visit]/ [TotalSubjects]) *100 else 0 end
      , CASE When ED_Visit > 0 then ([ED_Visit]/ [TotalSubjects]) *100 else 0 end
      , CASE When MDVisit_pname2 > 0 then ([MDVisit_pname2]/ [TotalSubjects]) *100 else 0 end
      , CASE When MDVisit_pname3 > 0 then ([MDVisit_pname3]/ [TotalSubjects]) *100 else 0 end
      , CASE When Routine_Care_2 > 0 then ([Routine_Care_2]/ [TotalSubjects]) *100 else 0 end
	  , CASE When Subjects_NoCriteria > 0 then ([Subjects_NoCriteria]/ [TotalSubjects]) *100 else 0 end
	FROM  #cohort_summary
	
	;With Top20 as 
	  (SELECT  patient_num, predicted_score,
		NTILE(5) OVER(ORDER BY predicted_score DESC) AS ScoreRank
		from loyalty_dev) -- THIS ALSO NEEDS TO BE MODIFIED FOR YOUR TABLENAME
		Update #cohort_summary 
		set PredictiveScoreCutoff = (select min(predicted_score)
										from Top20
										where ScoreRank = 1 and tablename='All Patients') where tablename='All Patients'
   
    -- jgk: It pains me to duplicate the code above but parameterizing in MSSQL is too awful
    -- Do the same calculations as above for >=65 and <65
    
    select * into #cohort_old from #cohort where age>=65
    select * into #cohort_young from #cohort where age<=65
    
    -- >=65
    	INSERT INTO  #cohort_summary (Summary_Decsription, tablename, TotalSubjects, Num_Dx1, Num_Dx2, MedUse1, MedUse2, Mammography, PapTest, PSATest, Colonoscopy, FecalOccultTest, FluShot, 
					PneumococcalVaccine, BMI, A1C, MedicalExam, INP1_OPT1_Visit, OPT2_Visit, ED_Visit, MDVisit_pname2, MDVisit_pname3, Routine_Care_2, Subjects_NoCriteria)
	SELECT
		'Patient Counts' as Summary_Description, 'Over 65' as tablename,
		(select count(distinct patient_num) from #cohort_old) as TotalSubjects,
		(select count(distinct patient_num) from #cohort_old where [Num_Dx1] = 1 ) as Num_DX,
        (select count(distinct patient_num) from #cohort_old where [Num_Dx2] = 1 ) as Num_DX2,
        (select count(distinct patient_num) from #cohort_old where [MedUse1] = 1 ) as MedUSe1,
        (select count(distinct patient_num) from #cohort_old where [MedUse2] = 1 ) as MedUse2,
        (select count(distinct patient_num) from #cohort_old where [Mammography] = 1 ) as Mammography,
        (select count(distinct patient_num) from #cohort_old where [PapTest] = 1 ) as PapTest,
        (select count(distinct patient_num) from #cohort_old where [PSATest] = 1 ) as PSATest,
        (select count(distinct patient_num) from #cohort_old where [Colonoscopy] = 1 ) as Colonoscopy,
        (select count(distinct patient_num) from #cohort_old where [FecalOccultTest] = 1 ) as FecalOccultTest,
        (select count(distinct patient_num) from #cohort_old where [FluShot] = 1 ) as  FluShot,
        (select count(distinct patient_num) from #cohort_old where [PneumococcalVaccine] = 1 ) as PneumococcalVaccine,
        (select count(distinct patient_num) from #cohort_old where [BMI] = 1 )  as BMI,
        (select count(distinct patient_num) from #cohort_old where [A1C] = 1 ) as A1C,
        (select count(distinct patient_num) from #cohort_old where [MedicalExam] = 1 ) as MedicalExam,
        (select count(distinct patient_num) from #cohort_old where [INP1_OPT1_Visit] = 1 ) as INP1_OPT1_Visit,
        (select count(distinct patient_num) from #cohort_old where [OPT2_Visit] = 1 ) as OutPT2_visit,
        (select count(distinct patient_num) from #cohort_old where [ED_Visit] = 1 )  as ED_Visit,
        (select count(distinct patient_num) from #cohort_old where [MDVisit_pname2] = 1 ) as SameProvider_2x,
        (select count(distinct patient_num) from #cohort_old where [MDVisit_pname3] = 1 ) as SameProvider_3x,
        (select count(distinct patient_num) from #cohort_old where [Routine_Care_2] = 1 ) as Routine_care,
		(select count(distinct patient_num) from #cohort_old 
			where Num_Dx1 =0 and Num_Dx2 = 0 and MedUse1  = 0 and  MedUse2 = 0 and  Mammography = 0
			and  PapTest  = 0 and PSATest  = 0 and Colonoscopy = 0 and  FecalOccultTest = 0 and FluShot = 0 
			and PneumococcalVaccine = 0 and BMI  = 0 and A1C = 0 and  MedicalExam  = 0 and INP1_OPT1_Visit  = 0 
			and OPT2_Visit = 0 and ED_Visit = 0 and MDVisit_pname2 = 0 and MDVisit_pname3 = 0 and Routine_Care_2 = 0) as Subjects_NoCriteria
			
	INSERT INTO #cohort_summary (Summary_Decsription, tablename, TotalSubjects, Num_Dx1, Num_Dx2, MedUse1, MedUse2, Mammography, PapTest, PSATest, Colonoscopy, FecalOccultTest, FluShot, 
						PneumococcalVaccine, BMI, A1C, MedicalExam, INP1_OPT1_Visit, OPT2_Visit, ED_Visit, MDVisit_pname2, MDVisit_pname3, Routine_Care_2, Subjects_NoCriteria)
	select  'PercentOfSubjects','Over 65'
	   , (select count(distinct patient_num) from #cohort_old) as TotalSubjects
	   ,CASE When Num_Dx1 > 0 then ([Num_Dx1] / [TotalSubjects]) *100 else 0 end
      , CASE When Num_Dx2 > 0 then ([Num_Dx2] / [TotalSubjects]) *100 else 0 end
      , CASE When MedUse1 > 0 then ([MedUse1] / [TotalSubjects]) *100 else 0 end
      , CASE When MedUse2 > 0 then ([MedUse2] / [TotalSubjects]) *100 else 0 end
      , CASE When Mammography > 0 then ([Mammography] / [TotalSubjects]) *100 else 0 end
      , CASE When PapTest > 0 then ([PapTest]/ [TotalSubjects]) *100 else 0 end
      , CASE When PSATest > 0 then ([PSATest]/ [TotalSubjects]) *100 else 0 end
      , CASE When Colonoscopy > 0 then ([Colonoscopy]/ [TotalSubjects]) *100 else 0 end
      , CASE When FecalOccultTest > 0 then ([FecalOccultTest]/ [TotalSubjects]) *100 else 0 end
      , CASE When FluShot > 0 then ([FluShot]/ [TotalSubjects]) *100 else 0 end
      , CASE When PneumococcalVaccine > 0 then ([PneumococcalVaccine]/ [TotalSubjects]) *100 else 0 end
      , CASE When BMI > 0 then ([BMI]/ [TotalSubjects]) *100 else 0 end
      , CASE When A1C > 0 then ([A1C]/ [TotalSubjects]) *100 else 0 end
      , CASE When MedicalExam > 0 then ([MedicalExam]/ [TotalSubjects]) *100 else 0 end
      , CASE When INP1_OPT1_Visit > 0 then ([INP1_OPT1_Visit]/ [TotalSubjects]) *100 else 0 end
      , CASE When OPT2_Visit > 0  then ([OPT2_Visit]/ [TotalSubjects]) *100 else 0 end
      , CASE When ED_Visit > 0 then ([ED_Visit]/ [TotalSubjects]) *100 else 0 end
      , CASE When MDVisit_pname2 > 0 then ([MDVisit_pname2]/ [TotalSubjects]) *100 else 0 end
      , CASE When MDVisit_pname3 > 0 then ([MDVisit_pname3]/ [TotalSubjects]) *100 else 0 end
      , CASE When Routine_Care_2 > 0 then ([Routine_Care_2]/ [TotalSubjects]) *100 else 0 end
	  , CASE When Subjects_NoCriteria > 0 then ([Subjects_NoCriteria]/ [TotalSubjects]) *100 else 0 end
	FROM  #cohort_summary where tablename='Over 65'
	
        ;With Top20 as 
	  (SELECT  patient_num, predicted_score, age,
		NTILE(5) OVER(ORDER BY predicted_score DESC) AS ScoreRank
		from loyalty_dev where age>=65) -- THIS ALSO NEEDS TO BE MODIFIED FOR YOUR TABLENAME
		Update #cohort_summary 
		set PredictiveScoreCutoff = (select min(predicted_score)
										from Top20
										where ScoreRank = 1) where tablename='Over 65'
	
	-- <65

		INSERT INTO  #cohort_summary (Summary_Decsription, tablename, TotalSubjects, Num_Dx1, Num_Dx2, MedUse1, MedUse2, Mammography, PapTest, PSATest, Colonoscopy, FecalOccultTest, FluShot, 
					PneumococcalVaccine, BMI, A1C, MedicalExam, INP1_OPT1_Visit, OPT2_Visit, ED_Visit, MDVisit_pname2, MDVisit_pname3, Routine_Care_2, Subjects_NoCriteria)
	SELECT
		'Patient Counts' as Summary_Description,
		'Under 65' as tablename,
		(select count(distinct patient_num) from #cohort_young) as TotalSubjects,
		(select count(distinct patient_num) from #cohort_young where [Num_Dx1] = 1 ) as Num_DX,
        (select count(distinct patient_num) from #cohort_young where [Num_Dx2] = 1 ) as Num_DX2,
        (select count(distinct patient_num) from #cohort_young where [MedUse1] = 1 ) as MedUSe1,
        (select count(distinct patient_num) from #cohort_young where [MedUse2] = 1 ) as MedUse2,
        (select count(distinct patient_num) from #cohort_young where [Mammography] = 1 ) as Mammography,
        (select count(distinct patient_num) from #cohort_young where [PapTest] = 1 ) as PapTest,
        (select count(distinct patient_num) from #cohort_young where [PSATest] = 1 ) as PSATest,
        (select count(distinct patient_num) from #cohort_young where [Colonoscopy] = 1 ) as Colonoscopy,
        (select count(distinct patient_num) from #cohort_young where [FecalOccultTest] = 1 ) as FecalOccultTest,
        (select count(distinct patient_num) from #cohort_young where [FluShot] = 1 ) as  FluShot,
        (select count(distinct patient_num) from #cohort_young where [PneumococcalVaccine] = 1 ) as PneumococcalVaccine,
        (select count(distinct patient_num) from #cohort_young where [BMI] = 1 )  as BMI,
        (select count(distinct patient_num) from #cohort_young where [A1C] = 1 ) as A1C,
        (select count(distinct patient_num) from #cohort_young where [MedicalExam] = 1 ) as MedicalExam,
        (select count(distinct patient_num) from #cohort_young where [INP1_OPT1_Visit] = 1 ) as INP1_OPT1_Visit,
        (select count(distinct patient_num) from #cohort_young where [OPT2_Visit] = 1 ) as OutPT2_visit,
        (select count(distinct patient_num) from #cohort_young where [ED_Visit] = 1 )  as ED_Visit,
        (select count(distinct patient_num) from #cohort_young where [MDVisit_pname2] = 1 ) as SameProvider_2x,
        (select count(distinct patient_num) from #cohort_young where [MDVisit_pname3] = 1 ) as SameProvider_3x,
        (select count(distinct patient_num) from #cohort_young where [Routine_Care_2] = 1 ) as Routine_care,
		(select count(distinct patient_num) from #cohort_young 
			where Num_Dx1 =0 and Num_Dx2 = 0 and MedUse1  = 0 and  MedUse2 = 0 and  Mammography = 0
			and  PapTest  = 0 and PSATest  = 0 and Colonoscopy = 0 and  FecalOccultTest = 0 and FluShot = 0 
			and PneumococcalVaccine = 0 and BMI  = 0 and A1C = 0 and  MedicalExam  = 0 and INP1_OPT1_Visit  = 0 
			and OPT2_Visit = 0 and ED_Visit = 0 and MDVisit_pname2 = 0 and MDVisit_pname3 = 0 and Routine_Care_2 = 0) as Subjects_NoCriteria
	
	INSERT INTO #cohort_summary (Summary_Decsription, tablename, TotalSubjects, Num_Dx1, Num_Dx2, MedUse1, MedUse2, Mammography, PapTest, PSATest, Colonoscopy, FecalOccultTest, FluShot, 
						PneumococcalVaccine, BMI, A1C, MedicalExam, INP1_OPT1_Visit, OPT2_Visit, ED_Visit, MDVisit_pname2, MDVisit_pname3, Routine_Care_2, Subjects_NoCriteria)
	select  'PercentOfSubjects','Under 65'
	  , (select count(distinct patient_num) from #cohort_young) as TotalSubjects
	   ,CASE When Num_Dx1 > 0 then ([Num_Dx1] / [TotalSubjects]) *100 else 0 end
      , CASE When Num_Dx2 > 0 then ([Num_Dx2] / [TotalSubjects]) *100 else 0 end
      , CASE When MedUse1 > 0 then ([MedUse1] / [TotalSubjects]) *100 else 0 end
      , CASE When MedUse2 > 0 then ([MedUse2] / [TotalSubjects]) *100 else 0 end
      , CASE When Mammography > 0 then ([Mammography] / [TotalSubjects]) *100 else 0 end
      , CASE When PapTest > 0 then ([PapTest]/ [TotalSubjects]) *100 else 0 end
      , CASE When PSATest > 0 then ([PSATest]/ [TotalSubjects]) *100 else 0 end
      , CASE When Colonoscopy > 0 then ([Colonoscopy]/ [TotalSubjects]) *100 else 0 end
      , CASE When FecalOccultTest > 0 then ([FecalOccultTest]/ [TotalSubjects]) *100 else 0 end
      , CASE When FluShot > 0 then ([FluShot]/ [TotalSubjects]) *100 else 0 end
      , CASE When PneumococcalVaccine > 0 then ([PneumococcalVaccine]/ [TotalSubjects]) *100 else 0 end
      , CASE When BMI > 0 then ([BMI]/ [TotalSubjects]) *100 else 0 end
      , CASE When A1C > 0 then ([A1C]/ [TotalSubjects]) *100 else 0 end
      , CASE When MedicalExam > 0 then ([MedicalExam]/ [TotalSubjects]) *100 else 0 end
      , CASE When INP1_OPT1_Visit > 0 then ([INP1_OPT1_Visit]/ [TotalSubjects]) *100 else 0 end
      , CASE When OPT2_Visit > 0  then ([OPT2_Visit]/ [TotalSubjects]) *100 else 0 end
      , CASE When ED_Visit > 0 then ([ED_Visit]/ [TotalSubjects]) *100 else 0 end
      , CASE When MDVisit_pname2 > 0 then ([MDVisit_pname2]/ [TotalSubjects]) *100 else 0 end
      , CASE When MDVisit_pname3 > 0 then ([MDVisit_pname3]/ [TotalSubjects]) *100 else 0 end
      , CASE When Routine_Care_2 > 0 then ([Routine_Care_2]/ [TotalSubjects]) *100 else 0 end
	  , CASE When Subjects_NoCriteria > 0 then ([Subjects_NoCriteria]/ [TotalSubjects]) *100 else 0 end
	FROM  #cohort_summary where tablename='Under 65'
	
	;With Top20 as 
	  (SELECT  patient_num, predicted_score, age,
		NTILE(5) OVER(ORDER BY predicted_score DESC) AS ScoreRank
		from loyalty_dev where age<65) -- THIS ALSO NEEDS TO BE MODIFIED FOR YOUR TABLENAME
		Update #cohort_summary 
		set PredictiveScoreCutoff = (select min(predicted_score)
										from Top20
										where ScoreRank = 1) where tablename='Under 65'
										
    -- Add obfuscated patient counts to the percent
    update s set TotalSubjects=s2.TotalSubjects + FLOOR(ABS(BINARY_CHECKSUM(NEWID())/2147483648.0)*(10*2+1)) - 10 
	  from #cohort_summary as s inner join #cohort_summary as s2 on s.tablename=s2.tablename
	  where s.Summary_Decsription='PercentOfSubjects' and s2.Summary_Decsription='Patient Counts'
   
   	if object_id('loyalty_dev_summary') is not null drop table loyalty_dev_summary --------->>>Change db name to your specific db
	select * into loyalty_dev_summary from #cohort_summary  --------->>>Change db name to your specific db

    select * from loyalty_dev_summary where Summary_Decsription='PercentOfSubjects' order by Summary_Decsription -- THIS IS OK TO EXPORT!

    END
Else
	PRINT 'Variable passed incorrect date format'  -----dummy code for error check


GO




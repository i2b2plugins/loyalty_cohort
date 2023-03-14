# Loyalty Cohort Algorithm
### Implements the loyalty cohort algorithm defined in [*External Validation of an Algorithm to Identify Patients with High Data-Completeness in Electronic Health Records for Comparative Effectiveness Research*](https://pubmed.ncbi.nlm.nih.gov/32099479/) by Lin et al.

#### See [appendix table S1](https://www.dovepress.com/get_supplementary_file.php?f=232540.docx) for the regression equation used to calculate the score.
#### See [algorithm outline](https://github.com/i2b2plugins/loyalty_cohort/blob/main/ALGORITHM_README.md) for more details on the algorithm.

## Notes:
* Relies on i2b2 data using the ACT ontology.
* This version is MSSQL. Oracle refactor underway in a separate branch.
* (Maybe - The Loyalty Paths might be missing some sibling nodes).

## From your ACT database...

### To install:
1) Run ddl_xref_LoyaltyCode_paths.sql to create the xref_LoyaltyCode_paths table.
2) Run ddl_LU_CHARLSON.sql to create the LU_CHARLSON table.
4) Import the contents of xref_LoyaltyCode_paths.csv into the table, or run insert_xref_LoyaltyCode_paths.sql
5) Run insert_LU_CHARLSON.sql to populate the LU_CHARLSON table. Replace the prefix in the code pattern column if your data do not use ICD10CM: and ICD9CM:
6) Run ddl_dml_xref_LoyaltyCohort_PSCoeff.sql to create and load the Predicted Score coefficients table. The coefficients can be changed in this file to load a custom set of coefficients, such as if the regression equation is retrained.
7) Run *dbtype*/LoyaltyCohort*dbtype* to create the usp_LoyaltyCohort_opt stored procedure.

### To run:

1) Create a cohort filter table, defining the patients on which to compute loyalty scores. The three columns are:
	* *patient_num*: patient_num from the i2b2 tables
	* *cohort_name*: a name for the cohort. You can optionally compute several cohorts separately, but specifying different values for this.
	* *index_dt*: a date which is a reference point in time at which to compute the loyalty score. It is suggested to select a common recent point in time or to choose each patient's most recent visit date, for example.
```
DECLARE @cfilter udt_CohortFilter

INSERT INTO @cfilter (PATIENT_NUM, COHORT_NAME, INDEX_DT)
   select distinct patient_num, substring(cohort,1,charindex('202',cohort)-1) cohort, admission_date 
 FROM [FourCE_LocalPatientSummary] /*  4CE X.2 COHORT FOR EXAMPLE */
```
2) Customize the following statement and execute on your database to compute the loyalty cohort.
		 ``EXEC [dbo].[usp_LoyaltyCohort_opt] @site='UKY', @lookbackYears=1,  @demographic_facts=1, @gendered=0,  @cohort_filter=@cfilter, @output=0 ``
  Note that steps 1-2 must be run in the same transaction.
3) Execute the following statement on your database to print the output that can be shared:
	select * from loyalty_dev_summary where Summary_Description='PercentOfSubjects'

4) We are collecting outputs of this script to compare heuristics. If participating, contact us for access and then paste the output of step 3 into the Google sheet here:
https://docs.google.com/spreadsheets/d/1ubuRt_ffVcZiQgUdOmeMXxgjOdfkpQe2FNFyt0u2Un4/edit?usp=sharing

5) The script also outputs patient level data in `loyalty_dev` and `loyalty_charlson_dev`. These cohorts are dependent on lookbackYears but not demographic_facts.

### Parameter description:
* *site*: A short (3-character) identifier for your site.
* *lookbackYears*: A number of years for lookback. The original algorithm used 1 year, but we have found 3- or 5-years are more accurate, because some preventitive care like PSA and Pap Smears do not occurr every year.
* *demographic_facts*: Set to 1 if demographic facts (e.g., age, sex) are stored in the fact table (rather than patient_dimension).
* *gendered*: Set to 1 to create a summary table (and cutoffs) that do not include male-only facts for female patients in the denominator and vice-versa.
* *filter_by_existing_cohort* and *cohort_filter*: If the first is 1, specify a table variable of (PATIENT_NUM, COHORT_NAME) in the second parameter.
* *output*: If 1, pretty-print the loyalty_dev_summary percentages after the run.

# Loyalty Cohort Algorithm
### Implements the loyalty cohort algorithm defined in [*External Validation of an Algorithm to Identify Patients with High Data-Completeness in Electronic Health Records for Comparative Effectiveness Research*](https://pubmed.ncbi.nlm.nih.gov/32099479/) by Lin et al.
(See [appendix table S1](https://www.dovepress.com/get_supplementary_file.php?f=232540.docx) for the regression equation used to calculate the score.)

## Notes:
* This only runs on MSSQL right now. (Oracle refactor underway)
* The Loyalty Paths are missing some sibling nodes. (New Paths added as of 20210512)
* Relies on i2b2 data using the ACT ontology.

## From your ACT database...

### If upgrading:
* Delete `loyalty_dev_summary`. (The format has changed.)
* Run https://github.com/i2b2plugins/loyalty_cohort/blob/main/updates_to_paths_and_coeff.sql to update your paths.

### To install:
1) Run ddl_xref_LoyaltyCode_paths.sql to create the xref_LoyaltyCode_paths table.
2) Run ddl_LU_CHARLSON.sql to create the LU_CHARLSON table.
4) Import the contents of xref_LoyaltyCode_paths.csv into the table, or run insert_xref_LoyaltyCode_paths.sql
5) Run insert_LU_CHARLSON.sql to populate the LU_CHARLSON table. Replace the prefix in the code pattern column if your data do not use ICD10CM: and ICD9CM:
6) Run ddl_dml_xref_LoyaltyCohort_PSCoeff.sql to create and load the Predicted Score coefficients table.
7) Run OPTIMIZATION_REFACTOR_V1.sql to create the usp_LoyaltyCohort_opt stored procedure.

### To run:
1) Execute the following statement on your database to compute the loyalty cohort. This should take about 10 minutes or less.
		 `EXEC [dbo].[usp_LoyaltyCohort_opt] @indexDate = '20210201', @site='UKY', @lookbackYears=1,  @demographic_facts=1, @gendered=0, @filter_by_existing_cohort=0, @cohort_filter=@cfilter, @output=0 `
2) Execute the following statement on your database to print the output that can be shared:
	select * from loyalty_dev_summary where Summary_Description='PercentOfSubjects'

3) We are collecting outputs of this script to compare heuristics. If participating, contact us for access and then paste the output of step 5 into the Google sheet here:
https://docs.google.com/spreadsheets/d/1ubuRt_ffVcZiQgUdOmeMXxgjOdfkpQe2FNFyt0u2Un4/edit?usp=sharing

4) The script also outputs patient level data in `loyalty_dev` and `loyalty_charlson_dev`. These cohorts are dependent on lookbackYears but not demographic_facts.

### Parameter description:
* *site*: A short (3-character) identifier for your site.
* *lookbackYears*: A number of years for lookback. The original algorithm used 1 year, but we have found 3- or 5-years are more accurate, because some preventitive care like PSA and Pap Smears do not occurr every year.
* *demographic_facts*: Set to 1 if demographic facts (e.g., age, sex) are stored in the fact table (rather than patient_dimension).
* *gendered*: Set to 1 to create a summary table (and cutoffs) that do not include male-only facts for female patients in the denominator and vice-versa.
* *filter_by_existing_cohort* and *cohort_filter*: If the first is 1, specify a table variable of (PATIENT_NUM, COHORT_NAME) in the second parameter.
* *output*: If 1, pretty-print the loyalty_dev_summary percentages after the run.

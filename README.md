# Loyalty Cohort Algorithm
### Implements the loyalty cohort algorithm defined in *External Validation of an Algorithm to Identify Patients with High Data-Completeness in Electronic Health Records for Comparative Effectiveness Research* by Lin et al.

## Notes:
* This only runs on MSSQL right now. (Oracle refactor underway)
* The Loyalty Paths are missing some sibling nodes. (New Paths added as of 20210512)
* Relies on i2b2 data using the ACT ontology.

## Steps to run:

From your ACT database.

1) Run ddl_xref_LoyaltyCode_paths.sql to create the xref_LoyaltyCode_paths table.
2) Import the contents of xref_LoyaltyCode_paths.csv into the table, or run insert_xref_LoyaltyCode_paths.sql
3) Run ddl_dml_xref_LoyaltyCohort_PSCoeff.sql to create and load the Predicted Score coefficients table.
4) Run OPTIMIZATION_REFACTOR_V1.sql to create the usp_LoyaltyCohort_opt stored procedure.
5) Execute the following statement on your database to compute the loyalty cohort. This should take about 10 minutes or less.
		 `exec usp_LoyaltyCohort_opt '20210201' `
5) Execute the following statement on your database to print the output that can be shared:
	select * from loyalty_dev_summary where Summary_Description='PercentOfSubjects'

6) We are collecting outputs of this script to compare heuristics. If participating, contact us for access and then paste the output of step 5 into the Google sheet here:
https://docs.google.com/spreadsheets/d/1ubuRt_ffVcZiQgUdOmeMXxgjOdfkpQe2FNFyt0u2Un4/edit?usp=sharing

# Loyalty Cohort Algorithm
### Implements the loyalty cohort algorithm defined in *External Validation of an Algorithm to Identify Patients with High Data-Completeness in Electronic Health Records for Comparative Effectiveness Research* by Lin et al.

## Notes:
* This only runs on MSSQL right now
* The Loyalty Paths are missing some sibling nodes.
* Relies on i2b2 data using the ACT ontology.

## Steps to run:

From your ACT database.

1) Run ddl_xref_LoyaltyCode_paths.sql to create the xref_LoyaltyCode_paths table.
2) Import the contents of xref_LoyaltyCode_paths.txt into the table.
3) Run usp_LoyaltyCohort_v6.sql to create the usp_LoyaltyCohort stored procedure.
4) Execute the following statement on your database to compute the loyalty cohort. This should take about 10 minutes or less.
		 `exec usp_LoyaltyCohort '2/01/2020' `
5) Execute the following statement on your database to print the output that can be shared:
	select * from loyalty_dev_summary where Summary_Decsription='PercentOfSubjects'

6) We are collecting outputs of this script to compare heuristics. If participating, contact us for access and then paste the output of step 5 into the Google sheet here:
https://docs.google.com/spreadsheets/d/1ubuRt_ffVcZiQgUdOmeMXxgjOdfkpQe2FNFyt0u2Un4/edit?usp=sharing

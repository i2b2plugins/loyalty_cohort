# Algorithm Details

Implements a loyalty cohort algorithm with the same general design defined in 
  *"External Validation of an Algorithm to Identify Patients with High Data-Completeness in Electronic Health Records for Comparative Effectiveness Research"* by Lin et al.
- Written primarily by Darren Henderson with contributions from: Jeff Klann, PhD; Andrew Cagan; Barbara Benoit
- Calculates 20 variables over the baseline period and computes an overall score, the highest scoring individuals are an approximation of those most likely present for future follow-up
- This script accepts an index_date and looks back n years previous to that date (baseline period).

## Outline of algorithm

1. Select all patients with a non-demographic fact between 1/1/2012 and the specified index date.

2. Determine which patients had visits of the required types between the index date and the index date minus the specified number of lookback years.

3. Determine which patients have facts of the required types between the index date and the index date minus the specified number of lookback years.

4. Compute average fact counts.

5. Compute Charlson score (by examining a set of diagnoses).

6. Save the final cohort table (`loyalty_dev`), Charlson scores (`loyalty_charlson_dev`), and generate summary statistics (loyalty_dev_summary) on the patients in the top quintile for highest loyalty score.

## Variables and their coefficients

 | Variable | Coefficient | 
 | -------- | ----------- |
 | Intercept | -0.010 | 
 | Having seen the same provider twice | 0.049 | 
 | Having seen the same provider >=3 times | 0.087 | 
 | Having general medical exam* | 0.078 | 
 | Mammography* | 0.075 | 
 | Pap smear* | 0.009 | 
 | PSA Test* | 0.103 | 
 | Colonoscopy* | 0.064 | 
 | Fecal occult blood test* | 0.034 | 
 | Influenza vaccine* | 0.102 | 
 | Pneumococcal vaccine* | 0.031 | 
 | Having BMI recorded* | 0.017 | 
 | Having 2 of the above routine care facts** | 0.049 | 
 | With any one medication use record | 0.002 | 
 | With at least 2 medication use records | 0.074 | 
 | Having A1C ordered or value recorded* | 0.018 | 
 | Having at least one inpatient or outpatient encounter | 0.091 | 
 | Having at least two  outpatient encounters | 0.050 | 
 | With 1 diagnosis recorded in the EHR | -0.026 | 
 | With at least 2 diagnoses recorded in the EHR | 0.037 | 
 | Having any ED visit in the EHR | 0.078 | 
 | ** having 2 of the facts followed by *, EHR=electronic health records, PSA= prostate specific antigen | 
 
 Table S1 from Lin KJ, Rosenthal GE, Murphy SN, Mandl KD, Jin Y, Glynn RJ, et al. External Validation of an Algorithm to Identify Patients with High Data-Completeness in Electronic Health Records for Comparative Effectiveness Research. Clin Epidemiol. 2020 Feb 4;12:133–41.

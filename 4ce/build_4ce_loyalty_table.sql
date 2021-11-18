 -- Select patients in loyalty cohort for 4CE. Generates a table called loyalty_4ce
 -- Run this after the LoyaltyCohort script, on the same database as the loyalty_dev table.
 --  a. Change fource.Phase22all_LocalPatientSummary to your 4CE 2.1/2.2 LocalPatientSummary SQL table
 --  b. Optionally uncomment the code after "filter cutoff by 4CE cohort" to pick a predictive score cutoff based on only 4CE data. The difference is 3x on our data at MGB!
 
IF OBJECT_ID(N'DBO.loyalty_4ce', N'U') IS NOT NULL DROP TABLE DBO.loyalty_dev;
 
select distinct l.patient_num, predicted_score into loyalty_4ce from loyalty_dev l inner join fource.Phase22all_LocalPatientSummary s on s.patient_num=l.patient_num 
where l.Predicted_score>=
(select min(predicted_score) from (select l.patient_num,l.Predicted_score, NTILE(5) OVER (PARTITION BY AGEGRP ORDER BY PREDICTED_SCORE DESC) AS ScoreRank
 from loyalty_dev l /*filter cutoff by 4CE cohort - inner join fource.Phase22all_LocalPatientSummary s on s.patient_num=l.patient_num */
 where agegrp = 'All Patients') x where ScoreRank=1) 
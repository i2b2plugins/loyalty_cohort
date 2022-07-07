OMOP Helper Files
There are at least 2 approaches that can be used. The group of ALL_SOURCE_CONCEPTS*.sql files create views that mimc an i2b2 observation_fact table. They place the  <domain> source concept id in the i2b2 concept_cd field. This would be my prefered path as it requires the least code translations. These views can also be unioned together to look like a standard i2b2 observavtion fact. 
  
  The second path is to use the views contained in the CREATE_ACT_OMOP_VIEWS_<RDB>.sql files. These files place OMOP Standard concept ids in the i2b2 concept_cd field.
  
  Loyalty and Charlson codes
  TBD

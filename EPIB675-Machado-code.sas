
/********************************************************************************************************/
/* Log Information */
/* Project Name: CRC Diagnosis Data Preparation */
/* Author: Michelle Machado */
/* Date: November 1st, 2024 */
/* Purpose: Filter and prepare data to assess timely CRC treatment */
/* Last Updated: November 4th, 2024 */
/********************************************************************************************************/

/* Libname statements */
libname mydata '/home/u64020049/my_shared_file_links/u45035527';
libname myset '/home/u64020049/sasuser.v94';

/********************************************************************************************************/
/* Filter patients with CRC diagnosis from sd_table_diag */
data diag;
    set mydata.sd_table_diag;
run;

/* Check unique IDs */
proc sql;
    select count(distinct id) as unique_ids
    from diag;
quit; /*n = 993953*/
    
/* Keep only records with CRC diagnoses based on ICD codes */
data diag_crc;
    set diag;
    if dx in ('C18', 'C19', 'C20', '153', '154');
run;

/*Rename date column*/
data diag_crc;
    set diag_crc(rename=(date= crc_date));
run;

/* Check unique IDs */
proc sql;
    select count(distinct id) as unique_ids
    from diag_crc;
quit; /*n = 13670*/

/* Sort by patient ID and crc date */
proc sort data=diag_crc;
    by id crc_date;
run;

/* Keep only the first diagnosis for each patient */
data diag_crc;
    set diag_crc;
    by id;
    if first.id; 
run;

/*******************************************************************************************/
/*Join with death data to get coverage dates*/
data coverage;
    set mydata.sd_table_death;
    keep id start end death;
run;

/* Check unique IDs */
proc sql;
    select count(distinct id) as unique_ids
    from coverage;
quit; /*n = 1000000*/

proc sql;
    create table diag_crc_start_end as
    select a.*, b.start, b.end, b.death
    from diag_crc as a
    left join coverage as b
    on a.id = b.id;
quit;

/* Check unique IDs */
proc sql;
    select count(distinct id) as unique_ids
    from diag_crc_start_end;
quit; /*n = 13670*/

/****************************************************************************************************************************/
/* Remove patients whose start is less than 2 years before crc_date and whose diag_date is not >42 days before end */
data diag_crc_final;
    set diag_crc_start_end;

    /* Apply both conditions */
    if intck('year', start, crc_date) >= 2 and crc_date <= intnx('day', end, -42);
run; 

/* Check unique IDs */
proc sql;
    select count(distinct id) as unique_ids
    from diag_crc_final;
quit; /*n = 9981*/

/****************************************************************************************************************************/
/*Join with drug dataset*/

data drug;
    set myset.machado_atc; /*replace with the dataset shared with you*/
run; /*n = 8149*/

/*The next code is to output my required atc codes from the bigger drug dataset
  But since I have received my datacut the number of unique ids remains the same in both*/
data drug;
    set drug(rename=(date=rx_date));
    if atc in ('L01BA04', 'L01BC02', 'L01BC06', 'L01BC59', 
               'L01XA03', 'L01XC07', 'L01XC08', 'L01XC11', 
               'L01XC17', 'L01XX19');
run; 

/* Check unique IDs */
proc sql;
    select count(distinct id) as unique_ids
    from drug;
quit; /*n = 8149*/

/****************************************************************************************************************************/
/*Joining diag data*/
proc sql;
    create table drug_diag as
    select a.*, b.atc, b.rx_date
    from diag_crc_final as a
    left join drug as b
    on a.id = b.id;
quit;

/* Check unique IDs */
proc sql;
    select count(distinct id) as unique_ids
    from drug_diag;
quit; /*n = 9981*/

/****************************************************************************************************************************/
/* Filter to keep only instances where rx_date is after crc_date */
data drug_diag;
    set drug_diag;
    where missing(rx_date) or rx_date > crc_date;
run; 

/* Check unique IDs */
proc sql;
    select count(distinct id) as unique_ids
    from drug_diag;
quit; /*n = 9825*/

proc sort data=drug_diag;
    by id rx_date;
run;

/*Keep the rx_date closest to crc_date for each patient ********************************************/
data drug_diag_final;
    set drug_diag;
    by id;
    
    /* If rx_date is missing, output the row as-is */
    if missing(rx_date) then do;
        output;
        return;
    end;

    /* Calculate the difference in days between rx_date and crc_date */
    days_diff = abs(rx_date - crc_date);

    /* Retain the closest rx_date for each patient */
    retain closest_rx_date closest_atc min_days_diff;

    /* Reset at the start of each patient */
    if first.id then do;
        min_days_diff = days_diff;
        closest_rx_date = rx_date;
        closest_atc = atc;
    end;

    /* Update if a closer rx_date is found */
    else if days_diff < min_days_diff then do;
        min_days_diff = days_diff;
        closest_rx_date = rx_date;
        closest_atc = atc;
    end;

    /* Output only the record with the closest rx_date for each patient */
    if last.id then do;
        rx_date = closest_rx_date;
        atc = closest_atc;
        output;
    end;
    drop days_diff min_days_diff closest_rx_date closest_atc;
run; /*n=9825*/

/****************************************************************************************************************************/
/*Remove patients that were diagnosed with other cancers before their CRC diagnosis*/

proc sql;
    create table patients_no_prior_cancer as
    select distinct a.*
    from drug_diag_final as a
    left join diag as b
    on a.id = b.id
    where not (
        /* Check for ICD-10 codes starting with 'C' or 'D' */
        (substr(b.dx, 1, 1) in ('C', 'D'))
        or
        /* Check for ICD-9 codes in the range 140-239 */
        (b.dx between '140' and '239')
    )
    and b.date < a.crc_date;
quit;

/* Check unique IDs */
proc sql;
    select count(distinct id) as unique_ids
    from patients_no_prior_cancer;
quit; /*n = 9738*/

/****************************************************************************************************************************/
/* Remove patients diagnosed with other cancer between their CRC diagnosis and first treatment initiation */
proc sql;
    create table final_drug_diag as
    select distinct a.*
    from patients_no_prior_cancer as a
    left join diag as b
    on a.id = b.id
    where not (
        /* Check for ICD-10 codes starting with 'C' or 'D' */
        (substr(b.dx, 1, 1) in ('C', 'D'))
        or
        /* Check for ICD-9 codes in the range 140-239 */
        (b.dx between '140' and '239')
    )
    and b.date > a.crc_date
    and b.date < coalesce(a.rx_date, a.end); /* Use end if rx_date is missing */
quit;

/* Check unique IDs */
proc sql;
    select count(distinct id) as unique_ids
    from final_drug_diag;
quit; /* n = 9046 */

/****************************************************************************************************************************/
/*Join all demo characteristics*/
/*Bring in sex, birthdate and calculate age at diagnosis*/

data age_sex;
    set mydata.sd_table_demo_rev;
    keep id male birthdate;
run;

proc sort data=age_sex nodupkey;
    by id;
run;

proc sql;
    create table age_sex_crc as
    select a.*, b.male, b.birthdate
    from final_drug_diag as a
    left join age_sex as b
    on a.id = b.id;
quit;

data age_sex_crc;
    set age_sex_crc;
    /* Calculate age in years at diagnosis */
    age = intck('year', birthdate, crc_date) 
                       - (month(crc_date) < month(birthdate) 
                       or (month(crc_date) = month(birthdate) 
                       and day(crc_date) < day(birthdate)));
                       drop birthdate;
run;

/****************************************************************************************************************************/
/*Add income data*/
data income;
    set mydata.sd_table_demo_rev;
    keep id start end income;
run;

proc sql;
    create table crc_demo as
    select a.*, b.start as new_start, b.end as new_end, b.income
    from age_sex_crc as a
    left join income as b
    on a.id = b.id;
quit;

/*Keep income at diagnosis*/
data crc_demo_final;
    set crc_demo;
    /* Keep only rows where crc_date falls within the new_start and new_end date range */
    if crc_date >= new_start and crc_date <= new_end;
    drop new_start new_end;
run;

/****************************************************************************************************************************/
/*Remove patients less than 18 years at diagnosis*/
data crc_demo_adults;
    set crc_demo_final;
    /* Keep only patients who are 18 years or older at diagnosis */
    if age >= 18;
run; /*n=9041*/

/* Check unique IDs */
proc sql;
    select count(distinct id) as unique_ids
    from crc_demo_adults;
quit; /* n = 9041 */

/****************************************************************************************************************************/
/*Make comorbidity score*/
data comorbidity;
    set mydata.sd_table_diag;
run;

proc sql;
    create table crc_comorbidity as
    select a.id, a.crc_date, b.dx, b.date
    from crc_demo_adults as a
    left join comorbidity as b
    on a.id = b.id
    where b.date < a.crc_date;
quit;

/****************************************************************************************************************************/
/*USING THE CCI MACRO DEVELOPED BY NCI*/
/*Modified to fit this datset*/
%macro Simple_Comorbidity_Score(DATASET=crc_comorbidity, OUTFILE=Comorbidity_Score);

/* Define comorbid conditions */
%let conditions = acute_mi history_mi chf pvd cvd copd dementia paralysis diabetes diabetes_comp renal_disease
                  mild_liver_disease liver_disease ulcers rheum_disease aids;

data comorbidity_flags;
    set &DATASET;
    by id;

    /* Initialize comorbidity flags */
    array comorb_flags[*] acute_mi history_mi chf pvd cvd copd dementia paralysis diabetes diabetes_comp renal_disease
                        mild_liver_disease liver_disease ulcers rheum_disease aids;
    do i = 1 to dim(comorb_flags);
        comorb_flags[i] = 0;
    end;

    /* Determine comorbidities based on ICD codes using substr function */
    if substr(dx, 1, 3) = '410' or dx = 'I21' or dx = 'I22' then acute_mi = 1;               /* Acute MI */
    if substr(dx, 1, 3) = '412' or dx = 'I252' then history_mi = 1;                          /* History MI */
    if substr(dx, 1, 3) = '428' or dx = 'I50' or dx in ('I099', 'I110', 'I130', 'I132', 'I255') then chf = 1;  /* CHF */
    if substr(dx, 1, 3) = '440' or dx in ('I70', 'I71', '0930', 'V434', '5571') then pvd = 1; /* PVD */
    if substr(dx, 1, 3) = '430' or dx = 'G45' or substr(dx, 1, 2) = 'I6' then cvd = 1;       /* CVD */
    if substr(dx, 1, 3) = '490' or dx = 'J40' then copd = 1;                                 /* COPD */
    if substr(dx, 1, 3) = '290' or dx in ('F051', 'G30') then dementia = 1;                  /* Dementia */
    if substr(dx, 1, 4) = '3341' or dx in ('G81', 'G82', '342', 'G041') then paralysis = 1;  /* Paralysis */
    if (substr(dx, 1, 3) = '250' or dx in ('E10', 'E11')) and not (dx = '2504' or dx = 'E14') then diabetes = 1; /* Diabetes */
    if dx in ('2504', '2505', 'E10', 'E11') then diabetes_comp = 1;                          /* Diabetes Complications */
    if substr(dx, 1, 3) = '585' or dx in ('N18', 'N19') then renal_disease = 1;              /* Renal Disease */
    if substr(dx, 1, 3) = '070' or dx in ('K73', 'K74') then mild_liver_disease = 1;         /* Mild Liver Disease */
    if substr(dx, 1, 4) = '4560' or substr(dx, 1, 4) = '5722' or dx = 'K70' then liver_disease = 1; /* Severe Liver Disease */
    if substr(dx, 1, 3) = '531' or substr(dx, 1, 3) = 'K25' then ulcers = 1;                 /* Peptic Ulcer Disease */
    if substr(dx, 1, 3) = '714' or dx in ('M05', 'M06', 'M32') then rheum_disease = 1;       /* Rheumatic Disease */
    if substr(dx, 1, 3) = '042' or dx in ('B20', 'B21', 'B22') then aids = 1;                /* AIDS */

    /* Only keep distinct patient ID with comorbidity flags */
    if last.id;
    keep id acute_mi history_mi chf pvd cvd copd dementia paralysis diabetes diabetes_comp renal_disease
         mild_liver_disease liver_disease ulcers rheum_disease aids;
run;

/* Calculate Charlson score */
data &OUTFILE;
    set comorbidity_flags;

    /* Calculate Charlson score */
    cci =
        1 * (acute_mi or history_mi) +
        1 * (chf) +
        1 * (pvd) +
        1 * (cvd) +
        1 * (copd) +
        1 * (dementia) +
        2 * (paralysis) +
        1 * (diabetes and not diabetes_comp) +
        2 * (diabetes_comp) +
        2 * (renal_disease) +
        1 * (mild_liver_disease and not liver_disease) +
        3 * (liver_disease) +
        1 * (ulcers) +
        1 * (rheum_disease) +
        6 * (aids);

    /* Keep final output */
    keep id cci acute_mi history_mi chf pvd cvd copd dementia paralysis diabetes diabetes_comp renal_disease
         mild_liver_disease liver_disease ulcers rheum_disease aids;
run;

%mend Simple_Comorbidity_Score;

/* Run the macro with the specified dataset */
%Simple_Comorbidity_Score(DATASET=crc_comorbidity, OUTFILE=comorbidity_score);

/****************************************************************************************************************************/
/*Join comorbidity score with crc data*/
proc sql;
    create table crc_cohort as
    select a.*, b.cci
    from crc_demo_adults as a
    left join comorbidity_score as b
    on a.id = b.id;
quit;

/****************************************************************************************************************************/
/*Final measure*/
data crc_cohort;
    set crc_cohort;

    /* Calculate DTI (diagnosis-to-treatment interval) in days */
    dti = rx_date - crc_date;

    /* Create within_time column: 1 if DTI is <= 42 days, else 0. If DTI is missing, set within_time to 0 */
    if missing(dti) then within_time = 0;
    else within_time = (dti <= 42);
run;

/****************************************************************************************************************************/
/*VALIDITY CHECKS*********************************************************************/

/*Looking at age at diagnosis trend in the cohort****************************************/
/* Create age groups in a new dataset */
data crc_age_groups;
    set crc_cohort;
    length age_group $5;  /* Adjusting to ensure space for the longest string "70-79" */
    /* Define age groups */
    if age < 50 then age_group = '<50';
    else if age >= 50 and age < 60 then age_group = '50-59';  /* Corrected the logic */
    else if age >= 60 and age < 70 then age_group = '60-69';
    else if age >= 70 and age < 80 then age_group = '70-79';
    else age_group = '80+';
run;

/* Calculate frequency of CRC diagnoses by age group */
proc freq data=crc_age_groups;
    tables age_group ;
    title "Frequency of CRC Diagnoses by Age Group";
run;
/*17% patients are <50 years old. This is in line with the epidemiology of CRC*/

/*Patients with DTI > 12 weeks**********************************************************************************/
proc print data=crc_cohort;
    where dti > 84;
    var id crc_date rx_date dti within_time;
    title "Cases with DTI Exceeding 12 Weeks (Potential Outliers)";
run;

/*Make datsets with DTI > 12 weeks and missing dti*/
data dti_over_12weeks dti_missing;
    set crc_cohort;
    
    /* Output records with DTI > 12 weeks to dti_over_12weeks */
    if dti > 84 then output dti_over_12weeks;
    
    /* Output records with missing DTI to dti_missing */
    else if missing(dti) then output dti_missing;
run;

/*Note: We might want to remove these patients from the denominator
  while calculating proportion within time
  As we can assume that these cases probably received radiotherapy/surgery prior to chemo,
  or have no chemo data as they were ineligible or did not choose to take chemo/*
  
/*Create a combined dataset with IDs to exclude from the validity check*/
data exclude_ids;
    set dti_over_12weeks dti_missing;
    keep id;
run;

/*Remove these IDs from crc_cohort */
proc sql;
    create table crc_cohort_excl as
    select *
    from crc_cohort
    where id not in (select id from exclude_ids);
quit;

/****************************************************************************************************************************/
/*Evaluating timeliness of the healthcare system*/

/*Depending on whether or not exclusion is assumed the measure can 
use the crc_cohort or crc_cohort_excl datasets*/
/* Summary statistics for the full cohort */
proc sql;
    title "Summary Statistics: Proportion of Patients Receiving Treatment Within 6 Weeks (Full Cohort)";
    select within_time,
           count(*) as n format=8.,
           (count(*) * 100 / (select count(*) from crc_cohort)) as percent format=8.2
    from crc_cohort
    group by within_time;
quit;

/* Summary statistics for the cohort after exclusion */
proc sql;
    title "Summary Statistics: Proportion of Patients Receiving Treatment Within 6 Weeks (After Exclusion)";
    select within_time,
           count(*) as n format=8.,
           (count(*) * 100 / (select count(*) from crc_cohort_excl)) as percent format=8.2
    from crc_cohort_excl
    group by within_time;
quit;

/****************************************************************************************************************************/
/*Checking predictive validity of the measure within time*/
/* Create a variable to indicate survival time capped at 2 years (730 days) */
/* Include all patients in the survival analysis ****************************************************/
data crc_cohort_full_2yr_survival;
    set crc_cohort;

    /* Calculate survival time for patients with rx_date */
    if not missing(rx_date) then do;
        if end - rx_date > 730 then survival_time_2yr = 730;
        else survival_time_2yr = end - rx_date;
    end;
    /* For patients without rx_date, use coverage_end to calculate survival time */
    else do;
        survival_time_2yr = end - crc_date;
        if survival_time_2yr > 730 then survival_time_2yr = 730;
    end;

    /* Create an event indicator for death within 2 years */
    death_2yr = (death = 1 and survival_time_2yr <= 730);
run;

/* Conduct survival analysis for 2-year survival using PROC PHREG on the full cohort*/
proc phreg data=crc_cohort_full_2yr_survival;
    class within_time (ref='0'); 

    /* Specify survival time capped at 2 years and 2-year death indicator */
    model survival_time_2yr * death_2yr(0) = within_time / ties=efron;

    /* Hazard Ratio for treatment timeliness */
    hazardratio 'Within 6 Weeks vs. After 6 Weeks' within_time;
    title "2-Year Survival Analysis: Effect of Treatment Timeliness on Survival Outcomes (Full Cohort)";
run;

/*The hazard ratio of 0.404 for within_time suggests that patients who received timely treatment
 have a 59.6% lower hazard of dying within 2 years compared to those who received 
 treatment after 6 weeks. However, this difference is not statistically significant, as indicated
 by the high p-value (0.3646).*/

/* Not including all patients in the survival analysis ****************************************************/
data crc_cohort_2yr_survival;
    set crc_cohort_excl;

    /* Calculate time from treatment initiation (rx_date) to either 2 years or coverage_end */
    if end - rx_date > 730 then survival_time_2yr = 730;
    else survival_time_2yr = end - rx_date;

    /* Create an event indicator for death within 2 years */
    death_2yr = (death = 1 and (end - rx_date) <= 730);
run;

/*Conduct survival analysis for 2-year survival using PROC PHREG after exclusion*/
proc phreg data=crc_cohort_2yr_survival;
    class within_time (ref='0'); /* Reference group is '0' (treatment not within 6 weeks) */
    
    /* Specify survival time capped at 2 years and 2-year death indicator */
    model survival_time_2yr * death_2yr(0) = within_time / ties=efron;
    
    /* Hazard Ratio for treatment timeliness */
    hazardratio 'Within 6 Weeks vs. After 6 Weeks' within_time;
    title "2-Year Survival Analysis: Effect of Treatment Timeliness on Survival Outcomes (After Exclusion)";
run;

/*The hazard ratio of 0.749 for within_time suggests that patients who received timely treatment  
 have a 25.1% lower hazard (or risk) of dying within 2 years compared to those who received treatment 
 after 6 weeks. However, this difference is not statistically significant, as shown by the high 
 p-value (0.8021). probably due to the low sample size and other rescrictions of the data*/

/****************************************************************************************************************************/
/*Looking at distributipn of patients in the within time vs not within time categories*/
/* Create categories based on CCI scores full cohort*/
data crc_cohort_categorized;
    set crc_cohort;
    length cci_category $8; 
    if cci >= 1 and cci <= 2 then cci_category = 'Mild';
    else if cci >= 3 and cci <= 4 then cci_category = 'Moderate';
    else if cci >= 5 then cci_category = 'Severe';
    else cci_category = 'None'; /* For CCI scores of 0 or missing */
run;

/* Frequency distribution for visualization */
proc report data=crc_cohort_categorized nowd;
    column cci_category within_time, (n pctn);
    define cci_category / group 'CCI Category';
    define within_time / across 'Within Time (Full Cohort)' format=within_time_fmt.;
    define n / 'Count' f=comma8.;
    define pctn / 'Percent' f=percent8.2;

    /* Compute custom combined 'n(%)' */
    compute pctn;
        pctn = cats(put(n, comma8.), ' (', put(pctn, percent8.2), ')');
    endcomp;
    rbreak after / summarize;
    where within_time in (0, 1);
    rbreak after / summarize style=[font_weight=bold];
    title "Distribution of Within Time by CCI";
run;

/****************************************************************************************************************************/
/* Create categories based on CCI scores after exclusion*/
data crc_cohort_categorized;
    set crc_cohort_excl;
    length cci_category $8; 
    if cci >= 1 and cci <= 2 then cci_category = 'Mild';
    else if cci >= 3 and cci <= 4 then cci_category = 'Moderate';
    else if cci >= 5 then cci_category = 'Severe';
    else cci_category = 'None'; /* For CCI scores of 0 or missing */
run;

/* Frequency distribution for visualization */
proc report data=crc_cohort_categorized nowd;
    column cci_category within_time, (n pctn);
    define cci_category / group 'CCI Category';
    define within_time / across 'Within Time (After Exclusion)' format=within_time_fmt.;
    define n / 'Count' f=comma8.;
    define pctn / 'Percent' f=percent8.2;

    /* Compute custom combined 'n(%)' */
    compute pctn;
        pctn = cats(put(n, comma8.), ' (', put(pctn, percent8.2), ')');
    endcomp;
    rbreak after / summarize;
    where within_time in (0, 1);
    rbreak after / summarize style=[font_weight=bold];
    title "Distribution of Within Time by CCI";
run;

/****************************************************************************************************************************/
/* Create categories based on sex from the 'male' variable using full cohort*/
data crc_cohort_categorized_sex;
    set crc_cohort;
    length sex_category $6;  /* Ensure enough space for category names */

    /* Categorize sex based on the 'male' variable */
    if male = 1 then sex_category = 'Male';
    else if male = 0 then sex_category = 'Female';
    else sex_category = 'Other'; /* This is optional, only if there are missing/other values */
run;

/* Frequency distribution for visualization based on sex */
proc report data=crc_cohort_categorized_sex nowd;
    column sex_category within_time, (n pctn);
    define sex_category / group 'Sex Category' width=8;
    define within_time / across 'Within Time (Full Cohort)' format=within_time_fmt.;
    define n / 'Count' f=comma8.;
    define pctn / 'Percent' format=percent8.2;

    /* Compute custom combined 'n(%)' */
    compute pctn;
        pctn = cats(put(n, comma8.), ' (', put(pctn, percent8.2), ')');
    endcomp;

    where within_time in (0, 1);
    rbreak after / summarize style=[font_weight=bold];
    title "Distribution of Within Time by Sex";
run;

/****************************************************************************************************************************/
/* Create categories based on sex from the 'male' variable using excluded cohort*/
data crc_cohort_categorized_sex;
    set crc_cohort_excl;
    length sex_category $6;  /* Ensure enough space for category names */

    /* Categorize sex based on the 'male' variable */
    if male = 1 then sex_category = 'Male';
    else if male = 0 then sex_category = 'Female';
    else sex_category = 'Other'; /* This is optional, only if there are missing/other values */
run;

/* Frequency distribution for visualization based on sex */
proc report data=crc_cohort_categorized_sex nowd;
    column sex_category within_time, (n pctn);
    define sex_category / group 'Sex Category' width=8;
    define within_time / across 'Within Time (After Exclusion)' format=within_time_fmt.;
    define n / 'Count' f=comma8.;
    define pctn / 'Percent' format=percent8.2;

    /* Compute custom combined 'n(%)' */
    compute pctn;
        pctn = cats(put(n, comma8.), ' (', put(pctn, percent8.2), ')');
    endcomp;

    where within_time in (0, 1);
    rbreak after / summarize style=[font_weight=bold];
    title "Distribution of Within Time by Sex";
run;

/****************************************************************************************************************************/
/* Create categories based on income levels full cohort */
data crc_cohort_categorized_income;
    set crc_cohort;
    length income_category $8;  /* Ensure enough space for category names */

    /* Categorize income based on the given scale */
    if income >= 1 and income <= 3 then income_category = 'Low';
    else if income >= 4 and income <= 6 then income_category = 'Moderate';
    else if income >= 7 and income <= 10 then income_category = 'High';
    else income_category = 'Undefined'; /* Include this to handle any unexpected values or missing data */
run;

/* Frequency distribution for visualization based on income */
proc report data=crc_cohort_categorized_income nowd;
    column income_category within_time, (n pctn);
    define income_category / group 'Income Category' width=10;
    define within_time / across 'Within Time (Full Cohort)' format=within_time_fmt.; /* You may need to define this format */
    define n / 'Count' f=comma8.;
    define pctn / 'Percent' format=percent8.2;

    /* Compute custom combined 'n(%)' */
    compute pctn;
        pctn = cats(put(n, comma8.), ' (', put(pctn, percent8.2), ')');
    endcomp;

    where within_time in (0, 1);
    rbreak after / summarize style=[font_weight=bold];
    title "Distribution of Within Time by Income Level";
run;

/****************************************************************************************************************************/
/* Create categories based on income levels excluded cohort */
data crc_cohort_categorized_income;
    set crc_cohort_excl;
    length income_category $8;  /* Ensure enough space for category names */

    /* Categorize income based on the given scale */
    if income >= 1 and income <= 3 then income_category = 'Low';
    else if income >= 4 and income <= 6 then income_category = 'Moderate';
    else if income >= 7 and income <= 10 then income_category = 'High';
    else income_category = 'Undefined'; /* Include this to handle any unexpected values or missing data */
run;

/* Frequency distribution for visualization based on income */
proc report data=crc_cohort_categorized_income nowd;
    column income_category within_time, (n pctn);
    define income_category / group 'Income Category' width=10;
    define within_time / across 'Within Time (After Exclusion)' format=within_time_fmt.; /* You may need to define this format */
    define n / 'Count' f=comma8.;
    define pctn / 'Percent' format=percent8.2;

    /* Compute custom combined 'n(%)' */
    compute pctn;
        pctn = cats(put(n, comma8.), ' (', put(pctn, percent8.2), ')');
    endcomp;

    where within_time in (0, 1);
    rbreak after / summarize style=[font_weight=bold];
    title "Distribution of Within Time by Income Level";
run;

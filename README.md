# Evaluating Timely Treatment for Colorectal Cancer in Canadian Healthcare

## Project Overview
This project assesses the timeliness of colorectal cancer (CRC) treatment in the Canadian healthcare system. Specifically, it evaluates whether patients receive treatment within six weeks (42 days) of diagnosis, an important benchmark for improving survival outcomes. The analysis uses a simulated dataset that represents administrative healthcare data to measure delays and identify potential disparities in treatment access.

## Dataset and Variables
The simulated dataset consists of multiple administrative files merged to capture patient demographics, diagnosis history, treatment initiation, and health outcomes.

### Key Data Sources:
- **sd_table_demo_rev**: Patient demographics, income, and healthcare coverage.
- **sd_table_death**: Healthcare coverage dates and mortality status.
- **sd_table_diag**: Diagnosis history, including CRC and comorbid conditions.
- **sd_table_drug**: Treatment data, including initiation dates and ATC drug codes for CRC therapies.
- **machado_atc.sas7bdat**: Processed dataset containing ATC-coded CRC treatments.

### Main Variables:
- `id`: Unique patient identifier.
- `sex`: Binary indicator (1=male, 0=female).
- `age`: Patient age at CRC diagnosis.
- `income`: Income decile (1=lowest, 10=highest).
- `crc_date`: Date of colorectal cancer diagnosis.
- `rx_date`: Start date of CRC treatment.
- `dti`: Diagnosis-to-treatment interval (days between diagnosis and treatment initiation).
- `within_time`: Binary variable indicating whether treatment was received within six weeks of diagnosis.
- `cci`: Charlson Comorbidity Index, representing patient health status based on comorbidities.
- `death`: Binary indicator (1=dead, 0=alive).

## Inclusion & Exclusion Criteria
### Inclusion:
- Patients diagnosed with CRC for the first time.
- Age ≥ 18 at the time of CRC diagnosis.
- Patients with at least two years of healthcare history before diagnosis.
- Patients diagnosed at least 42 days before their healthcare coverage ends.

### Exclusion:
- Patients with prior cancer diagnoses.
- Patients diagnosed with another cancer between CRC diagnosis and treatment initiation.

## Data Processing Steps
The analysis follows a structured pipeline using **SAS**:
1. **Data Cleaning & Filtering**  
   - Extract patients with CRC diagnoses.
   - Remove individuals with insufficient healthcare history.
   - Filter based on coverage dates.

2. **Merging and Feature Engineering**  
   - Join datasets on patient ID.
   - Compute diagnosis-to-treatment intervals (DTI).
   - Assign comorbidity scores using the Charlson Comorbidity Index.

3. **Validation & Quality Checks**  
   - **Face Validity**: Identifying outliers (e.g., patients with treatment delays exceeding 12 weeks).  
   - **Construct Validity**: Checking if CRC diagnosis rates align with expected epidemiological trends.  
   - **Predictive Validity**: Testing if timely treatment (within six weeks) is associated with better survival outcomes.

## Analytical Approach
- **Timeliness of Treatment**:  
  - Measure the proportion of patients treated within six weeks.
  - Compare distributions across sex, income, and comorbidity levels.

- **Survival Analysis**:  
  - Conduct **Cox Proportional Hazards (PROC PHREG)** regression to estimate the impact of timely treatment on two-year survival rates.

## Code Files
- `EPIB675-Machado-code.sas`: SAS script for data processing, cleaning, merging, and analysis.

## Results Summary
- A significant proportion of CRC patients experience delays in treatment initiation.
- Timely treatment is correlated with better survival outcomes, though statistical significance is affected by sample size constraints.
- Socioeconomic disparities (income levels) and comorbidities impact treatment timeliness.

## Limitations & Considerations
- Patients missing ATC codes might have undergone surgery or received palliative care instead of chemotherapy.
- Sample size constraints limit statistical power in survival analysis.
- Possible confounding factors (e.g., treatment preferences, cancer stage) are not fully accounted for.

## References
- Canadian Institute for Health Information, 2024.  
- Lee et al., BMJ, 2020.  
- Cone et al., JAMA Network Open, 2020.  

## Contributors
- **Michelle Machado**  
 

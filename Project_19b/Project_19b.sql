create database factless_db_19b;
create schema factless_db_19b.factless_schema;

use database factless_db_19b;
use schema factless_schema;

create or replace file format csv_format
type=csv
field_delimiter=','
skip_header=1
null_if=('null');

create stage factless_stage;

create table raw_doctor_roster(
shift_date date,
doctor_id varchar(10),
department_id varchar(10),
shift_type varchar(10)
);

create table raw_patient_journey(
encounter_id varchar(10),
patient_id varchar(10),
triage_date date,
admission_date date,
discharge_date date
);

create table raw_treatment_bills(
claim_id varchar(10),
encounter_id varchar(10),
patient_id varchar(10),
procedure_cost number(10,2),
insurance_discount_pct number(5,2),
copay_amount number(10,2)
);

copy into raw_doctor_roster
from @factless_stage/raw_doctor_roster.csv
file_format=csv_format;

copy into raw_patient_journey
from @factless_stage/raw_patient_journey.csv
file_format=(type=csv
field_optionally_enclosed_by='"'
skip_header=1
null_if=('NULL')
);

copy into raw_treatment_bills
from @factless_stage/raw_treatment_bills.csv
file_format=csv_format;

-- TASK 1: Factless Coverage Table Setup
create table FACTLESS_STAFF_COVERAGE(
shift_date date,
doctor_id varchar(10),
department_id varchar(10),
shift_type varchar(10)
);

insert into FACTLESS_STAFF_COVERAGE(shift_date,doctor_id,department_id,shift_type)
select shift_date,doctor_id,department_id,shift_type from raw_doctor_roster;

select count(*) as TOTAL_ROSTER_ROWS from  FACTLESS_STAFF_COVERAGE;
-- TOTAL_ROSTER_ROWS
-- 6

--TASK 2: Factless Coverage Analysis Query
select department_id,sum(case when shift_type='NIGHT' then 1 else 0 end) as night_shift_count 
from FACTLESS_STAFF_COVERAGE
where shift_date='2026-08-20' group by department_id having 
sum(case when shift_type='NIGHT' then 1 else 0 end)=0;

-- DEPARTMENT_ID	NIGHT_SHIFT_COUNT
-- DEP-20	        0

--TASK 3: Patient Lifecycle Accumulating Snapshot Table
create table ACT_PATIENT_ADMISSION_LIFECYCLE(
encounter_id varchar(10),
patient_id varchar(10),
triage_date date,
admission_date date,
discharge_date date,
triage_to_admit_days number,
length_of_stay_days number);

insert into ACT_PATIENT_ADMISSION_LIFECYCLE(encounter_id,patient_id,triage_date ,
admission_date,discharge_date ,triage_to_admit_days,length_of_stay_days)
select encounter_id,patient_id,triage_date ,admission_date, discharge_date,
datediff('day',triage_date,admission_date) as TRIAGE_TO_ADMIT_DAYS,
datediff('day',admission_date,discharge_date) as LENGTH_OF_STAY_DAYS
from raw_patient_journey;

select * from ACT_PATIENT_ADMISSION_LIFECYCLE;
-- ENCOUNTER_ID	PATIENT_ID	TRIAGE_DATE	ADMISSION_DATE	DISCHARGE_DATE	TRIAGE_TO_ADMIT_DAYS	LENGTH_OF_STAY_DAYS
-- ENC-701	PAT-901	2026-08-15	2026-08-15	2026-08-18	0	3
-- ENC-702	PAT-902	2026-08-16	2026-08-17	2026-08-22	1	5
-- ENC-703	PAT-903	2026-08-18	2026-08-18		null    0	null
-- ENC-704	PAT-904	2026-08-19	2026-08-20	2026-08-21	1	1
-- ENC-705	PAT-905	2026-08-20		null		null    null  null

select encounter_id,patient_id,triage_to_admit_days,length_of_stay_days from  ACT_PATIENT_ADMISSION_LIFECYCLE where discharge_date is not null;
-- ENCOUNTER_ID	PATIENT_ID	TRIAGE_TO_ADMIT_DAYS	LENGTH_OF_STAY_DAYS
-- ENC-701	PAT-901	0	3
-- ENC-702	PAT-902	1	5
-- ENC-704	PAT-904	1	1

-- TASK 4: Categorize Additive vs Non-Additive Billing Measures
create table FACT_TREATMENT_BILLING(
claim_id varchar(10),
encounter_id varchar(10),
patient_id varchar(10),
procedure_cost number(10,2),
insurance_discount_pct number(5,2),
copay_amount number(10,2),
net_charge number(10,2)
);

insert into FACT_TREATMENT_BILLING(
claim_id ,
encounter_id ,
patient_id ,
procedure_cost ,
insurance_discount_pct,
copay_amount ,
net_charge 
)
select claim_id ,
encounter_id ,
patient_id ,
procedure_cost ,
insurance_discount_pct,
copay_amount ,
(procedure_cost * (1 - insurance_discount_pct)) - copay_amount as net_charge
from raw_treatment_bills;

select * from FACT_TREATMENT_BILLING;
-- CLAIM_ID	ENCOUNTER_ID	PATIENT_ID	PROCEDURE_COST	INSURANCE_DISCOUNT_PCT	COPAY_AMOUNT	NET_CHARGE
-- CLM-301	ENC-701	PAT-901	 5000.00	    0.10	200.00	4300.00
-- CLM-302	ENC-702	PAT-902	 12000.00	    0.15	500.00	9700.00
-- CLM-303	ENC-702	PAT-902	 3500.00	    0.00	100.00	3400.00
-- CLM-304	ENC-704	PAT-904	 800.00	        0.05	50.00	710.00
select encounter_id,patient_id,procedure_cost,copay_amount,net_charge from FACT_TREATMENT_BILLING;
-- ENCOUNTER_ID	PATIENT_ID	PROCEDURE_COST	COPAY_AMOUNT	NET_CHARGE
--    ENC-701	PAT-901	         5000.00	 200.00	  4300.00
--    ENC-702	PAT-902       	12000.00	500.00	  9700.00
--    ENC-702	PAT-902	        3500.00	    100.00	  3400.00
--    ENC-704	PAT-904	        800.00	    50.00	  710.00

--TASK 5: Patient Billing Aggregation
select encounter_id,
sum(net_charge) as total_net_charge,
avg(procedure_cost) as avg_procedure_cost
from FACT_TREATMENT_BILLING group by encounter_id;
-- ENCOUNTER_ID	TOTAL_NET_CHARGE	AVG_PROCEDURE_COST
-- ENC-701	4300.00	    5000.00000000
-- ENC-702	13100.00	7750.00000000
-- ENC-704	710.00	    800.00000000

--TASK 6: Audit Untreated / Non-Billed Encounters
--Identify encounters in `FACT_PATIENT_ADMISSION_LIFECYCLE` that generated ZERO claims in `FACT_TREATMENT_BILLING`.
select  l.encounter_id,l.patient_id,' NO_CLAIMS_ISSUED' AS unbilled_status
from ACT_PATIENT_ADMISSION_LIFECYCLE l
left join  FACT_TREATMENT_BILLING b
on  l.encounter_id = b.encounter_id
where  b.encounter_id is null;
-- ENCOUNTER_ID	PATIENT_ID	UNBILLED_STATUS
-- ENC-703	PAT-903	 NO_CLAIMS_ISSUED
-- ENC-705	PAT-905	 NO_CLAIMS_ISSUED
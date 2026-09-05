create database Factless_db_19c;
create schema factless_schema;

use database Factless_db_19c;
use schema factless_schema;

create file format csv_format
type=csv
field_delimiter=','
skip_header=1
null_if=('NULL');

create stage factless_stage;

create table raw_wire_transfers (
txn_id VARCHAR(10),
txn_date DATE,
sender_acc VARCHAR(10),
receiver_acc VARCHAR(10),
amount NUMBER(10,2),
fee NUMBER(10,2),
currency_rate NUMBER(5,2),
auth_method VARCHAR(10),
risk_flag VARCHAR(10),
transfer_type VARCHAR(20)
);

create table raw_vault_cash (
    snapshot_date DATE,
    vault_id VARCHAR(10),
    currency_code VARCHAR(10),
    opening_balance NUMBER(10,2),
    closing_balance NUMBER(10,2),
    reserve_ratio_pct NUMBER(5,2)
);

create table raw_credit_lifecycles (
    app_id VARCHAR(10),
    submission_date DATE,
    underwrite_date DATE,
    risk_approval_date DATE,
    disbursement_date DATE
);

create table raw_audit_coverage (
    audit_year NUMBER,
    quarter VARCHAR(5),
    account_id VARCHAR(10),
    auditor_firm VARCHAR(10),
    compliance_status VARCHAR(10)
);


COPY INTO raw_wire_transfers
FROM @factless_stage/raw_wire_transfers.csv
FILE_FORMAT = csv_format;

COPY INTO raw_vault_cash
FROM @factless_stage/raw_vault_cash.csv
FILE_FORMAT = csv_format;

COPY INTO raw_credit_lifecycles
FROM @factless_stage/raw_credit_lifecycles.csv
FILE_FORMAT = csv_format;

COPY INTO raw_audit_coverage
FROM @factless_stage/raw_audit_coverage.csv
FILE_FORMAT = csv_format;

--TASK 1: Advanced Junk Dimension Construction
create table DIM_WIRE_ATTRIBUTES(
attribute_sk number,
auth_method VARCHAR(10),
risk_flag VARCHAR(10),
transfer_type VARCHAR(20)
);

insert into DIM_WIRE_ATTRIBUTES(attribute_sk,auth_method ,risk_flag ,transfer_type)
select row_number() over(order by first_txn_id), auth_method ,risk_flag ,transfer_type from 
(select auth_method ,risk_flag ,transfer_type,min(txn_id) as first_txn_id from raw_wire_transfers
group by auth_method ,risk_flag ,transfer_type);

select * from DIM_WIRE_ATTRIBUTES;
-- ATTRIBUTE_SK	AUTH_METHOD	RISK_FLAG	TRANSFER_TYPE
-- 1	2FA	        LOW	    DOMESTIC
-- 2	BIOMETRIC	HIGH	INTERNATIONAL
-- 3	HARD_TOKEN	HIGH	INTERNATIONAL
-- 4	BIOMETRIC	MEDIUM	INTERNATIONAL

--TASK 2: Wire Transfer Fact Table & Currency Normalized Measures
create table FACT_WIRE_TRANSFERS(
txn_id VARCHAR(10),
txn_date DATE,
sender_acc VARCHAR(10),
receiver_acc VARCHAR(10),
attribute_sk number,
amount NUMBER(10,2),
fee NUMBER(10,2),
currency_rate NUMBER(5,2),
base_amount_usd number(10,2),
net_transfer_val number(10,2)
);

insert into FACT_WIRE_TRANSFERS(
txn_id ,
txn_date ,
sender_acc ,
receiver_acc ,
attribute_sk ,
amount ,
fee ,
currency_rate ,
base_amount_usd ,
net_transfer_val)
select r.txn_id ,
r.txn_date ,
r.sender_acc ,
r.receiver_acc ,
d.attribute_sk ,
r.amount ,
r.fee ,
r.currency_rate ,
(r.amount*r.currency_rate) as base_amount_usd ,
(r.amount*r.currency_rate)-r.fee as net_transfer_val
from raw_wire_transfers r join DIM_WIRE_ATTRIBUTES d
on r.auth_method=d.auth_method and
r.risk_flag=d.risk_flag and
r.transfer_type=d.transfer_type;

select txn_id,sender_acc,attribute_sk,base_amount_usd,net_transfer_val from FACT_WIRE_TRANSFERS;
-- TXN_ID	SENDER_ACC	ATTRIBUTE_SK	BASE_AMOUNT_USD	NET_TRANSFER_VAL
-- TXN-9001	ACC-101	 1	100000.00	99950.00
-- TXN-9002	ACC-102	 2	382500.00	382250.00
-- TXN-9003	ACC-103	 1	75000.00	74970.00
-- TXN-9004	ACC-101	 3	1104000.00	1103500.00
-- TXN-9005	ACC-104	 1	25000.00	24985.00
-- TXN-9006	ACC-105	 4	510000.00	509700.00
-- TXN-9007	ACC-102	 1	89000.00	88960.00

--TASK 3: Periodic Vault Snapshot & Non-Additive Reserve Validation
create table FACT_VAULT_CASH_SNAPSHOT(
snapshot_date date,
vault_id varchar(10),
currency_code varchar(10),
opening_balance number(10,2),
closing_balance number(10,2),
reserve_ratio_pct number(5,2),
net_daily_change number(10,2)
);

insert into  FACT_VAULT_CASH_SNAPSHOT(
snapshot_date ,
vault_id ,
currency_code ,
opening_balance ,
closing_balance ,
reserve_ratio_pct ,
net_daily_change )
select snapshot_date ,
vault_id,
currency_code,
opening_balance,
closing_balance,
reserve_ratio_pct,
(closing_balance-opening_balance) as net_daily_change 
from raw_vault_cash;

select snapshot_date,sum(opening_balance) as TOTAL_OPENING_USD_EQ,
sum(closing_balance) as TOTAL_CLOSING_USD_EQ from FACT_VAULT_CASH_SNAPSHOT group by snapshot_date;
-- SNAPSHOT_DATE	TOTAL_OPENING_USD_EQ	TOTAL_CLOSING_USD_EQ
-- 2026-08-24	16000000.00	   16100000.00
-- 2026-08-25	16100000.00	   16400000.00
  -- * `UNDERWRITE_DAYS` (`underwrite_date - submission_date`)
  -- * `RISK_APPROVAL_DAYS` (`risk_approval_date - underwrite_date`)
  -- * `DISBURSEMENT_DAYS` (`disbursement_date - risk_approval_date`)
  -- * `TOTAL_CYCLE_DAYS` (`disbursement_date - submission_date`)
create table FACT_CREDIT_APPROVAL_LIFECYCLE(
app_id varchar(10),
submission_date date,
underwrite_date date,
risk_approval_date date,
disbursement_date date,
underwrite_days number,
risk_approval_days  number,
disbursement_days number,
total_cycle_days number
);

insert into FACT_CREDIT_APPROVAL_LIFECYCLE(
app_id ,
submission_date,
underwrite_date ,
risk_approval_date,
disbursement_date ,
underwrite_days ,
risk_approval_days  ,
disbursement_days,
total_cycle_days)
select app_id ,
submission_date,
underwrite_date ,
risk_approval_date,
disbursement_date ,
datediff('day',underwrite_date,submission_date) as underwrite_days ,
datediff('day',risk_approval_date,underwrite_date) as risk_approval_days ,
datediff('day',disbursement_date - risk_approval_date) as disbursement_days,
datediff('day',disbursement_date - submission_date) as total_cycle_days
from raw_credit_lifecycles;

select app_id,underwrite_days ,risk_approval_days ,disbursement_days,total_cycle_days
from FACT_CREDIT_APPROVAL_LIFECYCLE where disbursement_date is not null;
-- APP_ID	UNDERWRITE_DAYS	RISK_APPROVAL_DAYS	DISBURSEMENT_DAYS	TOTAL_CYCLE_DAYS
-- APP-401	2	2	2	6
-- APP-402	3	4	3	10


-- TASK 5: Bottleneck Stage Identification in Credit Pipeline
select app_id,
submission_date ,
case when disbursement_date is null and risk_approval_date is not null then 'AWAITING_DISBURSAL'
     when disbursement_date is null and risk_approval_date is null
     and underwrite_date is not null then 'AWAITING_RISK_AUTH' 
     when disbursement_date is null and risk_approval_date is null
     and underwrite_date is null then 'AWAITING_UNDERWRITE'
end as CURRENT_BOTTLENECK from FACT_CREDIT_APPROVAL_LIFECYCLE where disbursement_date is null;
);

-- APP_ID	SUBMISSION_DATE	CURRENT_BOTTLENECK
-- APP-403	2026-08-10	AWAITING_DISBURSAL
-- APP-404	2026-08-15	AWAITING_RISK_AUTH
-- APP-405	2026-08-20	AWAITING_UNDERWRITE

--TASK 6: Factless Audit Coverage Matrix Analysis
create table FACTLESS_COMPLIANCE_AUDIT_COVERAGE(
audit_year NUMBER,
quarter VARCHAR(5),
account_id VARCHAR(10),
auditor_firm VARCHAR(10),
compliance_status VARCHAR(10)
);

insert into FACTLESS_COMPLIANCE_AUDIT_COVERAGE(
audit_year ,
quarter ,
account_id ,
auditor_firm,
compliance_status) select audit_year ,
quarter ,
account_id ,
auditor_firm,
compliance_status from raw_audit_coverage;

select f.sender_acc as account_id,count(distinct f.txn_id) as HIGH_RISK_TXN_COUNT,
case when count(a.account_id)>0 then 'AUDITED'
else 'NEVER AUDITED'
end as COMPLIANCE_STATUS from FACT_WIRE_TRANSFERS f join DIM_WIRE_ATTRIBUTES d
on f.attribute_sk=d.attribute_sk left join FACTLESS_COMPLIANCE_AUDIT_COVERAGE a
on f.sender_acc=a.account_id and a.audit_year=2026
where  d.risk_flag='HIGH' group by f.sender_acc order by f.sender_acc;
-- ACCOUNT_ID	HIGH_RISK_TXN_COUNT	COMPLIANCE_STATUS
-- ACC-101	1	AUDITED
-- ACC-102	1	AUDITED


-- TASK 7: Risk Profile Revenue Cross-Analysis
-- - Join `FACT_WIRE_TRANSFERS` with `DIM_WIRE_ATTRIBUTES` to aggregate total fees and transaction volume by `RISK_FLAG` and `TRANSFER_TYPE`.
select d.risk_flag,d.transfer_type,count(f.txn_id) as total_txns,sum(f.fee) as total_fees,
sum(f.base_amount_usd) as total_volume_usd from FACT_WIRE_TRANSFERS f join DIM_WIRE_ATTRIBUTES d
on f.attribute_sk=d.attribute_sk group by  d.risk_flag,d.transfer_type order by d.risk_flag;

-- TASK 8: Multi-Fact Comprehensive Reconciliation Audit
-- - Write a unified audit query verifying gross totals across Transaction Facts, Periodic Snapshots, and Accumulating Snapshots.
select
(select sum(base_amount_usd) from FACT_WIRE_TRANSFERS) as TOTAL_WIRE_VOL_USD,
(select sum(closing_balance) from FACT_VAULT_CASH_SNAPSHOT where snapshot_date=(select max(snapshot_date) from FACT_VAULT_CASH_SNAPSHOT)) as VAULT_CLOSING_USD,
(select count(*) from FACT_CREDIT_APPROVAL_LIFECYCLE where disbursement_date is not null) as COMPLETED_LOAN_APPS,
case when TOTAL_WIRE_VOL_USD = 2285500.00
    and VAULT_CLOSING_USD = 16400000.00
    and COMPLETED_LOAN_APPS = 2
    then true else false
end as  AUDIT_SANITY_FLAG;
-- TOTAL_WIRE_VOL_USD	VAULT_CLOSING_USD	COMPLETED_LOAN_APPS 	AUDIT_SANITY_FLAG
--        2285500.00	16400000.00	                   2	          TRUE
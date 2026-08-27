create database medallion_db;
create schema med_schema;

use database medallion_db;
use schema med_schema;

create file format json_format
type=json
strip_outer_array=false;

create stage lakehouse;
--TASK 1: Bronze Layer Setup & Ingestion
-- Create table `BRONZE_PAYMENT_PAYLOADS` and ingest all 8 raw JSON records.
create table bronze(
raw_txn variant
);

copy into bronze from @lakehouse/raw_bronze.json
file_format=(format_name=json_format);

select * from bronze;

select count(*) as total_bronze_records_ct from bronze;
-- TOTAL_BRONZE_RECORDS_CT
-- 8

--TASK 2: Silver Layer ETL & Fee Computations
create table silver(
txn_id varchar(20),
merchant_id number,
merchant_name varchar(30),
card_number varchar(19),
gross_amount number(12,2),
fee_pct number(5,2),
processing_fee number(12,2),
net_settlement_amount number(12,2),
status varchar(20)
);

insert into silver(txn_id,merchant_id,merchant_name,card_number,
gross_amount,fee_pct,processing_fee,net_settlement_amount,status)
select raw_txn:txn_id::varchar,
raw_txn:merchant_id::number,
raw_txn:merchant_name::varchar,
'XXXX-XXXX-XXXX-' || right(raw_txn:card_number::varchar,4),
raw_txn:amount::number(12,2),
raw_txn:fee_pct::number(5,2),
--processing_Fee
raw_txn:amount::number(12,2)*
raw_txn:fee_pct::number(5,2)/100,
--net_settlement_amt
raw_txn:amount::number(12,2)-
(
raw_txn:amount::number(12,2)*
raw_txn:fee_pct::number(5,2)/100
),
raw_txn:status::varchar from bronze;

select * from silver;
-- TXN-901	301	TechZone	XXXX-XXXX-XXXX-4444	50000.00	2.50	1250.00	48750.00	APPROVED
-- TXN-902	302	StyleHub	XXXX-XXXX-XXXX-3333	12000.00	3.00	360.00	11640.00	APPROVED
-- TXN-903	301	TechZone	XXXX-XXXX-XXXX-4444	25000.00	2.50	625.00	24375.00	PENDING
-- TXN-904	303	FreshMart	XXXX-XXXX-XXXX-3333	8500.00	1.80	153.00	8347.00	APPROVED
-- TXN-905	302	StyleHub	XXXX-XXXX-XXXX-3333	45000.00	3.00	1350.00	43650.00	DECLINED
-- TXN-906	301	TechZone	XXXX-XXXX-XXXX-4444	150000.00	2.50	3750.00	146250.00	APPROVED
-- TXN-907	303	FreshMart	XXXX-XXXX-XXXX-3333	3200.00	1.80	57.60	3142.40	APPROVED
-- TXN-908	302	StyleHub	XXXX-XXXX-XXXX-3333	67000.00	3.00	2010.00	64990.00	PENDING

create table gold (
merchant_id number,
merchant_name varchar(50),
total_approved_gross number(12,2),
total_gateway_fees number(12,2),
total_net_payout number(12,2),
approved_count number
);

insert into gold(merchant_id,merchant_name,total_approved_gross,
total_gateway_fees,total_net_payout,approved_count)
select  merchant_id,merchant_name,sum(gross_amount),
sum(processing_fee),
sum(net_settlement_amount),
count(*) from silver
where status='APPROVED' group by merchant_id,merchant_name;

select * from gold order by merchant_id;
-- 301	TechZone	200000.00	5000.00	195000.00	2
-- 302	StyleHub	12000.00	360.00	11640.00	1
-- 303	FreshMart	11700.00	210.60	11489.40	2


-- TASK 4: Data Corruption Simulation & Time-Travel Inspection
-- 1. Run UPDATE setting `TechZone` approved records to `STATUS = 'REFUNDED'`.
update silver set status='REFUNDED' where merchant_name='TechZone' and status='APPROVED';
-- number of rows updated
-- 2

select txn_id, merchant_name, gross_amount, status from  silver
where merchant_name = 'TechZone' order by txn_id;
-- TXN-901	TechZone	50000.00	REFUNDED
-- TXN-903	TechZone	25000.00	PENDING
-- TXN-906	TechZone	150000.00	REFUNDED

select txn_id, merchant_name, gross_amount, status
from silver at (offset => -600)
where merchant_name = 'TechZone'
order by txn_id;
-- TXN-901	TechZone	50000.00	APPROVED
-- TXN-903	TechZone	25000.00	PENDING
-- TXN-906	TechZone	150000.00	APPROVED

-- TASK 5: Time-Travel Recovery Execution
-- - Revert corrupted statuses back to `APPROVED` using Time-Travel data.
update silver set status='APPROVED'
where merchant_name='TechZone' and status='REFUNDED';
-- number of rows updated
-- 2

select merchant_name,
count_if(status='APPROVED') as approved_count,
count_if(status='REFUNDED') as refunded_count,
from silver where merchant_name='TechZone' group by merchant_name;

-- MERCHANT_NAME   APPROVED_COUNT   REFUNDED_COUNT
-- TechZone            2                0

-- TASK 6: End-to-End Pipeline Reconciliation Audit
-- - Write a reconciliation audit query confirming gross totals across all three layers.
select (select sum(raw_txn:amount::number(12,2)) from bronze) as  bronze_gross_sum,
(select sum(gross_amount) from silver) as silver_gross_sum,
(select sum(total_approved_gross) from gold) as gold_gross_sum,
case when (select sum(raw_txn:amount::number(12,2)) from bronze)
           =(select sum(gross_amount) from silver)
    then true 
    else false
end as data_match_flag;
-- BRONZE_GROSS_SUM      BRONZE_GROSS_SUM   GOLD_GROSS_SUM    GOLD_GROSS_SUM
-- 360700.00                360700.00           223700.0           TRUE

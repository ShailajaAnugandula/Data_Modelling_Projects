-- TASK 1: Bronze Data Lake Ingestion & Schema-on-Read Exploration
create database LOGISTICS_LAKEHOUSE_DB;
create schema FLEET_CORE;

use database LOGISTICS_LAKEHOUSE_DB;
use schema FLEET_CORE;

create file format json_format
type=json
strip_outer_array=false;

create stage datalake;

create table bronze(
ingest_id number autoincrement,
raw_payload variant,
recorded_at timestamp
);

copy into bronze (raw_payload)
from @datalake/payload.json
file_format=(format_name=json_format);

select count(*) as total_bronze_records from bronze;

-- TASK 2: Dead-Letter Queue Quarantine Strategy
create table quarantine(
quarantine_id number autoincrement,
raw_record_text varchar,
reason varchar(30)
);

create file format text_format
type=csv
field_delimiter=none
record_delimiter='\n';

select $1 as raw_record_text,
try_parse_json($1) as parsed_json
from @datalake/bad_payload.json
(file_format => text_format);
-- RAW_RECORD_TEXT                                     PARSED_JSON
-- {"MALFORMED_IOT_SENSOR_BINARY_BURST_DATA_ERR"}       null

insert into quarantine(raw_record_text,reason)
select $1,'MALFORMED_JSON_BODY'
from @datalake/bad_payload.json
(file_format=>text_format)
where try_parse_json($1) is null;
-- number of rows inserted
-- 1

select * from quarantine;

-- QUARANTINE_ID            RAW_RECORD_TEXT                                  REASON
--       1          {"MALFORMED_IOT_SENSOR_BINARY_BURST_DATA_ERR"}     MALFORMED_JSON_BODY

-- TASK 3: Silver Layer ETL — Schema-on-Write Modeling & Computations
create table  silver(
shipment_id varchar(20),
payload_id varchar(20),
vehicle_id varchar(20),
dest_country varchar(20),
declared_value number(12,2),
duty_pct number(5,2),
duty_amount_due number(12,2),
border_code varchar(20),
clearance_status varchar(20)
);

insert into silver(shipment_id ,payload_id ,vehicle_id ,dest_country,declared_value ,
duty_pct ,duty_amount_due,border_code ,clearance_status)
select raw_payload:data:shipment_id::varchar,
raw_payload:payload_id::varchar,
raw_payload:data:vehicle_id::varchar,
raw_payload:data:destination_country::varchar,
raw_payload:data:declared_value::number(12,2),
raw_payload:data:duty_pct::number(5,2),

raw_payload:data:declared_value::number(12,2)*
raw_payload:data:duty_pct::number(5,2)/100,


raw_payload:data:border_clearance_code::varchar,
raw_payload:data:clearance_status::varchar
from bronze where raw_payload:payload_type::varchar = 'CUSTOMS';

select * from silver;
-- SHIPMENT_ID   PAYLOAD_ID   VEHICLE_ID    DEST_COUNTRY   DECLARED_VALUE   DUTY_PCT    DUTY_AMOUNT_DUE   BORDER_CODE   CLEARANCE_STATUS
--     SHP-5001	PL-802	    TRK-9001	     CAN	    85000.00	    5.00	       4250.00		    null          CLEARED
--     SHP-5002	PL-804	    TRK-9002	     MEX	    42000.00	    7.50	       3150.00		    null           CLEARED
--     SHP-5003	PL-806	    TRK-9003	     CAN	    120000.00	    4.00	       4800.00	    FAST_PASS_01     	CLEARED
--     SHP-5004	PL-807	    TRK-9001       	 MEX	    15000.00	    7.50	      1125.00		    null          HELD_INSPECTION

-- TASK 4: Gold Layer Strategic Aggregations
create table gold(
dest_country varchar(20),
total_cleared_val number(12,2),
total_duties_collected number(12,2),
avg_duty_rate_pct number(5,2),
cleared_shipments number
);

insert into gold(dest_country,total_cleared_val ,total_duties_collected ,
avg_duty_rate_pct ,cleared_shipments)
select dest_country,sum(declared_value),sum(duty_amount_due),avg(duty_pct),count(clearance_status)
from silver where clearance_status='CLEARED' group by dest_country;

select * from gold;

--DEST_COUNTRY  TOTAL_CLEARED_VAL   TOTAL_DUTIES_COLLECTED  AVG_DUTY_RATE_PCT  CLEARED_SHIPMENTS
--       CAN	   205000.00	           9050.00	           4.50	             2
--       MEX	   42000.00	               3150.00	           7.50	             1

-- TASK 5: Disaster Recovery via Snowflake Time-Travel Auditing
update silver set clearance_status='REJECTED' where dest_country='CAN' and clearance_status='CLEARED';
-- number of rows updated
-- 2
select * from silver;
-- SHP-5002	PL-804	TRK-9002	MEX	42000.00	7.50	3150.00	  null 	CLEARED
-- SHP-5001	PL-802	TRK-9001	CAN	85000.00	5.00	4250.00	  null	REJECTED
-- SHP-5003	PL-806	TRK-9003	CAN	120000.00	4.00	4800.00	FAST_PASS_01	REJECTED
-- SHP-5004	PL-807	TRK-9001	MEX	15000.00	7.50	1125.00	  null	HELD_INSPECTION

select * from silver at (offset=>-200) where dest_country='CAN';
-- SHP-5001	PL-802	TRK-9001	CAN	85000.00	5.00	4250.00	  null  	CLEARED
-- SHP-5003	PL-806	TRK-9003	CAN	120000.00	4.00	4800.00	FAST_PASS_01	CLEARED

update silver set clearance_status='CLEARED' where dest_country='CAN' and clearance_status='REJECTED';
-- number of rows updated
-- 2
select dest_country,
count_if(clearance_status='CLEARED') as cleared_count,
count_if(clearance_status='REJECTED') as rejected_count
from silver group by dest_country;
-- DEST_COUNTRY  CLEARED_COUNT  REJECTED_COUNT
--       MEX	       1	        0
--       CAN	       2	        0

-- TASK 6: End-to-End Pipeline Lineage & Reconciliation Audit
select (select sum(raw_payload:data:declared_value::number(12,2)) from bronze) as  bronze_gross_sum,
(select sum(declared_value) from silver) as silver_gross_sum,
(select sum(total_cleared_val) from gold) as gold_gross_sum,
case when (select sum(raw_payload:data:declared_value::number(12,2)) from bronze)
           =(select sum(declared_value) from silver)
    then true 
    else false
end as data_match_flag;
-- BRONZE_GROSS_SUM  SILVER_GROSS_SUM  GOLD_GROSS_SUM  DATA_MATCH_FLAG
-- 262000.00	262000.00	247000.00	TRUE
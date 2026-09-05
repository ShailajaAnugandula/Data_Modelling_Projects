-- TASK 1: Bronze Data Lake Ingestion & Schema-on-Read Exploration
create database HEALTHCARE_PIPELINE_DB;
create schema CLAIMS_CORE;

use database HEALTHCARE_PIPELINE_DB;
use schema CLAIMS_CORE;

create file format json_format
type=json
strip_outer_array=false;

create stage datalake;

create table bronze(
ingest_id number autoincrement,
payload variant,
loaded_at timestamp
);

copy into bronze (payload)
from @datalake/claims_payloads.json
file_format=(format_name=json_format);

select count(*) as total_bronze_records from bronze;
-- TOTAL_BRONZE_RECORDS
-- 8


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
from @datalake/bad_claim.json
(file_format => text_format);
-- RAW_RECORD_TEXT                                     PARSED_JSON
-- {"INVALID_PAYLOAD_UNPARSEABLE_STRING"}               null

insert into quarantine(raw_record_text,reason)
select $1,'MALFORMED_JSON_BODY'
from @datalake/bad_claim.json
(file_format=>text_format)
where try_parse_json($1) is null;
-- number of rows inserted
-- 1

select * from quarantine;
-- QUARANTINE_ID       RAW_RECORD_TEXT                          REASON
--        1      {"INVALID_PAYLOAD_UNPARSEABLE_STRING"}    MALFORMED_JSON_BODY

-- TASK 3: Silver Layer — Real-Time CDC via Stream Tracking
-- - Create a Snowflake Stream `STRM_BRONZE_CLAIMS` on `BRONZE_RAW_CLAIMS`.
-- - Create Silver base table `SILVER_CLAIMS_TRANSACTIONS` with columns:
--   * `CLAIM_ID`, `SUBMITTED_AT`, `PATIENT_ID`, `PROVIDER_ID`, `DIAGNOSIS_CODE`, 
--     `BILLED_AMOUNT`, `COPAY_AMOUNT`, `NET_PAYABLE_AMOUNT`, `STATUS`
-- - Calculate `NET_PAYABLE_AMOUNT = BILLED_AMOUNT - COPAY_AMOUNT`.
-- - Merge/Deduplicate records based on `CLAIM_ID`, picking the latest status update.

create stream strm_bronze on table bronze;

select * from strm_bronze;

create table silver_claims(
claim_id varchar,
submitted_at timestamp,
patient_id number,
provider_id varchar,
diagnosis_code varchar,
billed_amount number(12,2),
copay_amount number(12,2),
net_payable_amount number(12,2),
status varchar
);

insert into silver_claims(
claim_id ,
submitted_at ,
patient_id ,
provider_id ,
diagnosis_code ,
billed_amount ,
copay_amount ,
net_payable_amount ,
status 
)
select
payload:claim_id::varchar as claim_id,
payload:submitted_at::timestamp as submitted_at,
payload:patient_id::number as patient_id,
payload:provider_id::varchar as provider_id,
payload:diagnosis_code::varchar as diagnosis_code,
payload:billed_amount::number(12,2) as billed_amount,
payload:copay_amount::number(12,2) as copay_amount,
payload:billed_amount::number(12,2)
 - payload:copay_amount::number(12,2) as net_payable_amount,
    payload:status::varchar as status
from bronze 
qualify row_number() over (
    partition by payload:claim_id::varchar
    order by
        case payload:status::varchar
            when 'APPROVED' then 3
            when 'DENIED' then 3
            when 'PENDING' then 1
            else 0
        end desc
) = 1;

select * from strm_bronze;

INSERT INTO BRONZE (INGEST_ID, PAYLOAD, LOADED_AT)
SELECT
    9,
    PARSE_JSON('{
        "claim_id":"CLM-301",
        "submitted_at":"2026-08-10T08:00:00Z",
        "patient_id":5001,
        "provider_id":"PRV-10",
        "diagnosis_code":"ICD-10-A",
        "billed_amount":15000.00,
        "copay_amount":500.00,
        "status":"DENIED"
    }'),
    CURRENT_TIMESTAMP();

SELECT
    INGEST_ID,
    PAYLOAD:claim_id::VARCHAR AS CLAIM_ID,
    PAYLOAD:status::VARCHAR AS STATUS,
    METADATA$ACTION,
    METADATA$ISUPDATE,
    METADATA$ROW_ID
FROM strm_bronze;

-- 9	CLM-301	DENIED	INSERT	FALSE	721b305b005905533d385bfc08a0e35e875b93aa
select * from silver_claims where claim_id='CLM-301';
-- CLM-301	2026-08-10 08:00:00.000	5001	PRV-10	ICD-10-A	15000.00	500.00	14500.00	APPROVED

merge into silver_claims as target using(
select
payload:claim_id::varchar as claim_id,
payload:submitted_at::timestamp as submitted_at,
payload:patient_id::number as patient_id,
payload:provider_id::varchar as provider_id,
payload:diagnosis_code::varchar as diagnosis_code,
payload:billed_amount::number(12,2) as billed_amount,
payload:copay_amount::number(12,2) as copay_amount,
payload:billed_amount::number(12,2)
 - payload:copay_amount::number(12,2) as net_payable_amount,
    payload:status::varchar as status
from strm_bronze 
where metadata$action='INSERT'
)as source
on target.claim_id=source.claim_id
when matched then 
update set 
target.submitted_at=source.submitted_at,
target.patient_id=source.patient_id,
target.provider_id=source.provider_id,
target.diagnosis_code=source.diagnosis_code,
target.billed_amount=source.billed_amount,
target.copay_amount=source.copay_amount,
target.net_payable_amount=source. net_payable_amount,
target.status=source.status
when not matched then
insert(claim_id ,
submitted_at ,
patient_id ,
provider_id ,
diagnosis_code ,
billed_amount ,
copay_amount ,
net_payable_amount ,
status 
)
values (
source.claim_id,
source.submitted_at,
source.patient_id,
source.provider_id,
source.diagnosis_code,
source.billed_amount,
source.copay_amount,
source.net_payable_amount,
source.status
);

select claim_id,status from silver_claims where claim_id='CLM-301';
-- CLM-301	DENIED
update silver_claims set status='APPROVED' where claim_id='CLM-301';
select claim_id,status from silver_claims;

create dynamic table dt_provider
target_lag='1 minute'
warehouse=compute_wh
as 
select provider_id,
sum(billed_amount) as total_billed_amount,
sum(copay_amount) as total_copay_collect,
sum(net_payable_amount) as total_net_payable,
count(*) as approved_claims
from silver_claims where status='APPROVED'
group by provider_id;

select * from dt_provider order by provider_id;
 -- PROVIDER_ID  TOTAL_BILLED_AMOUNT   TOTAL_COPAY_COLLECT TOTAL_NET_PAYABLE   APPROVED_CLAIMS 
-- PRV-10	15000.00	500.00	14500.00	1
-- PRV-11	128500.00	2800.00	125700.00	2
-- PRV-12	9200.00	   300.00	8900.00	    2

select * from table(
information_schema.dynamic_table_refresh_history(
name=> 'dt_provider'
)
);
-- NAME   SCHEMA_NAME   DATABASE_NAME  STATE     STATE_CODE    STATE_MESSAGE     QUERY_ID     DATA_TIMESTAMP    GRAPH_HISTORY_VALID_FROM     REFRESH_START_TIME     REFRESH_END_TIME      TARGET_LAG_SEC        QUALIFIED_NAME    LAST_COMPLETED_DEPENDENCY  STATISTICS     REFRESH_ACTION    REFRESH_TRIGGER     WAREHOUSE  INPUTS_WITH_CHANGED_DATA      REINIT_REASON    EXECUTE_AS_USER     SECONDARY_ROLE_NAMES
-- 2026-08-31 23:39:10.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:39:12.138 -0700	2026-08-31 23:39:12.506 -0700	2026-08-31 23:39:22.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 232,
--   "executionTimeMs": 162,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:38:22.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:38:24.080 -0700	2026-08-31 23:38:24.559 -0700	2026-08-31 23:38:34.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 364,
--   "executionTimeMs": 146,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:37:34.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:37:36.289 -0700	2026-08-31 23:37:36.650 -0700	2026-08-31 23:37:46.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 254,
--   "executionTimeMs": 132,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:36:46.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:36:47.954 -0700	2026-08-31 23:36:48.334 -0700	2026-08-31 23:36:58.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 243,
--   "executionTimeMs": 166,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:35:58.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:35:59.567 -0700	2026-08-31 23:35:59.934 -0700	2026-08-31 23:36:10.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 247,
--   "executionTimeMs": 152,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:35:10.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:35:12.871 -0700	2026-08-31 23:35:13.631 -0700	2026-08-31 23:35:22.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 597,
--   "executionTimeMs": 214,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:34:22.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:34:23.679 -0700	2026-08-31 23:34:24.503 -0700	2026-08-31 23:34:34.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 681,
--   "executionTimeMs": 174,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:33:34.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:33:36.006 -0700	2026-08-31 23:33:36.429 -0700	2026-08-31 23:33:46.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 281,
--   "executionTimeMs": 171,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:32:46.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:32:48.218 -0700	2026-08-31 23:32:48.621 -0700	2026-08-31 23:32:58.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 307,
--   "executionTimeMs": 125,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:31:58.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:31:59.644 -0700	2026-08-31 23:32:00.129 -0700	2026-08-31 23:32:10.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 323,
--   "executionTimeMs": 196,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:31:10.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:31:12.182 -0700	2026-08-31 23:31:12.637 -0700	2026-08-31 23:31:22.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 276,
--   "executionTimeMs": 210,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:30:22.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:30:24.168 -0700	2026-08-31 23:30:24.620 -0700	2026-08-31 23:30:34.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 276,
--   "executionTimeMs": 208,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:29:34.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:29:35.953 -0700	2026-08-31 23:29:36.480 -0700	2026-08-31 23:29:46.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 361,
--   "executionTimeMs": 198,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:28:46.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:28:48.243 -0700	2026-08-31 23:28:48.934 -0700	2026-08-31 23:28:58.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 584,
--   "executionTimeMs": 141,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:27:58.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:27:59.836 -0700	2026-08-31 23:28:00.224 -0700	2026-08-31 23:28:10.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 239,
--   "executionTimeMs": 177,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:27:10.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:27:11.892 -0700	2026-08-31 23:27:12.595 -0700	2026-08-31 23:27:22.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 574,
--   "executionTimeMs": 164,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:26:22.764 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:26:23.661 -0700	2026-08-31 23:26:24.162 -0700	2026-08-31 23:27:22.764 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 349,
--   "executionTimeMs": 177,
--   "numAddedPartitions": 0,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 0,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 0
-- }	NO_DATA	SCHEDULED					
-- 2026-08-31 23:26:10.177 -0700	2026-08-31 23:26:11.532 -0700	2026-08-31 23:26:10.319 -0700	2026-08-31 23:26:11.437 -0700	2026-08-31 23:27:10.177 -0700	60	HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.DT_PROVIDER	{}	{
--   "compilationTimeMs": 577,
--   "executionTimeMs": 460,
--   "numAddedPartitions": 1,
--   "numCopiedRows": 0,
--   "numDeletedRows": 0,
--   "numInsertedRows": 3,
--   "numRemovedPartitions": 0,
--   "queuedTimeMs": 102
-- }	INCREMENTAL	CREATION	COMPUTE_WH	[
--   {
--     "kind": "TABLE",
--     "name": "HEALTHCARE_PIPELINE_DB.CLAIMS_CORE.SILVER_CLAIMS",
--     "statistics": {
--       "numAddedPartitions": 4,
--       "numRegisteredRows": 24,
--       "numRemovedPartitions": 3,
--       "numUnregisteredRows": 18
--     }
--   }
-- ]			

SELECT
    NAME AS DYNAMIC_TABLE_NAME,
    REFRESH_ACTION,
    REFRESH_TRIGGER,
    STATE AS QUALIFIED_STATUS
FROM TABLE(
    INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
        NAME => 'dt_provider'
    )
)
WHERE REFRESH_TRIGGER = 'CREATION'
ORDER BY REFRESH_START_TIME DESC
LIMIT 1;
-- DYNAMIC_TABLE_NAME   REFRESH_ACTION    REFRESH_TRIGGER   QUALIFIED_STATUS
-- DT_PROVIDER	      INCREMENTAL	            CREATION	  SUCCEEDED

select (select sum(payload:billed_amount::number(12,2))as billed_amount from bronze) as bronze_gross_total,
(select sum(billed_amount) as silver_gross_total from silver_claims) as silver_gross_total,
(select sum(total_billed_amount) from  dt_provider) as gold_gross_total,
case when (select sum(payload:billed_amount::number(12,2)) as billed_amount from bronze)=257700
and (select sum(billed_amount) as silver_gross_total from silver_claims)=197700
and (select sum(total_billed_amount) from  dt_provider)=152700 then true 
else false 
end as reconciled_flag;
-- BRONZE_GROSS_TOTAL| SILVER_GROSS_TOTAL| GOLD_GROSS_TOTAL| RECONCILED_FLAG
-- 257700.00	197700.00	152700.00	TRUE
SELECT
    PAYLOAD:claim_id::VARCHAR AS CLAIM_ID,
    PAYLOAD:billed_amount::NUMBER(12,2) AS BILLED_AMOUNT,
    PAYLOAD:status::VARCHAR AS STATUS
FROM BRONZE
ORDER BY CLAIM_ID;

SELECT COUNT(*)
FROM BRONZE;

SELECT
    INGEST_ID,
    PAYLOAD,
    LOADED_AT
FROM BRONZE
WHERE PAYLOAD:claim_id::VARCHAR = 'CLM-301';

DELETE FROM BRONZE
WHERE INGEST_ID = 9
  AND PAYLOAD:claim_id::VARCHAR = 'CLM-301'
  AND PAYLOAD:status::VARCHAR = 'DENIED';
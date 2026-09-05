-- Think of a Share as a controlled package containing the objects we allow another organization to read.
-- The underlying data isn't copied into another database in the traditional sense.
-- That's why the assignment calls it:
-- Zero-copy data sharing
-- The partner can access the objects we've shared, while the data remains managed by the provider.
-- Zero-copy means:
--  We share access to the same data without physically copying or moving the data.

-- Think of it like Google Drive sharing:

-- You own the file.
-- Instead of sending someone a duplicate file, you simply give them access.
-- They can view the data, but there is no second copy created.

-- In Snowflake, Secure Data Sharing works similarly.
-- “Zero-copy architecture means sharing access to data without physically duplicating or moving the underlying data. 
-- In Snowflake Secure Data Sharing, a provider exposes approved objects such as secure views to a consumer. With a Reader Account, 
-- the external partner can query that shared data even without their own Snowflake account, while the provider retains control over the underlying data.”

--TASK 1: Environment Setup & Raw Telemetry Ingestion
use role accountadmin;

create database CLEANROOM_SHARED_DB;
create schema PARTNER_TELEMETRY;

show schemas in database CLEANROOM_SHARED_DB; 

use database CLEANROOM_SHARED_DB;
use schema PARTNER_TELEMETRY;

select current_database(),current_schema();

create file format json_format
type=json
strip_outer_array=false;

create stage cleanroom_stage;

create table RAW_RETAIL_TRANSACTIONS(
ingest_id number autoincrement,
payload variant,
loaded_at timestamp default current_timestamp()
);

copy into RAW_RETAIL_TRANSACTIONS (payload)
from @cleanroom_stage/retail_trans.json
file_format=(format_name=json_format);

create table BRONZE_AD_EXPOSURES(
ingest_id number autoincrement,
payload variant,
loaded_at timestamp default current_timestamp()
);

copy into BRONZE_AD_EXPOSURES (payload)
from @cleanroom_stage/ad_expo.json
file_format=(format_name=json_format);

desc table RAW_RETAIL_TRANSACTIONS;
desc table BRONZE_AD_EXPOSURES;

select count(*) as retail_count from RAW_RETAIL_TRANSACTIONS;
-- RETAIL_COUNT
-- 4
select count(*) as ad_count from BRONZE_AD_EXPOSURES;
-- AD_COUNT
-- 3

--TASK 2: Silver Clean Room Overlap & Aggregation Layer
create table SILVER_ATTRIBUTION_MATCH as
select pos.payload:pos_id::varchar as pos_id,
pos.payload:store_id::varchar as store_id,
ad.payload:campaign_name::varchar as campaign_name,
ad.payload:channel::varchar as channel,
pos.payload:basket_value::number(10,2) as basket_value,
datediff('hour',ad.payload:timestamp::timestamp_tz,pos.payload:timestamp::timestamp_tz) 
as conversion_hours from RAW_RETAIL_TRANSACTIONS pos
inner join BRONZE_AD_EXPOSURES ad on pos.payload:hashed_email::varchar=
ad.payload:hashed_email::varchar;

select * from SILVER_ATTRIBUTION_MATCH;
-- POS_ID	STORE_ID	CAMPAIGN_NAME	CHANNEL	BASKET_VALUE	CONVERSION_HOURS
-- POS-1001	STORE-01	Summer_Apex_Promo	Meta	145.50	16
-- POS-1002	STORE-01	Summer_Apex_Promo	Google	89.20	15

--TASK 3: Aggregate-Only Differential Privacy View (Clean Room Governance)
create or replace secure view SECURE_GOLD_CAMPAIGN_ATTRIBUTION_PERFORMANCE as
select campaign_name,
count(distinct pos_id) as converted_user_count,
sum(basket_value) as total_attributed_sales,
avg(basket_value) as avg_basket_value
from SILVER_ATTRIBUTION_MATCH group by campaign_name
having count(distinct pos_id)>=2;

select * from SECURE_GOLD_CAMPAIGN_ATTRIBUTION_PERFORMANCE;
-- CAMPAIGN_NAME	CONVERTED_USER_COUNT	TOTAL_ATTRIBUTED_SALES	AVG_BASKET_VALUE
-- Summer_Apex_Promo	2	234.70	117.35000000

--TASK 4: Secure Data Share Creation & Privilege Assignment
use role accountadmin;
create share SHARE_CPG_PARTNER_ANALYTICS;

grant usage on database CLEANROOM_SHARED_DB to share SHARE_CPG_PARTNER_ANALYTICS;
grant usage on schema CLEANROOM_SHARED_DB.PARTNER_TELEMETRY to share  SHARE_CPG_PARTNER_ANALYTICS;
grant select on view CLEANROOM_SHARED_DB.PARTNER_TELEMETRY.SECURE_GOLD_CAMPAIGN_ATTRIBUTION_PERFORMANCE
to share SHARE_CPG_PARTNER_ANALYTICS;

show grants to share SHARE_CPG_PARTNER_ANALYTICS;
-- created_on	privilege	granted_on	name	granted_to	grantee_name	grant_option	granted_by
-- 2026-09-02 10:37:15.672 -0700	USAGE	DATABASE	CLEANROOM_SHARED_DB	SHARE	ME05597.SHARE_CPG_PARTNER_ANALYTICS	false	ACCOUNTADMIN
-- 2026-09-02 10:37:23.678 -0700	USAGE	SCHEMA	CLEANROOM_SHARED_DB.PARTNER_TELEMETRY	SHARE	ME05597.SHARE_CPG_PARTNER_ANALYTICS	false	ACCOUNTADMIN
-- 2026-09-02 10:39:33.016 -0700	SELECT	VIEW	CLEANROOM_SHARED_DB.PARTNER_TELEMETRY.SECURE_GOLD_CAMPAIGN_ATTRIBUTION_PERFORMANCE	SHARE	ME05597.SHARE_CPG_PARTNER_ANALYTICS	false	ACCOUNTADMIN

show shares like 'SHARE_CPG_PARTNER_ANALYTICS';
-- created_on	kind	owner_account	name	database_name	to	owner	comment	listing_global_name	secure_objects_only
-- 2026-09-02 10:33:29.481 -0700	OUTBOUND	CDMIJFL.LZ39242	SHARE_CPG_PARTNER_ANALYTICS	CLEANROOM_SHARED_DB		ACCOUNTADMIN			true
-- TASK 5: Provisioning a Reader Account for Non-Snowflake Partners
use role accountadmin;

create managed account CPG_READER_ACCT_01
admin_name = CPG_ADMIN,
admin_password= 'ShailajaAnugandula@098',
type = READER;

alter share SHARE_CPG_PARTNER_ANALYTICS
add accounts = AF60011;

show shares like 'SHARE_CPG_PARTNER_ANALYTICS';
-- created_on	                   kind  	owner_account	            name	database_name	to	           owner	comment	  listing_global_name	secure_objects_only
-- 2026-09-02 10:33:29.481 -0700	OUTBOUND	CDMIJFL.LZ39242	SHARE_CPG_PARTNER_ANALYTICS	CLEANROOM_SHARED_DB	CDMIJFL.CPG_READER_ACCT_01	ACCOUNTADMIN			true

show managed accounts like 'CPG_READER_ACCT_01';
-- account_name	 cloud	region	account_locator	created_on	account_url	account_locator_url	is_reader	comment	region_group	old_account_url	account_old_url_saved_on	account_old_url_last_used	organization_old_url	organization_old_url_saved_on	organization_old_url_last_used	tenant_type	domain_names
-- CPG_READER_ACCT_01	aws	AWS_AP_SOUTHEAST_2	AF60011	2026-09-02 10:51:08.594 -0700	https://cdmijfl-cpg_reader_acct_01.snowflakecomputing.com	https://af60011.ap-southeast-2.snowflakecomputing.com	true		PUBLIC	https://cdmijfl-ql56314.snowflakecomputing.com	2026-09-02 10:51:09.430 -0700					INTERNAL	
show warehouses;

-- TASK 6: End-to-End Clean Room Reconciliation & Compliance Check
SELECT
    COUNT(*) > 0 AS PII_EXPOSURE_FLAG
FROM INFORMATION_SCHEMA.VIEW_COLUMNS
WHERE TABLE_SCHEMA = 'PARTNER_TELEMETRY'
  AND TABLE_NAME = 'SECURE_GOLD_CAMPAIGN_ATTRIBUTION_PERFORMANCE'
  AND UPPER(COLUMN_NAME) = 'HASHED_EMAIL';

SELECT GET_DDL(
    'VIEW',
    'CLEANROOM_SHARED_DB.PARTNER_TELEMETRY.SECURE_GOLD_CAMPAIGN_ATTRIBUTION_PERFORMANCE'
);
	-- CAMPAIGN_NAME,
	-- CONVERTED_USER_COUNT,
	-- TOTAL_ATTRIBUTED_SALES,
	-- AVG_BASKET_VALUE
    //no hasheed_email is present so pii_exposure_flag is falss
select
    (
        select sum(basket_value)
        from CLEANROOM_SHARED_DB.PARTNER_TELEMETRY.SILVER_ATTRIBUTION_MATCH
    ) as silver_match_val,

    (
        select sum(total_attributed_sales)
        from CLEANROOM_SHARED_DB.PARTNER_TELEMETRY
             .SECURE_GOLD_CAMPAIGN_ATTRIBUTION_PERFORMANCE
    ) as gold_match_val,

    false as pii_exposure_flag,

    (
        (
            select sum(basket_value)
            from CLEANROOM_SHARED_DB.PARTNER_TELEMETRY.SILVER_ATTRIBUTION_MATCH
        )
        =
        (
            select sum(total_attributed_sales)
            from CLEANROOM_SHARED_DB.PARTNER_TELEMETRY
                 .SECURE_GOLD_CAMPAIGN_ATTRIBUTION_PERFORMANCE
        )
    ) as reconciled_flag;


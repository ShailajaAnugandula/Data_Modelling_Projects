
create database FINANCIAL_GOVERNANCE_DB;
create schema WEALTH_CORE;

use database FINANCIAL_GOVERNANCE_DB;
use schema WEALTH_CORE;

create file format json_format
type=json
strip_outer_array=false;

create stage datalake;

-- TASK 1: Bronze Storage Setup & Error Isolation
create table bronze(
ingest_id number autoincrement,
payload variant,
loaded_at timestamp
);

copy into bronze (payload)
from @datalake/payload_17.json
file_format=(format_name=json_format);

select count(*) as total_bronze_records from bronze;
-- TOTAL_BRONZE_RECORDS
-- 7


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
from @datalake/bad_payload17.json
(file_format => text_format);
-- RAW_RECORD_TEXT                                     PARSED_JSON
-- {"INVALID_RAW_WIRE_PAYLOAD_UNPARSEABLE"}             null

insert into quarantine(raw_record_text,reason)
select $1,'MALFORMED_JSON_BODY'
from @datalake/bad_payload17.json
(file_format=>text_format)
where try_parse_json($1) is null;
-- number of rows inserted
-- 1

select * from quarantine;
-- QUARANTINE_ID      RAW_RECORD_TEXT                REASON
-- 1	{"INVALID_RAW_WIRE_PAYLOAD_UNPARSEABLE"}	MALFORMED_JSON_BODY

-- TASK 2: Silver Layer Setup & RBAC Role Provisioning
create table silver(
txn_id varchar(10),
client_id number,
client_ssn varchar(20),
region varchar(20),
account_no varchar(20),
amount number(12,2),
status varchar(20),
aml_risk_score varchar(10)
);

insert into silver(txn_id ,client_id ,client_ssn ,region,
account_no ,amount ,status ,aml_risk_score)
select payload:txn_id::varchar as txn_id,
payload:client_id::number as client_id,
payload:client_ssn::varchar as client_ssn,
payload:region::varchar as region,
payload:account_no::varchar as account_no,
payload:amount::number(12,2) as amount,
payload:status::varchar as status,
payload:aml_risk_score::varchar as aml_risk_score
from bronze;

select * from silver;

-- TXN_ID	CLIENT_ID	CLIENT_SSN	REGION	ACCOUNT_NO	AMOUNT	STATUS	AML_RISK_SCORE
-- TXN-7001	101	999-12-3456	NA	ACT-5544	250000.00	SETTLED	
-- TXN-7002	102	888-98-7654	EU	ACT-7711	120000.00	SETTLED	
-- TXN-7003	103	777-45-6789	NA	ACT-3322	450000.00	PENDING	
-- TXN-7004	104	666-23-8901	EU	ACT-9988	85000.00	SETTLED	
-- TXN-7005	105	555-67-1234	NA	ACT-1144	1000000.00	SETTLED	LOW
-- TXN-7006	106	444-89-4321	EU	ACT-6633	310000.00	SETTLED	MEDIUM
-- TXN-7007	107	333-11-2222	NA	ACT-2211	0.00	FAILED	HIGH

select count(*) as total_silver_records from silver as accountadmin;
-- TOTAL_SILVER_RECORDS
-- 7


create role compliance_officer;
create role na_analyst;
create role eu_analyst;

grant usage on database FINANCIAL_GOVERNANCE_DB to role compliance_officer;
grant usage on schema FINANCIAL_GOVERNANCE_DB.WEALTH_CORE to role compliance_officer;
grant select on table FINANCIAL_GOVERNANCE_DB.WEALTH_CORE.silver to role compliance_officer;

grant usage on database FINANCIAL_GOVERNANCE_DB to role na_analyst;
grant usage on schema FINANCIAL_GOVERNANCE_DB.WEALTH_CORE to role na_analyst;
grant select on table FINANCIAL_GOVERNANCE_DB.WEALTH_CORE.silver to role na_analyst;

grant usage on database FINANCIAL_GOVERNANCE_DB to role eu_analyst;
grant usage on schema FINANCIAL_GOVERNANCE_DB.WEALTH_CORE to role eu_analyst;
grant select on table FINANCIAL_GOVERNANCE_DB.WEALTH_CORE.silver to role eu_analyst;

-- TASK 3: Dynamic Data Masking (DDM) Implementation
create masking policy masking_ssn
as (val varchar)
returns varchar ->
  case when current_role()='compliance_officer' then val
       else '***-**-' || right(val,4)
  end;

create masking policy mask_account
as (val varchar)
returns varchar ->
  case when current_role()='compliance_officer' then val
       else 'ACT-****'
  end;


alter table silver modify column client_ssn set masking policy masking_ssn;
alter table silver modify column account_no set masking policy mask_account;

select current_role();
-- CURRENT_ROLE()
-- ACCOUNTADMIN

select txn_id,client_ssn,account_no from silver;
-- TXN_ID	CLIENT_SSN	ACCOUNT_NO
-- TXN-7001	***-**-3456	ACT-****
-- TXN-7002	***-**-7654	ACT-****
-- TXN-7003	***-**-6789	ACT-****
-- TXN-7004	***-**-8901	ACT-****
-- TXN-7005	***-**-1234	ACT-****
-- TXN-7006	***-**-4321	ACT-****
-- TXN-7007	***-**-2222	ACT-****
-- Since our policy says only COMPLIANCE_OFFICER gets the full value, ACCOUNTADMIN will not match that condition and therefore will see the masked values.

select current_user();
-- CURRENT_USER()
-- SHAILAJA
-- grant role compliance_officer to user SHAILAJA;
-- use role compliance_officer;

-- show grants to user shailaja;
-- select txn_id,client_ssn,account_no from silver;

-- SELECT CURRENT_USER(), CURRENT_ROLE();
-- SELECT TXN_ID, CLIENT_SSN, ACCOUNT_NO
-- FROM FINANCIAL_GOVERNANCE_DB.WEALTH_CORE.SILVER
-- ORDER BY TXN_ID;

-- SELECT GET_DDL(
--     'masking policy',
--     'FINANCIAL_GOVERNANCE_DB.WEALTH_CORE.masking_ssn'
-- );

-- show masking policies;
-- SELECT
--     TXN_ID,
--     CLIENT_SSN,
--     ACCOUNT_NO
-- FROM SILVER
-- ORDER BY TXN_ID;

-- desc table silver;
-- SHOW MASKING POLICIES LIKE 'MASKING_SSN';

-- SELECT
--     CURRENT_ROLE() AS ACTIVE_ROLE,
--     TXN_ID,
--     CLIENT_SSN,
--     ACCOUNT_NO
-- FROM SILVER
-- ORDER BY TXN_ID;

-- DESCRIBE MASKING POLICY MASKING_SSN;
-- CREATE OR REPLACE MASKING POLICY MASKING_SSN
-- AS (VAL VARCHAR)
-- RETURNS VARCHAR ->
--     CASE
--         WHEN IS_ROLE_IN_SESSION('COMPLIANCE_OFFICER')
--             THEN VAL
--         ELSE '***-**-' || RIGHT(VAL, 4)
--     END;
-- SELECT
--  CURRENT_ROLE(),
--  IS_ROLE_IN_SESSION('COMPLIANCE_OFFICER');

-- USE ROLE COMPLIANCE_OFFICER;
-- SELECT CURRENT_ROLE();

-- SELECT TXN_ID, CLIENT_SSN, ACCOUNT_NO
-- FROM SILVER
-- ORDER BY TXN_ID;


-- select IS_ROLE_IN_SESSION('COMPLIANCE_OFFICER');

-- ALTER TABLE SILVER
-- MODIFY COLUMN CLIENT_SSN
-- UNSET MASKING POLICY;


-- ALTER TABLE SILVER
-- MODIFY COLUMN ACCOUNT_NO
-- UNSET MASKING POLICY;

-- CREATE OR REPLACE MASKING POLICY MASKING_SSN
-- AS (VAL VARCHAR)
-- RETURNS VARCHAR ->
--     CASE
--         WHEN IS_ROLE_IN_SESSION('COMPLIANCE_OFFICER')
--             THEN VAL
--         ELSE '***-**-' || RIGHT(VAL, 4)
--     END;

USE ROLE ACCOUNTADMIN;

GRANT CREATE MASKING POLICY
ON SCHEMA FINANCIAL_GOVERNANCE_DB.WEALTH_CORE
TO ROLE COMPLIANCE_OFFICER;

USE ROLE COMPLIANCE_OFFICER;
SELECT CURRENT_ROLE();


SELECT CURRENT_ROLE(), CURRENT_USER();

SELECT TXN_ID, CLIENT_SSN, ACCOUNT_NO
FROM SILVER;

-- TXN_ID	CLIENT_SSN	ACCOUNT_NO
-- TXN-7001	999-12-3456	ACT-5544
-- TXN-7002	888-98-7654	ACT-7711
-- TXN-7003	777-45-6789	ACT-3322
-- TXN-7004	666-23-8901	ACT-9988
-- TXN-7005	555-67-1234	ACT-1144
-- TXN-7006	444-89-4321	ACT-6633
-- TXN-7007	333-11-2222	ACT-2211

--TASK 4: Row-Access Policy (RAP) Regional Isolation

use role ACCOUNTADMIN;
select current_role();

create row access policy region_access_policy 
as (region varchar)
returns boolean->
case when current_role()='compliance_officer' then true
when current_role()='na_analyst' and region='NA' then true
when current_role()='eu_analyst' and region='EU' then true
else false
end;


alter table silver add row access policy region_access_policy on (region);
use role compliance_officer;
SELECT CURRENT_ROLE();
select txn_id,region,amount,status from silver order by txn_id;

SELECT CURRENT_USER(), CURRENT_ROLE();


USE ROLE ACCOUNTADMIN;
DESCRIBE ROW ACCESS POLICY REGION_ACCESS_POLICY;

SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.POLICY_REFERENCES(
        POLICY_NAME => 'REGION_ACCESS_POLICY'
    )
);

USE ROLE COMPLIANCE_OFFICER;
SELECT TXN_ID, REGION, AMOUNT, STATUS
FROM FINANCIAL_GOVERNANCE_DB.WEALTH_CORE.SILVER
ORDER BY TXN_ID;

SELECT
    CURRENT_ROLE(),
    IS_ROLE_IN_SESSION('COMPLIANCE_OFFICER');

SELECT
    CURRENT_ROLE() AS ACTIVE_ROLE,
    CURRENT_ROLE() = 'COMPLIANCE_OFFICER' AS UPPERCASE_MATCH,
    CURRENT_ROLE() = 'compliance_officer' AS LOWERCASE_MATCH;

USE ROLE ACCOUNTADMIN;
ALTER TABLE SILVER
DROP ROW ACCESS POLICY REGION_ACCESS_POLICY;

CREATE OR REPLACE ROW ACCESS POLICY REGION_ACCESS_POLICY
AS (REGION VARCHAR)
RETURNS BOOLEAN ->
    CASE
        WHEN CURRENT_ROLE() = 'COMPLIANCE_OFFICER' THEN TRUE
        WHEN CURRENT_ROLE() = 'NA_ANALYST' AND REGION = 'NA' THEN TRUE
        WHEN CURRENT_ROLE() = 'EU_ANALYST' AND REGION = 'EU' THEN TRUE
        ELSE FALSE
    END;

ALTER TABLE SILVER
ADD ROW ACCESS POLICY REGION_ACCESS_POLICY
ON (REGION);

USE ROLE COMPLIANCE_OFFICER;

SELECT TXN_ID, REGION, AMOUNT, STATUS
FROM SILVER
ORDER BY TXN_ID


-- | TXN\_ID  | REGION | AMOUNT     | STATUS  |
-- | -------- | ------ | ---------- | ------- |
-- | TXN-7001 | NA     | 250000.00  | SETTLED |
-- | TXN-7002 | EU     | 120000.00  | SETTLED |
-- | TXN-7003 | NA     | 450000.00  | PENDING |
-- | TXN-7004 | EU     | 85000.00   | SETTLED |
-- | TXN-7005 | NA     | 1000000.00 | SETTLED |
-- | TXN-7006 | EU     | 310000.00  | SETTLED |
-- | TXN-7007 | NA     | 0.00       | FAILED  |

USE ROLE ACCOUNTADMIN;
GRANT ROLE NA_ANALYST TO USER SHAILAJA;
GRANT ROLE EU_ANALYST TO USER SHAILAJA;
SHOW GRANTS TO USER SHAILAJA;

USE ROLE na_analyst;
select current_role();

SELECT TXN_ID, REGION, AMOUNT, STATUS
FROM SILVER
ORDER BY TXN_ID;

-- TXN_ID	REGION	AMOUNT	STATUS
-- TXN-7001	NA	250000.00	SETTLED
-- TXN-7003	NA	450000.00	PENDING
-- TXN-7005	NA	1000000.00	SETTLED
-- TXN-7007	NA	0.00	FAILED

use role eu_analyst;
select current_role();
select txn_id,region,amount,status from silver;
-- TXN_ID	REGION	AMOUNT	STATUS
-- TXN-7002	EU	120000.00	SETTLED
-- TXN-7004	EU	85000.00	SETTLED
-- TXN-7006	EU	310000.00	SETTLED


-- TASK 5: Secure Data Sharing & Clean Room Audit View
use role accountadmin;

create secure view gold_audit_summary as
select region,sum(amount) as total_settled_amount,
count(*) as settled_txn_amount,
avg(amount) as avg_settled_amount from silver 
where status='SETTLED' group by region;

use role COMPLIANCE_OFFICER;
SELECT CURRENT_ROLE();
select * from gold_audit_summary order by region;
-- REGION	TOTAL_SETTLED_AMOUNT	SETTLED_TXN_AMOUNT	AVG_SETTLED_AMOUNT
-- EU	515000.00	3	171666.66666667
-- NA	1250000.00	2	625000.00000000

use role accountadmin;
create role EXTERNAL_AUDITOR;
grant usage on database FINANCIAL_GOVERNANCE_DB to role EXTERNAL_AUDITOR;
grant usage on schema FINANCIAL_GOVERNANCE_DB.WEALTH_CORE to role EXTERNAL_AUDITOR;
grant select on view FINANCIAL_GOVERNANCE_DB.WEALTH_CORE.gold_audit_summary to role EXTERNAL_AUDITOR;

-- TASK 6: End-to-End Governance Audit & Lineage Reconciliation
USE ROLE ACCOUNTADMIN;

select (select sum(payload:amount::number(12,2))as amount from bronze) as bronze_gross_total,
(select sum(amount) as silver_gross_total from silver) as silver_gross_total,
(select sum(total_settled_amount) from gold_audit_summary) as gold_gross_total,
case when (select sum(payload:amount::number(12,2)) as amount from bronze)
= (select sum(amount) as silver_gross_total from silver) 
and (select sum(total_settled_amount) from gold_audit_summary)=1765000 then true 
else false 
end as leak;
-- BRONZE_GROSS_TOTAL	SILVER_GROSS_TOTAL	GOLD_GROSS_TOTAL	LEAK
-- 2215000.00	2215000.00	1765000.00	TRUE
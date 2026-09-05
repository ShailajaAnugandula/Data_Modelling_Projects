SELECT
    CURRENT_ACCOUNT(),
    CURRENT_USER(),
    CURRENT_ROLE();
-- CURRENT_ACCOUNT()	CURRENT_USER()	CURRENT_ROLE()
-- AF60011	CPG_ADMIN	PUBLIC
use role accountadmin;
create warehouse  CPG_READER_WH
with warehouse_size='x-small'
auto_suspend=60
auto_resume=true;

create or replace resource monitor CPG_READER_RM
with credit_quota=10
frequency=monthly
start_timestamp=immediately
triggers on 75 percent do notify
on 90 percent do notify
on 100 percent do suspend;

-- "The warehouse provides the compute resources for the Reader Account, 
-- while the Resource Monitor controls and limits the credits consumed by that compute. 
-- This is important because Reader Accounts are managed by the provider, 
-- so we can control the partner's compute consumption and prevent unexpected costs."

alter warehouse CPG_READER_WH
set resource_monitor = CPG_READER_RM;

show warehouses like 'CPG_READER_WH';


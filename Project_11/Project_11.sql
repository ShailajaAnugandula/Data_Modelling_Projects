
-- TASK 1 — Create Database and Schema
create warehouse hybrid_scd
warehouse_size='xsmall',
auto_suspend=60,
auto_resume=true;

create database scd_hybrid;
create schema scd_schema;

use database scd_hybrid;
use schema scd_schema;

-- TASK 2 — Create Hybrid Dimension Table

create table cust_hybrid(
customer_key int autoincrement,
customer_id int,
customer_name varchar(30),
current_city varchar(30),
previous_city varchar(30),
state varchar(30),
current_membership varchar(30),
previous_membership varchar(30),
historical_membership varchar(30),
segment varchar(30),
effective_date date,
expiry_date date,
is_current boolean
);

desc table cust_hybrid;

create file format csv_format 
type=csv
field_delimiter=','
skip_header=1;

create stage cust_stage;

create table cust_init(
customer_id int,
customer_name varchar(30),
city varchar(30),
state varchar(30),
membership varchar(30),
segment varchar(30)
);
-- TASK 3 — Load Initial Dimension Data
copy into cust_init
from @cust_stage/customers_initial.csv
file_format=csv_format;

insert into cust_hybrid(
customer_id ,
customer_name ,
current_city ,
previous_city ,
state ,
current_membership ,
previous_membership ,
historical_membership ,
segment ,
effective_date ,
expiry_date ,
is_current )
select customer_id,
customer_name,
city,
null,
state,
membership,
null,
membership,
segment,
'2026-01-01',
'9999-12-31',
true from cust_init;

select count(*) as total_records from cust_hybrid;
-- Total Records = 5
select count(*) as current_records from cust_hybrid;
-- Current Records = 5

-- TASK 4 — Display Initial Dimension State
select * from cust_hybrid order by customer_id;
-- 1	101	Amit Sharma	Hyderabad		Telangana	Silver		Silver	Regular	2026-01-01	9999-12-31	TRUE
-- 2	102	Priya Reddy	Warangal		Telangana	Gold		Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 3	103	Rahul Verma	Vijayawada		Andhra Pradesh	Silver		Silver	Regular	2026-01-01	9999-12-31	TRUE
-- 4	104	Neha Patel	Hyderabad		Telangana	Gold		Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 5	105	Arjun Gupta	Nagpur		Maharashtra	Bronze		Bronze	Regular	2026-01-01	9999-12-31	TRUE

create table cust_updates(
customer_id int,
customer_name varchar(30),
city varchar(30),
state varchar(30),
membership varchar(30),
segment varchar(30),
effective_date date
);

copy into cust_updates
from @cust_stage/cust_updates.csv
file_format=csv_format;
-- TASK 5 — Apply Hybrid Updates for Customers 101, 103, and 104
update cust_hybrid h 
set expiry_date=dateadd(day,-1,u.effective_date),
is_current=false
from cust_updates u where h.customer_id=u.customer_id
and h.is_current=true;

select customer_id,effective_date,expiry_date,is_current from cust_hybrid;
-- 102	2026-01-01	9999-12-31	TRUE
-- 101	2026-01-01	2026-03-31	FALSE
-- 103	2026-01-01	2026-04-04	FALSE
-- 104	2026-01-01	2026-04-09	FALSE
-- 105	2026-01-01	9999-12-31	TRUE
insert into cust_hybrid (
customer_id ,
customer_name ,
current_city ,
previous_city ,
state ,
current_membership ,
previous_membership ,
historical_membership ,
segment ,
effective_date ,
expiry_date ,
is_current
)
select u.customer_id ,
u.customer_name ,
u.city ,
h.current_city ,
u.state ,
u.membership ,
h.current_membership ,
u.membership ,
u.segment ,
u.effective_date ,
'9999-12-31',
true from cust_updates u 
join cust_hybrid h on h.customer_id=u.customer_id
where is_current=false and h.effective_date='2026-01-01';

desc table cust_hybrid;

select * from cust_hybrid;

-- Amit Sharma	Hyderabad	null	Telangana	Silver	null	Silver	Regular	2026-01-01	2026-03-31	FALSE
-- Amit Sharma	Bengaluru	Hyderabad	Karnataka	Gold	Silver	Gold	Premium	2026-04-01	9999-12-31	TRUE
-- Priya Reddy	Warangal	null	Telangana	Gold	null	Gold	Premium	2026-01-01	9999-12-31	TRUE
-- Rahul Verma	Vijayawada	null	Andhra Pradesh	Silver	null	Silver	Regular	2026-01-01	2026-04-04	FALSE
-- Rahul Verma	Chennai	Vijayawada	Tamil Nadu	Gold	Silver	Gold	Premium	2026-04-05	9999-12-31	TRUE
-- Neha Patel	Hyderabad	nuull	Telangana	Gold	null	Gold	Premium	2026-01-01	2026-04-09	FALSE
-- Neha Patel	Hyderabad	Hyderabad	Telangana	Platinum	Gold	Platinum	Premium	2026-04-10	9999-12-31	TRUE
-- Arjun Gupta	Nagpur	null	Maharashtra	Bronze	null	Bronze	Regular	2026-01-01	9999-12-31	TRUE
//updating cities
update cust_hybrid h set 
current_city=u.city,
previous_city=case 
when u.city<>old.current_city then old.current_city
else null
end
from cust_updates u join cust_hybrid old on old.customer_id=u.customer_id
where old.effective_date='2026-01-01' and u.customer_id=h.customer_id;

select * from cust_hybrid order by customer_id;
//updating state-overwriting-type1
update cust_hybrid h 
set state=u.state from cust_updates u 
where h.customer_id=u.customer_id;

select * from cust_hybrid order by customer_id;
-- 1	101	Amit Sharma	Bengaluru	Hyderabad	Karnataka	Silver		Silver	Regular	2026-01-01
-- 101	101	Amit Sharma	Bengaluru	Hyderabad	Karnataka	Gold	Silver	Gold	Premium	2026-04-01
-- 2	102	Priya Reddy	Warangal	null	Telangana	Gold		Gold	Premium	2026-01-01
-- 3	103	Rahul Verma	Chennai	Vijayawada	Tamil Nadu	Silver		Silver	Regular	2026-01-01
-- 102	103	Rahul Verma	Chennai	Vijayawada	Tamil Nadu	Gold	Silver	Gold	Premium	2026-04-05
-- 4	104	Neha Patel	Hyderabad	null	Telangana	Gold		Gold	Premium	2026-01-01
-- 103	104	Neha Patel	Hyderabad	null	Telangana	Platinum	Gold	Platinum	Premium	2026-04-10
-- 5	105	Arjun Gupta	Nagpur	nulll	Maharashtra	Bronze		Bronze	Regular	2026-01-01
//updating membership
update cust_hybrid h 
set current_membership=u.membership,
previous_membership=old.current_membership
from cust_updates u join cust_hybrid old 
on old.customer_id=u.customer_id
and  old.effective_date='2026-01-01' where  h.customer_id=u.customer_id;

select * from cust_hybrid order by customer_id;

-- 101	Amit Sharma	Bengaluru	Hyderabad	Karnataka	Gold	Silver	Silver	Regular	2026-01-01	2026-03-31	FALSE
-- 101	Amit Sharma	Bengaluru	Hyderabad	Karnataka	Gold	Silver	Gold	Premium	2026-04-01	9999-12-31	TRUE
-- 102	Priya Reddy	Warangal null	Telangana	Gold		Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 103	Rahul Verma	Chennai	Vijayawada	Tamil Nadu	Gold	Silver	Silver	Regular	2026-01-01	2026-04-04	FALSE
-- 103	Rahul Verma	Chennai	Vijayawada	Tamil Nadu	Gold	Silver	Gold	Premium	2026-04-05	9999-12-31	TRUE
-- 104	Neha Patel	Hyderabad	 null	Telangana	Platinum	Gold	Gold	Premium	2026-01-01	2026-04-09	FALSE
-- 104	Neha Patel	Hyderabad	null	Telangana	Platinum	Gold	Platinum	Premium	2026-04-10	9999-12-31	TRUE
-- 105	Arjun Gupta	Nagpur	null	Maharashtra	Bronze		Bronze	Regular	2026-01-01	9999-12-31	TRUE

-- TASK 7 — Display Active Customer Report
select * from cust_hybrid where is_current=true order by customer_id;
-- 101	101	Amit Sharma	Bengaluru	Hyderabad	Karnataka	Gold	Silver	Gold	Premium	2026-04-01	9999-12-31	TRUE
-- 2	102	Priya Reddy	Warangal		Telangana	Gold		Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 102	103	Rahul Verma	Chennai	Vijayawada	Tamil Nadu	Gold	Silver	Gold	Premium	2026-04-05	9999-12-31	TRUE
-- 103	104	Neha Patel	Hyderabad		Telangana	Platinum	Gold	Platinum	Premium	2026-04-10	9999-12-31	TRUE
-- 5	105	Arjun Gupta	Nagpur		Maharashtra	Bronze		Bronze	Regular	2026-01-01	9999-12-31	TRUE

-- TASK 8 — Point-in-Time Historical Query
-- "What was Customer 101's historical membership, segment, and city on March 15, 2026?"
select customer_id,customer_name,current_city,historical_membership,segment,effective_date,expiry_date from cust_hybrid 
where '2026-03-15' between effective_date and expiry_date and customer_id=101;
-- 101          Amit Sharma    Bengaluru  Silver                 Regular  2026-01-01      2026-03-31

-- TASK 9 — Metric Validation and Record Counts
-- --------------------------------------------

select 'TOTAL RECORD COUNT' as METRIC,
count(*) as VALUE from cust_hybrid
union all
select 'CURRENT RECORD COUNT' as METRIC,
count(*) as VALUE from cust_hybrid where is_current=true
union all
select 'HISTORICAL RECORD COUNT' as METRIC,
count(*) as VALUE from cust_hybrid where is_current=false;
-- METRIC          VALUE
-- TOTAL RECORD COUNT	8
-- CURRENT RECORD COUNT	5
-- HISTORICAL RECORD COUNT	3
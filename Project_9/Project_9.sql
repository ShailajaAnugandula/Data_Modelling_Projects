create warehouse customer_history
warehouse_size='xsmall'
auto_suspend=60
auto_resume=true;

create database cust_history;
create schema cust_history.cust_schema;

use database cust_history;
use schema cust_schema;

create file format csv_format 
type=csv
field_delimiter=','
skip_header=1;

create stage cust_hist_stage;

create table customer_scd1(
customer_key int autoincrement,
customer_id int,
customer_name varchar(30),
city varchar(30),
state varchar(30),
membership varchar(30),
segment varchar(30)
);

copy into customer_scd1(customer_id,customer_name,city,state,membership,segment)
from @cust_hist_stage/customers_initial.csv
file_format=csv_format;

select * from customer_scd1;
-- 1	101	Amit Sharma	Hyderabad	Telangana	Silver	Regular
-- 2	102	Priya Reddy	Warangal	Telangana	Gold	Premium
-- 3	103	Rahul Verma	Vijayawada	Andhra Pradesh	Silver	Regular
-- 4	104	Neha Patel	Hyderabad	Telangana	Gold	Premium
-- 5	105	Arjun Gupta	Nagpur	Maharashtra	Bronze	Regular

select count(*) as total_records from customer_scd1;
-- 5 records

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
from @cust_hist_stage/cust_updates.csv
file_format=csv_format;

select * from cust_updates;
-- 101	Amit Sharma	Bengaluru	Karnataka	Gold	Premium	2026-04-01
-- 103	Rahul Verma	Chennai	Tamil Nadu	Gold	Premium	2026-04-05
-- 104	Neha Patel	Hyderabad	Telangana	Platinum	Premium	2026-04-10
select count(*) from cust_updates;
//3 records

update customer_scd1 d set
d.customer_name=u.customer_name,
d.city=u.city,
d.state=u.state,
d.membership=u.membership,
d.segment=u.segment
from cust_updates u
where d.customer_id=u.customer_id;

select * from customer_scd1 order by customer_id;
-- 1	101	Amit Sharma	Bengaluru	Karnataka	Gold	Premium
-- 2	102	Priya Reddy	Warangal	Telangana	Gold	Premium
-- 3	103	Rahul Verma	Chennai	Tamil Nadu	Gold	Premium
-- 4	104	Neha Patel	Hyderabad	Telangana	Platinum	Premium
-- 5	105	Arjun Gupta	Nagpur	Maharashtra	Bronze	Regular

-- Type 1 History Loss
select * from customer_scd1 where customer_id=101;
-- 1	101	Amit Sharma	Bengaluru	Karnataka	Gold	Premium

-- Type-2 scd
create table customer_scd2(
customer_key int autoincrement,
customer_id int,
customer_name varchar(30),
city varchar(30),
state varchar(30),
membership varchar(30),
segment varchar(30),
effective_date date,
expiry_date date,
is_current boolean
);
desc table customer_scd2;
select count(*) from customer_scd2;
-- initially 0
insert into customer_scd2(customer_id,customer_name,city,state,membership,segment,effective_date,expiry_date,is_current)
select customer_id,customer_name,city,state,membership,segment,'2026-01-01'::date,'9999-12-31'::date,true
from customer_scd1;

select count(*) from customer_scd2;
select * from customer_scd2 order by customer_id;
-- 2	101	Amit Sharma	Bengaluru	Karnataka	Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 1	102	Priya Reddy	Warangal	Telangana	Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 3	103	Rahul Verma	Chennai	Tamil Nadu	Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 4	104	Neha Patel	Hyderabad	Telangana	Platinum	Premium	2026-01-01	9999-12-31	TRUE
-- 5	105	Arjun Gupta	Nagpur	Maharashtra	Bronze	Regular	2026-01-01	9999-12-31	TRUE

update customer_scd2 d set 
expiry_date=dateadd(day,-1,u.effective_date),
is_current=false
from cust_updates u 
where d.customer_id=u.customer_id and is_current=true;

select * from customer_scd2 where customer_id in (101,103,104);
-- 2	101	Amit Sharma	Bengaluru	Karnataka	Gold	Premium	2026-01-01	2026-03-31	FALSE
-- 3	103	Rahul Verma	Chennai	Tamil Nadu	Gold	Premium	2026-01-01	2026-04-04	FALSE
-- 4	104	Neha Patel	Hyderabad	Telangana	Platinum	Premium	2026-01-01	2026-04-09	FALSE

-- Inserting the new versions
insert into customer_scd2(customer_id,customer_name,city,state,membership,segment,effective_date,expiry_date,is_current)
select customer_id,customer_name,city,state,membership,segment,effective_date,'9999-12-31'::date,true
from cust_updates;

select * from customer_scd2 where customer_id=101;
-- 101	Amit Sharma	Bengaluru	Karnataka	Gold	Premium	2026-01-01	2026-03-31	FALSE
-- 101	Amit Sharma	Bengaluru	Karnataka	Gold	Premium	2026-04-01	9999-12-31	TRUE
select * from customer_scd2 where customer_id=103;
-- 103	Rahul Verma	Chennai	Tamil Nadu	Gold	Premium	2026-01-01	2026-04-04	FALSE
-- 103	Rahul Verma	Chennai	Tamil Nadu	Gold	Premium	2026-04-05	9999-12-31	TRUE
select * from customer_scd2 where customer_id=104;
-- 4	104	Neha Patel	Hyderabad	Telangana	Platinum	Premium	2026-01-01	2026-04-09	FALSE
-- 103	104	Neha Patel	Hyderabad	Telangana	Platinum	Premium	2026-04-10	9999-12-31	TRUE
select * from customer_scd2  order by customer_id;
-- 101	Amit Sharma	Bengaluru	Karnataka	Gold	Premium	2026-01-01	2026-03-31	FALSE
-- 101	Amit Sharma	Bengaluru	Karnataka	Gold	Premium	2026-04-01	9999-12-31	TRUE
-- 103	Rahul Verma	Chennai	Tamil Nadu	Gold	Premium	2026-01-01	2026-04-04	FALSE
-- 103	Rahul Verma	Chennai	Tamil Nadu	Gold	Premium	2026-04-05	9999-12-31	TRUE
-- 104	Neha Patel	Hyderabad	Telangana	Platinum	Premium	2026-01-01	2026-04-09	FALSE
-- 104	Neha Patel	Hyderabad	Telangana	Platinum	Premium	2026-04-10	9999-12-31	TRUE
-- 5	105	Arjun Gupta	Nagpur	Maharashtra	Bronze	Regular	2026-01-01	9999-12-31	TRUE

-- Display Current Customer Records
select customer_id,customer_name,city,state,membership,segment from customer_scd2 where is_current=true order by customer_id;
-- 101	Amit Sharma	Bengaluru	Karnataka	Gold	Premium
-- 102	Priya Reddy	Warangal	Telangana	Gold	Premium
-- 103	Rahul Verma	Chennai	Tamil Nadu	Gold	Premium
-- 104	Neha Patel	Hyderabad	Telangana	Platinum	Premium
-- 105	Arjun Gupta	Nagpur	Maharashtra	Bronze	Regular


-- TASK 16 — Historical Customer Analysis
-- ----------
-- Management asks:
-- What was Customer 101's membership on March 15, 2026?
select customer_id,customer_name,city,state,membership,segment,effective_date,expiry_date from customer_scd2 where customer_id=101
and '2026-03-15'::date between effective_date and expiry_date;
-- 101	Amit Sharma	Bengaluru	Karnataka	Gold	Premium	2026-01-01	2026-03-31

-- validating
select count(*) as scd_type_1_record_count from customer_scd1;
-- SCD TYPE 1 RECORD COUNT
-- 5
select count(*) as scd_type_2_record_count from customer_scd2;
-- SCD TYPE 2 RECORD COUNT
-- 8
select count(*) as SCD_TYPE2_CURRENT_RECORD_COUNT from customer_scd2 where is_current=true;
-- SCD TYPE 2 CURRENT RECORD COUNT
-- 5
select count(*) as SCD_TYPE2_CURRENT_RECORD_COUNT from customer_scd2 where is_current=false;
-- SCD TYPE 2 HISTORICAL RECORD COUNT
-- 3
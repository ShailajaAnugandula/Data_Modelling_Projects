create warehouse scd_type3_6
warehouse_size='xsmall',
auto_suspend=60,
auto_resume=true;

create database scd36_db;
create schema scd36_db.scd_schema;
use database scd36_db;
use schema scd_schema;

create file format csv_format
type=csv
field_delimiter=','
skip_header=1;

create stage scd_stage;

create table cust_init(
customer_id int,
customer_name varchar(30),
city varchar(30),
state varchar(30),
membership varchar(30),
segment varchar(30)
);

create table cust_updates(
customer_id int,
customer_name varchar(30),
city varchar(30),
state varchar(30),
membership varchar(30),
segment varchar(30),
effective_date date
);

copy into cust_init
from @scd_stage/customers_initial.csv
file_format=csv_format;

copy into cust_updates
from @scd_stage/cust_updates.csv
file_format=csv_format;

select * from cust_init;
select count(*) from cust_init; //5
select * from cust_updates;

create table cust_type3(
customer_key int autoincrement,
customer_id int,
customer_name varchar(30),
city varchar(30),
state varchar(30),
current_membership varchar(30),
previous_membership varchar(30),
segment varchar(30)
);
TRUNCATE TABLE CUST_TYPE3;

insert into cust_type3(customer_id,customer_name,city,state,current_membership,previous_membership,segment)
select customer_id,customer_name,city,state,membership,null,segment from cust_init;

select * from cust_type3;
-- 1	101	Amit Sharma	Hyderabad	Telangana	Silver		Regular
-- 2	102	Priya Reddy	Warangal	Telangana	Gold		Premium
-- 3	103	Rahul Verma	Vijayawada	Andhra Pradesh	Silver		Regular
-- 4	104	Neha Patel	Hyderabad	Telangana	Gold		Premium
-- 5	105	Arjun Gupta	Nagpur	Maharashtra	Bronze		Regular
update cust_type3 d set
previous_membership=d.current_membership,
current_membership=u.membership,
city=u.city,
state=u.state,
segment=u.segment
from cust_updates u where d.customer_id=u.customer_id;

select customer_id,customer_name,city,state,current_membership,previous_membership,segment
from cust_type3 order by customer_id;
-- 101	Amit Sharma	Bengaluru	Karnataka	Gold	Silver	Premium
-- 102	Priya Reddy	Warangal	Telangana	Gold		Premium
-- 103	Rahul Verma	Chennai	Tamil Nadu	Gold	Silver	Premium
-- 104	Neha Patel	Hyderabad	Telangana	Platinum	Gold	Premium
-- 105	Arjun Gupta	Nagpur	Maharashtra	Bronze		Regular

select count(*) as number_of_records from cust_type3; //5

select customer_id,customer_name,current_membership,previous_membership from cust_type3 where customer_id=101;
-- 101	Amit Sharma	Gold  Silver

create table cust_type6(
customer_key int autoincrement,
customer_id int,
customer_name varchar(30),
city varchar(30),
state varchar(30),
current_membership varchar(30),
previous_membership varchar(30),
historical_membership varchar(30),
segment varchar(30),
effective_date date,
expiry_date date,
is_current boolean
);

insert into cust_type6(customer_id,customer_name,city,state,current_membership,
previous_membership,historical_membership,segment,effective_date,expiry_date,is_current)
select customer_id,customer_name,city,state,
membership,null,membership,segment,'2026-01-01','9999-12-31',true
from cust_init;

select * from cust_type6;
-- 1	101	Amit Sharma	Hyderabad	Telangana	Silver		Silver	Regular	2026-01-01	9999-12-31	TRUE
-- 2	102	Priya Reddy	Warangal	Telangana	Gold		Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 3	103	Rahul Verma	Vijayawada	Andhra Pradesh	Silver		Silver	Regular	2026-01-01	9999-12-31	TRUE
-- 4	104	Neha Patel	Hyderabad	Telangana	Gold		Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 5	105	Arjun Gupta	Nagpur	Maharashtra	Bronze		Bronze	Regular	2026-01-01	9999-12-31	TRUE
select count(*) as total_records from cust_type6;
-- Total Records = 5
select count(*) as current_records from cust_type6 where is_current=true;
-- Current Records = 5
-- updating cust 101
update cust_type6 set expiry_date=dateadd(day,-1,'2026-04-01'),
is_current=false
where customer_id=101 and is_current=true;

select * from cust_type6 where customer_id=101;
-- 1	101	Amit Sharma	Hyderabad	Telangana	Silver		Silver	Regular	2026-01-01	2026-03-31	FALSE

insert into cust_type6(customer_id,customer_name,city,state,current_membership,
previous_membership,historical_membership,segment,effective_date,expiry_date,is_current)
select u.customer_id,u.customer_name,u.city,u.state,u.membership,
d.current_membership,u.membership,u.segment,u.effective_date,'9999-12-31',true
from cust_updates u join cust_type6 d on
d.customer_id=u.customer_id where u.customer_id=101 and d.is_current=false;

select * from cust_type6 where customer_id=101 order by customer_key;
-- 1	101	Amit Sharma	Hyderabad	Telangana	Silver	null	Silver	Regular	2026-01-01	2026-03-31	FALSE
-- 101	101	Amit Sharma	Bengaluru	Karnataka	Gold	Silver	Gold	Premium	2026-04-01	9999-12-31	TRUE

-- updating cust 103
update cust_type6 set expiry_date=dateadd(day,-1,'2026-04-05'),
is_current=false
where customer_id=103 and is_current=true;

-- update cust_type6 set effective_date='2026-04-05' where customer_id=103 and is_current=true;
-- truncate table cust_type6;
insert into cust_type6(customer_id,customer_name,city,state,current_membership,
previous_membership,historical_membership,segment,effective_date,expiry_date,is_current)
select u.customer_id,u.customer_name,u.city,u.state,u.membership,
d.current_membership,u.membership,u.segment,u.effective_date,'9999-12-31',true
from cust_updates u join cust_type6 d on
d.customer_id=u.customer_id where u.customer_id=103 and d.is_current=false;

select * from cust_type6 where customer_id=103 order by customer_id;
-- 203	103	Rahul Verma	Vijayawada	Andhra Pradesh	Silver	null	Silver	Regular	2026-01-01	2026-04-04	FALSE
-- 105	103	Rahul Verma	Chennai	Tamil Nadu	Gold	Silver	Gold	Premium	2026-04-05	9999-12-31	TRUE

-- updating 104 
update cust_type6 set expiry_date=dateadd(day,-1,'2026-04-10'),
is_current=false
where customer_id=104 and is_current=true;

insert into cust_type6(customer_id,customer_name,city,state,current_membership,
previous_membership,historical_membership,segment,effective_date,expiry_date,is_current)
select u.customer_id,u.customer_name,u.city,u.state,u.membership,
d.current_membership,u.membership,u.segment,u.effective_date,'9999-12-31',true
from cust_updates u join cust_type6 d on
d.customer_id=u.customer_id where u.customer_id=104 and d.is_current=false;

select * from cust_type6 where customer_id=104;
-- 204	104	Neha Patel	Hyderabad	Telangana	Gold	null	Gold	Premium	2026-01-01	2026-04-09	FALSE
-- 106	104	Neha Patel	Hyderabad	Telangana	Platinum	Gold	Platinum	Premium	2026-04-10	9999-12-31	TRUE

select customer_id,
customer_name,
current_membership,
previous_membership,
effective_date,
expiry_date,
is_current from cust_type6 order by customer_id,effective_date;
-- 101	Amit Sharma	Silver		2026-01-01	2026-03-31	FALSE
-- 101	Amit Sharma	Gold	Silver	2026-04-01	9999-12-31	TRUE
-- 102	Priya Reddy	Gold		2026-01-01	9999-12-31	TRUE
-- 103	Rahul Verma	Silver		2026-01-01	2026-04-04	FALSE
-- 103	Rahul Verma	Gold	Silver	2026-04-05	9999-12-31	TRUE
-- 104	Neha Patel	Gold		2026-01-01	2026-04-09	FALSE
-- 104	Neha Patel	Platinum	Gold	2026-04-10	9999-12-31	TRUE
-- 105	Arjun Gupta	Bronze		2026-01-01	9999-12-31	TRUE

select customer_id,
customer_name,
current_membership,
previous_membership
from cust_type6 where is_current=true;

-- 101          Amit Sharma     Bengaluru   Gold                Silver
-- 102          Priya Reddy     Warangal    Gold                NULL
-- 103          Rahul Verma     Chennai     Gold                Silver
-- 104          Neha Patel      Hyderabad   Platinum            Gold
-- 105          Arjun Gupta     Nagpur      Bronze               NULL
select customer_id,customer_name,current_membership,effective_date,expiry_date from cust_type6 where customer_id=101
and '2026-03-15' between effective_date and expiry_date;
-- 101	Amit Sharma	Silver	2026-01-01	2026-03-31

select count(*) as scd_type3_count from cust_type3;
-- SCD TYPE 3 RECORD COUNT
-- 5
select count(*) as scd_type6_count from cust_type6;
-- SCD TYPE 6 RECORD COUNT
-- 8
select count(*) as scd_type6_count from cust_type6 where is_current=true;
-- SCD TYPE 6 CURRENT RECORD COUNT
-- 5
select count(*) as scd_type6_count from cust_type6 where is_current=false;
-- SCD TYPE 6 HISTORICAL RECORD COUNT
-- 3
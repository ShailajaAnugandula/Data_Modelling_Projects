create database cust_db;
create schema cust_schema;

use database customer_db;
use schema cust_schema;

create file format csv_format
type=csv
field_delimiter=','
skip_header=1
field_optionally_enclosed_by='"';

create stage cust_stage;

create table dim_customer(
customer_key int autoincrement,
customer_id int,
customer_name varchar(30),
city varchar(30),
state varchar(30),
membership varchar(30),
segment varchar(30)
);

copy into dim_customer(customer_id,customer_name,city,state,membership,segment)
from @cust_stage/customers_initial.csv
file_format=csv_format;

select * from dim_customer;

create table cust_updated(
customer_id int,
customer_name varchar(30),
city varchar(30),
state varchar(30),
membership varchar(30),
segment varchar(30)
);
create stage cust_update_stage;
create file format csv_format
type=csv
field_delimiter=','
skip_header=4
field_optionally_enclosed_by='"';

copy into cust_updated
from @cust_update_stage/cust_updated.csv
file_format=csv_format;

list @cust_update_stage;

select * from cust_updated;

-- Task 6 — Identify Changed Customers
-- ------------------------------------
-- Compare DIM_CUSTOMER with CUSTOMER_UPDATES.
select d.customer_id,
d.city as old_city,
u.city as new_city,
d.state as old_state,
u.state as new_state,
d.membership as old_membership,
u.membership as new_membership,
d.segment as old_segment,
u.segment as new_segment
from dim_customer d join cust_updated u
on d.customer_id=u.customer_id
where d.city<>u.city or d.state <> u.state
or d.membership<>u.membership
or d.segment<>u.segment
order by d.customer_id;

-- 101	Hyderabad	Bengaluru	Telangana	Karnataka	Silver	Gold	Regular	Premium
-- 103	Vijayawada	Chennai	Andhra Pradesh	Tamil Nadu	Silver	Gold	Regular	Premium
-- 104	Hyderabad	Hyderabad	Telangana	Telangana	Gold	Platinum	Premium	Premium
-- Task 7 — Identify Attribute Changes
select d.customer_id,'city' as attribute,d.city as old_value,u.city as new_value
from dim_customer d join cust_updated u on d.customer_id=u.customer_id where d.city<>u.city
union all
select d.customer_id,'state' as attribute,d.state as old_value,u.state as new_value
from dim_customer d join cust_updated u on d.customer_id=u.customer_id where d.state<>u.state
union all 
select d.customer_id,'membership' as attribute,d.membership as old_value,u.membership as new_value
from dim_customer d join cust_updated u on d.customer_id=u.customer_id where d.membership<>u.membership
order by customer_id,attribute;
-- 101	city	Hyderabad	Bengaluru
-- 101	membership	Silver	Gold
-- 101	state	Telangana	Karnataka
-- 103	city	Vijayawada	Chennai
-- 103	membership	Silver	Gold
-- 103	state	Andhra Pradesh	Tamil Nadu
-- 104	membership	Gold	Platinum

update dim_customer d set 
customer_name=u.customer_name,
city=u.city,
state=u.state,
membership=u.membership,
segment=u.segment
from cust_updated u 
where d.customer_id=u.customer_id;

select * from dim_customer order by customer_id;
-- 1	101	Amit Sharma	Bengaluru	Karnataka	Gold	Premium
-- 2	102	Priya Reddy	Warangal	Telangana	Gold	Premium
-- 3	103	Rahul Verma	Chennai	Tamil Nadu	Gold	Premium
-- 4	104	Neha Patel	Hyderabad	Telangana	Platinum	Premium
-- 5	105	Arjun Gupta	Nagpur	Maharashtra	Bronze	Regular

-- Problem:After overwriting the dimension:
-- ------------------------------------------
-- Historical City       → LOST
-- Historical State      → LOST
-- Historical Membership → LOST
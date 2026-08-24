create warehouse retail_dw12
warehouse_size='xsmall',
auto_suspend=60,
auto_resume=true;

--TASK 1 — Create Database and Schema Context
create database retail_db12;
create schema retail_schema;
use database retail_db12;
use schema retail_schema;

create file format csv_format
type=csv
field_delimiter=','
skip_header=1;

create stage retail_stage;

create table stores(
store_id int,
store_name varchar(30),
city varchar(30),
state varchar(30),
store_manager varchar(30)
);

copy into stores 
from @retail_stage/stores.csv
file_format=csv_format;

select * from stores;

create table products(
product_id number,
product_name varchar(50),
category varchar(30),
unit_price number(10,2)
);

copy into products
from @retail_stage/product.csv
file_format=csv_format;

create table cust_init(
customer_id int,
customer_name varchar(30),
city varchar(30),
state varchar(30),
membership varchar(30),
segment varchar(30)
);

copy into cust_init 
from @retail_stage/customers_initial.csv
file_format=csv_format;

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
from @retail_stage/cust_updates.csv
file_format=csv_format;

--TASK 2 — Create Store Conformed Dimension Table (`DIM_STORE`)
create table dim_stores(
store_key int autoincrement primary key,
store_id int,
store_name varchar(30),
city varchar(30),
state varchar(30),
store_manager varchar(30)
);

--TASK 3 — Create Product Dimension Table (`DIM_PRODUCT`)
create table dim_products(
product_key int autoincrement primary key,
product_id number,
product_name varchar(50),
category varchar(30),
unit_price number(10,2)
);

--TASK 4 — Create Hybrid Customer Dimension Table (`DIM_CUSTOMER_HYBRID`)
create table dim_cust_hybrid(
customer_key number autoincrement  primary key,
customer_id int,
customer_name varchar(30),
city varchar(30),
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

--TASK 5 — Populate Initial Store and Product Dimension Data
insert into dim_stores(store_id,store_name,city,state,store_manager)
select store_id,store_name,city,state,store_manager from stores;

insert into dim_products(product_id,product_name,category,unit_price)
select product_id,product_name,category,unit_price from products;

--TASK 6 — Populate Initial Customer Dimension Data
insert into dim_cust_hybrid(
customer_id ,
customer_name ,
city ,
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

select * from dim_cust_hybrid;
-- 1	101	Amit Sharma	Hyderabad	null	Telangana	Silver	null	Silver	Regular	2026-01-01	9999-12-31	TRUE
-- 2	102	Priya Reddy	Warangal	null	Telangana	Gold null		Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 3	103	Rahul Verma	Vijayawada	null	Andhra Pradesh	Silver	null	Silver	Regular	2026-01-01	9999-12-31	TRUE
-- 4	104	Neha Patel	Hyderabad	null	Telangana	Gold	null	Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 5	105	Arjun Gupta	Nagpur	null	Maharashtra	Bronze	null	Bronze	Regular	2026-01-01	9999-12-31	TRUE

--TASK 7 — Create Sales Transaction Fact Table (`FACT_SALES`)
create table fact_sales(
sales_key int autoincrement primary key,
transaction_id varchar(20),
transaction_date date,
customer_key int,
store_key int,
product_key int,
quantity int,
unit_price number(10,2),
total_amount number(12,2),

foreign key(customer_key) references dim_cust_hybrid(customer_key),
foreign key(store_key) references dim_stores(store_key),
foreign key(product_key) references dim_products(product_key)
);

-- drop table dim_stores;
-- drop table dim_products;
-- drop table dim_cust_hybrid;

--TASK 8 — Insert Q1 2026 Sales Fact Transactions
insert into fact_sales(transaction_id,transaction_date,customer_key ,store_key ,product_key ,quantity ,unit_price ,
total_amount)
select 'TXN-1001','2026-02-15',c.customer_key ,s.store_key ,p.product_key ,1 ,p.unit_price ,
1*p.unit_price from dim_cust_hybrid c
join dim_stores s on s.store_id=201
join dim_products p on p.product_id=501
where customer_id=101 and is_current=true;
-- number of rows inserted
-- 1

insert into fact_sales(transaction_id,transaction_date,customer_key ,store_key ,product_key ,quantity ,unit_price ,total_amount)
select 'TXN-1002','2026-03-10',c.customer_key ,s.store_key ,p.product_key ,2 ,p.unit_price ,
2*p.unit_price from dim_cust_hybrid c
join dim_stores s on s.store_id=203
join dim_products p on p.product_id=502
where customer_id=103 and is_current=true;
-- number of rows inserted
-- 1

select * from fact_sales; 
-- SALES_KEY   TRANSACTION_ID  TRANSACTION_DATE  CUSTOMER_KEY  PRODUCT_KEY  QUANTITY  UNIT_PRICE  TOTAL_AMOUNT
-- 1	TXN-1001	2026-02-15	1	1	1	1	75000.00	75000.00
-- 2	TXN-1002	2026-03-10	3	3	2	2	1500.00	3000.00

--TASK 9 — Apply Store Manager Update (SCD Type 1 Overwrite)
update dim_stores set store_manager='Suresh Menon' where store_id=201;
select * from dim_stores where store_id=201;
-- 1	201	Metro Flagship	Hyderabad	Telangana	Suresh Menon

-- TASK 10 — Execute Multi-Attribute Customer Updates
--**Step 1:** Expire active records for Customers 101, 103, and 104 by updating 
--`EXPIRY_DATE` to the day before their `effective_date` and setting `IS_CURRENT = FALSE`.
update dim_cust_hybrid h set 
expiry_date=dateadd(day,-1,u.effective_date),
is_current=false
from cust_updates u where h.customer_id=u.customer_id
and h.is_current=true;

select * from dim_cust_hybrid order by customer_id;
-- 1	101	Amit Sharma	Hyderabad		Telangana	Silver		Silver	Regular	2026-01-01	2026-03-31	FALSE
-- 2	102	Priya Reddy	Warangal		Telangana	Gold		Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 3	103	Rahul Verma	Vijayawada		Andhra Pradesh	Silver		Silver	Regular	2026-01-01	2026-04-04	FALSE
-- 4	104	Neha Patel	Hyderabad		Telangana	Gold		Gold	Premium	2026-01-01	2026-04-09	FALSE
-- 5	105	Arjun Gupta	Nagpur		Maharashtra	Bronze		Bronze	Regular	2026-01-01	9999-12-31	TRUE


-- **Step 2:** Insert new active row versions for updated customers with `IS_CURRENT = TRUE` 
--and `EXPIRY_DATE = '9999-12-31'`. Preserve their old city in `PREVIOUS_CITY`.
insert into dim_cust_hybrid(customer_id,customer_name,city ,previous_city ,state ,current_membership ,previous_membership ,
historical_membership ,segment ,effective_date ,expiry_date ,is_current)
select u.customer_id,u.customer_name,u.city,h.city,u.state,u.membership,h.current_membership,u.membership,u.segment,
u.effective_date,'9999-12-31',true from cust_updates u join dim_cust_hybrid h on u.customer_id=h.customer_id
where h.is_current=false and h.effective_date='2026-01-01';

select * from dim_cust_hybrid order by customer_id;
-- 1	101	Amit Sharma	Hyderabad	null	Telangana	Silver	null	Silver	Regular	2026-01-01	2026-03-31	FALSE
-- 101	101	Amit Sharma	Bengaluru	Hyderabad	Karnataka	Gold	Silver	Gold	Premium	2026-04-01	9999-12-31	TRUE
-- 2	102	Priya Reddy	Warangal	null	Telangana	Gold	null	Gold	Premium	2026-01-01	9999-12-31	TRUE
-- 3	103	Rahul Verma	Vijayawada	null	Andhra Pradesh	Silver	null	Silver	Regular	2026-01-01	2026-04-04	FALSE
-- 102	103	Rahul Verma	Chennai	Vijayawada	Tamil Nadu	Gold	Silver	Gold	Premium	2026-04-05	9999-12-31	TRUE
-- 4	104	Neha Patel	Hyderabad	null	Telangana	Gold	null	Gold	Premium	2026-01-01	2026-04-09	FALSE
-- 103	104	Neha Patel	Hyderabad	Hyderabad	Telangana	Platinum	Gold	Platinum	Premium	2026-04-10	9999-12-31	TRUE
-- 5	105	Arjun Gupta	Nagpur	null	Maharashtra	Bronze	null	Bronze	Regular	2026-01-01	9999-12-31	TRUE

-- **Step 3:** Synchronize `CURRENT_MEMBERSHIP`, `PREVIOUS_MEMBERSHIP`, `CITY`, and `STATE` across 
--**all** historical rows for affected customers so current profile attributes match everywhere.
update dim_cust_hybrid 
set city=u.city,
state=u.state,
current_membership=u.membership,
previous_membership=h2.previous_membership
from cust_updates u join dim_cust_hybrid h2 on u.customer_id=h2.customer_id and h2.is_current=true
join dim_cust_hybrid  h on u.customer_id=h.customer_id and h.is_current=false;

select * from dim_cust_hybrid order by customer_id;
-- it changes the current and previous columns to match the active version but leaves historical column as it is because for analysis purpose
-- Amit Sharma	Bengaluru		Karnataka	Gold	Silver	Silver	Regular	2026-01-01	2026-03-31	FALSE
-- Amit Sharma	Bengaluru	Hyderabad	Karnataka	Gold	Silver	Gold	Premium	2026-04-01	9999-12-31	TRUE
-- Priya Reddy	Bengaluru		Karnataka	Gold	Silver	Gold	Premium	2026-01-01	9999-12-31	TRUE
-- Rahul Verma	Bengaluru		Karnataka	Gold	Silver	Silver	Regular	2026-01-01	2026-04-04	FALSE
-- Rahul Verma	Bengaluru	Vijayawada	Karnataka	Gold	Silver	Gold	Premium	2026-04-05	9999-12-31	TRUE
-- Neha Patel	Bengaluru		Karnataka	Gold	Silver	Gold	Premium	2026-01-01	2026-04-09	FALSE
-- Neha Patel	Bengaluru	Hyderabad	Karnataka	Gold	Silver	Platinum	Premium	2026-04-10	9999-12-31	TRUE
-- Arjun Gupta	Bengaluru		Karnataka	Gold	Silver	Bronze	Regular	2026-01-01	9999-12-31	TRUE

-- TASK 11 — Insert Q2 2026 Sales Transaction
insert into fact_sales(transaction_id,transaction_date,customer_key ,store_key ,product_key ,quantity ,unit_price ,total_amount)
select 'TXN-2001','2026-04-15',c.customer_key ,s.store_key ,p.product_key ,1 ,p.unit_price ,
1*p.unit_price from dim_cust_hybrid c
join dim_stores s on s.store_id=201
join dim_products p on p.product_id=503
where customer_id=101 and is_current=true;
-- number of rows inserted
-- 1

select * from fact_sales;
-- SALES_KEY   TRANSACTION_ID  TRANSACTION_DATE  CUSTOMER_KEY  PRODUCT_KEY  QUANTITY  UNIT_PRICE  TOTAL_AMOUNT
-- 1	TXN-1001	2026-02-15	1	1	1	1	75000.00	75000.00
-- 2	TXN-1002	2026-03-10	3	3	2	2	1500.00	3000.00
-- 101	TXN-2001	2026-04-15	101	1	3	1	12000.00	12000.00

-- TASK 12 — Display Full Customer Dimension History
select * from dim_cust_hybrid order by customer_id,effective_date;
-- Amit Sharma	Bengaluru		Karnataka	Gold	Silver	Silver	Regular	2026-01-01	2026-03-31	FALSE
-- Amit Sharma	Bengaluru	Hyderabad	Karnataka	Gold	Silver	Gold	Premium	2026-04-01	9999-12-31	TRUE
-- Priya Reddy	Bengaluru		Karnataka	Gold	Silver	Gold	Premium	2026-01-01	9999-12-31	TRUE
-- Rahul Verma	Bengaluru		Karnataka	Gold	Silver	Silver	Regular	2026-01-01	2026-04-04	FALSE
-- Rahul Verma	Bengaluru	Vijayawada	Karnataka	Gold	Silver	Gold	Premium	2026-04-05	9999-12-31	TRUE
-- Neha Patel	Bengaluru		Karnataka	Gold	Silver	Gold	Premium	2026-01-01	2026-04-09	FALSE
-- Neha Patel	Bengaluru	Hyderabad	Karnataka	Gold	Silver	Platinum	Premium	2026-04-10	9999-12-31	TRUE
-- Arjun Gupta	Bengaluru		Karnataka	Gold	Silver	Bronze	Regular	2026-01-01	9999-12-31	TRUE

-- TASK 13 — Point-in-Time Point-of-Sale Analytics Query
select f.transaction_id ,f.transaction_date, c.customer_id,  c.customer_name,  c.city as CURRENT_CITY,
c.historical_membership as MEMBERSHIP_AT_PURCHASE,c.SEGMENT AS SEGMENT_AT_PURCHASE,s.store_name,p.product_name,f.total_amount
from fact_sales f join dim_cust_hybrid c on f.customer_key=c.customer_key
join dim_stores s on f.store_key=s.store_key
join dim_products p on f.product_key=p.product_key
where c.customer_id=101 order by transaction_date;

-- TXN-1001	2026-02-15	101	Amit Sharma	Bengaluru	Silver	Regular	Metro Flagship	Laptop Pro	75000.00
-- TXN-2001	2026-04-15	101	Amit Sharma	Bengaluru	Gold	Premium	Metro Flagship	Ergonomic Chair	12000.00

--TASK 14 — Warehouse Record Count and Data Auditing Validation

select 'STORE DIMENSION RECORDS ' as METRIC,count(*) as VALUE from dim_stores 
union all
select 'PRODUCT DIMENSION RECORDS ' as METRIC,count(*) as VALUE from dim_products
union all
select 'TOTAL CUSTOMER DIMENSION RECORDS' as METRIC,
count(*) as VALUE from dim_cust_hybrid
union all
select 'CURRENT CUSTOMER RECORDS ' as METRIC,
count(*) as VALUE from dim_cust_hybrid where is_current=true
union all
select 'HISTORICAL CUSTOMER RECORDS' as METRIC,
count(*) as VALUE from dim_cust_hybrid where is_current=false
union all 
select 'FACT SALES TRANSACTIONS ' as METRIC,
count(*) as VALUE from fact_sales;
-- METRIC                            VALUE
-- ---------------------------------------
-- STORE DIMENSION RECORDS           3
-- PRODUCT DIMENSION RECORDS         4
-- TOTAL CUSTOMER DIMENSION RECORDS  8
-- CURRENT CUSTOMER RECORDS          5
-- HISTORICAL CUSTOMER RECORDS       3
-- FACT SALES TRANSACTIONS           3
create warehouse retail_13a
warehouse_size='xsmall'
auto_suspend=60;
auto_resume=true;
--TASK 1 — Create Database and Schema Context
create database retail_db13a;
create schema retail_schema;

use database retail_db13a;
use schema retail_schema;

create file format csv_format
type=csv
field_delimiter=','
skip_header=1;

create stage retail_stage;


create table reg_stores(store_id number ,
store_name varchar(30),
city varchar(30),
state varchar(30),
region_name varchar(30),
regional_manager varchar(30)
);

create table product13(
product_id number,
product_name varchar(30),
subcategory_name varchar(30),
category_name varchar(30),
unit_price varchar(30)
);

create table custom13(
customer_id number ,
customer_name varchar(30),
city varchar(30),
state varchar(30)
);

create table sales_trans(
transaction_id varchar(30),
transaction_date date,
customer_id number,
store_id number,
product_id number,
quantity number,
unit_price number(10,2)
);

copy into reg_stores 
from @retail_stage/reg_stores.csv
file_format=csv_format;

copy into sales_trans
from @retail_stage/sales_trans.csv
file_format=csv_format;

copy into product13 
from @retail_stage/products_13.csv
file_format=csv_format;

copy into custom13
from @retail_stage/custom13.csv
file_format=csv_format;

--TASK 2 — Create Denormalized Star Schema Store Dimension (`STAR_DIM_STORE`)
create table star_dim_store(
store_key number autoincrement primary key,
store_id number ,
store_name varchar(30),
city varchar(30),
state varchar(30),
region_name varchar(30),
regional_manager varchar(30)
);

--TASK 3 — Create Denormalized Star Schema Product Dimension (`STAR_DIM_PRODUCT`)
create table star_dim_product(
product_key number autoincrement primary key,
product_id number,
product_name varchar(30),
subcategory_name varchar(30),
category_name varchar(30),
unit_price number(10,2)
);

--TASK 4 — Load Star Schema Dimensions & Create Star Fact Table (`STAR_FACT_SALES`)
insert into star_dim_store(store_id,store_name,city,state,region_name,regional_manager)
select store_id,store_name,city,state,region_name,regional_manager from reg_stores;

insert into star_dim_product(product_id,product_name,subcategory_name,category_name,unit_price)
select product_id,product_name,subcategory_name,category_name,unit_price from product13;

drop table star_fact_sales;
create table star_fact_sales(
sales_key number autoincrement primary key,
transaction_id varchar(20),
transaction_date date,
customer_id number,
store_key number,
product_key number,
quantity number,
total_amount number(10,2),
foreign key(store_key) references star_dim_store(store_key),
foreign key(product_key) references star_dim_product(product_key)
);

--TASK 5 — Load Star Schema Fact Data
insert into star_fact_sales(transaction_id,transaction_date,customer_id,store_key,product_key,quantity,total_amount)
select t.transaction_id,t.transaction_date,t.customer_id,s.store_key,p.product_key,t.quantity,t.quantity*t.unit_price
from sales_trans t join star_dim_store s on t.store_id=s.store_id
join star_dim_product p on t.product_id=p.product_id;

--TASK 6 — Build Normalized Snowflake Schema Store Hierarchy
create table snow_dim_region(
region_key number autoincrement primary key,
region_name varchar(30),
regional_manager varchar(30)
);

create table snow_dim_store(
store_key number autoincrement primary key,
store_id number,
store_name varchar(30),
city varchar(30),
state varchar(30),
region_key number,
foreign key(region_key) references snow_dim_region(region_key)
);

--TASK 7 — Build Normalized Snowflake Schema Product Hierarchy
create table  snow_dim_category(category_key number autoincrement primary key,
category_name varchar(30)
);

create table snow_dim_subcategory(subcat_key number autoincrement primary key,
subcat_name varchar(30),category_key number,
foreign key(category_key) references snow_dim_category(category_key)
);

create table snow_dim_product(product_key number autoincrement primary key,
product_id number,
product_name varchar(30),
unit_price number(10,2),
subcat_key number,
foreign key(subcat_key) references snow_dim_subcategory(subcat_key)
);

--TASK 8 — Populate Snowflake Schema Normalized Dimensions
insert into snow_dim_region(region_name,regional_manager)
values('South','Rajesh Kumar'),('West','Sunil Verma');

insert into snow_dim_store(store_id,store_name,city,state,region_key)
select s.store_id,s.store_name,s.city,s.state,r.region_key from 
reg_stores s join snow_dim_region r on s.region_name=r.region_name;

insert into snow_dim_category(category_name)
select distinct category_name from product13;

insert into snow_dim_subcategory(subcat_name,category_key)
select p.subcategory_name,c.category_key from product13 p join 
snow_dim_category c on p.category_name=c.category_name;

select * from snow_dim_subcategory;

insert into snow_dim_product(product_id,product_name ,unit_price ,subcat_key)
select p.product_id,p.product_name,p.unit_price,s.subcat_key
from product13 p join snow_dim_subcategory s on p.subcategory_name=s.subcat_name;

select * from snow_dim_product;

--TASK 9 — Create Snowflake Schema Fact Table (`SNOW_FACT_SALES`) & Load Data
create table snow_fact_sales(
sales_key number autoincrement primary key,
transaction_id varchar(20),
transaction_date date,
customer_id number,
store_key number,
product_key number,
quantity number,
total_amount number(10,2),
foreign key(store_key) references snow_dim_store(store_key),
foreign key(product_key) references snow_dim_product(product_key)
);

insert into snow_fact_sales(transaction_id,transaction_date,customer_id,store_key,product_key,quantity,total_amount)
select t.transaction_id,t.transaction_date,t.customer_id,s.store_key,p.product_key,t.quantity,t.quantity*t.unit_price
from sales_trans t join snow_dim_store s on t.store_id=s.store_id
join snow_dim_product p on t.product_id=p.product_id;

--TASK 10 — Star Schema Analytics Query (Single-Hop Join Performance)
select s.region_name,p.category_name,sum(f.total_amount) as total_revenue from
star_fact_sales f join star_dim_store s on f.store_key=s.store_key
join star_dim_product p on f.product_key=p.product_key
group by s.region_name,p.category_name order by total_revenue desc;

--TASK 11 — Snowflake Schema Analytics Query (Multi-Hop Normalized Join)
select r.region_name,c.category_name,sum(f.total_amount) as total_revenue from 
snow_fact_sales f join snow_dim_store s on f.store_key=s.store_key
join snow_dim_region r on s.region_key=r.region_key
join snow_dim_product p on f.product_key=p.product_key
join snow_dim_subcategory d on p.subcat_key=d.subcat_key
join snow_dim_category c on d.category_key=c.category_key
group by r.region_name,c.category_name order by total_revenue desc;

--TASK 12 — Architectural Analysis: Compare Star vs. Snowflake Schemas
select 'Dimension Normalization Level' as METRIC_FEATURE,
'Denormalized (Flat)' as  STAR_SCHEMA ,
'Normalized (Hierarchical)' as SNOWFLAKE_SCHEMA
union all
select 'Total Dimension Tables' ,'2 Tables','5 Tables'
union all
select 'Joins for Category Revenue','2 Joins (Fact + 2 Dims)',' 4 Joins (Fact + 4 Dims)'
union all
select 'Data Redundancy', 'Higher (Repeated text)' ,'Lower (Normalized IDs)'
union all
select 'Query Simplicity',' High (Simple GROUP BY)','Lower (Requires nested FKs)';
  
-- METRIC_FEATURE                   STAR_SCHEMA             SNOWFLAKE_SCHEMA
-- Dimension Normalization Level	Denormalized (Flat)	    Normalized (Hierarchical)
-- Total Dimension Tables	        2 Tables	            5 Tables
-- Joins for Category Revenue	    2 Joins (Fact + 2 Dims)	 4 Joins (Fact + 4 Dims)
-- Data Redundancy	                Higher (Repeated text)   Lower (Normalized IDs)
-- Query Simplicity	                High (Simple GROUP BY)   Lower (Requires nested FKs)

--TASK 13 — Regional Manager Sales Performance Report
select s.regional_manager ,sum(f.quantity) as total_items_sold,sum(f.total_amount)
as total_sales_amount from star_fact_sales f join star_dim_store s 
on f.store_key=s.store_key group by s.regional_manager order by total_sales_amount desc;

--TASK 14 — Full Warehouse Architecture Audit & Record Count Verification

select 'Star Schema' as schema_type,'star_dim_store' as table_name,count(*)
as record_count from star_dim_store
union all
select 'Star schema','star_dim_product',count(*) from star_dim_product
union all
select 'Star schema','star_fact_sales',count(*) from star_fact_sales
union all 
select 'Snowflake schema','snow_dim_region',count(*) from snow_dim_region
union all
select 'Snowflake schema','snow_dim_store',count(*) from snow_dim_store
union all
select 'Snowflake schema','snow_dim_category',count(*) from snow_dim_category
union all
select 'Snowflake schema','snow_dim_subcategory',count(*) from snow_dim_subcategory
union all
select 'Snowflake schema','snow_dim_product',count(*) from snow_dim_product
union all
select 'Snowflake schema','snow_fact_sales',count(*) from snow_fact_sales;

-- SCHEMA_TYPE       TABLE_NAME           RECORD_COUNT
-- -------------------------------------------------
-- Star Schema       STAR_DIM_STORE       4
-- Star Schema       STAR_DIM_PRODUCT     4
-- Star Schema       STAR_FACT_SALES      5
-- Snowflake Schema  SNOW_DIM_REGION      2
-- Snowflake Schema  SNOW_DIM_STORE       4
-- Snowflake Schema  SNOW_DIM_CATEGORY    3
-- Snowflake Schema  SNOW_DIM_SUBCATEGORY 4
-- Snowflake Schema  SNOW_DIM_PRODUCT     4
-- Snowflake Schema  SNOW_FACT_SALES      5
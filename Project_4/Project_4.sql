create warehouse retail_dw
with warehouse_size='xsmall'
auto_suspend=60
auto_resume=true;

create database retail_database;

create schema retail_database.retail_schema;

use database retail_database;
use schema retail_schema;

create file format csv_format 
type=csv
field_delimiter=','
skip_header=1;

create stage retail_stage
file_format=csv_format;

create table dim_customer(
customer_id int primary key,
customer_name varchar(100),
city varchar(100),
state varchar(100),
membership varchar(100)
);

create table dim_product(
product_id int primary key,
product_name varchar(100),
category varchar(100),
brand varchar(100),
price decimal(15,2)
);

create table dim_branch(
branch_id int primary key,
branch_name varchar(150),
city varchar(100),
state varchar(100),
region varchar(50),
manager_name varchar(100)
);

create table dim_date(
date_id int primary key,
date date,
day int,
day_name varchar(20),
week_no int,
month varchar(20),
quarter varchar(10),
year int,
is_weekend varchar(10)
);

create table fact_sales(
sale_id int primary key,

customer_id int,
product_id int,
branch_id int,
date_id int,

quantity int,
total_amount decimal(15,2),

foreign key (customer_id) references dim_customer(customer_id),
foreign key (product_id) references dim_product(product_id),
foreign key (branch_id) references dim_branch(branch_id),
foreign key (date_id) references dim_date(date_id)
);

list @retail_stage;

copy into dim_customer
from @retail_stage/customers2.csv
file_format=csv_format;

copy into dim_product
from @retail_stage/products2.csv
file_format=csv_format;

copy into dim_branch
from @retail_stage/branches2.csv
file_format=csv_format;

copy into dim_date
from @retail_stage/calender.csv
file_format=csv_format;

copy into fact_sales
from @retail_stage/sales2.csv
file_format=csv_format

select count(*) from dim_customer;
select count(*) from dim_product;
select count(*) from dim_branch;
select count(*) from dim_date;
select count(*) from fact_sales;

-- Expected Output-4:Dimension Tables
show tables ->> select 'name' from $1 where 'name' like 'dim_%';

-- :Fact Table Structure;
desc table fact_sales;
-- Phase-4: Measure Identification
select sum(quantity) as total_quantity,sum(total_amount) as total_revenue from fact_sales;
//hence both are addiitive

-- Phase-5: Grain Identification
select sale_id,customer_id,product_id,date_id,quantity,total_amount from fact_sales;

-- Phase-6: Relationship Identification
select count(*) as total_sales,
count(distinct customer_id) as customers,
count(distinct product_id) as products,
count(distinct branch_id) as branches,
count(distinct date_id) as dates from fact_sales;

-- Phase-8: Business Validation
-- Customer Revenue Report
select c.customer_id,c.customer_name,sum(f.total_amount) as total_sales from dim_customer c 
join fact_sales f on c.customer_id=f.customer_id group by c.customer_id,c.customer_name
order by total_sales desc;

-- Product Revenue Report
select p.product_id,p.product_name,sum(f.total_amount) as total_revenue from dim_product p
join fact_sales f on p.product_id=f.product_id group by p.product_id,p.product_name
order by total_revenue desc;

-- Branch Performance Report
select b.branch_id,b.branch_name,sum(f.total_amount) as total_Sales from dim_branch b
join fact_sales f on b.branch_id=f.branch_id  group by b.branch_id,b.branch_name
order by total_Sales desc;

-- Monthly Revenue Report
select d.month,d.year,sum(f.total_amount) as monthly_revenue from dim_date d
join fact_sales f on d.date_id=f.date_id  group by d.month,d.year
order by  min(d.date_id);

-- State-wise Sales Report
select b.state,sum(f.total_amount) as total_Sales from dim_branch b
join fact_sales f on b.branch_id=f.branch_id  group by b.state
order by total_Sales desc;

-- Category-wise Revenue Report
select p.category,sum(f.total_amount) as total_revenue from dim_product p
join fact_sales f on p.product_id=f.product_id group by p.category
order by total_revenue desc;

-- Top Customers
select c.customer_id,c.customer_name,sum(f.total_amount) as total_sales from dim_customer c 
join fact_sales f on c.customer_id=f.customer_id group by c.customer_id,c.customer_name
order by total_sales desc limit 5;

-- Top Products
select p.product_id,p.product_name,sum(f.total_amount) as total_revenue from dim_product p
join fact_sales f on p.product_id=f.product_id group by p.product_id,p.product_name
order by total_revenue desc limit 5;

-- Sales Trend Analysis
select d.date,sum(f.total_amount) as daily_revenue from dim_date d
join fact_sales f on d.date_id=f.date_id  group by d.date
order by  d.date;




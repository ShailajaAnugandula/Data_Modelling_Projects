-- Phase-1
-- Business Process:
-- Retail Sales Analytics

-- Business Event:
-- A customer purchases one or more products from a retail branch on a specific date.
-- Phase-2
create warehouse retail_star_wh
warehouse_size='xsmall'
auto_suspend=60
auto_resume=true;

create database retail_star_db;
create schema retail_star_db.retail_star_schema;

use database retail_star_db;
use schema retail_star_schema;

create file format csv_format
type=csv
field_delimiter=','
skip_header=1
field_optionally_enclosed_by='"'
null_if=('NULL','null');

create stage retail_stage file_format=csv_format;

create table dim_customer(
customer_id int primary key,
customer_name varchar(100),
city varchar(100),
state varchar(100),
membership varchar(50)
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
branch_name varchar(100),
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

desc table fact_sales;
desc table dim_customer;
desc table dim_product;
desc table dim_branch;
desc table dim_date;

show imported keys in table fact_sales;

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
file_format=csv_format;

select count(*) from dim_customer;
select count(*) from dim_product;
select count(*) from dim_branch;
select count(*) from dim_date;
select count(*) from fact_sales;


-- Customer-wise Sales Report    |
select c.customer_id,c.customer_name,sum(f.total_amount) as total_sales from dim_customer c 
join fact_sales f on c.customer_id=f.customer_id group by c.customer_id,c.customer_name
order by total_sales desc;

-- | Product-wise Revenue Report   |
select p.product_id,p.product_name,sum(f.total_amount) as total_revenue from dim_product p
join fact_sales f on p.product_id=f.product_id group by p.product_id,p.product_name
order by total_revenue desc;

-- | Branch-wise Revenue Report    |
select b.branch_id,b.branch_name,sum(f.total_amount) as total_Sales from dim_branch b
join fact_sales f on b.branch_id=f.branch_id  group by b.branch_id,b.branch_name
order by total_Sales desc;

-- | State-wise Revenue Report     |
select b.state,sum(f.total_amount) as total_Sales from dim_branch b
join fact_sales f on b.branch_id=f.branch_id  group by b.state
order by total_Sales desc;

-- | Monthly Revenue Report        |
select d.month,d.year,sum(f.total_amount) as monthly_revenue from dim_date d
join fact_sales f on d.date_id=f.date_id  group by d.month,d.year
order by  min(d.date_id);

-- | Quarterly Revenue Report      |
select d.quarter,sum(f.total_amount) as monthly_revenue from dim_date d
join fact_sales f on d.date_id=f.date_id  group by d.quarter
order by  monthly_revenue;

-- | Top 10 Customers              |
select c.customer_id,c.customer_name,sum(f.total_amount) as total_sales from dim_customer c 
join fact_sales f on c.customer_id=f.customer_id group by c.customer_id,c.customer_name
order by total_sales desc limit 10;

-- | Top 10 Products               |
select p.product_id,p.product_name,sum(f.total_amount) as total_revenue from dim_product p
join fact_sales f on p.product_id=f.product_id group by p.product_id,p.product_name
order by total_revenue desc limit 10;

-- | Top 10 Branches               |
select b.branch_id,b.branch_name,sum(f.total_amount) as total_Sales from dim_branch b
join fact_sales f on b.branch_id=f.branch_id  group by b.branch_id,b.branch_name
order by total_Sales desc limit 10;

-- | Category-wise Revenue         |
select p.category,sum(f.total_amount) as total_revenue from dim_product p
join fact_sales f on p.product_id=f.product_id group by p.category
order by total_revenue desc;

-- | Customer Purchase Trend       |
select c.customer_name,d.month,count(f.sale_id) as purchase_count,sum(f.total_amount)
as total_sales from fact_sales f
join dim_customer c  on f.customer_id=c.customer_id
join dim_date d on f.date_id=d.date_id group by c.customer_name,d.month
order by c.customer_name,min(d.date_id);

-- | Product Performance Dashboard |
select p.product_id,p.product_name,p.category,p.brand,sum(f.quantity) AS units_sold,
sum(f.total_amount) AS total_revenue,count(f.sale_id) AS total_transactions
from fact_sales f join dim_product p on f.product_id = p.product_id
group by p.product_id,p.product_name,p.category,p.brand
ORDER BY total_revenue DESC;

-- | Branch Performance Dashboard  |
select b.branch_id, b.branch_name,b.city,b.state,b.region,count(f.sale_id) as total_transactions,
SUM(f.quantity) as total_quantity,SUM(f.total_amount) AS total_revenue
from fact_sales f join dim_branch b
on f.branch_id = b.branch_id
group by b.branch_id,b.branch_name,b.city,b.state,b.region
order by total_revenue desc;

-- | Sales Trend Analysis 
select d.date,sum(f.total_amount) as daily_revenue from dim_date d
join fact_sales f on d.date_id=f.date_id  group by d.date
order by  d.date;
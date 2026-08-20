create warehouse retail_snow_wh
warehouse_size='xsmall'
auto_suspend=60
auto_resume=true;

create database retail_snow_db;
create schema retail_snow_db.retail_snow_schema;

use database retail_snow_db;
use schema retail_snow_schema;

create file format csv_format
type=csv
field_delimiter=','
skip_header=1
field_optionally_enclosed_by='"'
null_if=('NULL','null');

create stage retail_stage file_format=csv_format;

create table dim_region(
region_id int primary key,
region_name varchar(50)
);

create table dim_state(
state_id int primary key,
state_name varchar(25),
region_id int,
foreign key (region_id) references dim_region(region_id)
);

create table dim_city(
city_id int primary key,
city_name varchar(35),
state_id int,
foreign key (state_id) references dim_state(state_id)
);
-- drop table dim_category;
-- drop table dim_categoryy;
create table dim_category(
category_id int primary key,
category_name varchar(35)
);

create table dim_brand(
brand_id int primary key,
brand_name varchar(50),
category_id int,
foreign key (category_id) references dim_category(category_id)
);

create table year(
year_id int primary key,
year_value int
);

create table quarter(
quarter_id int primary key,
quarter_name varchar(50),
year_id int,foreign key (year_id) references year(year_id)
);

create table month(
month_id int primary key,
month_name varchar(20),
quarter_id int,
foreign key (quarter_id) references quarter(quarter_id)
);

create table dim_customer(
customer_id int primary key,
customer_name varchar(100),
city_id int,
membership varchar(50),
foreign key (city_id) references dim_city(city_id)
);

drop table dim_product;
create table dim_product(
product_id int primary key,
product_name varchar(100),
brand_id int,
price decimal(15,2),
foreign key (brand_id) references dim_brand(brand_id)
);

drop table dim_branch;
create table dim_branch(
branch_id int primary key,
branch_name varchar(100),
city_id int,
manager_name varchar(100),
foreign key (city_id) references dim_city(city_id)
);

create table dim_date(
date_id int primary key,
date date,
day int,
day_name varchar(20),
week_no int,
month_id int,
is_weekend varchar(10),
foreign key (month_id) references month(month_id)
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

CREATE TABLE CUSTOMERS (
    CUSTOMER_ID INT,
    CUSTOMER_NAME VARCHAR,
    CITY VARCHAR,
    STATE VARCHAR,
    MEMBERSHIP VARCHAR
);

CREATE TABLE PRODUCTS (
    PRODUCT_ID INT,
    PRODUCT_NAME VARCHAR,
    CATEGORY VARCHAR,
    BRAND VARCHAR,
    PRICE NUMBER(12,2)
);

CREATE TABLE BRANCHES (
    BRANCH_ID INT,
    BRANCH_NAME VARCHAR,
    CITY VARCHAR,
    STATE VARCHAR,
    REGION VARCHAR,
    MANAGER_NAME VARCHAR
);

CREATE TABLE CALENDAR (
    DATE_ID INT,
    DATE DATE,
    DAY INT,
    DAY_NAME VARCHAR,
    WEEK_NO INT,
    MONTH VARCHAR,
    QUARTER VARCHAR,
    YEAR INT,
    IS_WEEKEND VARCHAR
);

CREATE TABLE SALES (
    SALE_ID INT,
    CUSTOMER_ID INT,
    PRODUCT_ID INT,
    BRANCH_ID INT,
    DATE_ID INT,
    QUANTITY INT,
    TOTAL_AMOUNT NUMBER(12,2)
);


copy into customers
from @retail_stage 
file_format=csv_format
pattern='.*customers2.*csv';

copy into products
from @retail_stage/products2.csv
file_format=csv_format;

copy into branches
from @retail_stage/branches2.csv
file_format=csv_format;

copy into calendar
from @retail_stage/calender.csv
file_format=csv_format;

copy into fact_sales
from @retail_stage/sales2.csv
file_format=csv_format;

insert into dim_region(region_id,region_name)
select distinct 
case region
when 'North' then 1
when 'South' then 2
when 'East' then 3
when 'West' then 4
end,
region from branches;

select * from dim_region;

insert into dim_state(state_id,state_name,region_id)
select distinct
    case state
        when'Telangana' then 1
        when 'Karnataka' then 2
        when 'Tamil Nadu' then 3
        when 'Maharashtra' then 4
        when 'Delhi' then 5
        when 'Gujarat' then 6
        when 'West Bengal' then 7
        when 'Rajasthan' then 8
        when 'Kerala' then 9
        when 'Uttar Pradesh' then 10
        when 'Andhra Pradesh' then 11
        when 'Bihar' then 12
        when 'Madhya Pradesh' then 13
        when 'Chandigarh' then 14
    end as state_id,
    state,
    case state
        WHEN 'Telangana' THEN 2
        WHEN 'Karnataka' THEN 2
        WHEN 'Tamil Nadu' THEN 2
        WHEN 'Maharashtra' THEN 4
        WHEN 'Delhi' THEN 1
        WHEN 'Gujarat' THEN 4
        WHEN 'West Bengal' THEN 3
        WHEN 'Rajasthan' THEN 1
        WHEN 'Kerala' THEN 2
        WHEN 'Uttar Pradesh' THEN 1
        WHEN 'Andhra Pradesh' THEN 2
        WHEN 'Bihar' THEN 1
        WHEN 'Madhya Pradesh' THEN 1
        WHEN 'Chandigarh' THEN 1
    end as region_id
from branches;

insert into dim_city(city_id,city_name,state_id) 
select distinct 
row_number() over(order by city),city,s.state_id from branches b join dim_state s on b.state=s.state_name;

insert into dim_category(category_id,category_name)
select distinct row_number() over(order by category),category from products;

insert into dim_brand(brand_id,brand_name,category_id)
select row_number() over(order by p.brand),p.brand,c.category_id
from products p join dim_category c on p.category=c.category_name;
);

insert into year(year_id,year_value)
select distinct year,year from calendar;

insert into quarter(quarter_id,quarter_name,year_id)
select distinct case quarter
when 'Q1' then 1
when 'Q2' then 2
when 'Q3' then 3
when 'Q4' then 4
end ,
quarter,year from calendar;

insert into month(month_id,month_name,quarter_id)
select distinct
case month 
when 'January' then 1
when 'February' then 2
when 'March' then 3
when 'April' then 4
when 'May' then 5
when 'June' then 6
when 'July' then 7
when 'August' then 8
when 'September' then 9
when 'October' then 10
when 'November' then 11
when 'December' then 12
end,
month,
case quarter
when 'Q1' then 1
when 'Q2' then 2
when 'Q3' then 3
when 'Q4' then 4
end
from calendar;

select * from dim_region;
select * from dim_state;
select * from dim_city;
select * from dim_category;
select * from dim_brand;
select * from year;
select * from month;
select * from quarter;


insert into dim_customer(customer_id,customer_name,city_id,membership)
select c.customer_id,c.customer_name,ci.city_id,c.membership 
from customers c join dim_city ci on c.city=ci.city_name;

insert into dim_product(product_id,product_name,brand_id,price)
select p.product_id,p.product_name,b.brand_id,p.price 
from products p join dim_brand b on p.brand=b.brand_name;

insert into dim_branch(branch_id,branch_name,city_id,manager_name)
select b.branch_id,b.branch_name,c.city_id,b.manager_name from
branches b join dim_city c on b.city=c.city_name;

insert into dim_date(date_id,date,day,day_name,week_no,month_id,is_weekend)
select c.date_id ,c.date ,c.day,c.day_name ,c.week_no ,m.month_id ,c.is_weekend
from calendar c join month m on c.month=m.month_name;

select * from dim_customer;
select * from dim_product;
select * from dim_branch;
select * from dim_date;

-- Phase 5 — validate FACT_SALES relationships with the normalized dimensions.

select count(*) as unmatched_customers from fact_sales f
left join dim_customer c on f.customer_id=c.customer_id where c.customer_id is null;

select count(*) as unmatched_products from fact_sales f
left join dim_product p on f.product_id=p.product_id where p.product_id is null;

select count(*) as unmatched_branches from fact_sales f
left join dim_branch b on f.branch_id=b.branch_id where b.branch_id is null;

select count(*) as unmatched_dates from fact_sales f
left join dim_date d on f.date_id=d.date_id where d.date_id is null;

-- every query should return 0 as count
-- overall validation
select count(*) as total_Sales,
count(distinct customer_id) as customers,
count(distinct product_id) as products,
count(distinct branch_id) as branches,
count(distinct date_id) as dates from fact_sales;

select count(*) from fact_sales;

-- Customer-wise Sales Report
select c.customer_id,c.customer_name,sum(f.total_amount) as total_sales from 
dim_customer c join fact_sales f on c.customer_id=f.customer_id
group by  c.customer_id,c.customer_name order by total_sales desc;

-- Product-wise Revenue Report
select p.product_id,p.product_name,sum(f.total_amount) as total_sales from 
dim_product p join fact_sales f on p.product_id=f.product_id
group by  p.product_id,p.product_name order by total_sales desc;

-- Brand-wise Revenue Report
select b.brand_id,b.brand_name,sum(f.total_amount) as total_revenue from 
dim_product p join fact_sales f on p.product_id=f.product_id
join dim_brand b on b.brand_id=p.brand_id
group by b.brand_id,b.brand_name order by total_revenue desc;

-- Category-wise Revenue Report\
select c.category_id,c.category_name,sum(f.total_amount) as total_revenue from 
dim_product p join fact_sales f on p.product_id=f.product_id
join dim_brand b on b.brand_id=p.brand_id
join dim_category c on b.category_id=c.category_id
group by c.category_id,c.category_name order by total_revenue desc;

-- City-wise Sales Report
select d.city_id,d.city_name,sum(f.total_amount) as total_revenue from
dim_customer c join fact_sales f on f.customer_id=c.customer_id
join dim_city d on c.city_id=d.city_id 
group by d.city_id,d.city_name order by total_revenue desc;

-- State-wise Revenue Report
select s.state_id,s.state_name,sum(f.total_amount) as total_revenue 
from dim_customer c join fact_sales f on c.customer_id=f.customer_id
join dim_city d on c.city_id=d.city_id
join dim_state s on d.state_id=s.state_id 
group by s.state_id,s.state_name order by total_revenue desc;


-- Region-wise Revenue Report
select r.region_id,r.region_name,sum(f.total_amount) as total_revenue 
from dim_branch b join fact_sales f on b.branch_id=f.branch_id
join dim_city c on c.city_id=b.city_id
join dim_state s on c.state_id=s.state_id
join dim_region r on s.region_id=r.region_id 
group by r.region_id,r.region_name order by total_revenue desc;

-- Monthly Revenue Report
select m.month_id,m.month_name,sum(f.total_amount) as total_revenue 
from dim_date d join fact_sales f on d.date_id=f.date_id
join month m on d.month_id=m.month_id
group by m.month_id,m.month_name order by total_revenue desc;

-- Quarterly Revenue Report
select q.quarter_id,q.quarter_name,sum(f.total_amount) as total_revenue 
from dim_date d join fact_sales f on d.date_id=f.date_id
join month m on d.month_id=m.month_id
join quarter q on m.quarter_id=q.quarter_id
group by q.quarter_id,q.quarter_name order by total_revenue desc;

-- Top 10 Customers
select c.customer_id,c.customer_name,sum(f.total_amount) as total_revenue 
from dim_customer c join fact_sales f on c.customer_id=f.customer_id
group by c.customer_id,c.customer_name order by total_revenue desc limit 10;

-- Top 10 Products
select p.product_id,p.product_name,sum(f.total_amount) as total_sales from 
dim_product p join fact_sales f on p.product_id=f.product_id
group by  p.product_id,p.product_name order by total_sales desc limit 10;

-- Top 10 Branches
select b.branch_id,b.branch_name,sum(f.total_amount) as total_revenue from 
dim_branch b join fact_sales f on b.branch_id=f.branch_id
group by b.branch_id,b.branch_name order by total_revenue desc limit 10;

-- Customer Purchase Trend
select c.customer_id,c.customer_name,m.month_name,count(f.sale_id) as purchase_counr,sum(f.total_amount) as total_revenue
from dim_customer c join fact_sales f on c.customer_id=f.customer_id
join dim_date d on f.date_id=d.date_id
join month m on d.month_id=m.month_id
group by  c.customer_id,c.customer_name,m.month_name order by total_revenue ;

-- Product Performance Dashboard
select p.product_id,p.product_name,b.brand_name,c.category_name,count(f.sale_id) as total_transactions,
sum(f.quantity) as units_sold,sum(f.total_amount) as total_revenue from dim_product p
join fact_sales f on p.product_id=f.product_id
join dim_brand b on p.brand_id=b.brand_id
join dim_category c on b.category_id=c.category_id
group by p.product_id,p.product_name,b.brand_name,c.category_name order by total_revenue desc;

-- Regional Sales Dashboard
select r.region_id,r.region_name,count(distinct c.customer_id) as  number_of_customers,
count(f.sale_id) as number_of_orders,
sum(f.quantity) as quantity_sold,
sum(f.total_amount) as total_sales 
from dim_customer c join fact_sales f on c.customer_id=f.customer_id
join dim_city d on c.city_id=d.city_id
join dim_state s on s.state_id=d.state_id
join dim_region r on r.region_id=s.region_id
group by r.region_id,r.region_name order by total_sales desc;

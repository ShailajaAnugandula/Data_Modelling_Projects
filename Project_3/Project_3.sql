create warehouse enterprise_wh
with warehouse_size='xsmall'
auto_suspend=60
auto_resume=true;

create database enterprise_db;

create schema enterprise_db.sales_schema;

use database enterprise_db;
use schema sales_schema;

create file format csv_format 
type=csv
field_delimiter=','
skip_header=1;


create stage sales_stage
file_format=csv_format;


create table customers1(
customer_id int,
customer_name varchar(100),
city varchar(100),
membership varchar(50)
);


create table products1(
product_id int,
product_name varchar(100),
category varchar(100),
price number(12,2)
);

create table branches1(
branch_id int,
branch_name varchar(100),
state varchar(100)
);

create table sales(
sales_id int,
customer_id int,
product_id int,
branch_id int,
quantity int,
sale_date date,
total_amount number(12,2)
);


copy into customers1
from @sales_stage/customers1.csv
file_format=csv_format;

copy into products1
from @sales_stage/products1.csv
file_format=csv_format;

copy into branches1
from @sales_stage/branches1.csv
file_format=csv_format;

copy into sales
from @sales_stage/sales_history.csv
file_format=csv_format;

select * from customers1;
select * from products1;
select * from branches1;
select * from sales;

create stream sales_stream on table sales;
show streams;

create table sales_stage_table(
sales_id int,
customer_id int,
product_id int,
branch_id int,
quantity int,
sale_date date,
total_amount number(12,2)
);
copy into sales_stage_table
from @sales_stage/new_sales.csv
file_format=csv_format;

select * from sales_stage_table;

merge into sales as target
using sales_stage_table as source
on target.sales_id=source.sales_id
when not matched then insert(
sales_id,
customer_id,
product_id,
branch_id,
quantity,
sale_date,
total_amount
)
values(
source.sales_id,
source.customer_id,
source.product_id,
source.branch_id,
source.quantity,
source.sale_date,
source.total_amount
);

//14.Identify duplicate Sale IDs.
select sales_id,count(*) as duplicate_count from sales group by sales_id having count(*)>1;

//15.Identify missing Customer IDs.
select s.* from sales s left join customers1 c on s.customer_id=c.customer_id
where c.customer_id is null;

//16.Display invalid Product IDs.
select s.* from sales s left join products1 p on s.product_id=p.product_id
where p.product_id is null;

//17.Count total newly inserted records.
select count(*) from sales_stage_table;
select count(*) from sales_stream;

//18.Delete one sales record
delete from sales where sales_id=10;
-- select * from sales before (statement=>'01c65dce-3206-a990-0003-9b3e0007aa9e') where sales_id=10;
-- select * from sales at (timestamp=> '2026-08-13 10:48:42'::TIMESTAMP_LTZ) where sales_id=10;
SELECT *
FROM SALES
AT (OFFSET => -2900)
WHERE SALES_ID = 10;

//19.Recover the deleted record using Time Travel.
insert into sales select * from sales at (offset=> -2900) where sales_id=10;

//20.Verify recovery.
select * from sales where sales_id=10;
select count(*) from sales;

//21.Create a clone named: SALES_TEST
create table sales_test clone sales;

//22.Display cloned records.
select * from sales_test order by sales_id;

//23.Insert one new record into the clone.
insert into sales_test values( 11,1,105,1,2,'2026-07-11',24000);

//24.Verify that the original SALES table remains unchanged.
select * from sales_test where sales_id=11; 
select * from sales where sales_id=11;     

//25.Create a Task that automatically performs incremental loading every day.
select * from sales_stream;
select sales_id,customer_id,product_id,branch_id,quantity,sale_date,total_amount,
metadata$action,metadata$isupdate from sales_stream;

create task daily_sales_task
warehouse=enterprise_wh
schedule= 'USING CRON 0 2 * * * UTC'
as 
merge into sales as target
using sales_stage_table as source
on target.sales_id=source.sales_id
when not matched then insert(
sales_id,
customer_id,
product_id,
branch_id,
quantity,
sale_date,
total_amount
)
values(
source.sales_id,
source.customer_id,
source.product_id,
source.branch_id,
source.quantity,
source.sale_date,
source.total_amount
);

-- 26.Resume the Task.
alter task daily_sales_task resume;
-- 27.Verify Task execution.
execute task daily_sales_task;
select count(*) from sales;

-- 28.Customer Revenue Report
select c.customer_id,c.customer_name,sum(s.total_amount) as total_revenue from customers1 c 
join sales s on c.customer_id=s.customer_id group by c.customer_id,c.customer_name
order by total_revenue desc;

-- 29.Branch Revenue Report
select b.branch_id,b.branch_name,sum(s.total_amount) as total_revenue from branches1 b
join sales s on b.branch_id=s.branch_id group by b.branch_id,b.branch_name
order by total_revenue desc;

-- 30.Product Revenue Report
select p.product_id,p.product_name,sum(s.total_amount) as total_revenue from products1 p
join sales s on p.product_id=s.product_id group by p.product_id,p.product_name
order by total_revenue desc;

-- 31.Monthly Revenue Report
select date_trunc("month",sale_date) as month,sum(total_amount) as monthly_revenue from sales group by date_trunc("month",sale_date);

//32.Highest Revenue Customer
select c.customer_id,c.customer_name,sum(s.total_amount) as revenue from customers1 c 
join sales s on c.customer_id=s.customer_id group by c.customer_id,c.customer_name
order by revenue desc limit 1;

-- 33.Highest Revenue Branch
select b.branch_id,b.branch_name,sum(s.total_amount) as total_revenue from branches1 b
join sales s on b.branch_id=s.branch_id group by b.branch_id,b.branch_name
order by total_revenue desc limit 1;

//Top 5 products
select p.product_id,p.product_name,sum(s.total_amount) as total_revenue from products1 p
join sales s on p.product_id=s.product_id group by p.product_id,p.product_name
order by total_revenue desc limit 5;

-- 35.Customer Purchase Frequency
select c.customer_id,c.customer_name,count(s.sales_id) as frequency from customers1 c left join
sales s on c.customer_id=s.customer_id group by c.customer_id,c.customer_name
order by frequency;

//36.Running Revenue
select sales_id,sale_date,total_amount,sum(total_amount) over(order by sale_date,sales_id) as running_revenue
from sales order by sale_date,sales_id;

-- 37.Customer Ranking
select c.customer_id,c.customer_name,sum(s.total_amount) as total_revenue,rank() over(order by sum(s.total_amount) desc)
as customer_rank from customers1 c join sales s on c.customer_id=s.customer_id
group by c.customer_id,c.customer_name
order by customer_rank;

-- 38.Create View: CUSTOMER_REVENUE
-- 39.Create Materialized View: BRANCH_REVENUE
-- 40.Display data from both Views.
create view customer_revenue as
select c.customer_id,c.customer_name,sum(s.total_amount) as total_revenue from customers1 c 
join sales s on c.customer_id=s.customer_id group by c.customer_id,c.customer_name
order by total_revenue desc;

create view branch_revenue as
select b.branch_id,b.branch_name,sum(s.total_amount) as total_revenue from branches1 b
join sales s on b.branch_id=s.branch_id group by b.branch_id,b.branch_name
order by total_revenue desc;


select * from customer_revenue;
select * from branch_revenue;
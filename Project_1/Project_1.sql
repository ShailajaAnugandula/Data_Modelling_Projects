create warehouse sales_wh
with warehouse_size="xsmall"
auto_suspend=60
auto_resume=true;


use warehouse sales_wh;

create database customer_sales_db;

create schema sales_schema;
use database customer_sales_db;

use schema sales_schema;

create file format csv_format type=csv
field_delimiter=","
skip_header=1;

create stage sales_stage 
file_format=csv_format;


//select current_database(),current_schema();
create table customers
(
customer_id int,
first_name varchar(50),
last_name varchar(50),
email varchar(100),
phone varchar(20),
address varchar(100)
);



CREATE TABLE FOODITEMS
(
    FOOD_ID INT,
    NAME VARCHAR(100),
    PRICE NUMBER(10,2),
    CATEGORY VARCHAR(50),
    AVAILABILITY VARCHAR(20)
);

CREATE TABLE ORDERS
(
    ORDER_ID INT,
    CUSTOMER_ID INT,
    FOOD_ID INT,
    QUANTITY INT,
    ORDER_DATE TIMESTAMP,
    STATUS VARCHAR(20),
    TOTAL_AMOUNT NUMBER(10,2)
);


drop table customers;

CREATE TABLE CUSTOMERS
(
    CUSTOMER_ID INT,
    FIRST_NAME VARCHAR(50),
    LAST_NAME VARCHAR(50),
    EMAIL VARCHAR(100),
    PHONE VARCHAR(20),
    ADDRESS VARCHAR(100)
);

show tables;

CREATE FILE FORMAT CSV_FORMAT
TYPE = CSV
FIELD_DELIMITER = ','
SKIP_HEADER = 1;

COPY INTO CUSTOMERS
FROM @SALES_STAGE/customers.csv
FILE_FORMAT = (FORMAT_NAME = CSV_FORMAT);

COPY INTO FOODITEMS
FROM @SALES_STAGE/fooditems.csv
FILE_FORMAT = (FORMAT_NAME = CSV_FORMAT);

COPY INTO ORDERS
FROM @SALES_STAGE/orders.csv
FILE_FORMAT = (FORMAT_NAME = CSV_FORMAT);


select * from customers;
select * from fooditems;
select * from orders;

select c.customer_id,c.first_name||' '||c.last_name as customer_name,sum(o.total_amount)
as total_amount_spent from customers c join orders o on c.customer_id=o.order_id group by
c.customer_id,customer_name order by total_amount_spent desc;

select c.customer_id,c.first_name||' '||c.last_name as customer_name,sum(o.total_amount) as total_spent from 
customers c join orders o on c.customer_id=o.customer_id group by c.customer_id,customer_name
order by total_spent desc limit 1;


select sum(total_amount) as total_revenue from orders;

select f.category as Category,sum(o.total_amount) as Revenue from fooditems f join orders o on o.food_id=f.food_id where
group by f.category;

select status,sum(total_amount) as revenue from orders group by status order by revenue desc;

select rank() over(order by sum(o.total_amount) desc) as Rank,c.first_name||' '||c.last_name as customer_name,sum(o.total_amount) as total_spent from 
customers c join orders o on c.customer_id=o.customer_id group by c.customer_id,customer_name
limit 3;


select c.customer_id,c.first_name||' '||c.last_name as customer_name,count(o.quantity) as orders_placed from 
customers c join orders o on c.customer_id=o.customer_id group by c.customer_id,customer_name
order by orders_placed desc,c.customer_id ;

select order_id,customer_id,food_id,status,total_amount from orders where status='Delivered';

select o.order_id,c.first_name||' '||c.last_name as customer_name,o.order_date,o.status,o.total_amount from orders o
join customers c on o.customer_id=c.customer_id where date(order_date) >'2026-07-12';

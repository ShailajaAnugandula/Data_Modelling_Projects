create database facts_db_19a;
create schema facts_schema;

use database facts_db_19a;
use schema facts_schema;

create or replace file format csv_format
type=csv
field_delimiter=','
skip_header=1
null_if=('null');

create stage facts_stage;

create table raw_orders(
order_id varchar(10),
order_date date,
user_id varchar(10),
store_id varchar(20),
amount number(10,2),
tax number(5,2),
payment_method varchar(20),
shipping_option varchar(20),
gift_wrap_flag varchar(5)
);

create table raw_inventory(
snapshot_date date,
store_id varchar(20),
product_id varchar(10),
qty_on_hand number,
unit_cost number(12,2)
);

create or replace table raw_fulfillment(
order_id varchar(10),
order_date date,
pick_date date,
ship_date date,
delivery_date date
);

copy into raw_orders
from @facts_stage/raw_orders.csv
file_format=csv_format;

copy into  raw_inventory
from @facts_stage/raw_inventory.csv
file_format=csv_format;

COPY INTO RAW_FULFILLMENT
FROM @facts_stage/raw_fulfillment.csv
FILE_FORMAT = (
    TYPE = CSV
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER = 1
    NULL_IF = ('NULL')
);

select * from raw_orders;
select * from raw_inventory;
select * from raw_fulfillment;

--TASK 1: Build Junk Dimension Table
create table dim_order_indicators(
indicator_sk number,
payment_method varchar(20),
shipping_option varchar(20),
gift_wrap_flag varchar(5)
);

select distinct payment_method ,
shipping_option ,
gift_wrap_flag from raw_orders;
-- PAYMENT_METHOD	SHIPPING_OPTION	GIFT_WRAP_FLAG
-- UPI	Standard	N
-- Credit	Express	Y
-- Credit	Express	N
-- UPI	Express	Y
-- NetBanking	Standard	Y
-- Credit	Standard	N

insert into dim_order_indicators(indicator_sk ,payment_method ,shipping_option ,gift_wrap_flag)
select row_number() over(order by first_order_id) as indicator_sk,
payment_method ,shipping_option ,gift_wrap_flag from 
(select payment_method ,shipping_option ,gift_wrap_flag, min(order_id) 
as first_order_id from raw_orders group by payment_method ,shipping_option ,gift_wrap_flag);

select * from dim_order_indicators;
-- INDICATOR_SK	PAYMENT_METHOD	SHIPPING_OPTION	GIFT_WRAP_FLAG
--          1	Credit   	Express	     Y
--          2	UPI	       Standard	     N
--          3	Credit   	Express    	 N
--          4	NetBanking	 Standard  	Y
--          5	UPI	         Express	Y
--          6	Credit	     Standard	N

--TASK 2: Build Transaction Fact Table with Degenerate Dimension
create table fact_sales_transaction(
order_id varchar(10),
order_date date,
user_id varchar(10),
store_id varchar(20),
indicator_sk number,
amount number(10,2),
tax number(5,2)
);

insert into fact_sales_transaction(order_id ,order_date ,user_id ,store_id, indicator_sk ,amount ,tax )
select o.order_id ,o.order_date ,o.user_id ,o.store_id, d.indicator_sk ,o.amount ,o.tax
from raw_orders o join dim_order_indicators d on o.payment_method = d.payment_method and
o.shipping_option = d.shipping_option and
o.gift_wrap_flag = d.gift_wrap_flag;


select * from fact_sales_transaction;
-- ORDER_ID	ORDER_DATE	USER_ID	STORE_ID	INDICATOR_SK	AMOUNT	TAX
-- ORD-101	2026-08-20	U-401	STR-10	1	120.00	10.00
-- ORD-102	2026-08-20	U-402	STR-10	2	250.00	20.00
-- ORD-103	2026-08-21	U-403	STR-11	3	75.00	5.00
-- ORD-104	2026-08-21	U-404	STR-11	4	410.00	30.00
-- ORD-105	2026-08-22	U-401	STR-10	5	190.00	15.00
-- ORD-106	2026-08-22	U-405	STR-12	6	310.00	25.00

select order_id,indicator_sk,amount from fact_sales_transaction;
-- ORDER_ID	INDICATOR_SK	AMOUNT
-- ORD-101	1	120.00
-- ORD-102	2	250.00
-- ORD-103	3	75.00
-- ORD-104	4	410.00
-- ORD-105	5	190.00
-- ORD-106	6	310.00

--TASK 3: Periodic Snapshot Rollup & Semi-Additive Metrics
create table fact_inventory_snapshot(
snapshot_date date,
store_id varchar(20),
total_units_held number,
total_inventory_val number(10,2)
);

insert into fact_inventory_snapshot(snapshot_date ,store_id ,total_units_held ,total_inventory_val)
select snapshot_date ,store_id,sum(qty_on_hand) as total_units_held ,
sum(qty_on_hand * unit_cost) as total_inventory_val from raw_inventory
group by snapshot_date ,store_id ;

select * from fact_inventory_snapshot order by total_units_held;
-- SNAPSHOT_DATE	STORE_ID	TOTAL_UNITS_HELD	TOTAL_INVENTORY_VAL
-- 2026-08-24	STR-10	150	3750.00
-- 2026-08-25	STR-10	180	5250.00
-- 2026-08-24	STR-11	280	4500.00

--TASK 4: Accumulating Milestone Lag Duration Calculations
create or replace table fact_order_fulfillment(
order_id varchar(10),
order_date date,
pick_date date,
ship_date date,
delivery_date date,
pick_lag_days number,
ship_lag_days number,
delivery_lag_days number,
total_fulfillment_days number
);

insert into fact_order_fulfillment(order_id ,order_date ,pick_date ,ship_date ,delivery_date ,
pick_lag_days ,ship_lag_days ,delivery_lag_days,total_fulfillment_days)
select order_id ,order_date ,pick_date ,ship_date ,delivery_date ,
datediff('day',order_date,pick_date)as pick_lag_days ,
datediff('day',pick_date,ship_date) as ship_lag_days ,
datediff('day',ship_date,delivery_date) as delivery_lag_days,
datediff('day',order_date,delivery_date) as total_fulfillment_days
from raw_fulfillment;

select * from fact_order_fulfillment;
-- ORDER_ID	ORDER_DATE	PICK_DATE	SHIP_DATE	DELIVERY_DATE	PICK_LAG_DAYS	SHIP_LAG_DAYS	DELIVERY_LAG_DAYS	TOTAL_FULFILLMENT_DAYS
-- ORD-101	   2026-08-20	2026-08-21	2026-08-21	2026-08-23	        1	         0	   2	3
-- ORD-102	   2026-08-20	2026-08-20	2026-08-22	2026-08-24	        0	         2	   2 	4
-- ORD-103    2026-08-21	2026-08-21	2026-08-22	2026-08-25	        0	         1	   3	4
-- ORD-104	   2026-08-21	2026-08-22		null	   null             1           null  null  null	
-- ORD-105	   2026-08-22	2026-08-22	2026-08-23		null            0	         1	  null   null	
-- ORD-106	   2026-08-22	2026-08-23	2026-08-24	2026-08-26	        1	         1	   2	  4

select * from fact_order_fulfillment where delivery_lag_days is not null;
-- ORDER_ID	ORDER_DATE	PICK_DATE	SHIP_DATE	DELIVERY_DATE	PICK_LAG_DAYS	SHIP_LAG_DAYS	DELIVERY_LAG_DAYS	TOTAL_FULFILLMENT_DAYS
-- ORD-101	2026-08-20	2026-08-21	2026-08-21	2026-08-23	1	0	2	3
-- ORD-102	2026-08-20	2026-08-20	2026-08-22	2026-08-24	0	2	2	4
-- ORD-103	2026-08-21	2026-08-21	2026-08-22	2026-08-25	0	1	3	4
-- ORD-106	2026-08-22	2026-08-23	2026-08-24	2026-08-26	1	1	2	4

-- TASK 5: Incomplete Lifecycle Status Auditing
select order_id,order_date,case when pick_lag_days is not null and
                                     ship_lag_days is null then 'PICKED_NOT_SHIPPED'
                                when ship_lag_days is not null and
                                      delivery_lag_days is null then 'SHIPPED_NOT_DELIVERED' 
                            end as current_status
                            from fact_order_fulfillment where delivery_date is null;

-- ORDER_ID	ORDER_DATE	CURRENT_STATUS
-- ORD-104	2026-08-21	PICKED_NOT_SHIPPED
-- ORD-105	2026-08-22	SHIPPED_NOT_DELIVERED

--TASK 6: Aggregate Revenue Summary by Junk Dimension Indicators
select d.payment_method,
count(f.order_id) as total_orders,
sum(amount) as total_revenue from
dim_order_indicators d join fact_sales_transaction f 
on d.indicator_sk=f.indicator_sk group by d.payment_method
order by d.payment_method;
--PAYMENT_METHOD	TOTAL_ORDERS	TOTAL_REVENUE
-- Credit	   3	505.00
-- NetBanking	1	410.00
-- UPI	       2	440.00
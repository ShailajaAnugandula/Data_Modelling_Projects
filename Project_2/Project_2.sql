create warehouse retail_wh
with warehouse_size="xsmall"
auto_suspend=60
auto_resume=true;

use warehouse retail_wh;

create database retail_db;
create schema sales_schema;
use database retail_db;
use schema sales_schema;

create file format csv_format type= csv
field_delimiter=","
skip_header=1;

create stage sales file_format=csv_format;

create table customer
(
customer_id int,
customer_name varchar(50),
city varchar(100),
membership varchar(20)
);

create table products
(
product_id int,
product_name varchar(100),
category varchar(50),
price number(10,2)

);

create table branches
(
branch_id int,
branch_name varchar(100),
city varchar(100)
);

create table sales
(
sale_id int,
customer_id int,
product_id int,
branch_id int,
quantity int,
sale_date date,
total_amount number(10,2)
);

copy into customer from @sales/customer.csv
file_format=(format_name=csv_format);

copy into products from @sales/products.csv
file_format=(format_name=csv_format);

copy into branches from @sales/branches.csv
file_format=(format_name=csv_format);

copy into sales from @sales/sales.csv
file_format=(format_name=csv_format);

select * from customer;
select * from products;
select * from branches;
select * from sales;

//total business revenue
select sum(total_amount) as total_revenue from sales;

//customer-wise sales.
select c.customer_id,c.cutsomer_name,sum(s.total_amount) from customer c join sales s
on c.customer_id=s.customer_id group by c.customer_id,c.cutsomer_name;

//branch-wise sales.
select b.branch_id,b.branch_name,sum(s.total_amount) total_sales from branches b join sales s
on b.branch_id=s.branch_id group by b.branch_id,branch_name order by total_sales desc;

//Generate product-wise sales.
select p.product_id,p.product_name,sum(total_amount) as total_sales from products p join sales s on p.product_id=s.product_id
group by p.product_id,p.product_name order by total_sales desc;


//Generate category-wise sales.
select p.category,sum(s.total_amount) as total_sales from products p join sales s
on p.product_id=s.product_id group by p.category order by total_sales desc;

//Display the highest revenue branch.
select b.branch_name,sum(s.total_amount) as total_revenue from branches b join sales s on 
b.branch_id=s.branch_id group by b.branch_name order by total_revenue desc limit 1;

//Display the highest spending customer.
select c.cutsomer_name,sum(s.total_amount) as total_revenue from customer c join sales s on 
c.customer_id=s.branch_id group by c.cutsomer_name order by total_revenue desc limit 1;
//Display the top three products by revenue.4
select p.product_name,sum(s.total_amount) as total_revenue from products p join sales s on 
p.product_id=s.product_id group by p.product_name order by total_revenue desc limit 3;

//Display the top three customers by spending.
select c.cutsomer_name,sum(s.total_amount) as total_revenue from customer c join sales s on 
c.customer_id=s.branch_id group by c.cutsomer_name order by total_revenue desc limit 3;


//Rank customers based on total spending.
select rank() over(order by sum(s.total_amount) desc) as Rankk ,c.cutsomer_name,sum(s.total_amount) as total_revenue from customer c join sales s on 
c.customer_id=s.branch_id group by c.cutsomer_name order by total_revenue desc;

//Rank branches based on total sales.
select rank() over(order by sum(s.total_amount) desc) as Rank,b.branch_name,sum(s.total_amount) as total_revenue from branches b join sales s on 
b.branch_id=s.branch_id group by b.branch_name order by total_revenue desc;

//Display the top-selling product in each category using ROW_NUMBER().
select row_number() over(partition by p.category order by sum(s.total_amount) desc) as row_numbers,
p.product_id,p.product_name,p.category,sum(s.total_amount) as total_revenue from products p join sales s on 
p.product_id=s.product_id group by p.product_id,p.product_name,p.category order by total_revenue desc;

//Calculate cumulative sales using SUM() OVER().
select sale_date,sum(total_amount) over(order by sale_date desc) as cumulative_sales from sales;

//Calculate the average sale amount using AVG() OVER().
select sale_id,sale_date,avg(total_amount) over(order by sale_date desc) as avg_Sales from sales;


//Generate customer-wise revenue using a Common Table Expression (CTE).
with customer_revenue as
(
select c.customer_id,c.cutsomer_name,sum(s.total_amount) as total_revenue from customer c join sales s
on c.customer_id=s.customer_id group by c.customer_id,c.cutsomer_name
)
select * from customer_revenue order by total_revenue desc;

//Display customers whose spending is greater than the average spending.
with avg_revenue as(
select c.customer_id,c.cutsomer_name,sum(s.total_amount) as amount_spent from customer c join sales s on c.customer_id=
s.customer_id group by c.customer_id,c.cutsomer_name having sum(s.total_amount)>(select avg(total_amount) from sales)
)
select * from avg_revenue;


//Create a View named SALES_REPORT.
//Create a Materialized View named TOP_CUSTOMERS.
//Query both views.
create view sales_report1 as 
select c.customer_id,c.cutsomer_name,sum(s.total_amount) as total_sales from customer c join sales s
on c.customer_id =s.customer_id group by c.customer_id,c.cutsomer_name order by total_sales desc;

select * from sales_report1;

//Create a Materialized View named TOP_CUSTOMERS.
create materialized view top_customer as
select customer_id,sum(total_amount) as total_revenue from sales group by customer_id;

select * from top_customer order by total_revenue limit 1;
-- snowflake/models/gold/fact_sales.sql
CREATE SCHEMA IF NOT EXISTS GOLD_SALES;
USE SCHEMA GOLD_SALES;

-- Create Fact Dynamic Table
-- Implements Gold Layer Dimensional Data Modeling (Kimball)
-- Transaction Fact table linked to dimensions via surrogate keys
CREATE OR REPLACE DYNAMIC TABLE FACT_SALES
    TARGET_LAG = '15 MINUTES'
    WAREHOUSE = 'COMPUTE_WH'
    AS
    SELECT
        MD5(t.transaction_id) AS sales_sk, -- Fact Surrogate Key
        t.transaction_id,
        MD5(t.customer_id) AS customer_sk, -- Foreign Key to DIM_CUSTOMER
        MD5(t.product_id) AS product_sk,   -- Foreign Key to DIM_PRODUCT (not implemented here)
        t.transaction_date,
        t.amount,
        t.status
    FROM SILVER_SALES.SILVER_SALES_TRANSACTIONS t
    WHERE t.status = 'COMPLETED'; -- Only include completed transactions in the fact table

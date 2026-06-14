-- snowflake/models/gold/dim_customer.sql
CREATE SCHEMA IF NOT EXISTS GOLD_SALES;
USE SCHEMA GOLD_SALES;

-- Create Dimension Dynamic Table (SCD Type 1 - Latest State)
-- Implements Gold Layer Dimensional Data Modeling (Kimball)
CREATE OR REPLACE DYNAMIC TABLE DIM_CUSTOMER
    TARGET_LAG = '15 MINUTES'
    WAREHOUSE = 'COMPUTE_WH'
    AS
    SELECT
        MD5(customer_id) AS customer_sk, -- Surrogate Key generated via MD5 hash
        customer_id,
        -- In a real scenario, we would pull customer details (name, email, etc.) from a Silver Customer table.
        -- Here we extract unique customer profiles available in the sales transactions.
        MAX(transaction_date) AS last_purchase_date,
        COUNT(transaction_id) AS lifetime_transactions,
        SUM(amount) AS lifetime_value,
        CURRENT_TIMESTAMP() AS _gold_updated_at
    FROM SILVER_SALES.SILVER_SALES_TRANSACTIONS
    GROUP BY customer_id;

-- snowflake/models/gold/fact_sales.sql
CREATE SCHEMA IF NOT EXISTS GOLD_SALES;
USE SCHEMA GOLD_SALES;

-- Create Fact Dynamic Table
-- Implements Gold Layer Dimensional Data Modeling (Kimball)
-- Transaction Fact table linked to dimensions via surrogate keys
-- Freshness SLA: Updated within 15 minutes of Silver refresh (Rule 11 §1)
CREATE OR REPLACE DYNAMIC TABLE FACT_SALES
    TARGET_LAG = '15 MINUTES'
    WAREHOUSE = 'COMPUTE_WH'
    AS
    SELECT
        MD5(t.transaction_id) AS sales_sk,     -- Fact Surrogate Key
        t.transaction_id,
        MD5(t.customer_id) AS customer_sk,     -- FK → DIM_CUSTOMER
        MD5(t.product_id) AS product_sk,       -- FK → DIM_PRODUCT
        TO_CHAR(t.transaction_date, 'YYYYMMDD')::INT AS date_sk, -- FK → DIM_DATE (Rule 05 §1)
        t.transaction_date,
        t.amount,
        t.status,
        CURRENT_TIMESTAMP() AS _gold_updated_at
    FROM SILVER_SALES.SILVER_SALES_TRANSACTIONS t
    WHERE t.status = 'COMPLETED';

-- RBAC Grants (Rule 08 §1: Gold is strictly BI_READ_ROLE)
GRANT SELECT ON DYNAMIC TABLE FACT_SALES TO ROLE BI_READ_ROLE;

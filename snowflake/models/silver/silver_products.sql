-- snowflake/models/silver/silver_products.sql
CREATE SCHEMA IF NOT EXISTS SILVER_SALES;
USE SCHEMA SILVER_SALES;

-- Create Silver Dynamic Table for Products
-- Implements Silver Layer (Cleansed & Conformed) using Dynamic Tables
-- Parses JSON fields, standardizes types, and deduplicates records
CREATE OR REPLACE DYNAMIC TABLE SILVER_PRODUCTS
    TARGET_LAG = 'DOWNSTREAM' -- Complies with Rule 3.1 (Use DOWNSTREAM for chained tables)
    WAREHOUSE = 'COMPUTE_WH'
    AS
    SELECT
        RAW_DATA:product_id::VARCHAR AS product_id,
        UPPER(TRIM(RAW_DATA:product_name::VARCHAR)) AS product_name,  -- Rule 08 §3: Standardize strings
        UPPER(TRIM(RAW_DATA:category::VARCHAR)) AS category,          -- Rule 08 §3: Standardize strings
        UPPER(TRIM(RAW_DATA:sub_category::VARCHAR)) AS sub_category,  -- Rule 08 §3: Standardize strings
        RAW_DATA:unit_price::NUMBER(10,2) AS unit_price,
        _FILE_NAME,
        _ingested_at AS _bronze_ingested_at,
        CURRENT_TIMESTAMP() AS _silver_processed_at
    FROM RAW_SALES.VW_BRONZE_PRODUCTS -- Complies with Rule 3.3 (Read from View Abstraction)
    WHERE RAW_DATA:product_id::VARCHAR IS NOT NULL -- Rule 12 §2 / Rule 08 §3: Drop records missing PK
    -- Simple deduplication taking the most recently loaded record per product
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY RAW_DATA:product_id::VARCHAR 
        ORDER BY _ingested_at DESC
    ) = 1;

-- RBAC Grants (Rule 08 §1: TRANSFORM_ROLE owns Silver, BI_READ_ROLE read-only)
GRANT USAGE ON SCHEMA SILVER_SALES TO ROLE TRANSFORM_ROLE;
GRANT SELECT, INSERT ON DYNAMIC TABLE SILVER_PRODUCTS TO ROLE TRANSFORM_ROLE;
GRANT SELECT ON DYNAMIC TABLE SILVER_PRODUCTS TO ROLE BI_READ_ROLE;

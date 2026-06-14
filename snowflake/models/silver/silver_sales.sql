-- snowflake/models/silver/silver_sales.sql
CREATE SCHEMA IF NOT EXISTS SILVER_SALES;
USE SCHEMA SILVER_SALES;

-- Create Silver Dynamic Table
-- Implements Silver Layer (Cleansed & Conformed) using Dynamic Tables
-- Parses JSON fields, standardizes types, and deduplicates records
CREATE OR REPLACE DYNAMIC TABLE SILVER_SALES_TRANSACTIONS
    TARGET_LAG = '1 MINUTE' -- Set to near-realtime stream processing (1-minute latency)
    WAREHOUSE = 'COMPUTE_WH'
    AS
    SELECT
        RAW_DATA:transaction_id::VARCHAR AS transaction_id,
        RAW_DATA:customer_id::VARCHAR AS customer_id,
        RAW_DATA:product_id::VARCHAR AS product_id,
        RAW_DATA:transaction_date::TIMESTAMP_NTZ AS transaction_date,
        RAW_DATA:amount::NUMBER(10,2) AS amount,
        UPPER(TRIM(RAW_DATA:status::VARCHAR)) AS status, -- Rule 08 §3: Standardize strings
        _FILE_NAME,
        _ingested_at AS _bronze_ingested_at,
        CURRENT_TIMESTAMP() AS _silver_processed_at
    FROM RAW_SALES.VW_BRONZE_SALES -- Complies with Rule 3.3 (Read from View Abstraction)
    WHERE RAW_DATA:transaction_id::VARCHAR IS NOT NULL -- Rule 12 §2 / Rule 08 §3: Drop records missing PK
    -- Simple deduplication taking the most recently loaded record per transaction
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY RAW_DATA:transaction_id::VARCHAR 
        ORDER BY _ingested_at DESC
    ) = 1;

-- RBAC Grants (Rule 08 §1: TRANSFORM_ROLE owns Silver, BI_READ_ROLE read-only)
GRANT USAGE ON SCHEMA SILVER_SALES TO ROLE TRANSFORM_ROLE;
GRANT SELECT, INSERT ON DYNAMIC TABLE SILVER_SALES_TRANSACTIONS TO ROLE TRANSFORM_ROLE;
GRANT SELECT ON DYNAMIC TABLE SILVER_SALES_TRANSACTIONS TO ROLE BI_READ_ROLE;

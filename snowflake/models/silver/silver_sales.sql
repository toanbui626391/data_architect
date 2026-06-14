-- snowflake/models/silver/silver_sales.sql
CREATE SCHEMA IF NOT EXISTS SILVER_SALES;
USE SCHEMA SILVER_SALES;

-- Create Silver Dynamic Table
-- Implements Silver Layer (Cleansed & Conformed) using Dynamic Tables
-- Parses JSON fields, standardizes types, and deduplicates records
CREATE OR REPLACE DYNAMIC TABLE SILVER_SALES_TRANSACTIONS
    TARGET_LAG = '5 MINUTES'
    WAREHOUSE = 'COMPUTE_WH'
    AS
    SELECT
        RAW_DATA:transaction_id::VARCHAR AS transaction_id,
        RAW_DATA:customer_id::VARCHAR AS customer_id,
        RAW_DATA:product_id::VARCHAR AS product_id,
        RAW_DATA:transaction_date::TIMESTAMP_NTZ AS transaction_date,
        RAW_DATA:amount::NUMBER(10,2) AS amount,
        RAW_DATA:status::VARCHAR AS status,
        _FILE_NAME,
        _LOAD_TIMESTAMP
    FROM RAW_SALES.BRONZE_SALES
    -- Simple deduplication taking the most recently loaded record per transaction
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY RAW_DATA:transaction_id::VARCHAR 
        ORDER BY _LOAD_TIMESTAMP DESC
    ) = 1;

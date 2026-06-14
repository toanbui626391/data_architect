-- snowflake/models/bronze/bronze_sales.sql
-- Create Schema if not exists
CREATE SCHEMA IF NOT EXISTS RAW_SALES;
USE SCHEMA RAW_SALES;

-- 1. Create Bronze Table (Variant pattern for JSON data)
-- Follows Schema-on-Read Pattern (Flexible Path)
CREATE OR REPLACE TABLE BRONZE_SALES (
    RAW_DATA VARIANT,
    _FILE_NAME VARCHAR,
    _LOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 2. Create External Stage (Example using AWS S3)
CREATE OR REPLACE STAGE EXT_SALES_STAGE
    URL='s3://my-enterprise-data-lake/sales/raw/'
    STORAGE_INTEGRATION = s3_integration
    FILE_FORMAT = (TYPE = JSON);

-- 3. Create Snowpipe with ON_ERROR = CONTINUE for DLQ handling
-- Implements Pattern 1: Continuous File Loading
CREATE OR REPLACE PIPE SNOWPIPE_SALES
    AUTO_INGEST = TRUE
    AS
    COPY INTO BRONZE_SALES (RAW_DATA, _FILE_NAME)
    FROM (
        SELECT $1, metadata$filename
        FROM @EXT_SALES_STAGE
    )
    ON_ERROR = CONTINUE;

-- 4. Create DLQ Quarantine Table and Task
-- Implements DLQ Quarantine Pattern (Section 5.3)
CREATE OR REPLACE TABLE BRONZE_SALES_DLQ (
    FILE_NAME VARCHAR,
    ERROR_MESSAGE VARCHAR,
    RAW_LINE VARCHAR,
    _LOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Task to sweep errors into the DLQ
CREATE OR REPLACE TASK QUARANTINE_SALES_TASK
    WAREHOUSE = 'COMPUTE_WH'
    SCHEDULE = '60 MINUTE'
    AS
    INSERT INTO BRONZE_SALES_DLQ (FILE_NAME, ERROR_MESSAGE, RAW_LINE)
    SELECT 
        FILE_NAME, 
        FIRST_ERROR_MESSAGE, 
        REJECTED_RECORD
    FROM TABLE(VALIDATE(BRONZE_SALES, JOB_ID => '_last'));
    -- In practice, a more sophisticated DLQ collection using COPY_HISTORY is used.

ALTER TASK QUARANTINE_SALES_TASK RESUME;

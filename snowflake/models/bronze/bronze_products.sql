-- snowflake/models/bronze/bronze_products.sql
-- Create Schema if not exists
CREATE SCHEMA IF NOT EXISTS RAW_SALES;
USE SCHEMA RAW_SALES;

-- 1. Create Bronze Table (Variant pattern for JSON data)
-- Follows Schema-on-Read Pattern (Flexible Path)
CREATE OR REPLACE TABLE BRONZE_PRODUCTS (
    RAW_DATA VARIANT,
    _FILE_NAME VARCHAR,
    _ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _ingested_date DATE DEFAULT CURRENT_DATE()
) ENABLE_SCHEMA_EVOLUTION = TRUE; -- Rule 15 §1 / Ingestion Arch §5.1: Absorb new source columns automatically

-- 2. Create External Stage (Example using AWS S3)
CREATE OR REPLACE STAGE EXT_PRODUCTS_STAGE
    URL='s3://my-enterprise-data-lake/products/raw/'
    STORAGE_INTEGRATION = s3_integration
    FILE_FORMAT = (TYPE = JSON);

-- 3. Create Snowpipe with ON_ERROR = CONTINUE for DLQ handling
-- Implements Pattern 1: Continuous File Loading
CREATE OR REPLACE PIPE SNOWPIPE_PRODUCTS
    AUTO_INGEST = TRUE
    AS
    COPY INTO BRONZE_PRODUCTS (RAW_DATA, _FILE_NAME)
    FROM (
        SELECT $1, metadata$filename
        FROM @EXT_PRODUCTS_STAGE
    )
    ON_ERROR = CONTINUE;

-- 4. Create DLQ Quarantine Table and Task
-- Implements DLQ Quarantine Pattern (Section 5.3)
CREATE OR REPLACE TABLE BRONZE_PRODUCTS_DLQ (
    FILE_NAME VARCHAR,
    ERROR_MESSAGE VARCHAR,
    RAW_LINE VARCHAR,
    _ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Task to sweep errors into the DLQ (Serverless — no warehouse needed)
CREATE OR REPLACE TASK QUARANTINE_PRODUCTS_TASK
    USER_TASK_MANAGED_COMPUTE_RESOURCES = TRUE -- Rule 03 (Serverless-First): avoid idle VW costs
    SCHEDULE = '60 MINUTE'
    AS
    INSERT INTO BRONZE_PRODUCTS_DLQ (FILE_NAME, ERROR_MESSAGE, RAW_LINE)
    SELECT 
        FILE_NAME, 
        FIRST_ERROR_MESSAGE, 
        REJECTED_RECORD
    FROM TABLE(VALIDATE(BRONZE_PRODUCTS, JOB_ID => '_last'));

ALTER TASK QUARANTINE_PRODUCTS_TASK RESUME;

-- 5. Create View Abstraction Layer for Dynamic Tables (Rule 3.3)
-- Prevents schema changes on the source table from breaking downstream Dynamic Tables
CREATE OR REPLACE VIEW VW_BRONZE_PRODUCTS AS
SELECT * FROM BRONZE_PRODUCTS;

-- 6. RBAC Grants (Rule 08 §1 / Rule 09: Least-privilege access)
GRANT USAGE ON SCHEMA RAW_SALES TO ROLE RAW_ROLE;
GRANT SELECT, INSERT ON TABLE BRONZE_PRODUCTS TO ROLE RAW_ROLE;
GRANT SELECT ON TABLE BRONZE_PRODUCTS_DLQ TO ROLE RAW_ROLE;
GRANT SELECT ON VIEW VW_BRONZE_PRODUCTS TO ROLE TRANSFORM_ROLE; -- Silver pipeline reads the view

-- 7. DLQ Alert: P2 — notify when any rejected rows land in the DLQ (Rule 18 §1.6 / Rule 11 §4)
CREATE OR REPLACE ALERT ALERT_BRONZE_PRODUCTS_DLQ_ERRORS
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '60 MINUTE'
    IF (EXISTS (
        SELECT 1 FROM BRONZE_PRODUCTS_DLQ
        WHERE _ingested_at >= DATEADD('minute', -60, CURRENT_TIMESTAMP())
    ))
    THEN CALL SYSTEM$SEND_EMAIL(
        'data_eng_notifications',
        'P2: BRONZE_PRODUCTS DLQ has rejected rows',
        'Rows were written to BRONZE_PRODUCTS_DLQ in the last 60 minutes. Investigate COPY_HISTORY for errors.'
    );

ALTER ALERT ALERT_BRONZE_PRODUCTS_DLQ_ERRORS RESUME;

-- snowflake/models/bronze/bronze_products.sql
-- Create Schema if not exists
CREATE SCHEMA IF NOT EXISTS RAW_SALES;
USE SCHEMA RAW_SALES;

-- 1. Create Bronze Table aligning with Snowflake Kafka Connector (Snowpipe Streaming)
-- The connector writes JSON payloads into RECORD_CONTENT and metadata into RECORD_METADATA.
CREATE OR REPLACE TABLE BRONZE_PRODUCTS (
    RECORD_CONTENT VARIANT,
    RECORD_METADATA VARIANT
);

-- 2. View Abstraction Layer for Dynamic Tables (Rule 18 §3.3)
-- Transforms Kafka metadata and content into conformed schemas for downstream layers.
-- This protects downstream models from ingestion changes.
CREATE OR REPLACE VIEW VW_BRONZE_PRODUCTS AS
SELECT
    RECORD_CONTENT AS RAW_DATA,                                  -- Downstream conformed payload
    RECORD_METADATA:offset::VARCHAR AS _file_name,               -- Offset maps to file/source identifier
    TO_TIMESTAMP_NTZ(RECORD_METADATA:CreateTime::LONG) AS _ingested_at, -- Kafka record timestamp
    TO_DATE(TO_TIMESTAMP_NTZ(RECORD_METADATA:CreateTime::LONG)) AS _ingested_date
FROM BRONZE_PRODUCTS;

-- 3. RBAC Grants (Rule 08 §1 / Rule 09: Least-privilege access)
GRANT USAGE ON SCHEMA RAW_SALES TO ROLE RAW_ROLE;
GRANT INSERT ON TABLE BRONZE_PRODUCTS TO ROLE RAW_ROLE;            -- Kafka streaming user needs INSERT privilege
GRANT SELECT ON VIEW VW_BRONZE_PRODUCTS TO ROLE TRANSFORM_ROLE;     -- Silver pipeline reads the view

/*
================================================================================
KAFKA CONNECTOR CONFIGURATION REFERENCE (Rule 18 §3.2)
================================================================================
To ingest data from Kafka into this table using Snowpipe Streaming, deploy the
Snowflake Kafka Connector with the following settings:

connector.class = com.snowflake.kafka.connector.SnowflakeSinkConnector
snowflake.ingestion.method = SNOWPIPE_STREAMING
snowflake.database.name = SALES_DB
snowflake.schema.name = RAW_SALES
snowflake.topic2table.map = sales_products_topic:BRONZE_PRODUCTS

-- DLQ / Error Handling (handled connector-side):
errors.tolerance = all
errors.deadletterqueue.topic.name = sales_products_dlq
errors.deadletterqueue.context.headers.enable = true
================================================================================
*/

-- snowflake/models/gold/observability.sql
-- Pipeline Observability Layer (Rule 11, Rule 12, Transformation Arch §7.2-7.3)
-- Implements automated monitoring for Dynamic Table failures and DQ alerts.
CREATE SCHEMA IF NOT EXISTS GOLD_SALES;
USE SCHEMA GOLD_SALES;

-- 1. Notification Integration (connect Snowflake Alerts to email/SNS)
-- NOTE: Requires Snowflake ACCOUNTADMIN to execute once per account.
-- CREATE OR REPLACE NOTIFICATION INTEGRATION data_eng_notifications
--     TYPE = EMAIL
--     ENABLED = TRUE
--     ALLOWED_RECIPIENTS = ('data-engineering@company.com');

-- 2. P1 Alert: Dynamic Table refresh FAILED (Transformation Arch §7.3 / Rule 11 §4)
-- Fires when any Dynamic Table in the pipeline has failed in the last 10 minutes.
CREATE OR REPLACE ALERT ALERT_DYNAMIC_TABLE_FAILURES
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '10 MINUTE'
    IF (EXISTS (
        SELECT 1
        FROM SNOWFLAKE.ACCOUNT_USAGE.DYNAMIC_TABLE_REFRESH_HISTORY
        WHERE STATE = 'FAILED'
          AND DATABASE_NAME = CURRENT_DATABASE()
          AND REFRESH_START_TIME >= DATEADD('minute', -10, CURRENT_TIMESTAMP())
    ))
    THEN CALL SYSTEM$SEND_EMAIL(
        'data_eng_notifications',
        'P1: Dynamic Table Refresh FAILED',
        'One or more Dynamic Tables have failed refresh. Query DYNAMIC_TABLE_REFRESH_HISTORY for details.'
    );

ALTER ALERT ALERT_DYNAMIC_TABLE_FAILURES RESUME;

-- 3. P2 Alert: Gold table SLA breach — data stale beyond 3x TARGET_LAG (Rule 11 §1)
-- Fires if the FACT_SALES refresh timestamp is older than 36 hours (3x 12-hour scheduled lag).
CREATE OR REPLACE ALERT ALERT_GOLD_SLA_BREACH
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '60 MINUTE'
    IF (EXISTS (
        SELECT 1
        FROM SNOWFLAKE.ACCOUNT_USAGE.DYNAMIC_TABLE_REFRESH_HISTORY
        WHERE NAME = 'FACT_SALES'
          AND DATABASE_NAME = CURRENT_DATABASE()
          AND DATA_TIMESTAMP < DATEADD('hour', -36, CURRENT_TIMESTAMP())
        ORDER BY REFRESH_END_TIME DESC
        LIMIT 1
    ))
    THEN CALL SYSTEM$SEND_EMAIL(
        'data_eng_notifications',
        'P2: FACT_SALES SLA Breach — table stale > 36 hours',
        'FACT_SALES has not refreshed within its 3x TARGET_LAG SLA window of 36 hours. Investigate upstream Silver streaming and scheduler status.'
    );

ALTER ALERT ALERT_GOLD_SLA_BREACH RESUME;

-- 4. P2 Alert: Non-incremental Dynamic Table fallback (Rule 18 §3.5)
-- Detects when any DT silently falls back to FULL refresh (unbounded cost risk).
CREATE OR REPLACE ALERT ALERT_DYNAMIC_TABLE_FULL_REFRESH
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '60 MINUTE'
    IF (EXISTS (
        SELECT 1
        FROM SNOWFLAKE.ACCOUNT_USAGE.DYNAMIC_TABLE_REFRESH_HISTORY
        WHERE REFRESH_MODE = 'FULL'
          AND DATABASE_NAME = CURRENT_DATABASE()
          AND REFRESH_START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
    ))
    THEN CALL SYSTEM$SEND_EMAIL(
        'data_eng_notifications',
        'P2: Dynamic Table running in FULL refresh mode',
        'One or more Dynamic Tables are not using INCREMENTAL refresh. Review REFRESH_MODE_REASON and simplify the SQL query.'
    );

ALTER ALERT ALERT_DYNAMIC_TABLE_FULL_REFRESH RESUME;

-- 5. P1 Alert: Snowpipe Streaming Client Inactivity (Real-Time Ingestion Monitoring)
-- Alerts when the count of active Snowpipe Streaming clients drops to 0, indicating Kafka Connector disconnect.
CREATE OR REPLACE ALERT ALERT_STREAMING_CLIENT_HEALTH
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '10 MINUTE'
    IF (EXISTS (
        SELECT 1
        FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWPIPE_STREAMING_CLIENT_HISTORY
        WHERE NUM_ACTIVE_CLIENTS = 0
          AND EVENT_TIMESTAMP >= DATEADD('minute', -10, CURRENT_TIMESTAMP())
    ))
    THEN CALL SYSTEM$SEND_EMAIL(
        'data_eng_notifications',
        'P1: Snowpipe Streaming Clients Inactive',
        'Count of active Snowpipe Streaming clients dropped to 0 in the last 10 minutes. Check Kafka Connect Connector status immediately.'
    );

ALTER ALERT ALERT_STREAMING_CLIENT_HEALTH RESUME;

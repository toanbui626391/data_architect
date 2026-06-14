-- snowflake/models/gold/dim_date.sql
-- Date Dimension — required for all time-intelligence BI queries (Rule 05 §1)
-- Generates a calendar spine from 2020-01-01 to 2030-12-31
CREATE SCHEMA IF NOT EXISTS GOLD_SALES;
USE SCHEMA GOLD_SALES;

-- Freshness SLA: Static reference table, rebuilt annually or on demand (Rule 11 §1)
CREATE OR REPLACE TABLE DIM_DATE AS
WITH date_spine AS (
    SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2020-01-01'::DATE) AS calendar_date
    FROM TABLE(GENERATOR(ROWCOUNT => 3653)) -- 10 years of dates
)
SELECT
    TO_CHAR(calendar_date, 'YYYYMMDD')::INT AS date_sk,      -- PK / FK used in FACT_SALES
    calendar_date,
    YEAR(calendar_date)                     AS year,
    QUARTER(calendar_date)                  AS quarter,
    MONTH(calendar_date)                    AS month,
    TO_CHAR(calendar_date, 'MMMM')          AS month_name,
    WEEK(calendar_date)                     AS week_of_year,
    DAY(calendar_date)                      AS day_of_month,
    DAYOFWEEK(calendar_date)                AS day_of_week,
    DAYNAME(calendar_date)                  AS day_name,
    CASE WHEN DAYOFWEEK(calendar_date) IN (0, 6) THEN TRUE ELSE FALSE END AS is_weekend,
    CURRENT_TIMESTAMP()                     AS _gold_updated_at
FROM date_spine;

-- RBAC Grants (Rule 08 §1)
GRANT SELECT ON TABLE DIM_DATE TO ROLE BI_READ_ROLE;

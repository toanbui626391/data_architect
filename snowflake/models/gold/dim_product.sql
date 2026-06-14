-- snowflake/models/gold/dim_product.sql
-- Product Dimension — resolves the dangling product_sk FK in FACT_SALES (Rule 05 §1)
-- NOTE: In production this should join to a Silver product source table.
--       This stub provides the schema contract for downstream BI consumers.
CREATE SCHEMA IF NOT EXISTS GOLD_SALES;
USE SCHEMA GOLD_SALES;

-- Freshness SLA: Updated within 15 minutes of Silver product table refresh (Rule 11 §1)
CREATE OR REPLACE DYNAMIC TABLE DIM_PRODUCT
    TARGET_LAG = '15 MINUTES'
    WAREHOUSE = 'COMPUTE_WH'
    AS
    SELECT
        MD5(product_id) AS product_sk,              -- Surrogate Key (Transformation Arch §6.1)
        product_id,
        UPPER(TRIM(product_name)) AS product_name,  -- Rule 08 §3: Standardize strings
        UPPER(TRIM(category)) AS category,
        UPPER(TRIM(sub_category)) AS sub_category,
        unit_price,
        CURRENT_TIMESTAMP() AS _gold_updated_at
    FROM SILVER_SALES.SILVER_PRODUCTS;              -- Assumes a Silver product table exists

-- RBAC Grants (Rule 08 §1: Gold is strictly BI_READ_ROLE)
GRANT SELECT ON DYNAMIC TABLE DIM_PRODUCT TO ROLE BI_READ_ROLE;

# Snowflake SQL Models - Deployment Guide

This directory contains the Snowflake SQL models structured using the Medallion Architecture (Bronze -> Silver -> Gold).

Due to the dependency graph of views, tables, and Dynamic Tables, models MUST be deployed in the following specific execution order.

---

## 1. Dependency Tree

```
          [EXT_SALES_STAGE]            [EXT_PRODUCTS_STAGE]
                 │                              │
                 ▼ (Snowpipe)                   ▼ (Snowpipe)
           BRONZE_SALES                  BRONZE_PRODUCTS
                 │                              │
                 ▼                              ▼
          VW_BRONZE_SALES                VW_BRONZE_PRODUCTS
                 │                              │
                 ▼                              ▼
     SILVER_SALES_TRANSACTIONS           SILVER_PRODUCTS
         │               │                      │
         ├───┐           └────────┐             │
         │   │                    │             │
         ▼   ▼                    ▼             ▼
  DIM_CUSTOMER (Gold)       FACT_SALES (Gold) ◄─┘ (DIM_PRODUCT)
                             ▲
                             │
  DIM_DATE (Gold) ───────────┘
```

---

## 2. Recommended Deployment Order

To avoid schema/object resolution errors in Snowflake, execute the scripts in the following order:

### Phase 1: Bronze Layer (Ingestion & Stages)
1. **[bronze_sales.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/bronze/bronze_sales.sql)**
   - Creates `RAW_SALES` schema.
   - Configures `BRONZE_SALES`, stage `EXT_SALES_STAGE`, and `SNOWPIPE_SALES`.
   - Creates quarantine table `BRONZE_SALES_DLQ`, task `QUARANTINE_SALES_TASK`, and view `VW_BRONZE_SALES`.
   - Grants RBAC permissions to `RAW_ROLE` and `TRANSFORM_ROLE`.
2. **[bronze_products.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/bronze/bronze_products.sql)**
   - Configures `BRONZE_PRODUCTS`, stage `EXT_PRODUCTS_STAGE`, and `SNOWPIPE_PRODUCTS`.
   - Creates quarantine table `BRONZE_PRODUCTS_DLQ`, task `QUARANTINE_PRODUCTS_TASK`, and view `VW_BRONZE_PRODUCTS`.
   - Grants RBAC permissions to `RAW_ROLE` and `TRANSFORM_ROLE`.

### Phase 2: Silver Layer (Standardization & Cleansing)
3. **[silver_sales.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/silver/silver_sales.sql)**
   - Creates `SILVER_SALES` schema and `SILVER_SALES_TRANSACTIONS` dynamic table.
   - Grants permissions to `TRANSFORM_ROLE` and `BI_READ_ROLE`.
4. **[silver_products.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/silver/silver_products.sql)**
   - Creates `SILVER_PRODUCTS` dynamic table.
   - Grants permissions to `TRANSFORM_ROLE` and `BI_READ_ROLE`.

### Phase 3: Gold Layer (Dimensions & Facts)
5. **[dim_customer.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/gold/dim_customer.sql)**
   - Creates `GOLD_SALES` schema and `DIM_CUSTOMER` dynamic table.
   - Grants permissions to `BI_READ_ROLE`.
6. **[dim_product.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/gold/dim_product.sql)**
   - Creates `DIM_PRODUCT` dynamic table using `SILVER_SALES.SILVER_PRODUCTS`.
   - Grants permissions to `BI_READ_ROLE`.
7. **[dim_date.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/gold/dim_date.sql)**
   - Generates static calendar dimension table `DIM_DATE`.
   - Grants permissions to `BI_READ_ROLE`.
8. **[fact_sales.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/gold/fact_sales.sql)**
   - Creates `FACT_SALES` fact table linking customer, product, and date keys.
   - Grants permissions to `BI_READ_ROLE`.

### Phase 4: Observability (Alerting & Monitoring)
9. **[observability.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/gold/observability.sql)**
   - Registers native Snowflake ALERT objects monitoring the dynamic tables and SLA targets.
   - Note: Creating the `NOTIFICATION INTEGRATION` requires account-level `ACCOUNTADMIN` execution.

---

## 3. Operations & Refreshing

All Silver and Gold dynamic tables (except the static `DIM_DATE` table and Bronze ingest) refresh automatically based on their configuration:
- `SILVER_SALES_TRANSACTIONS` and `SILVER_PRODUCTS` are set to `TARGET_LAG = 'DOWNSTREAM'`.
- `DIM_CUSTOMER`, `DIM_PRODUCT`, and `FACT_SALES` are set to `TARGET_LAG = '15 MINUTES'`.
- Querying any Gold table automatically triggers a refresh of the upstream dependencies in the graph if the data is older than the SLA.

# Snowflake SQL Models - Real-Time Ingestion & Scheduled Presentation Guide

This directory contains the Snowflake SQL models structured using the Medallion Architecture (Bronze -> Silver -> Gold), configured for real-time Kafka ingestion and scheduled BI presentation.

---

## 1. Pipeline Architecture & SLA Flow

```
   [Upstream Producers]
            │
            ▼ (Kafka Topics)
     [Kafka Connect] ◄─── (Schema Registry Validation)
            │
            ▼ (Snowpipe Streaming Connector - Sub-second Ingestion)
BRONZE_SALES / BRONZE_PRODUCTS (Tables: RECORD_CONTENT, RECORD_METADATA)
            │
            ▼ (SQL View Abstraction - Extracts RAW_DATA and Kafka Timestamps)
VW_BRONZE_SALES / VW_BRONZE_PRODUCTS
            │
            ▼ (Dynamic Tables: TARGET_LAG = '1 MINUTE' - Near Real-Time)
SILVER_SALES_TRANSACTIONS / SILVER_PRODUCTS
            │
            ▼ (Dynamic Tables: TARGET_LAG = '12 HOURS' - Scheduled Refresh)
GOLD_SALES (DIM_CUSTOMER, DIM_PRODUCT, FACT_SALES) ◄── [DIM_DATE] (Static)
```

| Layer | Ingestion Style | SLA/Lag Target | Purpose |
|---|---|---|---|
| **Bronze Layer** | Real-Time (Kafka Connector) | Sub-second | Immutable landing of raw JSON payload and Kafka transport metadata. |
| **Silver Layer** | Near Real-Time (Dynamic Tables) | `1 MINUTE` | Cleaned, standardized (`UPPER(TRIM())`), casted, and deduplicated records. |
| **Gold Layer** | Scheduled (Dynamic Tables) | `12 HOURS` | Kimball Star Schema dimensional models (Fact & Dimensions) optimized for BI queries. |

---

## 2. Recommended Deployment Order

To avoid schema/object resolution errors in Snowflake, execute the scripts in the following order:

### Phase 1: Bronze Ingestion Layer (Kafka Schema Mapping)
1. **[bronze_sales.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/bronze/bronze_sales.sql)**
   - Creates `RAW_SALES` schema and `BRONZE_SALES` table with default Kafka connector schema.
   - Deploys view abstraction `VW_BRONZE_SALES` parsing JSON elements.
   - Grants RBAC permissions to `RAW_ROLE` (for insertion) and `TRANSFORM_ROLE`.
2. **[bronze_products.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/bronze/bronze_products.sql)**
   - Configures `BRONZE_PRODUCTS` table and view abstraction `VW_BRONZE_PRODUCTS`.
   - Grants RBAC permissions to `RAW_ROLE` and `TRANSFORM_ROLE`.

### Phase 2: Silver Cleansing Layer (Near Real-Time)
3. **[silver_sales.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/silver/silver_sales.sql)**
   - Creates `SILVER_SALES` schema and `SILVER_SALES_TRANSACTIONS` dynamic table with `TARGET_LAG = '1 MINUTE'`.
   - Grants permissions to `TRANSFORM_ROLE` and `BI_READ_ROLE`.
4. **[silver_products.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/silver/silver_products.sql)**
   - Creates `SILVER_PRODUCTS` dynamic table with `TARGET_LAG = '1 MINUTE'`.
   - Grants permissions to `TRANSFORM_ROLE` and `BI_READ_ROLE`.

### Phase 3: Gold Presentation Layer (Scheduled Dimensions & Facts)
5. **[dim_customer.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/gold/dim_customer.sql)**
   - Creates `GOLD_SALES` schema and `DIM_CUSTOMER` dynamic table with `TARGET_LAG = '12 HOURS'`.
   - Grants permissions to `BI_READ_ROLE`.
6. **[dim_product.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/gold/dim_product.sql)**
   - Creates `DIM_PRODUCT` dynamic table with `TARGET_LAG = '12 HOURS'`.
   - Grants permissions to `BI_READ_ROLE`.
7. **[dim_date.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/gold/dim_date.sql)**
   - Generates static calendar dimension table `DIM_DATE`.
   - Grants permissions to `BI_READ_ROLE`.
8. **[fact_sales.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/gold/fact_sales.sql)**
   - Creates `FACT_SALES` fact table with `TARGET_LAG = '12 HOURS'` linking dimensional surrogate keys.
   - Grants permissions to `BI_READ_ROLE`.

### Phase 4: Observability (Alerting & Monitoring)
9. **[observability.sql](file:///Users/toanbui/dev/data_architect/snowflake/models/gold/observability.sql)**
   - Registers native Snowflake ALERT objects monitoring the dynamic tables, Scheduled SLA breaches (36-hour window), and active Kafka connect streaming clients.
   - Note: Creating the `NOTIFICATION INTEGRATION` requires account-level `ACCOUNTADMIN` execution.

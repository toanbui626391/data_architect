# Medallion Architecture Data Modeling Rules

All data warehouse and lakehouse pipelines MUST follow the Medallion Architecture (Bronze → Silver → Gold). These rules apply across all platforms (Databricks, Snowflake, GCP).

---

## 1. Architect & Cross-Layer Requirements

*   **Idempotency:** Every pipeline must be fully idempotent. Re-running it must never cause data loss or duplication. Use streaming checkpoints (DLT) or deterministic `MERGE` keys (Snowflake) to guarantee this.
*   **Separation of Concerns:** Never mix ingestion, cleansing, or aggregation logic in a single model. Each layer has a single, defined responsibility.
*   **Naming Convention:** All tables MUST use the fully qualified Unity Catalog path: `catalog.{layer}.{entity}` (e.g., `catalog.bronze.sales_orders`). Never use implicit schema references.
*   **Storage Optimization:** Use **Liquid Clustering** (`CLUSTER BY`) on all
    Delta tables. **Never use `PARTITIONED BY`** unless legacy compatibility
    demands it. Enable Row Tracking (`"delta.enableRowTracking" = "true"`)
    on Silver and Gold tables to optimize incremental Materialized Views.
*   **Audit Columns:** Every table in every layer MUST contain pipeline lineage columns:
    *   Bronze: `_ingested_at TIMESTAMP`, `_ingested_date DATE`
    *   Silver: `_bronze_ingested_at TIMESTAMP`, `_silver_processed_at TIMESTAMP`
    *   Gold: `_gold_updated_at TIMESTAMP`
*   **Security (RBAC):**
    *   `Bronze`: Data Engineering service principals only (`RAW_ROLE`).
    *   `Silver`: Data Engineering pipeline authors only (`TRANSFORM_ROLE`).
    *   `Gold`: Read-only for Analysts, BI tools, and ML Feature Stores (`BI_READ_ROLE`).

---

## 2. Bronze Layer (Raw / Landing)

**Purpose:** Immutable, append-only archive of all raw data. **Capture everything, zero data loss.**

*   **DLT Type:** `CREATE OR REFRESH STREAMING TABLE`. Bronze is always a streaming sink.
*   **CDF:** Disable Change Data Feed (`"delta.enableChangeDataFeed" = "false"`). Bronze is append-only; Silver uses `APPLY CHANGES INTO` for CDC.
*   **Payload:** Always retain the raw payload (e.g., `CAST(value AS STRING) AS record_content`). Extracting known columns alongside is acceptable, but the raw string must be preserved for schema drift recovery.
*   **Data Quality:** Apply **only structural constraints** on ingestion metadata (e.g., `kafka_offset IS NOT NULL`). Use `ON VIOLATION WARN` exclusively. **Never drop records or apply business logic in Bronze.**

---

## 3. Silver Layer (Cleansed / Conformed)

**Purpose:** Single source of truth for typed, deduplicated, and standardized enterprise entities.

*   **DLT Type:** Use a `STREAMING LIVE VIEW` for cleansing/DQ, then `APPLY CHANGES INTO` a `STREAMING TABLE` target for deduplication. This two-step pattern separates concerns cleanly.
*   **CDF & Row Tracking:** Enable Change Data Feed
    (`"delta.enableChangeDataFeed" = "true"`) and Row Tracking
    (`"delta.enableRowTracking" = "true"`) to support high-performance
    incremental materialized views and downstream replication.
*   **Processing:**
    *   Parse raw payloads into strictly typed columns using `from_json` or `CAST`.
    *   Standardize formats: strings to `UPPER(TRIM(...))`, amounts to `DECIMAL(18,2)`, currencies to ISO codes.
    *   Deduplicate using `APPLY CHANGES INTO` with `KEYS (primary_key)` and `SEQUENCE BY updated_at`.
*   **Data Quality:**
    *   `ON VIOLATION DROP`: For records missing a primary key (cannot be joined downstream).
    *   `ON VIOLATION WARN`: For optional but important fields (e.g., `customer_id` for guest checkouts).

---

## 4. Gold Layer (Curated / Consumption)

**Purpose:** Business-level aggregations and dimensional models for BI, reporting, and Machine Learning.

*   **DLT Type:** `CREATE OR REFRESH MATERIALIZED VIEW`. DLT automatically computes these incrementally using the upstream Silver CDF, without full table scans.
*   **Structure:** MUST use **Kimball Star Schema** (Fact + Dimension tables) or aggregated Materialized Views. Snowflake schemas (dimension-to-dimension joins) are **strictly forbidden**.
*   **Source Filter:** Always filter out semantically invalid states at the source (e.g., `WHERE order_status IN ('COMPLETED', 'SHIPPED')`).
*   **Data Quality:** Apply **semantic business constraints** using `ON VIOLATION WARN` (e.g., `total_revenue >= 0`). Failures here indicate upstream business logic bugs, not ingestion errors.

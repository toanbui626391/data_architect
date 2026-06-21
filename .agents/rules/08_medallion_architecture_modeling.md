# Medallion Architecture Data Modeling Rules

All Databricks Lakehouse pipelines MUST follow the Medallion Architecture (Bronze → Silver → Gold). For platform-specific DLT and clustering details, see Rule 07.

---

## 1. Cross-Layer Requirements

*   **Idempotency:** Every pipeline must be fully idempotent. Re-running must never cause data loss or duplication. Use DLT streaming checkpoints or deterministic `MERGE` keys.
*   **Separation of Concerns:** Never mix ingestion, cleansing, or aggregation logic in a single model. Each layer has one responsibility.
*   **Naming Convention:** All tables MUST use the fully qualified Unity Catalog path: `catalog.{layer}.{entity}` (e.g., `catalog.bronze.sales_orders`). Never use implicit schema references.
*   **Storage Optimization:** Use Liquid Clustering (`CLUSTER BY`) on all Delta tables (per Rule 07). Enable Row Tracking (`"delta.enableRowTracking" = "true"`) on Silver and Gold tables to optimize incremental Materialized Views.
*   **Audit Columns:** Every table MUST include lineage columns:
    *   Bronze: `_ingested_at TIMESTAMP`, `_ingested_date DATE`, `_source_system STRING`
    *   Silver: `_bronze_ingested_at TIMESTAMP`, `_silver_processed_at TIMESTAMP`
    *   Gold: `_gold_updated_at TIMESTAMP`
*   **Data Contracts:** The Bronze→Silver boundary MUST be governed by a data contract specifying expected schema, data types, freshness SLA, and quality thresholds. Contract violations quarantine records and alert upstream owners.
*   **Schema Evolution:** Bronze tables MUST enable schema auto-merge. Silver allows additive evolution; breaking changes require contract versioning. Gold schema changes MUST be versioned and coordinated with downstream consumers.
*   **Security (RBAC):**
    *   `Bronze`: Data Engineering service principals only (`RAW_ROLE`).
    *   `Silver`: Data Engineering pipeline authors only (`TRANSFORM_ROLE`).
    *   `Gold`: Read-only for Analysts, BI tools, ML Feature Stores, and AI agents (`BI_READ_ROLE`).

---

## 2. Bronze Layer (Raw / Landing)

**Purpose:** Immutable, append-only archive of all raw data. Zero data loss.

*   **DLT Type:** `CREATE OR REFRESH STREAMING TABLE`. Bronze is always a streaming sink.
*   **CDF:** Disable Change Data Feed (`"delta.enableChangeDataFeed" = "false"`). Bronze is append-only; Silver uses `APPLY CHANGES INTO` for CDC.
*   **Payload:** Always retain the raw payload (e.g., `CAST(value AS STRING) AS record_content`). Extracting known columns alongside is acceptable, but the raw string must be preserved for schema drift recovery.
*   **Data Quality:** Apply **only structural constraints** on ingestion metadata (e.g., `kafka_offset IS NOT NULL`). Use `ON VIOLATION WARN` exclusively. **Never drop records or apply business logic in Bronze.**

---

## 3. Silver Layer (Cleansed / Conformed)

**Purpose:** Single source of truth for typed, deduplicated, and standardized enterprise entities.

*   **DLT Type:** Use a `STREAMING LIVE VIEW` for cleansing/DQ, then `APPLY CHANGES INTO` a `STREAMING TABLE` target for deduplication. This two-step pattern separates concerns cleanly.
*   **CDF & Row Tracking:** Enable Change Data Feed (`"delta.enableChangeDataFeed" = "true"`) and Row Tracking (`"delta.enableRowTracking" = "true"`) to support incremental materialized views and downstream replication.
*   **Processing:**
    *   Parse raw payloads into strictly typed columns using `from_json` or `CAST`.
    *   Standardize formats: strings to `UPPER(TRIM(...))`, amounts to `DECIMAL(18,2)`, currencies to ISO codes.
    *   Deduplicate using `APPLY CHANGES INTO` with `KEYS (primary_key)` and `SEQUENCE BY updated_at`.
*   **Data Quality:**
    *   `ON VIOLATION DROP`: For records missing a primary key. Dropped records MUST be routed to a quarantine table (`catalog.silver._quarantine_{entity}`) with the original payload and failure reason. Never silently discard data.
    *   `ON VIOLATION WARN`: For optional but important fields (e.g., `customer_id` for guest checkouts).

---

## 4. Gold Layer (Curated / Consumption)

**Purpose:** Business-level aggregations and dimensional models for BI, reporting, ML Feature Stores, and AI inference.

*   **DLT Type:** `CREATE OR REFRESH STREAMING TABLE` reading from `STREAM(catalog.silver.entity)`. Enable CDF (`"delta.enableChangeDataFeed" = "true"`) and Row Tracking (`"delta.enableRowTracking" = "true"`) on all Gold tables.
*   **Structure:** MUST use Kimball Star Schema as default (per Rule 05). Snowflake-style normalization requires explicit justification and review. One Big Table (OBT) is permitted for simple aggregation endpoints.
*   **Source Filter:** Always filter out semantically invalid states (e.g., `WHERE order_status IN ('COMPLETED', 'SHIPPED')`).
*   **AI/ML Readiness:** Gold tables serving ML Feature Stores or AI inference MUST support point-in-time lookups via `_gold_updated_at` for training data reproducibility.
*   **Data Quality:** Apply **semantic business constraints** using `ON VIOLATION WARN` (e.g., `total_revenue >= 0`). Failures indicate upstream logic bugs, not ingestion errors.

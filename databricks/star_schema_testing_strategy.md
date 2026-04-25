# Data Warehouse Model Testing Strategy (Star Schema)

As a Solution Architect, ensuring the integrity and accuracy of a Star Schema data model is critical for maintaining trust in Business Intelligence (BI) and analytics. Testing a data warehouse goes beyond simple code unit tests; it requires rigorous data quality, structural, and business logic testing.

This document outlines the testing strategy for a Star Schema data warehouse, specifically tailored for implementation within the Databricks Lakehouse.

---

## Executive Summary: Top Data Quality Issues & Prevention Strategies

The following table summarizes the most critical data quality issues frequently encountered in a Star Schema, how to proactively test for them, and how to natively prevent them in Databricks.

| Top Data Quality Issue | Where It Occurs | How to Test | Databricks Prevention Strategy |
| :--- | :--- | :--- | :--- |
| **Row Fan-out (Data Duplication)** | Fact & Dimension Joins | Compare row counts before and after `LEFT JOIN` / Denormalization. | Use Unity Catalog Primary Key constraints. Fail pipelines if duplicate source keys are ingested. |
| **Referential Integrity Loss** | Fact to Dimension mapping | Count Fact rows where Foreign Key maps to `NULL` or missing Dimension keys. | Map unmatched keys to an "Unknown" member (`-1`) via `COALESCE`. Use DLT `EXPECT OR FAIL` on `fk IS NOT NULL`. |
| **Missing History (SCD2 Gaps)** | Slowly Changing Dimensions | Check for overlapping `valid_from` / `valid_to` dates or missing active records. | Use strict window functions in Silver pipelines. Add `EXPECT OR FAIL` for `valid_from < valid_to`. |
| **Silent Data Truncation** | Data Ingestion (Bronze/Silver) | Reconcile Source vs. Target aggregate row counts and sum totals. | Implement Databricks SQL Alerts on `COUNT(*)` thresholds to notify teams immediately when data volumes drop unexpectedly. |
| **Invalid Measures** | Fact Tables | Query for out-of-bound numerics (e.g., negative prices, percentages > 100). | Use DLT `EXPECT OR DROP` to automatically quarantine bad records into an error table before reaching Gold. |

---

## 1. Dimension Table Testing

Dimension tables provide the context (the "who, what, where, and when") for facts. Errors in dimensions lead to incorrect grouping, filtering, and slicing in BI dashboards.

### 1.1 Surrogate Key Uniqueness & Not-Null
> [!IMPORTANT]
> **High Frequency & High Impact:** This is the most foundational test for any dimension table. If surrogate keys are not unique, every downstream join will fail or fan-out.

* **What to Test**: Ensure the primary key (Surrogate Key) of every dimension table contains strictly unique, non-null values.
* **Why / Possible Causes of Issues**: 
  * Upstream source systems sending duplicate records.
  * Flawed ETL merge logic (e.g., matching on the wrong natural key).
  * Race conditions in concurrent data pipelines leading to duplicate inserts.
* **Impact if Untested**: Duplicate surrogate keys cause fan-out joins with the fact table, silently inflating all BI metrics (e.g., revenue reported doubles).

### 1.2 Natural Key Integrity
* **What to Test**: Validate that the natural (business) key column(s) in a dimension table correctly map back to the source system without orphans or mismatches.
* **Why / Possible Causes of Issues**:
  * Schema drift in the source system (e.g., a column renamed or data type changed).
  * Truncation of alphanumeric codes during ingestion (e.g., a leading zero stripped from a product code).
* **Impact if Untested**: Business users cannot reconcile Databricks reports against the operational source system, eroding trust.

### 1.3 Slowly Changing Dimension (SCD Type 2) Integrity
* **What to Test**: For SCD Type 2 dimensions, ensure that for any given natural key:
  * There are no overlapping effective dates (`valid_from` and `valid_to`).
  * Exactly one record is marked as current (`is_current = TRUE`).
  * The `valid_to` of the previous version equals the `valid_from` of the next version (no gaps).
* **Why / Possible Causes of Issues**:
  * Out-of-order data arrival (late-arriving updates).
  * Bugs in the window functions used to calculate validity dates.
  * Timezone mismatches when recording transaction timestamps.
* **Impact if Untested**: Historical "as-of" reporting becomes unreliable. A customer's region assignment might be duplicated or missing for a specific period, causing incorrect regional revenue attribution.

### 1.4 Unknown Member (Default Row) Presence
* **What to Test**: Ensure that every dimension table contains a default "Unknown" or "Not Applicable" row (typically with a surrogate key of `-1` or `0`).
* **Why / Possible Causes of Issues**:
  * Missing initialization steps during pipeline deployment.
  * Accidental deletion during manual data backfills.
* **Impact if Untested**: Fact records with missing dimensional context will be silently dropped during `INNER JOIN`s in BI tools, leading to underreported metrics.

### 1.5 Attribute Completeness
* **What to Test**: Validate that critical descriptive attributes in dimensions are not excessively null (e.g., `customer_email`, `product_category`). Define a threshold (e.g., < 5% null is acceptable).
* **Why / Possible Causes of Issues**:
  * Optional fields in the source system that are rarely populated.
  * A new source onboarded without mapping all required attributes.
* **Impact if Untested**: BI dashboards show large "Unknown" or "N/A" segments that make reports unusable for business decisions.

### 1.6 Referential Integrity Between Dimensions (Outrigger / Snowflake)
* **What to Test**: If a dimension references another dimension (e.g., `dim_product` has a `brand_key` pointing to `dim_brand`), validate that every foreign key in the child dimension maps to a valid key in the parent dimension.
* **Why / Possible Causes of Issues**:
  * Parent dimension loaded after the child dimension in the pipeline.
  * Mismatch in surrogate key generation logic between pipelines.
* **Impact if Untested**: Queries joining across related dimensions return incomplete or duplicated results.

### 1.7 Denormalization Row Count Integrity (Fan-Out Prevention)
> [!CAUTION]
> **High Impact:** When flattening multiple related source tables (e.g., merging an Outrigger into a primary Dimension), improper joins can accidentally multiply dimension records, creating more data than actually exists.

* **What to Test**: Validate that the row count of the final denormalized dimension table exactly equals the row count of the primary base table (or the grain-defining source table). For example, `COUNT(1)` from `final_customer_dim` must equal `COUNT(1)` from `stg_customer_base`.
* **Why / Possible Causes of Issues**:
  * Performing a `LEFT JOIN` against a related lookup table that unexpectedly has a one-to-many relationship (e.g., joining Customer to Addresses, where a customer has multiple addresses).
  * Unresolved duplicate records present in the secondary tables being joined.
* **Impact if Untested**: A single entity (e.g., one customer) is duplicated into multiple rows in the dimension table. When the fact table later joins to this dimension, the facts will be multiplied (fan-out), massively inflating downstream BI metrics.

---

## 2. Fact Table Testing

Fact tables store the measurable, quantitative data. Errors here directly impact financial reporting, operational KPIs, and executive decision-making.

### 2.1 Referential Integrity (Foreign Key Constraints)
> [!IMPORTANT]
> **High Frequency:** This is the most common failure point in data warehousing, usually caused by timing issues (e.g., facts arriving before dimensions).

* **What to Test**: Ensure every foreign key in a fact table correctly maps to a valid surrogate key in the corresponding dimension table. If a match is not found, it should map to the "Unknown" member (`-1`), but never be `NULL`.
* **Why / Possible Causes of Issues**:
  * **Late-Arriving Dimensions**: A transaction arrives before the customer or product master data has been ingested.
  * Upstream deletions of master data that violate referential integrity.
* **Impact if Untested**: Orphaned fact records are invisible in all dimension-filtered reports (e.g., a sale with no product dimension won't appear in any product-level report).

### 2.2 Unknown Member Threshold (Late-Arriving Tolerance)
> [!WARNING]
> **Data Quality Degradation:** While mapping to `-1` ("Unknown") safely handles referential integrity and late-arriving dimensions, having *too many* Unknowns renders the dimension useless for business analysis.

* **What to Test**: Monitor the percentage of rows in the Fact table where a specific Foreign Key maps to the "Unknown" member (`-1`). Set a strict threshold (e.g., `< 2%` or `< 5%`) and fail the pipeline or trigger a severe alert if the threshold is exceeded. 
* **Why / Possible Causes of Issues**:
  * An upstream dimension pipeline failed completely, meaning *all* new fact records are mapping to Unknown.
  * A massive batch of new products or customers was onboarded into the operational system but the dimension load logic wasn't updated to capture them.
* **Impact if Untested**: Technically the pipeline succeeds (no referential integrity crash), but BI dashboards become unusable because 50% of the sales are attributed to the "Unknown" category. Business users lose trust in the granularity of the reporting.

### 2.3 Grain Uniqueness
> [!CAUTION]
> **Critical Impact:** This is the single most dangerous error in a data warehouse. A grain violation means facts are being duplicated via fan-out joins, silently inflating all financial and operational metrics.

* **What to Test**: Verify that the combination of keys representing the stated grain of the fact table (e.g., `date_key + store_key + product_key + transaction_id`) is strictly unique.
* **Why / Possible Causes of Issues**:
  * **Fan-out Joins**: Accidental one-to-many joins in the ETL pipeline that multiply fact records.
  * Processing the same source file or Kafka offset multiple times without proper idempotency.
  * Incorrect deduplication logic in the Silver layer.
* **Impact if Untested**: All aggregate metrics (SUM, COUNT, AVG) will be inflated, producing silently incorrect reports. This is one of the most dangerous and difficult-to-detect errors in a data warehouse.

### 2.3 Measure Constraints and Range Validation
* **What to Test**: Validate that numeric measures fall within expected boundaries (e.g., `sales_amount >= 0`, `discount_pct BETWEEN 0 AND 100`, `quantity > 0`).
* **Why / Possible Causes of Issues**:
  * Upstream system bugs (e.g., negative prices entered manually by operators).
  * Currency conversion errors (e.g., multiplying instead of dividing).
  * Unit-of-measure mismatches (e.g., kilograms loaded as grams).
* **Impact if Untested**: Aggregate metrics become meaningless. A single negative $1M transaction can wipe out an entire region's reported revenue.

### 2.4 Additive, Semi-Additive, and Non-Additive Measure Classification
* **What to Test**: Verify that measures are aggregated correctly according to their type:
  * **Additive** (e.g., `sales_amount`): Can be summed across all dimensions.
  * **Semi-Additive** (e.g., `account_balance`): Can be summed across some dimensions but not time (use snapshot or latest value).
  * **Non-Additive** (e.g., `unit_price`, `ratio`): Should never be summed directly.
* **Why / Possible Causes of Issues**:
  * BI tool or dashboard misconfigured to `SUM()` a semi-additive measure like `inventory_level` across dates, producing a nonsensical total.
  * Gold-layer views pre-aggregating non-additive measures incorrectly.
* **Impact if Untested**: Business users unknowingly report wildly incorrect numbers (e.g., summing daily account balances to get a "total balance" that is 30x the actual value).

### 2.5 Fact Table Completeness (No Missing Periods)
* **What to Test**: Verify that the fact table contains records for every expected time period (e.g., every day, every hour) without unexplained gaps.
* **Why / Possible Causes of Issues**:
  * A scheduled pipeline run failed silently and was never retried.
  * A source system had an outage during a specific window and no data was produced.
  * Timezone conversion errors causing an entire day's data to shift to the previous or next day.
* **Impact if Untested**: Trend analysis, month-over-month comparisons, and forecasting models produce misleading results because certain periods appear to have zero activity.

### 2.6 Duplicate Event Detection
> [!WARNING]
> **High Frequency:** Very common in streaming or incremental batch pipelines (like Auto Loader or Kafka) if idempotency is not handled perfectly.

* **What to Test**: Check for exact duplicate rows in the fact table (all columns identical), which indicates the same source event was loaded multiple times.
* **Why / Possible Causes of Issues**:
  * Kafka consumer reprocessing the same offset after a restart.
  * Auto Loader reprocessing a file that was moved and re-landed in the source bucket.
  * Missing `MERGE` or deduplication logic in the ETL pipeline.
* **Impact if Untested**: All aggregate metrics are inflated. Unlike grain violations (which may be intentional), exact duplicates are always errors.

### 2.7 Fact Enrichment Row Count Integrity (Fan-Out Prevention)
> [!CAUTION]
> **Critical Impact:** When enriching a fact table by `LEFT JOIN`ing to multiple dimension tables, a flawed join condition will multiply the fact rows, silently destroying the accuracy of all financial metrics.

* **What to Test**: Validate that the row count of the fact table *after* the enrichment joins exactly equals the row count of the base fact table *before* the joins. For example, if you start with 1,000 sales transactions and left join to 5 dimension tables, the output must be exactly 1,000 rows.
* **Why / Possible Causes of Issues**:
  * Joining a fact table to a dimension table that contains duplicate natural keys or surrogate keys.
  * Using a `LEFT JOIN` on a dimension that has an unintended one-to-many relationship with the fact (e.g., joining a sales fact to a promotion dimension where multiple promotions apply to one sale, instead of using a bridge table).
* **Impact if Untested**: A single base transaction is duplicated into multiple rows in the final Gold fact table. A $100 sale enriched with two conflicting dimension records becomes two $100 sales, instantly doubling reported revenue.

---

## 3. Cross-Model & Integration Testing

These tests validate the relationships and consistency across the entire Star Schema model rather than individual tables.

### 3.1 Source-to-Target Reconciliation
> [!IMPORTANT]
> **High Visibility:** This is the test that business users care about the most. If the data warehouse totals don't match the source system's frontend totals, trust is immediately lost.

* **What to Test**: Compare high-level aggregates (e.g., total sales amount, total row count) in the Gold fact tables against the Bronze (raw) layer or the operational source system.
* **Why / Possible Causes of Issues**:
  * Dropped records due to overly restrictive `WHERE` clauses or `INNER JOIN`s in the Silver/Gold transformations.
  * Failures in incremental processing logic capturing only partial updates.
  * Incorrect handling of soft deletes from the source system.
* **Impact if Untested**: The data warehouse silently underreports or overreports activity compared to the source of truth, which will eventually be discovered by business users who lose trust in the platform.

### 3.2 Conformed Dimension Consistency
* **What to Test**: If the same dimension (e.g., `dim_date`, `dim_customer`) is shared across multiple fact tables (conformed dimension), verify that all fact tables reference the exact same dimension table and version.
* **Why / Possible Causes of Issues**:
  * Different teams building separate pipelines that generate their own version of a "customer" dimension with different surrogate key sequences.
  * A dimension table was rebuilt or reloaded in one pipeline but not reflected in others.
* **Impact if Untested**: Drill-across queries (joining two fact tables on a shared dimension) produce incorrect or empty results because the surrogate keys don't align.

### 3.3 Cross-Fact Consistency (Shared Metrics)
* **What to Test**: If two fact tables should agree on a shared metric (e.g., `fact_orders.total_revenue` should equal `fact_invoices.total_billed` for completed orders), validate the reconciliation.
* **Why / Possible Causes of Issues**:
  * Different fact tables sourced from different operational systems with different update cadences.
  * Business rules applied inconsistently (e.g., one pipeline includes tax, another excludes it).
* **Impact if Untested**: Different dashboards built on different fact tables show contradicting numbers for the same KPI, causing confusion and distrust among executives.

### 3.4 Schema Drift Detection
* **What to Test**: Compare the current schema (column names, data types, nullability) of each table against a registered baseline. Detect any unexpected additions, removals, or type changes.
* **Why / Possible Causes of Issues**:
  * Upstream source systems deploying schema changes without notifying the data team.
  * Auto Loader's schema evolution adding unexpected columns to Bronze tables, which then propagate downstream.
* **Impact if Untested**: Downstream pipelines or BI reports break silently or produce incorrect results when a column type changes (e.g., a string column suddenly containing integers).

---

## 4. Performance & Query Pattern Testing

Even if data is correct, a poorly performing Star Schema will be abandoned by business users.

### 4.1 Query Performance Baseline
* **What to Test**: Benchmark a set of representative analytical queries (e.g., "total sales by region by month") and track execution time over time. Alert if query time degrades beyond an acceptable threshold (e.g., > 2x baseline).
* **Why / Possible Causes of Issues**:
  * Data volume growth without corresponding partitioning or Z-Ordering updates.
  * Stale Delta table statistics causing suboptimal query plans.
  * Missing `OPTIMIZE` and `VACUUM` maintenance jobs.
* **Impact if Untested**: Dashboard load times degrade from seconds to minutes over time, and users revert to manual spreadsheets.

### 4.2 Partition and Clustering Effectiveness
* **What to Test**: Verify that the most frequently filtered columns (e.g., `date_key`, `region`) are properly used for Delta Lake partitioning or Z-Ordering, and that file sizes are within the optimal range (32MB-256MB per file).
* **Why / Possible Causes of Issues**:
  * Over-partitioning on high-cardinality columns creating millions of tiny files (the "small file problem").
  * Under-partitioning forcing full table scans on every query.
* **Impact if Untested**: Serverless SQL Warehouse costs increase dramatically due to unnecessary data scanning.

---

## 5. Implementation in Databricks

As a Databricks-native architecture, these tests should be embedded directly into the data pipelines using native tools:

### 5.1 Delta Live Tables (DLT) Expectations
For preventative, inline testing within the ETL pipeline itself:
* **`EXPECT`**: Tracks failure rates in the DLT event log without stopping the pipeline. Use for non-critical anomaly tracking (e.g., attribute completeness thresholds).
* **`EXPECT OR DROP`**: Drops invalid records into a quarantine state, ensuring the Star Schema remains clean. Use for measure range violations (e.g., negative sales).
* **`EXPECT OR FAIL`**: Stops the pipeline immediately. Use for critical structural errors (e.g., surrogate key uniqueness, referential integrity violations, grain violations).

### 5.2 Databricks SQL Alerts (Post-Load Validation)
For post-execution business logic and reconciliation testing:
* Create scheduled SQL queries in Databricks SQL that run against the Gold tables after each pipeline completes.
* Configure **Databricks SQL Alerts** to trigger notifications (Slack, PagerDuty, Email) when a query detects a discrepancy:
  * Orphaned foreign keys: `SELECT COUNT(*) FROM fact WHERE fk NOT IN (SELECT sk FROM dim)`
  * Missing time periods: `SELECT date_key FROM dim_date WHERE date_key NOT IN (SELECT DISTINCT date_key FROM fact) AND ...`
  * Source-to-target row count mismatch exceeding a tolerance threshold.

### 5.3 Unity Catalog System Tables (Drift & Performance)
For schema drift detection and performance regression monitoring:
* Query **`system.information_schema.columns`** to compare current table schemas against a registered baseline stored in a control table.
* Query **`system.query.history`** to monitor average query duration per dashboard/report and alert on performance regressions.

### 5.4 Test Organization Summary

| Test Category | When to Run | Databricks Tool | Failure Action |
| :--- | :--- | :--- | :--- |
| Surrogate Key Uniqueness | During ETL | DLT `EXPECT OR FAIL` | Stop pipeline |
| SCD Type 2 Integrity | During ETL | DLT `EXPECT OR FAIL` | Stop pipeline |
| Referential Integrity (FK) | During ETL | DLT `EXPECT OR FAIL` | Stop pipeline |
| Grain Uniqueness | During ETL | DLT `EXPECT OR FAIL` | Stop pipeline |
| Measure Range Validation | During ETL | DLT `EXPECT OR DROP` | Quarantine record |
| Attribute Completeness | During ETL | DLT `EXPECT` | Log & monitor |
| Source-to-Target Reconciliation | Post-Load | SQL Alert | Notify team |
| Conformed Dimension Consistency | Post-Load | SQL Alert | Notify team |
| Cross-Fact Consistency | Post-Load | SQL Alert | Notify team |
| Missing Time Periods | Post-Load | SQL Alert | Notify team |
| Schema Drift Detection | Post-Load | System Tables + SQL Alert | Notify team |
| Query Performance Regression | Continuous | System Tables + SQL Alert | Notify team |

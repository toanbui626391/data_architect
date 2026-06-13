# Agent Guidelines: Full-Refresh & Table Rebuilds (Fabric, Databricks, Snowflake)

When updating ELT transformation business logic (e.g. changing formulas, correcting historical data, or refactoring schemas), the AI agent **MUST** follow these guidelines to rebuild downstream tables safely without data loss, downtime, or orphan metadata.

---

## 1. General Principles (Cross-Platform)
*   **Ingestion Preservation:** **NEVER** run full-refreshes or deletes on the raw ingestion layer (Bronze/Raw landing storage). Bronze is the immutable source of truth used to rebuild all downstream layers.
*   **Checkpoint Resets:** When rebuilding a streaming table, the agent **MUST** delete or reset the consumer's checkpoint directory (`checkpointLocation`). Failing to reset checkpoints will cause Spark to resume from the old state, causing schema mismatches or missing historical data.
*   **Atomic Table Swaps (Zero Downtime):** For large tables, **ALWAYS** rebuild data in a shadow table (e.g., `silver_sales_orders_rebuild`), validate the results, and execute an atomic swap (`SWAP WITH` or `RENAME`) to prevent BI dashboard outages.

---

## 2. Microsoft Fabric (OneLake / Spark)
*   **Rule:** The agent **MUST** preserve table metadata IDs and Power BI DirectLake bindings during rebuilds.
*   **Directives:**
    *   **Overwrite, Do Not Drop:** **ALWAYS** use `df.write.format("delta").mode("overwrite").saveAsTable("table")`. **NEVER** use `DROP TABLE` followed by `CREATE TABLE`, as dropping tables destroys the underlying GUID inside OneLake, breaking Power BI semantic model connections.
    *   **V-Order Maintenance:** Ensure V-Order optimization configurations are active during the overwrite run so the newly generated data files are immediately optimized for Power BI memory structures.

---

## 3. Databricks (Delta Lake / DLT)
*   **Rule:** The agent **MUST** leverage Delta Lake's cloning and time travel features to protect operations.
*   **Directives:**
    *   **Rollback Safety Clone:** Before overwriting a table, **ALWAYS** create a temporary shallow clone to serve as an instant backup:
        ```sql
        CREATE OR REPLACE TABLE catalog.silver.sales_orders_backup CLONE catalog.silver.sales_orders;
        ```
    *   **DLT Rebuilds:** For Delta Live Tables pipelines, **NEVER** run manual delete queries. **MUST** trigger a "Full Refresh" on the selected tables via the DLT UI or Databricks CLI to let DLT handle checkpoint resets and atomic table replacements.
    *   **Instant Rollbacks:** If validation fails after a full refresh, immediately roll back using Delta Time Travel:
        ```sql
        RESTORE TABLE catalog.silver.sales_orders TO VERSION AS OF <backup_version_or_timestamp>;
        ```
    *   **Post-Refresh Cleanup:** After a successful refresh and validation, run `VACUUM` to prune historical parquet files and save storage costs.

---

## 4. Snowflake (Data Cloud)
*   **Rule:** The agent **MUST** use metadata cloning to perform zero-downtime swaps and minimize compute credits.
*   **Directives:**
    *   **Zero-Downtime Clone & Swap:** Rebuild tables using metadata swaps:
        1.  Create a clone of the production table: `CREATE TABLE sales_temp CLONE sales;`
        2.  Truncate and rebuild `sales_temp` using the new ELT business logic.
        3.  Swap the tables atomically: `ALTER TABLE sales SWAP WITH sales_temp;`
        4.  Drop `sales_temp` (which now holds the old production data).
    *   **Dynamic Table Full Refreshes:** To rebuild a Dynamic Table, **NEVER** truncate it manually. Alter the definition if needed, and run a manual full refresh:
        ```sql
        ALTER DYNAMIC TABLE catalog.gold.sales_summary REFRESH; -- If refresh_mode is full
        -- Or force refresh via:
        ALTER DYNAMIC TABLE catalog.gold.sales_summary SET TARGET_LAG = 'DOWNSTREAM';
        ```

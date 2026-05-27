# Silver Layer: Incremental Deduplication Model (SQL)

This document provides a concrete **Delta Live Tables (DLT)** SQL implementation for the Silver layer. It specifically addresses the requirement to perform an **incremental load** while guaranteeing **no duplicates** (upsert pattern).

---

## 1. DLT SQL Implementation (`APPLY CHANGES INTO`)

To incrementally load data while eliminating duplicates (handling updates/upserts), standard streaming tables are insufficient. DLT provides a native CDC/Upsert engine called `APPLY CHANGES INTO` that implements Slowly Changing Dimensions (SCD Type 1 or Type 2) completely incrementally.

Create a new SQL file in your Databricks workspace (e.g., `silver_transform.sql`) with the following code.

```sql
-- 1. Declare the Target Streaming Table
-- We do not use 'AS SELECT' here because 'APPLY CHANGES INTO' will populate it.
CREATE OR REFRESH STREAMING TABLE silver_sales_orders
COMMENT "Cleansed and deduplicated sales orders. Represents the exact current state of each order."
TBLPROPERTIES (
  "quality" = "silver"
);

-- 2. Define Data Quality Expectations (Optional but Recommended)
-- If a record has no order_id, drop it from the stream before processing
ALTER TABLE LIVE.silver_sales_orders SET TBLPROPERTIES (
  "pipelines.data_quality.expect_or_drop.valid_order_id" = "order_id IS NOT NULL"
);

-- 3. Execute the Incremental Deduplication / Upsert
APPLY CHANGES INTO LIVE.silver_sales_orders
FROM STREAM(LIVE.bronze_sales_orders)
  -- Deduplicate based on the Primary Key
  KEYS (order_id)
  
  -- When multiple records arrive for the same order_id, pick the latest one
  SEQUENCE BY _ingested_at
  
  -- Optional: Ignore deletes if you only want to track active updates
  -- IGNORE DELETED MACRO (operation = 'DELETE')
  
  -- SCD Type 1: Overwrite existing data with the latest data
  -- SCD Type 2: Keep historical versions (use STORED AS SCD TYPE 2)
  STORED AS SCD TYPE 1;
```

---

## 2. Key Design Decisions Explained

This implementation pattern is the industry standard for transforming messy, potentially duplicated Bronze event streams into a pristine Silver layer.

### 2.1 The `APPLY CHANGES INTO` Engine
Standard streaming queries (`SELECT * FROM STREAM()`) are append-only. If the Bronze layer ingests three updates for the same `order_id`, a standard stream will output three rows.
*   **The Solution:** The `APPLY CHANGES INTO` command acts as an intelligent router. It reads the append-only Bronze stream, looks at the defined `KEYS`, and incrementally merges (upserts) the data into the Silver target table behind the scenes. 
*   **Performance:** Databricks handles the state management and transaction logs automatically, ensuring only new or changed records are processed.

### 2.2 Handling Duplicates (`SEQUENCE BY`)
If the upstream source sends duplicate records at the exact same time, or if an order is updated (e.g., status changes from `Pending` to `Shipped`), the `SEQUENCE BY` clause guarantees accuracy.
*   By pointing it to a timestamp column (e.g., `_ingested_at` or a source `updated_at` column), DLT knows mathematically which record is the "newest". It discards older duplicates and overwrites the Silver row with the newest data.

### 2.3 SCD Type 1 vs SCD Type 2
*   **`STORED AS SCD TYPE 1`**: This is the default approach for most operational tables. It means the table always reflects the *current state*. Old data is overwritten.
*   **`STORED AS SCD TYPE 2`**: If your business requires tracking historical changes (e.g., seeing exactly when an order changed from Pending to Shipped), changing this to Type 2 tells Databricks to automatically generate `__START_AT` and `__END_AT` columns to track the history of the row over time without you writing complex SQL.

### 2.4 Separation of Declaration and Execution
Notice that the process is split into two steps:
1.  **`CREATE STREAMING TABLE`**: Declares the existence of the table and attaches constraints (Data Quality Expectations).
2.  **`APPLY CHANGES INTO`**: Defines the transformation logic and feeds the table. You cannot combine these into a single `CREATE TABLE AS SELECT` when doing incremental upserts.

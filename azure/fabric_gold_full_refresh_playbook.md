# Playbook: Full Refresh Strategy for `fabric_gold_sales.py`

This playbook outlines the operational steps to execute a **Zero-Downtime Full Refresh** on the Gold Daily Sales aggregation table (`gold_daily_sales`) in Microsoft Fabric. 

This procedure complies with [.agents/rules/17_elt_full_refresh_best_practices.md](file:///Users/toanbui/dev/data_architect/.agents/rules/17_elt_full_refresh_best_practices.md) by leveraging a shadow rebuild table, an atomic Delta overwrite, and a checkpoint swap, ensuring downstream Power BI reports experience zero query outages while preserving OneLake metadata IDs and DirectLake bindings.

---

## Pre-Reconciliation Checklist

> [!CAUTION]
> - **Power BI DirectLake Connections**: **NEVER** run `DROP TABLE` on the production `gold_daily_sales` table. Dropping the table destroys its OneLake GUID and permanently breaks Power BI semantic models.
> - **Zero-Downtime Requirement**: Do **NOT** use `TRUNCATE TABLE` on the production table. Doing so creates an immediate query outage for business users until the rebuild completes. Follow the shadow swap steps below.

---

## Step-by-Step Execution Playbook

### Step 1: Provision the Shadow Rebuild Table
Create an empty shadow table with the exact same schema and tags as the production table.

Run the following SQL in a Fabric Notebook:
```sql
-- Create shadow table using zero-copy metadata cloning
CREATE TABLE IF NOT EXISTS gold_daily_sales_rebuild
CLONE gold_daily_sales;

-- Empty the shadow table to prepare for full rebuild
TRUNCATE TABLE gold_daily_sales_rebuild;
```

---

### Step 2: Purge the Rebuild Stream Checkpoint
Structured Streaming tracks processed offsets using checkpoints. To reprocess the Silver history from version `0`, you must clear the shadow checkpoint directory.

Run this Python code inside a Fabric Notebook:
```python
from notebookutils import mssparkutils

rebuild_checkpoint = "Files/checkpoints/gold_daily_sales_rebuild"

# Purge old shadow checkpoints if they exist
if mssparkutils.fs.exists(rebuild_checkpoint):
    print(f"Purging shadow checkpoint: {rebuild_checkpoint}")
    mssparkutils.fs.rm(rebuild_checkpoint, True)
```

---

### Step 3: Run the Rebuild Job
Run a modified version of the Spark Job Definition (SJD) `sjd_gold_sales_aggregation` (or configure parameters inside the notebook) that:
1.  Sets target table to `gold_daily_sales_rebuild`.
2.  Sets checkpoint path to `Files/checkpoints/gold_daily_sales_rebuild`.

Because the checkpoint is empty, Spark will read the complete Silver CDF history, calculate the daily aggregates, and insert them into the shadow table. The production table `gold_daily_sales` remains online and fully queryable by users.

---

### Step 4: Post-Rebuild Data Validation
Verify the accuracy of the rebuilt dataset in the shadow table before swapping:

```sql
-- QA Query: Verify rows, revenue, and order counts against the current production table
SELECT 
  'Shadow Rebuild (New)' AS source, COUNT(*) AS rows, SUM(total_revenue) AS revenue, SUM(total_orders) AS orders
FROM gold_daily_sales_rebuild
UNION ALL
SELECT 
  'Active Production (Old)' AS source, COUNT(*) AS rows, SUM(total_revenue) AS revenue, SUM(total_orders) AS orders
FROM gold_daily_sales;
```

---

### Step 5: Delta Overwrite & Checkpoint Swap (Zero Downtime)
Once data is validated, execute the atomic swap using a Delta Overwrite to overwrite the production table with the shadow table's data. This preserves Power BI GUID linkages, and then swap the checkpoints:

#### A. Atomic Table Data Overwrite (Python)
Run this PySpark code to overwrite the production table with the staging data. Ensure V-Order optimization configurations are active during the overwrite:
```python
# 1. Enable V-Order and Auto-Optimize configs for Power BI DirectLake compatibility
spark.conf.set("spark.sql.parquet.vorder.enabled", "true")
spark.conf.set("spark.microsoft.delta.optimizeWrite.enabled", "true")

# 2. Perform atomic Delta overwrite (preserves OneLake table GUID and Power BI bindings)
spark.read.table("gold_daily_sales_rebuild") \
    .write.format("delta") \
    .mode("overwrite") \
    .saveAsTable("gold_daily_sales")

# 3. Clean up the shadow rebuild table
spark.sql("DROP TABLE IF EXISTS gold_daily_sales_rebuild")
```

#### B. Checkpoint Directory Swap (Python)
Immediately swap the checkpoint directories in OneLake so future incremental runs resume from the correct offsets:
```python
from notebookutils import mssparkutils

# Replace production checkpoint with rebuild checkpoint
# Clean up production checkpoint directory first, then move the shadow checkpoint to production
if mssparkutils.fs.exists("Files/checkpoints/gold_daily_sales_backup"):
    mssparkutils.fs.rm("Files/checkpoints/gold_daily_sales_backup", True)

# Backup active checkpoint (if exists), then swap
if mssparkutils.fs.exists("Files/checkpoints/gold_daily_sales"):
    mssparkutils.fs.mv("Files/checkpoints/gold_daily_sales", "Files/checkpoints/gold_daily_sales_backup")

mssparkutils.fs.mv("Files/checkpoints/gold_daily_sales_rebuild", "Files/checkpoints/gold_daily_sales")
```

Downstream Power BI dashboards automatically pick up the new records with zero query downtime.

---

## Rollback Procedure (Emergency Only)

If issues occur after the swap, execute these commands to restore the old table and state:

1.  Restore table data from backup:
    Since Delta Lake supports time travel, you can restore the production table directly to the version prior to the overwrite (version - 1) instead of using raw table swaps:
    ```sql
    -- Find the version number before overwrite (e.g. current_version - 1)
    RESTORE TABLE gold_daily_sales TO VERSION AS OF <backup_version_or_timestamp>;
    ```
2.  Swap checkpoints back:
    ```python
    from notebookutils import mssparkutils
    
    # Restore the backup checkpoint
    if mssparkutils.fs.exists("Files/checkpoints/gold_daily_sales_backup"):
        mssparkutils.fs.rm("Files/checkpoints/gold_daily_sales", True)
        mssparkutils.fs.mv("Files/checkpoints/gold_daily_sales_backup", "Files/checkpoints/gold_daily_sales")
    ```

# Rule: Slowly Changing Dimensions (SCD) Standards

## Scope
This rule defines standards for designing, building, and operating Slowly Changing Dimensions (SCD) in the **Gold layer** (Medallion Architecture).

---

## 1. Core SCD Type Standards

### SCD Type 0 (Static / Retain)
*   **Definition:** Attributes that must NEVER change once captured (e.g., `signup_date`, `original_credit_score`).
*   **Implementation:** Set column value on insert; ignore all upstream updates during subsequent merge/upsert operations.

### SCD Type 1 (Overwrite)
*   **Definition:** Overwrites historical values with current values (no history tracked). Default choice for correction of typos or when history holds no analytical value.
*   **Implementation:** Perform direct replacement/overwrite. Downstream BI queries will retroactively reflect the new value across all historical transactions.

### SCD Type 2 (Historical Versioning) — Primary Standard
*   **Definition:** Tracks the complete history of attribute
    changes by writing a new row for each state change.
*   **Conformed Columns:** Every SCD Type 2 table MUST include:
    *   `valid_from TIMESTAMP/DATE`: Inclusive start of validity.
    *   `valid_to TIMESTAMP/DATE`: Exclusive end. Use
        `'9999-12-31'` for active rows. Never NULL.
    *   `is_current BOOLEAN`: Active version flag.
    *   `_version INT`: Monotonically increasing version number
        per natural key (1, 2, 3, ...) for debugging.
*   **Tracked vs. Untracked Columns:** Explicitly classify every
    dimension attribute as either:
    *   **Tracked (Type 2):** Changes trigger a new version row
        (e.g., `customer_region`, `account_status`).
    *   **Untracked (Type 1):** Changes overwrite in-place on the
        current row without creating history (e.g., `email`,
        `phone`). Document the classification in the table DDL
        or data contract.
*   **Hash-Based Change Detection:** Compute a deterministic hash
    (e.g., `SHA2(CONCAT_WS('|', tracked_col_1, ...))`) of all
    tracked columns. Compare the incoming hash against the current
    row's hash. Create a new version ONLY when the hash differs.
    This prevents phantom versions from no-op upstream replays.
*   **Delete Handling (Soft Close):** When a source system deletes
    a record, do NOT physically delete the dimension row. Close
    the current version by setting `valid_to` to the deletion
    timestamp and `is_current = false`. Optionally add an
    `_is_deleted BOOLEAN` flag for downstream filtering.
*   **Initial Load:** On first load, all records receive
    `valid_from = source_timestamp`, `valid_to = '9999-12-31'`,
    `is_current = true`, `_version = 1`.
*   **Clustering / Indexing:** Cluster SCD Type 2 tables on
    `(natural_key, valid_from)` to accelerate point-in-time
    range-lookup joins from fact tables.
*   **Fact Join Rule:** Fact tables join to the surrogate key
    corresponding to the transaction date:
    `fact.tx_date >= dim.valid_from AND fact.tx_date < dim.valid_to`.
*   **Growth Monitoring:** Track dimension row count per load.
    Alert if a single batch grows a dimension by > 20% of its
    total row count — this signals a volatile attribute is being
    tracked incorrectly as Type 2.

### SCD Type 4 (Split Table History)
*   **Definition:** Surfaces the current state (Type 1) in the primary dimension table, while routing all historical state versions to a separate history log table.
*   **Use Case:** High-cardinality dimensions where dimension table size/performance is critical, but history is still needed for audit or low-frequency querying.

---

## 2. Platform Ingestion Frameworks

### Databricks / Delta Lake (DLT)
*   **Standard:** Use Delta Live Tables (DLT) `APPLY CHANGES INTO` syntax.
*   **Configuration:** Always configure:
    *   `KEYS` mapping the business key.
    *   `SEQUENCE BY` referencing the source commit sequence/timestamp.
    *   `STORED AS {SCD TYPE 1 | SCD TYPE 2}`.
*   *Note:* The DLT framework automatically handles out-of-order records and updates active/closed range parameters.

### Snowflake
*   **Standard:** Use `dbt snapshots` or native **Dynamic Tables** as the primary orchestration pattern instead of writing custom multi-statement `MERGE` procedures.
*   **Optimization:** When using raw SQL queries, leverage temporal joins and cluster the table on `(natural_key, valid_from)` to accelerate range-lookup joins.

---

## 3. Late-Arriving Data Ingestion

### Late-Arriving Dimension Records (Placeholders)
When a fact record arrives referencing a natural key that does not yet exist in the dimension table:
1.  Generate a placeholder dimension record.
2.  Assign a conformed surrogate key (hash or sequence).
3.  Set the natural key, flag all descriptive fields as `'Unknown'`, set `valid_from` to the fact's transaction date, and `valid_to` to `'9999-12-31'`.
4.  Write the fact table mapping to this surrogate key.
5.  When the actual dimension row arrives, overwrite the placeholder's descriptive attributes using SCD Type 1 logic.

### Late-Arriving Fact Records (Point-in-Time Joins)
When a fact event arrives late (e.g., event happened 3 days ago but ingested today):
*   Do NOT map the fact to the current (`is_current = true`) dimension record.
*   Join the fact to the dimension using the fact transaction date:
    ```sql
    ON fact.natural_key = dim.natural_key
    AND fact.transaction_timestamp >= dim.valid_from
    AND fact.transaction_timestamp < dim.valid_to
    ```

---

## Anti-Patterns ("Do Not Do" Rules)

*   **Do NOT use NULL for Active Rows:** Never set `valid_to`
    to NULL. Use `'9999-12-31'` to ensure index usage and
    avoid expensive `IS NULL` or `COALESCE` filters.
*   **Do NOT track Volatile Fields in SCD Type 2:** Never
    track frequently changing attributes (e.g., account
    balance, daily logins). This triggers row-explosion.
    Move volatile fields to fact tables or junk dimensions.
*   **Do NOT Join Facts to Natural Keys:** Fact tables must
    join strictly using surrogate keys. Natural key joins
    bypass point-in-time version accuracy.
*   **Do NOT allow Overlapping Time Bounds:** Ensure there
    are no overlapping intervals (`valid_from` to `valid_to`)
    for any single natural key.
*   **Do NOT use Auto-Increment in Distributed Pipelines:**
    Never use database identity/auto-increment columns across
    distributed nodes. Use deterministic hashing (e.g.,
    `SHA-256`) to maintain key alignment.
*   **Do NOT run SCD logic on raw data:** Always cleanse,
    standardize, and deduplicate in Silver before applying
    dimensional history logic in Gold.
*   **Do NOT create versions without change detection:**
    Always compare incoming attribute hashes against the
    current row. No-op replays from upstream MUST NOT
    generate phantom version rows.
*   **Do NOT edit closed historical records:** Past versions
    (`is_current = false`) are immutable audit artifacts.
    Corrections MUST be applied as new versions, never by
    updating closed rows.
*   **Do NOT mix tracked/untracked columns without a
    contract:** Every SCD Type 2 table MUST document which
    columns are tracked (trigger new versions) vs. untracked
    (overwritten in-place). Undocumented classification leads
    to unpredictable versioning behavior.

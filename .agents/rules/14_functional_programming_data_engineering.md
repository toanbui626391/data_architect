# Agent Guidelines: Functional Programming in Data Engineering

When writing, refactoring, or generating PySpark pipelines, SQL scripts, or data processing logic in this repository, the AI agent **MUST** strictly adhere to the following functional programming principles and guidelines.

---

## 1. Enforce Immutability (Read-Only State)
*   **Rule:** The agent **MUST NOT** attempt to mutate data structures or variables in-place.
*   **Directive:**
    *   **ALWAYS** treat input DataFrames as read-only.
    *   **MUST** represent transformations as a chain of expressions that yield new DataFrames (e.g. `df_clean = df.select(...)` rather than modifying collection elements).
    *   **NEVER** use mutable global state variables or write to shared in-memory variables inside distributed executors.

---

## 2. Abstract Pure Transformation Functions
*   **Rule:** The agent **MUST** decouple data transformation logic from I/O side effects (reads and writes).
*   **Directive:**
    *   **MUST** keep transformation functions (`transform_data`) **pure**: they must accept a `DataFrame` (and configuration parameters) as arguments, return a new `DataFrame`, and have **zero** side effects (no database writes, no network calls, no system calls).
    *   **MUST** place all writing, merging, and logging side-effects inside dedicated wrapper functions (e.g. `process_micro_batch` or `write_target`) to isolate impure logic.
    *   **SHOULD** ensure transformation code can be unit-tested offline using mocked datasets without needing active database connections.

---

## 3. Guarantee Idempotency
*   **Rule:** The agent **MUST** ensure all data pipeline writes are repeatable and safe to retry.
*   **Directive:**
    *   **NEVER** use blind `INSERT` or append operations that risk duplicating records if the same batch or stream offset runs multiple times.
    *   **MUST** employ `MERGE INTO` (SCD Type 1 or SCD Type 2) or `INSERT OVERWRITE` statements for target tables.
    *   **MUST** verify that replaying a job or streaming checkpoint after a crash results in the exact same database state as a single successful run.

---

## 4. Prioritize Declarative Programming
*   **Rule:** The agent **MUST** describe *what* needs to be computed rather than *how* to loop and manipulate bytes.
*   **Directive:**
    *   **NEVER** use cursor loops, row-by-row iterations, or manual row counter loops to process data.
    *   **MUST** use relational SQL operators or PySpark API methods (e.g. `.groupBy()`, `.filter()`, `.select()`, and Window aggregations) to allow execution engines (like Catalyst Optimizer) to compile optimal execution plans.

---

## 5. Leverage Lazy Evaluation
*   **Rule:** The agent **MUST** minimize intermediate evaluations of the execution graph.
*   **Directive:**
    *   **MUST** construct the transformation flow as a sequence of lazy operations (constructing the DAG).
    *   **NEVER** trigger unnecessary Actions (like `.count()`, `.show()`, or `.collect()`) in production code paths unless logging metrics, as they force immediate evaluations, break pipeline pipelining, and severely degrade performance.

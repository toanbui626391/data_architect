# Clean Code Principles for Data Engineering

All batch and streaming PySpark pipelines in this repository MUST strictly adhere to the following clean code standards to ensure modularity, readability, maintainability, and testability.

---

## 1. Don't Repeat Yourself (DRY)
*   **Common Functions:** Common functions like audit logging, metrics tracking, or custom session builders MUST be abstracted into shared utility files (e.g., `fabric_observability.py`) instead of being duplicated across individual scripts.
*   **Imports:** Import shared utilities in your job scripts.

## 2. Modularity & Separation of Concerns
*   **Step Division:** Avoid monolithic script structures. Divide the pipeline logic into clearly bounded, single-responsibility functions:
    1.  `get_spark_session(...)`: Configure and initialize the session.
    2.  `read_source(...)`: Load streaming or batch source data.
    3.  `transform_data(...)`: Apply cleaning, casting, deduplication, and quality checks (pure transform logic).
    4.  `write_target(...)`: Append or merge to target tables and Dead Letter Queues (DLQ).
    5.  `log_execution(...)`: Collect run-level stats and write execution logs.
*   **Decoupled Transforms:** Keep data transform logic (`transform_data`) free of write side-effects (pure functions) so they can be unit-tested locally without requiring connection to OneLake.

## 3. Strict Exception Handling & Alerting Boundaries
*   **No Silent Failures:** Never catch exceptions silently. If a step fails, log the metrics with `status = 'Failed'`, detail the error message, and re-raise (`raise`) the exception to notify the orchestrator (Data Factory / Fabric Scheduler).
*   **Granular Try-Except Blocks:** Wrap network calls (reading from Event Hubs, Delta logs, writing to tables) in detailed try-except structures to pinpoint failure reasons (e.g., connection drop vs. schema mismatch).

## 4. Coding Standards & Documentation
*   **Type Hinting:** Use standard Python type hinting for all parameters and return types (e.g., `def process_batch(df: DataFrame, batch_id: int) -> None`).
*   **Standard Docstrings:** Every function must have a clear PEP 257 docstring explaining its purpose, parameters, and return types.
*   **Variable Names:** Use clean, descriptive naming conventions (PEP 8 snake_case for functions/variables, UPPER_CASE for constants).
*   **Configuration Decoupling:** Keep environment variables and file paths at the top of the file as constants or fetch them dynamically (e.g., Key Vault).

## 5. Cost-Aware Spark Configurations
*   **Centralize Settings:** Define Spark configurations (shuffle partitions, adaptive query execution, state store providers) in the shared utility builder, but allow overrides on a per-job basis.

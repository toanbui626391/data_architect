# ELT Data Pipeline Rules: Quality & Observability

All batch and streaming ELT (Extract, Load, Transform) data pipelines in this
repository MUST adhere to these unified quality and observability rules to
prevent data corruption, silent failures, and schema anomalies.

---

## 1. Pipeline Design & Idempotency

*   **Idempotent Execution:** Every pipeline load MUST be fully idempotent.
    Re-running a batch or streaming job must never duplicate or lose data.
    *   **Streaming:** Use structured streaming checkpoints to ensure
        exactly-once processing.
    *   **Batch:** Use deterministic `MERGE` statements with distinct primary
        keys or partition-level `OVERWRITE` statements. Avoid `INSERT INTO`
        without prior deduplication.
*   **Backpressure Handling (Streaming):** Ingestion pipelines must limit max
    batch sizing (e.g., `maxFilesPerTrigger` or `maxBytesPerTrigger`) to
    prevent out-of-memory (OOM) errors during traffic spikes.
*   **Watermarking (Streaming):** Use watermarking on all streaming event
    streams to prune old state data and prevent unbounded memory state growth.

---

## 2. Schema Enforcement & Data Quality (DQ)

*   **Schema Evolution Policy:**
    *   **Ingestion (Bronze):** Schema evolution must be enabled (e.g.,
        `cloudFiles.schemaEvolutionMode = "rescue"`) to capture unrecognized
        columns dynamically without failing the pipeline.
    *   **Conformed (Silver/Gold):** Schema evolution is strictly disabled.
        Any schema modification requires an explicit schema registry update
        or `ALTER TABLE` statement.
*   **Edge Validation (Push):** Webhook push pipelines must enforce OpenAPI or
    JSON Schema validation at the API Gateway or edge tier. Malformed payloads
    must be rejected immediately (400 Bad Request).
*   **Three-Tier Expectation Model:**
    *   **Bronze Layer:** Enforce structural parameters (e.g., `kafka_offset IS
        NOT NULL`) using `ON VIOLATION WARN`. Never reject records in Bronze.
    *   **Silver Layer:** Enforce type conversions and key completeness. Use
        `ON VIOLATION DROP` for records missing join keys. Use `ON VIOLATION
        WARN` for optional columns.
    *   **Gold Layer:** Enforce business logic constraints (e.g., `price >= 0`)
        using `ON VIOLATION WARN`. Use `ON VIOLATION FAIL UPDATE` only for
        critical violations that would corrupt downstream reports.
*   **Dead Letter Queues (DLQ):** Connectors and parsers must write bad records
    to a dead letter queue (DLQ) rather than failing the execution. DLQs must
    mirror the structure of the source table and capture the parse error
    context.

---

## 3. Observability & Telemetry

*   **Audit Columns (Lineage):** Every table must implement audit columns:
    *   Bronze: `_ingested_at TIMESTAMP`
    *   Silver: `_bronze_ingested_at TIMESTAMP`,
        `_silver_processed_at TIMESTAMP`
    *   Gold: `_gold_updated_at TIMESTAMP`
*   **Consumer Lag Monitoring:** Streaming pipelines must continuously export
    offset lag metrics. Trigger a P1 incident if lag increases continuously
    for more than 5 minutes.
*   **Throughput Monitoring:** Track processed row counts.
    *   **Streaming:** Monitor `processedRowsPerSecond`. Alert on a drop to
        zero.
    *   **Batch:** Alert if a batch run loads 50% fewer rows than the rolling
        7-day average.
*   **Logs Centralization:** All connector, worker, and pipeline logs must
    export to a centralized log workspace (Azure Monitor, AWS CloudWatch,
    Datadog). Silent failures are prohibited.

# Data Warehouse Observability & Alerting Rules

A data warehouse is only as reliable as its observability. All data platforms (Databricks, Snowflake, BigQuery) MUST strictly adhere to the following telemetry, monitoring, and alerting standards to prevent silent failures and control costs.

---

## 1. Pipeline Health & Data Freshness (SLAs)

*   **SLA Definitions:** Every Gold/Consumption layer table MUST have a defined freshness SLA documented in its metadata (e.g., "Updated by 08:00 AM daily" or "Max 15-minute lag").
*   **Freshness Monitoring:** Monitor completion timestamps against the SLA. Alerting on "Job Failed" alone is insufficient. You MUST also alert on "Table Stale" due to silent upstream delays and "Job Running Too Long" exceeding a defined timeout.
*   **Streaming Consumer Lag:** Monitor consumer offset lag continuously. Alert if lag grows continuously for > 5 minutes.
*   **Streaming Throughput:** Monitor `inputRowsPerSecond` vs. `processedRowsPerSecond`. A sustained divergence indicates the cluster is falling behind and requires scale-up. Alert if throughput drops to zero during expected traffic windows.

---

## 2. Data Quality (DQ) Observability

*   **Medallion DQ Enforcement (Two-Constraint Model):**
    *   **Bronze:** Structural checks only (`ON VIOLATION WARN`). Never drop records.
    *   **Silver:** Syntactic checks. Use `ON VIOLATION WARN` to retain records while logging violations. Alert if violation rate exceeds 1% of total volume.
    *   **Gold:** Semantic business checks. Use `ON VIOLATION WARN` for standard metrics. Use `ON VIOLATION FAIL UPDATE` **only** for catastrophic violations that would corrupt downstream dashboards (e.g., `order_total >= 0` violation).
*   **Telemetry Source (Databricks):** The DLT Event Log (System Tables) is the authoritative source for all DQ violation metrics. Databricks SQL Alerts must query `event_log_table` for `STATE = 'FAILED'` and expectation violation counts.
*   **Volume Anomaly Detection:** Track row counts per load. Alert if a pipeline loads > 50% fewer rows than its 7-day rolling average, which signals a partial or silent source system failure.

---

## 3. Compute & Cost Observability

*   **Warehouse / Cluster Utilization:**
    *   Snowflake: Monitor `WAREHOUSE_LOAD_HISTORY`. Alert if query queuing exceeds 5 minutes (undersized warehouse).
    *   Databricks: Monitor cluster memory/CPU. Alert on persistent OOM errors or excessive disk spill.
*   **Spike Detection:** Implement automated budget alerts. Alert Data Engineering if daily compute spend spikes > 30% above the 30-day moving average.
*   **Idle Compute:** Alert on clusters or warehouses running without active queries for > 30 minutes. Auto-suspend must be rigidly enforced on all warehouses.

---

## 4. Alert Routing & Severities

Alerts MUST be routed via an incident management tool (PagerDuty, OpsGenie) and categorized by severity to prevent alert fatigue. Email alerts for critical issues are forbidden.

| Severity | Condition | Routing | Action Required |
|---|---|---|---|
| **P1** | Gold table misses SLA / Pipeline `FAIL UPDATE` / Zero rows loaded | PagerDuty (Wake up on-call) | Immediate triage and stakeholder notification. |
| **P2** | Silver DQ drop rate > 1% / Consumer lag growing > 5 min / Cost spike | Slack (Data Eng Channel) | Investigate within business hours. |
| **P3** | Bronze structural warnings / Cluster disk spill / Long-running query | JIRA / Issue Tracker | Address during next sprint. |

---

## 5. Centralized Telemetry

*   **No Siloed Logs:** All diagnostic logs, query histories, and job statuses MUST be exported from proprietary platforms (Databricks Event Log, Snowflake `ACCOUNT_USAGE`, Kafka JMX) into a centralized observability platform (e.g., Datadog, Azure Monitor, Splunk).
*   **Dashboarding:** Maintain a single "Data Platform Health" dashboard with three mandatory panels:
    1.  Pipeline SLA status (Red/Green per table).
    2.  Data Quality violation rates per layer.
    3.  Daily Compute Cost vs. 30-day average.

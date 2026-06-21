# Centralized Message Bus Rules

The message bus is the **backbone of all real-time data ingestion**. All streaming architectures MUST adhere to these standards. For general network/security rules see Rule 09; for alerting standards see Rule 11.

---

## 1. Architecture & Design Standards

*   **Single Central Bus:** All sources (SaaS APIs, CDC databases, partner feeds) MUST publish to one centralized message bus (Apache Kafka, Azure Event Hubs, or GCP Pub/Sub). No pipeline may consume directly from a source database in production.
*   **No Custom Producers:** Standardize on Kafka Connect connectors (Debezium for CDC, JDBC for databases, SaaS connectors for APIs). Write custom producer code only when no mature connector exists.
*   **Topic Naming Convention:** Topics MUST follow `{source}.{entity}.{version}` (e.g., `crm.sales_orders.v1`). Version the topic on breaking schema changes; never alter a live topic's schema in place.
*   **Partitioning:** Partition topics by the primary entity key (e.g., `order_id`) to ensure ordered delivery per entity and enable consumer parallelism.
*   **KRaft Metadata Quorum:** Production Kafka clusters MUST utilize KRaft (Kafka Raft) for metadata management. ZooKeeper coordination is strictly forbidden.

---

## 2. Data Quality & Schema Contracts

*   **Schema Registry is Mandatory:** Every topic MUST enforce a schema contract via a Schema Registry (Confluent or Apicurio). The registry rejects producer messages that violate the registered schema before they reach consumers.
*   **Backward-Compatible Evolution Only:** Schema changes MUST be backward-compatible (adding optional fields). Breaking changes require a new topic version (`*.v2`). Compatibility mode MUST be set to `BACKWARD` or `FULL`.
*   **Serialization Format:** Use Avro or Protobuf as the wire format. Plain JSON is forbidden for high-throughput topics — it provides no broker-level schema enforcement.
*   **CI/CD Validation:** Schema compatibility MUST be validated against the Schema Registry in CI pipelines. Breaking schemas must fail the build, not fail at runtime.
*   **Standard Message Headers:** Every published message MUST include standard metadata headers: `event_id` (UUID), `timestamp` (UTC), `producer_id`, and distributed tracing context.

---

## 3. Error Handling & Dead Letter Queues

*   **DLQ per Topic:** Every source topic MUST have a corresponding DLQ topic (e.g., `crm.sales_orders.dlq`). Configure connectors with `errors.tolerance = all` to route unparseable payloads to the DLQ instead of halting the connector.
*   **Error Classification:** Classify failures as transient (network blips, temporary unavailability) or permanent (schema mismatch, malformed payload). Retry transient failures with exponential backoff before routing to DLQ. Route permanent failures directly to DLQ.
*   **DLQ Message Enrichment:** DLQ messages MUST include metadata headers: original topic, partition, offset, error message, and failing application version. Never store raw payloads alone.
*   **DLQ Alerting:** A DLQ message count > 0 is never acceptable in steady state. Any DLQ message MUST trigger an immediate P1 alert (per Rule 11).

---

## 4. Security & Data Durability

*   **Authentication & Encryption:** All producers and consumers MUST authenticate via SASL/SCRAM or mTLS. All traffic encrypted in transit via TLS 1.2+. At-rest encryption per Rule 09.
*   **Zero Data Loss Guarantees:** Producers MUST use `acks=all` and `enable.idempotence=true`. Messages must be fully committed to all replicas before acknowledging success.
*   **Consumer Idempotency:** All consumers MUST be idempotent. Processing the same event multiple times must produce the same result. Use deterministic `MERGE` keys or deduplication windows.
*   **Network Isolation:** The message bus MUST reside within a private network (VNet/VPC). External sources connect via PrivateLink or secure NAT gateways (per Rule 09).

---

## 5. Observability & Monitoring

*   **Producer Health:** Track `messages_per_second` per topic. A sustained drop to zero during business hours indicates a silent source failure. Alert if a connector task enters `FAILED` state.
*   **Consumer Lag:** Monitor consumer group offset lag per partition. Alert if lag grows continuously for > 5 minutes (per Rule 11 P2).
*   **Distributed Tracing:** Inject OpenTelemetry trace context into message headers. Consumers MUST extract and propagate this context to enable end-to-end tracing across asynchronous boundaries (per Rule 11).
*   **End-to-End Auditing:** Reconcile producer message counts against consumer processed counts per topic periodically. Discrepancies beyond DLQ entries indicate silent data loss.

---

## 6. Operational Best Practices

*   **Retention & Tiered Storage:** Minimum 7-day topic retention. For retention requirements beyond 7 days, enable Tiered Storage to offload historical segments to cloud object storage.
*   **Replication Factor:** All production topics MUST use replication factor ≥ 3.
*   **Consumer Group Isolation:** Each pipeline MUST use a unique consumer group ID. Never share consumer groups across pipelines.
*   **Producer Performance Tuning:** Enforce compression (`zstd` or `snappy`) and tune `linger.ms` (e.g., 5-10ms) on producers to maximize batch efficiency and reduce network overhead.
*   **Infrastructure as Code:** All topics, connectors, schemas, and ACLs MUST be provisioned via IaC (Terraform). Manual creation is strictly forbidden.

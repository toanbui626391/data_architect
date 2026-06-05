# Centralized Message Bus Rules

The message bus is the **backbone of all real-time data ingestion**. All data warehouse architectures using streaming MUST adhere to these standards for reliability, data quality, observability, and alerting.

---

## 1. Architecture & Design Standards

*   **Single Central Bus:** All sources (SaaS APIs, CDC databases, partner feeds) MUST publish to one centralized message bus (**Apache Kafka**, **Azure Event Hubs**, or **GCP Pub/Sub**). No pipeline may consume directly from a source database in production.
*   **No Custom Producers:** Standardize on **Kafka Connect** connectors (Debezium for CDC, JDBC for databases, SaaS connectors for APIs). Write custom producer code only as a last resort and only when no mature connector exists.
*   **Topic Naming Convention:** Topics MUST follow the pattern `{source}.{entity}.{version}` (e.g., `crm.sales_orders.v1`). Version the topic when a breaking schema change occurs; never alter a live topic's schema in place.
*   **Dead Letter Queue (DLQ) per Topic:** Every source topic MUST have a corresponding DLQ topic (e.g., `crm.sales_orders.dlq`). Configure all connectors with `errors.tolerance = all` to route unparseable payloads to the DLQ instead of halting the connector.
*   **Partitioning:** Partition topics by the primary entity key (e.g., `order_id`, `customer_id`) to ensure ordered delivery per entity and enable downstream consumer parallelism.

---

## 2. Data Quality & Schema Contracts

*   **Schema Registry is Mandatory:** Every topic MUST enforce a schema contract using a **Schema Registry** (Confluent Schema Registry or Apicurio). The registry rejects producer messages that violate the registered schema before they reach consumers.
*   **Backward-Compatible Evolution Only:** Schema changes MUST be backward-compatible (adding optional fields). Breaking changes (removing fields, changing types) require creating a new topic version (`*.v2`). The Schema Registry's compatibility mode MUST be set to `BACKWARD` or `FULL`.
*   **Serialization Format:** Use **Avro** or **Protobuf** as the wire format. Avoid plain JSON for high-throughput topics; it provides no schema enforcement at the broker level.
*   **DLQ Alert on Any Message:** A DLQ message count `> 0` is never acceptable in steady state. Any message landing in a DLQ indicates a serialization or structural failure at the source and MUST trigger an immediate alert.

---

## 3. Security & Data Durability

*   **Authentication & Encryption:** Anonymous access to the message bus is strictly forbidden. All producers and consumers MUST authenticate using **SASL/SCRAM** or **mTLS**. All traffic must be encrypted in transit via TLS 1.2+.
*   **Zero Data Loss Guarantees:** Producers MUST be configured with `acks=all` (or equivalent) and `enable.idempotence=true` to ensure messages are fully committed to all replicas before acknowledging success.
*   **Network Isolation:** The message bus MUST reside within a private network (VNet/VPC). External sources (e.g., SaaS APIs) must connect via secure NAT gateways or PrivateLink, never over the public internet directly to the brokers.

---

## 4. Observability & Monitoring

Monitor the message bus across two dimensions:

*   **Producer Health:**
    *   Track `messages_per_second` per topic. A sustained drop to zero during business hours indicates a silent source system failure.
    *   Alert if a connector task enters `FAILED` state.

*   **Consumer Lag (Most Critical Metric):**
    *   Monitor the **consumer group offset lag** per topic partition. Lag represents the number of unprocessed messages queued behind the consumer.
    *   Alert immediately if lag **grows continuously for more than 5 minutes**, indicating the consumer is falling behind real-time SLAs.

*   **Monitoring Tools:** Use platform-native tools (**Confluent Control Center**, **Azure Monitor**, **GCP Cloud Monitoring**).

---

## 5. Alerting Standards

All alerts MUST be actionable and routed to an on-call communication channel (Slack, PagerDuty). 

| Alert | Condition | Severity | Responsible Team |
|---|---|---|---|
| Connector Task Failed | Task state = `FAILED` | **P1** | Platform Engineering |
| DLQ Message Received | DLQ topic count > 0 | **P1** | Platform Engineering |
| Consumer Lag Growing | Lag increases continuously > 5 min | **P2** | Data Engineering |
| Throughput Drop | `messages/sec` drops to 0 in business hours | **P2** | Data Engineering |
| Topic Disk Usage High | Broker disk > 80% | **P3** | Platform Engineering |

---

## 6. Operational Best Practices

*   **Retention Policy:** Set topic retention to a minimum of **7 days** to allow pipeline replay and incident recovery without data loss.
*   **Replication Factor:** All production topics MUST use a **replication factor of 3** (minimum) to tolerate broker failures.
*   **Consumer Group Isolation:** Each pipeline consuming a topic MUST use a **unique consumer group ID**. Never share a consumer group across different pipelines.
*   **Infrastructure as Code:** All Kafka topics, connectors, and Schema Registry schemas MUST be provisioned via IaC (**Terraform**). Manual creation is strictly forbidden.

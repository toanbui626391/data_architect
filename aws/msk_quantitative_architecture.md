# Quantitative Design: AWS Centralized Message Bus (Amazon MSK)

## 1. Executive Summary

This document establishes the quantitative resource sizing and cloud economics framework for building an enterprise Centralized Message Bus on AWS using **Amazon Managed Streaming for Apache Kafka (MSK)**.

It serves as the upstream companion to the [Databricks Quantitative Architecture](./databricks_dw_quantitative_architecture.md) and quantifies the architectural patterns defined in the [Unified Source to MSK Architecture](./unified_source_to_msk_architecture.md).

The MSK ecosystem has a fundamentally different cost profile compared to Databricks:
1. **MSK Brokers**: A fixed hourly infrastructure cost (always-on).
2. **MSK Connect**: A variable cost layer that auto-scales based on MCU (MSK Connect Unit) hours.
3. **Webhook Path (API Gateway + SQS + Pipes)**: A pure pay-per-request serverless model.

This framework details how to configure every resource to maximize throughput, guarantee zero data loss, and control costs.

---

## 2. Standardized Throughput Tiers

To ensure an accurate end-to-end cost model, we align the ingestion tiers exactly with the downstream Databricks Data Warehouse model:

| Metric                        | Small Tier (Batch/Low-Volume) | Medium Tier (Enterprise Scale) | Large Tier (High-Volume Streaming) |
| :---------------------------- | :---------------------------- | :----------------------------- | :--------------------------------- |
| **Daily Ingestion Volume**    | 100 GB/day                    | 1.0 TB/day                     | 10.0 TB/day                        |
| **Average Throughput**        | ~1.15 MB/sec                  | ~11.57 MB/sec                  | ~115.74 MB/sec                     |
| **Record Rate** (~1 KB/event) | ~1,150 events/sec             | ~11,570 events/sec             | ~115,740 events/sec                |
| **Total Topics**              | 10 Topics                     | 50 Topics                      | 500+ Topics                        |
| **Total Partitions**          | 30 Partitions                 | 300 Partitions                 | 3,000+ Partitions                  |
| **Replication Factor**        | 3 (Standard)                  | 3 (Standard)                   | 3 (Standard)                       |

---

## 3. MSK Broker Sizing (The Fixed Cost Layer)

MSK is provisioned as an always-on cluster. Brokers must be sized for peak throughput, not average throughput.

### 3.1 Broker Instance Selection and Scaling

The number of brokers is driven by the **number of partitions** and the **network throughput** per broker. 

*   **Formula**: `Brokers = max(3, ceil(Total Partitions / Partitions per Broker limit))`
*   *Note: We deploy across 3 Availability Zones, so broker count must be a multiple of 3.*

**Tier Configurations (Standard pricing for `us-east-1`):**
1.  **Small Tier (100 GB/day)**:
    *   **Instance**: `kafka.m5.large` (2 vCPU, 8 GB RAM)
    *   **Cluster Size**: 3 Brokers (1 per AZ)
    *   **Partition Limit**: 1,000 partitions per broker (3,000 total)
    *   **Cost**: 3 × $0.21/hr × 720 hrs = **$453.60 / month**

2.  **Medium Tier (1.0 TB/day)**:
    *   **Instance**: `kafka.m5.2xlarge` (8 vCPU, 32 GB RAM)
    *   **Cluster Size**: 3 Brokers (1 per AZ)
    *   **Partition Limit**: 2,000 partitions per broker (6,000 total)
    *   **Cost**: 3 × $0.84/hr × 720 hrs = **$1,814.40 / month**

3.  **Large Tier (10.0 TB/day)**:
    *   **Instance**: `kafka.m5.4xlarge` (16 vCPU, 64 GB RAM)
    *   **Cluster Size**: 6 Brokers (2 per AZ)
    *   **Partition Limit**: 4,000 partitions per broker (24,000 total)
    *   **Cost**: 6 × $1.68/hr × 720 hrs = **$7,257.60 / month**

### 3.2 EBS Storage Sizing

*   **Formula**: `Total Storage = Daily Volume × Retention Days × Replication Factor × Overhead (1.1)`
*   **Retention**: Configured to **7 days** (allows time for downstream consumers to recover from outages).
*   **MSK Storage Price**: $0.10 / GB / month (Standard MSK provisioned capacity in `us-east-1`).

**Tier Storage Costs:**
*   **Small Tier**: 100 GB × 7 × 3 × 1.1 = 2,310 GB = **$231.00 / month**
*   **Medium Tier**: 1,000 GB × 7 × 3 × 1.1 = 23,100 GB = **$2,310.00 / month**
*   **Large Tier**: 10,000 GB × 7 × 3 × 1.1 = 231,000 GB = **$23,100.00 / month**

---

## 4. MSK Connect Sizing (The Variable Cost Layer)

AWS MSK Connect runs Kafka Connect workers as serverless endpoints. Costs are based on **MSK Connect Units (MCUs)**. One MCU is 1 vCPU and 4 GB RAM.

*   **Pricing**: $0.11 per MCU-hour.
*   **Auto-scaling Policy** (from Terraform): Scale out at 80% CPU; Scale in at 20% CPU.

### 4.1 Connector Resource Profiles

1.  **Small Tier (e.g., Salesforce CDC - Low Volume)**:
    *   **Config**: 1 Connector, Min Workers = 1, Max Workers = 3, `tasks.max` = 1.
    *   **Average Active MCUs**: 1
    *   **Cost**: 1 MCU × $0.11/hr × 720 hrs = **$79.20 / month**

2.  **Medium Tier (e.g., Multiple CDC/JDBC Connectors)**:
    *   **Config**: Multiple concurrent connectors (e.g., SAP HANA JDBC, Salesforce CDC).
    *   **Average Active MCUs**: 5 (combined cluster-wide average)
    *   **Cost**: 5 MCUs × $0.11/hr × 720 hrs = **$396.00 / month**

3.  **Large Tier (Enterprise Aggregation - High Volume CDC)**:
    *   **Config**: 5+ Heavy Connectors, active auto-scaling.
    *   **Average Active MCUs**: 20 (across all connectors)
    *   **Cost**: 20 MCUs × $0.11/hr × 720 hrs = **$1,584.00 / month**

---

## 5. Webhook Push Path Sizing (Serverless Ingestion)

The webhook ingestion path (API Gateway → SQS → EventBridge Pipes → MSK) is a pure serverless path. You only pay for what you use, based on the **Record Rate**.

### 5.1 Request Pricing

*   **API Gateway (REST)**: $3.50 per 1 million requests.
*   **API Gateway (HTTP)**: $0.90 per 1 million requests.
*   **Amazon SQS**: $0.40 per 1 million requests (Standard Queue).
*   **EventBridge Pipes**: $0.40 per 1 million requests (Standard).

*Note: The EventBridge Pipe is configured with an SQS batch size of 10 (`batch_size = 10`), meaning Pipes and MSK are only invoked once for every 10 API requests, saving massive compute costs.*

### 5.2 Serverless Tier Costs (Assuming 50% Ingestion Split)

If 50% of the daily ingestion volume is pushed via webhooks, the monthly events are:
*   **Small Tier**: 1.5 Billion events/month
*   **Medium Tier**: 15 Billion events/month
*   **Large Tier**: 150 Billion events/month

1.  **Small Tier (1.5 Billion events/month)**:
    *   **API Gateway (REST)**: 1,500M × $3.50/M = **$5,250.00**
    *   **SQS**: (1,500M writes + 150M reads) × $0.40/M = **$660.00**
    *   **EventBridge Pipes**: 150M reads × $0.40/M = **$60.00**
    *   **Total**: **$5,970.00 / month**

2.  **Medium Tier (15 Billion events/month)**:
    *   **API Gateway (REST)**: 15,000M × $3.50/M = **$52,500.00**
    *   **SQS**: (15,000M writes + 1,500M reads) × $0.40/M = **$6,600.00**
    *   **EventBridge Pipes**: 1,500M reads × $0.40/M = **$600.00**
    *   **Total**: **$59,700.00 / month**

3.  **Large Tier (150 Billion events/month)**:
    *   **API Gateway (HTTP)**: 150,000M × $0.90/M = **$135,000.00**
    *   **SQS**: (150,000M writes + 15,000M reads) × $0.40/M = **$66,000.00**
    *   **EventBridge Pipes**: 15,000M reads × $0.40/M = **$6,000.00**
    *   **Total (with HTTP API)**: **$207,000.00 / month**

---

## 6. Data Quality & Observability Sizing

1.  **AWS Glue Schema Registry**:
    *   The registry acts as the enforcement engine for AVRO schemas.
    *   **Pricing**: 1 million requests free, then $1.00 per million. 
    *   **Impact**: Kafka clients cache schemas heavily. Estimated cost: **<$5.00 / month** across all tiers.
2.  **CloudWatch Logs & Metrics**:
    *   MSK Broker logging, API Gateway execution logs, and MSK Connect worker logs.
    *   Estimated monthly costs: Small: **$50.00**, Medium: **$250.00**, Large: **$1,000.00**.

---

## 7. End-to-End Cost Matrices

*Note: These matrices assume a hybrid ingestion model where 50% of the volume comes from MSK Connect (Pull) and 50% comes from Webhooks (Push).*

### 7.1 Small Tier (100 GB/day)
| Resource                  | Details                 | Monthly Cost  |
| :------------------------ | :---------------------- | :------------ |
| **MSK Brokers**           | 3 × `kafka.m5.large`    | $453.60       |
| **EBS Storage**           | 2,310 GB                | $231.00       |
| **MSK Connect**           | 1 MCU Average           | $79.20        |
| **Serverless Push (50%)** | 1.5B API/SQS/Pipe events| $5,970.00     |
| **Observability**         | CloudWatch              | $50.00        |
| **Total Model Cost**      | —                       | **$6,783.80** |

### 7.2 Medium Tier (1.0 TB/day)
| Resource                  | Details                  | Monthly Cost   |
| :------------------------ | :----------------------- | :------------- |
| **MSK Brokers**           | 3 × `kafka.m5.2xlarge`   | $1,814.40      |
| **EBS Storage**           | 23,100 GB                | $2,310.00      |
| **MSK Connect**           | 5 MCUs Average           | $396.00        |
| **Serverless Push (50%)** | 15B API/SQS/Pipe events  | $59,700.00     |
| **Observability**         | CloudWatch               | $250.00        |
| **Total Model Cost**      | —                        | **$64,470.40** |

### 7.3 Large Tier (10.0 TB/day)
| Resource                  | Details                     | Monthly Cost    |
| :------------------------ | :-------------------------- | :-------------- |
| **MSK Brokers**           | 6 × `kafka.m5.4xlarge`      | $7,257.60       |
| **EBS Storage**           | 231,000 GB                  | $23,100.00      |
| **MSK Connect**           | 20 MCUs Average             | $1,584.00       |
| **Serverless Push (50%)** | 150B HTTP API/SQS/Pipe events| $207,000.00     |
| **Observability**         | CloudWatch                  | $1,000.00       |
| **Total Model Cost**      | —                           | **$239,941.60** |

---

## 8. Total End-to-End Pipeline Cost (MSK + Databricks)

Combining this model with the downstream Databricks model provides the true Total Cost of Ownership (TCO) for the data platform:

| Tier               | Central Message Bus (MSK) | Data Warehouse (Databricks) | **Total Platform TCO / Month** |
| :----------------- | :------------------------ | :-------------------------- | :----------------------------- |
| **Small (100 GB)** | $6,783.80                 | $853.92                     | **$7,637.72**                  |
| **Medium (1 TB)**  | $64,470.40                | $6,071.43                   | **$70,541.83**                 |
| **Large (10 TB)**  | $239,941.60               | $34,143.10                  | **$274,084.70**                |

---

## 9. MSK Architecture & Cost Map

```mermaid
graph TD
    subgraph "Push Ingestion (Serverless)"
        WH[Webhooks] -->|API Rate: $3.50/M| API[API Gateway]
        API -->|Queue Rate: $0.40/M| SQS[SQS Buffer]
        SQS -->|Pipe Rate: $0.40/M| PIPE[EventBridge Pipes]
    end

    subgraph "Pull Ingestion (Compute)"
        DB[(SAP/Salesforce)] -->|MCU Rate: $0.11/hr| CONN[MSK Connect]
    end

    subgraph "Central Message Bus (Fixed)"
        PIPE --> MSK
        CONN --> MSK
        MSK[Amazon MSK Brokers]
        MSK --- EBS[(EBS Storage $0.10/GB)]
    end

    subgraph "Data Quality"
        MSK -.- GLUE[Glue Schema Registry]
        CONN -.- GLUE
    end

    MSK -->|Databricks DLT| DBX[Databricks Warehouse]
```

---

## 10. Summary of Quantitative Best Practices (FinOps Rules)

1.  **Avoid API Gateway at High Volumes**: In the Medium/Large Tiers, request-based API Gateway costs are prohibitive ($52,500/M for Medium). Implement **Direct SQS Ingestion** or route requests through an **Application Load Balancer (ALB)** behind a lightweight ECS cluster to bypass API Gateway transaction fees entirely.
2.  **Right-size Replication**: A replication factor of 3 is standard for production. Do not use replication factor 4, as it drastically inflates cross-AZ network traffic and EBS storage costs without meaningful availability gains.
3.  **Batch Everything**: The EventBridge Pipe must use an SQS batch size of at least 10 (as configured in the Terraform `batch_size = 10`). This reduces Pipe execution requests by 90%, cutting Pipe costs by 90% and optimizing MSK disk writes.
4.  **Tune MSK Connect CPU Scaling**: The Terraform scales out when CPU hits 80% and scales in at 20%. For bursty CDC workloads, consider lowering the scale-out threshold to 60% to prevent message lag during rapid spikes, at the cost of slightly higher MCU-hours.
5.  **Implement Tiered Storage for MSK**: If data retention needs to exceed 7 days, enable MSK Tiered Storage. This automatically offloads older Kafka segments to Amazon S3, allowing you to retain data for months without provisioning expensive EBS volumes.

# Retrieval-Augmented Generation (RAG) & AI Agents Architecture

Welcome to the **RAG & AI Agents Architecture** module. This directory contains production-grade architecture blueprints, design patterns, and engineering guidelines for building scalable, secure, and observable RAG systems and autonomous AI Agents.

---

## 📚 Document Index

| Blueprint / Document | Primary Focus | Key Platform & Components |
| :--- | :--- | :--- |
| [Databricks Enterprise RAG & AI Agents](file:///Users/toanbui/dev/data_architect/rag/databricks_enterprise_rag_and_ai_agents.md) | End-to-End Enterprise Architecture | Databricks, Unity Catalog, Delta Live Tables, Databricks AI Search, Model Serving, MLflow 3.0, DABs |
| [Databricks Vector Search Architecture](file:///Users/toanbui/dev/data_architect/rag/databricks_vector_search_architecture.md) | Vector Search Engine Deep Dive | Databricks AI Search, Delta Sync Index, Managed Embeddings, Hybrid Search (HNSW + BM25) |
| [Data Engineering RAG Patterns](file:///Users/toanbui/dev/data_architect/rag/data_engineering_rag_patterns.md) | Data Engineer Perspective & DE Patterns | Auto Loader, DLT Parsing/Chunking, Delta CDF, Unity Catalog Functions (Data-as-a-Tool) |

---

## 🏗️ High-Level RAG & AI Agent Capability Map

```mermaid
flowchart TD
    subgraph IngestPlane ["1. Data Ingestion & Vector Indexing"]
        direction TB
        I1[Unstructured Doc Processing]
        I2[Chunking & Metadata Tagging]
        I3[Hybrid Vector Search Indexing]
    end

    subgraph AgentRuntime ["2. Agentic Orchestration & Tools"]
        direction TB
        A1[Multi-Agent Router & Execution]
        A2[Governed Tool & Function Calling]
        A3[Low-Latency Model Serving]
    end

    subgraph SecurityObs ["3. Security, Governance & Observability"]
        direction TB
        S1[Unified RBAC & ABAC Access Control]
        S2[MLflow Step-by-Step Tracing]
        S3[Automated LLM-as-a-Judge Evaluation]
    end

    IngestPlane --> AgentRuntime
    AgentRuntime --> SecurityObs

    classDef ingestStyle fill:#e2f0d9,stroke:#385723,stroke-width:1px,color:#000;
    classDef agentStyle fill:#dae8fc,stroke:#6c8ebf,stroke-width:1px,color:#000;
    classDef secStyle fill:#e1d5e7,stroke:#9673a6,stroke-width:1px,color:#000,stroke-dasharray: 5 5;
    class I1,I2,I3 ingestStyle;
    class A1,A2,A3 agentStyle;
    class S1,S2,S3 secStyle;
```

> [!NOTE]
> All architectural documents in this directory are optimized for standard displays and small-screen e-ink readers (e.g., 7 to 8-inch BOOX Tab Mini devices).

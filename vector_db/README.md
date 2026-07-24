# Vector Databases: Architecture & Engineering Guide

Welcome to the comprehensive guide on **Vector Databases**, curated for **Data Architects** and **AI Engineers**. This documentation covers fundamental vector search theory, index mechanics, database evaluation, production data pipelines, and modern RAG pattern implementations.

---

## 📚 Document Index

| Document | Primary Audience | Key Topics Covered |
| :--- | :--- | :--- |
| [01. Fundamentals](file:///Users/toanbui/dev/data_architect/vector_db/01_fundamentals.md) | All | Vector embeddings, vector spaces, distance metrics, B-Tree limitations |
| [02. Indexing Algorithms](file:///Users/toanbui/dev/data_architect/vector_db/02_indexing_algorithms.md) | AI Engineers / Data Architects | Flat, IVF, HNSW, PQ, ScaNN, DiskANN & performance trade-offs |
| [03. Data Architect Guide](file:///Users/toanbui/dev/data_architect/vector_db/03_data_architect_perspective.md) | Data Architects | Engine selection, memory sizing, batch/stream pipelines, multi-tenancy & cost |
| [04. AI Engineer Guide](file:///Users/toanbui/dev/data_architect/vector_db/04_ai_engineer_perspective.md) | AI Engineers | Embedding models, chunking, Hybrid Search, Reranking, & RAG patterns |

---

## 🎯 Role Comparison Matrix

```mermaid
flowchart TD
    subgraph DA [Data Architect Focus]
        direction TB
        DA1[Scalability & Partitioning]
        DA2[Storage & RAM Sizing]
        DA3[CDC & ETL Pipeline Design]
        DA4[Cost & Vendor Selection]
    end

    subgraph AE [AI Engineer Focus]
        direction TB
        AE1[Embedding Models & Dimensions]
        AE2[Semantic Chunking]
        AE3[Hybrid Search & Reranking]
        AE4[RAG Quality & Evaluation]
    end

    DA <-->|Shared Goal: High Recall & Low Latency| AE

    classDef daStyle fill:#e2f0d9,stroke:#385723,stroke-width:1px,color:#000;
    classDef aeStyle fill:#dae8fc,stroke:#6c8ebf,stroke-width:1px,color:#000;
    class DA1,DA2,DA3,DA4 daStyle;
    class AE1,AE2,AE3,AE4 aeStyle;
```

> [!NOTE]
> All documentation and diagrams in this directory are formatted for readability on standard screens as well as small-screen e-ink devices (e.g., 7 to 8-inch readers).

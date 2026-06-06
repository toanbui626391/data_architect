---
name: mermaid-edit
description: Use this skill to write or edit Mermaid diagrams in markdown files. It ensures compatibility with VS Code's built-in Markdown preview.
---

# Mermaid Edit Skill

**Agent Context & Tooling:**
The user relies on the built-in VS Code Markdown preview to render Mermaid diagrams embedded in markdown files. This native integration uses a modern version of Mermaid, supporting contemporary features and syntax.

**Instructions for Mermaid Editing:**

1. **Modern Syntax is Supported:**
   - You can use modern features like connecting edges directly to or from subgraphs (e.g., `SubgraphID --> Node`).
   - Use standard `flowchart TD` or `flowchart LR` (or `graph TD` / `graph LR`) combined with `subgraph` blocks to visually organize components into planes, networks, and environments.
   - Define subgraph titles using the square bracket syntax: `subgraph ID [Title with Spaces & Characters]`.

2. **Syntax Compatibility & Best Practices:**
   - **Special Characters in Nodes and Edges:** If a node label OR an edge/link label contains parentheses or other potentially conflicting characters, you MUST use HTML entities (e.g., `&#40;` for `(` and `&#41;` for `)`) to prevent parser confusion and rendering errors.
     - *Correct Node:* `Event[Event Notification <br>&#40;SQS/EventGrid/PubSub&#41;]`
     - *Correct Edge:* `NodeA -->|Returns Data &#40;JSON/CSV&#41;| NodeB`
   - **Avoid Bleeding-Edge Syntax:** While the parser is modern, avoid highly experimental or beta diagram types (e.g., `architecture-beta`) unless explicitly requested or verified.

3. **Small Screen Optimization:**
   - Per the project's architectural guidelines (`.clinerules`), diagrams should be optimized for small screens (e-ink readers). 
   - Keep diagrams as compact as possible. 
   - Use `direction TB` inside subgraphs when using a `flowchart LR` parent diagram to keep horizontal scrolling to a minimum.
   - Limit the length of text labels.

4. **Visual Component Coloring & Clarification:**
   - Always define clear custom styles using `classDef` at the end of the diagram to distinguish different architectural layers visually.
   - Use the standard enterprise pastel color palette to clarify roles:
     - **Storage / Databases:** Soft Green (`fill:#e2f0d9,stroke:#385723,stroke-width:1px,color:#000;`)
     - **Compute / ETL Processes:** Soft Blue (`fill:#dae8fc,stroke:#6c8ebf,stroke-width:1px,color:#000;`)
     - **Central Bus / Telemetry Hubs:** Soft Yellow (`fill:#fff2cc,stroke:#d6b656,stroke-width:2px,color:#000;`)
     - **Monitoring / Logs / Stats / DQ:** Soft Grey / Dotted (`fill:#f5f5f5,stroke:#666,stroke-width:1px,color:#000,stroke-dasharray: 5 5;`)
     - **Alerting & Notifications:** Soft Orange (`fill:#ffe6cc,stroke:#d79b00,stroke-width:1px,color:#000;`)
     - **Security / Identity / Governance:** Soft Purple / Dotted (`fill:#e1d5e7,stroke:#9673a6,stroke-width:1px,color:#000,stroke-dasharray: 5 5;`)
     - **Dead-Letter / Failures:** Soft Red (`fill:#f8cecc,stroke:#b85450,stroke-width:1px,color:#000;`)
   - Explicitly apply styling to all nodes using `class Node1,Node2 ClassName;` for clean and readable diagrams.

**Goal:** Provide clear, modern, and natively compatible Mermaid diagrams optimized for VS Code's built-in preview.

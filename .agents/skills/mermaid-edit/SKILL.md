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
   - **Special Characters in Nodes:** If a node label contains parentheses or other potentially conflicting characters, it is highly recommended to use HTML entities (e.g., `&#40;` for `(` and `&#41;` for `)`) to prevent parser confusion.
     - *Correct:* `Event[Event Notification <br>&#40;SQS/EventGrid/PubSub&#41;]`
   - **Avoid Bleeding-Edge Syntax:** While the parser is modern, avoid highly experimental or beta diagram types (e.g., `architecture-beta`) unless explicitly requested or verified.

3. **Small Screen Optimization:**
   - Per the project's architectural guidelines (`.clinerules`), diagrams should be optimized for small screens (e-ink readers). 
   - Keep diagrams as compact as possible. 
   - Use `direction TB` inside subgraphs when using a `flowchart LR` parent diagram to keep horizontal scrolling to a minimum.
   - Limit the length of text labels.

**Goal:** Provide clear, modern, and natively compatible Mermaid diagrams optimized for VS Code's built-in preview.

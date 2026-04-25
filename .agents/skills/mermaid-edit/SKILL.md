---
name: mermaid-edit
description: Use this skill to write or edit Mermaid diagrams in markdown files. It ensures compatibility with the "Markdown Preview Mermaid Support" extension.
---

# Mermaid Edit Skill

**Agent Context & Tooling:**
The user relies on the "Markdown Preview Mermaid Support" extension in their IDE to preview Mermaid diagrams embedded in markdown files. This extension (like many offline or bundled previewers) typically uses a slightly older or highly stable bundled version of the Mermaid.js library (e.g., v9.x or v10.x).

**Instructions for Mermaid Editing:**

1. **Avoid Experimental Syntax:**
   - **Do NOT** use experimental or bleeding-edge diagram types like `architecture-beta`.
   - When asked to create an architecture diagram, **ALWAYS** use standard `flowchart TD` or `flowchart LR` combined with `subgraph` blocks to visually organize components into planes, networks, and environments.

2. **Syntax Compatibility & Best Practices:**
   - **Node Labels with Special Characters:** If a node label contains HTML tags (like `<br>`), spaces, or special characters (like `&`, `/`), you **MUST** enclose the label in double quotes. 
     - *Correct:* `IdP["Enterprise IdP <br> Okta / Entra ID"]`
     - *Incorrect:* `IdP[Enterprise IdP <br> Okta / Entra ID]`
   - **Subgraph Declarations:** Subgraph IDs must be simple alphanumeric strings without spaces or special characters. Always define the title separately using square brackets.
     - *Correct:* `subgraph IdentityAccess [Enterprise Identity & Access]`
     - *Incorrect:* `subgraph Enterprise Identity & Access`
   - **Edge Definitions:** Avoid putting complex text directly on edges without quotes if they contain unusual characters. Standard pipes are fine: `-->|Action|`.

3. **Small Screen Optimization:**
   - Per the project's architectural guidelines (`.clinerules`), diagrams should be optimized for small screens (e-ink readers). 
   - Keep diagrams as compact as possible. 
   - Use `direction TB` inside subgraphs when using a `flowchart LR` parent diagram to keep horizontal scrolling to a minimum.
   - Limit the length of text labels.

**Goal:** Ensure 100% rendering success across standard markdown preview extensions without causing parser crashes or syntax errors.

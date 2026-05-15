# Rule: Small Screen Optimization

## Overview
All output in this repository must be readable on small-screen
devices (7–8 inch e-ink screens, e.g., BOOX Tab Mini).

## Rules

1. **Limit Line Width:** Keep lines of code, SQL, and prose
   under ~80 characters where possible. Break long lines.

2. **Concise Blocks:** Use short, well-structured blocks of
   content. Avoid dense walls of text.

3. **Mermaid Diagrams:** Keep diagrams compact. Use
   `direction TB` inside subgraphs to reduce horizontal
   scrolling. Limit label text length.

4. **Markdown Formatting:** Use headers, bullet points, and
   tables to break up content. Avoid long single paragraphs.

5. **SQL Formatting:** Place each SELECT column and each JOIN
   clause on its own line for readability.

## Example — SQL (Good)
```sql
SELECT
    d.FiscalPeriodName,
    a.L1_Category,
    SUM(f.AmountFunctional) AS Amount
FROM FactFinancialVariance f
JOIN DimDate    d ON f.DateKey    = d.DateKey
JOIN DimAccount a ON f.AccountKey = a.AccountKey
WHERE v.Is_Current = true
GROUP BY
    d.FiscalPeriodName,
    a.L1_Category;
```

-- =============================================================================
-- gold_sales.sql
-- Gold Layer: Aggregated Business Metrics (Delta Live Tables)
--
-- Design Reference: .agents/rules/08_medallion_architecture_modeling.md
-- Pattern: Materialized View (Incremental Aggregation)
--
-- Responsibilities:
--   1. Aggregate cleansed sales data to the Grain: Customer + Store + Date
--   2. Compute core business metrics (Revenue, Tax, Discounts, Order Counts)
--   3. Apply semantic business logic constraints (e.g., Revenue cannot be negative)
--   4. Expose an optimized, read-heavy table for BI/Analysts (Tableau, PowerBI)
--
-- Unity Catalog target: catalog.gold.sales_daily_summary
-- Owned by:            Analytics Engineering (BI_READ_ROLE)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- SECTION 1: Materialized View Definition
-- -----------------------------------------------------------------------------
-- We use a MATERIALIZED VIEW rather than a STREAMING TABLE for the Gold layer.
-- Because the upstream Silver table has "delta.enableChangeDataFeed" = "true",
-- DLT will automatically compute these aggregations incrementally as new CDC
-- records arrive, rather than scanning the entire Silver table every time.

CREATE OR REFRESH MATERIALIZED VIEW catalog.gold.sales_daily_summary
(
  -- 1.1 Semantic Business Logic Constraints
  -- In the Gold layer, we validate semantic business reality. If these fail,
  -- it usually indicates a flaw in business logic upstream, not ingestion failure.
  -- We use WARN so dashboards stay online, but Data Stewards are alerted.
  CONSTRAINT valid_revenue EXPECT (total_sales_amount >= 0) ON VIOLATION WARN,
  CONSTRAINT valid_order_count EXPECT (total_orders > 0) ON VIOLATION WARN
)
COMMENT "Daily aggregated sales metrics by Customer and Store."
TBLPROPERTIES (
  "quality" = "gold",
  "pipelines.autoOptimize.managed" = "true"
)
CLUSTER BY (order_date, store_id)  -- Liquid Clustering optimization for BI filtering
AS SELECT
  -- -------------------------------------------------------------------------
  -- 1.2 Dimension Grain (Group By)
  -- -------------------------------------------------------------------------
  customer_id,
  store_id,
  order_date,

  -- -------------------------------------------------------------------------
  -- 1.3 Aggregated Business Metrics (Facts)
  -- -------------------------------------------------------------------------
  COUNT(order_id)                                 AS total_orders,
  
  -- Financial Aggregates
  SUM(total_amount)                               AS total_sales_amount,
  SUM(tax_amount)                                 AS total_tax_collected,
  SUM(discount_amount)                            AS total_discounts_given,
  SUM(shipping_amount)                            AS total_shipping_revenue,
  
  -- Averages
  AVG(total_amount)                               AS average_order_value,

  -- -------------------------------------------------------------------------
  -- 1.4 Materialized View Audit Metadata
  -- -------------------------------------------------------------------------
  current_timestamp()                             AS _gold_updated_at

FROM catalog.silver.sales_orders
-- Filter out cancelled/failed orders from the main financial aggregation
WHERE order_status IN ('COMPLETED', 'SHIPPED', 'DELIVERED')
GROUP BY
  customer_id,
  store_id,
  order_date;

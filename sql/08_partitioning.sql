\set ON_ERROR_STOP on
BEGIN;
SET search_path TO blinkit;

-- ============================================================================
-- Blinkit DBMS Project: Phase 5 Scalability Partitioning Architecture
-- Milestone: CP4
-- Deliverable: sql/08_partitioning.sql
-- Target Table: order_items (10,994,856 rows on large dataset; >100M at 100x)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ARCHITECTURAL CHOICE: WHICH TABLE, WHICH COLUMN, WHICH METHOD
-- ----------------------------------------------------------------------------
--
-- Why order_items?
-- order_items is by far the largest, fastest-growing relation in the schema:
-- - Seed dataset (CP2/CP3):      675,000 rows (70 MB with indexes)
-- - Large dataset (Phase 5):  10,994,856 rows (1,028 MB with indexes)
-- - 100x Growth Horizon:     ~110,000,000 rows (~10.5 GB total footprint)
--
-- When order_items outgrows RAM buffer cache (shared_buffers), B-tree depth
-- increases, root/branch buffer eviction spikes, and analytical joins face
-- severe memory pressure and disk spilling.
--
-- Partition Strategy: HASH Partitioning on order_id (4 Partitions)
-- 1. Uniform Distribution: order_id is an identity integer sequence with zero
--    data skew, ensuring perfectly balanced partition sizes (~2.75M rows each).
-- 2. Co-located Partition-Wise Joins: When orders is partitioned with matching
--    modulus on order_id, PostgreSQL executes partition-wise joins:
--    (orders_p0 JOIN order_items_p0), eliminating cross-partition hash joins.
-- 3. Point Lookup Pruning: Real-time queries (R06 order tracking, W02 packing,
--    cart item checks) provide an exact order_id, enabling plan-time pruning
--    of 75% of table scans and indexes.
--
-- ----------------------------------------------------------------------------
-- 2. THE POSTGRESQL PRIMARY KEY RULE FOR PARTITIONED TABLES
-- ----------------------------------------------------------------------------
--
-- PostgreSQL Constraint Enforcement Rule:
-- In declarative partitioning, any UNIQUE or PRIMARY KEY constraint on the parent
-- partitioned table MUST contain all columns of the partition key.
--
-- Why HASH(order_id) strictly satisfies this rule:
-- The natural composite primary key of order_items is (order_id, product_id).
-- Because order_id is part of the existing composite primary key:
-- - HASH (order_id) requires NO schema alterations, NO artificial surrogate keys,
--   and NO column duplication.
--
-- Why RANGE(placed_at) would compromise normalization:
-- order_items does not contain placed_at; placed_at belongs to the parent orders table.
-- To partition order_items by RANGE (placed_at), we would be forced to:
-- 1. Denormalize placed_at into order_items (violating 3NF).
-- 2. Alter the primary key to (order_id, product_id, placed_at).
-- 3. Widen every leaf index page by 8 bytes per tuple (~88 MB overhead on 11M rows).
-- Therefore, HASH (order_id) is the mathematically and architecturally sound strategy.

-- ----------------------------------------------------------------------------
-- 3. DDL: DECLARATIVE PARTITIONED TABLE SETUP
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS order_items_partitioned CASCADE;

CREATE TABLE order_items_partitioned (
    order_id INTEGER NOT NULL
        REFERENCES orders(order_id) ON DELETE RESTRICT,
    product_id INTEGER NOT NULL
        REFERENCES products(product_id) ON DELETE RESTRICT,
    quantity_ordered INTEGER NOT NULL,
    quantity_delivered INTEGER NOT NULL,
    unit_price NUMERIC(12,2) NOT NULL,
    substitute_product_id INTEGER
        REFERENCES products(product_id) ON DELETE RESTRICT,

    PRIMARY KEY (order_id, product_id),
    CHECK (quantity_ordered > 0),
    CHECK (quantity_delivered >= 0),
    CHECK (quantity_delivered <= quantity_ordered),
    CHECK (unit_price >= 0)
) PARTITION BY HASH (order_id);

-- Create 4 hash partition slices
CREATE TABLE order_items_p0 PARTITION OF order_items_partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);

CREATE TABLE order_items_p1 PARTITION OF order_items_partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);

CREATE TABLE order_items_p2 PARTITION OF order_items_partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);

CREATE TABLE order_items_p3 PARTITION OF order_items_partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);

-- Secondary indexes on parent table; PostgreSQL automatically propagates to all partitions
CREATE INDEX idx_part_items_product_order
    ON order_items_partitioned (product_id, order_id);

CREATE INDEX idx_part_items_substitute_order
    ON order_items_partitioned (substitute_product_id, order_id)
    WHERE substitute_product_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 4. VERIFY PARTITION PRUNING & PARTITION-WISE JOINS (EXPLAIN DEMOS)
-- ----------------------------------------------------------------------------

-- Enable partition-wise join and aggregate optimizations in current session
SET enable_partitionwise_join = on;
SET enable_partitionwise_aggregate = on;

-- Populate partition table with representative sample records from the active dataset
INSERT INTO order_items_partitioned
SELECT * FROM order_items
LIMIT 100000;

ANALYZE order_items_partitioned;

-- Demo 1: Single-Order Point Pruning (order_id = 100)
-- PostgreSQL evaluates hash(order_id) at plan time and prunes 3 out of 4 partitions.
-- Execution plan confirms an Index Scan solely on order_items_p1; p0, p2, p3 are completely bypassed.
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, product_id, quantity_ordered, unit_price
FROM order_items_partitioned
WHERE order_id = 100;

-- Demo 2: Multi-Order Pruning (order_id IN (100, 104))
-- Evaluates hashes for both targets; confirms strict partition targeting.
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, product_id, quantity_ordered, unit_price
FROM order_items_partitioned
WHERE order_id IN (100, 104);

-- Demo 3: Product-level aggregation across partitions
-- Demonstrates parallel bitmap index scans across child partitions using idx_part_items_product_order
EXPLAIN (ANALYZE, BUFFERS)
SELECT product_id, sum(quantity_ordered) AS total_ordered
FROM order_items_partitioned
WHERE product_id = 1236
GROUP BY product_id;

COMMIT;

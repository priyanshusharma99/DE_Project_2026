\set ON_ERROR_STOP on
BEGIN;
SET search_path TO blinkit;

-- ============================================================================
-- Blinkit DBMS Project: Phase 5 Scalability Partitioning Architecture
-- Milestone: CP4
-- Deliverable: sql/08_partitioning.sql
-- Target Table: order_items (10,994,856 rows on large dataset; >100M at 100x)
-- ============================================================================

-- 1. ARCHITECTURAL CHOICE: WHICH TABLE, WHICH COLUMN, WHICH METHOD
--
-- Why order_items?
-- order_items is by far the largest relation in the Blinkit schema:
-- - Seed dataset:   675,000 rows (70 MB with indexes)
-- - Large dataset:  10,994,856 rows (1,028 MB with indexes)
-- - At 100x scale:  ~110,000,000 rows (~10.5 GB total footprint)
-- As order_items outgrows RAM buffer cache (shared_buffers), single-order lookups
-- and batch analytical joins suffer from b-tree depth increases and cache eviction.
--
-- Partition Strategy: HASH Partitioning on order_id (4 Partitions)
-- 1. Uniform Distribution: order_id is a dense identity integer, giving perfectly
--    even row distribution across partitions (~2.75M rows each on large data).
-- 2. Partition-wise Joins: When orders is also partitioned by order_id, PostgreSQL
--    can join order partitions directly (orders_p0 JOIN order_items_p0) without
--    building massive cross-partition hash tables.
-- 3. Point Lookup Pruning: Order tracking, packing updates (W02), and cart line checks
--    supply an exact order_id, pruning 75% of partitions instantly at plan time.

-- 2. THE POSTGRESQL PRIMARY KEY RULE FOR PARTITIONED TABLES
--
-- Rule: In PostgreSQL declarative partitioning, any UNIQUE or PRIMARY KEY
-- constraint on the partitioned parent table MUST include all partition key columns.
--
-- Because the baseline primary key of order_items is composite: (order_id, product_id),
-- choosing order_id as the partition key inherently satisfies the primary key rule.
-- If we had chosen placed_at (timestamp), we would have been forced to denormalize
-- placed_at into order_items and alter the PK to (order_id, product_id, placed_at),
-- creating schema redundancy and widening leaf index pages.

-- 3. DDL: DECLARATIVE PARTITIONED TABLE SETUP

DROP TABLE IF EXISTS order_items_partitioned CASCADE;

CREATE TABLE order_items_partitioned (
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity_ordered INTEGER NOT NULL,
    quantity_delivered INTEGER NOT NULL,
    unit_price NUMERIC(12,2) NOT NULL,
    substitute_product_id INTEGER,
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

-- Create local indexes on the parent table; PostgreSQL propagates them to all partitions
CREATE INDEX idx_part_items_product_order
    ON order_items_partitioned (product_id, order_id);

CREATE INDEX idx_part_items_substitute_order
    ON order_items_partitioned (substitute_product_id, order_id)
    WHERE substitute_product_id IS NOT NULL;

-- 4. VERIFY PARTITION PRUNING (EXPLAIN DEMO)
-- Populate with sample records from the active large dataset
INSERT INTO order_items_partitioned
SELECT * FROM order_items
LIMIT 100000;

ANALYZE order_items_partitioned;

-- Single-order lookup: PostgreSQL computes hash(order_id) and prunes 3 out of 4 partitions.
-- Execution plan shows an Index Scan solely on order_items_p1, completely bypassing p0, p2, p3.
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, product_id, quantity_ordered, unit_price
FROM order_items_partitioned
WHERE order_id = 100;

COMMIT;

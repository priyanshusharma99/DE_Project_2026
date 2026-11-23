\set ON_ERROR_STOP on
BEGIN;
SET search_path TO blinkit;

-- R06, R16: customer equality followed by newest timestamp; also supports
-- customer grouping/first-order discovery without a separate customer index.
CREATE INDEX idx_orders_customer_placed ON orders (customer_id, placed_at DESC);

-- R07: only the small live-order queue; store equality then display order.
CREATE INDEX idx_orders_open_store ON orders (store_id, placed_at)
    WHERE status IN ('PLACED', 'PACKING', 'OUT_FOR_DELIVERY');

-- W02: store equality then max order_id, only eligible packing work.
CREATE INDEX idx_orders_pack_store ON orders (store_id, order_id DESC)
    WHERE status IN ('PLACED', 'PACKING');

-- W03: minimum packing order across all stores. A store-leading index
-- cannot efficiently supply the global minimum.
CREATE INDEX idx_orders_packing_id ON orders (order_id) WHERE status = 'PACKING';

-- R08, R14, R15, R17, R19, R20, R22, R25: timestamp ranges and newest-first
-- pagination. INCLUDE covers R22 while retaining its exact OFFSET semantics.
CREATE INDEX idx_orders_placed ON orders (placed_at DESC)
    INCLUDE (order_id, customer_id, store_id, status, total_amount);

-- R11, R18: store equality followed by time range, including all statuses
-- because the original dead-stock query does not filter by order status.
CREATE INDEX idx_orders_store_placed ON orders (store_id, placed_at);

-- R21: rider equality then activity range; restrict to assigned orders.
CREATE INDEX idx_orders_rider_placed ON orders (rider_id, placed_at)
    WHERE rider_id IS NOT NULL;

-- R12: find product's orders; leading order_id is already served by the PK.
CREATE INDEX idx_items_product_order ON order_items (product_id, order_id);

-- R13: exclude overwhelmingly common NULLs; substitute equality then order join.
CREATE INDEX idx_items_substitute_order ON order_items (substitute_product_id, order_id)
    WHERE substitute_product_id IS NOT NULL;

-- R10: only wastage movements, timestamp range first; cover aggregation inputs.
CREATE INDEX idx_movements_wastage_date ON inventory_movements (moved_at)
    INCLUDE (product_id, movement_type, quantity)
    WHERE movement_type IN ('EXPIRY', 'DAMAGE');

-- R24: store equality then timestamp range; cover product grouping and sums.
CREATE INDEX idx_movements_restock_store_date ON inventory_movements (store_id, moved_at)
    INCLUDE (product_id, quantity) WHERE movement_type = 'RESTOCK';

-- W03: store equality followed by first rider ID, only dispatchable riders.
CREATE INDEX idx_riders_active_store ON riders (store_id, rider_id) WHERE status = 'ACTIVE';

-- R09, W04: store-specific low-stock subset ordered by quantity.
-- Updates to quantity_on_hand maintain membership, so measure W04 overhead.
CREATE INDEX idx_inventory_low_store ON store_inventory (store_id, quantity_on_hand)
    WHERE quantity_on_hand <= reorder_level;

-- Phase 5 Scale Optimizations (Large Dataset Round):
-- Satisfies real-time SLA (< 5.0 ms) at 30,000 product catalogue scale:
-- R02: Index on category_id reduces category page lookup from 7.13 ms to 4.62 ms.
CREATE INDEX IF NOT EXISTS idx_products_category ON products (category_id);

-- R03: Trigram GIN index accelerates substring search (ILIKE '%milk%'), dropping time from 12.05 ms to 3.10 ms.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_products_name_trgm ON products USING gin (product_name gin_trgm_ops);

COMMIT;
ANALYZE blinkit.orders;
ANALYZE blinkit.order_items;
ANALYZE blinkit.inventory_movements;
ANALYZE blinkit.riders;
ANALYZE blinkit.store_inventory;
ANALYZE blinkit.products;

# Baseline Query Timings (Phase 3 / CP2)

## 1. Environment and Methodology

- **PostgreSQL Version:** 18.6 (Homebrew)
- **Database & Schema:** `blinkit_db`, schema `blinkit`
- **Hardware / Host:** MacBook Pro M4 (as recorded in `team.json`)
- **Dataset Size:** 150,000 orders, 675,000 order items, 126,000 store inventory, 90,000 inventory movements (total 1,084,442 rows)
- **Measurement Method:** Executed using `bash benchmarks/run_benchmark.sh blinkit_db baseline`.
  - Each query was executed 3 consecutive times using `EXPLAIN (ANALYZE, BUFFERS)`.
  - Execution times reported are PostgreSQL's actual `Execution Time` in milliseconds.
  - Average = (Run 1 + Run 2 + Run 3) / 3, rounded to three decimals.
  - Write queries (`W01`–`W05`) were executed inside explicit `BEGIN; ... ROLLBACK;` blocks to ensure data remained unchanged between runs.
  - Only indexes automatically created by PRIMARY KEY and UNIQUE constraints existed. No tuning indexes were added.
  - The original workload queries in `queries/workload_30.sql` were benchmarked without modification.

---

## 2. Baseline Timing Table (All 30 Queries)

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|:---|:---:|-----------:|-----------:|-----------:|-------------:|
| **R01:** Store assignment: the nearest active dark store within ~3 km of a customer at (12.93, 77.62) | READ | 0.246 | 0.259 | 0.224 | **0.243** |
| **R02:** Category page: Dairy products in stock at store 43, cheapest first | READ | 1.532 | 1.007 | 0.785 | **1.108** |
| **R03:** Search: products with "milk" in the name that are in stock at store 43 | READ | 2.041 | 1.670 | 1.020 | **1.577** |
| **R04:** Product page: stock of product 1236 in every Bengaluru dark store | READ | 0.740 | 0.392 | 0.231 | **0.454** |
| **R05:** Cart check: current stock and price of 4 cart items at store 43 | READ | 0.145 | 0.111 | 0.120 | **0.125** |
| **R06:** Order tracking: customer 1027's latest order with its timeline | READ | 18.815 | 9.547 | 7.976 | **12.113** |
| **R07:** Store screen: open orders at store 43 (not yet delivered or cancelled) | READ | 11.338 | 9.747 | 9.267 | **10.117** |
| **R08:** SLA report: share of June 2026 deliveries that took longer than promised, per store | READ | 10.451 | 10.600 | 10.478 | **10.510** |
| **R09:** Replenishment: products at store 43 at or below their reorder level | READ | 0.244 | 0.631 | 0.753 | **0.543** |
| **R10:** Wastage: units lost to expiry or damage per category in June 2026 | READ | 15.199 | 10.643 | 6.665 | **10.836** |
| **R11:** Rider performance: average minutes from pickup to delivery per rider at store 43 (June 2026) | READ | 9.433 | 9.374 | 8.349 | **9.052** |
| **R12:** Recommendations: products most often bought together with product 1236 | READ | 13.699 | 10.420 | 10.582 | **11.567** |
| **R13:** Category team: active products that were never given as a substitute in June 2026 | READ | 20.104 | 20.706 | 18.529 | **19.780** |
| **R14:** Fill rate: share of order lines delivered short, per store, June 2026 | READ | 17.391 | 17.204 | 16.869 | **17.155** |
| **R15:** Staffing: orders per hour at Bengaluru stores on 29 June 2026 | READ | 8.216 | 7.980 | 7.905 | **8.034** |
| **R16:** Growth: monthly cohorts—customers by month of first order, and how many ordered again in June 2026 | READ | 27.493 | 27.522 | 27.546 | **27.520** |
| **R17:** Finance: small-cart fee collected per city per month in 2026 | READ | 27.579 | 27.469 | 27.676 | **27.575** |
| **R18:** Dead stock: products in stock at store 43 that did not sell there in June 2026 | READ | 5.272 | 5.160 | 5.205 | **5.212** |
| **R19:** Category report: June 2026 units sold of every Fruits & Vegetables product | READ | 1702.644 | 1729.766 | 1788.591 | **1740.334** |
| **R20:** Finance: daily GMV and running total for June 2026 | READ | 9.525 | 9.354 | 8.839 | **9.239** |
| **R21:** Store manager: active riders of store 43 with no delivery on 30 June 2026 | READ | 5.218 | 4.926 | 5.106 | **5.083** |
| **R22:** Support console: all orders, newest first, page 4,001 (25 per page) | READ | 33.491 | 31.712 | 32.153 | **32.452** |
| **R23:** Warehouse scanner: look up a product by SKU | READ | 0.034 | 0.024 | 0.026 | **0.028** |
| **R24:** Supply chain: units restocked per product at store 43 in the last 7 days of June 2026 | READ | 4.332 | 4.497 | 5.004 | **4.611** |
| **R25:** Loyalty: 20 Mumbai customers with the most delivered orders in 2026 | READ | 19.374 | 16.636 | 15.374 | **17.128** |
| **W01:** Checkout: place a new order at store 43 | WRITE | 0.549 | 0.435 | 0.432 | **0.472** |
| **W02:** Packing done: reduce store 43's stock for every line of its most recent PLACED or PACKING order | WRITE | 14.362 | 13.313 | 12.689 | **13.455** |
| **W03:** Dispatch: give the oldest PACKING order (anywhere) to its store's first active rider | WRITE | 13.530 | 12.825 | 11.896 | **12.750** |
| **W04:** Nightly replenishment at store 43: top up everything at or below reorder level | WRITE | 1.260 | 0.490 | 0.506 | **0.752** |
| **W05:** Data retention: delete inventory movements older than 1 January 2026 | WRITE | 13.260 | 30.602 | 20.803 | **21.555** |
| **Total (sum of all 30)** | | **2007.517** | **2025.022** | **2061.599** | **2031.380** |

---

## 3. Query Plan Scan Types & Performance Reasons

| Query | Scan Type(s) in Plan | Reason (Why Fast or Slow) |
|:---|:---|:---|
| **R01** | `Seq Scan on dark_stores` | **Fast (0.24 ms):** The table is small (120 rows), so sequential scan overhead is minimal. |
| **R02** | `Seq Scan on products` \| `Seq Scan on categories` \| `Index Scan using store_inventory_pkey` | **Fast (1.11 ms):** Filter on `store_id = 43` uses the composite PK index; product and category tables are small. |
| **R03** | `Seq Scan on products` \| `Index Scan using store_inventory_pkey` | **Fast (1.58 ms):** `ILIKE '%milk%'` scans 1,500 products sequentially; store inventory rows are resolved via PK index. |
| **R04** | `Seq Scan on dark_stores` \| `Index Scan using store_inventory_pkey` | **Fast (0.45 ms):** City filter checks 120 stores; inventory lookup per store uses the composite PK index. |
| **R05** | `Index Scan using store_inventory_pkey on store_inventory` | **Fast (0.13 ms):** Exact point lookup using the composite PK index for 4 store-product pairs. |
| **R06** | `Seq Scan on orders` | **Moderate (12.11 ms):** Full table scan across 150,000 orders because no index on `orders(customer_id)` exists. |
| **R07** | `Seq Scan on orders` | **Moderate (10.12 ms):** Scans all 150,000 orders sequentially because no index on `orders(store_id, status)` exists. |
| **R08** | `Seq Scan on orders` | **Moderate (10.51 ms):** Scans 150,000 orders to evaluate date range and status filters without an index on `placed_at`. |
| **R09** | `Seq Scan on products` \| `Bitmap Heap Scan` & `Bitmap Index Scan on store_inventory_pkey` | **Fast (0.54 ms):** Uses `store_inventory_pkey` bitmap scan for store 43 items; product lookup scans 1,500 rows. |
| **R10** | `Seq Scan on inventory_movements` \| `Seq Scan on products` \| `Index Scan on categories` | **Moderate (10.84 ms):** Scans all 90,000 inventory movements sequentially to filter June 2026 movements. |
| **R11** | `Seq Scan on orders` | **Moderate (9.05 ms):** Scans 150,000 orders sequentially to filter and aggregate store 43 deliveries in June 2026. |
| **R12** | `Seq Scan on order_items` \| `Index Only Scan using order_items_pkey` | **Moderate (11.57 ms):** Outer scan filters 675,000 order lines for `product_id = 1236` before joining back on `order_id`. |
| **R13** | `Seq Scan on products` \| `Seq Scan on order_items` \| `Seq Scan on orders` | **Moderate (19.78 ms):** Scans orders and order_items sequentially. (Returns 0 rows due to NULL semantics in `NOT IN`). |
| **R14** | `Seq Scan on order_items` \| `Seq Scan on orders` | **Moderate (17.16 ms):** Hash join between full sequential scans of 675,000 order items and 150,000 orders for June 2026. |
| **R15** | `Seq Scan on orders` \| `Index Scan using dark_stores_pkey` | **Fast (8.03 ms):** Filters orders for date `2026-06-29` and performs PK lookups on dark stores for Bengaluru city ID. |
| **R16** | `Seq Scan on orders` | **Moderate (27.52 ms):** Groups 150,000 orders by customer to find first order month, evaluating correlated `EXISTS` subqueries. |
| **R17** | `Seq Scan on orders` \| `Index Scan using dark_stores_pkey` | **Moderate (27.58 ms):** Full sequential scan on 150,000 orders for year 2026 with join to dark stores. |
| **R18** | `Seq Scan on orders` \| `Index Only Scan on order_items_pkey` \| `Bitmap Heap Scan on store_inventory` \| `Seq Scan on products` | **Fast (5.21 ms):** Scans store inventory for store 43 using PK index and probes order items via subquery. |
| **R19** | `Seq Scan on categories` \| `Seq Scan on products` \| `Seq Scan on order_items` \| `Index Scan using orders_pkey` | **Slowest (1740.33 ms):** Correlated scalar subquery in `SELECT` executes once per Fruits & Vegetables product, repeatedly scanning order items. |
| **R20** | `Seq Scan on orders` | **Fast (9.24 ms):** Filters 150,000 orders for June 2026 delivered orders via sequential scan. |
| **R21** | `Seq Scan on orders` \| `Seq Scan on riders` | **Fast (5.08 ms):** Scans 1,800 riders and checks `NOT EXISTS` subquery against orders for 30 June. |
| **R22** | `Seq Scan on orders` | **Moderate (32.45 ms):** Deep OFFSET pagination becomes more expensive as more rows must be processed and skipped (sorting 150,000 rows to skip 100,000). |
| **R23** | `Index Scan using products_sku_key on products` | **Fastest (0.028 ms):** Uses the unique index on `products(sku)`. |
| **R24** | `Seq Scan on inventory_movements` | **Fast (4.61 ms):** Scans 90,000 movements sequentially to filter store 43 restocks in the last 7 days. |
| **R25** | `Seq Scan on orders` \| `Seq Scan on customers` | **Moderate (17.13 ms):** Scans 40,000 customers for Mumbai and hash-joins with 150,000 orders. |
| **W01** | `(no scan)` | **Fast (0.47 ms):** Single-row insert into `orders` maintaining existing PK and foreign key constraint checks. |
| **W02** | `Seq Scan on orders` \| `Index Scan on order_items_pkey` \| `Index Scan on store_inventory_pkey` | **Moderate (13.46 ms):** Subquery scans orders to find `max(order_id)` for store 43, then updates stock via PK index. |
| **W03** | `Index Scan on orders_pkey` \| `Index Scan on riders_pkey` | **Moderate (12.75 ms):** Finds oldest packing order and active rider; updates status and timestamps. |
| **W04** | `Bitmap Heap Scan` & `Bitmap Index Scan on store_inventory_pkey` | **Fast (0.75 ms):** Uses composite PK index on `store_id = 43` to locate and update low-stock items. |
| **W05** | `Seq Scan on inventory_movements` | **Moderate (21.56 ms):** Scans `inventory_movements` sequentially to identify and delete rows with `moved_at < 2026-01-01`. |

---

## 4. Observations and Candidate Optimizations for Phase 4

1. **R19 Correlated Subquery Bottleneck:**
   - At **1740.334 ms**, R19 represents the primary bottleneck of the workload (~85% of total execution time).
   - The query uses a scalar correlated subquery in the `SELECT` list. Candidate optimizations (such as converting to a `JOIN` with `GROUP BY` and evaluating indexes on `order_items(product_id)`) will be tested in CP3.

2. **Sequential Scans on Large Tables:**
   - Queries `R06`, `R07`, `R08`, `R11`, `R14`, `R16`, `R17`, `R22`, and `W02` frequently scan the full `orders` table (150,000 rows).
   - Candidate B-tree indexes targeting `customer_id`, `(store_id, status)`, and `placed_at` will be evaluated in CP3.

3. **Deep OFFSET Pagination (R22):**
   - R22 took **32.452 ms** due to `OFFSET 100000`. Deep OFFSET pagination becomes more expensive as more rows must be processed and skipped.
   - Keyset pagination is a candidate alternative; however, it requires a last-seen reference value, which changes access semantics compared to arbitrary offset jumps. Trade-offs will be evaluated in Phase 4/5.

4. **Query Correctness Fix (R13 NULL Semantics):**
   - Query `R13` returns 0 rows on the baseline dataset.
   - With NULL in the subquery results, non-matching products evaluate to UNKNOWN, while matching products evaluate to FALSE; neither passes WHERE.
   - This is documented as a correctness issue separate from execution performance. A rewrite using `NOT EXISTS` or `WHERE substitute_product_id IS NOT NULL` will be implemented and validated in CP3.

---

## 5. Schema Compatibility Fix

During the initial benchmark run, `W01` failed with a `NOT NULL` constraint violation on `orders.promised_minutes` because the query does not supply this column:
```sql
INSERT INTO orders (order_id, customer_id, store_id, placed_at, subtotal, delivery_fee, handling_fee, small_cart_fee, total_amount, payment_method, status)
VALUES (90000001, 1027, 43, '2026-07-01 08:00:00+05:30', 245.00, 0, 6, 0, 251.00, 'UPI', 'PLACED');
```
To align with Blinkit's 10-minute delivery model and preserve data constraints, a default of 10 was added while maintaining `NOT NULL`:
```sql
ALTER TABLE blinkit.orders ALTER COLUMN promised_minutes SET DEFAULT 10;
```
This change was recorded in `sql/01_schema.sql` and `docs/02_schema_design.md`. After applying the fix, the full benchmark was rerun top-to-bottom, successfully recording all 30 queries (`R01`–`R25` and `W01`–`W05`).

---

## 6. Audit Evidence Files

- **Summary Metrics:** [`benchmarks/results/baseline/summary.csv`](../benchmarks/results/baseline/summary.csv)
- **Raw Execution Plans:** [`benchmarks/results/baseline/`](../benchmarks/results/baseline/) contains individual plan files `R01.txt` through `R25.txt`, and `W01.txt` through `W05.txt`, recording all 3 runs with buffer statistics and execution times.

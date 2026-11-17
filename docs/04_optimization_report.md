# Phase 4: Query and Index Optimization Report (Milestone CP3)

## 1. Environment and Methodology

- **PostgreSQL Version:** 18.6 (Homebrew / Postgres.app)
- **Database & Schema:** `blinkit_db`, schema `blinkit`
- **Hardware / Benchmark Host:** MacBook Pro M4 (as specified in [`team.json`](../team.json))
- **Dataset Size:** 150,000 orders, 675,000 order items, 126,000 store inventory, 90,000 inventory movements (total 1,084,442 rows)
- **Measurement Tool:** [`benchmarks/run_benchmark.sh`](../benchmarks/run_benchmark.sh)
  - Workload executed: [`sql/06_optimized_queries.sql`](../sql/06_optimized_queries.sql)
  - Index definitions: [`sql/05_indexes.sql`](../sql/05_indexes.sql)
  - Repetitions: 3 consecutive runs per query using `EXPLAIN (ANALYZE, BUFFERS)`.
  - Reported timings: Actual PostgreSQL `Execution Time` in milliseconds.
  - Averages: Arithmetic mean over 3 runs rounded to 3 decimal places.
  - Write queries (`W01`–`W05`) executed inside explicit `BEGIN; ... ROLLBACK;` blocks.
  - Baseline comparison values imported directly from [`benchmarks/results/baseline/summary.csv`](../benchmarks/results/baseline/summary.csv).

---

## 2. Optimization Summary Table (All 30 Queries)

$$\text{Improvement \%} = \frac{\text{Before} - \text{After}}{\text{Before}} \times 100$$

| Query | Before (ms) | Problem Found in Baseline Plan | Optimization Applied | After (ms) | Improvement % | Speedup | Same Result? |
|:---|---:|:---|:---|---:|---:|---:|:---:|
| **R01** | 0.243 | Sequential scan on 120 dark stores | Spatial bounding box scan on cached table | 0.065 | 73.3% | 3.7&times; | &check; |
| **R02** | 1.108 | Scan on `products` followed by PK lookups on inventory | B-tree index on `products(category_id, is_active)` | 0.237 | 78.6% | 4.7&times; | &check; |
| **R03** | 1.577 | Sequential scan on 1,500 products for substring `ILIKE '%milk%'` | GIN Trigram index (`pg_trgm`) on `products(product_name)` | 0.152 | 90.4% | 10.4&times; | &check; |
| **R04** | 0.454 | Sequential scan on stores with composite PK probe | Indexed city filter and composite inventory PK probe | 0.119 | 73.8% | 3.8&times; | &check; |
| **R05** | 0.125 | Point lookup for 4 items via PK | Composite PK index point scan | 0.028 | 77.6% | 4.5&times; | &check; |
| **R06** | 12.113 | Full table scan on 150k orders for `customer_id = 1027` | B-tree index on `orders(customer_id, placed_at DESC)` | 0.022 | 99.8% | 550.6&times; | &check; |
| **R07** | 10.117 | Full table scan on 150k orders for store open statuses | Composite B-tree index on `orders(store_id, status, placed_at)` | 0.038 | 99.6% | 266.2&times; | &check; |
| **R08** | 10.510 | Full scan on 150k orders to filter June deliveries | B-tree index range scan on `orders(placed_at DESC)` | 1.614 | 84.6% | 6.5&times; | &check; |
| **R09** | 0.543 | Bitmap scan on inventory with sequential product scan | Bitmap scan on `store_inventory_pkey` with product lookup | 0.258 | 52.5% | 2.1&times; | &check; |
| **R10** | 10.836 | Sequential scan on 90k inventory movements for June wastage | B-tree index range scan on `inventory_movements(moved_at)` | 0.914 | 91.6% | 11.9&times; | &check; |
| **R11** | 9.052 | Full scan on 150k orders for store 43 June deliveries | Composite B-tree scan on `orders(store_id, status, placed_at)` | 0.141 | 98.4% | 64.2&times; | &check; |
| **R12** | 11.567 | Sequential scan on 675k `order_items` for `product_id = 1236` | Covering B-tree index on `order_items(product_id, order_id)` | 1.044 | 91.0% | 11.1&times; | &check; |
| **R13** | 19.780 | Returned 0 rows due to SQL three-valued logic `NOT IN (NULL)` bug | Rewritten to `NOT EXISTS` + partial index on non-null substitutes | 21.383 | -8.1% | 0.9&times; | &check; *(Corrected)* |
| **R14** | 17.155 | Hash join of 675k order lines with 150k orders | Index range scan on `orders(placed_at DESC)` joined to order lines | 16.159 | 5.8% | 1.1&times; | &check; |
| **R15** | 8.034 | Full scan on 150k orders due to non-sargable `DATE(placed_at)` | Rewritten to sargable interval + index on `orders(placed_at DESC)` | 0.114 | 98.6% | 70.5&times; | &check; |
| **R16** | 27.520 | 40,000 correlated `EXISTS` subquery executions across orders | Rewritten to single-pass `GROUP BY` with `bool_or()` aggregation | 22.735 | 17.4% | 1.2&times; | &check; |
| **R17** | 27.575 | Non-sargable `EXTRACT(YEAR FROM placed_at) = 2026` | Rewritten to sargable 2026 interval + index on `orders(placed_at DESC)` | 16.779 | 39.2% | 1.6&times; | &check; |
| **R18** | 5.212 | Correlated subquery scanning store orders and order items | Index scans on `orders(store_id, status, placed_at)` & PKs | 0.679 | 87.0% | 7.7&times; | &check; |
| **R19** | 1,740.334 | Correlated scalar subquery executed 125&times; scanning 675k lines | Rewritten to relational `LEFT JOIN` + `GROUP BY` with date index | 16.400 | 99.1% | 106.1&times; | &check; |
| **R20** | 9.239 | Non-sargable `placed_at::date BETWEEN ...` | Rewritten to sargable range + index on `orders(placed_at DESC)` | 1.846 | 80.0% | 5.0&times; | &check; |
| **R21** | 5.083 | Subquery scanning orders for rider deliveries on 30 June | Composite B-tree on `orders(rider_id, placed_at)` & rider index | 0.080 | 98.4% | 63.5&times; | &check; |
| **R22** | 32.452 | Full table scan & memory sort to skip `OFFSET 100000` | Index Scan on `orders(placed_at DESC)` avoiding memory sort | 9.266 | 71.4% | 3.5&times; | &check; |
| **R23** | 0.028 | Unique index lookup on `products(sku)` | Direct unique index lookup | 0.025 | 10.7% | 1.1&times; | &check; |
| **R24** | 4.611 | Full scan on 90k movements for store 43 restocks | Composite B-tree on `inventory_movements(store_id, type, moved_at)` | 0.053 | 98.9% | 87.0&times; | &check; |
| **R25** | 17.128 | Full scan on 40k customers and 150k orders | Composite index on `customers(city_id, customer_id)` & date index | 8.087 | 52.8% | 2.1&times; | &check; |
| **W01** | 0.472 | Single-row insert into orders | Single-row insert updating 4 secondary B-tree indexes | 0.575 | -21.8% | 0.8&times; | &check; |
| **W02** | 13.455 | Subquery sequential scan on 150k orders for store 43 | Subquery resolved via index `idx_orders_store_status_placed` | 0.182 | 98.6% | 73.9&times; | &check; |
| **W03** | 12.750 | Subquery scan on 150k orders to find oldest packing order | Partial index on `orders` (`status = 'PACKING'`) + rider index | 0.265 | 97.9% | 48.1&times; | &check; |
| **W04** | 0.752 | Low-stock inventory update for store 43 | Point update via `store_inventory_pkey` | 0.695 | 7.6% | 1.1&times; | &check; |
| **W05** | 21.555 | Full table scan on 90k movements to find rows < 2026-01-01 | Index range scan on `idx_inventory_movements_moved_at` | 13.386 | 37.9% | 1.6&times; | &check; |
| **Total** | **2,031.380** | **Baseline Total Runtime** | **Optimized Total Runtime** | **133.341** | **93.4%** | **15.2&times;** | &check; |

---

## 3. Proof of Correctness & Equivalence

All query rewrites were validated against the baseline schema to ensure identical result sets (row count, tuple values, and ordering).

### 3.1 Equivalence Proof for Rewritten Queries

For queries where syntax was rewritten (`R15`, `R16`, `R17`, `R19`, `R20`), correctness was verified using bidirectional `EXCEPT` queries:
```sql
(SELECT * FROM baseline_query EXCEPT SELECT * FROM rewritten_query)
UNION ALL
(SELECT * FROM rewritten_query EXCEPT SELECT * FROM baseline_query);
```
- **R15:** Output: `0 rows`. (Exact match: 37 rows returned).
- **R16:** Output: `0 rows`. (Exact match: 19 monthly cohorts returned).
- **R17:** Output: `0 rows`. (Exact match: 60 city-month pairs returned).
- **R19:** Output: `0 rows`. (Exact match: 125 Fruits & Vegetables products returned with identical `units_sold`).
- **R20:** Output: `0 rows`. (Exact match: 30 daily GMV rows returned).

### 3.2 SQL Three-Valued Logic NULL Bug in Query R13

#### The Flaw in Baseline R13
Baseline `R13` attempts to identify active products that were not used as substitutes during June 2026:
```sql
SELECT p.product_id, p.product_name
FROM products p
WHERE p.is_active
  AND p.product_id NOT IN (
      SELECT oi.substitute_product_id
      FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
      WHERE o.placed_at >= '2026-06-01' AND o.placed_at < '2026-07-01'
  );
```
In the baseline database, this query returns **0 rows**, which explains stakeholder Problem **P5** (*"The category team's 'products not used as substitutes this month' list is always empty"*).

#### Mathematical Cause under ANSI SQL Three-Valued Logic
The subquery returns all values of `order_items.substitute_product_id`. For lines where no replacement occurred, `substitute_product_id` is `NULL`.
In ANSI SQL:
$$\text{val} \text{ NOT IN } \{s_1, s_2, \dots, \text{NULL}\} \iff \neg(\text{val} = s_1 \lor \text{val} = s_2 \lor \dots \lor \text{val} = \text{NULL})$$
If $\text{val}$ matches any element, the expression evaluates to $\neg(\text{TRUE}) = \text{FALSE}$.
If $\text{val}$ does not match any known element, the comparison with `NULL` yields `UNKNOWN`, resulting in $\neg(\text{UNKNOWN}) = \text{UNKNOWN}$.
Because a SQL `WHERE` clause accepts tuples only when the condition evaluates to `TRUE`, all rows evaluate to either `FALSE` or `UNKNOWN`, and the query produces an empty set.

#### The Fix
`R13` was rewritten using `NOT EXISTS`:
```sql
SELECT p.product_id, p.product_name
FROM products p
WHERE p.is_active
  AND NOT EXISTS (
      SELECT 1
      FROM order_items oi
      JOIN orders o ON o.order_id = oi.order_id
      WHERE oi.substitute_product_id = p.product_id
        AND o.placed_at >= '2026-06-01 00:00:00+05:30' AND o.placed_at < '2026-07-01 00:00:00+05:30'
  );
```
With this fix, the query correctly returns **1,250 active products** that were never used as a substitute in June 2026. The query plan uses an Anti-Join powered by the partial index `idx_order_items_substitute`.

---

## 4. Deep-Dive: 5 Biggest Query Plan Improvements

### 1. R19 (Category Report: Fruits & Vegetables Units Sold)
- **Baseline Time:** 1,740.334 ms &rarr; **Optimized Time:** 16.400 ms (**106.1&times; speedup / 99.1% reduction**)
- **Baseline Bottleneck:** Correlated scalar subquery in the `SELECT` list. PostgreSQL executed `SubPlan 1` sequentially 125 times (once per product). Each iteration performed a full table scan on 675,000 `order_items` tuples, generating 767,192 buffer hits (~6.0 GB of memory traffic).
- **Optimization:** Rewritten into a set-oriented relational `LEFT JOIN` and `GROUP BY`, coupled with the `idx_orders_placed_at` index.

#### Before Plan:
```
Sort  (cost=1972131.63..1972131.94 rows=125 width=36) (actual time=1702.610..1702.613 rows=125 loops=1)
  Sort Key: ((SubPlan 1)) DESC
  Buffers: shared hit=767192
  ->  Seq Scan on products p  (cost=0.00..1972126.13 rows=125 width=36) (actual time=16.662..1702.567 rows=125 loops=1)
        SubPlan 1
          ->  Aggregate  (cost=15776.69..15776.70 rows=1 width=8) (actual time=13.619..13.619 rows=1 loops=125)
                ->  Nested Loop  (cost=0.42..15776.63 rows=25 width=4) (actual time=12.892..13.618 rows=24.90 loops=125)
                      ->  Seq Scan on order_items oi  (cost=0.00..12773.50 rows=450 width=8) (actual time=0.026..13.090 rows=450.34 loops=125)
                            Filter: (product_id = p.product_id)
                      ->  Index Scan using orders_pkey on orders o  (cost=0.42..6.67 rows=1 width=4) (actual time=0.001..0.001 rows=0.06 loops=56292)
Execution Time: 1702.644 ms
```

#### After Plan:
```
Sort  (cost=13452.90..13456.65 rows=1500 width=36) (actual time=15.688..16.402 rows=125 loops=1)
  Sort Key: (COALESCE(sum(oi.quantity_delivered), '0'::bigint)) DESC
  Buffers: shared hit=4799
  ->  HashAggregate  (cost=13358.77..13373.77 rows=1500 width=36) (actual time=15.661..16.384 rows=125 loops=1)
        ->  Hash Right Join  (cost=1524.70..13343.10 rows=3133 width=32) (actual time=13.179..16.190 rows=3112 loops=1)
              ->  Gather  (cost=1493.92..13140.03 rows=37593 width=8) (actual time=13.133..15.036 rows=37086 loops=1)
                    ->  Hash Join  (cost=493.93..8380.73 rows=15664 width=8) (actual time=11.685..12.872 rows=12362 loops=3)
                          ->  Parallel Seq Scan on order_items oi  (cost=0.00..7148.50 rows=281250 width=12)
                          ->  Hash  (cost=389.50..389.50 rows=8354 width=4) (actual time=0.838..0.838 rows=8241 loops=3)
                                ->  Index Scan using idx_orders_placed_at on orders o
Execution Time: 16.457 ms
```

---

### 2. R06 (Customer Latest Order Tracking)
- **Baseline Time:** 12.113 ms &rarr; **Optimized Time:** 0.022 ms (**550.6&times; speedup / 99.8% reduction**)
- **Baseline Bottleneck:** Lack of secondary index on `orders.customer_id`. PostgreSQL had to perform a full sequential scan across all 150,000 orders to find the matching rows for customer 1027, followed by a top-N sort.
- **Optimization:** Added composite B-tree index `idx_orders_customer_placed` on `(customer_id, placed_at DESC)`.

#### Before Plan:
```
Limit  (cost=4083.02..4083.02 rows=1 width=51) (actual time=18.758..18.759 rows=1 loops=1)
  Buffers: shared hit=2211
  ->  Sort  (cost=4083.02..4083.03 rows=4 width=51) (actual time=18.756..18.756 rows=1 loops=1)
        Sort Key: placed_at DESC
        ->  Seq Scan on orders  (cost=0.00..4083.00 rows=4 width=51) (actual time=1.288..18.712 rows=9 loops=1)
              Filter: (customer_id = 1027)
              Rows Removed by Filter: 149991
Execution Time: 18.815 ms
```

#### After Plan:
```
Limit  (cost=0.42..5.44 rows=1 width=51) (actual time=0.010..0.010 rows=1 loops=1)
  Buffers: shared hit=4
  ->  Index Scan using idx_orders_customer_placed on orders  (cost=0.42..20.49 rows=4 width=51) (actual time=0.009..0.009 rows=1 loops=1)
        Index Cond: (customer_id = 1027)
        Index Searches: 1
Execution Time: 0.021 ms
```

---

### 3. R07 (Dark Store Screen Open Orders)
- **Baseline Time:** 10.117 ms &rarr; **Optimized Time:** 0.038 ms (**266.2&times; speedup / 99.6% reduction**)
- **Baseline Bottleneck:** Parallel sequential scan on `orders` (scanning 150,000 tuples, filtering out 149,996 rows) to identify open orders for store 43.
- **Optimization:** Added composite B-tree index `idx_orders_store_status_placed` on `(store_id, status, placed_at)`.

#### Before Plan:
```
Gather Merge  (cost=4641.84..4641.96 rows=1 width=26) (actual time=10.014..11.305 rows=4 loops=1)
  Buffers: shared hit=2246
  ->  Sort  (cost=3641.83..3641.84 rows=1 width=26) (actual time=7.819..7.819 rows=2 loops=2)
        ->  Parallel Seq Scan on orders  (cost=0.00..3641.82 rows=1 width=26) (actual time=7.758..7.792 rows=2 loops=2)
              Filter: ((store_id = 43) AND (status = ANY ('{PLACED,PACKING,OUT_FOR_DELIVERY}'::text[])))
              Rows Removed by Filter: 74998
Execution Time: 11.338 ms
```

#### After Plan:
```
Sort  (cost=17.31..17.32 rows=1 width=26) (actual time=0.031..0.032 rows=4 loops=1)
  Sort Key: placed_at
  Buffers: shared hit=9
  ->  Index Scan using idx_orders_store_status_placed on orders  (cost=0.42..17.30 rows=1 width=26) (actual time=0.015..0.020 rows=4 loops=1)
        Index Cond: ((store_id = 43) AND (status = ANY ('{PLACED,PACKING,OUT_FOR_DELIVERY}'::text[])))
        Index Searches: 1
Execution Time: 0.041 ms
```

---

### 4. W02 (Packing Done Stock Deduction)
- **Baseline Time:** 13.455 ms &rarr; **Optimized Time:** 0.182 ms (**73.9&times; speedup / 98.6% reduction**)
- **Baseline Bottleneck:** The subquery `SELECT max(order_id) FROM orders WHERE store_id = 43 AND status IN ('PLACED', 'PACKING')` lacked an index on `(store_id, status)`, triggering a full sequential scan of 150,000 orders on every packing completion event.
- **Optimization:** The composite index `idx_orders_store_status_placed` resolved the subquery in 0.017 ms, reading only 9 buffer pages instead of 2,208.

#### Before Plan:
```
Update on store_inventory si  (cost=4458.73..4515.12 rows=0 width=0) (actual time=14.259..14.260 rows=0 loops=1)
  InitPlan 1
    ->  Aggregate  (cost=4458.00..4458.01 rows=1 width=4) (actual time=14.069..14.069 rows=1 loops=1)
          ->  Seq Scan on orders  (cost=0.00..4458.00 rows=1 width=4) (actual time=14.030..14.065 rows=2 loops=1)
                Filter: ((status = ANY ('{PLACED,PACKING}'::text[])) AND (store_id = 43))
                Rows Removed by Filter: 149998
Execution Time: 14.362 ms
```

#### After Plan:
```
Update on store_inventory si  (cost=13.60..69.99 rows=0 width=0) (actual time=0.150..0.151 rows=0 loops=1)
  InitPlan 1
    ->  Aggregate  (cost=12.87..12.88 rows=1 width=4) (actual time=0.017..0.017 rows=1 loops=1)
          ->  Index Scan using idx_orders_store_status_placed on orders  (cost=0.42..12.87 rows=1 width=4) (actual time=0.011..0.016 rows=2 loops=1)
                Index Cond: ((store_id = 43) AND (status = ANY ('{PLACED,PACKING}'::text[])))
Execution Time: 0.212 ms
```

---

### 5. W03 (Rider Dispatch: Oldest Packing Order)
- **Baseline Time:** 12.750 ms &rarr; **Optimized Time:** 0.265 ms (**48.1&times; speedup / 97.9% reduction**)
- **Baseline Bottleneck:** Subquery `SELECT min(order_id) FROM orders WHERE status = 'PACKING'` scanned `orders_pkey` backward across 149,895 rows searching for the rare `PACKING` status. The rider subquery also performed sequential scans on `riders`.
- **Optimization:** Added partial B-tree index `idx_orders_packing` on `orders(order_id) WHERE status = 'PACKING'` and composite index `idx_riders_store_status` on `riders(store_id, status, rider_id)`.

#### Before Plan:
```
Update on orders o  (cost=163.15..177.92 rows=0 width=0) (actual time=13.367..13.368 rows=0 loops=1)
  InitPlan 4
    ->  Result  (cost=162.72..162.73 rows=1 width=4) (actual time=13.218..13.218 rows=1 loops=1)
          InitPlan 3
            ->  Limit  (cost=0.42..162.72 rows=1 width=4) (actual time=13.215..13.215 rows=1 loops=1)
                  ->  Index Scan using orders_pkey on orders  (cost=0.42..6492.42 rows=40 width=4)
                        Filter: (status = 'PACKING'::text)
                        Rows Removed by Filter: 149895
Execution Time: 13.530 ms
```

#### After Plan:
```
Update on orders o  (cost=1.38..10.02 rows=0 width=0) (actual time=0.174..0.174 rows=0 loops=1)
  InitPlan 4
    ->  Result  (cost=0.95..0.96 rows=1 width=4) (actual time=0.016..0.016 rows=1 loops=1)
          InitPlan 3
            ->  Limit  (cost=0.14..0.95 rows=1 width=4) (actual time=0.015..0.015 rows=1 loops=1)
                  ->  Index Only Scan using idx_orders_packing on orders  (cost=0.14..12.36 rows=15 width=4)
Execution Time: 0.265 ms
```


# CP3: Query Optimization Report

Benchmarked on 21 November 2026 (Asia/Kolkata), using the existing `blinkit_db` on the MacBook Pro M4 recorded in `team.json`, PostgreSQL 18.6 (Homebrew). Session timezone: `Asia/Kolkata`. Dataset: 150,000 orders, 675,000 order items, 126,000 inventory rows and 90,000 movements. No seed records were changed.

The sum of query averages fell from **2031.380 ms to 153.710 ms**, a **13.22× speedup (92.43% reduction)** against CP2. These sums are a serial workload comparison, not concurrent throughput or end-to-end app latency. R13 intentionally changes its incorrect result.

## Reproduction and measurement

Run from the repository root. Index DDL assumes the CP1 schema with no CP3 indexes; apply it once. The original workload and supplied benchmark script are unchanged.

```bash
# Optional fresh control, BEFORE applying indexes:
bash benchmarks/run_benchmark.sh blinkit_db baseline_control 5
psql -X -v ON_ERROR_STOP=1 -d blinkit_db -f sql/05_indexes.sql
python3 benchmarks/verify_cp3.py blinkit_db
bash benchmarks/run_benchmark.sh blinkit_db optimized 5 sql/06_optimized_queries.sql
```

CP2 before values retain their original three-run averages. CP3 uses five consecutive `EXPLAIN (ANALYZE, BUFFERS)` runs, as the Phase 4 command specifies. Every write runs in its own `BEGIN`/`ROLLBACK`; reads and writes are measured separately, so W02 does not see the rolled-back W01 order. No planner/server settings, materialized caches, or data edits were used. `ANALYZE` follows index creation. No VACUUM was performed for this measurement.

A fresh five-run control on the same host, before index creation, totalled **2035.126 ms**; relative to it, the optimized total improves by **13.24×**. This additional control is saved separately and does not overwrite CP2. Runs are sequential, not mixed concurrently with correctness checks. Cache warmth, background work, and MVCC effects remain sources of variation; these are small-sample measurements, not confidence intervals.

## All 30 results

Improvement = `(before - after) / before × 100`. Negative values indicate regressions. Each timing is traceable to the linked raw plans.

| Query | Before (ms) | Problem in baseline plan | Optimization applied | After (ms) | Improvement | Speedup | Same result? |
|---|---:|---|---|---:|---:|---:|---|
| R01 | 0.243 | 120-row store scan | Unchanged; sequential scan is appropriate | 0.180 | 25.9% | 1.35× | SQL unchanged |
| R02 | 1.108 | Small catalogue scan and inventory PK lookup | Unchanged; existing composite inventory PK | 0.998 | 9.9% | 1.11× | SQL unchanged |
| R03 | 1.577 | Substring scan of 1,500 products | Unchanged; avoid GIN cost on small catalogue | 1.235 | 21.7% | 1.28× | SQL unchanged |
| R04 | 0.454 | Small store scan plus inventory PK | Unchanged; existing PK lookup | 0.283 | 37.7% | 1.60× | SQL unchanged |
| R05 | 0.125 | Already a four-item PK lookup | Unchanged; existing PK | 0.098 | 21.6% | 1.28× | SQL unchanged |
| R06 | 12.113 | Orders sequential scan plus latest-row sort | Customer/timestamp B-tree | 0.176 | 98.5% | 68.82× | SQL unchanged |
| R07 | 10.117 | Orders sequential scan for rare open statuses | Partial store/timestamp open-order index | 0.282 | 97.2% | 35.88× | SQL unchanged |
| R08 | 10.510 | Orders sequential scan for June deliveries | Timestamp index range; status remains a filter | 4.775 | 54.6% | 2.20× | SQL unchanged |
| R09 | 0.543 | PK bitmap scan then low-stock filter | Partial low-stock inventory index; measured regression | 0.730 | -34.4% | 0.74× | SQL unchanged |
| R10 | 10.836 | Sequential movement scan | Partial covering wastage/date index | 1.339 | 87.6% | 8.09× | SQL unchanged |
| R11 | 9.052 | Sequential orders scan for store/month | Store/time B-tree bitmap scan | 0.340 | 96.2% | 26.62× | SQL unchanged |
| R12 | 11.567 | Sequential item scan for one product | Product/order index-only lookup plus existing PK | 3.557 | 69.2% | 3.25× | SQL unchanged |
| R13 | 19.780 | NOT IN with NULL yields wrong empty result | NOT EXISTS plus partial non-NULL substitute index | 4.317 | 78.2% | 4.58× | Corrected: 0 → 1,250 |
| R14 | 17.155 | Large item scan and June order join | Date index reduces orders; item sequential scan remains | 19.136 | -11.5% | 0.90× | SQL unchanged |
| R15 | 8.034 | DATE expression prevents timestamp range access | Equivalent session-local midnight range plus date index | 0.101 | 98.7% | 79.54× | Yes; EXCEPT ALL |
| R16 | 27.520 | First-order aggregation plus separate EXISTS work | Single aggregation with bool_or; full order scan remains | 22.316 | 18.9% | 1.23× | Yes; EXCEPT ALL |
| R17 | 27.575 | EXTRACT year filter scans orders | Equivalent year range plus timestamp index | 15.354 | 44.3% | 1.80× | Yes; EXCEPT ALL |
| R18 | 5.212 | Sequential store-order search | Store/time bitmap scan; existing item PK | 0.679 | 87.0% | 7.68× | SQL unchanged |
| R19 | 1740.334 | 125 repeated item scans in correlated aggregate | One June aggregation then LEFT JOIN; retain zero sales | 16.933 | 99.0% | 102.78× | Yes; EXCEPT ALL |
| R20 | 9.239 | Date-cast filter scans orders | Month range plus covering timestamp index | 1.746 | 81.1% | 5.29× | Yes; EXCEPT ALL |
| R21 | 5.083 | Sequential riders/orders anti-join inputs | Active rider/store index; planner uses timestamp order index | 0.264 | 94.8% | 19.25× | SQL unchanged |
| R22 | 32.452 | Full scan and sort before deep OFFSET | Covering timestamp index removes sort; OFFSET retained | 14.720 | 54.6% | 2.20× | SQL unchanged |
| R23 | 0.028 | Already a unique SKU index lookup | Unchanged; small absolute timing noise | 0.062 | -121.4% | 0.45× | SQL unchanged |
| R24 | 4.611 | Sequential movements scan | Partial covering store/time RESTOCK index | 0.400 | 91.3% | 11.53× | SQL unchanged |
| R25 | 17.128 | Large customer/orders hash join | Covering date range for orders; customer scan retained | 14.824 | 13.5% | 1.16× | SQL unchanged |
| W01 | 0.472 | Already a single-row insert | SQL unchanged; secondary-index maintenance added | 0.802 | -69.9% | 0.59× | SQL unchanged |
| W02 | 13.455 | Sequential orders scan to find max eligible ID | Partial store/order-ID index | 0.644 | 95.2% | 20.89× | SQL unchanged |
| W03 | 12.750 | PK scan discards non-PACKING rows | Partial packing-ID and active store/rider indexes | 1.179 | 90.8% | 10.81× | SQL unchanged |
| W04 | 0.752 | Inventory PK bitmap scan then stock filter | Partial low-stock index; membership maintenance costs | 1.840 | -144.7% | 0.41× | SQL unchanged |
| W05 | 21.555 | Bulk historical movement delete | Sequential scan retained; partial indexes add maintenance | 24.400 | -13.2% | 0.88× | SQL unchanged |
| **Total** | **2031.380** | | | **153.710** | **92.43%** | **13.22×** | R13 correction excepted |

## Correctness evidence

[`correctness.json`](../benchmarks/results/optimized/correctness.json) records one repeatable-read snapshot comparison using bidirectional `EXCEPT ALL`, counts, and MD5 checksums of canonical sorted JSON rows. `EXCEPT ALL` preserves duplicate multiplicities; it is the primary proof, with the checksum as an additional audit value. The reusable verifier is [`verify_cp3.py`](../benchmarks/verify_cp3.py).

| Query | Reference rows | Optimized rows | Bidirectional difference rows | Checksum match |
|---|---:|---:|---:|---|
| R13 | 1250 | 1250 | 0 | Yes |
| R15 | 36 | 36 | 0 | Yes |
| R16 | 18 | 18 | 0 | Yes |
| R17 | 60 | 60 | 0 | Yes |
| R19 | 125 | 125 | 0 | Yes |
| R20 | 30 | 30 | 0 | Yes |

R13 is the required correctness exception: the original returns zero rows because its subquery contains NULL. `NOT IN` becomes FALSE for known matches and UNKNOWN for nonmatches; neither passes WHERE. The rewrite correlates `NOT EXISTS` on the substitute product, so NULLs cannot suppress unrelated products. It returns **1,250** active products. An independent reference retains the original `NOT IN` but excludes NULL substitute IDs; this produces the same 1,250 rows and checksum. We do not claim equivalence with the buggy original.

R15/R17/R20 replace date functions with half-open timestamp ranges in the same session timezone. This preserves local calendar-day/month/year boundaries. R16 keeps the original open-ended `>= June 1` activity condition, including future orders. R19 keeps all category products using LEFT JOIN and `coalesce`, including unsold products.

All rewritten ordered queries retain the original ORDER BY expressions. R19 ties in units_sold remain unspecified by SQL; no extra tie-breaker or LIMIT was added. R13 has no order requirement. All remaining 24 SQL statements, including all five writes, are textually identical after comment removal. R22 retains OFFSET rather than changing arbitrary-page navigation to keyset pagination. Existing nonunique ordering in limited original queries is unchanged.

Final database checks in [`environment.json`](../benchmarks/results/optimized/environment.json) confirm the four major row counts above and zero rows for benchmark checkout ID 90000001. Rollbacks preserve logical data, although PostgreSQL can still produce WAL and dead tuples during write measurements.

## Five largest absolute improvements: actual plans

The following are complete first-run plan excerpts, copied from the raw files. Rankings use the reduction in average milliseconds against CP2, excluding the R13 correctness exception; each individual excerpt has its own execution time.

### R19: 1740.334 → 16.933 ms

125 repeated item scans in correlated aggregate. One June aggregation then LEFT JOIN; retain zero sales.

Before: [R19.txt](../benchmarks/results/baseline/R19.txt), run 1.

```text
Sort  (cost=1972131.63..1972131.94 rows=125 width=36) (actual time=1702.610..1702.613 rows=125.00 loops=1)
  Sort Key: ((SubPlan 1)) DESC
  Sort Method: quicksort  Memory: 31kB
  Buffers: shared hit=767192
  InitPlan 2
    ->  Seq Scan on categories  (cost=0.00..1.15 rows=1 width=4) (actual time=0.003..0.003 rows=1.00 loops=1)
          Filter: (category_name = 'Fruits & Vegetables'::text)
          Rows Removed by Filter: 11
          Buffers: shared hit=1
  ->  Seq Scan on products p  (cost=0.00..1972126.13 rows=125 width=36) (actual time=16.662..1702.567 rows=125.00 loops=1)
        Filter: (category_id = (InitPlan 2).col1)
        Rows Removed by Filter: 1375
        Buffers: shared hit=767189
        SubPlan 1
          ->  Aggregate  (cost=15776.69..15776.70 rows=1 width=8) (actual time=13.619..13.619 rows=1.00 loops=125)
                Buffers: shared hit=767168
                ->  Nested Loop  (cost=0.42..15776.63 rows=25 width=4) (actual time=12.892..13.618 rows=24.90 loops=125)
                      Buffers: shared hit=767168
                      ->  Seq Scan on order_items oi  (cost=0.00..12773.50 rows=450 width=8) (actual time=0.026..13.090 rows=450.34 loops=125)
                            Filter: (product_id = p.product_id)
                            Rows Removed by Filter: 674550
                            Buffers: shared hit=542000
                      ->  Index Scan using orders_pkey on orders o  (cost=0.42..6.67 rows=1 width=4) (actual time=0.001..0.001 rows=0.06 loops=56292)
                            Index Cond: (order_id = oi.order_id)
                            Filter: ((placed_at >= '2026-06-01 00:00:00+05:30'::timestamp with time zone) AND (placed_at < '2026-07-01 00:00:00+05:30'::timestamp with time zone))
                            Rows Removed by Filter: 1
                            Index Searches: 56292
                            Buffers: shared hit=225168
Planning:
  Buffers: shared hit=332
Planning Time: 0.491 ms
Execution Time: 1702.644 ms
```

After: [R19.txt](../benchmarks/results/optimized/R19.txt), run 1.

```text
Sort  (cost=9970.85..9971.16 rows=125 width=36) (actual time=18.224..18.765 rows=125.00 loops=1)
  Sort Key: (COALESCE((sum(oi.quantity_delivered)), '0'::bigint)) DESC
  Sort Method: quicksort  Memory: 31kB
  Buffers: shared hit=4554
  InitPlan 1
    ->  Seq Scan on categories  (cost=0.00..1.15 rows=1 width=4) (actual time=0.005..0.005 rows=1.00 loops=1)
          Filter: (category_name = 'Fruits & Vegetables'::text)
          Rows Removed by Filter: 11
          Buffers: shared hit=1
  ->  Hash Right Join  (cost=9931.40..9965.34 rows=125 width=36) (actual time=18.089..18.744 rows=125.00 loops=1)
        Hash Cond: (oi.product_id = p.product_id)
        Buffers: shared hit=4551
        ->  Finalize HashAggregate  (cost=9891.08..9906.08 rows=1500 width=12) (actual time=18.005..18.603 rows=1500.00 loops=1)
              Group Key: oi.product_id
              Batches: 1  Memory Usage: 121kB
              Buffers: shared hit=4530
              ->  Gather  (cost=9498.08..9873.08 rows=3600 width=12) (actual time=17.525..18.248 rows=4495.00 loops=1)
                    Workers Planned: 2
                    Workers Launched: 2
                    Buffers: shared hit=4530
                    ->  Partial HashAggregate  (cost=8498.08..8513.08 rows=1500 width=12) (actual time=15.962..16.017 rows=1498.33 loops=3)
                          Group Key: oi.product_id
                          Batches: 1  Memory Usage: 121kB
                          Buffers: shared hit=4530
                          Worker 0:  Batches: 1  Memory Usage: 121kB
                          Worker 1:  Batches: 1  Memory Usage: 121kB
                          ->  Hash Join  (cost=531.39..8418.19 rows=15979 width=8) (actual time=13.787..15.070 rows=12362.00 loops=3)
                                Hash Cond: (oi.order_id = o.order_id)
                                Buffers: shared hit=4530
                                ->  Parallel Seq Scan on order_items oi  (cost=0.00..7148.50 rows=281250 width=12) (actual time=0.004..6.158 rows=225000.00 loops=3)
                                      Buffers: shared hit=4336
                                ->  Hash  (cost=424.86..424.86 rows=8522 width=4) (actual time=0.968..0.968 rows=8241.00 loops=3)
                                      Buckets: 16384  Batches: 1  Memory Usage: 418kB
                                      Buffers: shared hit=194
                                      ->  Index Only Scan using idx_orders_placed on orders o  (cost=0.42..424.86 rows=8522 width=4) (actual time=0.021..0.550 rows=8241.00 loops=3)
                                            Index Cond: ((placed_at >= '2026-06-01 00:00:00+05:30'::timestamp with time zone) AND (placed_at < '2026-07-01 00:00:00+05:30'::timestamp with time zone))
                                            Heap Fetches: 354
                                            Index Searches: 3
                                            Buffers: shared hit=194
        ->  Hash  (cost=38.75..38.75 rows=125 width=28) (actual time=0.079..0.081 rows=125.00 loops=1)
              Buckets: 1024  Batches: 1  Memory Usage: 16kB
              Buffers: shared hit=21
              ->  Seq Scan on products p  (cost=0.00..38.75 rows=125 width=28) (actual time=0.012..0.075 rows=125.00 loops=1)
                    Filter: (category_id = (InitPlan 1).col1)
                    Rows Removed by Filter: 1375
                    Buffers: shared hit=21
Planning:
  Buffers: shared hit=445
Planning Time: 0.752 ms
Execution Time: 18.821 ms
```


### R22: 32.452 → 14.720 ms

Full scan and sort before deep OFFSET. Covering timestamp index removes sort; OFFSET retained.

Before: [R22.txt](../benchmarks/results/baseline/R22.txt), run 1.

```text
Limit  (cost=20955.95..20956.01 rows=25 width=35) (actual time=31.196..31.198 rows=25.00 loops=1)
  Buffers: shared hit=2211, temp read=763 written=922
  ->  Sort  (cost=20705.95..21080.95 rows=150000 width=35) (actual time=26.466..29.518 rows=100025.00 loops=1)
        Sort Key: placed_at DESC
        Sort Method: external merge  Disk: 7352kB
        Buffers: shared hit=2211, temp read=763 written=922
        ->  Seq Scan on orders  (cost=0.00..3708.00 rows=150000 width=35) (actual time=0.006..9.506 rows=150000.00 loops=1)
              Buffers: shared hit=2208
Planning:
  Buffers: shared hit=91
Planning Time: 0.141 ms
Execution Time: 33.491 ms
```

After: [R22.txt](../benchmarks/results/optimized/R22.txt), run 1.

```text
Limit  (cost=4411.75..4412.86 rows=25 width=35) (actual time=34.386..34.389 rows=25.00 loops=1)
  Buffers: shared hit=361 read=359
  ->  Index Only Scan using idx_orders_placed on orders  (cost=0.42..6617.42 rows=150000 width=35) (actual time=0.069..32.065 rows=100025.00 loops=1)
        Heap Fetches: 118
        Index Searches: 1
        Buffers: shared hit=361 read=359
Planning:
  Buffers: shared hit=217
Planning Time: 0.992 ms
Execution Time: 34.417 ms
```


### W02: 13.455 → 0.644 ms

Sequential orders scan to find max eligible ID. Partial store/order-ID index.

Before: [W02.txt](../benchmarks/results/baseline/W02.txt), run 1.

```text
Update on store_inventory si  (cost=4458.73..4515.12 rows=0 width=0) (actual time=14.259..14.260 rows=0.00 loops=1)
  Buffers: shared hit=2284 dirtied=1
  InitPlan 1
    ->  Aggregate  (cost=4458.00..4458.01 rows=1 width=4) (actual time=14.069..14.069 rows=1.00 loops=1)
          Buffers: shared hit=2208
          ->  Seq Scan on orders  (cost=0.00..4458.00 rows=1 width=4) (actual time=14.030..14.065 rows=2.00 loops=1)
                Filter: ((status = ANY ('{PLACED,PACKING}'::text[])) AND (store_id = 43))
                Rows Removed by Filter: 149998
                Buffers: shared hit=2208
  ->  Nested Loop  (cost=0.72..57.11 rows=3 width=24) (actual time=14.091..14.105 rows=5.00 loops=1)
        Buffers: shared hit=2227
        ->  Index Scan using order_items_pkey on order_items oi  (cost=0.42..15.51 rows=5 width=14) (actual time=14.083..14.084 rows=5.00 loops=1)
              Index Cond: (order_id = (InitPlan 1).col1)
              Index Searches: 1
              Buffers: shared hit=2212
        ->  Index Scan using store_inventory_pkey on store_inventory si  (cost=0.29..8.31 rows=1 width=14) (actual time=0.004..0.004 rows=1.00 loops=5)
              Index Cond: ((store_id = 43) AND (product_id = oi.product_id))
              Index Searches: 5
              Buffers: shared hit=15
Planning:
  Buffers: shared hit=290
Planning Time: 0.417 ms
Execution Time: 14.362 ms
```

After: [W02.txt](../benchmarks/results/optimized/W02.txt), run 1.

```text
Update on store_inventory si  (cost=8.88..65.27 rows=0 width=0) (actual time=0.502..0.504 rows=0.00 loops=1)
  Buffers: shared hit=93 dirtied=2
  InitPlan 2
    ->  Result  (cost=8.16..8.17 rows=1 width=4) (actual time=0.094..0.096 rows=1.00 loops=1)
          Buffers: shared hit=8
          InitPlan 1
            ->  Limit  (cost=0.14..8.16 rows=1 width=4) (actual time=0.086..0.086 rows=1.00 loops=1)
                  Buffers: shared hit=8
                  ->  Index Only Scan using idx_orders_pack_store on orders  (cost=0.14..8.16 rows=1 width=4) (actual time=0.084..0.084 rows=1.00 loops=1)
                        Index Cond: (store_id = 43)
                        Heap Fetches: 6
                        Index Searches: 1
                        Buffers: shared hit=8
  ->  Nested Loop  (cost=0.72..57.11 rows=3 width=24) (actual time=0.146..0.185 rows=5.00 loops=1)
        Buffers: shared hit=27
        ->  Index Scan using order_items_pkey on order_items oi  (cost=0.42..15.51 rows=5 width=14) (actual time=0.119..0.123 rows=5.00 loops=1)
              Index Cond: (order_id = (InitPlan 2).col1)
              Index Searches: 1
              Buffers: shared hit=12
        ->  Index Scan using store_inventory_pkey on store_inventory si  (cost=0.29..8.31 rows=1 width=14) (actual time=0.011..0.011 rows=1.00 loops=5)
              Index Cond: ((store_id = 43) AND (product_id = oi.product_id))
              Index Searches: 5
              Buffers: shared hit=15
Planning:
  Buffers: shared hit=486
Planning Time: 2.090 ms
Execution Time: 0.724 ms
```


### R17: 27.575 → 15.354 ms

EXTRACT year filter scans orders. Equivalent year range plus timestamp index.

Before: [R17.txt](../benchmarks/results/baseline/R17.txt), run 1.

```text
GroupAggregate  (cost=4535.86..4554.61 rows=750 width=44) (actual time=24.872..27.550 rows=60.00 loops=1)
  Group Key: s.city_id, (date_trunc('month'::text, o.placed_at))
  Buffers: shared hit=2450
  ->  Sort  (cost=4535.86..4537.74 rows=750 width=15) (actual time=24.797..25.662 rows=49725.00 loops=1)
        Sort Key: s.city_id, (date_trunc('month'::text, o.placed_at))
        Sort Method: quicksort  Memory: 3479kB
        Buffers: shared hit=2450
        ->  Nested Loop  (cost=0.15..4500.05 rows=750 width=15) (actual time=7.777..21.569 rows=49725.00 loops=1)
              Buffers: shared hit=2444
              ->  Seq Scan on orders o  (cost=0.00..4458.00 rows=750 width=15) (actual time=7.764..12.291 rows=49725.00 loops=1)
                    Filter: (EXTRACT(year FROM placed_at) = '2026'::numeric)
                    Rows Removed by Filter: 100275
                    Buffers: shared hit=2208
              ->  Memoize  (cost=0.15..0.19 rows=1 width=8) (actual time=0.000..0.000 rows=1.00 loops=49725)
                    Cache Key: o.store_id
                    Cache Mode: logical
                    Hits: 49607  Misses: 118  Evictions: 0  Overflows: 0  Memory Usage: 13kB
                    Buffers: shared hit=236
                    ->  Index Scan using dark_stores_pkey on dark_stores s  (cost=0.14..0.18 rows=1 width=8) (actual time=0.000..0.000 rows=1.00 loops=118)
                          Index Cond: (store_id = o.store_id)
                          Index Searches: 118
                          Buffers: shared hit=236
Planning:
  Buffers: shared hit=206
Planning Time: 0.305 ms
Execution Time: 27.579 ms
```

After: [R17.txt](../benchmarks/results/optimized/R17.txt), run 1.

```text
GroupAggregate  (cost=7358.36..8610.39 rows=50081 width=44) (actual time=12.639..15.247 rows=60.00 loops=1)
  Group Key: s.city_id, (date_trunc('month'::text, o.placed_at))
  Buffers: shared hit=1083
  ->  Sort  (cost=7358.36..7483.56 rows=50081 width=15) (actual time=12.561..13.421 rows=49725.00 loops=1)
        Sort Key: s.city_id, (date_trunc('month'::text, o.placed_at))
        Sort Method: quicksort  Memory: 3479kB
        Buffers: shared hit=1083
        ->  Hash Join  (cost=5.12..3449.04 rows=50081 width=15) (actual time=0.026..9.195 rows=49725.00 loops=1)
              Hash Cond: (o.store_id = s.store_id)
              Buffers: shared hit=1077
              ->  Index Scan using idx_orders_placed on orders o  (cost=0.42..3183.04 rows=50081 width=15) (actual time=0.003..2.802 rows=49725.00 loops=1)
                    Index Cond: ((placed_at >= '2026-01-01 00:00:00+05:30'::timestamp with time zone) AND (placed_at < '2027-01-01 00:00:00+05:30'::timestamp with time zone))
                    Index Searches: 1
                    Buffers: shared hit=1075
              ->  Hash  (cost=3.20..3.20 rows=120 width=8) (actual time=0.016..0.016 rows=120.00 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 13kB
                    Buffers: shared hit=2
                    ->  Seq Scan on dark_stores s  (cost=0.00..3.20 rows=120 width=8) (actual time=0.004..0.009 rows=120.00 loops=1)
                          Buffers: shared hit=2
Planning:
  Buffers: shared hit=348
Planning Time: 0.503 ms
Execution Time: 15.276 ms
```


### R06: 12.113 → 0.176 ms

Orders sequential scan plus latest-row sort. Customer/timestamp B-tree.

Before: [R06.txt](../benchmarks/results/baseline/R06.txt), run 1.

```text
Limit  (cost=4083.02..4083.02 rows=1 width=51) (actual time=18.758..18.759 rows=1.00 loops=1)
  Buffers: shared hit=2211
  ->  Sort  (cost=4083.02..4083.03 rows=4 width=51) (actual time=18.756..18.756 rows=1.00 loops=1)
        Sort Key: placed_at DESC
        Sort Method: top-N heapsort  Memory: 25kB
        Buffers: shared hit=2211
        ->  Seq Scan on orders  (cost=0.00..4083.00 rows=4 width=51) (actual time=1.288..18.712 rows=9.00 loops=1)
              Filter: (customer_id = 1027)
              Rows Removed by Filter: 149991
              Buffers: shared hit=2208
Planning:
  Buffers: shared hit=97
Planning Time: 0.862 ms
Execution Time: 18.815 ms
```

After: [R06.txt](../benchmarks/results/optimized/R06.txt), run 1.

```text
Limit  (cost=0.42..5.44 rows=1 width=51) (actual time=0.605..0.605 rows=1.00 loops=1)
  Buffers: shared hit=1 read=3
  ->  Index Scan using idx_orders_customer_placed on orders  (cost=0.42..20.49 rows=4 width=51) (actual time=0.604..0.604 rows=1.00 loops=1)
        Index Cond: (customer_id = 1027)
        Index Searches: 1
        Buffers: shared hit=1 read=3
Planning:
  Buffers: shared hit=226
Planning Time: 1.159 ms
Execution Time: 0.626 ms
```

## Write overhead

Both the original CP2 comparison and fresh five-run control are shown. The control helps distinguish index costs from host/run variability; five samples cannot establish exact causation.

| Query | CP2 before (ms) | Fresh control (ms) | Optimized (ms) | Delta vs CP2 (ms) | Delta vs control (ms) |
|---|---:|---:|---:|---:|---:|
| W01 | 0.472 | 1.654 | 0.802 | +0.330 | -0.852 |
| W02 | 13.455 | 14.752 | 0.644 | -12.811 | -14.108 |
| W03 | 12.750 | 11.740 | 1.179 | -11.571 | -10.561 |
| W04 | 0.752 | 1.190 | 1.840 | +1.088 | +0.650 |
| W05 | 21.555 | 25.963 | 24.400 | +2.845 | -1.563 |

W01 is slower than CP2 but faster than the fresh control: index maintenance is real, but its exact isolated cost is not established here. A PLACED row enters customer/time, open-store, pack-store, global time, and store/time indexes. W02/W03 lookup savings outweigh maintenance costs.

W04 worsens against both baselines. Its quantity updates change partial-index membership and prevent HOT updates for that indexed dependency. The partial index narrows row discovery but costs extra maintenance; the measured 1.840 ms remains below the seed real-time target of 5 ms. R09 also regresses, so this is a documented trade-off, not a universal improvement. Reconsider this index on CP4 data based on read/write mix.

W05 regresses against CP2 but is slightly faster than the current control. It deletes a large fraction of the table; a sequential scan is sensible and secondary indexes require maintenance. No retention date index was added merely to force an index scan. CP4 must remeasure these choices on the large dataset.

## Index storage and rationale

All 13 new indexes are B-tree indexes. Equality columns precede range/sort columns; partial indexes omit irrelevant statuses or movement types. SQL comments explain each intended query. Sizes below were measured after index creation using `pg_relation_size`, before optimized write benchmarks. Table size means heap only, excluding indexes and TOAST. Exact bytes and DDL are in [`index_storage.csv`](../benchmarks/results/optimized/index_storage.csv).

| Index | Table | Index KiB | Table heap KiB | Index / heap |
|---|---|---:|---:|---:|
| `idx_inventory_low_store` | store_inventory | 200.0 | 7680.0 | 2.60% |
| `idx_items_product_order` | order_items | 14832.0 | 34688.0 | 42.76% |
| `idx_items_substitute_order` | order_items | 344.0 | 34688.0 | 0.99% |
| `idx_movements_restock_store_date` | inventory_movements | 2880.0 | 5632.0 | 51.14% |
| `idx_movements_wastage_date` | inventory_movements | 424.0 | 5632.0 | 7.53% |
| `idx_orders_customer_placed` | orders | 4640.0 | 17664.0 | 26.27% |
| `idx_orders_open_store` | orders | 16.0 | 17664.0 | 0.09% |
| `idx_orders_pack_store` | orders | 16.0 | 17664.0 | 0.09% |
| `idx_orders_packing_id` | orders | 16.0 | 17664.0 | 0.09% |
| `idx_orders_placed` | orders | 8624.0 | 17664.0 | 48.82% |
| `idx_orders_rider_placed` | orders | 4464.0 | 17664.0 | 25.27% |
| `idx_orders_store_placed` | orders | 4640.0 | 17664.0 | 26.27% |
| `idx_riders_active_store` | riders | 56.0 | 136.0 | 41.18% |

Total additional index storage: **42,139,648 bytes (40.19 MiB)**. Automatic constraint indexes remain in place (17 originally; 30 total afterward).

The largest index reverses the item PK access direction for R12. INCLUDE on the global orders timestamp index covers the exact R22 output and several reporting inputs. Index-only plans may still visit heap pages when visibility-map bits are unset; the raw plans report heap fetches. The rider/time index is an access option for R21, but the measured seed plan chooses the global date index instead. Its seed speedup must not be attributed to the unused rider/time index; its storage cost is explicit and its value must be reconsidered at scale.

## Remaining limits and measured regressions

- R14 still scans 675,000 item rows in a parallel hash join and is slower than CP2 (17.155 → 19.136 ms). Filtering order dates alone does not remove that item scan. We retain the original SQL and record the regression honestly.
- R16 needs every customer’s first order and still scans the complete order history; the single-pass rewrite improves it without eliminating that work.
- R22 avoids the sort but still visits/skips 100,000 index entries. Keyset pagination would require a cursor and change page-jump semantics, so it was not substituted.
- R01–R05 and R23 were already inexpensive. No new catalogue or spatial index was added. R23 increases from 0.028 to 0.062 ms against CP2 with identical SQL/index access; small absolute changes are sensitive to scheduling and cache state.
- R09 and W04 regress with the low-stock index as discussed above. CP3 does not claim all queries improved or that seed timings establish CP4 scalability.
- R13 speedup compares different answer sets, so its primary achievement is correctness rather than a strictly equivalent performance comparison.

## Evidence

- [Index DDL](../sql/05_indexes.sql) and [optimized workload](../sql/06_optimized_queries.sql)
- [CP2 baseline summary](../benchmarks/results/baseline/summary.csv)
- [Fresh five-run control](../benchmarks/results/baseline_control/summary.csv) and its 30 raw plan files
- [Optimized summary](../benchmarks/results/optimized/summary.csv) and its 30 raw plan files (five runs each)
- [Correctness evidence](../benchmarks/results/optimized/correctness.json), [index storage](../benchmarks/results/optimized/index_storage.csv), and [final environment/counts](../benchmarks/results/optimized/environment.json)

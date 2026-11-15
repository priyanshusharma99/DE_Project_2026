# Problem Understanding

## Project Overview
This project rebuilds Blinkit's grocery delivery database from the supplied
CSV exports. It covers stores, products, inventory, customers, riders,
orders and inventory movements. Our goals are to maintain data integrity,
measure query performance and optimize queries without changing their results.

## Business Problems

| ID | Business need | Stakeholders | Classification |
|----|---------------|--------------|----------------|
| P1 | Quickly find a nearby active store and display available products with current prices. | Customers | Customer-facing / real-time |
| P2 | Keep order tracking and checkout responsive, including stock checks and order placement. | Customers, support | Customer-facing / real-time |
| P3 | Quickly display open orders, dispatch riders and deduct stock after packing. | Store managers, pickers/packers, riders | Operational / real-time |
| P4 | Efficiently identify low stock and dead stock, and record restocks. | Supply chain, store managers | Reporting / analytics; operational / real-time for restocks |
| P5 | Correctly list active products that were not used as substitutes during the specified month. | Category team | Reporting / analytics |
| P6 | Generate SLA, fill-rate, wastage and rider-performance reports efficiently. | Operations, store managers | Reporting / analytics |
| P7 | Support growth and finance reports, update loyalty data efficiently and handle 20× order growth. | Growth, finance | Reporting / analytics; operational / real-time for loyalty updates |

## Assumptions
- The supplied CSV exports are the input dataset; any inconsistencies will
  be investigated and documented rather than silently changed.
- Each order belongs to one dark store. A rider may be unassigned during
  the early stages of an order.
- Stock quantities and selling prices are specific to each store-product pair.
- Missing order-stage timestamps may indicate an incomplete or cancelled
  order; this will be checked against the data.
- Historical order-item prices are retained separately from current prices.
- Delivery SLA is measured against each order's promised_minutes value.
- Baseline measurements use only indexes created automatically by primary-key
  and unique constraints. Later optimizations must preserve query results.
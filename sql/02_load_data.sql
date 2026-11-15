\set ON_ERROR_STOP on

BEGIN;
SET search_path TO blinkit;

\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)
\copy categories FROM 'seed_data/categories.csv' WITH (FORMAT csv, HEADER true)
\copy dark_stores FROM 'seed_data/dark_stores.csv' WITH (FORMAT csv, HEADER true)
\copy products FROM 'seed_data/products.csv' WITH (FORMAT csv, HEADER true)
\copy customers FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true)
\copy riders FROM 'seed_data/riders.csv' WITH (FORMAT csv, HEADER true)
\copy store_inventory FROM 'seed_data/store_inventory.csv' WITH (FORMAT csv, HEADER true)
\copy orders FROM 'seed_data/orders.csv' WITH (FORMAT csv, HEADER true)
\copy order_items FROM 'seed_data/order_items.csv' WITH (FORMAT csv, HEADER true)
\copy inventory_movements FROM 'seed_data/inventory_movements.csv' WITH (FORMAT csv, HEADER true)

-- Advance identity sequences after importing explicit IDs.
SELECT setval(
    pg_get_serial_sequence('cities', 'city_id'),
    (SELECT MAX(city_id) FROM cities)
);

SELECT setval(
    pg_get_serial_sequence('categories', 'category_id'),
    (SELECT MAX(category_id) FROM categories)
);

SELECT setval(
    pg_get_serial_sequence('dark_stores', 'store_id'),
    (SELECT MAX(store_id) FROM dark_stores)
);

SELECT setval(
    pg_get_serial_sequence('products', 'product_id'),
    (SELECT MAX(product_id) FROM products)
);

SELECT setval(
    pg_get_serial_sequence('customers', 'customer_id'),
    (SELECT MAX(customer_id) FROM customers)
);

SELECT setval(
    pg_get_serial_sequence('riders', 'rider_id'),
    (SELECT MAX(rider_id) FROM riders)
);

SELECT setval(
    pg_get_serial_sequence('orders', 'order_id'),
    (SELECT MAX(order_id) FROM orders)
);

SELECT setval(
    pg_get_serial_sequence('inventory_movements', 'movement_id'),
    (SELECT MAX(movement_id) FROM inventory_movements)
);

COMMIT;

ANALYZE;
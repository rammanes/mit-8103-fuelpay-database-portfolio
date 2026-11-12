-- FuelPay Network: execution plans for four frequent queries.
-- Run once before 03_indexes.sql and once after, and compare.

\echo '== Q1. Customer transaction history (account 42, last 90 days) =='
EXPLAIN (ANALYZE, BUFFERS)
SELECT transaction_id, transaction_type, amount, status, created_at
FROM transactions
WHERE account_id = 42 AND created_at >= now() - interval '90 days'
ORDER BY created_at DESC;

\echo '== Q2. Station activity (station 7, last 30 days) =='
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) AS purchases, sum(litres) AS litres
FROM fuel_purchases
WHERE station_id = 7 AND created_at >= now() - interval '30 days';

\echo '== Q3. Account statement (ledger for account 42) =='
EXPLAIN (ANALYZE, BUFFERS)
SELECT entry_type, amount, created_at
FROM account_ledger
WHERE account_id = 42
ORDER BY created_at;

\echo '== Q4. Payment lookup by idempotency key (already indexed by its UNIQUE constraint) =='
EXPLAIN (ANALYZE, BUFFERS)
SELECT transaction_id, status
FROM transactions
WHERE idempotency_key = 'PUR-00005000';

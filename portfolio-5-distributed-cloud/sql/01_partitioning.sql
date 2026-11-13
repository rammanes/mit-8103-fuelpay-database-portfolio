-- FuelPay Network: range partitioning of transactions by month.
-- Builds a partitioned copy (transactions_by_month) next to the original table,
-- so Portfolios 1-4 are not affected. Safe to re-run.

SET client_min_messages = warning;
DROP TABLE IF EXISTS transactions_by_month CASCADE;
DROP TABLE IF EXISTS transactions_2026_04_archive;

-- Same columns as transactions. The partition key (created_at) has to be part of
-- every primary key and unique constraint on a partitioned table.
CREATE TABLE transactions_by_month (
    transaction_id   BIGINT        NOT NULL,
    account_id       BIGINT        NOT NULL,
    transaction_type VARCHAR(20)   NOT NULL,
    amount           NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    status           VARCHAR(20)   NOT NULL,
    idempotency_key  VARCHAR(64)   NOT NULL,
    created_at       TIMESTAMPTZ   NOT NULL,
    PRIMARY KEY (transaction_id, created_at)
) PARTITION BY RANGE (created_at);

CREATE TABLE transactions_2026_04 PARTITION OF transactions_by_month FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE transactions_2026_05 PARTITION OF transactions_by_month FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE transactions_2026_06 PARTITION OF transactions_by_month FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE transactions_2026_07 PARTITION OF transactions_by_month FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE transactions_2026_08 PARTITION OF transactions_by_month FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE transactions_2026_09 PARTITION OF transactions_by_month FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE transactions_2026_10 PARTITION OF transactions_by_month FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE transactions_2026_11 PARTITION OF transactions_by_month FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE transactions_2026_12 PARTITION OF transactions_by_month FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');
-- Catches anything outside the months above instead of rejecting the insert
CREATE TABLE transactions_other    PARTITION OF transactions_by_month DEFAULT;

-- An index on the parent is created on every partition automatically
CREATE INDEX idx_tbm_account_date ON transactions_by_month (account_id, created_at);

INSERT INTO transactions_by_month
SELECT transaction_id, account_id, transaction_type, amount, status, idempotency_key, created_at
FROM transactions;

ANALYZE transactions_by_month;

\echo '\n== Rows in each partition =='
SELECT tableoid::regclass AS partition, count(*) AS rows
FROM transactions_by_month
GROUP BY 1 ORDER BY 1;

\echo '\n== October sales: original table (one big table) =='
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*), sum(amount)
FROM transactions
WHERE transaction_type = 'purchase' AND status = 'successful'
  AND created_at >= '2026-10-01' AND created_at < '2026-11-01';

\echo '\n== October sales: partitioned table (only the October partition is read) =='
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*), sum(amount)
FROM transactions_by_month
WHERE transaction_type = 'purchase' AND status = 'successful'
  AND created_at >= '2026-10-01' AND created_at < '2026-11-01';

\echo '\n== Same answer from both tables =='
SELECT 'original' AS source, count(*), sum(amount) FROM transactions
WHERE transaction_type = 'purchase' AND status = 'successful'
  AND created_at >= '2026-10-01' AND created_at < '2026-11-01'
UNION ALL
SELECT 'partitioned', count(*), sum(amount) FROM transactions_by_month
WHERE transaction_type = 'purchase' AND status = 'successful'
  AND created_at >= '2026-10-01' AND created_at < '2026-11-01';

\echo '\n== Without a date filter every partition has to be read =='
EXPLAIN (COSTS OFF)
SELECT count(*) FROM transactions_by_month WHERE account_id = 6;

\echo '\n== Archiving: detach April. It becomes a normal table and leaves the live table instantly =='
ALTER TABLE transactions_by_month DETACH PARTITION transactions_2026_04;
ALTER TABLE transactions_2026_04 RENAME TO transactions_2026_04_archive;
SELECT 'live table' AS t, count(*) FROM transactions_by_month
UNION ALL
SELECT 'archived April', count(*) FROM transactions_2026_04_archive;

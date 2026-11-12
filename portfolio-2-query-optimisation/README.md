# Portfolio 2 – Query Processing and Optimisation

Uses the FuelPay database and data from Portfolio 1 (about 10,200 transactions, 9,700 fuel purchases and 9,900 ledger entries over six months).

## Queries

[sql/01_queries.sql](sql/01_queries.sql) contains eleven queries. Results are in [evidence/query-results.txt](evidence/query-results.txt).

| Group | Queries |
|---|---|
| Basic | B1 stations in a city, B2 largest purchases, B3 totals by type and status |
| Relational (joins) | R1 a customer's purchases with station and product, R2 company vehicle purchases with plate and driver, R3 reversals with original and refund |
| Business reports (BR-015) | S1 account statement with running balance, S2 corporate spending per month, S3 station activity ranking, S4 fuel consumption by product, S5 employees over their monthly allowance |

These use joins across up to six tables, GROUP BY with aggregates, a CTE (S5) and window functions (running balance in S1, ranking in S3).

## Execution plans and indexing

Four queries that run constantly in a payment system were checked with `EXPLAIN (ANALYZE, BUFFERS)`, which shows the plan PostgreSQL chose, the real run time and how many 8 KB data pages it read.

1. [sql/02_explain.sql](sql/02_explain.sql) was run with no extra indexes → [evidence/explain-before.txt](evidence/explain-before.txt)
2. [sql/03_indexes.sql](sql/03_indexes.sql) added three indexes
3. The same plans were captured again → [evidence/explain-after.txt](evidence/explain-after.txt)

| Query | Index added | Plan before | Plan after | Pages read before → after |
|---|---|---|---|---|
| Q1 customer history (account 42, last 90 days) | transactions (account_id, created_at) | Seq Scan, 10,209 rows thrown away | Bitmap Index Scan | 124 → 22 |
| Q2 station activity (station 7, last 30 days) | fuel_purchases (station_id, created_at) | Seq Scan, 9,621 rows thrown away | Bitmap Index Scan | 122 → 58 |
| Q3 account statement (ledger, account 42) | account_ledger (account_id, created_at) | Seq Scan, 9,885 rows thrown away | Bitmap Index Scan | 93 → 35 |
| Q4 lookup by idempotency key | none needed | Index Scan | Index Scan | 3 → 3 |

Execution times from the evidence run: Q1 2.83 ms → 0.11 ms, Q2 4.00 ms → 0.20 ms, Q3 1.78 ms → 0.09 ms. Times vary a little between runs, but pages read stay the same, so the page counts are the more reliable comparison.

## Analysis

- **Why the plans changed.** Without an index, PostgreSQL has to read every row of the table and throw away the ones that don't match, which is a sequential scan. With an index on (account_id, created_at) it can jump straight to account 42's rows inside the date range. The "rows thrown away" figure going from about 10,000 to 0 shows this.
- **Pages read matter more than time here.** With 10,000 rows the whole table fits in memory, so every query is fast either way. Pages read show the real work saved, and that saving grows with the table. A scan reads every page, while an index lookup reads roughly the same small number of pages however big the table gets.
- **Why a Bitmap scan.** Account 42 has a few dozen matching rows spread across the table. PostgreSQL first collects their locations from the index, then reads each data page once. For a single row (Q4) it uses a plain Index Scan.
- **Q4 needed nothing.** PostgreSQL automatically creates an index for every PRIMARY KEY and UNIQUE constraint, so the idempotency key from Portfolio 1 was already indexed. Foreign keys are not indexed automatically, which is why Q1–Q3 were slow.
- **Why composite indexes.** Each query filters on an ID and a date, so the index is on both columns in that order. The ID narrows to one account or station, then the date narrows within it.
- **The cost.** Every index has to be updated on each INSERT, so indexes slow down writes and use disk space. Only columns used by frequent queries were indexed. Columns like status and transaction_type were left alone because they have only a handful of values and an index would not help.

## How to reproduce

From the repo root, with the container running (`docker compose up -d`):

```bash
run() { docker exec -i fuelpay-postgres psql -U fuelpay -d fuelpay -v ON_ERROR_STOP=1 < "$1"; }
for f in portfolio-1-database-design/sql/0[1-3]*.sql; do run "$f"; done   # fresh database, no extra indexes
run portfolio-2-query-optimisation/sql/02_explain.sql
run portfolio-2-query-optimisation/sql/03_indexes.sql
run portfolio-2-query-optimisation/sql/02_explain.sql
```

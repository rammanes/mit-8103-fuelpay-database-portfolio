# Portfolio 5 – Distributed and Cloud Databases

FuelPay starts with one PostgreSQL server. As more stations and fleets join, three problems show up: the transactions table keeps growing, one server is a single point of failure, and reports compete with live payments. This portfolio looks at how to handle that.

| Topic | Status |
|---|---|
| Partitioning transactions by month | **Implemented and tested** |
| Streaming replication (primary + read-only replica) and failover | **Implemented and tested** |
| Synchronous replication for payments | Discussed, not implemented |
| Sharding | Discussed, not implemented |
| Consistency vs availability | Discussed |
| Cloud deployment | Discussed, not implemented |

## 1. Partitioning (implemented)

Script: [sql/01_partitioning.sql](sql/01_partitioning.sql). Output: [evidence/partitioning.txt](evidence/partitioning.txt).

FuelPay reports are almost always by period (monthly statements, monthly fleet spending), and old months are never changed. So `transactions` is a good fit for **range partitioning by month** on `created_at`. The script builds a partitioned copy, `transactions_by_month`, with one partition per month (April to December 2026) and a default partition for anything outside those months. The original table is left alone so Portfolios 1–4 still work.

Query: total successful purchases in October 2026.

| | Original table | Partitioned table |
|---|---|---|
| Plan | Seq Scan on `transactions` (all months) | Seq Scan on `transactions_2026_10` only |
| Buffers read | 121 | 21 |
| Rows read and thrown away | 8,622 | 66 |
| Result | 1,654 purchases, ₦50,428,828 | Same |

PostgreSQL saw the date range in the WHERE clause and skipped every other month (**partition pruning**). With 10k rows both queries are fast, but the work done drops to about a sixth, and the gap grows every month as data is added.

Things I noticed:
- **Queries without a date filter get slower, not faster.** Looking up one account across all time has to check every partition (shown in the evidence). Partitioning only helps queries that filter on the partition key.
- **Unique rules must include the partition key.** The primary key had to become `(transaction_id, created_at)`. That also means `idempotency_key` can't be unique across the whole partitioned table on its own, which is a real problem for FuelPay (it's what stops double charging). In production I'd keep the idempotency check in a small separate table, or make the key include the date.
- **Archiving is easy.** Detaching April took it out of the live table instantly (10,071 rows left, 205 in the archive table). Without partitions this would be a big DELETE.

## 2. Replication and failover (implemented)

Files: [sql/02_replication_demo.sh](sql/02_replication_demo.sh), [replication/](replication/) and the `primary` and `replica` services in [docker-compose.yml](../docker-compose.yml). Output: [evidence/replication-demo.txt](evidence/replication-demo.txt).

Two new PostgreSQL 17 containers, separate from the main `fuelpay-postgres`:
- **fuelpay-primary** accepts reads and writes. `pg_hba.conf` lets a `replicator` login (created by `replication-role.sql`) connect for replication.
- **fuelpay-replica** copies the primary once with `pg_basebackup -R`, then keeps receiving its changes (the write-ahead log, WAL) and replays them. It is read-only.

The demo script loads the Portfolio 1 schema and data into the **primary only**, then checks the replica.

| Check | Result |
|---|---|
| Server roles | primary `pg_is_in_recovery = f`, replica `t` |
| Primary's view of the replica | `streaming`, `async` |
| Data on the replica | 14 tables, 10,225 transactions, same total balance as the primary |
| New ₦10,000 payment written on the primary | Visible on the replica half a second later, replay lag about 1 ms |
| UPDATE sent to the replica | `ERROR: cannot execute UPDATE in a read-only transaction` |
| Primary stopped, replica promoted with `pg_promote()` | Replica becomes a normal server and accepts a new ₦5,000 payment. The earlier ₦10,000 payment is still there |

Uses for FuelPay:
- **Reports on the replica.** Monthly statements and fleet reports can run on the replica so they don't slow down payments at the pump.
- **Failover.** If the primary fails, the replica can take over with the data it already has. In the demo I promoted it by hand. In production a tool like Patroni, or the cloud provider, would detect the failure and do it.

**The catch: asynchronous means a small risk of losing payments.** The primary confirms a payment before the replica has it. If the primary crashes in that gap (about 1 ms here), the payment is lost after failover even though the customer was told it went through. For payments, PostgreSQL's synchronous replication (`synchronous_standby_names`) fixes this by waiting for the replica before confirming, at the cost of slower commits, and payments would stop if the only replica went down. Discussed, not implemented.

## 3. Sharding (discussed, not implemented)

Partitioning splits a table inside one server. Sharding splits data across several servers, each with its own CPU and disk. FuelPay doesn't need it at the current size, but if it did:

- **Shard key: `account_id`.** A payment touches one account, its transaction rows and its ledger entries. If all of these live on the same shard, the ₦20,000 locking from Portfolio 3 still works inside one server, with no cross-server transaction.
- **Not by station or city.** A customer buys fuel in different cities, so one account's payments would be spread across shards, and checking the balance would need a distributed transaction.
- **What gets harder.** Organisation reports cover many accounts, so they would have to query every shard and combine the results. Small shared tables (products, stations) would be copied to every shard. Extensions like Citus do this for PostgreSQL.

## 4. Consistency vs availability

When servers can't reach each other (a network partition), a system has to choose between refusing requests and risking out-of-date data (CAP theorem). FuelPay makes different choices for different data:

| Data | Choice | Why |
|---|---|---|
| Balances, transactions, ledger (PostgreSQL) | **Consistency.** Refuse the payment if the system can't be sure of the balance | Approving on an old balance is the lost update from Portfolio 3 at a larger scale. A declined payment can be retried. Money that was spent twice can't easily be recovered |
| Payment events and pump telemetry (MongoDB, Portfolio 4) | **Availability.** Keep accepting writes, sync later (eventual consistency) | A reading or event log that is a few seconds late harms no one. Losing pump alerts because one server is down would be worse |

## 5. Cloud deployment (discussed, not implemented)

How FuelPay could run in the cloud:
- **PostgreSQL** as a managed service (for example Amazon RDS, Azure Database for PostgreSQL or Google Cloud SQL) with a standby in a second availability zone for automatic failover, a read replica for reports, and automatic backups with point-in-time recovery. This is what sections 1 and 2 did by hand.
- **MongoDB** on MongoDB Atlas as a three-node replica set.
- **Region.** Payment and customer data is personal data under the Nigeria Data Protection Act 2023, so the hosting region and any cross-border transfer have to be checked before choosing a provider.
- **Trade-off.** Managed services cost more than running servers yourself, but backups, patching and failover are handled by the provider.

## How to reproduce

From the repo root, with Portfolio 1 loaded in `fuelpay-postgres`:

```bash
docker exec -i fuelpay-postgres psql -U fuelpay -d fuelpay -X < portfolio-5-distributed-cloud/sql/01_partitioning.sql
bash portfolio-5-distributed-cloud/sql/02_replication_demo.sh
```

The replication script builds a fresh primary and replica each time it runs (about 15 seconds). To remove the pair afterwards, run `docker rm -f fuelpay-primary fuelpay-replica`. Don't use `docker compose down -v`, because that would also delete the main PostgreSQL and MongoDB data.

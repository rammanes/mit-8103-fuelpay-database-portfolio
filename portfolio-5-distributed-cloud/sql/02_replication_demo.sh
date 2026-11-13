#!/usr/bin/env bash
# FuelPay Network: streaming replication and failover.
# Builds a fresh primary + replica pair (separate from the main fuelpay-postgres container),
# loads the Portfolio 1 data on the primary only, then checks what reaches the replica.
# Run from the repo root. Re-running rebuilds the pair from scratch.
set -e

primary() { docker exec -i fuelpay-primary stdbuf -oL -eL psql -U fuelpay -d fuelpay -X -q -c "$1" 2>&1; }
replica() { docker exec -i fuelpay-replica stdbuf -oL -eL psql -U fuelpay -d fuelpay -X -q -c "$1" 2>&1; }

echo "Setting up: removing any old pair and starting a new primary and replica..."
docker rm -f fuelpay-primary fuelpay-replica >/dev/null 2>&1 || true
docker volume rm -f fuelpay-primarydata fuelpay-replicadata >/dev/null
docker compose --profile replication up -d primary replica >/dev/null 2>&1
wait_for() {
  for i in $(seq 60); do
    docker exec "$1" pg_isready -q -h localhost 2>/dev/null && return 0
    sleep 1
  done
  echo "$1 did not start. Check: docker logs $1"; exit 1
}
wait_for fuelpay-primary
wait_for fuelpay-replica

echo "Loading the Portfolio 1 schema and data into the PRIMARY only..."
for f in portfolio-1-database-design/sql/0[123]*.sql; do
  docker exec -i -e PGOPTIONS="-c client_min_messages=warning" fuelpay-primary psql -U fuelpay -d fuelpay -X -q -v ON_ERROR_STOP=1 < "$f" >/dev/null
done
sleep 1

echo
echo "== 1. Which server is which =="
echo "primary:"; primary "SELECT pg_is_in_recovery() AS is_read_only_standby;"
echo "replica:"; replica "SELECT pg_is_in_recovery() AS is_read_only_standby;"

echo "== 2. The primary sees the replica connected and streaming =="
primary "SELECT application_name, state, sync_state FROM pg_stat_replication;"

echo "== 3. Data loaded on the primary is already on the replica =="
COUNTS="SELECT (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public') AS tables,
               (SELECT count(*) FROM transactions) AS transactions,
               (SELECT sum(balance) FROM customer_accounts) AS total_balances;"
echo "primary:"; primary "$COUNTS"
echo "replica:"; replica "$COUNTS"

echo "== 4. A new N10,000 funding payment on the primary appears on the replica =="
KEY="REPL-TEST-$(date +%s)"
primary "WITH t AS (INSERT INTO transactions (account_id, transaction_type, amount, status, idempotency_key)
                    VALUES (1, 'funding', 10000, 'successful', '$KEY') RETURNING transaction_id, account_id),
              l AS (INSERT INTO account_ledger (account_id, transaction_id, entry_type, amount)
                    SELECT account_id, transaction_id, 'credit', 10000 FROM t)
         UPDATE customer_accounts SET balance = balance + 10000 WHERE account_id = 1;"
sleep 0.5
echo "read from the replica:"
replica "SELECT idempotency_key, amount, created_at FROM transactions WHERE idempotency_key = '$KEY';"
primary "SELECT state, replay_lag FROM pg_stat_replication;"

echo "== 5. The replica refuses writes =="
replica "UPDATE customer_accounts SET balance = 0 WHERE account_id = 1;" || true
echo

echo "== 6. Failover: the primary goes down and the replica is promoted =="
docker stop fuelpay-primary >/dev/null
echo "primary container stopped"
replica "SELECT pg_promote() AS promoted;"
replica "SELECT pg_is_in_recovery() AS is_read_only_standby;"
echo "the promoted server now accepts payments:"
replica "WITH t AS (INSERT INTO transactions (account_id, transaction_type, amount, status, idempotency_key)
                    VALUES (1, 'funding', 5000, 'successful', '$KEY-AFTER-FAILOVER') RETURNING transaction_id, account_id),
              l AS (INSERT INTO account_ledger (account_id, transaction_id, entry_type, amount)
                    SELECT account_id, transaction_id, 'credit', 5000 FROM t)
         UPDATE customer_accounts SET balance = balance + 5000 WHERE account_id = 1 RETURNING account_id, balance;"
replica "SELECT idempotency_key, amount FROM transactions WHERE idempotency_key LIKE '$KEY%' ORDER BY transaction_id;"
echo "The old primary is left stopped. Re-run this script to rebuild the pair."

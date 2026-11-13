#!/usr/bin/env bash
# FuelPay Network: the N20,000 concurrent payment demo and an isolation level demo.
# Two database sessions (A and B) run at the same time against the same account.
# Every step prints a timestamp so the order of events can be followed.
# Run from the repo root:  bash portfolio-3-transactions-concurrency/sql/02_concurrency_demo.sh

PSQL="docker exec -i fuelpay-postgres stdbuf -oL -eL psql -U fuelpay -d fuelpay -X -q -tA"
TMP=$(mktemp -d)

# New customer account funded with N20,000 (funding transaction + ledger credit)
new_account() {
  $PSQL <<'SQL'
WITH c AS (
    INSERT INTO customers (first_name, last_name, email, phone)
    VALUES ('Demo', 'Customer', 'demo-' || txid_current() || '@example.com', 'DEMO-' || txid_current())
    RETURNING customer_id
), a AS (
    INSERT INTO customer_accounts (account_number, customer_id, balance)
    SELECT 'DEMO-' || txid_current(), customer_id, 20000 FROM c
    RETURNING account_id
), t AS (
    INSERT INTO transactions (account_id, transaction_type, amount, status, idempotency_key)
    SELECT account_id, 'funding', 20000, 'successful', 'DEMO-FUND-' || txid_current() FROM a
    RETURNING transaction_id, account_id
), l AS (
    INSERT INTO account_ledger (account_id, transaction_id, entry_type, amount)
    SELECT account_id, transaction_id, 'credit', 20000 FROM t
)
SELECT account_id FROM a;
SQL
}

# SQL that records a N15,000 diesel payment (12 litres at N1,250) for session $2 on account $1
record_payment() {
  cat <<SQL
INSERT INTO transactions (account_id, transaction_type, amount, status, idempotency_key)
VALUES ($1, 'purchase', 15000, 'successful', 'DEMO-$1-$2') RETURNING transaction_id AS tx \gset
INSERT INTO fuel_purchases (transaction_id, station_id, product_id, litres, price_per_litre) VALUES (:tx, 1, 2, 12, 1250);
INSERT INTO account_ledger (account_id, transaction_id, entry_type, amount) VALUES ($1, :tx, 'debit', 15000);
SQL
}

log() { echo "SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') || '  Session $1: ' || $2;"; }

# Run session A now and session B half a second later, then print both as one timeline
run_both() {
  $PSQL < "$TMP/A.sql" > "$TMP/A.out" 2>&1 &
  sleep 0.5
  $PSQL < "$TMP/B.sql" > "$TMP/B.out" 2>&1 &
  wait
  cat "$TMP/A.out" "$TMP/B.out" | grep -E '^[0-9]{2}:' | sort -s -k1,1
  grep -h -E '^(ERROR|DETAIL)' "$TMP/A.out" "$TMP/B.out" | sed 's/^/  /'
}

summary() {
  $PSQL <<SQL
SELECT 'Result: balance N' || a.balance
       || ' | balance worked out from the ledger N' || sum(CASE WHEN l.entry_type = 'credit' THEN l.amount ELSE -l.amount END)
       || ' | N15,000 payments recorded: ' || (SELECT count(*) FROM transactions WHERE account_id = $1 AND transaction_type = 'purchase')
FROM customer_accounts a JOIN account_ledger l ON l.account_id = a.account_id
WHERE a.account_id = $1 GROUP BY a.balance;
SQL
}

# ---------------------------------------------------------------------------
echo "== Scenario 1: no concurrency control (lost update) =="
echo "Each session reads the balance, checks it is enough, then writes back balance - 15000."
ACC=$(new_account)
for S in A B; do
  { echo "BEGIN;"
    echo "SELECT balance AS bal FROM customer_accounts WHERE account_id = $ACC \gset"
    log $S "'read balance N' || :bal || ', enough for N15,000'"
    echo "SELECT pg_sleep(2) \gset"
    echo "UPDATE customer_accounts SET balance = :bal - 15000 WHERE account_id = $ACC;"
    record_payment $ACC $S
    echo "COMMIT;"
    log $S "'committed, set balance to N' || (:bal - 15000)"
  } > "$TMP/$S.sql"
done
run_both
summary $ACC
echo

# ---------------------------------------------------------------------------
echo "== Scenario 2: SELECT ... FOR UPDATE (row lock) =="
echo "Each session locks the account row before reading the balance."
ACC=$(new_account)
for S in A B; do
  { echo "BEGIN;"
    log $S "'asking for a lock on the account'"
    echo "SELECT balance AS bal, balance >= 15000 AS enough FROM customer_accounts WHERE account_id = $ACC FOR UPDATE \gset"
    log $S "'got the lock, balance is N' || :bal"
    echo "SELECT pg_sleep(2) \gset"
    echo "\if :enough"
    echo "UPDATE customer_accounts SET balance = balance - 15000 WHERE account_id = $ACC;"
    record_payment $ACC $S
    echo "COMMIT;"
    log $S "'paid N15,000 and committed'"
    echo "\else"
    echo "ROLLBACK;"
    log $S "'not enough money, payment declined'"
    echo "\endif"
  } > "$TMP/$S.sql"
done
run_both
summary $ACC
echo

# ---------------------------------------------------------------------------
for LEVEL in "READ COMMITTED" "REPEATABLE READ"; do
  echo "== Scenario 3: isolation level $LEVEL =="
  echo "Session A reads the balance twice in one transaction. Session B pays N15,000 in between."
  ACC=$(new_account)
  { echo "BEGIN ISOLATION LEVEL $LEVEL;"
    echo "SELECT balance AS b1 FROM customer_accounts WHERE account_id = $ACC \gset"
    log A "'first read: balance N' || :b1"
    echo "SELECT pg_sleep(2) \gset"
    echo "SELECT balance AS b2 FROM customer_accounts WHERE account_id = $ACC \gset"
    log A "'second read: balance N' || :b2"
    log A "'now tries to take N10,000 from the balance'"
    echo "WITH u AS (UPDATE customer_accounts SET balance = balance - 10000 WHERE account_id = $ACC AND balance >= 10000 RETURNING 1) SELECT count(*) AS updated FROM u \gset"
    [ "$LEVEL" = "READ COMMITTED" ] && log A "'rows updated: ' || :updated"
    echo "ROLLBACK;"
    log A "'rolled back (demo only, nothing saved)'"
  } > "$TMP/A.sql"
  { echo "BEGIN;"
    echo "UPDATE customer_accounts SET balance = balance - 15000 WHERE account_id = $ACC AND balance >= 15000;"
    record_payment $ACC B
    echo "COMMIT;"
    log B "'paid N15,000 and committed'"
  } > "$TMP/B.sql"
  run_both
  echo
done

rm -rf "$TMP"

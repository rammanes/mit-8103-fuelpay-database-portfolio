-- FuelPay Network: COMMIT, ROLLBACK and atomicity, on a fresh demo account funded with N20,000.
-- Some steps fail on purpose, so this script keeps going after errors.
\set ON_ERROR_STOP 0

\echo '== Setup: new demo account funded with N20,000 =='
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
SELECT account_id AS acc FROM a \gset
SELECT account_id, account_number, balance FROM customer_accounts WHERE account_id = :acc;

\echo '== 1. COMMIT: a N5,000 diesel purchase (4 litres at N1,250) =='
BEGIN;
INSERT INTO transactions (account_id, transaction_type, amount, status, idempotency_key)
VALUES (:acc, 'purchase', 5000, 'successful', 'DEMO-PAY-' || :acc || '-1')
RETURNING transaction_id AS tx \gset
INSERT INTO fuel_purchases (transaction_id, station_id, product_id, litres, price_per_litre)
VALUES (:tx, 1, 2, 4, 1250);
INSERT INTO account_ledger (account_id, transaction_id, entry_type, amount)
VALUES (:acc, :tx, 'debit', 5000);
UPDATE customer_accounts SET balance = balance - 5000 WHERE account_id = :acc;
COMMIT;
\echo 'After COMMIT the balance is N15,000 and the payment is saved:'
SELECT a.balance, t.transaction_id, t.amount, t.status
FROM customer_accounts a JOIN transactions t ON t.account_id = a.account_id AND t.transaction_type = 'purchase'
WHERE a.account_id = :acc;

\echo '== 2. ROLLBACK: a N3,000 payment cancelled before it finishes =='
BEGIN;
INSERT INTO transactions (account_id, transaction_type, amount, status, idempotency_key)
VALUES (:acc, 'purchase', 3000, 'successful', 'DEMO-PAY-' || :acc || '-2')
RETURNING transaction_id AS tx2 \gset
INSERT INTO account_ledger (account_id, transaction_id, entry_type, amount)
VALUES (:acc, :tx2, 'debit', 3000);
UPDATE customer_accounts SET balance = balance - 3000 WHERE account_id = :acc;
\echo 'Inside the transaction the balance shows N12,000:'
SELECT balance FROM customer_accounts WHERE account_id = :acc;
ROLLBACK;
\echo 'After ROLLBACK the balance is back to N15,000 and the payment does not exist:'
SELECT balance,
       (SELECT count(*) FROM transactions WHERE idempotency_key = 'DEMO-PAY-' || :acc || '-2') AS payments_saved
FROM customer_accounts WHERE account_id = :acc;

\echo '== 3. Automatic rollback: a N50,000 payment fails halfway through =='
\echo 'The transaction row and ledger entry are inserted first, then the balance update breaks the CHECK rule.'
BEGIN;
INSERT INTO transactions (account_id, transaction_type, amount, status, idempotency_key)
VALUES (:acc, 'purchase', 50000, 'successful', 'DEMO-PAY-' || :acc || '-3')
RETURNING transaction_id AS tx3 \gset
INSERT INTO account_ledger (account_id, transaction_id, entry_type, amount)
VALUES (:acc, :tx3, 'debit', 50000);
UPDATE customer_accounts SET balance = balance - 50000 WHERE account_id = :acc;
ROLLBACK;
\echo 'Nothing from the failed payment was kept (atomicity):'
SELECT balance,
       (SELECT count(*) FROM transactions WHERE idempotency_key = 'DEMO-PAY-' || :acc || '-3') AS payments_saved,
       (SELECT count(*) FROM account_ledger WHERE transaction_id = :tx3) AS ledger_entries_saved
FROM customer_accounts WHERE account_id = :acc;

\echo '== 4. Duplicate request: the terminal retries payment 1 with the same idempotency key =='
INSERT INTO transactions (account_id, transaction_type, amount, status, idempotency_key)
VALUES (:acc, 'purchase', 5000, 'successful', 'DEMO-PAY-' || :acc || '-1');
\echo 'The retry was rejected, so the customer was only charged once:'
SELECT count(*) AS payments_with_this_key FROM transactions
WHERE idempotency_key = 'DEMO-PAY-' || :acc || '-1';

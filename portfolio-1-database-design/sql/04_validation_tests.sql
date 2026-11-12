-- FuelPay Network: constraint tests.
-- Each test tries to break a business rule. PASS means the database rejected it
-- with the expected constraint. Everything runs inside a transaction that is
-- rolled back, so no test data is left behind.

BEGIN;

CREATE FUNCTION pg_temp.expect_rejected(stmt text, expected text) RETURNS text AS $$
DECLARE
    fired text;
BEGIN
    EXECUTE stmt;
    RETURN 'FAIL: statement was accepted';
EXCEPTION WHEN integrity_constraint_violation THEN
    GET STACKED DIAGNOSTICS fired = CONSTRAINT_NAME;
    RETURN CASE WHEN fired = expected THEN 'PASS' ELSE 'FAIL' END || ': rejected by ' || fired;
END;
$$ LANGUAGE plpgsql;

SELECT t.test, t.rule, pg_temp.expect_rejected(t.stmt, t.expected) AS result
FROM (VALUES
  ('T01', 'BR-001 duplicate customer email',
   $q$INSERT INTO customers (first_name, last_name, email, phone) VALUES ('Test', 'User', 'customer1@example.com', '09000000001')$q$,
   'uq_customers_email'),
  ('T02', 'BR-003 account with two owners',
   $q$INSERT INTO customer_accounts (account_number, customer_id, organisation_id) VALUES ('TEST001', 1, 1)$q$,
   'chk_accounts_one_owner'),
  ('T03', 'BR-003 account with no owner',
   $q$INSERT INTO customer_accounts (account_number) VALUES ('TEST002')$q$,
   'chk_accounts_one_owner'),
  ('T04', 'BR-004 duplicate card UID',
   $q$INSERT INTO payment_instruments (account_id, instrument_type, uid) VALUES (2, 'card', 'CARD-000001')$q$,
   'uq_instruments_uid'),
  ('T05', 'BR-004 card linked to a vehicle',
   $q$INSERT INTO payment_instruments (account_id, vehicle_id, instrument_type, uid) VALUES (1, 1, 'card', 'CARD-TEST')$q$,
   'chk_instruments_vehicle_tag_only'),
  ('T06', 'BR-006 allowance for employee and vehicle',
   $q$INSERT INTO fuel_allowances (employee_id, vehicle_id, limit_amount) VALUES (1, 1, 50000)$q$,
   'chk_allowances_one_target'),
  ('T07', 'BR-006 allowance with zero limit',
   $q$INSERT INTO fuel_allowances (employee_id, limit_amount) VALUES (1, 0)$q$,
   'chk_allowances_limit_positive'),
  ('T08', 'BR-007 purchase at a station that does not exist',
   $q$INSERT INTO fuel_purchases (transaction_id, station_id, product_id, litres, price_per_litre)
      VALUES ((SELECT transaction_id FROM transactions WHERE status = 'failed' LIMIT 1), 99999, 1, 10, 1050)$q$,
   'fk_purchases_station'),
  ('T09', 'BR-008 negative balance',
   $q$UPDATE customer_accounts SET balance = -1 WHERE account_id = 1$q$,
   'chk_accounts_balance_non_negative'),
  ('T10', 'BR-009 duplicate idempotency key',
   $q$INSERT INTO transactions (account_id, transaction_type, amount, idempotency_key) VALUES (1, 'purchase', 1000, 'PUR-00000001')$q$,
   'uq_transactions_idempotency'),
  ('T11', 'BR-010 unknown transaction status',
   $q$INSERT INTO transactions (account_id, transaction_type, amount, status, idempotency_key) VALUES (1, 'purchase', 1000, 'done', 'TEST-STATUS')$q$,
   'chk_transactions_status'),
  ('T12', 'BR-010 zero amount',
   $q$INSERT INTO transactions (account_id, transaction_type, amount, idempotency_key) VALUES (1, 'purchase', 0, 'TEST-AMOUNT')$q$,
   'chk_transactions_amount_positive'),
  ('T13', 'BR-011 reversing a transaction twice',
   $q$INSERT INTO reversals (original_transaction_id, reversal_transaction_id)
      VALUES ((SELECT original_transaction_id FROM reversals LIMIT 1),
              (SELECT transaction_id FROM transactions WHERE transaction_type = 'funding' LIMIT 1))$q$,
   'uq_reversals_original'),
  ('T14', 'One payment linked to two purchases',
   $q$INSERT INTO fuel_purchases (transaction_id, station_id, product_id, litres, price_per_litre)
      VALUES ((SELECT transaction_id FROM fuel_purchases LIMIT 1), 1, 1, 10, 1050)$q$,
   'uq_purchases_transaction'),
  ('T15', 'BR-012/013 deleting a customer who has an account',
   $q$DELETE FROM customers WHERE customer_id = 1$q$,
   'fk_accounts_customer')
) AS t(test, rule, stmt, expected)
ORDER BY t.test;

ROLLBACK;

-- Data checks on the seeded data (every count should be 0)
SELECT 'Accounts whose balance does not match the ledger' AS check_name, count(*) AS problems
FROM customer_accounts a
LEFT JOIN (SELECT account_id, sum(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END) AS total
           FROM account_ledger GROUP BY account_id) l ON l.account_id = a.account_id
WHERE a.balance <> coalesce(l.total, 0)
UNION ALL
SELECT 'Successful purchases with no pump record', count(*)
FROM transactions t LEFT JOIN fuel_purchases p ON p.transaction_id = t.transaction_id
WHERE t.transaction_type = 'purchase' AND t.status IN ('successful', 'reversed') AND p.purchase_id IS NULL
UNION ALL
SELECT 'Reversed purchases with no reversal record', count(*)
FROM transactions t LEFT JOIN reversals r ON r.original_transaction_id = t.transaction_id
WHERE t.status = 'reversed' AND r.reversal_id IS NULL;

-- FuelPay Network: synthetic test data.
-- Run after 01_create_tables.sql and 02_constraints.sql. Safe to re-run.
-- Change n_purchases to load more or fewer fuel purchases.
\set n_purchases 10000

BEGIN;

SELECT setseed(0.42);  -- same random data on every run

TRUNCATE audit_logs, reversals, account_ledger, fuel_purchases, transactions,
         fuel_allowances, payment_instruments, customer_accounts, fuel_products,
         fuel_stations, vehicles, employees, customers, organisations
RESTART IDENTITY;

-- Reference data
INSERT INTO organisations (name, rc_number, email, phone)
SELECT name, 'RC' || (100000 + i), 'fleet' || i || '@example.com', '0803' || lpad(i::text, 7, '0')
FROM (VALUES (1, 'Sahel Haulage Ltd'), (2, 'Lagoon Couriers Ltd'), (3, 'Savannah Agro Fleet'),
             (4, 'Delta Transport Services'), (5, 'Plateau Logistics Ltd')) AS o(i, name);

INSERT INTO customers (first_name, last_name, email, phone)
SELECT (ARRAY['Ada','Chinedu','Fatima','Ibrahim','Ngozi','Tunde','Aisha','Emeka','Zainab','Yusuf'])[1 + i % 10],
       (ARRAY['Okafor','Bello','Adeyemi','Musa','Eze','Abubakar','Okon','Lawal','Nwosu','Danladi'])[1 + (i / 10) % 10],
       'customer' || i || '@example.com',
       '0810' || lpad(i::text, 7, '0')
FROM generate_series(1, 200) AS i;

INSERT INTO employees (organisation_id, first_name, last_name, staff_number)
SELECT 1 + i % 5,
       (ARRAY['Musa','Bola','Kelechi','Hauwa','Segun','Amaka','Sani','Funmi'])[1 + i % 8],
       (ARRAY['Garba','Ojo','Umeh','Sule','Bakare','Obi'])[1 + i % 6],
       'EMP' || lpad(i::text, 4, '0')
FROM generate_series(1, 50) AS i;

INSERT INTO vehicles (organisation_id, plate_number, make, model)
SELECT 1 + i % 5,
       'FP' || lpad(i::text, 3, '0') || 'KJA',
       (ARRAY['Toyota','Toyota','Nissan','Mercedes-Benz'])[1 + i % 4],
       (ARRAY['Hilux','Hiace','Navara','Actros'])[1 + i % 4]
FROM generate_series(1, 40) AS i;

INSERT INTO fuel_stations (station_code, name, city, state)
SELECT 'STN-' || lpad(i::text, 3, '0'),
       c.city || ' Station ' || i,
       c.city, c.state
FROM generate_series(1, 20) AS i
JOIN (VALUES (0, 'Abuja', 'FCT'), (1, 'Lagos', 'Lagos'), (2, 'Kano', 'Kano'),
             (3, 'Port Harcourt', 'Rivers'), (4, 'Ibadan', 'Oyo'), (5, 'Kaduna', 'Kaduna'),
             (6, 'Enugu', 'Enugu'), (7, 'Jos', 'Plateau'), (8, 'Benin City', 'Edo'),
             (9, 'Abeokuta', 'Ogun')) AS c(k, city, state) ON c.k = i % 10;

INSERT INTO fuel_products (name, price_per_litre)
VALUES ('Petrol', 1050.00), ('Diesel', 1250.00), ('Kerosene', 1400.00);

-- Accounts: one per customer, one per organisation
INSERT INTO customer_accounts (account_number, customer_id)
SELECT 'FPC' || lpad(customer_id::text, 7, '0'), customer_id FROM customers;

INSERT INTO customer_accounts (account_number, organisation_id)
SELECT 'FPO' || lpad(organisation_id::text, 7, '0'), organisation_id FROM organisations;

-- Cards for customers, tags for company vehicles
INSERT INTO payment_instruments (account_id, instrument_type, uid)
SELECT account_id, 'card', 'CARD-' || lpad(account_id::text, 6, '0')
FROM customer_accounts WHERE customer_id IS NOT NULL;

INSERT INTO payment_instruments (account_id, vehicle_id, instrument_type, uid)
SELECT a.account_id, v.vehicle_id, 'tag', 'TAG-' || lpad(v.vehicle_id::text, 6, '0')
FROM vehicles v JOIN customer_accounts a ON a.organisation_id = v.organisation_id;

-- Allowances: monthly per employee, weekly for half the vehicles
INSERT INTO fuel_allowances (employee_id, limit_amount, period)
SELECT employee_id, 300000, 'monthly' FROM employees;

INSERT INTO fuel_allowances (vehicle_id, limit_amount, period)
SELECT vehicle_id, 80000, 'weekly' FROM vehicles WHERE vehicle_id % 2 = 0;

-- Fund every account once: N5m for customers, N50m for company fleets
INSERT INTO transactions (account_id, transaction_type, amount, status, idempotency_key, created_at)
SELECT account_id, 'funding', CASE WHEN organisation_id IS NULL THEN 5000000 ELSE 50000000 END,
       'successful', 'FUND-' || account_id, now() - interval '200 days'
FROM customer_accounts;

-- Plan the purchases: 30% by company fleets, the rest by customers, spread over the last 180 days
CREATE TEMP TABLE planned_purchases AS
WITH g AS (
    SELECT n, random() AS r_owner, random() AS r_account, random() AS r_station, random() AS r_product,
              random() AS r_litres, random() AS r_status, random() AS r_app, random() AS r_date
    FROM generate_series(1, :n_purchases) AS n
)
SELECT n,
       'PUR-' || lpad(n::text, 8, '0')                                  AS idempotency_key,
       CASE WHEN r_owner < 0.30
            THEN (SELECT count(*) FROM customers) + 1 + floor(r_account * (SELECT count(*) FROM organisations))
            ELSE 1 + floor(r_account * (SELECT count(*) FROM customers))
       END::bigint                                                      AS account_id,
       1 + floor(r_station * (SELECT count(*) FROM fuel_stations))::bigint     AS station_id,
       CASE WHEN r_product < 0.70 THEN 1 WHEN r_product < 0.95 THEN 2 ELSE 3 END::bigint AS product_id,
       round((5 + r_litres * 45)::numeric, 2)                           AS litres,
       r_status < 0.03                                                  AS failed,
       r_app < 0.10                                                     AS app_payment,
       now() - r_date * interval '180 days'                             AS created_at
FROM g;

-- Card or tag used (none for app payments); for company accounts also the vehicle and driver
ALTER TABLE planned_purchases ADD COLUMN instrument_id bigint, ADD COLUMN vehicle_id bigint,
                              ADD COLUMN employee_id bigint, ADD COLUMN price_per_litre numeric(10,2);

UPDATE planned_purchases p
SET instrument_id = CASE WHEN p.app_payment THEN NULL ELSE
        (SELECT pi.instrument_id FROM payment_instruments pi
         WHERE pi.account_id = p.account_id ORDER BY random() LIMIT 1) END,
    employee_id = (SELECT e.employee_id FROM employees e
                   JOIN customer_accounts a ON a.organisation_id = e.organisation_id
                   WHERE a.account_id = p.account_id ORDER BY random() LIMIT 1),
    price_per_litre = (SELECT price_per_litre FROM fuel_products fp WHERE fp.product_id = p.product_id);

UPDATE planned_purchases p
SET vehicle_id = pi.vehicle_id
FROM payment_instruments pi WHERE pi.instrument_id = p.instrument_id;

-- Purchase transactions (about 3% fail)
INSERT INTO transactions (account_id, transaction_type, amount, status, idempotency_key, created_at)
SELECT account_id, 'purchase', round(litres * price_per_litre, 2),
       CASE WHEN failed THEN 'failed' ELSE 'successful' END, idempotency_key, created_at
FROM planned_purchases ORDER BY created_at;

-- Pump details for successful purchases only
INSERT INTO fuel_purchases (transaction_id, station_id, product_id, instrument_id, employee_id,
                            vehicle_id, litres, price_per_litre, created_at)
SELECT t.transaction_id, p.station_id, p.product_id, p.instrument_id, p.employee_id,
       p.vehicle_id, p.litres, p.price_per_litre, p.created_at
FROM planned_purchases p JOIN transactions t ON t.idempotency_key = p.idempotency_key
WHERE NOT p.failed;

-- Reverse 20 random successful purchases (the original is kept and marked reversed)
CREATE TEMP TABLE to_reverse AS
SELECT transaction_id, account_id, amount, created_at FROM transactions
WHERE transaction_type = 'purchase' AND status = 'successful'
ORDER BY random() LIMIT 20;

UPDATE transactions SET status = 'reversed'
WHERE transaction_id IN (SELECT transaction_id FROM to_reverse);

INSERT INTO transactions (account_id, transaction_type, amount, status, idempotency_key, created_at)
SELECT account_id, 'reversal', amount, 'successful', 'REV-' || transaction_id, created_at + interval '1 hour'
FROM to_reverse;

INSERT INTO reversals (original_transaction_id, reversal_transaction_id, reason, created_at)
SELECT r.transaction_id, t.transaction_id, 'Pump failed to dispense', t.created_at
FROM to_reverse r JOIN transactions t ON t.idempotency_key = 'REV-' || r.transaction_id;

INSERT INTO audit_logs (table_name, record_id, action, details, performed_by)
SELECT 'reversals', reversal_id, 'insert',
       jsonb_build_object('original_transaction_id', original_transaction_id, 'reason', reason),
       'seed_script'
FROM reversals;

-- Ledger: credit for fundings and reversals, debit for purchases that went through
INSERT INTO account_ledger (account_id, transaction_id, entry_type, amount, created_at)
SELECT account_id, transaction_id,
       CASE WHEN transaction_type = 'purchase' THEN 'debit' ELSE 'credit' END,
       amount, created_at
FROM transactions
WHERE status IN ('successful', 'reversed')
ORDER BY created_at;

-- Balance = credits - debits from the ledger
UPDATE customer_accounts a
SET balance = l.total
FROM (SELECT account_id,
             sum(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END) AS total
      FROM account_ledger GROUP BY account_id) l
WHERE l.account_id = a.account_id;

COMMIT;

ANALYZE;

-- Row counts
SELECT 'organisations' AS table_name, count(*) AS rows FROM organisations
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'employees', count(*) FROM employees
UNION ALL SELECT 'vehicles', count(*) FROM vehicles
UNION ALL SELECT 'customer_accounts', count(*) FROM customer_accounts
UNION ALL SELECT 'payment_instruments', count(*) FROM payment_instruments
UNION ALL SELECT 'fuel_stations', count(*) FROM fuel_stations
UNION ALL SELECT 'fuel_products', count(*) FROM fuel_products
UNION ALL SELECT 'fuel_allowances', count(*) FROM fuel_allowances
UNION ALL SELECT 'transactions', count(*) FROM transactions
UNION ALL SELECT 'fuel_purchases', count(*) FROM fuel_purchases
UNION ALL SELECT 'account_ledger', count(*) FROM account_ledger
UNION ALL SELECT 'reversals', count(*) FROM reversals
UNION ALL SELECT 'audit_logs', count(*) FROM audit_logs;

-- FuelPay Network: basic, relational and business queries.
-- Uses the data loaded by portfolio-1-database-design/sql/03_seed_data.sql.

\echo '== B1. Stations in Lagos =='
SELECT station_code, name, city
FROM fuel_stations
WHERE city = 'Lagos'
ORDER BY station_code;

\echo '== B2. Ten largest successful purchases =='
SELECT transaction_id, account_id, amount, created_at::date AS date
FROM transactions
WHERE transaction_type = 'purchase' AND status = 'successful'
ORDER BY amount DESC
LIMIT 10;

\echo '== B3. Transactions by type and status =='
SELECT transaction_type, status, count(*) AS transactions, sum(amount) AS total_amount
FROM transactions
GROUP BY transaction_type, status
ORDER BY transaction_type, status;

\echo '== R1. Last 10 purchases by customer 42, with station and product =='
SELECT t.created_at::date AS date, s.name AS station, p.name AS product,
       fp.litres, fp.price_per_litre, t.amount
FROM customers c
JOIN customer_accounts a ON a.customer_id = c.customer_id
JOIN transactions t      ON t.account_id = a.account_id
JOIN fuel_purchases fp   ON fp.transaction_id = t.transaction_id
JOIN fuel_stations s     ON s.station_id = fp.station_id
JOIN fuel_products p     ON p.product_id = fp.product_id
WHERE c.customer_id = 42
ORDER BY t.created_at DESC
LIMIT 10;

\echo '== R2. Company vehicle purchases this week, with plate and driver =='
SELECT o.name AS organisation, v.plate_number, e.first_name || ' ' || e.last_name AS driver,
       fp.litres, t.amount, t.created_at::date AS date
FROM fuel_purchases fp
JOIN transactions t   ON t.transaction_id = fp.transaction_id
JOIN vehicles v       ON v.vehicle_id = fp.vehicle_id
JOIN organisations o  ON o.organisation_id = v.organisation_id
LEFT JOIN employees e ON e.employee_id = fp.employee_id
WHERE t.created_at >= now() - interval '7 days'
ORDER BY t.created_at DESC
LIMIT 10;

\echo '== R3. Reversals with the original and refund amounts =='
SELECT r.reversal_id, o.transaction_id AS original_id, o.amount AS original_amount,
       o.status AS original_status, rv.transaction_id AS refund_id, rv.amount AS refund_amount, r.reason
FROM reversals r
JOIN transactions o  ON o.transaction_id = r.original_transaction_id
JOIN transactions rv ON rv.transaction_id = r.reversal_transaction_id
ORDER BY r.reversal_id
LIMIT 10;

\echo '== S1. Account statement for account 42 with running balance (last 10 entries) =='
SELECT * FROM (
    SELECT l.created_at::date AS date, t.transaction_type, l.entry_type, l.amount,
           sum(CASE WHEN l.entry_type = 'credit' THEN l.amount ELSE -l.amount END)
               OVER (ORDER BY l.created_at, l.entry_id) AS running_balance
    FROM account_ledger l
    JOIN transactions t ON t.transaction_id = l.transaction_id
    WHERE l.account_id = 42
) statement
ORDER BY date DESC
LIMIT 10;

\echo '== S2. Corporate fuel spending per organisation per month =='
SELECT o.name AS organisation, date_trunc('month', t.created_at)::date AS month,
       count(*) AS purchases, sum(fp.litres) AS litres, sum(t.amount) AS spent
FROM organisations o
JOIN customer_accounts a ON a.organisation_id = o.organisation_id
JOIN transactions t      ON t.account_id = a.account_id
JOIN fuel_purchases fp   ON fp.transaction_id = t.transaction_id
WHERE t.status = 'successful'
GROUP BY o.name, month
ORDER BY o.name, month
LIMIT 12;

\echo '== S3. Station activity in the last 30 days, busiest first =='
SELECT s.station_code, s.name, count(*) AS purchases,
       sum(fp.litres) AS litres, sum(fp.litres * fp.price_per_litre) AS revenue,
       rank() OVER (ORDER BY sum(fp.litres) DESC) AS rank
FROM fuel_stations s
JOIN fuel_purchases fp ON fp.station_id = s.station_id
WHERE fp.created_at >= now() - interval '30 days'
GROUP BY s.station_id
ORDER BY rank
LIMIT 10;

\echo '== S4. Fuel consumption by product per month =='
SELECT date_trunc('month', fp.created_at)::date AS month, p.name AS product,
       sum(fp.litres) AS litres
FROM fuel_purchases fp
JOIN fuel_products p ON p.product_id = fp.product_id
GROUP BY month, p.name
ORDER BY month, p.name;

\echo '== S5. Employees who went over their monthly allowance this month =='
WITH spent AS (
    SELECT fp.employee_id, sum(fp.litres * fp.price_per_litre) AS spent
    FROM fuel_purchases fp
    WHERE fp.created_at >= date_trunc('month', now())
    GROUP BY fp.employee_id
)
SELECT e.staff_number, e.first_name || ' ' || e.last_name AS employee,
       fa.limit_amount, s.spent
FROM fuel_allowances fa
JOIN employees e ON e.employee_id = fa.employee_id
JOIN spent s     ON s.employee_id = fa.employee_id
WHERE fa.period = 'monthly' AND s.spent > fa.limit_amount
ORDER BY s.spent DESC;

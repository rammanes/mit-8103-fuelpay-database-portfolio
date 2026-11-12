-- FuelPay Network: indexes for the frequent queries in 02_explain.sql.
-- PostgreSQL indexes primary keys and UNIQUE columns automatically, but not foreign keys.

CREATE INDEX idx_transactions_account_date ON transactions (account_id, created_at);    -- Q1
CREATE INDEX idx_purchases_station_date    ON fuel_purchases (station_id, created_at);  -- Q2
CREATE INDEX idx_ledger_account_date       ON account_ledger (account_id, created_at);  -- Q3

ANALYZE transactions;
ANALYZE fuel_purchases;
ANALYZE account_ledger;

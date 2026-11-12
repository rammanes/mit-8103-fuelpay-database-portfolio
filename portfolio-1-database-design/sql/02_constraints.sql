-- FuelPay Network: business rules as named constraints.
-- Run after 01_create_tables.sql. BR numbers refer to docs/business-requirements.md.

-- Foreign keys (BR-002, BR-003, BR-004, BR-007, BR-011, BR-013)
ALTER TABLE employees           ADD CONSTRAINT fk_employees_organisation        FOREIGN KEY (organisation_id)         REFERENCES organisations (organisation_id);
ALTER TABLE vehicles            ADD CONSTRAINT fk_vehicles_organisation         FOREIGN KEY (organisation_id)         REFERENCES organisations (organisation_id);
ALTER TABLE customer_accounts   ADD CONSTRAINT fk_accounts_customer             FOREIGN KEY (customer_id)             REFERENCES customers (customer_id);
ALTER TABLE customer_accounts   ADD CONSTRAINT fk_accounts_organisation         FOREIGN KEY (organisation_id)         REFERENCES organisations (organisation_id);
ALTER TABLE payment_instruments ADD CONSTRAINT fk_instruments_account           FOREIGN KEY (account_id)              REFERENCES customer_accounts (account_id);
ALTER TABLE payment_instruments ADD CONSTRAINT fk_instruments_vehicle           FOREIGN KEY (vehicle_id)              REFERENCES vehicles (vehicle_id);
ALTER TABLE fuel_allowances     ADD CONSTRAINT fk_allowances_employee           FOREIGN KEY (employee_id)             REFERENCES employees (employee_id);
ALTER TABLE fuel_allowances     ADD CONSTRAINT fk_allowances_vehicle            FOREIGN KEY (vehicle_id)              REFERENCES vehicles (vehicle_id);
ALTER TABLE transactions        ADD CONSTRAINT fk_transactions_account          FOREIGN KEY (account_id)              REFERENCES customer_accounts (account_id);
ALTER TABLE fuel_purchases      ADD CONSTRAINT fk_purchases_transaction         FOREIGN KEY (transaction_id)          REFERENCES transactions (transaction_id);
ALTER TABLE fuel_purchases      ADD CONSTRAINT fk_purchases_station             FOREIGN KEY (station_id)              REFERENCES fuel_stations (station_id);
ALTER TABLE fuel_purchases      ADD CONSTRAINT fk_purchases_product             FOREIGN KEY (product_id)              REFERENCES fuel_products (product_id);
ALTER TABLE fuel_purchases      ADD CONSTRAINT fk_purchases_instrument          FOREIGN KEY (instrument_id)           REFERENCES payment_instruments (instrument_id);
ALTER TABLE fuel_purchases      ADD CONSTRAINT fk_purchases_employee            FOREIGN KEY (employee_id)             REFERENCES employees (employee_id);
ALTER TABLE fuel_purchases      ADD CONSTRAINT fk_purchases_vehicle             FOREIGN KEY (vehicle_id)              REFERENCES vehicles (vehicle_id);
ALTER TABLE account_ledger      ADD CONSTRAINT fk_ledger_account                FOREIGN KEY (account_id)              REFERENCES customer_accounts (account_id);
ALTER TABLE account_ledger      ADD CONSTRAINT fk_ledger_transaction            FOREIGN KEY (transaction_id)          REFERENCES transactions (transaction_id);
ALTER TABLE reversals           ADD CONSTRAINT fk_reversals_original            FOREIGN KEY (original_transaction_id) REFERENCES transactions (transaction_id);
ALTER TABLE reversals           ADD CONSTRAINT fk_reversals_reversal            FOREIGN KEY (reversal_transaction_id) REFERENCES transactions (transaction_id);

-- Unique values (BR-001, BR-004, BR-009, BR-011)
ALTER TABLE organisations       ADD CONSTRAINT uq_organisations_rc_number   UNIQUE (rc_number);
ALTER TABLE organisations       ADD CONSTRAINT uq_organisations_email       UNIQUE (email);
ALTER TABLE customers           ADD CONSTRAINT uq_customers_email           UNIQUE (email);
ALTER TABLE customers           ADD CONSTRAINT uq_customers_phone           UNIQUE (phone);
ALTER TABLE employees           ADD CONSTRAINT uq_employees_staff_number    UNIQUE (organisation_id, staff_number);
ALTER TABLE vehicles            ADD CONSTRAINT uq_vehicles_plate_number     UNIQUE (plate_number);
ALTER TABLE customer_accounts   ADD CONSTRAINT uq_accounts_account_number   UNIQUE (account_number);
ALTER TABLE payment_instruments ADD CONSTRAINT uq_instruments_uid           UNIQUE (uid);
ALTER TABLE fuel_stations       ADD CONSTRAINT uq_stations_station_code     UNIQUE (station_code);
ALTER TABLE fuel_products       ADD CONSTRAINT uq_products_name             UNIQUE (name);
ALTER TABLE transactions        ADD CONSTRAINT uq_transactions_idempotency  UNIQUE (idempotency_key);
ALTER TABLE fuel_purchases      ADD CONSTRAINT uq_purchases_transaction     UNIQUE (transaction_id);
ALTER TABLE reversals           ADD CONSTRAINT uq_reversals_original        UNIQUE (original_transaction_id);
ALTER TABLE reversals           ADD CONSTRAINT uq_reversals_reversal        UNIQUE (reversal_transaction_id);

-- Check rules
ALTER TABLE customer_accounts   ADD CONSTRAINT chk_accounts_one_owner            CHECK (num_nonnulls(customer_id, organisation_id) = 1);
ALTER TABLE customer_accounts   ADD CONSTRAINT chk_accounts_balance_non_negative CHECK (balance >= 0);  -- BR-008
ALTER TABLE customer_accounts   ADD CONSTRAINT chk_accounts_status               CHECK (status IN ('active', 'suspended', 'closed'));

ALTER TABLE payment_instruments ADD CONSTRAINT chk_instruments_type              CHECK (instrument_type IN ('card', 'tag'));
ALTER TABLE payment_instruments ADD CONSTRAINT chk_instruments_status            CHECK (status IN ('active', 'blocked', 'expired'));
ALTER TABLE payment_instruments ADD CONSTRAINT chk_instruments_vehicle_tag_only  CHECK (instrument_type = 'tag' OR vehicle_id IS NULL);

ALTER TABLE fuel_products       ADD CONSTRAINT chk_products_price_positive       CHECK (price_per_litre > 0);

ALTER TABLE fuel_allowances     ADD CONSTRAINT chk_allowances_one_target         CHECK (num_nonnulls(employee_id, vehicle_id) = 1);  -- BR-006
ALTER TABLE fuel_allowances     ADD CONSTRAINT chk_allowances_limit_positive     CHECK (limit_amount > 0);
ALTER TABLE fuel_allowances     ADD CONSTRAINT chk_allowances_period             CHECK (period IN ('daily', 'weekly', 'monthly'));

ALTER TABLE transactions        ADD CONSTRAINT chk_transactions_amount_positive  CHECK (amount > 0);
ALTER TABLE transactions        ADD CONSTRAINT chk_transactions_type             CHECK (transaction_type IN ('funding', 'purchase', 'reversal'));
ALTER TABLE transactions        ADD CONSTRAINT chk_transactions_status           CHECK (status IN ('pending', 'successful', 'failed', 'reversed'));  -- BR-010

ALTER TABLE fuel_purchases      ADD CONSTRAINT chk_purchases_litres_positive     CHECK (litres > 0);
ALTER TABLE fuel_purchases      ADD CONSTRAINT chk_purchases_price_positive      CHECK (price_per_litre > 0);

ALTER TABLE account_ledger      ADD CONSTRAINT chk_ledger_entry_type             CHECK (entry_type IN ('debit', 'credit'));
ALTER TABLE account_ledger      ADD CONSTRAINT chk_ledger_amount_positive        CHECK (amount > 0);

ALTER TABLE reversals           ADD CONSTRAINT chk_reversals_not_self            CHECK (original_transaction_id <> reversal_transaction_id);

ALTER TABLE audit_logs          ADD CONSTRAINT chk_audit_action                  CHECK (action IN ('insert', 'update', 'delete'));

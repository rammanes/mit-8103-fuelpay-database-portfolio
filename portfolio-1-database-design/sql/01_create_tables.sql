-- FuelPay Network: tables, keys and data types.
-- Foreign keys, UNIQUE and CHECK rules are added in 02_constraints.sql.
-- Re-running this script drops and recreates every table.

DROP TABLE IF EXISTS
    audit_logs, reversals, account_ledger, fuel_purchases, transactions,
    fuel_allowances, fuel_products, fuel_stations, payment_instruments,
    customer_accounts, vehicles, employees, customers, organisations
CASCADE;

CREATE TABLE organisations (
    organisation_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(150) NOT NULL,
    rc_number       VARCHAR(20)  NOT NULL,
    email           VARCHAR(150) NOT NULL,
    phone           VARCHAR(20),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE customers (
    customer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name  VARCHAR(80)  NOT NULL,
    last_name   VARCHAR(80)  NOT NULL,
    email       VARCHAR(150) NOT NULL,
    phone       VARCHAR(20)  NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE employees (
    employee_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id BIGINT      NOT NULL,
    first_name      VARCHAR(80) NOT NULL,
    last_name       VARCHAR(80) NOT NULL,
    staff_number    VARCHAR(30) NOT NULL,
    is_active       BOOLEAN     NOT NULL DEFAULT true
);

CREATE TABLE vehicles (
    vehicle_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_id BIGINT      NOT NULL,
    plate_number    VARCHAR(15) NOT NULL,
    make            VARCHAR(50),
    model           VARCHAR(50),
    is_active       BOOLEAN     NOT NULL DEFAULT true
);

CREATE TABLE customer_accounts (
    account_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_number  VARCHAR(20)   NOT NULL,
    customer_id     BIGINT,
    organisation_id BIGINT,
    balance         NUMERIC(14,2) NOT NULL DEFAULT 0,
    status          VARCHAR(20)   NOT NULL DEFAULT 'active',
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE payment_instruments (
    instrument_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id      BIGINT      NOT NULL,
    vehicle_id      BIGINT,
    instrument_type VARCHAR(10) NOT NULL,
    uid             VARCHAR(32) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'active',
    issued_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE fuel_stations (
    station_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    station_code VARCHAR(20)  NOT NULL,
    name         VARCHAR(150) NOT NULL,
    city         VARCHAR(80)  NOT NULL,
    state        VARCHAR(50)  NOT NULL
);

CREATE TABLE fuel_products (
    product_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(50)   NOT NULL,
    price_per_litre NUMERIC(10,2) NOT NULL
);

CREATE TABLE fuel_allowances (
    allowance_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id  BIGINT,
    vehicle_id   BIGINT,
    limit_amount NUMERIC(14,2) NOT NULL,
    period       VARCHAR(10)   NOT NULL DEFAULT 'monthly',
    is_active    BOOLEAN       NOT NULL DEFAULT true,
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE transactions (
    transaction_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id       BIGINT        NOT NULL,
    transaction_type VARCHAR(20)   NOT NULL,
    amount           NUMERIC(14,2) NOT NULL,
    status           VARCHAR(20)   NOT NULL DEFAULT 'pending',
    idempotency_key  VARCHAR(64)   NOT NULL,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE fuel_purchases (
    purchase_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_id  BIGINT        NOT NULL,
    station_id      BIGINT        NOT NULL,
    product_id      BIGINT        NOT NULL,
    instrument_id   BIGINT,
    employee_id     BIGINT,
    vehicle_id      BIGINT,
    litres          NUMERIC(10,2) NOT NULL,
    price_per_litre NUMERIC(10,2) NOT NULL,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE account_ledger (
    entry_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id     BIGINT        NOT NULL,
    transaction_id BIGINT        NOT NULL,
    entry_type     VARCHAR(10)   NOT NULL,
    amount         NUMERIC(14,2) NOT NULL,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE reversals (
    reversal_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    original_transaction_id BIGINT      NOT NULL,
    reversal_transaction_id BIGINT      NOT NULL,
    reason                  VARCHAR(255),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_logs (
    audit_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name   VARCHAR(63) NOT NULL,
    record_id    BIGINT      NOT NULL,
    action       VARCHAR(10) NOT NULL,
    details      JSONB,
    performed_by VARCHAR(100),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

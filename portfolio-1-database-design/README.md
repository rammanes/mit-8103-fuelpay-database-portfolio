# Portfolio 1 – Database Design and Modelling

Business rules and design decisions are in [../docs/business-requirements.md](../docs/business-requirements.md).

## Entities

Each table exists because at least one business rule needs it.

| Entity | What it stores | Needed for |
|---|---|---|
| organisations | Companies using FuelPay for their fleet | BR-002, BR-003 |
| customers | Individual customers | BR-001, BR-003 |
| employees | Staff belonging to an organisation | BR-002, BR-006 |
| vehicles | Vehicles registered by an organisation | BR-002, BR-006 |
| customer_accounts | Accounts that hold a balance and pay for fuel | BR-003, BR-008 |
| payment_instruments | NFC cards and tags linked to accounts | BR-004 |
| fuel_stations | Filling stations on the network | BR-007, BR-015 |
| fuel_products | Fuel types (petrol, diesel, etc.) and prices | BR-007, BR-015 |
| fuel_allowances | Spending limits for employees or vehicles | BR-006 |
| fuel_purchases | What was bought: station, product, litres | BR-007, BR-015 |
| transactions | Money movements: amount, status, idempotency reference | BR-005, BR-009, BR-010 |
| account_ledger | Debit and credit entries behind every balance change | BR-008, BR-012 |
| reversals | Links a reversed transaction to its reversal | BR-011 |
| audit_logs | Record of important actions | BR-012 |

**Purchases vs transactions:** a purchase records what happened at the pump; a transaction records the money. Funding an account creates a transaction without a purchase, so they're kept separate.

Left out on purpose:
- **station_inventory**: no requirement needs fuel stock levels. Fuel use reports come from purchases.
- **settlements**: paying stations is a separate process that none of the requirements cover.

## Relational schema

All primary keys are auto-generated IDs. Money is `NUMERIC(14,2)` (exact, no rounding errors). Times are `TIMESTAMPTZ`.

- **organisations**: `organisation_id` PK, `name`, `rc_number` UNIQUE, `email` UNIQUE, `phone`, `created_at`
- **customers**: `customer_id` PK, `first_name`, `last_name`, `email` UNIQUE, `phone` UNIQUE, `created_at`
- **employees**: `employee_id` PK, `organisation_id` FK, `first_name`, `last_name`, `staff_number`, `is_active`. UNIQUE (`organisation_id`, `staff_number`)
- **vehicles**: `vehicle_id` PK, `organisation_id` FK, `plate_number` UNIQUE, `make`, `model`, `is_active`
- **customer_accounts**: `account_id` PK, `account_number` UNIQUE, `customer_id` FK (nullable), `organisation_id` FK (nullable), `balance` CHECK (>= 0), `status` (active / suspended / closed), `created_at`
- **payment_instruments**: `instrument_id` PK, `account_id` FK, `vehicle_id` FK (nullable, tags only), `instrument_type` (card / tag), `uid` UNIQUE, `status` (active / blocked / expired), `issued_at`
- **fuel_stations**: `station_id` PK, `station_code` UNIQUE, `name`, `city`, `state`
- **fuel_products**: `product_id` PK, `name` UNIQUE, `price_per_litre` CHECK (> 0)
- **fuel_allowances**: `allowance_id` PK, `employee_id` FK (nullable), `vehicle_id` FK (nullable), `limit_amount` CHECK (> 0), `period` (daily / weekly / monthly, default monthly), `is_active`, `created_at`
- **transactions**: `transaction_id` PK, `account_id` FK, `transaction_type` (funding / purchase / reversal), `amount` CHECK (> 0), `status` (pending / successful / failed / reversed), `idempotency_key` UNIQUE, `created_at`
- **fuel_purchases**: `purchase_id` PK, `transaction_id` FK UNIQUE, `station_id` FK, `product_id` FK, `instrument_id` FK (nullable, app payments have none), `employee_id` FK (nullable), `vehicle_id` FK (nullable), `litres` CHECK (> 0), `price_per_litre`, `created_at`
- **account_ledger**: `entry_id` PK, `account_id` FK, `transaction_id` FK, `entry_type` (debit / credit), `amount` CHECK (> 0), `created_at`
- **reversals**: `reversal_id` PK, `original_transaction_id` FK UNIQUE, `reversal_transaction_id` FK UNIQUE, `reason`, `created_at`
- **audit_logs**: `audit_id` PK, `table_name`, `record_id`, `action` (insert / update / delete), `details` JSONB, `performed_by`, `created_at`

### Rules across columns

- An account has exactly one owner: a customer or an organisation.
- An allowance targets exactly one of an employee or a vehicle.
- Only tags can be linked to a vehicle; cards can't.
- A transaction can be reversed only once (UNIQUE on `original_transaction_id`).

### Why some columns are (or aren't) there

- **Price is stored on each purchase** because product prices change. The purchase must keep the price actually paid.
- **fuel_purchases has no account_id**; the account comes through its transaction. Storing it twice would let the two disagree.
- **fuel_allowances has no organisation_id**; the organisation comes through the employee or vehicle, for the same reason.

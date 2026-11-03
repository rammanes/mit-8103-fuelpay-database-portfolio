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

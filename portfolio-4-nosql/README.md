# Portfolio 4 – NoSQL and Advanced Data Models

## What goes in MongoDB, and why

FuelPay keeps money in PostgreSQL. Accounts, transactions and the ledger need constraints, joins and multi-row ACID transactions, as Portfolios 1 and 3 showed.

Two kinds of FuelPay data don't fit fixed tables well, so they go in MongoDB (a document database):

| Collection | What it holds | Why a document model suits it |
|---|---|---|
| `payment_events` | One document per payment attempt with its full event history from the card reader or app (tap, PIN, timeout, authorised, pump started/stopped, receipt) | The number and type of events differ for every payment, and each channel sends different device details. The whole history is read together, so it is stored together |
| `pump_telemetry` | Readings sent by pumps at each station | Each pump model sends different readings (PX-100 sends flow rate only, PX-300 adds temperature and tank level), and alerts appear only sometimes. New models can add fields without a schema change |

The two databases are linked by value: `payment_events.transaction_ref` holds the `idempotency_key` of the PostgreSQL transaction, and account and station codes are the same as in PostgreSQL. This setup is called polyglot persistence: each database holds the data it handles best.

## Document model

An NFC tag payment (from [evidence/query-results.txt](evidence/query-results.txt), Q1):

```js
{
  transaction_ref: 'PUR-00000007',      // = transactions.idempotency_key in PostgreSQL
  account_number: 'FPC0000006',
  station_code: 'STN-017',
  channel: 'nfc_tag',
  outcome: 'approved',
  device: { reader_id: 'RDR-017-1', firmware: '3.2.0', vehicle_plate: 'FP016KJA' },
  events: [
    { type: 'tag_read', at: ... },
    { type: 'authorised', at: ... },
    { type: 'pump_started', at: ... },
    { type: 'pump_stopped', at: ..., litres: 28.45 },
    { type: 'receipt_printed', at: ... }
  ]
}
```

A mobile app payment in the same collection has a different `device` (platform, app version, phone model), a `location`, and different events (`app_opened`, `qr_scanned`, `otp_verified`). In PostgreSQL this would need either many nullable columns or a separate events table and device tables joined on every read.

**Embedding vs referencing.** Events are embedded because they belong to one payment, are always read with it, and a payment has a small, bounded number of them. Accounts and stations are referenced by code, not embedded, because they are shared and already live in PostgreSQL.

## Implementation

MongoDB 8.2 runs in Docker next to PostgreSQL (`docker-compose.yml`), on port 27018 because a local MongoDB already uses 27017. Version 8.0 was tried first but refuses to start on Docker Desktop's Linux kernel 7.0.x, so 8.2 is used.

| Script | What it does |
|---|---|
| [mongo/01_setup.js](mongo/01_setup.js) | Creates both collections with `$jsonSchema` validation rules and indexes. Output: [evidence/setup.txt](evidence/setup.txt) |
| [mongo/02_load_data.js](mongo/02_load_data.js) | Loads 2,000 payment documents (30 days) and 1,000 telemetry documents (7 days). Output: [evidence/load.txt](evidence/load.txt) |
| [mongo/03_queries.js](mongo/03_queries.js) | Nine queries. Output: [evidence/query-results.txt](evidence/query-results.txt) |

## Queries and results

| Query | What it shows |
|---|---|
| Q1 full history of one payment | One read returns everything. No joins |
| Q2 app payment vs tag payment | Documents in one collection with different fields |
| Q3 declined payments by reason | `$unwind` on the embedded events array, then `$group` |
| Q4 approval rate and timeouts per channel | Conditional counting inside an aggregation |
| Q5 seconds from start to authorisation | Tag about 14 s, card about 33 s, app about 73 s: card PINs and app OTPs slow checkout |
| Q6 pump alerts | Querying a field that only some documents have (`$exists`) |
| Q7 readings per pump model | Tank level averages only over PX-300, the only model that sends it |
| Q8 index use | `IXSCAN` on (station_code, started_at): 22 documents examined out of 2,000 |
| Q9 validation | A payment with an empty events array is rejected by the schema rule |

## Flexible does not mean unchecked

MongoDB doesn't force a schema, but FuelPay adds one where it matters. The `$jsonSchema` validator requires the fields every payment must have, limits `channel` and `outcome` to known values, and requires at least one event (Q9). Everything else, such as device details and extra readings, is free to vary. The unique index on `transaction_ref` stops the same payment being logged twice, which mirrors the idempotency key in PostgreSQL.

## Why money stays in PostgreSQL

MongoDB supports transactions, but the ledger depends on things PostgreSQL does better: foreign keys between accounts, transactions and ledger entries, CHECK rules like balance ≥ 0, and joins for reports such as corporate spending. Event logs and telemetry need none of these. They are written once, never updated, read whole, and their shape keeps changing.

## How to reproduce

From the repo root:

```bash
docker compose up -d
for f in portfolio-4-nosql/mongo/0*.js; do
  docker exec -i fuelpay-mongo mongosh --quiet --file /dev/stdin < "$f"
done
```

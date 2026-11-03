# Business Requirements

These are the rules the FuelPay database has to follow. For each one I've noted how the database will enforce it, so I can test it later.

| ID | Rule | How it's enforced |
|---|---|---|
| BR-001 | Every customer has a unique ID and a profile. | Primary key, unique email and phone |
| BR-002 | An organisation can have many employees and vehicles. | Foreign keys to organisations |
| BR-003 | A customer can have more than one account. | Foreign key from accounts to the owner |
| BR-004 | Accounts can have NFC cards or tags, each with a unique ID. | Foreign key to accounts, unique card/tag ID |
| BR-005 | Accounts can be funded. | Funding saved as a transaction plus a ledger credit |
| BR-006 | Organisations can set fuel limits for staff or vehicles. | Foreign keys, limit must be greater than 0 |
| BR-007 | A purchase must point to a real account, station and fuel product. | Foreign keys, not null |
| BR-008 | A payment can't take a balance below zero. | CHECK (balance >= 0), conditional update in a transaction |
| BR-009 | The same payment can't be processed twice. | Unique idempotency reference |
| BR-010 | A transaction is pending, successful, failed or reversed. | CHECK on status |
| BR-011 | Reversals keep the original transaction. | Separate reversals table, original row never deleted |
| BR-012 | Financial actions can be traced. | Ledger entries are never edited, audit log table |
| BR-013 | Relationships and data must always be valid. | All the constraints above |
| BR-014 | Two payments at the same time can't break the balance. | Transactions and row locking (tested in Portfolio 3) |
| BR-015 | Reports: customer history, company spending, station activity, fuel use. | Joins, aggregates and indexes (Portfolio 2) |

## Balances and the ledger

The balance is never changed on its own. Every change also adds a ledger entry in the same database transaction, so the history is always there and the balance can be rebuilt from the ledger.

## Still to decide

- Does a company account belong to the organisation, or does each employee get their own?
- Are fuel limits set per employee, per vehicle, or either?
- Are limits daily, weekly or monthly?
- Is an NFC tag tied to a vehicle as well as an account?

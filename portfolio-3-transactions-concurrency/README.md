# Portfolio 3 – Transactions and Concurrency

Every demo creates its own customer account funded with ₦20,000, so the Portfolio 1 data is not touched. A payment always does three things together: insert the transaction, insert the ledger debit, and reduce the balance. Those three steps have to succeed or fail as one unit.

## 1. COMMIT and ROLLBACK

Script: [sql/01_commit_rollback.sql](sql/01_commit_rollback.sql). Output: [evidence/commit-rollback.txt](evidence/commit-rollback.txt).

| Step | What happens | Result |
|---|---|---|
| COMMIT | ₦5,000 diesel purchase: transaction, pump record, ledger debit, balance update, then COMMIT | Balance ₦15,000, payment saved |
| ROLLBACK | ₦3,000 payment started. Inside the transaction the balance shows ₦12,000, then ROLLBACK | Balance back to ₦15,000, no payment saved |
| Automatic rollback | ₦50,000 payment. The transaction row and ledger entry are inserted, then the balance update breaks `chk_accounts_balance_non_negative` | The whole transaction is rolled back. No transaction row, no ledger entry (atomicity) |
| Duplicate request | Payment 1 is retried with the same idempotency key | Rejected by `uq_transactions_idempotency`, customer charged once |

The automatic rollback is the important one. The first two inserts had succeeded, but because they were in the same transaction as the failed update, PostgreSQL threw all of them away. Without a transaction the database would have a payment and a ledger debit for money that was never taken.

## 2. The ₦20,000 concurrent payment problem

Script: [sql/02_concurrency_demo.sh](sql/02_concurrency_demo.sh). Output: [evidence/concurrency-demo.txt](evidence/concurrency-demo.txt).

Scenario: an account has ₦20,000. Two stations try to take ₦15,000 at almost the same moment (session B starts half a second after A). Only one of them should succeed.

**Scenario 1, no concurrency control.** Each session reads the balance, checks it is enough, and writes back `balance - 15000`, the way a simple application would.

- Both sessions read ₦20,000, both decide there is enough, both commit.
- The final balance is ₦5,000, but the ledger has two ₦15,000 debits and works out to **−₦10,000**.
- This is a **lost update**: session B overwrote A's change. The customer got ₦30,000 of fuel from ₦20,000. The CHECK constraint didn't catch it, because the value written (₦5,000) was not negative. Constraints alone can't stop this.
- The demo account is left in this broken state on purpose, as evidence. Re-running the Portfolio 1 data checks afterwards will report it as a balance that doesn't match its ledger.

**Scenario 2, `SELECT ... FOR UPDATE`.** Each session locks the account row before reading the balance.

- Session A gets the lock and sees ₦20,000.
- Session B asks for the lock and **waits about 1.5 seconds** until A commits (visible in the timestamps).
- B then reads the new balance, ₦5,000, and declines the payment.
- The final balance is ₦5,000, the ledger agrees, and only one payment was recorded. This is BR-014.

A row lock only blocks other transactions that want the same account row. Payments on different accounts still run in parallel.

## 3. Isolation levels

Same script, scenario 3. Session A reads the balance twice in one transaction. Session B pays ₦15,000 and commits between the two reads.

| | READ COMMITTED (PostgreSQL default) | REPEATABLE READ |
|---|---|---|
| First read | ₦20,000 | ₦20,000 |
| Second read (after B committed) | ₦5,000 | ₦20,000 |
| A then tries to take ₦10,000 | Re-checks the new row, `balance >= 10000` is false, 0 rows updated | `ERROR: could not serialize access due to concurrent update` |

- **READ COMMITTED** lets each statement see the latest committed data, so the same query can return different results within one transaction (a non-repeatable read).
- **REPEATABLE READ** gives the whole transaction one snapshot, so both reads match. If the transaction then tries to change a row someone else changed, PostgreSQL refuses rather than act on old data, and the application has to retry.

For FuelPay, READ COMMITTED with `SELECT ... FOR UPDATE` (or a conditional `UPDATE ... WHERE balance >= amount`, as session B uses in scenario 3) is enough for payments. REPEATABLE READ suits reports that need a consistent picture, such as end-of-day totals.

## How to reproduce

From the repo root, after Portfolio 1 has been loaded:

```bash
docker exec -i fuelpay-postgres stdbuf -oL -eL psql -U fuelpay -d fuelpay -X < portfolio-3-transactions-concurrency/sql/01_commit_rollback.sql
bash portfolio-3-transactions-concurrency/sql/02_concurrency_demo.sh
```

`stdbuf` keeps psql's normal output and error messages in the right order when the output is saved to a file.

# Solutions · Lab 09

**Part A:** one session gets `ERROR: deadlock detected` (~1s later — that's
`deadlock_timeout`), the other proceeds. The DETAIL line names the two processes and
the statements; from the observer query you see one pid with `wait_event_type=Lock`
and `pg_blocking_pids` pointing at the other. Detection is periodic, not instant,
because the probe runs `deadlock_timeout` after a wait begins.

**Part B:** no deadlock — session B simply waits on order 100 while A finishes, then
proceeds. Consistent ordering turns circular wait into a queue. Team convention
required because the database can't know your intended order; row locks are granted
in arrival order.

**Part C:** single-statement transactions break hold-and-wait (Coffman #2): the
lock and the mutation are atomic, nothing to hold-and-wait *with*. Not always
applicable (multi-row business ops), which is why D exists.

**Part D:** locking both rows up front in sorted order makes the lock set
transaction-wide and ordered — the classic multi-row protocol; pairs with the
application locking the same entities in the same order (order id here).

**Part E:** the collision: A holds FOR KEY SHARE on order 101? No — trace it: A
inserts item → KEY SHARE on order 100; B inserts item → KEY SHARE on order 101;
A's `UPDATE orders id=101` needs to bump... wait, the classic collision is:
B's INSERT→order 101 wants FOR KEY SHARE on order 101, which conflicts with A's
UPDATE of order 101 (row exclusive), while A's INSERT wants KEY SHARE on order 100,
conflicting with B's UPDATE of order 100. Circular: A(update 101) ← B(insert 101)
← B(update 100) ← A(insert 100) ← A(update 101). The FK's KEY SHARE is what makes
child inserts participate in the wait graph — parent UPDATEs and child INSERTs on
the same parent row do not compose freely.

**Exercises:**

1. `ALTER ROLE app SET deadlock_timeout = '200ms';` (faster victim selection) and
   `ALTER ROLE app SET lock_timeout = '5s';` (fail fast instead of piling up).
   They change blast radius (fewer piled-up connections, quicker retries), not the
   circular-wait itself — only code-level lock ordering fixes the cause.
2. Two sessions each `SELECT ... FOR UPDATE` row A1/A2 in opposite order — deadlock
   arises even though neither has *written* yet (locks are taken at read time).
   Fix with Part D (lock both, ordered, up front).
3. Retrying a deadlock re-runs a transaction that was *legal but unlucky* — the work
   itself was fine. Retrying a constraint violation re-runs work that is *wrong*
   (the invariant says no): the app must handle it as a business outcome (409,
   idempotency return), not an accident. Otherwise you're building a random retry
   generator on top of a rule that will never pass.

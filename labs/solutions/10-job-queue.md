# Solutions · Lab 10

**Part B:** with SKIP LOCKED, two workers claim *different* ids simultaneously —
each claim transaction sees only unlocked pending rows. Plain FOR UPDATE: worker B
blocks on the row A claimed (same id each time) — the queue serialises and the
second worker idles: a self-inflicted outage under load.

**Part C:**
- Without `run_after` filtering: jobs scheduled for the future would be claimed
  immediately (retry backoff impossible).
- Recovery while a worker is mid-job: its 'processing' row flips to 'pending' and a
  *second* worker claims the same job → double send. Mitigations: heartbeat/lease
  extension (worker updates locked_at periodically), longer timeout than worst-case
  job, or idempotent handlers (dedupe key at the SMTP/provider layer).

**Part D:** statuses converge to done/failed with pending shrinking; zero Lock waits
in pg_stat_activity — workers never contend.

**Exercises:**

1. Batch of 10: claim all with one CTE (`LIMIT 10`); if one fails, per-row status
   (each row marked failed individually, others proceed) beats batch abort — unless
   the batch has atomic semantics (e.g. one email per order), in which case abort and
   requeue all with attempt+1. Decide per job type; write it in the queue table
   (a `batch_id` column makes requeueing sane).
2. Add `priority int NOT NULL DEFAULT 100` (lower = sooner); the reset-worker claim
   adds `AND priority = 0` (or `ORDER BY priority, id`) — served by a partial index:
   `CREATE INDEX ... ON email_queue (run_after, id) WHERE status='pending' AND priority = 0;`
   (partial indexes per priority class beat one giant index here).
3. Claim: exactly once (row lock + status flip is atomic). Processing: at-least-once
   (crash between claim and side-effect → retry after recovery → duplicate send).
   The gap between the two is *exactly* the idempotency requirement on the handler;
   no queue can close it for you.
4. Migrate away when: fan-out/consumer scaling outgrows one writer (Postgres queue
   rows become the bottleneck), or retention/replay semantics are needed (Kafka), or
   long-poll latency SLAs force dedicated infra (SQS). Stay when: jobs are a feature
   of an OLTP flow needing transactional consistency with business data (one
   transaction = job + state change is the superpower Postgres queues have that
   external queues lack).

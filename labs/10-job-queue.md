# Lab 10 · A real job queue with FOR UPDATE SKIP LOCKED

**Sessions:** three (two workers + one observer). **Goal:** the pattern behind every
"background worker pulls jobs from Postgres" system you will ever maintain.

## Part A — build the queue

```sql
CREATE TABLE email_queue (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payload    text NOT NULL,
  status     text NOT NULL DEFAULT 'pending'
             CHECK (status IN ('pending', 'processing', 'done', 'failed')),
  attempts   integer NOT NULL DEFAULT 0,
  run_after  timestamptz NOT NULL DEFAULT now(),
  locked_at  timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_email_queue_due ON email_queue (run_after)
  WHERE status = 'pending';

INSERT INTO email_queue (payload)
SELECT 'send order confirmation ' || g FROM generate_series(1, 50) g;
```

## Part B — the worker claim query

Both sessions run this simultaneously, over and over:

```sql
WITH next_job AS (
  SELECT id FROM email_queue
  WHERE status = 'pending' AND run_after <= now()
  ORDER BY id
  LIMIT 1
  FOR UPDATE SKIP LOCKED
)
UPDATE email_queue e
SET status = 'processing', attempts = attempts + 1, locked_at = now()
FROM next_job
WHERE e.id = next_job.id
RETURNING e.id, e.payload;
```

Watch what happens: neither worker ever blocks or errors — they just get *different*
jobs. That is `SKIP LOCKED`: "give me any row I don't have to wait for". Compare with
plain `FOR UPDATE` (remove SKIP LOCKED): now workers block each other and the queue
serialises — the bug this pattern exists to prevent.

## Part C — completion, failure, and the visibility timeout

```sql
-- success:
UPDATE email_queue SET status = 'done' WHERE id = <claimed id> AND status = 'processing';

-- crash recovery (a worker died mid-job): rows stuck in 'processing' for too long
-- are made claimable again — the "visibility timeout":
UPDATE email_queue
   SET status = 'pending'
 WHERE status = 'processing'
   AND locked_at < now() - interval '5 minutes'
   AND attempts < 5;

-- poison message handling:
UPDATE email_queue SET status = 'failed'
 WHERE status = 'processing' AND attempts >= 5;
```

Argue with your partner: what breaks if `run_after` is missing from the claim query?
What breaks if the recovery UPDATE above runs *while* a legitimate worker is mid-job
on a slow SMTP call? (This is why real queues add heartbeats or lease extensions.)

## Part D — the observer

While both workers hammer the claim query, from the third session:

```sql
SELECT status, count(*) FROM email_queue GROUP BY status ORDER BY 2 DESC;
SELECT pid, wait_event_type, left(query, 60)
FROM pg_stat_activity WHERE state = 'active' AND query LIKE '%email_queue%';
-- Zero 'Lock' waits expected. That is the point.
```

## Exercises

1. Change the claim to process **batches of 10**. What breaks if one job in the batch fails? Design the failure semantics (per-row status vs batch abort).
2. Make jobs **prioritised**: two classes (bulk newsletters vs password resets) served from one table. What index serves the password-reset worker's claim query?
3. Prove exactly-once *claim* but at-least-once *processing*: explain the difference in one paragraph, using the crash-recovery UPDATE as your example.
4. When do you abandon Postgres queues for SQS/Kafka? Give one concrete symptom per system that would trigger the migration, and one counter-argument for staying.

**Solutions:** [solutions/10-job-queue.md](solutions/10-job-queue.md)

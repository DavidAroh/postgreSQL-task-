# Workbook · Advanced Database Engineering & Data Modelling

Your four-week path through this module. Each week: read the docs, do the labs in
order, write the answers in a notes file. Everything runs on your local container —
`./scripts/reset.sh` any time you break something.

## Week 1 — Model it before you tune it

**Read:** docs/01 (architecture), docs/02 (modelling), docs/03 (constraints).
**Study the schema:** read every file in `sql/migrations/` *before* running it. For
each file, write down one question (e.g. "why is carts.user_id not a FK?"). Most
questions are answered in the docs; bring the rest to your mentor.

**Do:**
- Lab 01 (constraints).
- Draw the ER diagram by hand from the migrations. Check it against lab 12's checklist.
- The modelling exercise at the end of docs/02 (course platform). Show it to someone
  and let them attack it.

**Gate to pass:** you can explain, without notes, why `order_items` snapshots exist,
what `DEFERRABLE INITIALLY DEFERRED` does, and why "one default address per user" is
a partial unique index and not a trigger.

## Week 2 — Make the plans legible

**Read:** docs/04 (indexing), docs/05 (plans & optimisation).
**Do:** Lab 02 (indexing drill), Lab 03 (plans), Lab 04 (joins/skew).
Seed the database, run every `EXPLAIN (ANALYZE, BUFFERS)` yourself — no reading
someone else's output.

**Gate:** given a slow query on this schema, your first three moves are written into
your notes (hint: sargability, statistics, join shape). You can explain `loops=`,
`rows removed by filter`, and why the second run is faster than the first.

## Week 3 — Concurrency is the exam

**Read:** docs/06 (transactions & concurrency).
**Do:** Labs 05, 06, 07, 08 — two psql sessions side by side, no shortcuts. The lost
update in lab 06 and the oversell in lab 07 are the two experiences this module
exists for. Write the checkout function in lab 05 and *run the concurrent test*.

**Gate:** for any read-modify-write flow, you can pick between atomic predicate
UPDATE, FOR UPDATE, and version columns, and say in one sentence why. You have seen
`could not serialize access` at least once and know what to do about it.

## Week 4 — Production reality

**Read:** docs/07 (operations).
**Do:** Lab 09 (deadlocks), Lab 10 (SKIP LOCKED queue), Lab 11 (soft delete/audit),
then the Lab 12 capstone and its one-page `REVIEW.md`.

**Gate:** you can whiteboard the zero-downtime migration for "add loyalty tier",
name the four Coffman conditions and their practical cures, and explain why a
2-worker queue with `FOR UPDATE` (no SKIP) is a self-inflicted outage.

---

## Final deliverable

`REVIEW.md` (lab 12) + a 30-minute walkthrough session with your mentor covering:

1. your ER diagram and two modelling decisions you would revisit;
2. one query you made fast, with before/after plans;
3. the checkout transaction and its concurrency argument;
4. the job queue and its failure semantics;
5. your GDPR-by-transaction design from lab 11.

**Grading rubric (what "advanced" actually means here):**

| Claim quality | Evidence |
|---|---|
| Intern | "I added an index and it got faster." |
| Engineer | "The plan read 24,800 rows to return 12; the rewrite reads 13; here are both plans." |
| Senior | "…and the rewrite costs 4% more on writes, which is acceptable at our update rate; the alternative (materialised view) would push staleness onto the dashboard, which the PM rejected on 3 May." |

The rubric is not a joke: the difference between the rows is *measured trade-offs
stated out loud*, and that is the entire skill this module teaches.

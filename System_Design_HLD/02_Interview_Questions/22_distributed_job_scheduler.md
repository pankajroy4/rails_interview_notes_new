# Design a Distributed Job Scheduler

## Problem Statement

"Design a distributed job scheduling system — something like a company-wide cron replacement or a lightweight Airflow. Teams register jobs with a schedule (e.g. 'run every day at 2am,' or a cron expression), and the system must trigger each job at the right time, run it reliably, retry it on failure, and — critically — never run the same scheduled occurrence twice even though the scheduler itself runs on multiple machines for high availability. How would you build this?"

The interviewer is probing whether you understand that the hard part of a distributed scheduler isn't the scheduling math (cron parsing is a solved problem) — it's coordination. The moment you have more than one scheduler process for availability, you've created a distributed-locking problem: two nodes must never both believe they're the one responsible for firing a given job occurrence.

## Step 1: Clarify Requirements

**Functional Requirements**
- Users/services register jobs with a schedule: either a cron expression (`0 2 * * *`) or a fixed interval, plus a target action (e.g. an HTTP webhook to call, or a task payload to enqueue).
- The system triggers each job at its scheduled time, exactly once per occurrence.
- Support retries with backoff on failure, up to a configurable max attempt count.
- Support one-off (non-recurring) scheduled jobs ("run this once at 3pm tomorrow") in addition to recurring ones.
- Users can query job status/history: last run time, last result, next scheduled run.
- Users can pause, resume, and delete jobs.
- Configurable behavior for missed occurrences (system was down when the job was due) — catch up immediately vs skip to next occurrence.

**Non-Functional Requirements**
- Scale: 1 million registered jobs across the company, with schedules ranging from "every minute" to "once a year."
- Trigger accuracy: jobs should fire within a small tolerance of their scheduled time (e.g. within 5-10 seconds) — this is not a hard-real-time system, but minute-level drift would be unacceptable for many use cases.
- Exactly-once TRIGGERING semantics (a given occurrence must not be double-fired by two racing scheduler nodes), even though the downstream job EXECUTION itself is only guaranteed at-least-once (a worker can crash mid-job and the job gets retried) — this distinction matters and is discussed in Step 6.
- High availability: the scheduler must survive individual node failure without missing scheduled triggers or duplicating them.
- Durability: job definitions and schedules must survive a full scheduler restart with zero loss.
- Isolation: one slow or misbehaving job must not delay or block other jobs from being noticed and triggered on time.
- Horizontal scalability of execution: the number of jobs actually running concurrently should scale independently from the number of scheduler nodes deciding what's due.

## Step 2: Back-of-Envelope Estimation

**Assumptions**
- 1 million registered jobs.
- Average job frequency: assume a mix, but a reasonable blended average of one trigger every 15 minutes per job (many jobs are hourly/daily, some are per-minute, weighted toward less-frequent).

**Trigger rate**
- 1,000,000 jobs / 15 minutes ≈ 66,667 triggers/minute ≈ 1,111 triggers/second average.
- Peak concentration matters more than average here: cron-style schedules cluster heavily at round times (midnight, on-the-hour, top-of-minute). If even 10% of jobs are hourly and all scheduled for the top of the hour, that's 100,000 jobs wanting to fire within the same 60-second window — 1,667 triggers/second sustained for that minute, an order of magnitude above the blended average. The design must handle this clustering, not just the smoothed average (Step 6 addresses spreading load).

**Scanning cost**
- The scheduler must periodically scan for "jobs whose next_run_time <= now." If job definitions live in a database with an index on `next_run_time`, a scan every 5 seconds for due jobs against a 1M-row table with a B-tree index on that column is cheap — the index directly gives the relevant range, not a full table scan; expect low tens of milliseconds even at this scale.

**Storage**
- Each job definition: job_id, cron expression, next_run_time, last_run_time, retry policy, payload/webhook target ≈ 1 KB including a moderate payload.
- 1M jobs x 1 KB ≈ 1 GB — trivially fits in a standard relational or document database, no exotic storage needed for job definitions themselves.

**Execution history**
- If each job run is logged (start time, end time, result, attempt number): 66,667 runs/minute x 1440 minutes/day ≈ 96M runs/day.
- Each history record ≈ 200 bytes → 96M x 200 bytes ≈ 19 GB/day. Over 90 days of retention (a reasonable default before archival) ≈ 1.7 TB — a job worth putting in a horizontally-scalable store (e.g. a wide-column or time-series-oriented database) rather than the same relational store holding job definitions, since it's write-heavy, append-only, and time-partitioned in access pattern.

## Step 3: High-Level Design

**Core components**
- **Job Definition Store**: durable database holding every job's schedule, next-run-time, retry policy, and target action. Source of truth — never in-memory only.
- **Scheduler Nodes** (multiple, for HA): periodically scan the Job Definition Store for jobs due to run, and for each due job, attempt to CLAIM it before triggering execution.
- **Distributed Lock / Claim Store** (e.g. a table with a conditional write, or a dedicated coordination service like the ones discussed in `09_distributed_systems_core.md`): provides the atomic compare-and-swap primitive scheduler nodes use to claim a specific occurrence.
- **Work Queue** (e.g. Kafka/SQS, per `10_message_queues_and_streaming.md`): due jobs are pushed here by the scheduler, not executed inline.
- **Execution Workers**: a horizontally-scalable pool that consumes from the work queue and actually performs the job's action (call a webhook, run a task), independent of and decoupled from the scheduler nodes.
- **Job History/Status Store**: records each execution attempt's outcome for observability and for the retry logic to consult.

**Data flow**
1. User registers a job via the API → written to the Job Definition Store with a computed `next_run_time`.
2. Every few seconds, each Scheduler Node runs a scan query: `SELECT * FROM jobs WHERE next_run_time <= now() AND status = 'active' LIMIT batch_size`.
3. For each candidate due job, the Scheduler Node attempts an atomic claim: `UPDATE jobs SET locked_by = my_node_id, locked_until = now() + lease_ttl WHERE job_id = ? AND (locked_by IS NULL OR locked_until < now()) AND next_run_time = ?` — a conditional write that only succeeds for exactly one racing node.
4. On successful claim, the Scheduler Node pushes a `JobTriggered{job_id, occurrence_time}` message to the Work Queue and advances the job's `next_run_time` to its next occurrence (computed from the cron expression).
5. Execution Workers consume from the Work Queue, run the job's action, and write the result to the History Store, releasing the claim/lock.
6. On failure, the worker (or a separate retry-scheduling component) re-enqueues the job per its retry policy with backoff.

```text
                        +----------------------------+
   User/Service  -----> |  Job Registration API       |
                        +--------------+---------------+
                                       |
                                       v
                        +----------------------------+
                        |  Job Definition Store        |
                        |  (job_id, cron, next_run,    |
                        |   retry_policy, lock fields)  |
                        +---------------+--------------+
                            ^           |   ^
                    scan/claim|         |   |scan/claim
                            |          |    |
              +-------------+---+     |   +-+---------------+
              | Scheduler Node A |<----+-->| Scheduler Node B |
              +--------+---------+         +---------+--------+
                       |                              |
                       +--------------+---------------+
                                      v
                        +----------------------------+
                        |     Work Queue (Kafka)       |
                        +---------------+---------------+
                                        |
                    +-------------------+-------------------+
                    v                   v                    v
            +---------------+  +---------------+    +---------------+
            | Exec Worker 1  |  | Exec Worker 2  |    | Exec Worker N  |
            +-------+--------+  +-------+--------+    +-------+--------+
                    |                   |                     |
                    +---------+---------+----------+----------+
                              v
                    +----------------------------+
                    |   Job History / Status Store |
                    +----------------------------+
```

## Step 4: API Design

**`POST /jobs`**
```
Request: {
  "name": "daily-report-email",
  "schedule": "0 2 * * *",
  "action": { "type": "http", "url": "https://internal/reports/send", "method": "POST" },
  "retry_policy": { "max_attempts": 3, "backoff": "exponential", "base_delay_sec": 30 },
  "missed_run_policy": "skip"
}
Response: { "job_id": "job_8891", "next_run_time": "2026-09-14T02:00:00Z" }
```

**`GET /jobs/{job_id}`**
```
Response: {
  "job_id": "job_8891", "status": "active",
  "next_run_time": "2026-09-14T02:00:00Z",
  "last_run": { "time": "2026-09-13T02:00:00Z", "result": "success", "attempts": 1 }
}
```

**`PUT /jobs/{job_id}/pause`** / **`PUT /jobs/{job_id}/resume`**
```
Response: { "job_id": "job_8891", "status": "paused" }
```

**`DELETE /jobs/{job_id}`**
```
Response: { "job_id": "job_8891", "status": "deleted" }
```

**`GET /jobs/{job_id}/history?limit=20`**
```
Response: { "job_id": "job_8891", "runs": [
  { "occurrence_time": "2026-09-13T02:00:00Z", "started_at": "...", "finished_at": "...", "result": "success", "attempt": 1 }
]}
```

**`POST /jobs/one-off`**
```
Request: { "run_at": "2026-09-13T15:00:00Z", "action": { "type": "http", "url": "..." } }
Response: { "job_id": "job_9910", "next_run_time": "2026-09-13T15:00:00Z" }
```

## Step 5: Data Model

**Job definitions — relational database (e.g. Postgres)**
```
Table: jobs
  job_id            (PK)
  name
  cron_expression
  next_run_time     (indexed — this is the scan column)
  status            (active | paused | deleted)
  retry_policy      (JSON: max_attempts, backoff strategy)
  missed_run_policy (catch_up | skip)
  action_payload    (JSON: webhook URL / task type / args)
  locked_by         (nullable — current claiming scheduler node)
  locked_until      (nullable — lease expiry)
```
- Relational chosen deliberately: job definitions need the atomic conditional-write semantics of a transactional database for the claim mechanism (an `UPDATE ... WHERE` compare-and-swap), a moderate write rate relative to their read/scan pattern, and strong consistency (a stale read of `next_run_time` could cause a double-trigger). This is a case where relational's transactional guarantees are worth more than a NoSQL store's raw throughput, because correctness of the claim is the whole point of the system.
- The `next_run_time` index is the single most important index in the system — every scheduler scan hits it.

**Execution history — wide-column / time-series-oriented store (e.g. Cassandra, or a time-series DB)**
```
Table: job_runs
  job_id           (partition key)
  occurrence_time  (clustering key, descending)
  started_at
  finished_at
  result           (success | failure | timeout)
  attempt_number
  worker_id
```
- Chosen because this is high-volume, append-only, time-partitioned, read mostly by "recent history for job X" — a pattern wide-column stores handle far more cheaply at this write volume (per the ~96M runs/day estimate) than a relational table would, and it doesn't need cross-row transactional guarantees the way the claim mechanism does.

## Step 6: Deep Dive

### 6.1 Durable Job Storage, Not In-Memory Scheduler State

A tempting naive design keeps job schedules in-memory on a single scheduler process (e.g. a min-heap ordered by next-run-time, like a classic single-machine cron implementation). This fails the moment that process restarts or crashes: every job's schedule is gone, and there's no way to know what should have fired while the process was down or what to trigger next without external state.

The fix is to make the Job Definition Store — a real, durable database — the single source of truth, and treat scheduler nodes as stateless workers that repeatedly re-derive "what's due" by querying that store, rather than processes that privately remember their own schedule. This has a valuable side effect: any scheduler node can restart, or a brand new node can join the fleet, and immediately participate correctly, because all the state it needs is external and durable. It also means horizontal scaling of the scheduler tier is just "add another node that runs the same scan-and-claim loop" — no state to migrate or resync.

### 6.2 Exactly-Once Triggering Across Multiple Scheduler Nodes

This is the central hard problem of the whole system. With multiple scheduler nodes scanning the same Job Definition Store for due jobs (necessary for availability — if there's only one scheduler node, it's a single point of failure that stops all scheduling when it dies), two nodes can independently observe the same job as "due" at nearly the same instant and both attempt to trigger it. Without coordination, this means the job fires twice — for something like "send the daily summary email," that's a visible, embarrassing bug; for something like "charge the customer's card," it's a serious incident.

The fix is the same atomic-claim pattern as a distributed lock (cross-reference `09_distributed_systems_core.md`'s distributed locks section), applied per job-occurrence rather than trusting each node's own clock and in-memory state:
- Each scheduler node, upon finding a candidate due job, issues a **conditional/compare-and-swap write**: "set `locked_by = me` and `locked_until = now + lease_ttl`, but ONLY IF no one currently holds a valid (non-expired) lock on this job." In a relational database this is a straightforward `UPDATE ... WHERE locked_by IS NULL OR locked_until < now()` — the database's own transactional isolation guarantees that only one of two racing `UPDATE` statements against the same row succeeds.
- Only the node whose conditional write actually succeeds (i.e. whose `UPDATE` affected a row — checked via the database's reported row-count) proceeds to trigger the job. The loser simply moves on to the next candidate job in its scan batch.
- The lease has a TTL (`locked_until`) specifically so that if the claiming node crashes after claiming but before finishing the trigger-and-advance step, the lock eventually expires and another node can pick up the job rather than it being stuck forever — this is the same lease-based failure recovery used in general distributed locking.
- Critically, this must NOT be implemented as "check if locked, then separately write the lock" (a check-then-act sequence) — that has a race window between the check and the write where two nodes could both see "unlocked" and both proceed. It must be a single atomic conditional operation performed by the store itself.
- Note the important nuance: this guarantees exactly-once TRIGGERING (the act of deciding-and-dispatching the job to the work queue). It does not, by itself, guarantee exactly-once EXECUTION — that's a separate problem addressed in 6.4, because a message can still be delivered more than once by the work queue, or a worker can crash mid-execution and get retried.

### 6.3 Decoupling "Decide What's Due" from "Actually Execute It"

If the scheduler node executed each due job inline — synchronously calling the webhook or running the task itself as part of its scan loop — then a single slow or hanging job (e.g. a webhook that takes 30 seconds to respond, or a task that genuinely runs for an hour) would block that scheduler node from noticing and triggering every OTHER due job during that time. At the scale estimated in Step 2 (potentially 1,600+ triggers/second during a clustered peak minute), even a handful of slow jobs would cause cascading scheduling delay across completely unrelated jobs.

The fix is the classic separation of concerns: the scheduler's only job is to identify due occurrences, claim them, and push a lightweight trigger message onto a work queue (`10_message_queues_and_streaming.md`) — it never runs job logic itself. Execution Workers, a separately and independently scalable pool, consume from that queue and do the actual work. This buys two things:
- The scheduling loop's latency is now bounded by "how fast can I scan and claim," completely decoupled from "how long does any individual job take to run" — a job that takes an hour doesn't slow down scheduling for anything else.
- Execution capacity scales independently of scheduling capacity: if the trigger rate spikes (the clustered-peak-minute scenario from Step 2), add more Execution Workers to drain the queue faster, without needing to add more Scheduler Nodes (which would just mean more contention on the claim mechanism for no benefit, since the bottleneck was execution throughput, not decision-making throughput).

### 6.4 Idempotency, Retries, and At-Least-Once Execution

Once a trigger message is on the work queue, standard message-queue delivery semantics apply: most practical queue systems guarantee at-least-once delivery, meaning a worker crashing after starting a job but before acknowledging the message will cause that message to be redelivered and the job re-attempted. Combined with the retry policy (explicit retries on failure, e.g. exponential backoff up to N attempts), this means job execution is fundamentally an at-least-once guarantee, not exactly-once — even though triggering (6.2) is exactly-once.

This makes it essential (and worth stating explicitly to an interviewer) that **job logic itself must be written idempotently** — the same idempotency principle discussed in `09_distributed_systems_core.md`. Concretely:
- A job that sends an email should use a deterministic idempotency key (e.g. `job_id + occurrence_time`) that the downstream email service can use to deduplicate, so a retried execution doesn't send the report twice.
- A job that charges a payment should pass an idempotency key to the payment processor for the same reason.
- A job that writes to a database should use an upsert (`INSERT ... ON CONFLICT`) keyed by the occurrence, rather than a blind insert that would create a duplicate row on retry.
- Per-job timeouts are necessary so a hung job doesn't hold a worker slot indefinitely — after the timeout, the worker gives up, and the retry policy kicks in as if it had failed, with the same idempotency requirement applying to the retry.
- The scheduler system can help by tagging every trigger with a stable, deterministic identifier for the occurrence (not a random UUID generated fresh on each attempt), so the job logic and any downstream systems have a consistent key to deduplicate against across retries.

### 6.5 Missed-Schedule (Catch-Up) Handling

If the entire scheduling system (or a specific job's claim) was down across a scheduled occurrence — e.g. a deploy, an outage, or the scan loop being paused for maintenance — the system must decide what happens to that missed occurrence once it comes back up. Two policies, and the design should let this be configured per job rather than system-wide, because different jobs genuinely need different answers:
- **Skip-to-next**: don't run the missed occurrence at all; just compute the next future occurrence from now and wait for that. Appropriate for jobs where running late is worse than not running at all, or where catching up would be actively harmful — e.g. "send daily summary email at 8am": if the system was down from 7am to 10am, nobody wants three summary emails backfilled at 10:01am; they want the next normal 8am email tomorrow.
- **Catch-up-immediately**: run the missed occurrence(s) as soon as the system recovers, since correctness/completeness matters more than punctuality. Appropriate for jobs like "reconcile financial ledger" or "generate a required compliance report" — skipping an occurrence entirely could mean a gap in required records that has real consequences, so running it late (even hours late) is strictly better than not running it.
- Implementation-wise, this is a property (`missed_run_policy`) on the job definition itself, consulted by the scheduler when it computes `next_run_time` after an outage: if the stored `next_run_time` is now far in the past relative to the cron schedule's expected cadence, `catch_up` policy triggers that occurrence once (or, for multiple missed occurrences, typically once — not one per missed interval, to avoid a flood), while `skip` policy simply recomputes the next future occurrence and discards the missed one(s).

## Step 7: Bottlenecks & Trade-offs

- **The scan-and-claim loop as a contention point**: at peak clustering (many jobs due in the same window), multiple scheduler nodes scanning the same due-jobs range and racing to claim overlapping candidates causes wasted work (failed conditional writes) and contention on the underlying database. Mitigation: partition the due-jobs scan itself (e.g. by a hash of job_id modulo number of scheduler nodes) so different nodes are primarily scanning/claiming disjoint subsets, falling back to the conditional-claim as a safety net for edge cases (node count changes, rebalancing) rather than the primary mechanism for avoiding collisions.
- **Database as a bottleneck for the claim mechanism**: because claiming requires a strongly consistent conditional write, the Job Definition Store can't simply be scaled out with eventual-consistency trade-offs the way the execution history store can. At very large job counts, this pushes toward sharding the Job Definition Store itself (e.g. by job_id range or hash) with each shard independently scanned/claimed, accepting the added complexity of cross-shard job management (pause/resume/delete now need to route to the right shard).
- **Thundering-herd trigger clustering**: as computed in Step 2, cron schedules naturally cluster at round times, creating peak trigger rates far above the average. Mitigation: many production schedulers add small random jitter to `next_run_time` computation (e.g. spread an hourly job's actual trigger within a few seconds of the top of the hour rather than exactly at it) when the job's semantics tolerate it, smoothing the peak without meaningfully violating the schedule's intent.
- **Trade-off — polling-based scanning vs event-driven scheduling**: the scan-loop design (poll the database every few seconds) is simple and robust but inherently has some latency floor equal to the scan interval, and constant polling has a baseline cost even when nothing is due. An alternative — a priority-queue-based approach where the earliest next-run-time is watched precisely — offers tighter latency but is significantly harder to make correct across multiple distributed nodes and crash-safe; most production distributed schedulers accept the polling approach's small latency floor in exchange for its operational simplicity.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you handle a job whose cron expression means it's due every second — does the scan-and-claim overhead dominate for very high-frequency jobs?"** For sub-minute frequencies, treat them as a special class: rather than re-entering the general due-job scan/claim cycle every second, hand such jobs to a dedicated lightweight loop (still using the same claim mechanism, but batched/optimized for high-frequency single jobs) to avoid the general scan query being dominated by re-checking the same handful of hyperactive jobs constantly.

2. **"What if the action itself (e.g. the webhook target) is slow or repeatedly failing — how do you prevent it from consuming disproportionate worker capacity?"** Apply per-job or per-target concurrency limits and circuit-breaking: after N consecutive failures, back off the job's retry cadence more aggressively or temporarily suspend it and alert the owner, so one broken integration doesn't starve the worker pool for healthy jobs.

3. **"How do you support jobs with dependencies — 'run job B only after job A succeeds' — closer to an Airflow DAG than plain cron?"** This extends the data model with a DAG of job dependencies and shifts part of the triggering logic from purely time-based to event-based (job A's completion event, rather than a clock, becomes what makes job B eligible for the scheduler's claim step), while reusing the same claim mechanism for exactly-once triggering of each DAG node.

4. **"How would a user debug why their job didn't run at the expected time?"** The History Store combined with structured scheduler logs (which node claimed it, when, and what happened) should make this traceable end-to-end; expose this via the `GET /jobs/{id}/history` endpoint and make sure claim attempts (including failed/lost races) are logged, not just successful triggers, so a "why didn't this fire" investigation isn't a dead end.

5. **"How do you scale to 100 million jobs instead of 1 million?"** Revisit the estimation in Step 2 — at that scale the Job Definition Store almost certainly needs sharding (per the bottleneck discussion above), and it becomes worth asking whether every job needs individual tracking or whether extremely high-cardinality, low-value jobs (e.g. per-user scheduled reminders) could be modeled differently, such as a single recurring "scan for due reminders" job against a separate reminders table rather than one scheduler job definition per reminder.

6. **"What consistency guarantee do you actually need for `next_run_time` reads — could you relax the strong consistency requirement to scale further?"** The claim step genuinely needs strong consistency (it's the correctness-critical compare-and-swap), but the initial due-job SCAN that finds candidates could tolerate reading from a replica with slight lag — worst case, a node considers a job "not yet due" a few hundred milliseconds later than another node would, which just means a slightly later trigger, not a duplicate one, since the claim step is still the final gate.

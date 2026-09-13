# Message Queues and Streaming

## Why asynchronous messaging exists

In a purely synchronous system, service A calls service B directly and waits for a response before continuing. This is simple, but it wires A's availability and latency directly to B's: if B is slow, A is slow; if B is down, A fails too. A **message queue** breaks that coupling by putting a durable buffer between the producer of work and the consumer of work.

Three concrete problems this solves:

- **Decoupling producers from consumers**: the producer doesn't need to know who consumes the message, how many consumers there are, or whether they're currently healthy — it just writes the message and moves on. Consumers can be added, removed, or rewritten without the producer changing at all.
- **Smoothing traffic spikes**: if 10,000 requests arrive in one second but your system can only comfortably process 1,000/second, a queue lets you accept all 10,000 immediately (a cheap, fast write to the queue) and drain them over the next 10 seconds, instead of rejecting 9,000 of them or falling over trying to process them all synchronously.
- **Fault isolation**: if a downstream service is slow or temporarily down, messages simply pile up in the queue instead of piling up as failed requests or timed-out threads in the upstream service — the upstream service stays healthy and keeps accepting new work.

## Why it matters

Without asynchronous messaging, systems tend to fail in these specific ways:

- **A slow email/SMS/webhook provider inside a request path** makes every request that triggers a notification slow, or fails the whole request when the provider has a blip — even though "send a notification" was never something the user needed to wait for.
- **A traffic spike (flash sale, viral post) takes the whole system down** because every request tries to do all of its work synchronously, and the database/downstream services get overwhelmed with no buffer to absorb the burst.
- **One service's outage cascades to unrelated services** that happen to call it synchronously, turning a single component failure into a system-wide outage.

## Pub/sub vs point-to-point queue

These are the two fundamental messaging shapes, and interviewers expect you to pick the right one for the scenario.

- **Point-to-point queue**: each message is delivered to and processed by exactly **one** consumer, even if many consumers are listening. This is for **work distribution** — you want a pool of workers to split up a backlog of jobs.
  - Example: order-processing jobs pushed onto a queue, consumed by a pool of worker processes — each order should be processed once, by one worker, not by all of them.
- **Publish/subscribe (pub/sub)**: each message is broadcast to **every** subscriber independently. This is for **fan-out** — you want multiple, independent parties to each react to the same event in their own way.
  - Example: a `UserUpdated` event is published when a user changes their email; the email service, the analytics service, and the fraud-detection service each subscribe and react independently — all three should see every event, not just whichever one happens to grab it first.

```text
Point-to-point queue (work distribution)     Pub/Sub (fan-out)
                                               
 Producer --> [ Queue ] --> Worker 1           Publisher --> [ Topic ] --> Subscriber A
                        \-> Worker 2                                  \-> Subscriber B
                        \-> Worker 3                                  \-> Subscriber C
 (each message goes to ONE worker)            (each message goes to EVERY subscriber)
```

## Delivery semantics

Delivery semantics describe the guarantee a messaging system makes about how many times a message will actually be delivered/processed.

| Semantic | Guarantee | Failure mode | Mechanism |
|---|---|---|---|
| At-most-once | Message delivered zero or one times | Can silently lose messages | Fire-and-forget — send and don't wait for/retry on failure |
| At-least-once | Message delivered one or more times | Can deliver duplicates | Producer/broker retries until it gets an acknowledgment (ack) from the consumer |
| Exactly-once | Message delivered and processed exactly one time | Very hard to actually guarantee end-to-end | Usually simulated, not truly native |

**Exactly-once is, in practice, almost always "effectively-once"**: real systems achieve the *effect* of exactly-once by combining **at-least-once delivery** (the safe default — never silently drop a message, tolerate duplicates arriving) with **idempotent consumers** (the consumer can safely process the same message twice and get the same result). This is the same idempotency-key mechanism described in `09_distributed_systems_core.md` — the messaging layer's job is just to not lose anything, and the consumer's job is to make re-processing harmless. True exactly-once delivery at the transport level would require solving distributed consensus on every single message, which is too costly for high-throughput systems, so nearly everyone builds effectively-once instead.

## Kafka basics

**Apache Kafka** is a distributed streaming platform built around durable, ordered, replayable logs, not a traditional "delete on ack" queue. The vocabulary you need for an interview:

- **Topic**: a named stream of messages (e.g., `orders`, `page_views`) — the logical channel producers write to and consumers read from.
- **Partition**: a topic is split into multiple partitions, each an ordered, append-only log. Splitting into partitions is what enables parallelism — different partitions can be written to and read from independently, spreading load across machines. Order is only guaranteed **within** a single partition, not across the whole topic.
- **Consumer group**: a named set of consumer instances that split up the work of reading a topic. Within a group, **each partition is consumed by exactly one consumer at a time** — this is what makes consumption horizontally scalable: add more consumer instances to a group (up to the number of partitions) and Kafka rebalances partitions across them automatically.
- **Offset**: a consumer's position (an integer index) within a partition, marking how far it has read. Because it's just a position — not a deletion pointer — a consumer can rewind its offset and **replay** old messages, or run a brand-new consumer group that reads the whole history from offset 0.
- **Retention**: Kafka retains messages for a configured time window or size limit (e.g., 7 days) **regardless of whether they've been consumed** — unlike a traditional queue, reading a message does not delete it. This is what makes replay possible: a new consumer (or a buggy one that needs to reprocess) can read messages that were already consumed by someone else days ago.

```text
Topic: orders
  Partition 0: [msg0][msg1][msg2][msg3] --> Consumer group "billing": Consumer A
  Partition 1: [msg0][msg1][msg2]       --> Consumer group "billing": Consumer B
  Partition 2: [msg0][msg1][msg2][msg3][msg4] --> Consumer group "billing": Consumer C

  Same topic, independently read by a second, unrelated group:
  Consumer group "analytics": reads all partitions from its own offsets, unaffected by "billing"
```

Because retention is time/size-based rather than ack-based, **multiple independent consumer groups can each read the entire topic at their own pace** — this is a fundamentally different model from a traditional queue, where a message is gone once someone acks it.

## RabbitMQ / SQS vs Kafka

**RabbitMQ** and **AWS SQS** are traditional message queues: a message is delivered to a consumer, the consumer processes it and sends an **ack**, and the broker then deletes the message. There's no replay — once it's acked and gone, it's gone (unless you've built your own archival).

| | RabbitMQ / SQS | Kafka |
|---|---|---|
| Mental model | Queue — message deleted after ack | Log — message retained regardless of consumption |
| Per-message tracking | Per-message ack/nack, easy to retry a single failed message | Offset-based — tracks position, not per-message state |
| Replay | Not supported natively | Native — rewind offset, or spin up a new consumer group |
| Throughput ceiling | Good for moderate throughput task queues | Built for very high throughput (millions of messages/sec) |
| Multiple independent readers of the same stream | Awkward — typically needs fan-out exchanges/topics per consumer | Natural — every consumer group reads independently |
| Best fit | Task queues, job processing, request/reply patterns, simpler ops | Event streaming, analytics pipelines, event sourcing, systems needing replay or many independent consumers |

Practical rule of thumb for an interview: reach for **RabbitMQ/SQS** when you just need reliable task distribution with simple per-message semantics (e.g., "process this uploaded image," "send this email"). Reach for **Kafka** when you need replay, very high sustained throughput, or several unrelated services independently consuming the same event stream at their own pace.

## Event-driven architecture patterns

These describe *what the event itself contains*, not the transport mechanism — you can implement any of them on Kafka, RabbitMQ, or SQS.

- **Event notification**: a small, minimal event ("something happened," e.g., `{"orderId": 123, "event": "OrderCreated"}`) — the consumer, if it needs more detail, calls back to the source service's API to fetch the full data. Keeps events small and simple, but adds an extra network call and a runtime dependency back on the source service being available.
- **Event-carried state transfer**: the event carries the **full relevant data** of the change itself (e.g., `{"orderId": 123, "event": "OrderCreated", "items": [...], "total": 49.99, "customerId": 456}`). The consumer never needs to call back — it has everything it needs in the event. Trade-off: events are larger, and every consumer now depends on the event schema including everything they might ever need.
- **Event sourcing**: instead of storing current state directly, you store the full **sequence of events** that led to that state, and the current state is **derived** by replaying those events from the beginning (or from the last snapshot). E.g., an account's balance isn't a stored column — it's the sum of every `Deposited`/`Withdrawn` event ever applied to that account. This gives you a full audit trail and the ability to reconstruct state as of any point in time, but it's real added complexity (replaying logic, snapshotting for performance, schema evolution of old events) and should not be reached for by default — only when the audit trail / time-travel / replay capability is an actual requirement, not just "because it sounds robust."

## Push vs pull consumption

This is a second axis worth knowing alongside queue vs pub/sub, because it explains *why* Kafka and RabbitMQ behave so differently under load:

- **Push-based** (RabbitMQ, SQS-with-long-polling-pushed-to-workers): the broker actively sends messages to consumers as they arrive/become available. Lower latency (no polling delay), but the broker has to actively manage consumer speed — if it pushes faster than a consumer can handle, the consumer gets overwhelmed unless the protocol has an explicit flow-control mechanism (e.g., RabbitMQ's "prefetch count," which caps how many unacked messages a consumer can be holding at once).
- **Pull-based** (Kafka): consumers actively request the next batch of messages at their own pace, tracking their own offset. This naturally self-regulates — a slow consumer just pulls less often and falls behind in its own offset, without the broker needing to do anything special — and it's what makes replay trivial (just ask for an older offset).

Pull-based is a large part of why Kafka handles very high throughput and many independent consumer groups well: the broker doesn't need to track per-consumer delivery state beyond "where is this consumer's offset," whereas a push broker actively managing delivery and acks to many different consumers has more bookkeeping to do per message.

## Dead-letter queues and poison messages

A **poison message** is a message that a consumer can never successfully process — e.g., it's malformed, or it triggers a bug that crashes the consumer every time it's retried. Without a safety valve, a consumer using at-least-once delivery will retry that same message forever, blocking it from making progress on anything behind it in the queue/partition (this is especially damaging in point-to-point queues where ordering matters, or in Kafka where a stuck partition blocks every message behind it until the offset advances).

A **dead-letter queue (DLQ)** is the standard fix: after a message fails processing some configured number of times (e.g., 5 retries), it's automatically moved out of the main queue and into a separate DLQ instead of being retried indefinitely. The main queue keeps flowing; the DLQ accumulates the messages that need manual investigation or a code fix before being reprocessed. Both RabbitMQ and SQS support DLQs natively; a Kafka equivalent is typically built by the application (catch the processing error, publish the failed message to a separate `*-dlq` topic, then advance the offset so the partition isn't stuck).

## Backpressure

**Backpressure** is what happens when producers generate messages faster than consumers can process them — the gap grows, and the system needs a deliberate strategy or it degrades uncontrolled (unbounded memory growth, cascading timeouts, eventual crash).

Strategies:
- **Bounded queues that push back upstream**: cap the queue size, and once full, make the producer wait or reject new writes — this propagates the slowdown back to the source instead of hiding it, forcing the producer (or whatever is upstream of it) to deal with the overload explicitly rather than silently accumulating unbounded backlog.
- **Load shedding**: deliberately drop lower-priority messages/requests when overloaded, to protect capacity for the higher-priority ones — an explicit, controlled trade-off rather than an uncontrolled failure.
- **Consumer autoscaling**: add more consumer instances (e.g., more workers in a consumer group) in response to queue depth/lag growing, so processing capacity grows with load.
- **Buffering with retention**: Kafka's approach — since messages aren't deleted on read, a burst simply sits in the log until consumers catch up; as long as retention window/size isn't exceeded, no data is lost, just delayed.

## Trade-offs / When to use what

| Scenario | Choice | Why |
|---|---|---|
| Distribute jobs across a worker pool, each job done once | Point-to-point queue (SQS/RabbitMQ) | Built-in work distribution, simple ack model |
| Notify multiple independent services of an event | Pub/sub (SNS, Kafka topic, RabbitMQ fan-out exchange) | Every subscriber needs its own copy |
| Need to replay history or support new consumers reading old data | Kafka | Retention-based, replayable log |
| Very high sustained throughput, ordered per key | Kafka (partitioned by key) | Partitions parallelize while preserving per-key order |
| Simple task queue, minimal ops overhead | SQS/RabbitMQ | Simpler mental model, less to operate than a Kafka cluster |
| Guaranteeing no double-processing on retries | At-least-once delivery + idempotent consumer | True exactly-once is impractical at scale; this achieves the same effect |

## Interview Tips

- When a design has any "notify other services" or "process this asynchronously" requirement, proactively suggest a queue/event bus rather than a synchronous call — interviewers are checking whether you default to decoupling for exactly these cases (slow downstream, traffic spikes, fault isolation).
- If you say "exactly-once," the interviewer will likely push on how — the strong answer is "at-least-once delivery plus an idempotent consumer using a dedup key," not "the message broker guarantees it."
- Expect a direct "would you use Kafka or SQS here?" question — justify with a specific property (needs replay → Kafka; simple job queue, minimal ops → SQS), not "Kafka is more scalable" as a blanket statement.
- If a design mentions ordering requirements ("process a given user's events in order"), bring up Kafka partitioning by key — messages with the same key go to the same partition and are processed in order within it, but there's no global ordering across the whole topic.
- Don't reach for event sourcing unless the question explicitly needs an audit trail or point-in-time reconstruction — proposing it as a default is a common over-engineering tell.

## Quick Recall — Self-Test

**Q1: What three problems does asynchronous messaging solve that synchronous calls don't?**
Decoupling (producer doesn't need to know about or depend on consumers), smoothing traffic spikes (buffering bursts instead of rejecting or collapsing under them), and fault isolation (a slow/down downstream doesn't propagate failure/latency back to the producer).

**Q2: What's the fundamental difference between a point-to-point queue and pub/sub?**
A queue delivers each message to exactly one consumer (for distributing work across a pool), while pub/sub broadcasts each message to every subscriber (for fanning an event out to multiple independent, unrelated consumers).

**Q3: Why is "exactly-once" delivery usually not implemented literally, and what's used instead?**
True exactly-once at the transport level effectively requires distributed consensus on every message, which is too expensive at scale. In practice systems use at-least-once delivery (never silently drop, tolerate duplicates) combined with idempotent consumers, achieving the same practical effect ("effectively-once").

**Q4: In Kafka, what determines how many consumers within a group can process a topic in parallel, and what happens if you add more consumers than partitions?**
The number of partitions is the ceiling on parallelism within a consumer group, since each partition is consumed by exactly one consumer in the group at a time. Extra consumers beyond the partition count sit idle with nothing assigned to them.

**Q5: How does Kafka's retention model differ from RabbitMQ/SQS, and why does that matter?**
Kafka retains messages for a configured time/size regardless of whether they've been consumed, so messages can be replayed and multiple independent consumer groups can each read the full stream at their own pace. RabbitMQ/SQS delete a message once it's acked, so there's no native replay and no clean way for a second, later consumer to see history.

**Q6: What's the difference between event notification and event-carried state transfer, and what does each trade off?**
Event notification sends a minimal "something happened" ping and requires the consumer to call back for details (small events, extra network dependency); event-carried state transfer embeds the full changed data in the event itself (no callback needed, but larger events and every consumer depends on the event schema).

**Q7: When would you specifically choose event sourcing, and why shouldn't it be a default choice?**
Choose it when you genuinely need a full audit trail or the ability to reconstruct state as of any past point in time. It's not a default because replaying events, snapshotting for performance, and evolving event schemas over time add real, ongoing complexity that most applications don't need.

**Q8: Name two concrete strategies for handling backpressure when consumers can't keep up with producers.**
Bounded queues that push back on producers once full (forcing the slowdown to surface upstream instead of hiding it), and consumer autoscaling (adding more consumer instances in response to growing queue depth/lag). Load shedding and retention-based buffering (Kafka's approach) are the other two covered.

**Q9: What's the practical difference between push-based and pull-based message consumption, and why does it matter for scaling?**
Push-based brokers (RabbitMQ) actively send messages to consumers and need explicit flow control (like a prefetch limit) to avoid overwhelming a slow consumer. Pull-based brokers (Kafka) let consumers request messages at their own pace, which self-regulates naturally and requires less per-consumer bookkeeping from the broker — a big reason Kafka scales well to high throughput and many independent consumer groups.

**Q10: What is a dead-letter queue, and what problem does it solve?**
It's a separate queue that a poison message (one that fails processing repeatedly, e.g., due to malformed data or a triggered bug) is automatically moved to after a configured number of failed attempts, instead of being retried forever. This keeps a single unprocessable message from blocking everything behind it in the main queue/partition while preserving the message for manual investigation.

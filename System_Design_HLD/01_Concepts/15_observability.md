# Observability

## Why it matters

You can design the most elegant architecture in the world and it will still break in production — a deploy introduces a regression, a downstream dependency slows down, a specific shard gets hot. The difference between a 5-minute incident and a 5-hour one is almost entirely whether you can quickly answer "what's broken, where, and why" from the data your system already produces, rather than SSHing into a box and guessing. **Observability** is the general property of a system that lets you answer that question from the outside, using its outputs (logs, metrics, traces), without having to add new instrumentation after the fact just to debug the specific incident in front of you. In an interview, mentioning observability signals that you're thinking about a system's entire lifecycle — build it, operate it, debug it at 2am — not just its happy-path architecture diagram.

## The three pillars

| Pillar | Answers | Granularity |
|---|---|---|
| Logging | What exactly happened, for one specific event/request | Very fine — full detail on a single occurrence |
| Metrics | Is the system healthy right now, in aggregate | Coarse — numeric signal over time, no per-event detail |
| Tracing | How did one request's time get spent across multiple services | Medium — one request, but across its entire path |

**Logging**: a record of a specific event as it happened — "user 4821 attempted login at 14:32:07 and failed: invalid password," "order 9931 failed to charge: gateway timeout." Logs are your source of detailed truth for a single occurrence — indispensable when you already know roughly *what* happened and need to know exactly *why*, for one request or one user.

**Metrics**: aggregate numeric signals sampled/collected over time — requests per second, error rate, CPU utilization, queue depth. Metrics answer "is the system healthy right now" at a glance, across the whole fleet, without needing to look at any individual event. They're what dashboards and most alerts are built on, because they're cheap to store and query even at huge volume (a counter is a single number, not a growing log of every event).

**Tracing**: follows a single request's journey as it flows through multiple services, showing how much time was spent in each hop. Once a request touches more than one service, logging and metrics from each service in isolation can't tell you *which* hop caused a slowdown — tracing stitches the whole path together into one timeline.

```text
Logging:  "exactly what happened, for this one event"      -> one line, full detail
Metrics:  "is everything healthy right now"                -> one number, over time
Tracing:  "where did this one request's time actually go"  -> one timeline, across services
```

These three are complementary, not substitutes: a metric tells you error rate just spiked; a trace tells you it's specifically the payment service's calls to the fraud-check service that got slow; a log tells you the fraud-check service is timing out because of a specific malformed request payload.

## Structured logging vs plain-text logging

**Plain-text logs** are free-form human-readable strings: `"2024-01-15 14:32:07 ERROR User 4821 login failed: invalid password"`. Easy to read directly in a terminal, but hard to query at scale — finding "all failed logins for user 4821 in the last hour, across 200 servers" means grep-like text searching over unstructured strings, which is slow and brittle (a slightly different message format breaks your search).

**Structured logging** emits logs as machine-parseable key-value data, typically JSON: `{"timestamp": "2024-01-15T14:32:07Z", "level": "error", "event": "login_failed", "user_id": 4821, "reason": "invalid_password"}`. Every field is queryable directly — "all `login_failed` events where `user_id = 4821`" is a precise, fast query against a log aggregation system (e.g., Elasticsearch-backed tooling — see `13_search_and_indexing.md`), not a text search.

Once you have more than a handful of services generating meaningful log volume, structured logging wins decisively: it lets you filter, aggregate, and correlate logs across services (e.g., "show me every log line across every service tagged with this one `request_id`") in a way plain text fundamentally can't support at scale. The cost is that structured logs are less pleasant to eyeball directly in a raw file — but at scale, nobody's eyeballing raw log files anyway; they're querying an aggregation system.

| | Plain-text | Structured (JSON/key-value) |
|---|---|---|
| Human readability | High, directly | Lower directly, but tools render it nicely |
| Queryability at scale | Poor — text search only | Strong — precise field-based queries |
| Cross-service correlation | Hard | Easy (shared fields like `request_id`) |
| Best fit | Local dev, single small app | Any system with more than a few services/meaningful volume |

## Metrics types

**Counters**: a value that only ever increases (until it's reset, e.g., on process restart) — total requests served, total errors, total orders placed. You typically care about the *rate of change* of a counter (requests/sec) more than its raw cumulative value.

**Gauges**: a value that can go up or down, representing a current state — current active connections, current queue depth, current memory usage. Unlike a counter, a gauge's current value is meaningful on its own (a counter alone just tells you "a lot happened since start," not the current state).

**Histograms**: capture the *distribution* of a set of values, not just a single number — bucketed counts of how many observations fell into each range. The canonical use is request latency: instead of one number, you get enough data to compute percentiles like p50 (median), p95, p99 (99th percentile).

**Why percentiles matter more than averages for latency**: an average can look perfectly healthy while hiding real user pain. If 99 requests take 10ms and 1 request takes 10 seconds, the average is roughly 109ms — looks fine — but that one request represents a real user who had a terrible experience, and at scale "1 in 100" is not rare, it's a meaningful fraction of your total traffic. p99 latency (the value below which 99% of requests fall) directly answers "what's the worst experience a non-trivial chunk of my users are actually having," which is what you generally want to optimize and alert on — a system can have a great average and a terrible p99 simultaneously, and averages will never surface that.

```text
Latencies (ms): 8, 9, 9, 10, 10, 11, 10, 9, 8, 10000

Average ≈ 1009ms   <- dominated/skewed, but also misleadingly "not that bad" looking
                       for the 9 fast requests hidden inside it
p50 (median) = 9-10ms   <- "typical" request, accurate
p99 = ~10000ms          <- the tail user's actual (bad) experience, visible
```

| Metric type | Example | Question it answers |
|---|---|---|
| Counter | Total requests served | How much has happened, cumulatively? |
| Gauge | Current active DB connections | What's the state right now? |
| Histogram | Request latency distribution | What does the full spread of outcomes look like (p50/p95/p99)? |

## Distributed tracing

Once a system is a handful of services calling each other, a single user-facing request can fan out across many of them — an API call might hit a gateway, an auth service, an order service, a payment service, and an inventory service before responding. If that request is slow, per-service logs and metrics in isolation don't tell you *which* of those five hops is the culprit — each service might report itself as healthy, because the slowness could be in the network hop, a queue, or a downstream call none of them individually sees end-to-end.

Distributed tracing solves this by propagating shared identifiers across every hop of a request:

- **Trace ID**: identifies the entire request end-to-end, across every service it touches. Every span belonging to this one logical request shares the same trace ID.
- **Span ID**: identifies one unit of work within that trace — typically one service's handling of the request, or one significant operation inside it (e.g., a DB query). Each span records its own start time, duration, and which span it's a child of, so the full trace reconstructs a timeline/tree of "who called whom, and how long did each hop take."

This context (trace ID, current span ID, plus the parent span ID) is **propagated via request headers** as the request moves from service to service — each service reads the incoming trace context, creates its own span as a child of it, and passes the (possibly updated) context along to whatever it calls next. Collecting all spans sharing a trace ID and visualizing them (commonly as a waterfall/flame graph of nested time ranges) shows exactly where the request's total time went.

```text
trace_id: abc123
┌─────────────────────────────── Gateway (span 1, 220ms) ───────────────────────────────┐
   ┌──── Auth svc (span 2, 15ms) ────┐
                                       ┌────────── Order svc (span 3, 190ms) ───────────┐
                                          ┌── Payment svc (span 4, 160ms) ──┐  <- the culprit
                                          ┌ Inventory svc (span 5, 10ms) ┐
```
Without tracing, each service individually might log "I took 190ms" or "I took 160ms" with no shared context tying them together into one request's story — tracing is what turns isolated per-service numbers into a single, attributable timeline.

## Log levels

Structured or not, logs are typically tagged with a **severity level** so consumers (both humans and alerting systems) can filter by importance without parsing message content:

| Level | Meaning | Example |
|---|---|---|
| `DEBUG` | Fine-grained detail, useful only during active debugging | "Cache lookup for key X missed, falling through to DB" |
| `INFO` | Normal operational events, expected | "User 4821 logged in" |
| `WARN` | Something unexpected but not (yet) broken | "Retrying payment gateway call, attempt 2 of 3" |
| `ERROR` | An operation failed | "Failed to charge order 9931: gateway timeout" |
| `FATAL/CRITICAL` | The process itself can't continue | "Unable to connect to primary DB at startup, exiting" |

In production, `DEBUG` is usually disabled or heavily sampled (too high-volume to store/query at full fidelity), and alerting is generally built on `ERROR`/`FATAL` rates rather than raw log volume, feeding into the symptom-based alerting below.

## Sampling: making tracing affordable at scale

Capturing a full trace for every single request is expensive at high request volume — both the overhead of generating spans and the storage cost of retaining them. Production tracing systems commonly use **sampling**: only a percentage of requests (e.g., 1% of all traffic, or 100% of requests that error/exceed a latency threshold, which is called "tail-based" or "error-biased" sampling) are fully traced and retained. This is a trade-off worth naming if asked about tracing at scale: full-fidelity tracing on every request gives complete visibility but doesn't scale cheaply; sampling keeps cost bounded while still catching the traces that matter most (the slow and failing ones), at the cost of not having a trace for every single request if you needed to look one up after the fact.

## Alerting

**Symptom-based alerting**: alert on what users actually experience — elevated error rate, elevated p99 latency, failed checkouts per minute. These are the primary alerts, because they directly reflect user impact — if nothing is symptomatically wrong, arguably nothing worth waking someone up for is wrong yet, regardless of what internal metrics say.

**Cause-based alerting**: alert on a specific internal condition — high CPU, high memory, disk filling up, queue depth rising. These are valuable as *supporting diagnostic signals* once a symptom-based alert has already fired (high CPU is probably why latency is up), but as primary alerts on their own they're noisy and often disconnected from actual user impact — CPU can spike briefly with zero user-visible effect (e.g., during a GC pause that's well within tolerance), and alerting on every such blip trains people to ignore alerts.

**Why symptom-based should be primary**: it's the more honest question. "Is the CPU high" doesn't necessarily mean users are suffering; "is the error rate/latency elevated" means they are, directly, regardless of the internal cause. Cause-based signals are best treated as dashboards/diagnostics you check *after* a symptom-based alert fires, to find the root cause — not as things that page someone by themselves.

**Alert fatigue**: the danger of having too many low-value, low-signal alerts (every minor CPU blip, every transient retry) is that people start ignoring alerts wholesale, including the real ones — the alerting system trains its own operators to tune it out. A smaller number of high-signal, symptom-based alerts that reliably indicate real user impact is far more effective than a large number of noisy ones, even if the noisy ones are individually well-intentioned.

## Health checks: liveness vs readiness

**Liveness probe**: "is this process still running / functioning at all, or should it be killed and restarted?" A failing liveness check means the process is in a broken, unrecoverable-without-restart state (e.g., deadlocked, hung) — the orchestrator's response is typically to kill and restart it.

**Readiness probe**: "is this process ready to receive traffic *right now*?" A process can be alive (not crashed, would pass a liveness check) but not yet ready — e.g., it's still warming up, loading a large in-memory cache, or waiting on a dependency to become available. A failing readiness check means "don't route traffic here yet," not "kill it" — the orchestrator's response is to temporarily remove it from the load balancer's pool until it reports ready again.

**Why conflating the two causes real outages**: if a slow-starting or temporarily-busy process is checked with a liveness probe instead of a readiness probe, the orchestrator concludes it's dead and kills it — even though it was just warming up or briefly overloaded, and would have recovered on its own. Repeatedly killing a process that's about to become healthy (because it never gets the chance to finish starting up) is a classic self-inflicted outage: the fix isn't in the application code, it's in correctly distinguishing "should this be restarted" (liveness) from "should this receive traffic" (readiness) at the infrastructure/health-check configuration level.

| | Liveness | Readiness |
|---|---|---|
| Question | Should this process be restarted? | Should this process receive traffic right now? |
| Fails when | Process is hung/deadlocked/broken | Process is alive but not yet ready (warming up, dependency down) |
| Orchestrator response to failure | Kill and restart | Remove from load balancer pool, don't kill |
| Conflating them causes | N/A | Killing healthy-but-busy/starting processes, worsening outages |

## Trade-offs

| Decision | Choose this when... | Cost |
|---|---|---|
| Structured logging | More than a couple of services, need cross-service queries/correlation | Slightly less pleasant for a human reading raw log files directly |
| Fine-grained tracing on every request | Debugging a specific microservices latency problem, or always-on in a complex system | Storage/overhead cost of trace data; usually mitigated with sampling (trace only a percentage of requests) at high volume |
| Symptom-based alerts as primary | Almost always — it's the safer default | Requires good visibility into user-facing metrics (error rate, latency) to be meaningful |
| Cause-based alerts as primary | Rarely — only for conditions that are reliably, directly predictive of imminent user impact (e.g., disk about to fill completely) | High risk of noise/alert fatigue if used broadly |

## Interview Tips

- If a design spans multiple services, proactively mention distributed tracing — it's a strong signal that you're thinking about operability, not just the happy-path architecture.
- When discussing latency requirements, say "p99" rather than "average" — interviewers notice when a candidate defaults to average latency, since it's a well-known way real tail-latency problems hide from a metric.
- Distinguish symptom-based alerts as primary and cause-based as diagnostic support when asked "how would you monitor this" — a common weak answer just lists "we'd alert on CPU and memory," which misses the point of what should actually page someone.
- Mention liveness vs readiness specifically if the design involves containerized/orchestrated services (e.g., Kubernetes) with autoscaling or rolling deploys — conflating them is a realistic, concrete failure mode that shows practical operational awareness.

## Quick Recall — Self-Test

**Q1: What distinct question does each of the three observability pillars answer?**
Logging answers what exactly happened for one specific event. Metrics answer whether the system is healthy right now, in aggregate. Tracing answers how a single request's time was spent as it flowed across multiple services.

**Q2: Why does structured logging outperform plain-text logging once you have several services?**
Structured (JSON/key-value) logs are machine-parseable, so you can query precisely on specific fields (e.g., all events with a given `user_id` or `request_id`) and correlate logs across services sharing a common field. Plain text logs only support brittle text search and can't be reliably aggregated or filtered at scale.

**Q3: Give an example of a counter, a gauge, and a histogram, and what each is for.**
Counter: total requests served (monotonically increasing, care about its rate). Gauge: current active connections (goes up or down, current-state snapshot). Histogram: request latency distribution (bucketed values enabling percentile calculations like p95/p99).

**Q4: Why can an average latency look healthy while real users are suffering?**
An average blends fast and slow requests into one number, so a small fraction of very slow requests can be masked by a majority of fast ones. Percentiles like p99 isolate the tail directly, showing the experience of the worst-affected (but still numerically significant) fraction of users, which an average hides.

**Q5: What do trace ID and span ID each identify, and how is that context passed between services?**
A trace ID identifies the entire end-to-end request across every service it touches; a span ID identifies one unit of work (typically one service's handling, or a sub-operation) within that trace. This context is propagated via request headers as the request moves from service to service, letting every hop attach its span to the same overall trace.

**Q6: Why is symptom-based alerting generally preferred over cause-based alerting as the primary alert?**
Symptom-based alerts (elevated error rate, elevated latency) directly reflect actual user impact, while cause-based signals (high CPU, high memory) can spike without any user-visible effect, causing noisy, low-value alerts. Cause-based signals are still useful as diagnostic support once a symptom-based alert has already fired.

**Q7: What is alert fatigue, and why is it dangerous?**
It's the effect of having too many low-signal alerts, which trains the people receiving them to start ignoring alerts in general — including the real, important ones. A small set of high-signal alerts is more effective than a large set of noisy ones, even if each noisy alert was individually well-intentioned.

**Q8: What's the difference between a liveness probe and a readiness probe, and what real outage does conflating them cause?**
A liveness probe asks "should this process be restarted" (fails only when it's genuinely broken/hung); a readiness probe asks "should this process receive traffic right now" (fails when it's alive but temporarily not ready, e.g., still warming up). Conflating them causes an orchestrator to kill processes that were only briefly busy or starting up, turning a transient, self-recovering condition into an unnecessary restart loop and outage.

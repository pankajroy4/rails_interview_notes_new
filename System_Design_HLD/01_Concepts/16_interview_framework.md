# The Interview Framework

This file is the capstone of `01_Concepts` — it doesn't introduce new technical vocabulary the way the previous 15 files did. Instead, it gives you the repeatable *process* for running an entire system design interview, into which everything you've learned so far (scalability and estimation, networking, load balancing, caching, databases, CAP/consistency, distributed systems, queues, microservices, storage, search, security, observability) gets slotted at the right moment. Every file in `02_Interview_Questions/` is a worked example of this exact framework applied to a specific system — so internalizing this file is what turns a pile of separate concepts into a single, confident approach you can run on *any* prompt, including ones you've never seen before.

## The Framework

A realistic system design interview is 45-60 minutes. The single most common failure mode is mismanaging that clock — spending 20 minutes drawing boxes and having no time left for the deep dive, which is the part that actually differentiates candidates. Treat the time budgets below as defaults to consciously steer toward, not a rigid script.

### 1. Clarify requirements (~5 min)

Before designing anything, convert the ambiguous prompt ("design Twitter") into a concrete, scoped problem. Ask about:

- **Functional requirements (FRs)** — what must the system actually do? A prompt like "design Twitter" could mean posting + following + a feed, or could also mean search, trending topics, DMs, ads. Explicitly narrow scope: "I'll focus on posting, following, and the home timeline — should I include search or DMs, or treat those as out of scope?"
- **Non-functional requirements (NFRs)** — how well must it perform? Scale (how many users, how many requests/sec), latency targets, consistency needs (can the feed be a few seconds stale, or must it be immediate), availability expectations. See `02_scalability_and_estimation.md` for the full vocabulary here (SLA/SLO/SLI, the "nines").

Do not silently assume any of this — state your assumptions out loud and get a nod, or ask directly. This step exists specifically so you don't spend the next 40 minutes designing the wrong system.

### 2. Estimate scale (~5 min)

Do back-of-envelope math to pin down rough numbers: daily active users, requests/sec at peak (often estimated as ~2-5x the daily average to account for non-uniform traffic), read/write ratio, storage growth per day/year, average payload size. This directly drives real design decisions later — e.g., "200K writes/sec" rules out a single unsharded relational database outright, while "50 writes/sec" means you probably don't need to shard at all yet. Full technique and worked examples live in `02_scalability_and_estimation.md` — this step is where you apply that technique to the specific numbers this interview gave you.

Keep the numbers rough and round (powers of 10, not false precision) — the goal is order-of-magnitude judgment ("this needs to be sharded," "this fits comfortably on one Redis instance"), not a spreadsheet.

### 3. High-level design (~15 min)

Sketch the core components and how data flows between them — client, API/load balancer, application services, databases, caches, queues — at a level that fits comfortably on one diagram. Keep the first pass deliberately simple: a small number of boxes covering the main read and write paths for the FRs you scoped in step 1. Resist the urge to add every component you know about (a cache, a queue, a CDN, a search index) unless the requirements actually justify each one — an unjustified component is a red flag to an interviewer, not a bonus point.

```text
  client ──► load balancer ──► app servers ──► primary DB
                                    │
                                    ├──► cache (hot reads)
                                    └──► queue ──► async workers
```

State the *reasoning* for each box as you draw it, not just the box itself — "writes go through a queue here because this system needs to absorb bursty traffic without blocking the user-facing request," not just "queue" with no justification.

### 4. API design (~5 min, often folded into high-level design)

Define the key endpoints/contracts the client-facing (or service-facing) API exposes — method, path, key parameters, and response shape, at a level of detail that pins down the contract without belaboring every field. E.g., for a URL shortener: `POST /urls {long_url} -> {short_url}`, `GET /:short_code -> 302 redirect to long_url`. This forces you to confirm you actually understand what the system needs to expose before you design the storage underneath it, and it's a natural place for the interviewer to probe scope questions.

### 5. Data model (~5-10 min, often folded into high-level design)

Choose storage types (relational vs NoSQL, and which flavor of NoSQL if relevant — see `06_databases_fundamentals.md`) and sketch the core schema/entities and their relationships, driven directly by the access patterns implied by the API from step 4. State *why* each storage choice fits — e.g., "user profile data is relational and needs joins/transactions, so Postgres; the feed itself is accessed by a single key (user ID) at very high read volume with no need for joins, so a key-value/wide-column store fits better there." Don't pick a storage engine because it's trendy — pick it because the access pattern demands it.

### 6. Deep dive (~15-20 min — the most important part)

Go genuinely deep on the 1-2 hardest parts of *this specific system* — not everything, and not generically "scale it more." This is where strong candidates separate from weak ones, because it's where you demonstrate you can actually reason through a hard problem rather than recite component names. Identify the deep-dive target by asking: what's the one part of this system that's genuinely hard, non-obvious, or where a naive approach clearly breaks?

Examples of what a deep dive looks like per system:
- **URL shortener**: how do you generate unique short codes at scale without collisions and without a single bottlenecked counter? (base62 encoding of a distributed ID generator, vs a hash + collision check, vs pre-generated key ranges handed out to app servers.)
- **News feed**: fan-out-on-write (precompute each follower's feed when a post is made — fast reads, expensive/wasteful for celebrities with millions of followers) vs fan-out-on-read (compute the feed at read time by merging followed users' recent posts — cheap writes, expensive reads) vs a hybrid.
- **Rate limiter**: which algorithm (see `14_security_basics.md`), and how do you keep counters consistent and fast across many distributed rate-limiter instances without the counter store itself becoming the bottleneck.
- **Chat application**: how do you deliver messages in real time (see `03_networking_and_apis.md` on WebSockets), guarantee ordering and at-least-once delivery, and handle a user connected to a different server than the sender.

Watch for the interviewer steering you here — if they ask "what happens when X fails" or "how would you handle 100x the load on this one part," that's a direct signal of where they want the deep dive to go. Follow it.

### 7. Identify bottlenecks and trade-offs (~5 min)

Explicitly state what breaks first as load grows, and how you'd address it — e.g., "the primary database becomes the write bottleneck past N writes/sec; I'd address that with sharding by user ID" (see `07_database_scaling.md`), or "a single point of failure at the load balancer; I'd run it in an active-passive or active-active pair." Also revisit and name the trade-offs your design already made (consistency vs availability, latency vs throughput, cost vs redundancy) rather than leaving them implicit — see `08_cap_theorem_and_consistency.md` for the vocabulary.

### 8. Wrap up (~5 min)

Summarize the design in a few sentences, and proactively mention what you'd do with more time — things you knowingly deferred (e.g., "I'd add a dedicated search index for full-text post search, and I'd want to dig deeper into exactly-once delivery guarantees for the notification path"). This shows self-awareness about the design's current gaps rather than presenting it as finished and perfect.

```text
 5 min      5 min        15 min          20 min           5 min    5 min
┌───────┬───────────┬──────────────┬────────────────┬───────────┬───────┐
│Clarify│ Estimate  │ High-level   │   Deep dive     │Bottlenecks│ Wrap  │
│  reqs │  scale    │ design + API │  (1-2 hard      │ & trade-  │  up   │
│       │           │ + data model │   parts)        │   offs    │       │
└───────┴───────────┴──────────────┴────────────────┴───────────┴───────┘
                                          ▲
                              strong vs weak candidates
                              separate here, most of all
```

## A Compressed Worked Example

To make the framework concrete, here's how the 8 steps might sound in practice for "design a URL shortener," compressed to a few lines per step (the full version of this exact system is `02_Interview_Questions/03_url_shortener.md`):

1. **Clarify**: "Should short codes be user-chosen (custom aliases) or system-generated? Do links expire? Is click analytics in scope?" → agree: system-generated codes, optional expiry, basic click count only.
2. **Estimate**: 100M new URLs/month ≈ ~40 writes/sec average; reads (redirects) are typically ~100x writes ≈ ~4K reads/sec; each mapping is tiny (a few hundred bytes), so storage is dominated by count, not size.
3. **High-level design**: client → load balancer → app service → DB for the mapping, cache in front of the DB for hot redirects (redirects are extremely read-heavy and highly cacheable).
4. **API**: `POST /urls {long_url, expiry?} -> {short_url}`, `GET /:code -> 302 to long_url`.
5. **Data model**: a simple key-value mapping (`short_code -> long_url, expiry, created_at`) — no relational joins needed, so a key-value store or a simple relational table both work; pick based on expected scale.
6. **Deep dive**: how short codes are generated without collisions at this write rate without a single bottlenecked counter — e.g., base62-encoding a distributed unique ID (see `02_Interview_Questions/01_distributed_id_generator.md`) instead of a naive auto-increment column on one DB.
7. **Bottlenecks**: the cache absorbs almost all redirect traffic, so the DB itself is rarely the bottleneck for reads; the write path is low-volume enough that a single primary with replicas is likely sufficient — explicitly say so rather than reflexively sharding a system that doesn't need it yet.
8. **Wrap-up**: summarize the design in two sentences; mention that with more time you'd cover analytics aggregation and custom alias collision handling.

Notice the deep dive (step 6) is the one place real problem-solving happens — everything before it is establishing shared context, and everything after it is stress-testing what was built.

## Common Mistakes

- **Diving into low-level details before establishing a high-level design.** Spending the first 10 minutes on exact schema field types or a specific caching library before the interviewer even knows your overall architecture — they can't follow or challenge reasoning they haven't seen yet, and you risk building fine detail onto a foundation you'll have to rip up later.
- **Not asking clarifying questions and silently assuming requirements.** The single most damaging early mistake — you might spend the entire interview designing a system for the wrong scale, the wrong consistency needs, or the wrong feature set, and there may not be time to recover once it's discovered late.
- **Over-engineering for infinite scale when the interviewer described a modest system.** Reaching for sharding, multi-region replication, and a message queue for a system the interviewer scoped at "a few thousand users" signals you can't calibrate complexity to actual requirements — which is itself the core skill being tested (see `01_what_is_system_design.md`'s core mindset section).
- **Under-engineering and ignoring scale entirely.** The opposite failure — designing as if a single server and a single database will handle whatever numbers were established in step 2, with no acknowledgment of where that breaks. Both directions signal the same underlying gap: not connecting the design to the stated constraints.
- **Never stating trade-offs out loud — just silently picking one option.** Choosing eventual consistency, or a NoSQL store, or async processing, without saying *why*, denies the interviewer the chance to see your reasoning (which is most of what's being evaluated) and makes it look like you don't know there was a choice to make at all.
- **Going quiet for long stretches while thinking, instead of narrating.** An interview is not a silent exam — long silences leave the interviewer unable to follow your reasoning or course-correct you early, and it reads as uncertainty even when you're actually making good progress internally.
- **Not managing time, and running out before the deep dive.** Since the deep dive is the highest-signal part of the interview, spending too long drawing the initial architecture (or over-polishing a diagram) at its expense is one of the costliest mistakes you can make — actively watch the clock and move yourself along.
- **Treating it like a whiteboard art exercise instead of a technical conversation.** Focusing on a tidy diagram over substantive reasoning, or not engaging with the interviewer's questions/pushback as real signal to incorporate, misses that the interview is evaluating how you think and communicate under ambiguity — not your box-and-arrow drawing skill.

## How to Communicate While Designing

- **Think out loud, continuously.** State your reasoning as you go, including the options you're weighing and why you're picking one — the interviewer is grading the reasoning process, not just the final diagram, and they cannot grade what they can't hear.
- **Treat the interviewer as a collaborator, not an examiner to defend against.** They're a stakeholder you're driving toward shared understanding and alignment with — someone building this with you, whose questions are meant to help you land on a better design, not "gotchas" to survive.
- **Periodically check in.** Explicitly pause at natural boundaries and ask things like "does this direction make sense, or would you like me to go deeper on X?" — this keeps you correctly calibrated on where to spend the limited time, rather than guessing and potentially going deep on the wrong thing for 15 minutes.
- **Explicitly name trade-offs as you make choices.** E.g., "I'm choosing eventual consistency here because this system needs to prioritize availability and low latency over every reader seeing the absolute latest write" — say the trade-off out loud at the moment you make the choice, not only if asked about it later. This single habit is one of the highest-leverage things you can do in the entire interview, because it directly demonstrates the trade-off reasoning that system design interviews exist to test.

## How This Maps to the Interview Questions Folder

Every file in `02_Interview_Questions/` follows this exact same step structure: clarify → estimate → high-level design → API → data model → deep dive → bottlenecks → follow-ups. That's not a coincidence — it's the same framework from this file, applied end-to-end to a specific system (a URL shortener, a rate limiter, a news feed, a chat app, and so on).

This means working through those files isn't just "learning how those specific systems are built" — it's directly practicing this framework, repeatedly, against varied problems, the same way solving problems in `dsa.rb` builds pattern recognition for algorithmic problem types by repeatedly applying the same small set of techniques (two pointers, sliding window, BFS/DFS, DP) across many different problems. Here, the "techniques" are the 8 framework steps and the vocabulary from `01_Concepts/01` through `15`, and the "problems" are the systems in `02_Interview_Questions/`.

Practically: don't just read those files passively. Before reading a given file's design, try running the framework yourself on that system's prompt first (clarify, estimate, sketch a high-level design, pick a deep-dive target) — then compare against the worked version. The gap between your attempt and the worked design is exactly where your practice should focus.

## Quick Recall — Self-Test

**Q1: What's the single biggest interview mistake candidates make in the first 5 minutes?**
Not asking clarifying questions and instead silently assuming requirements — this can result in designing the wrong system for the wrong scale or feature scope, and there may not be time left to recover once the mismatch surfaces.

**Q2: Why is the deep-dive step the most important part of a 45-60 minute interview, and what's a realistic time budget for it?**
It's where strong and weak candidates separate, because it requires genuine reasoning through a hard, specific problem rather than reciting component names — a realistic budget is roughly 15-20 minutes, the largest single block of the interview.

**Q3: What's the difference between over-engineering and under-engineering in this context, and why are both mistakes?**
Over-engineering applies heavy-scale patterns (sharding, multi-region, queues) to a system the interviewer scoped as small; under-engineering ignores the stated scale entirely and designs as if a single server suffices regardless of the numbers established in the estimation step. Both signal the same failure: not calibrating the design to the actual stated constraints.

**Q4: Why should you state trade-offs out loud rather than silently picking one option?**
The interview is evaluating your reasoning process, not just your final architecture — a silently made choice (e.g., picking eventual consistency) gives the interviewer no visibility into whether you understood there was a choice at all, while naming it explicitly demonstrates the trade-off reasoning the interview exists to test.

**Q5: How should you decide what to focus on in the deep-dive step?**
Identify the part of the system that's genuinely hard or non-obvious, where a naive approach clearly breaks (e.g., unique ID generation at scale, feed fan-out strategy), and follow any direct signal from the interviewer (a specific "what happens when X fails" or "handle 100x load here" question) toward where they want you to go deep.

**Q6: What should you do at natural checkpoints during the design, and why?**
Periodically check in with the interviewer — e.g., "does this direction make sense, or should I go deeper on X?" — because it keeps you calibrated on where the limited interview time should actually be spent, rather than guessing and risking a long detour on the wrong part.

**Q7: How does this framework relate to the files in `02_Interview_Questions/`?**
Every file there follows the exact same 8-step structure (clarify, estimate, high-level design, API, data model, deep dive, bottlenecks, follow-ups) applied to a specific system, so working through them is direct, repeated practice of this framework — analogous to how solving problems in `dsa.rb` builds pattern recognition through repeated application of a small set of core techniques.

**Q8: Why treat the interviewer as a collaborator rather than an examiner?**
Because the interview is structured as a technical conversation, not a silent exam — the interviewer's questions and pushback are meant to help steer you toward a better design and are genuine signal to incorporate, not obstacles to defend against; engaging with them as a collaborator also keeps you talking and narrating, avoiding the silence mistake.

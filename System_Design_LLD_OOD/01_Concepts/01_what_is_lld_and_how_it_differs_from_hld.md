# What Is LLD/OOD, and How It Differs from HLD

## Definition

**Low-Level Design (LLD)**, also called **Object-Oriented Design (OOD)**, is
the practice of designing the classes, interfaces, methods, and relationships
that make up a **single application or process** so that the resulting code
is correct, readable, and easy to extend without rewriting it. The unit of
design is the **class** (and the object it produces at runtime). The core
question LLD answers is: *"Given this problem, what objects exist, what does
each one know, what does each one do, and how do they collaborate?"*

**High-Level Design (HLD)**, the subject of the sibling `System_Design/`
folder in this repo, is the practice of designing how a system is
**distributed across many machines/services** so it can handle scale,
availability, and failure. The unit of design is the **service** (or
component: database, cache, queue, load balancer). The core question HLD
answers is: *"Given this load and these failure modes, how do we split the
work across machines, and what do we do when a machine dies?"*

Both are "design" in the sense of "think before you code," but they operate
at entirely different altitudes. LLD is about the shape of code inside one
process. HLD is about the shape of a system across a network. A single
service in an HLD diagram — say, "Booking Service" — is itself something you
would apply LLD to internally: what classes does the Booking Service
contain, how do `Booking`, `Slot`, and `Payment` objects relate? The two
disciplines compose; they don't compete.

## Why it matters

Without a clear mental model of which discipline a question belongs to, two
failure modes show up constantly in interviews (and in real design docs):

1. **An LLD question gets an HLD answer.** Asked "design a parking lot using
   OOP," a candidate who defaults to systems thinking starts talking about
   "we'd put spot availability in Redis for fast reads, shard the database by
   region, and put a load balancer in front of the API." None of that is
   wrong in a real production system, but it completely dodges the actual
   ask: classes, inheritance, polymorphism, how a van consumes 3 bike spots.
   The interviewer wanted to see object modeling and got a whiteboard full
   of boxes labeled "DB" and "Cache" instead.

2. **An HLD question gets an LLD answer.** Asked "design a URL shortener
   that handles 10 million requests a day," a candidate who defaults to
   class modeling starts writing a `UrlShortener` class with an
   `encode(long_url)` method and a `Hash` for storage, and spends 20 minutes
   perfecting the base-62 encoding algorithm. Meanwhile the interviewer
   wanted to hear about read/write ratio, caching layers, database choice
   and indexing strategy, and horizontal scaling — none of which showed up
   because the candidate was heads-down in a single class's method body.

Both are "answering the wrong question well." The interviewer isn't grading
whether your code compiles in your head — they're grading whether you
correctly identified what kind of problem this is and brought the right
toolkit to it. Getting this triage right in the first 60 seconds is worth
more than any amount of polish on the wrong kind of answer.

The same confusion costs real time in production work too: a team that
tries to solve a class-modeling problem ("our `Order` object has become a
1500-line god class") by reaching for infrastructure changes (splitting it
into microservices) instead of an LLD refactor (extracting collaborator
classes, applying Single Responsibility) ends up with a distributed version
of the same tangled object graph, now with network calls in between.

## LLD vs HLD: Comparison Table

| Dimension | LLD / OOD | HLD |
|---|---|---|
| Unit of design | Classes, objects, interfaces | Services, components, machines |
| Primary concern | Correctness, readability, extensibility of code | Scalability, availability, fault tolerance across machines |
| Core skill tested | OOP modeling, design patterns, SOLID | Distributed systems trade-offs (CAP, sharding, caching, queues) |
| Typical question framing | "Design the classes for X. Now extend it to support Y." | "Design X to handle N million users/requests." |
| Artifact produced | Class diagram, method signatures, working code | Architecture diagram (boxes: services, DBs, caches, queues) |
| Failure looks like | God classes, `case type` chains, fragile inheritance | Single points of failure, unbounded growth, data loss on partition |
| Where it runs | Inside one process/application | Across a network of processes |
| Example deep dive in this repo | `LLD_OOD/02_Interview_Questions/01_parking_lot.md` | `System_Design/01_Concepts/16_interview_framework.md` |

## The diagnostic skill: recognizing which kind of question you're being asked

This is the single most directly useful thing in this file. Interviewers
rarely say "this is an LLD question" out loud — you have to infer it from
phrasing, and sometimes from a pivot mid-interview (more on that below).
Here is how to read the signal:

**Signals that point to LLD:**
- The prompt names a bounded, single-application domain: a parking lot, a
  chess game, an elevator system, a library management system, a
  tic-tac-toe game, a vending machine, a movie ticket booking *flow* (not
  the whole platform).
- The prompt says "design the classes for," "model," "design the system
  using OOP," or asks you to "extend it to support" a new variant.
- There is no mention of request volume, number of users, latency budgets,
  or "at scale."
- The interesting complexity is in the **rules and relationships between
  entities** (a van takes 3 bike spots; a bishop moves diagonally; an
  elevator picks the nearest request in its direction of travel), not in
  **data volume or network topology**.

**Signals that point to HLD:**
- The prompt names a platform or product used by many people: "design
  Twitter," "design WhatsApp," "design Uber," "design a URL shortener,"
  "design Netflix."
- The prompt gives you a number: "handles 10 million requests/day," "100M
  daily active users," "must respond within 200ms at p99."
- The interesting complexity is in **data volume, availability, and
  distribution** (how do you shard this table, what happens if this
  region goes down, how do you cache this hot read).

**Worked examples, classified explicitly:**

| Prompt | Classification | Why |
|---|---|---|
| "Design a parking lot" | LLD | Single-facility domain, no user-count/scale language, complexity is in vehicle/spot rules. |
| "Design a URL shortener that handles 10M requests/day" | HLD | Explicit scale number; the interesting problem is storage, caching, and encoding uniqueness at volume. |
| "Design a chess game" | LLD | Bounded rules engine, one game at a time, complexity is in modeling pieces/moves/board state. |
| "Design WhatsApp" | HLD (usually) | Named platform, implies millions of concurrent users, message delivery guarantees, presence — a systems problem. |
| "Design the message class hierarchy for a chat app" | LLD | Same domain as WhatsApp, but explicitly scoped to "class hierarchy" — no scale language, pure object modeling. |
| "Design a vending machine" | LLD | Single machine, state-machine-like behavior (idle, has-money, dispensing), classic OOD interview staple. |
| "Design an elevator system for a 40-floor building" | LLD | Bounded to one building; the hard part is scheduling algorithm and elevator/request object modeling, not distributed scale. |
| "Design a ride-sharing service like Uber" | HLD | Platform-scale, involves geospatial matching across millions of drivers/riders — a distributed systems problem. |
| "Design a rate limiter" | Ambiguous by default — often HLD (if framed as "for our API gateway handling X requests/sec") but can be LLD ("implement a `RateLimiter` class using the token bucket algorithm") | Check for scale language or a specific data-structure/algorithm ask. |

The pattern: **named platforms serving many concurrent external users tend
to be HLD; bounded single-instance domains, or a prompt that explicitly
narrows to "classes"/"model"/"hierarchy," tend to be LLD.** When genuinely
ambiguous (the rate limiter case), it is completely fair — and a strong
signal — to ask the interviewer directly: "Should I focus on the class
design and algorithm here, or do you want me to also cover how this scales
across multiple servers?" That question alone demonstrates you know the
distinction exists, which is half of what's being evaluated.

## The blended question: recognizing a mid-interview pivot

Some interviews deliberately blend both. A common shape: "Design a movie
ticket booking system" starts as an HLD conversation (services, database
choice, handling concurrent seat-booking requests), and after 15-20 minutes
the interviewer says "okay, now let's zoom into the seat-selection and
booking logic — show me the core classes for how you'd prevent two people
from booking the same seat." That's a pivot from HLD into LLD mid-interview,
and it's deliberate: the interviewer wants to see whether you can operate
at both altitudes, and — critically — whether you **notice the pivot** and
switch modes rather than continuing to talk about database replication when
you should be sketching a `Seat`/`Booking`/`Show` class diagram with an
explicit locking or state-transition mechanism (e.g., a `Seat` moves from
`available` to `locked` to `booked`, and only one thread/request can win
that transition — this is where you'd bring up an atomic compare-and-swap
on `Seat#status`, echoing the same race-condition concern the parking lot
example raises for concurrent `park` calls).

The tell that a pivot is happening: the interviewer starts asking about
specific business rules, edge cases, or "show me the code for X" instead of
"how would this scale" or "what happens if this server goes down." When you
hear that shift, say so out loud — "got it, let's move from the
architecture level into the actual class design for this piece" — and
change what you're drawing. Naming the pivot is itself part of the signal
you're sending; silently continuing in the wrong mode is the mistake this
whole file exists to prevent.

**A worked mini-dialogue, to make the pivot concrete:**

```
Interviewer: "Design a movie ticket booking system."
Candidate:   "Let's start with the high-level shape: a Booking Service
             behind an API, a Postgres database for shows/seats/bookings,
             and probably a cache in front of show listings since those
             are read-heavy. For booking itself, the tricky part is two
             users hitting 'book' on the same seat at once — I'd handle
             that with a short-lived lock or a DB-level unique constraint
             on (show_id, seat_id) for confirmed bookings."
Interviewer: "Okay — walk me through the actual classes and how you'd
             implement that seat-locking logic."
Candidate:   "Got it, switching from architecture to the class design for
             this piece specifically." [draws Show / Seat / Booking, and
             a Seat#status state machine: available -> locked -> booked,
             with the transition guarded by a single atomic update]
```

Notice what the candidate did at the pivot: said it out loud in one short
sentence, then immediately changed what they were producing (from service
boxes to a class diagram and a state machine) instead of continuing to
elaborate on caching or database choice. That explicit acknowledgment plus
the visible change in output is the whole skill — an interviewer watching
for it sees confirmation you tracked the shift, not just luck that you
happened to keep talking about something relevant.

## What a Strong Opening Sounds Like, by Mode

The first 60 seconds set the frame for the rest of the interview, and what
you say differs meaningfully depending on which kind of question you've
identified:

**Opening an LLD question** (e.g., "design a parking lot"):
- Confirm scope: "This is about the class design for a single parking
  facility, not multiple locations or concurrent access at scale — should
  I assume single-process, or do you want me to note concurrency
  concerns too?"
- Move immediately to requirements and nouns: "Let me list the entities
  I'm seeing: Vehicle, ParkingSpot, ParkingLot, and probably a Ticket to
  track an active parking session."
- Do **not** open with storage choice, caching, or load balancing — those
  answers don't exist yet at this altitude, and reaching for them signals
  you're pattern-matching to HLD out of habit.

**Opening an HLD question** (e.g., "design a URL shortener for 10M
requests/day"):
- Confirm scale and constraints first: "What's the read/write ratio, and
  do shortened URLs need to be globally unique immediately, or is
  eventual consistency acceptable?"
- Move to back-of-envelope estimation before any class talk: requests/sec,
  storage growth per year, cache hit rate assumptions.
- Do **not** open by sketching a `UrlShortener` class with an `encode`
  method — that's answering the LLD sub-problem before establishing the
  system-level constraints that should shape it.

**Opening a blended or ambiguous question** (e.g., "design a rate
limiter"):
- Ask which altitude is wanted before committing either way — this single
  question is often worth more than either a full LLD or full HLD answer
  delivered to the wrong expectation.
- If told "both," sequence it explicitly: "I'll cover the algorithm and
  class design first, then talk about how this holds up distributed
  across multiple servers" — and actually follow that structure rather
  than blending the two answers together mid-stream.

## Common Misconceptions

**"LLD is just easier/smaller HLD."** No — they test different skills
entirely, not the same skill at different sizes. An excellent HLD
candidate can still fail an LLD interview by not knowing SOLID, design
patterns, or how to model polymorphism, and vice versa. Treat them as two
separate skill sets to prepare for, not one skill scaled down.

**"If a question doesn't mention scale, infrastructure discussion is
still a safe thing to mention briefly."** A one-sentence acknowledgment
("this would sit behind an API in a real deployment") is fine and often
expected. Spending real time on it — sketching services, discussing a
database schema, mentioning a cache — is not safe; it directly eats time
budgeted for the class design the question actually wants, and reads as
not having correctly triaged the question.

**"Design patterns belong only to LLD, distributed systems concepts
belong only to HLD, so I can prepare them independently."** Mostly true
as a study split, but the boundary case is worth knowing: the Strategy
pattern (used for `PricingStrategy` in the parking lot follow-ups) is an
LLD/OOD concept, while a distributed lock (needed if that same parking
lot ran across multiple servers) is an HLD concept — the same feature
(pricing, or concurrent booking) can require both, depending on which
layer of the problem you're currently being asked about.

**"Once I've correctly identified LLD vs. HLD, I'm done triaging."** Not
quite — some interviews pivot mid-way (see above), so the identification
isn't a one-time decision made in minute one; it's something to keep
re-checking as the conversation evolves, especially right after you think
you've finished the "first pass" of a design.

## Interview Tips

- In the first minute, explicitly state which kind of question you think
  this is: "This sounds like an LLD/OOD question — you want me to focus on
  class design and relationships rather than infrastructure scaling, is
  that right?" This costs 10 seconds and prevents 10 minutes of misaligned
  work; interviewers consistently react well to it because it shows
  self-awareness about the discipline being tested.
- If a "design X" prompt is ambiguous, ask directly. Never guess silently
  and burn 15 minutes in the wrong mode — the interviewer would much rather
  answer a 5-second clarifying question than watch you build the wrong
  thing.
- If you notice a pivot mid-interview (systems talk turning into "show me
  the classes for..."), narrate the switch. It signals you're tracking the
  interviewer's intent, not just executing a memorized script.
- Don't over-correct into rigidity: some questions genuinely want a brief
  HLD framing ("this would sit behind an API, but let's focus on...") before
  diving into LLD. A single sentence of HLD context is fine and often
  expected; the mistake is spending real time there when the ask is LLD.
- For the step-by-step process of actually working through an LLD question
  once you've identified it as one (clarify requirements, identify objects,
  identify relationships, design, code, discuss edge cases/extensibility),
  see `08_lld_interview_framework.md` in this same folder — it plays the
  same role for LLD that `System_Design/01_Concepts/16_interview_framework.md`
  plays for HLD.

## Quick Recall — Self-Test

1. **What is the unit of design in LLD, and what is it in HLD?**
   LLD's unit of design is the class (and the objects it produces at
   runtime) within a single application or process. HLD's unit of design is
   the service or component (database, cache, queue, load balancer)
   distributed across a network of machines.

2. **A prompt says "design Instagram." Is this LLD or HLD, and what would
   make you reconsider?**
   Default classification is HLD — it's a named platform implying millions
   of concurrent users, feed generation, media storage at scale. It would
   become LLD if narrowed to something like "design the class hierarchy for
   Instagram's post/story/reel content types," which drops the scale
   framing and asks for object modeling instead.

3. **Name two concrete signals in a prompt's wording that point to HLD
   rather than LLD.**
   A specific scale number (e.g., "10 million requests/day," "100M DAU"),
   and framing around named platforms/products used by many external users
   rather than a single bounded instance (one parking lot, one chess game,
   one elevator bank).

4. **What is the "wrong question well" failure mode, and why is it worse
   than a partially wrong answer to the right question?**
   It's giving a technically correct, polished answer to a different
   problem than the one asked — e.g., discussing database sharding when
   asked to design a parking lot's classes. It's worse than a partial
   right-question answer because it signals you can't correctly triage
   problems, which is itself part of what's being evaluated, independent of
   your technical depth.

5. **Describe what a mid-interview HLD-to-LLD pivot looks like, and what you
   should do when you notice one.**
   The interviewer starts asking about specific business rules, edge cases,
   or says "show me the classes/code for X" after a period of
   architecture-level discussion. You should say so explicitly ("let's move
   from architecture into the class design for this piece") and switch to
   sketching class boxes and relationships instead of continuing to discuss
   infrastructure.

6. **Why is it acceptable, and even a good sign, to ask the interviewer
   directly whether a question is LLD or HLD?**
   Some prompts (like "design a rate limiter") are genuinely ambiguous
   without more context. Asking costs seconds and demonstrates you
   understand the two disciplines are distinct and require different
   approaches — silently guessing wrong can cost most of the interview.

7. **Give one example of a real-world (non-interview) cost of confusing
   these two disciplines.**
   A team facing a class-modeling problem — e.g., an `Order` class that has
   grown into an unmaintainable god object — reaches for an infrastructure
   fix (splitting into microservices) instead of an LLD refactor
   (extracting collaborator classes per Single Responsibility), ending up
   with the same tangled object graph now spread across a network with
   added latency and operational complexity.

8. **What HLD counterpart file plays the same role as
   `08_lld_interview_framework.md` will play for this folder?**
   `System_Design/01_Concepts/16_interview_framework.md` — it gives the
   step-by-step approach for working through an HLD question, the way
   `08_lld_interview_framework.md` will for LLD questions.

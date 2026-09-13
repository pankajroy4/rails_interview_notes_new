# The LLD Interview Framework

A repeatable step-by-step approach for walking into any "design X using
OOP" prompt — Parking Lot, Vending Machine, ATM, Elevator, Tic-Tac-Toe,
whatever the specific object is — without freezing on where to start or
rushing straight to code. This is the LLD equivalent of what
`System_Design/01_Concepts/16_interview_framework.md` does for HLD
questions; the shape of the process is similar, but the substance is
different: HLD framework steps end in servers/databases/scaling
trade-offs, LLD framework steps end in classes/interfaces/methods.

## The Framework

Budgeted for a realistic 45-minute LLD interview. Times are guidance, not
a rulebook — talk to your interviewer about scope if a step is clearly
going to run long.

**1. Clarify functional requirements AND scope (~5 minutes).**
Don't just list what the system does — explicitly state what's *out of
scope* too. LLD prompts are intentionally underspecified and can balloon
to cover far more than 45 minutes allows if you try to design everything
at once. Say things like "I'll assume single-threaded for now and
mention concurrency as a follow-up if we have time" or "I'll design for a
single parking lot, not a multi-location chain, unless you want me to."
This does two things: it keeps your design achievably sized, and it shows
the interviewer you know how to scope a problem — a skill they're
explicitly evaluating, not just a time-saving trick.

**2. Identify core objects/entities (~5 minutes).**
Read back through the requirements and pull out the nouns — they're
almost always your first-pass class list. "A parking lot has spots, and
vehicles park in spots, and get a ticket" surfaces `ParkingLot`,
`ParkingSpot`, `Vehicle`, `ParkingTicket` directly from the sentence. Say
this out loud — "let me pull the nouns out of the problem statement" is a
legible, teachable step for the interviewer to follow, versus silently
producing a class list from nowhere.

**3. Identify relationships between them (~5 minutes).**
Sketch a class diagram — even a rough text/ASCII one — showing inheritance
(is-a), composition (owns, dies with owner), aggregation (owns, but
survives independently), and association (references, but no ownership
implied). Getting this vocabulary right is itself a signal; see
`04_uml_and_class_diagrams.md` for the notation and a full worked
breakdown of these relationship types.

**4. Identify key behaviors/methods on each class (~5-8 minutes).**
For each class, what does it need to *do*, not just what data does it
hold? This is where you decide which class owns which responsibility —
the most common failure here is putting all behavior on one "manager"
class (e.g., cramming vehicle-specific rules into `ParkingLot`) instead of
letting each object own its own behavior.

**5. Spot places where a design pattern genuinely helps (~5 minutes).**
This step comes *after* you already have objects, relationships, and
behaviors sketched — not before. Look at what you've drawn and ask "is
there a `case`/`if` chain here that polymorphism would remove? Is there an
object whose behavior depends on an internal status field? Do I need to
add behavior to specific instances without touching a whole class?" Reach
for a pattern because the shape you already have calls for it, not because
you want to demonstrate you know the pattern's name. Cross-reference
`05_design_patterns_creational.md`, `06_design_patterns_structural.md`,
and `07_design_patterns_behavioral.md` for the catalog.

**6. Write working code for the core classes (~10-12 minutes).**
Not everything — pick the 2-3 classes that matter most to the problem's
central challenge (in Parking Lot, that's `Vehicle`'s hierarchy and
`ParkingLot#park`/`#unpark`; the surrounding classes like `ParkingSpot` can
be thinner). Say out loud which classes you're prioritizing and why, so
the interviewer isn't left wondering if you forgot the rest.

**7. Walk through the main use case end-to-end against your code (~3-5
minutes).**
Literally trace a call (e.g., "a Van arrives, `park` is called, it tries
`:van_spot` first...") through your actual method bodies. This step
catches real bugs (an off-by-one, a spot type mismatch) before the
interviewer does, and demonstrates you test your own designs rather than
declaring victory the moment the code compiles in your head.

**8. Discuss edge cases and extensibility (~5 minutes, often
interviewer-driven).**
"How would you add a new vehicle type?" "What if two people park at the
exact same time?" "How would you add multi-floor support?" You often don't
need to write more code here — describing precisely which classes would
change (ideally: only new ones, zero edits to existing ones) is the
answer, and it's a direct payoff of steps 2-5 being done well.

```text
 1. Scope        2. Objects       3. Relationships     4. Behaviors
 (5 min)   -->    (5 min)   -->    (5 min)       -->    (5-8 min)
    |                                                        |
    v                                                        v
 8. Edge cases  <--  7. Walk through  <--  6. Write code  <--  5. Patterns
 (5 min)             (3-5 min)             (10-12 min)         (5 min)

 Total: ~45 min. Steps 1-5 are "design," 6-8 are "prove the design works."
 Spending the whole 45 minutes in step 6 (jumping to code early) is the
 single most common way this framework gets skipped under pressure.
```

## Common Mistakes

- **Jumping straight to code before sketching any class structure.**
  Feels productive because you're typing, but you'll typically end up
  redesigning mid-way once a relationship you didn't think through (e.g.,
  "wait, how does un-parking a van free all 3 spots?") surfaces inside a
  method body instead of on a diagram, which is a far more expensive place
  to discover it.
- **Building a deep inheritance hierarchy where composition would be more
  flexible.** A `Vehicle -> LandVehicle -> WheeledVehicle -> Car` chain
  built preemptively "because it might be needed" adds rigidity without
  payoff — every layer is a coupling point. Prefer the shallowest
  hierarchy that satisfies the actual requirements, and reach for
  composition (an object *has* a capability, via a small collaborator
  object) when behavior needs to mix and match rather than strictly
  specialize.
- **Reaching for a design pattern because you know it, not because the
  problem calls for it.** Pattern-first thinking is a very recognizable
  failure mode to interviewers — e.g., forcing an Observer into a design
  with no actual notification requirement, just to show you know
  Observer. Patterns should be the answer to a specific pain point you've
  already identified in your own design (step 5 above), never the
  starting point.
- **Ignoring the interviewer's "what if we also need to support X"
  follow-ups instead of adapting the design live.** These follow-ups are
  the actual test — a design that can't absorb a reasonable extension
  without a rewrite usually indicates a responsibility was put on the
  wrong class earlier. Treat every follow-up as a chance to demonstrate
  Open/Closed in action, not as a nuisance to route around.
- **Conflating this with an HLD question and starting to talk about
  databases/servers when the interviewer wanted classes.** LLD interviews
  are about object design inside a single process/codebase — talking about
  horizontal scaling or database sharding when asked to design a parking
  lot's classes is answering the wrong question. See
  `01_what_is_lld_and_how_it_differs_from_hld.md` for exactly where that
  boundary sits, and how to bridge to it *briefly* only if the interviewer
  explicitly pulls you there (as the parking lot file's concurrency/
  multi-location follow-ups do).
- **Not stating assumptions/scope out loud, leading to over-building.**
  Silently deciding "I'll support multi-floor and concurrent access and
  pricing and reservations" without checking scope first is how 45 minutes
  disappears into an unfinished `ParkingLot` class. State the scope,
  explicitly, in step 1 — and revise it out loud if the interviewer
  pushes back.

## How to Communicate While Designing

- **Think out loud, always** — narrate *why* you're choosing composition
  over inheritance, or reaching for a specific pattern, not just the fact
  that you're doing it. "I'm making `Vehicle` an abstract class with
  `spots_required` as the one method subclasses must implement, so
  `ParkingLot` never has to branch on vehicle type" is a complete,
  gradeable sentence; silently writing the same code is not.
- **Name SOLID principles explicitly when they justify a decision.**
  "This keeps `ParkingLot` closed to modification when a new vehicle type
  is added — Open/Closed" is a stronger, more specific statement than "this
  is more extensible." See `03_solid_principles.md` for the full set and
  how each shows up in code, not just in name.
- **Check in with the interviewer on scope before diving deep into one
  area.** Before spending 10 minutes fully fleshing out pricing logic, ask
  "do you want me to go deep on pricing, or keep it as a stub and move on
  to un-parking?" — this keeps you from over-investing in a corner of the
  design the interviewer doesn't actually care about.

## How This Maps to the Interview Questions Folder

Every file in `02_Interview_Questions/` follows this exact same shape:
requirements and scope, then core objects, then relationships (a class
diagram), then design decisions and which patterns apply and why, then
code for the classes that matter most, then edge cases and extensibility,
then likely follow-up questions. That's not a coincidence — it's this
framework, applied. Working through those files isn't just "reading worked
examples" — it's rehearsing this exact framework end-to-end each time, so
treat each one as a timed practice run: read the problem statement only,
work through steps 1-8 yourself first, then compare against the file.

## Quick Recall — Self-Test

1. **What's the first concrete thing you should do when given an LLD
   prompt, before writing any code?**
   Clarify the functional scope and explicitly state what's out of scope,
   then extract the core nouns as candidate classes — jumping to code
   first usually means redesigning later once requirements surface mid-
   implementation.

2. **Why does stating scope out loud matter as much as actually having a
   scoped design?**
   Because the interviewer is evaluating whether you *can* scope a
   problem down, not just whether your final design happens to be
   reasonably sized — a candidate who silently limits scope looks
   identical, from the interviewer's seat, to one who never considered the
   larger version at all.

3. **At what point in the framework should you look for a design pattern
   to apply, and why not earlier?**
   After objects, relationships, and behaviors are sketched (step 5, not
   step 1) — because patterns should solve a concrete pain point you've
   already identified in your own design, not be forced onto the problem
   before you know what shape it actually has.

4. **Give one concrete tell that a design has put too much responsibility
   on one "manager" class.**
   That class contains `if`/`case` branches on another object's type or
   status (e.g., `ParkingLot` branching on `vehicle.type`) — that logic
   belongs on the object whose type/status is being checked, not on the
   class orchestrating it.

5. **Why is "ignoring the interviewer's follow-up questions" treated as a
   mistake rather than just an omission?**
   Follow-ups ARE the test of extensibility, not a distraction from it — a
   design that can't absorb "what if we also need X" without a rewrite
   usually means a responsibility was assigned to the wrong class earlier,
   and dodging the follow-up hides exactly the thing being evaluated.

6. **How should you respond if an LLD interviewer starts asking about
   database schemas or server scaling?**
   Recognize that as a bridge into HLD territory and name that transition
   explicitly ("that's moving into the distributed-systems version of this
   problem") rather than silently trying to answer an HLD question using
   LLD framing, or vice versa — see
   `01_what_is_lld_and_how_it_differs_from_hld.md`.

7. **What's the difference between narrating "I'm using composition here"
   and narrating "I'm using composition here because X"?**
   The first states a fact the interviewer can already see in your code;
   the second demonstrates judgment — the actual thing being evaluated.
   Always include the "because."

8. **Why is `02_Interview_Questions/` described as practicing this
   framework, rather than just as reference material?**
   Because every file in it follows the same requirements-objects-
   relationships-decisions-code-extensibility shape this framework
   prescribes — reading one passively teaches less than treating the
   problem statement as a timed prompt and working through the 8 steps
   yourself before comparing against the file's answer.

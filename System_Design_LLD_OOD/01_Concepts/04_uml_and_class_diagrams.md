# UML and Class Diagrams

**UML (Unified Modeling Language)** is a standardized set of diagram
notations for visualizing software design. In LLD interviews, the only
corner of UML that matters is the **class diagram** — a way to sketch
classes, their members, and the relationships between them before (or
while) writing code.

## Why it matters

A class diagram is the fastest way to communicate your object model to
another person. Explaining "there's a `ParkingLot` that owns many
`ParkingSpot`s, and `Vehicle` is a base class with `Bike`, `Car`, and `Van`
subclasses" out loud, sentence by sentence, is slow and easy to lose track
of — both for you and for the interviewer. A ten-second sketch showing
boxes and arrows conveys the same structure instantly and gives the
interviewer something concrete to point at when they ask "what happens
here if..." Many interviewers explicitly ask you to sketch a class diagram
(on a whiteboard, in a shared doc, or in a code comment) before or
alongside writing code, specifically because it reveals your object model
faster than reading code line by line would.

Without this skill, two things go wrong. First, candidates jump straight
into code without ever externalizing the object model, so the interviewer
can't see the design until it's fully typed out — any misunderstanding
gets caught late, after significant time is sunk. Second, candidates who
do attempt a diagram often blur the relationship types (drawing every
connection as a plain line, or worse, describing a composition as
"inheritance" by mistake), which signals confusion about the underlying
concepts, not just the notation. Precision in the arrows is precision in
the design.

## Class Box Notation

A UML class box has three compartments: **class name**, **attributes**,
**methods**. Visibility is marked with a prefix: `+` public, `-` private,
`#` protected.

```text
+-----------------------------------+
|              ParkingSpot           |
+-----------------------------------+
| + id: String                       |
| + spot_type: Symbol                |
| - occupied_by: Vehicle             |
+-----------------------------------+
| + occupied?() : Boolean            |
| + occupy(vehicle: Vehicle) : void  |
| + vacate() : void                  |
+-----------------------------------+
```

Reading this box: `ParkingSpot` has a public `id` and `spot_type`, a
private `occupied_by` (only accessible from within the class, matching how
`ParkingSpot` in the parking lot example exposes `occupied_by` only via a
controlled accessor rather than raw mutation from anywhere), and three
public methods. In an interview, drawing the full three-compartment box
with types for every attribute is usually overkill — see the "Practical
Interview Guidance" section below for how much detail is actually
expected.

## Relationship Types

This is the part people get genuinely confused about — the four
relationship types below look superficially similar (lines and arrows
between boxes) but mean structurally different things, and precision here
is exactly what interviewers are listening for.

### Association

**Definition:** a general "uses/knows about" relationship between two
classes, with no ownership implied in either direction — neither object
controls the other's lifecycle.

```text
Driver ------------- Car
       "drives"
```

**Example:** a `Driver` associates with the `Car` they're currently
driving. The `Driver` object holds a reference to a `Car` (or the `Car`
holds a reference to its current `Driver`, or both), but destroying the
`Driver` object doesn't destroy the `Car`, and vice versa — they have
fully independent lifecycles and simply refer to each other for the
duration of the association.

```ruby
class Car
  attr_accessor :current_driver
end

class Driver
  attr_reader :name
  def initialize(name) = @name = name
end

car = Car.new
driver = Driver.new("Alex")
car.current_driver = driver   # association: car knows about driver, but doesn't own it
```

### Aggregation ("has-a," hollow diamond)

**Definition:** a whole/part relationship where the part **can exist
independently** of the whole — if the whole is destroyed, the parts live
on.

```text
Department  o------------  Employee
  (whole)   hollow diamond   (part)
```

**Example:** a `Department` has `Employee`s, but if the department is
dissolved, the employees still exist (they might be reassigned to another
department, or simply exist as people who still have jobs elsewhere in the
company). The `Department` holds references to `Employee` objects it
doesn't exclusively own.

```ruby
class Employee
  attr_reader :name
  def initialize(name) = @name = name
end

class Department
  def initialize(name)
    @name = name
    @employees = []
  end

  def add_employee(employee)
    @employees << employee   # aggregation: employees can be added/removed,
  end                          # and outlive the department if it's dissolved
end
```

### Composition ("owns-a," filled diamond)

**Definition:** a stricter whole/part relationship where the part's
**lifecycle is bound to the whole** — the part doesn't meaningfully exist
independently, and destroying the whole destroys its parts.

```text
ParkingLot  *------------  ParkingSpot
  (whole)   filled diamond    (part)
```

**Example, and cross-reference:** this is precisely the relationship
between `ParkingLot` and `ParkingSpot` in
`LLD_OOD/02_Interview_Questions/01_parking_lot.md` — spots are created by
and stored inside `ParkingLot` (`@spots = Hash.new { |h, k| h[k] = [] }`,
populated via `add_spots`), and a spot has no meaningful existence outside
some lot. If the `ParkingLot` object goes away, so do its spots — nothing
else in the system holds an independent reference to a bare `ParkingSpot`.

```ruby
class ParkingSpot
  def initialize(id, spot_type)
    @id = id
    @spot_type = spot_type
  end
end

class ParkingLot
  def initialize
    @spots = Hash.new { |h, k| h[k] = [] }
  end

  def add_spots(spot_type, count)
    # ParkingLot CREATES its ParkingSpots - composition, not just a reference
    count.times { |i| @spots[spot_type] << ParkingSpot.new("#{spot_type}_#{i}", spot_type) }
  end
end
```

The tell, structurally: in aggregation, the part is typically constructed
elsewhere and *handed to* the whole (`add_employee(existing_employee)`).
In composition, the whole typically *constructs* the part itself
(`ParkingSpot.new(...)` happens inside `ParkingLot`), and nothing outside
the whole is expected to hold a reference to a part in isolation.

### Inheritance ("is-a," hollow triangle arrow to parent)

**Definition:** a subclass relationship — the child **is a** more specific
version of the parent, inheriting its interface and behavior.

```text
                Vehicle
                    ^
        ____________|____________
       |            |            |
     Bike          Car          Van
```

**Example:** the `Vehicle`/`Bike`/`Car`/`Van` hierarchy from the parking
lot file. The hollow triangle arrow always points **up**, from child to
parent — `Bike ---|> Vehicle` reads as "Bike is a Vehicle." Each subclass
inherits `Vehicle`'s interface (`spots_required`) and provides its own
implementation, which is the class-diagram picture of the polymorphism
covered in `02_oop_fundamentals_for_interviews.md`.

### Realization / Implementation (dashed hollow triangle)

**Definition:** a class implementing an interface's or contract's
methods, without inheriting any concrete implementation from it — in
languages with a formal `interface` keyword, this is the relationship
between a class and the interface it implements.

```text
       <<interface>>
         PricingStrategy
              ^
              . (dashed)
              |
       HourlyPricing
```

**Mapped to Ruby:** since Ruby has no `interface` keyword, this
relationship maps to the module/duck-typing convention from
`02_oop_fundamentals_for_interviews.md` — a class that `include`s a module
and implements the methods that module expects (or a class that simply
implements the right method names by convention, satisfying duck typing,
with no shared ancestry at all) is "realizing" that contract in the UML
sense, even though Ruby expresses it structurally different from a class
literally inheriting from an abstract base. The distinction from
inheritance: realization implements a *contract* (a set of expected
method signatures); inheritance shares actual *implementation* from a
concrete or semi-concrete parent.

```text
Inheritance (solid, hollow triangle):     Realization (dashed, hollow triangle):
  Bike ─────▷ Vehicle                       CreditCardPayment ┄┄┄▷ <<PaymentMethod contract>>
  (inherits Vehicle's code + contract)      (implements the `process` method Ruby-style,
                                              via a NotImplementedError-raising base class
                                              or simply duck typing - no shared code required)
```

## Multiplicity Notation

Multiplicity marks how many instances of one class relate to how many
instances of another, written at each end of a relationship line:

| Symbol | Meaning |
|---|---|
| `1` | exactly one |
| `0..1` | zero or one (optional single reference) |
| `*` (or `0..*`) | zero or more |
| `1..*` | one or more (at least one required) |

**Worked example:**

```text
ParkingLot  "1" ────────── "*"  ParkingSpot
```

Reading left to right: one `ParkingLot` relates to many (`*`, zero or
more) `ParkingSpot`s. Reading right to left: each `ParkingSpot` relates to
exactly one (`1`) `ParkingLot` — a spot doesn't float between lots. If
instead a spot could theoretically exist unassigned to any lot yet, the
right-hand side would be `0..1` instead of `1`. A second example from the
same domain:

```text
Vehicle  "1" ────────── "0..1"  ParkingTicket
```

One `Vehicle` has zero or one active `ParkingTicket` at a time (it might
not currently be parked at all, but can never hold two simultaneous
tickets in this design) — the `0..1` captures "optional, and at most one"
in a single symbol.

## Practical Interview Guidance

You almost never need a formally correct, tool-drawn UML diagram in an
interview — no one is grading whether your diamonds are precisely hollow
versus filled with a ruler. What's expected is simple ASCII-art or
boxes-and-arrows, drawn by hand or typed in a shared doc, that correctly
conveys three things fast:

1. **Class names** — what are the nouns in your design.
2. **Key methods** — just the ones relevant to the discussion, not a full
   attribute/method inventory.
3. **Relationship types** — inheritance vs. composition vs. association,
   correctly distinguished, since this is what actually reveals whether
   you understand the object model (a candidate who draws every connection
   as the same plain line is signaling they haven't thought about
   ownership and lifecycle, even if the class list itself is correct).

A diagram like the one in the parking lot file's Step 3 — plain-text boxes,
a `^` for inheritance, an arrow with a word like `[composition]` or
`--->`  annotated in a comment — is exactly the right level of formality.
Spending interview time getting a diagram tool-perfect, adding full type
annotations to every attribute, or drawing every relationship with
textbook-exact diamond/triangle glyphs takes time away from the part of
the interview that's actually being scored: the design reasoning and the
code. Use just enough diagram to think out loud and to give the
interviewer a map — then move to code, and let the code carry the
precision the diagram was only sketching.

## Interview Tips

- Default to a quick ASCII sketch (boxes, a few key methods, `^` for
  inheritance, a labeled arrow for composition/association) before or
  right as you start coding — it takes under a minute and immediately
  surfaces misunderstandings.
- When asked to distinguish relationship types out loud, use the
  lifecycle test: "does the part make sense without the whole?" Yes →
  aggregation or plain association. No → composition. "Does the child
  reuse the parent's actual code/behavior, or just satisfy a method
  contract?" Code reuse → inheritance. Contract only → realization
  (module/duck typing in Ruby).
- If an interviewer asks you to formalize a relationship you drew as a
  plain line, be ready to justify it: "I drew `ParkingLot` to
  `ParkingSpot` as composition because the lot constructs and owns its
  spots — there's no path for a `ParkingSpot` to exist independently in
  this design."
- Don't over-invest in the diagram. If you notice yourself spending more
  than a minute or two perfecting box formatting, that's a sign to move to
  code — the diagram is scaffolding for the conversation, not the
  deliverable.
- Multiplicity is worth mentioning verbally even if you don't annotate it
  on the diagram: saying "each `Vehicle` has at most one active
  `ParkingTicket`" out loud demonstrates the same precision without
  needing to draw `0..1`.

## Quick Recall — Self-Test

1. **What are the three compartments of a UML class box, and what do `+`,
   `-`, and `#` mean?**
   Class name, attributes, and methods. `+` marks a member as public, `-`
   as private, and `#` as protected.

2. **What is the structural test that distinguishes aggregation from
   composition?**
   Whether the part can exist independently of the whole's lifecycle.
   Aggregation: the part is typically constructed elsewhere and handed in,
   and survives the whole's destruction (an `Employee` outlives a
   dissolved `Department`). Composition: the whole typically constructs
   the part itself, and the part has no meaningful existence outside it
   (a `ParkingSpot` has no purpose without its `ParkingLot`).

3. **In the parking lot example, is the relationship between `ParkingLot`
   and `ParkingSpot` aggregation or composition? Justify it structurally,
   not just by definition.**
   Composition. `ParkingLot#add_spots` constructs `ParkingSpot` instances
   itself (`ParkingSpot.new(...)` happens inside `ParkingLot`), and no
   other part of the system holds or expects a bare, lot-less
   `ParkingSpot` — the part is created by, and scoped to, the whole.

4. **What visual distinguishes inheritance from realization/implementation
   in UML notation, and how does each map to Ruby?**
   Both use a hollow triangle arrowhead pointing to the parent/interface,
   but inheritance uses a solid line and realization uses a dashed line.
   Inheritance maps to Ruby's `class Bike < Vehicle` (shared code and
   contract); realization maps to Ruby's module/duck-typing convention —
   implementing the expected methods (often enforced via
   `NotImplementedError` in a base class) without necessarily sharing a
   concrete ancestor.

5. **What does the multiplicity `ParkingLot "1" --- "*" ParkingSpot` mean,
   read in both directions?**
   Read left to right: one `ParkingLot` relates to many (zero or more)
   `ParkingSpot`s. Read right to left: each `ParkingSpot` belongs to
   exactly one `ParkingLot`.

6. **A candidate draws every relationship in their design — inheritance,
   composition, and plain association — as the same undifferentiated
   line. What does this signal to an interviewer, even if the class list
   itself is otherwise correct?**
   It signals the candidate hasn't thought through ownership and
   lifecycle relationships between objects, even if they identified the
   right classes. Relationship type is where the actual design reasoning
   lives; a uniform line flattens that distinction and reads as not having
   considered it.

7. **How does association differ from aggregation? Give an example of
   each.**
   Association is a general "uses/knows about" relationship with no
   whole/part structure implied at all (a `Driver` associates with the
   `Car` they're currently driving — neither owns the other). Aggregation
   specifically implies a whole/part structure where the part can outlive
   the whole (a `Department` has `Employee`s who remain employed elsewhere
   if the department is dissolved).

8. **Why is a hand-drawn ASCII diagram usually sufficient in an interview,
   and what's the actual risk of over-formatting one?**
   Interviewers are evaluating whether your diagram correctly conveys
   class names, key methods, and relationship types — not whether it's
   tool-perfect UML. The risk of over-formatting (precise diamond/triangle
   glyphs, full attribute lists with types) is spending interview time on
   presentation polish instead of on the design reasoning and code that
   are actually being scored.

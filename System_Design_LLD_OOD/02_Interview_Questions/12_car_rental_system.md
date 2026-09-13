# Design a Car Rental System (Object-Oriented Design)

## Problem Statement

"Design a car rental system. There are multiple rental locations, each with
its own inventory of vehicles across categories (economy, SUV, luxury).
A customer searches for a vehicle of a given category, available for a
given date range, at a given location, and reserves it. The system needs
to price the rental and track the reservation from booking through
return."

The trap in this problem is reaching for inheritance too eagerly —
`Economy < Vehicle`, `SUV < Vehicle`, `Luxury < Vehicle` — because that
pattern worked well in the Parking Lot problem. It doesn't automatically
transfer here, and noticing *why* is itself part of what a good answer
demonstrates. The actual hard part of this problem is availability
checking across future date ranges, not category modeling.

## Step 1: Clarify Requirements

**Functional Requirements**
- Multiple `RentalLocation`s, each with its own vehicle inventory.
- Search: given a category, a date range, and a location, return vehicles
  of that category with no conflicting reservation in that range.
- Reserve a vehicle for a date range; track reservation status (reserved,
  active/picked-up, completed/returned, cancelled).
- Compute price based on vehicle category, rental duration, and
  potentially seasonal/demand multipliers.
- Extend an existing reservation's end date, re-checking for conflicts.
- Support one-way rentals: pick up at one location, return at another.

**Non-Functional Requirements**
- **Correct overlap detection**: reservations are made for future date
  ranges, not just "is this car currently out" — the availability check
  must be genuinely range-based, which is the main source of subtle bugs
  in this problem if rushed.
- **Extensibility of pricing**: new pricing dimensions (loyalty tiers,
  seasonal demand) should compose onto existing pricing without rewriting
  it — points to Strategy again.
- **Don't over-model vehicle behavior**: category differences in this
  domain are almost entirely about *data* (base rate, seating capacity),
  not *behavior* — worth stating explicitly since it's the opposite lesson
  from Parking Lot's `Vehicle` hierarchy, and conflating the two is a
  common mistake under interview pressure.

## Step 2: Identify Core Objects / Entities

- **Vehicle** — one physical car: make, model, category, license plate,
  home `RentalLocation`. See Step 4 for why this is a single class with a
  `category` attribute rather than an `Economy`/`SUV`/`Luxury` subclass
  hierarchy.
- **RentalLocation** (branch) — owns an inventory of `Vehicle`s, exposes
  availability search scoped to itself.
- **Reservation** — the central association object: `customer`, `vehicle`,
  `pickup_location`, `return_location`, `start_date`, `end_date`,
  `status`. This is the same recurring shape seen elsewhere in this
  folder — `ParkingTicket` (Parking Lot), a `Loan` (Library), a booked
  `Seat`/`Booking` (Ticket Booking) — an explicit object representing a
  *transaction between two entities*, rather than the two entities
  mutating each other's state directly. By this point in the series it's
  worth naming as a pattern in its own right: whenever two domain objects
  need a time-bounded relationship with its own status and history, model
  that relationship as a first-class object, don't bolt flags onto either
  side.
- **PricingStrategy** — computes cost from a `Reservation`'s vehicle
  category and duration (and later, loyalty tier / seasonal multiplier),
  kept entirely separate from `Reservation` itself.

## Step 3: Identify Relationships (Class Diagram)

```text
  Vehicle
  - id, make, model, category (:economy | :suv | :luxury)
  - license_plate
  - home_location ---> RentalLocation

  RentalLocation
  - id, name
  - vehicles: [Vehicle]                    (composition: owns its inventory)
  - reservations: [Reservation]
  + available_vehicles(category, start_date, end_date) : [Vehicle]
  + reserve(customer, vehicle, start_date, end_date, return_location) : Reservation

  Reservation
  - customer ------------> Customer
  - vehicle --------------> Vehicle
  - pickup_location -------> RentalLocation
  - return_location -------> RentalLocation      (may differ: one-way rental)
  - start_date, end_date
  - status: :reserved | :active | :completed | :cancelled
  - price: Money                                  (computed via PricingStrategy)

  PricingStrategy (interface)             StandardPricing
  + calculate(reservation) : Money    <--------  implements  --------  (+ SeasonalPricing, LoyaltyPricing...)
```

Relationship types:
- `RentalLocation` **composes** its `Vehicle` inventory (a vehicle belongs
  to exactly one home location's inventory; composition).
- `Reservation` **associates** `Customer`, `Vehicle`, and two
  `RentalLocation`s — none of these are owned by the reservation, they
  each have independent lifecycles (association, not ownership) — this is
  the "explicit association object" pattern called out in Step 2.
- `RentalLocation` **uses-a** `PricingStrategy` (injected, association) to
  price reservations — classic Strategy pattern.
- `StandardPricing`/`SeasonalPricing`/`LoyaltyPricing` all **implement**
  `PricingStrategy` (interface implementation).

## Step 4: Design Decisions & Patterns Used

**Why `Vehicle` is one class with a `category` attribute, not a subclass
per category — and why this is DIFFERENT from Parking Lot's `Vehicle`
hierarchy.** In Parking Lot, `Bike`/`Car`/`Van` genuinely differ in
*behavior* — each implements `spots_required(spot_type)` differently, and
that method is called polymorphically by code that doesn't know which
vehicle type it's holding. That's exactly when inheritance/polymorphism
earns its keep. Here, "Economy" vs. "SUV" vs. "Luxury" don't differ in
behavior at all — nothing in this system calls a method that an `SUV`
would implement differently from a `Luxury`. They differ only in *data*:
base rental rate, seating capacity, maybe fuel type. Modeling that as a
subclass hierarchy (`class SUV < Vehicle`) would mean every one of those
data differences becomes an overridden constant or method returning a
literal — inheritance used purely to carry data, which is a smell. The
right call is a single `Vehicle` class with a `category` symbol/enum
attribute, where category-specific *values* (base rate, etc.) live in a
lookup table or in `PricingStrategy`, not in the class hierarchy. This is
the composition-over-inheritance guidance from
`LLD_OOD/01_Concepts/02_oop_fundamentals_for_interviews.md` applied
directly: reach for inheritance/polymorphism when behavior genuinely
varies by type, not just because a `Vehicle` hierarchy "worked last time."
If a genuine behavioral difference later appears (e.g. `ElectricVehicle`
needing charging-station logic that gas vehicles don't), that's the moment
to introduce a subclass or a small mixin for that specific behavior — not
before.

**Why `Reservation` is an explicit object instead of flags on `Vehicle` and
`Customer`.** The naive design marks `vehicle.rented = true` and appends to
`customer.rented_vehicles`. That immediately breaks under two real
requirements: reservations are made for *future* date ranges (a boolean
"is it rented" can't represent "available now, but booked starting next
Tuesday"), and a reservation has its own lifecycle (reserved -> active ->
completed, or cancelled) that doesn't map onto either side's state cleanly.
An explicit `Reservation` object holds the date range and status itself,
so availability checking becomes "does any `Reservation` for this vehicle
overlap this range," and lifecycle transitions happen on the reservation,
not by mutating the vehicle. As noted in Step 2, this is the same shape as
`ParkingTicket`, `Loan`, and ticket-booking's `Booking` — recognizing this
repeated pattern (association-with-a-lifecycle needs its own object) is
worth stating out loud; it signals you're not solving each LLD problem from
scratch but recognizing a recurring shape.

**Why `PricingStrategy` is pulled out of `Reservation`.** Pricing logic
(base rate x duration, plus seasonal/demand multipliers, plus later a
loyalty discount) changes far more often and along more independent
dimensions than reservation lifecycle logic does. Keeping `calculate
(reservation)` on a separate, injectable `PricingStrategy` means
`Reservation` never needs to change when a new pricing rule is added — only
a new `PricingStrategy` implementation does, and it composes with existing
ones (see Follow-up 1).

## Step 5: Code

```ruby
class Vehicle
  attr_reader :id, :make, :model, :category, :license_plate, :home_location

  def initialize(id, make:, model:, category:, license_plate:, home_location:)
    @id = id
    @make = make
    @model = model
    @category = category # :economy | :suv | :luxury
    @license_plate = license_plate
    @home_location = home_location
  end
end

class Reservation
  attr_reader :customer, :vehicle, :pickup_location, :return_location, :start_date, :end_date
  attr_accessor :status, :price

  def initialize(customer:, vehicle:, pickup_location:, return_location:, start_date:, end_date:)
    @customer = customer
    @vehicle = vehicle
    @pickup_location = pickup_location
    @return_location = return_location
    @start_date = start_date
    @end_date = end_date
    @status = :reserved
    @price = nil
  end

  # Two date ranges overlap unless one ends before the other starts.
  # This is the crux of correct availability checking in this problem.
  def overlaps?(other_start, other_end)
    return false if [:cancelled, :completed].include?(@status)

    !(other_end < @start_date || other_start > @end_date)
  end
end

class RentalLocation
  attr_reader :id, :name

  def initialize(id, name, pricing_strategy: StandardPricing.new)
    @id = id
    @name = name
    @vehicles = []          # inventory homed at this location
    @reservations = []      # every reservation ever made picking up here
    @pricing_strategy = pricing_strategy
  end

  def add_vehicle(vehicle)
    @vehicles << vehicle
  end

  # The core non-trivial method in this problem: vehicles of `category`
  # homed here, with no existing (non-cancelled/completed) reservation
  # that overlaps [start_date, end_date].
  def available_vehicles(category, start_date, end_date)
    @vehicles.select do |vehicle|
      vehicle.category == category &&
        @reservations.none? { |r| r.vehicle == vehicle && r.overlaps?(start_date, end_date) }
    end
  end

  def reserve(customer, vehicle, start_date, end_date, return_location: self)
    conflict = @reservations.any? { |r| r.vehicle == vehicle && r.overlaps?(start_date, end_date) }
    raise "vehicle unavailable for that range" if conflict

    reservation = Reservation.new(
      customer: customer, vehicle: vehicle,
      pickup_location: self, return_location: return_location,
      start_date: start_date, end_date: end_date
    )
    reservation.price = @pricing_strategy.calculate(reservation)
    @reservations << reservation
    reservation
  end

  # Re-check conflicts against the SAME overlap logic before committing —
  # extending a reservation is just "would a new reservation with the
  # extended range conflict with anything else."
  def extend_reservation(reservation, new_end_date)
    conflict = @reservations.any? do |r|
      r != reservation && r.vehicle == reservation.vehicle && r.overlaps?(reservation.start_date, new_end_date)
    end
    raise "extension conflicts with another reservation" if conflict

    reservation.instance_variable_set(:@end_date, new_end_date)
    reservation.price = @pricing_strategy.calculate(reservation)
    reservation
  end
end

class StandardPricing
  DAILY_RATE = { economy: 30, suv: 55, luxury: 120 }.freeze

  def calculate(reservation)
    days = (reservation.end_date - reservation.start_date).to_i + 1
    DAILY_RATE.fetch(reservation.vehicle.category) * days
  end
end
```

**Using it — including the one-way rental case:**

```ruby
downtown = RentalLocation.new(1, "Downtown")
airport  = RentalLocation.new(2, "Airport")

civic = Vehicle.new(101, make: "Honda", model: "Civic", category: :economy,
                     license_plate: "ABC-123", home_location: downtown)
downtown.add_vehicle(civic)

downtown.available_vehicles(:economy, Date.new(2026, 9, 20), Date.new(2026, 9, 25))
# => [civic]   (no conflicting reservation yet)

res = downtown.reserve(customer, civic, Date.new(2026, 9, 20), Date.new(2026, 9, 25),
                        return_location: airport) # one-way: picked up downtown, returned at airport
res.price # => 30 * 6 = 180

downtown.available_vehicles(:economy, Date.new(2026, 9, 22), Date.new(2026, 9, 23))
# => []   (overlaps the existing reservation's range)

downtown.available_vehicles(:economy, Date.new(2026, 9, 26), Date.new(2026, 9, 28))
# => [civic]   (no overlap — starts the day after the existing reservation ends)
```

## Step 6: Edge Cases & Extensibility

- **Two customers racing for the last available vehicle in a category.**
  `available_vehicles` and `reserve` above are two separate reads/writes —
  under concurrency, two requests could both see the vehicle as available
  and both attempt to reserve it. This is a real concern, but it's
  explicitly an HLD/infrastructure-level fix, not something to over-design
  at the LLD layer: a unique constraint at the database level (e.g. no two
  non-cancelled reservations for the same vehicle with overlapping ranges,
  enforced via a DB exclusion constraint or an application-level
  compare-and-swap with optimistic locking/version column) is the right
  answer to name, without building out a full concurrency solution in this
  file.
- **Extending an existing reservation's end date.** Must re-run the exact
  same overlap check used for new reservations (`extend_reservation`
  above), excluding the reservation being extended itself from the
  conflict check (`r != reservation`) — a common bug is checking against
  all reservations including the one being modified, which would always
  "conflict with itself."
- **One-way rentals and inventory tracking per location.** A `Reservation`
  tracks `pickup_location` and `return_location` separately; on
  `:completed` status (return processed), the vehicle's *effective*
  location for future availability searches should reflect where it was
  returned, not `vehicle.home_location`. The clean fix: `available_
  vehicles` at a location should really be scoped by "vehicles currently
  at this location" (derivable from the most recent completed
  reservation's `return_location`, or `home_location` if never rented) —
  worth stating this refinement explicitly, since naively trusting `home_
  location` forever would make a one-way-rented car permanently "belong"
  to a location it's no longer physically at.
- **Cancelling a reservation.** Setting `status = :cancelled` is
  sufficient given `overlaps?` already excludes cancelled/completed
  reservations from conflict checks — no separate cleanup needed, which is
  a direct payoff of keeping status ON the `Reservation` rather than as
  external bookkeeping.
- **Zero-length or inverted date ranges** (`end_date < start_date`):
  reject at the `reserve`/`extend_reservation` boundary before any overlap
  logic runs — worth a guard clause, and worth mentioning even if not
  coded live.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you add a loyalty/membership discount tier to pricing?"**
   Compose it onto `PricingStrategy` rather than editing `StandardPricing`
   — either a `LoyaltyPricing` decorator wrapping a base strategy
   (`LoyaltyPricing.new(StandardPricing.new, discount: 0.10)` computing the
   base price then applying a discount), or a strategy that takes the
   customer's tier into account directly. The decorator form is worth
   naming specifically: it lets loyalty discounts, seasonal multipliers,
   and base category pricing all stack independently without any one of
   them knowing about the others.
2. **"How would you handle late returns and penalty pricing?"** Add an
   `actual_return_date` to `Reservation`, set when status transitions to
   `:completed`; if `actual_return_date > end_date`, a `LateFeeCalculator`
   (another small Strategy-shaped object, or a method on `PricingStrategy`)
   computes an additional charge based on the overage — kept separate from
   the original `price` so the reservation can show "base price" and "late
   fee" as distinct line items rather than one opaque total.
3. **"What if a customer wants to search across ALL locations, not just
   one?"** Add a `RentalNetwork`/`RentalCompany` that owns multiple
   `RentalLocation`s and aggregates `available_vehicles` across them — same
   shape as Parking Lot's "add multiple floors" follow-up: the aggregator
   just fans the query out and merges results, no change to
   `RentalLocation` itself.
4. **"How would you model add-ons — insurance, GPS, child seat?"** As
   optional line items attached to a `Reservation` (a small `AddOn` value
   object with its own price), summed into the final total by
   `PricingStrategy` or a thin `Invoice` object wrapping the reservation —
   deliberately kept off `Vehicle`, since add-ons are a property of the
   booking, not the physical car.
5. **"How would you test the availability logic specifically?"** Unit-test
   `Reservation#overlaps?` directly and exhaustively with the classic
   interval cases (fully before, fully after, exact match, partial overlap
   on each side, one range fully containing the other) — this is where
   off-by-one bugs actually live in this problem, and it's cheap to test
   in complete isolation from `RentalLocation`.
6. **"How is this different from a peer-to-peer rental system (like
   Turo), where 'inventory' is owned by individual hosts, not a company
   with branches?"** The core `Reservation`/overlap-checking/`Pricing
   Strategy` design barely changes; what changes is `RentalLocation`
   becoming closer to a `Host`'s listing plus a pickup/dropoff location
   the host defines per vehicle, and ownership/approval workflows (a host
   approving a booking request) get added on top — a good moment to note
   that the *transaction-object* pattern from Step 2 is what stays stable
   across that variation.

# Design a Parking Lot (Object-Oriented Design)

## Problem Statement

"Design a parking lot using OOP. It should track the total number of spots,
remaining spots, whether the lot is full or empty. There are different
vehicle types (bike, car, van) and different spot types. A van can also
park in a bike spot, but it takes up 3 bike spots. Tell me the number of
remaining spots per vehicle type, and whether parking for vans specifically
is full."

This is a real question asked at a small/mid-size product company interview
— and it's a good one, because the "van takes 3 bike spots" rule is
deliberately planted to see whether you reach for **polymorphism** or for a
pile of `if vehicle_type == :van` checks scattered through your parking-lot
class. The second approach is what fails this interview even if the code
technically works.

## Step 1: Clarify Requirements

**Functional Requirements**
- Track parking spots by type (bike spot, car spot, van spot).
- Park a vehicle: find and occupy an appropriate spot (or spots).
- Un-park a vehicle: free up whatever spot(s) it was occupying.
- A van can park in a **bike spot**, but consumes **3 bike spots** at once
  (this is the rule the interviewer explicitly planted — treat it as a
  general "some vehicles can use a smaller/different spot type but consume
  more than one" rule, not a one-off special case).
- Report, per spot type: total spots, remaining spots, is full, is empty.

**Non-Functional Requirements (the ones a strong candidate states out loud
even in an LLD interview — these justify *why* you design it a certain way)**
- **Extensibility**: adding a new vehicle type (e.g., Truck) or a new spot
  type should require adding a class, not editing existing classes
  (Open/Closed Principle).
- **Single responsibility**: `ParkingLot` should not contain per-vehicle
  business rules; a vehicle should know its own spot requirements.
- Correctness under exit: when a van (occupying 3 spots) leaves, **all 3**
  spots must be freed together, not just one.

## Step 2: Identify Core Objects / Entities

Read the problem statement for nouns — that's usually your class list:

- **Vehicle** (abstract) → `Bike`, `Car`, `Van` — each vehicle instance.
- **ParkingSpot** — a single physical spot, has a type and occupancy state.
- **ParkingTicket** — represents one active parking session; tracks which
  spot(s) a vehicle is occupying (this is the object that makes the
  "free all 3 spots together" requirement trivial instead of messy).
- **ParkingLot** — owns the collection of spots, orchestrates
  parking/un-parking, answers the aggregate queries (full/empty/remaining).

## Step 3: Identify Relationships (Class Diagram)

```text
                 Vehicle (abstract)
                 - license_plate
                 + spots_required(spot_type) : Integer   [abstract]
                      ^
        ___________|___________
       |            |           |
     Bike          Car         Van
  (1 bike_spot) (1 car_spot)  (1 van_spot, OR 3 bike_spot)

  ParkingSpot                    ParkingTicket
  - id                           - vehicle -----------> Vehicle
  - spot_type                    - spot_ids[] ---------> [ParkingSpot.id]
  - occupied_by ---> Vehicle|nil

  ParkingLot
  - spots: { spot_type => [ParkingSpot] }     (composition: owns the spots)
  - tickets: { license_plate => ParkingTicket }
  + add_spots(spot_type, count)
  + park(vehicle) : ParkingTicket
  + unpark(vehicle) : Boolean
  + total_spots(spot_type) / remaining_spots(spot_type)
  + full?(spot_type) / empty?(spot_type)
```

Relationship types, precisely (this vocabulary is exactly what an
interviewer is listening for):
- `Bike`/`Car`/`Van` **inherit** from `Vehicle` (is-a).
- `ParkingLot` **composes** `ParkingSpot`s — spots don't exist independently
  of the lot; if the lot is destroyed, so are its spots (composition, not
  aggregation).
- `ParkingSpot` **associates** with `Vehicle` via `occupied_by` — a spot
  references a vehicle, but the vehicle's lifecycle is independent of the
  spot (association, not ownership).
- `ParkingTicket` associates a `Vehicle` with the `ParkingSpot`s it holds —
  this is the object that solves the "multi-spot" requirement cleanly.

## Step 4: Design Decisions & Patterns Used

**Why polymorphism instead of a case statement in `ParkingLot`.** The naive
approach puts `if vehicle.type == :van && spot.type == :bike_spot then
needs = 3` logic inside `ParkingLot`. That violates Single Responsibility
(the lot now knows every vehicle's parking rules) and Open/Closed (adding a
`Truck` means editing `ParkingLot`). Instead, each `Vehicle` subclass
implements `spots_required(spot_type)` and answers for itself. `ParkingLot`
just asks "how many do you need here?" and never branches on vehicle type.
This is effectively the **Strategy pattern** — each vehicle carries its own
spot-allocation strategy.

**Why a `ParkingTicket` object instead of just marking spots occupied.**
Without a ticket, un-parking a van means somehow finding "all the spots
this exact van is on" by searching — error-prone and slow. The ticket
captures the spot IDs at park-time, so un-parking is a direct lookup and
release, and it also gives you a natural place to add park-time,
duration-based pricing, etc. later without touching `ParkingSpot` at all.

**Why spots are grouped in a `spot_type => [spots]` hash, not one flat
list.** Every required query (`total_spots(:bike_spot)`,
`remaining_spots(:van_spot)`) is naturally scoped by spot type — grouping
up front makes every one of those O(spots of that type) instead of scanning
everything and filtering every time.

## Step 5: Code

```ruby
class Vehicle
  attr_reader :license_plate

  def initialize(license_plate)
    @license_plate = license_plate
  end

  # How many spots of `spot_type` this vehicle needs to park here.
  # Float::INFINITY means "this vehicle cannot use this spot type at all."
  def spots_required(spot_type)
    raise NotImplementedError, "#{self.class} must implement spots_required"
  end
end

class Bike < Vehicle
  def spots_required(spot_type)
    spot_type == :bike_spot ? 1 : Float::INFINITY
  end
end

class Car < Vehicle
  def spots_required(spot_type)
    spot_type == :car_spot ? 1 : Float::INFINITY
  end
end

class Van < Vehicle
  def spots_required(spot_type)
    case spot_type
    when :van_spot  then 1
    when :bike_spot then 3   # the interview's planted rule, isolated here
    else Float::INFINITY
    end
  end
end

class ParkingSpot
  attr_reader :id, :spot_type
  attr_accessor :occupied_by

  def initialize(id, spot_type)
    @id = id
    @spot_type = spot_type
    @occupied_by = nil
  end

  def occupied?
    !@occupied_by.nil?
  end
end

class ParkingTicket
  attr_reader :vehicle, :spot_ids

  def initialize(vehicle, spot_ids)
    @vehicle = vehicle
    @spot_ids = spot_ids
  end
end

class ParkingLot
  def initialize
    @spots = Hash.new { |h, k| h[k] = [] }   # spot_type => [ParkingSpot]
    @tickets = {}                             # license_plate => ParkingTicket
  end

  def add_spots(spot_type, count)
    offset = @spots[spot_type].size
    count.times { |i| @spots[spot_type] << ParkingSpot.new("#{spot_type}_#{offset + i}", spot_type) }
  end

  def total_spots(spot_type)
    @spots[spot_type].size
  end

  def remaining_spots(spot_type)
    @spots[spot_type].count { |s| !s.occupied? }
  end

  def full?(spot_type)
    remaining_spots(spot_type).zero?
  end

  def empty?(spot_type)
    remaining_spots(spot_type) == total_spots(spot_type)
  end

  # Tries spot types most-specific-first (a van's own spot before it
  # cannibalizes 3 bike spots), and picks the first type where enough
  # free spots of that type exist.
  def park(vehicle, preferred_order = [:van_spot, :car_spot, :bike_spot])
    preferred_order.each do |spot_type|
      needed = vehicle.spots_required(spot_type)
      next if needed == Float::INFINITY

      free = @spots[spot_type].reject(&:occupied?)
      next if free.size < needed

      chosen = free.first(needed)
      chosen.each { |s| s.occupied_by = vehicle }
      ticket = ParkingTicket.new(vehicle, chosen.map(&:id))
      @tickets[vehicle.license_plate] = ticket
      return ticket
    end
    nil # no spot type could accommodate this vehicle right now
  end

  def unpark(vehicle)
    ticket = @tickets.delete(vehicle.license_plate)
    return false unless ticket

    all_spots = @spots.values.flatten
    ticket.spot_ids.each do |id|
      spot = all_spots.find { |s| s.id == id }
      spot.occupied_by = nil
    end
    true
  end
end
```

**Using it:**

```ruby
lot = ParkingLot.new
lot.add_spots(:bike_spot, 5)
lot.add_spots(:car_spot, 3)
lot.add_spots(:van_spot, 1)

van = Van.new("VAN-001")
ticket = lot.park(van)          # parks in the dedicated van_spot first
lot.remaining_spots(:van_spot)  # => 0
lot.full?(:van_spot)            # => true

van2 = Van.new("VAN-002")
lot.park(van2)                  # no van_spot left, falls back to 3 bike spots
lot.remaining_spots(:bike_spot) # => 2   (5 - 3)

lot.unpark(van2)
lot.remaining_spots(:bike_spot) # => 5   (all 3 freed together, via the ticket)
```

Every sub-question from the original interview is answered directly:
`total_spots`, `remaining_spots`, `full?`, `empty?` — all parameterized by
spot type, so "is van parking full" is just `lot.full?(:van_spot)`, and the
3-bike-spot rule never appears outside `Van#spots_required`.

## Step 6: Edge Cases & Extensibility

- **Adding a `Truck` that needs 2 car spots or 6 bike spots**: write
  `class Truck < Vehicle` implementing `spots_required` — zero changes to
  `ParkingLot`, `ParkingSpot`, or `ParkingTicket`. This is the Open/Closed
  Principle paying off directly, and it's exactly what an interviewer
  tests by asking "now add a new vehicle type" right after your first pass.
- **A vehicle that's already parked tries to park again**: `park` should
  check `@tickets.key?(vehicle.license_plate)` first and reject/return the
  existing ticket rather than double-allocating spots — a good follow-up
  to mention even if you don't code it live.
- **Partial spot availability** (e.g., only 2 bike spots free, a van needs
  3): the current `park` correctly finds `free.size < needed` and moves on
  to try the next spot type (or fails) — it does NOT partially occupy 2
  spots. Point this out explicitly; it's a common bug when people write
  this under time pressure.
- **Pricing/duration**: `ParkingTicket` is the natural place to add
  `entry_time`, and a `Pricing` strategy object (Strategy pattern again)
  that computes cost from `Time.now - entry_time` and vehicle type — a
  common immediate follow-up question.
- **Thread-safety** (if asked "what if two people park at the exact same
  time"): the `park` method's read-then-write on `free` spots is a race
  condition under concurrency — mention a mutex/lock around the
  find-and-occupy step, or an atomic compare-and-swap on each spot's state,
  as the fix. This is a good bridge if the interviewer pushes toward
  "now imagine this runs across multiple servers" — at that point you're
  being walked into HLD territory (see `System_Design/01_Concepts/09_distributed_systems_core.md`
  on distributed locks), which is worth naming explicitly to show you know
  where the LLD/HLD boundary is.

## Follow-up Questions an Interviewer Might Ask

1. **"Add support for multiple floors."** Add a `Floor` class that owns its
   own `spots` hash (same structure `ParkingLot` has now); `ParkingLot`
   becomes a collection of `Floor`s and aggregates totals across them. The
   per-type query methods barely change — they just sum across floors.
2. **"Add pricing based on vehicle type and duration."** Introduce a
   `PricingStrategy` interface with `calculate(ticket)`, and concrete
   strategies like `HourlyPricing` or `FlatRatePricing` injected into
   `ParkingLot` — classic Strategy pattern, keeps pricing logic out of
   `ParkingLot` and `Vehicle` entirely.
3. **"What if a vehicle type can be assigned different spots at different
   times (e.g., a car can also use a van spot if bikes/cars are full)?"**
   This is already handled by `spots_required` returning a finite value for
   more than one spot type — just extend `Car#spots_required` similarly to
   `Van#spots_required`, and adjust `preferred_order` in `park`.
4. **"How would you test this?"** Unit test each `Vehicle` subclass's
   `spots_required` in isolation (pure logic, no `ParkingLot` needed), then
   integration-test `ParkingLot#park`/`unpark` for the full flow, including
   the van-spanning-3-bike-spots case and the "not enough spots" case.
5. **"How is this different from how you'd design this at Amazon/Google
   scale, with thousands of parking lots across a city?"** That's the
   HLD version of this question — multiple lots become a distributed
   system problem (which lot has availability, real-time spot-count sync
   across locations, cross-references to `System_Design/01_Concepts/07_database_scaling.md`
   and `12_ride_sharing_uber.md`'s geospatial-search deep dive for "find
   nearby lots with availability"). Naming this distinction explicitly is
   itself a strong signal.

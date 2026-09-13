# Design an Elevator System (Object-Oriented Design)

## Problem Statement

"Design an elevator system for a building with multiple elevator cars and
multiple floors. Users can call an elevator from any floor by pressing an
up/down button (a hall call), and once inside, select a destination floor
(a car call). Given several elevators and an incoming request, your system
should decide which car handles it. Model the elevator's own behavior too —
what it does when idle, moving, or with its doors open."

This question is popular because it packs two separate hard parts into one
prompt: (1) a single elevator's **behavior as a state machine** — what
"pressing a button" even means depends entirely on what the elevator is
currently doing — and (2) a **scheduling problem** across multiple cars. A
candidate who jumps straight to code before separating these two concerns
usually ends up with a `case @status` scattered through every method and a
scheduler that just picks `elevators.first`. Both are the actual bugs this
question is designed to surface.

## Step 1: Clarify Requirements

**Functional Requirements**
- A building has `N` floors and `M` elevator cars.
- A user on a floor can press **up** or **down** (a hall call) — this is a
  request for *any* elevator, with a known direction, from outside a car.
- A user inside a car selects a destination floor (a car call) — this is a
  request for *that specific car*, with no separate direction (the car
  infers direction from where it already is).
- The system must pick which elevator serves an incoming hall call.
- Each elevator tracks its current floor, direction, and door state, and
  transitions between idle / moving / doors-open correctly.
- An elevator serves multiple requests along a single trip without needless
  back-and-forth (it should not zig-zag floor by floor).

**Non-Functional Requirements**
- **Single responsibility**: an `Elevator` should not know how to pick
  *itself* out of a fleet — that's a fleet-level concern, not a car-level
  one. Keep `ElevatorController` (fleet/scheduling) and `Elevator` (one
  car's own state machine) as separate classes.
- **Extensibility**: adding a new elevator behavior (e.g., an express car
  that skips floors) or swapping the scheduling algorithm should not
  require rewriting `Elevator`'s state transition logic.
- **No scattered conditionals**: what happens when a button is pressed
  should never be a `case @status` inside `Elevator` — the valid actions
  and transitions differ per state, which is the textbook signal for the
  **State pattern**.
- **Correctness under concurrent requests**: multiple hall/car calls
  arriving while a car is already moving must be integrated into its
  current trip, not handled by interrupting it arbitrarily.

## Step 2: Identify Core Objects / Entities

- **Elevator** — one physical car: current floor, direction, door state,
  and the set of floors it still needs to visit.
- **ElevatorState** (abstract) → `IdleState`, `MovingUpState`,
  `MovingDownState`, `DoorsOpenState` — what the car does in response to
  "arrived at a floor," "doors should open/close," and what requests it
  will currently accept.
- **Request** (abstract) → `HallCall` (floor + direction, made from outside
  any car), `CarCall` (floor only, made from inside a specific car) — these
  are genuinely different objects because a hall call needs to be *matched
  to* a car by the controller, while a car call already belongs to one.
- **ElevatorController** — owns all `Elevator` instances, receives incoming
  `HallCall`s, and runs the scheduling algorithm to assign a car.

## Step 3: Identify Relationships (Class Diagram)

```text
                  ElevatorState (abstract)
                  + on_arrival(elevator, floor)
                  + request_floor(elevator, floor)  [abstract]
                       ^
       ________________|__________________________
      |            |               |                |
  IdleState   MovingUpState   MovingDownState   DoorsOpenState

  Request (abstract)
  - floor
       ^
       |________________
       |                 |
  HallCall           CarCall
  - direction (:up/:down)   (no direction; belongs to one car)

  Elevator
  - id
  - current_floor
  - door_open: Boolean
  - state ------------------> ElevatorState   (composition: state owned by elevator)
  - stops: SortedSet<Integer> (floors still queued to visit)
  + press_button(floor)
  + step()                    (simulate one floor of movement / one state tick)
  + direction : :up | :down | :idle

  ElevatorController
  - elevators: [Elevator]     (composition: controller owns the fleet)
  + request_elevator(floor, direction) : Elevator   (assigns a HallCall)
  + dispatch(elevator, floor)
```

Relationship types:
- `IdleState`/`MovingUpState`/`MovingDownState`/`DoorsOpenState` **inherit**
  from `ElevatorState` (is-a) — each implements the same interface
  differently.
- `Elevator` **composes** its current `ElevatorState` — the state object
  has no meaning or lifecycle outside the elevator that holds it.
- `HallCall`/`CarCall` **inherit** from `Request` (is-a); `ElevatorController`
  **associates** `HallCall`s with the `Elevator` chosen to serve them.
- `ElevatorController` **composes** the fleet of `Elevator`s (owns them for
  the lifetime of the building's system).

## Step 4: Design Decisions & Patterns Used

**Why the State pattern for `Elevator`, instead of a `@status` flag.** The
naive version keeps `@status = :idle` and writes `press_button` as:

```ruby
def press_button(floor)
  if @status == :idle
    # start moving
  elsif @status == :moving_up
    # maybe add stop, maybe ignore
  elsif @status == :doors_open
    # reject or queue
  end
end
```

Every method on `Elevator` grows another branch as behavior gets more
realistic (should doors re-open if you press the button while closing?
should a car call in the *wrong* direction be accepted?). The State pattern
inverts this: each `ElevatorState` subclass implements `on_arrival` and
`request_floor` for *its own* situation only, and `Elevator` just delegates
to `@state`. Adding a new state (e.g., `OutOfServiceState`) means adding one
class, not editing every method on `Elevator`.

**Why hall calls and car calls are different classes.** A `CarCall` is
already unambiguous — it belongs to the car it was pressed inside, and
means "please also stop at this floor." A `HallCall` is ambiguous by
design — it's a request for *some* elevator, qualified by direction (an
up-call at floor 5 should not be satisfied by a car heading down past floor
5). Collapsing them into one `Request(floor, direction: nil)` class forces
every consumer to null-check `direction` to know which kind of request it
has — a sign the two should be separate types.

**Why the scheduling algorithm is a SCAN-style direction match, not
"nearest idle car."** "Pick the closest elevator" sounds right until you
picture: elevator A is at floor 2 moving up, elevator B is idle at floor 10.
A hall call at floor 5 going up arrives. The nearest-*idle* car is B (5
floors away) but A is *already heading there* and will arrive sooner and
more efficiently — sending B instead means two cars converge on nearby
floors while other requests wait. Real elevator systems use a **SCAN /
LOOK**-style algorithm: a car continues in its current direction, picking
up every compatible request along the way, before reversing. The
controller's job is to find whichever car can absorb the request into its
current sweep most cheaply — either an idle car (cost = distance) or a
moving car already heading toward the floor in the same direction
(cost = distance, but only if the floor is still ahead of it).

## Step 5: Code

```ruby
# --- Requests ---------------------------------------------------------

class Request
  attr_reader :floor

  def initialize(floor)
    @floor = floor
  end
end

class HallCall < Request
  attr_reader :direction # :up or :down

  def initialize(floor, direction)
    super(floor)
    @direction = direction
  end
end

class CarCall < Request
end

# --- Elevator states ----------------------------------------------------

class ElevatorState
  # Called every time the elevator arrives at a floor. Decides whether to
  # stop (open doors) and what state comes next.
  def on_arrival(elevator, floor)
    raise NotImplementedError
  end

  # Called when a floor is requested (hall call assigned by the controller,
  # or a car call pressed inside). Returns true if accepted.
  def request_floor(elevator, floor)
    elevator.stops.add(floor)
    true
  end
end

class IdleState < ElevatorState
  def on_arrival(elevator, floor)
    # Idle elevators don't move, so arrival doesn't apply; no-op.
  end

  def request_floor(elevator, floor)
    super
    elevator.state = floor > elevator.current_floor ? MovingUpState.new : MovingDownState.new
    true
  end
end

class MovingUpState < ElevatorState
  def on_arrival(elevator, floor)
    return unless elevator.stops.include?(floor)

    elevator.stops.delete(floor)
    elevator.state = DoorsOpenState.new
  end

  def request_floor(elevator, floor)
    # Accept immediately if the floor is ahead in the current direction;
    # otherwise it still gets queued and served after the direction flips
    # (the SCAN behavior — no interrupting the current sweep).
    super
  end
end

class MovingDownState < ElevatorState
  def on_arrival(elevator, floor)
    return unless elevator.stops.include?(floor)

    elevator.stops.delete(floor)
    elevator.state = DoorsOpenState.new
  end

  def request_floor(elevator, floor)
    super
  end
end

class DoorsOpenState < ElevatorState
  def on_arrival(elevator, floor)
    # Already stopped; nothing to do until doors close.
  end

  def request_floor(elevator, floor)
    # A new request while doors are open just queues; it doesn't reopen
    # doors or interrupt the close-and-move cycle.
    elevator.stops.add(floor)
    true
  end

  def close_doors(elevator)
    elevator.state = elevator.next_travel_state
  end
end

# --- Elevator -------------------------------------------------------------

class Elevator
  MAX_OCCUPANTS = 10

  attr_reader :id, :current_floor, :stops
  attr_accessor :state
  attr_reader :occupants

  def initialize(id, current_floor: 0)
    @id = id
    @current_floor = current_floor
    @stops = SortedSet.new
    @state = IdleState.new
    @occupants = 0
  end

  def direction
    case @state
    when MovingUpState then :up
    when MovingDownState then :down
    else :idle
    end
  end

  def press_button(floor)
    @state.request_floor(self, floor)
  end

  # Advances the car by one floor toward its next stop, or opens/closes
  # doors if it has arrived. In a real system this is driven by a timer;
  # here it's exposed as an explicit tick for testability.
  def step
    if @state.is_a?(DoorsOpenState)
      @state.close_doors(self)
      return
    end

    return if @stops.empty?

    @current_floor += (direction == :up ? 1 : -1) if @state.is_a?(MovingUpState) || @state.is_a?(MovingDownState)
    @state.on_arrival(self, @current_floor)
  end

  # After doors close, decide the next direction: continue the same way if
  # there are still stops ahead, reverse if stops remain behind, else idle.
  def next_travel_state
    return IdleState.new if @stops.empty?

    ahead_up = @stops.any? { |f| f > @current_floor }
    ahead_down = @stops.any? { |f| f < @current_floor }
    return MovingUpState.new if ahead_up
    return MovingDownState.new if ahead_down

    IdleState.new
  end

  def idle? = @state.is_a?(IdleState)
  def full? = @occupants >= MAX_OCCUPANTS
end

# --- Fleet controller / scheduler -----------------------------------------

class ElevatorController
  def initialize(elevators)
    @elevators = elevators
  end

  # SCAN-style assignment: prefer a car already moving toward the floor in
  # the matching direction (it "picks up" the request for free), otherwise
  # fall back to the closest idle car. Cars that are full are skipped.
  def request_elevator(floor, direction)
    candidates = @elevators.reject(&:full?)

    en_route = candidates.select do |e|
      e.direction == direction &&
        ((direction == :up && floor >= e.current_floor) ||
         (direction == :down && floor <= e.current_floor))
    end
    best = en_route.min_by { |e| (e.current_floor - floor).abs }

    best ||= candidates.select(&:idle?).min_by { |e| (e.current_floor - floor).abs }

    best&.tap { |e| e.press_button(floor) }
  end
end
```

**Using it:**

```ruby
fleet = [Elevator.new(1, current_floor: 0), Elevator.new(2, current_floor: 10)]
controller = ElevatorController.new(fleet)

# Hall call: someone at floor 5 wants to go up.
chosen = controller.request_elevator(5, :up)
chosen.id # => 1 (closer, and idle beats the farther idle car)

chosen.press_button(8) # car call from inside, once boarded
chosen.stops # => #<SortedSet: {5, 8}>

chosen.step until chosen.current_floor == 5 && chosen.state.is_a?(DoorsOpenState)
```

## Step 6: Edge Cases & Extensibility

- **New requests arriving mid-trip should not interrupt the current
  sweep.** This is the single most common mistake: if elevator A is moving
  up serving floors 5 and 8, and a hall call for floor 3 going down comes
  in, A should **not** reverse immediately — it finishes floors 5 and 8
  first, then reverses. The `request_floor` methods only ever *add* to
  `stops`; direction changes happen exclusively in `next_travel_state` once
  the current sweep is exhausted. Get this wrong and the elevator
  effectively becomes First-Come-First-Served, which is both slower on
  average and what a real elevator never does.
- **Capacity / weight limits.** `Elevator#full?` gates whether the
  controller will even consider a car. A more complete model would reject
  `press_button` for a *car call* once full (someone already inside
  selecting a floor is fine; someone new boarding when full should be
  turned away at the door, not at the button).
- **An elevator going out of service mid-request.** Add an
  `OutOfServiceState` that rejects `request_floor` entirely; the
  controller must also **reassign** any hall calls already queued for that
  car — this means `HallCall`s the controller assigned need to be tracked
  by the controller (not just pushed into `stops` and forgotten), so they
  can be redirected. Worth mentioning even if not fully coded live.
- **Starvation.** A naive "closest car wins" scheduler can starve a distant
  floor if requests keep appearing closer to other cars. A production
  system caps wait time per request and forces assignment past a
  threshold — a good thing to mention as a refinement, not something to
  over-engineer up front.
- **Doors reopening on obstruction** (a real elevator's door sensor) maps
  naturally onto `DoorsOpenState` gaining a `door_blocked` transition that
  resets its own close timer — the State pattern absorbs this without
  touching any other state.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you minimize average wait time across many elevators?"**
   Track each car's queue length and estimated time-to-arrival (not just
   floor distance — direction and current stops matter), and assign the
   request to the car with the lowest estimated cost rather than pure
   distance. At real scale this becomes a live optimization problem (bulk
   elevator dispatch algorithms), but the LLD-level answer is: make the
   cost function `request_elevator` uses richer than `(floor - current_floor).abs`.
2. **"Add express/priority floors (e.g., a penthouse floor with a
   dedicated car)."** Give some elevators a `serviceable_floors` set, and
   filter `candidates` in `request_elevator` to only cars where the floor
   is serviceable — no changes needed to the state machine.
3. **"What if two hall calls at the same floor request opposite
   directions?"** They're modeled as two distinct `HallCall`s (different
   `direction`), so they can legitimately be served by two different cars,
   or by one car making two separate visits — the model already supports
   this without special-casing.
4. **"How do you avoid the elevator oscillating between two close
   floors?"** This falls out of the SCAN design: stops are only served in
   the current direction until exhausted, so a request behind the car
   never causes an immediate reversal — it's picked up on the next sweep.
5. **"How would you test this?"** Unit-test each `ElevatorState` subclass's
   `on_arrival`/`request_floor` in isolation with a stub elevator, then
   integration-test full ride sequences (`press_button`, repeated `step`,
   assert stops served in a sane order) and the controller's assignment
   logic separately, using a fixed fleet of elevators in known states.
6. **"How would this change with thousands of elevators across many
   buildings (e.g., a SaaS platform monitoring elevator fleets)?"** That
   pushes into HLD territory — telemetry ingestion, per-building
   partitioning, and eventual consistency of car state across a network —
   worth naming explicitly as the LLD/HLD boundary, similar to how the
   Parking Lot example bridges into `System_Design/01_Concepts/09_distributed_systems_core.md`.

# Behavioral Design Patterns

Behavioral patterns are about **how objects communicate and distribute
responsibility** among themselves — swapping algorithms at runtime,
notifying dependents of changes, changing behavior based on internal
state, encapsulating requests as objects, routing a request through a
chain of handlers, and sharing the skeleton of an algorithm across
subclasses. If creational patterns are "how do I build this object" and
structural patterns are "how do these objects fit together," behavioral
patterns are "who does what, and how do they talk to each other."

## Interview Tips

**Strategy** is the single most useful pattern for LLD interviews, full
stop — it's the direct antidote to `case type` chains, which is exactly
the mistake that sinks candidates on questions like Parking Lot (see
`02_Interview_Questions/01_parking_lot.md`). If you internalize one
pattern deeply before an interview, make it this one. **State** is the
correct answer to an entire category of prompts — anything with an
explicit status/mode field driving different behavior (vending machines,
ATMs, traffic lights, order lifecycles) — and directly powers
`04_vending_machine.md` and `05_atm_machine.md` later in this folder.
**Observer** comes up whenever a prompt involves "notify subscribers/
watchers/listeners." **Command** and **Chain of Responsibility** are
common in slightly more systems-flavored LLD prompts (undo/redo, request
pipelines, approval workflows). **Template Method** is useful to recognize
but less often the star of an answer. **Visitor** is worth knowing by name
only — very rarely worth implementing live in an interview.

## Strategy

**Problem it solves:** you have a family of interchangeable
algorithms/behaviors for accomplishing the same conceptual task, and
without this pattern that family ends up as a `case`/`if` chain baked
directly into the class that needs the behavior — meaning every new
variant requires editing that class, and the class now has to know the
details of every variant.

This is exactly the pattern already at work in the parking lot design.
`Vehicle#spots_required(spot_type)` is a strategy method — `Bike`, `Car`,
and `Van` each implement it differently, and `ParkingLot#park` never
branches on vehicle type at all; it just asks whichever vehicle object
it's holding "how many spots do you need here?" Each vehicle subclass *is*
a spot-allocation strategy, selected simply by which object you're holding.

```text
   ParkingLot                     Vehicle (strategy interface)
   - park(vehicle)  ----uses---->  + spots_required(spot_type)
                                          ^        ^        ^
                                        Bike      Car      Van
                                      (needs 1) (needs 1) (needs 1 van_spot,
                                                            or 3 bike_spot)

   ParkingLot never branches on vehicle type — it just calls the method
   and lets whichever concrete strategy object is plugged in answer.
```

The follow-up the parking lot file previews — pricing — is the same
pattern applied again:

```ruby
class PricingStrategy
  def calculate(ticket)
    raise NotImplementedError
  end
end

class HourlyPricing < PricingStrategy
  RATE_PER_HOUR = 2.0

  def calculate(ticket)
    hours = ((Time.now - ticket.entry_time) / 3600.0).ceil
    hours * RATE_PER_HOUR
  end
end

class FlatRatePricing < PricingStrategy
  def calculate(_ticket) = 15.0
end

class ParkingLot
  def initialize(pricing_strategy: HourlyPricing.new)
    @pricing_strategy = pricing_strategy
    # ...
  end

  def charge(ticket)
    @pricing_strategy.calculate(ticket)
  end
end

ParkingLot.new(pricing_strategy: FlatRatePricing.new)
# Swapping pricing models is a one-line change at construction time —
# ParkingLot's own code never changes.
```

### When NOT to use this

If there's genuinely only one algorithm, and no credible reason to expect
a second one, Strategy is unnecessary indirection — a plain method is
clearer. The signal to introduce it is either (a) more than one variant
already exists, or (b) you can point to a concrete, likely-next variant
(as the parking lot file does with pricing) — not "this might need to
vary somehow, someday."

## Observer

**Problem it solves:** one object's state change needs to trigger
reactions in an open-ended, changeable set of other objects, without the
first object needing to know the concrete classes of everything that
cares about it.

```ruby
class Stock
  def initialize(symbol, price)
    @symbol = symbol
    @price = price
    @observers = []
  end

  def subscribe(observer)
    @observers << observer
  end

  def unsubscribe(observer)
    @observers.delete(observer)
  end

  def price=(new_price)
    @price = new_price
    notify_observers
  end

  private

  def notify_observers
    @observers.each { |o| o.update(@symbol, @price) }
  end
end

class PriceDisplay
  def update(symbol, price)
    puts "#{symbol} is now $#{price}"
  end
end

class PriceAlert
  def initialize(threshold)
    @threshold = threshold
  end

  def update(symbol, price)
    puts "ALERT: #{symbol} crossed #{@threshold}!" if price >= @threshold
  end
end

stock = Stock.new("ACME", 100)
stock.subscribe(PriceDisplay.new)
stock.subscribe(PriceAlert.new(120))

stock.price = 125
# => "ACME is now $125"
# => "ALERT: ACME crossed 120!"
```

Ruby ships a built-in `Observable` module (`require "observable"`) that
gives you `changed`/`notify_observers`/`add_observer` for free, though it's
common enough in interviews to just implement the subscribe/notify list
directly, as above — it's a handful of lines and shows you understand the
mechanics rather than just naming a stdlib module.

This is the same shape as "notify all watchers when an auction's price
changes" or "notify all subscribers when a YouTube channel uploads a new
video" — any one-to-many "thing changed, tell everyone who cares" scenario.

### When NOT to use this

If there's exactly one interested party, a direct method call is simpler
than the subscribe/notify machinery. Also watch for Observer hiding a
performance or ordering problem — if notification order matters, or if one
observer's `#update` can throw and should or shouldn't block the others,
that needs to be handled explicitly; Observer alone doesn't solve it.

## State

**Problem it solves:** an object's behavior needs to change based on an
internal status/mode, and the naive approach — a `status` field checked by
`if`/`case` in every method — spreads the same conditional across the
entire class and gets worse with every new state or every new method that
needs to be state-aware.

This is exactly the right pattern for a Vending Machine or an ATM — see
`02_Interview_Questions/04_vending_machine.md` and
`05_atm_machine.md`, both of which use State directly rather than a
`status` field with conditionals scattered through their methods.

```ruby
class TrafficLightState
  def next
    raise NotImplementedError
  end

  def name
    raise NotImplementedError
  end
end

class RedState < TrafficLightState
  def next = GreenState.new
  def name = "red"
end

class GreenState < TrafficLightState
  def next = YellowState.new
  def name = "green"
end

class YellowState < TrafficLightState
  def next = RedState.new
  def name = "yellow"
end

class TrafficLight
  def initialize
    @state = RedState.new
  end

  def advance
    @state = @state.next
  end

  def current = @state.name
end

light = TrafficLight.new
light.current   # => "red"
light.advance
light.current   # => "green"
light.advance
light.current   # => "yellow"
```

```text
   RedState --next--> GreenState --next--> YellowState --next--> RedState
   (cycle: each state object knows only what it transitions to next —
    TrafficLight itself holds no transition logic at all)
```

Contrast with the naive version: `def advance; case @status; when :red then
@status = :green; when :green then @status = :yellow; when :yellow then
@status = :red; end; end` — functionally similar for 3 states, but every
additional state-dependent method (`can_cars_go?`, `duration_seconds`)
would need its own parallel `case @status` block. With State, each of
those becomes a method on the state classes instead, and the conditionals
never accumulate in `TrafficLight`.

### When NOT to use this

If there are only two states and one trivial transition (e.g., a boolean
`open`/`closed` toggle), a plain enum/boolean field is simpler than a set
of state classes. State earns its keep once you have three or more states,
transitions with real logic, or multiple methods whose behavior depends on
the current state — that's when the alternative (conditionals duplicated
across methods) actually gets painful.

## Command

**Problem it solves:** you want to treat a request or action as a
first-class object — so it can be queued, logged, passed around, undone,
or redone — rather than as an immediate direct method call that leaves no
trace of itself afterward.

```ruby
class Command
  def execute
    raise NotImplementedError
  end

  def undo
    raise NotImplementedError
  end
end

class InsertTextCommand < Command
  def initialize(document, text, position)
    @document = document
    @text = text
    @position = position
  end

  def execute
    @document.insert(@text, @position)
  end

  def undo
    @document.delete(@position, @text.length)
  end
end

class TextEditor
  def initialize(document)
    @document = document
    @history = []
  end

  def run(command)
    command.execute
    @history << command
  end

  def undo_last
    return if @history.empty?

    @history.pop.undo
  end
end

document = Document.new
editor = TextEditor.new(document)
editor.run(InsertTextCommand.new(document, "hello", 0))
editor.undo_last   # calls InsertTextCommand#undo, removing "hello" again
```

The same shape covers a remote control mapping physical buttons to actions
(`LightOnCommand`, `LightOffCommand` assigned to a button slot at runtime,
swappable without changing the `RemoteControl` class), or a job queue where
each queued item is a Command waiting to be executed later, possibly on a
different thread or process.

### When NOT to use this

If you never need to queue, log, delay, or undo an action — it's just a
direct method call, immediately — wrapping it in a Command object is pure
ceremony. The tell that you need it: the word "undo," "queue," "replay,"
or "log every action taken" appearing in the requirements.

## Chain of Responsibility

**Problem it solves:** a request needs to be handled by exactly one of
several possible handlers, and which one should handle it depends on
runtime conditions — without this pattern, that decision becomes a large
`if`/`elsif` that knows about every handler and has to be edited whenever a
handler is added, removed, or reordered.

```ruby
class TicketHandler
  attr_accessor :next_handler

  def handle(ticket)
    if can_handle?(ticket)
      resolve(ticket)
    elsif @next_handler
      @next_handler.handle(ticket)
    else
      puts "No handler available for: #{ticket}"
    end
  end
end

class Tier1Handler < TicketHandler
  def can_handle?(ticket) = ticket[:severity] == :low
  def resolve(ticket) = puts "Tier1 resolved: #{ticket[:issue]}"
end

class Tier2Handler < TicketHandler
  def can_handle?(ticket) = ticket[:severity] == :medium
  def resolve(ticket) = puts "Tier2 resolved: #{ticket[:issue]}"
end

class Tier3Handler < TicketHandler
  def can_handle?(ticket) = ticket[:severity] == :high
  def resolve(ticket) = puts "Tier3 resolved: #{ticket[:issue]}"
end

tier1 = Tier1Handler.new
tier2 = Tier2Handler.new
tier3 = Tier3Handler.new
tier1.next_handler = tier2
tier2.next_handler = tier3

tier1.handle(severity: :medium, issue: "Login broken")
# => "Tier2 resolved: Login broken"
# (Tier1 passed it along because can_handle? returned false)
```

```text
   request --> Tier1Handler --(can't handle)--> Tier2Handler --(can't handle)--> Tier3Handler
                    |handles it                       |handles it                     |handles it
                    v                                  v                               v
                 resolved                           resolved                        resolved

   The sender only ever talks to Tier1 — it doesn't know or care how
   many handlers exist downstream, or which one ends up handling it.
```

### When NOT to use this

If it's always obvious, statically, which single handler should process a
given request, a chain adds indirection for no benefit — call that handler
directly. Chain of Responsibility earns its keep when the set of possible
handlers, or the order they're tried in, can change independently of the
sender — and when "no handler accepted this" needs to be a valid, handled
outcome.

## Template Method

**Problem it solves:** several related classes need to perform the same
overall sequence of steps, but one or two of those steps differ per class
— and without this pattern, each class either duplicates the entire
sequence (with tiny variations buried inside) or the sequence itself lives
in some caller that has to know each class's specific steps.

**Contrast with Strategy:** Template Method uses inheritance and fixes the
*shape* of the algorithm in the base class, letting subclasses override
only specific steps. Strategy uses composition and swaps out the *entire*
algorithm as one interchangeable object. If only one step varies and the
overall sequence is fixed, that's Template Method; if the whole algorithm
needs to be swappable, that's Strategy.

```ruby
class DataExporter
  # The template method: fixed sequence, not overridden by subclasses
  def export
    data = fetch_data
    formatted = format(data)
    write(formatted)
  end

  def fetch_data
    raise NotImplementedError
  end

  def format(data)
    raise NotImplementedError
  end

  def write(formatted)
    puts formatted
  end
end

class CsvExporter < DataExporter
  def fetch_data = [["id", "name"], [1, "Alice"], [2, "Bob"]]

  def format(data)
    data.map { |row| row.join(",") }.join("\n")
  end
end

class JsonExporter < DataExporter
  def fetch_data = [{ id: 1, name: "Alice" }, { id: 2, name: "Bob" }]

  def format(data)
    require "json"
    data.to_json
  end
end

CsvExporter.new.export
# id,name
# 1,Alice
# 2,Bob

JsonExporter.new.export
# [{"id":1,"name":"Alice"},{"id":2,"name":"Bob"}]
```

Both exporters share the exact same `export` sequence — fetch, format,
write — and only override `format` (and `fetch_data`, in this example).
`write` is shared as-is by both, showing that subclasses only need to
override the steps that actually differ.

### When NOT to use this

If subclasses need to change the overall *order* of steps, not just the
content of one or two steps, Template Method's fixed sequence is fighting
you — Strategy (swap the whole algorithm) or plain composition fits
better. Also avoid it when there's only one class currently doing the
sequence — a shared base class with abstract steps is premature until a
second, genuinely similar class exists.

## Visitor (worth recognizing, rarely worth implementing live)

Visitor separates an algorithm from the object structure it operates on:
instead of adding a new method to every class in a hierarchy every time you
need a new operation (e.g., adding `#export_to_xml` to every node type in
an AST), you define a `Visitor` with one `visit_X` method per class, and
each class gets a single `#accept(visitor)` method that just calls back
into the right `visit_` method. New operations become new Visitor classes,
with zero changes to the visited classes — the inverse trade-off of
Template Method/Strategy, where adding a new *type* to the hierarchy is
what's expensive (every visitor needs a new `visit_` method), but adding a
new *operation* is cheap. It shows up in real compilers/AST tooling and is
worth being able to name and sketch the shape of if asked, but it's dense
enough (double-dispatch, a visitor interface per node type) that it's
rarely the pattern an interviewer expects you to produce working code for
from scratch in 45 minutes.

## Quick Recall — Self-Test

1. **Where does the parking lot design already use Strategy, even though
   the file never uses that word explicitly?**
   `Vehicle#spots_required(spot_type)` — each subclass (`Bike`, `Car`,
   `Van`) implements it differently, and `ParkingLot#park` calls it
   polymorphically without ever branching on vehicle type. Each vehicle
   subclass is effectively a spot-allocation strategy.

2. **What's the concrete difference between Strategy and Template
   Method?**
   Strategy uses composition and swaps the entire algorithm as one
   interchangeable object; Template Method uses inheritance and fixes the
   overall sequence in a base class, letting subclasses override only
   specific steps within that fixed sequence.

3. **Why is State a better fit than a `status` field with `case`
   statements once a class has 3+ states and several state-dependent
   methods?**
   Because each new state-dependent method would need its own parallel
   `case @status` block scattered through the class. State moves each
   state's behavior into its own class, so adding a state or a new
   state-aware method doesn't multiply conditionals across the original
   class.

4. **What's the tell in a requirements doc that you need Command rather
   than a plain method call?**
   Words like "undo," "redo," "queue this for later," or "log every action
   taken" — anything that requires treating the action itself as data you
   can hold onto, not just execute immediately.

5. **In Chain of Responsibility, what happens if no handler in the chain
   can handle the request, and why does that matter?**
   The request falls through to the end of the chain unresolved — the
   design needs to explicitly define what happens then (log it, raise, a
   default fallback handler). It matters because forgetting this case
   silently drops requests with no visible error.

6. **Why is Observer a good fit for "notify all subscribers when a
   YouTube channel uploads," and what's a limitation it doesn't solve on
   its own?**
   It fits because the channel (subject) doesn't need to know the concrete
   type of every subscriber — it just calls `#update` on whoever is
   subscribed. It doesn't solve notification ordering or failure isolation
   on its own — if one observer's `#update` raises, you need to decide
   explicitly whether that should block the rest.

7. **Why is Visitor rarely the pattern you should attempt to hand-write in
   a 45-minute interview, even if you recognize it fits?**
   It requires double-dispatch (an `#accept` method per visited class plus
   a `visit_X` method per type on the visitor) which is a lot of
   boilerplate to set up correctly under time pressure — better to name it
   and describe the trade-off (cheap to add new operations, expensive to
   add new types) than to build it live.

8. **A vending machine has states Idle, HasMoney, Dispensing, OutOfStock.
   Sketch, in one sentence, why State fits better here than a boolean
   flag.**
   There are more than two states with genuinely different valid
   transitions and behavior (e.g., `insert_coin` is valid from Idle but
   not from Dispensing), which a single boolean can't represent — each
   state needs its own object defining what's valid from it, exactly the
   problem State solves.

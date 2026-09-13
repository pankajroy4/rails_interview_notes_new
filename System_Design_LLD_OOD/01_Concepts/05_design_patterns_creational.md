# Creational Design Patterns

Creational patterns are about **how objects get created** — specifically,
how to keep object-creation logic from leaking into and cluttering every
place that needs a new object. The tell that you need one of these: you find
yourself writing `if`/`case` logic around `.new` calls, or a constructor
that's grown 8 optional keyword arguments, or code that assumes "there's
only ever one of these" without actually enforcing it.

## Interview Tips

Of the five patterns here, **Factory Method** is the one you'll actually
reach for most in an LLD interview — almost every worked example (vehicles,
payment methods, notification channels) has a family of related subclasses
that need to be instantiated from some input, and "how do you decide which
class to instantiate" is a natural follow-up question. **Singleton** comes
up constantly too, but more often as a trap: interviewers ask "would you
make this a Singleton?" to see whether you understand its downsides, not
because they want you to use one. **Builder** is worth knowing cold for any
"this object has a lot of optional configuration" scenario. **Abstract
Factory** and **Prototype** are asked about far less often — know the shape
and the canonical example well enough to explain them, but don't expect to
have to design one from scratch under interview pressure.

## Singleton

**Problem it solves:** some things in a system genuinely should have
exactly one instance — a single application-wide logger, a single
configuration object, a single connection pool. Without enforcement, nothing
stops two parts of the codebase from independently constructing two
`Config` objects that quietly drift out of sync.

```ruby
# Using Ruby's built-in Singleton module
require "singleton"

class AppConfig
  include Singleton

  attr_accessor :max_retries, :timeout_seconds

  def initialize
    @max_retries = 3
    @timeout_seconds = 30
  end
end

AppConfig.instance.max_retries        # => 3
AppConfig.instance.max_retries = 5
AppConfig.instance.max_retries        # => 5 (same instance everywhere)
AppConfig.new                         # => NoMethodError: private method 'new'
```

```ruby
# Hand-rolled version (what Singleton does under the hood) — worth knowing
# because interviewers sometimes ask you to implement it, not just use it
class Logger
  @instance_mutex = Mutex.new

  class << self
    def instance
      return @instance if @instance

      @instance_mutex.synchronize do
        @instance ||= new
      end
      @instance
    end

    private :new
  end

  def log(message)
    puts "[LOG] #{message}"
  end
end
```

Note the mutex — a naive `@instance ||= new` is not thread-safe under true
parallelism (two threads can both see `@instance` as `nil` and both call
`new`). Mentioning this unprompted is a good signal.

**Why interviewers push back on Singletons.** This is the pattern most
worth having a real opinion on, not just a definition of. The problems:

- **Hidden global state.** Any code, anywhere, can read and mutate the
  singleton. Two unrelated classes can end up coupled through it without
  that dependency showing up in either class's constructor or method
  signature — you have to read the implementation to discover it.
- **Testing gets harder.** Because the instance is shared and typically
  memoized for the life of the process, one test that mutates the
  singleton's state can leak into the next test unless you remember to
  reset it — a classic source of flaky, order-dependent test suites.
- **It's a workaround for not doing dependency injection.** Most of the
  time, "I need every object to see the same config/logger" is better
  solved by constructing that object once at the composition root (e.g.
  app boot) and passing it into whatever needs it — a plain object,
  injected explicitly, is easier to test (swap in a fake) and makes the
  dependency visible in the constructor signature instead of hidden inside
  method bodies.

If an interviewer asks "would a Singleton work well here?", the strong
answer is usually: "It would work, but I'd prefer constructing one instance
at startup and injecting it, because that keeps the dependency explicit and
testable — I'd only reach for an actual Singleton if I needed to guarantee
single-instance-ness independent of how the object gets wired together
(e.g., a hardware resource handle)."

### When NOT to use this

Don't use Singleton just because "there's only one of these right now" —
that's true of lots of objects that don't need global-access enforcement.
Reach for it only when (a) exactly-one-instance is a genuine invariant you
need enforced, not just a current fact, and (b) global access is actually
required across the codebase, not just convenient. Otherwise, construct one
instance and pass it around.

## Factory Method

**Problem it solves:** calling code that needs to create one of several
related subclasses, based on some runtime input (a type string, a config
value), ends up littered with `case`/`if` blocks calling different
constructors — and every time a new subclass is added, every one of those
call sites needs to be found and updated.

```ruby
# Before: creation logic scattered across the codebase
def handle_new_vehicle(type, plate)
  case type
  when :bike then Bike.new(plate)
  when :car  then Car.new(plate)
  when :van  then Van.new(plate)
  else raise ArgumentError, "unknown vehicle type: #{type}"
  end
end
# ...and the same case statement, copy-pasted, shows up wherever else
# a Vehicle needs to be constructed from a type + plate.
```

```ruby
# After: one Factory Method, everyone else just calls it
class VehicleFactory
  VEHICLE_CLASSES = {
    bike: Bike,
    car:  Car,
    van:  Van
  }.freeze

  def self.create(type, plate)
    klass = VEHICLE_CLASSES.fetch(type) do
      raise ArgumentError, "unknown vehicle type: #{type}"
    end
    klass.new(plate)
  end
end

VehicleFactory.create(:van, "VAN-001")   # => #<Van ...>
```

This ties directly back to the parking lot design
(`02_Interview_Questions/01_parking_lot.md`): `Vehicle`/`Bike`/`Car`/`Van`
already form the right hierarchy for a Factory Method. If the interviewer
extends the problem to "vehicles arrive as raw strings from an API," a
`VehicleFactory.create(type_string, plate)` is exactly where that
translation belongs — not scattered through `ParkingLot`. Calling code
depends only on `VehicleFactory` and the `Vehicle` interface, never on the
concrete `Bike`/`Car`/`Van` classes directly, so adding a `Truck` is a
one-line addition to `VEHICLE_CLASSES` plus the new class itself.

### When NOT to use this

If there's only one concrete class being created, or the mapping from input
to class is trivial and used in exactly one place, a factory is unnecessary
indirection — just call `.new`. Introduce a Factory Method when the same
"which class do I instantiate" decision is duplicated across multiple call
sites, or when construction itself involves nontrivial logic worth
isolating (not just a type lookup).

## Abstract Factory

**Problem it solves:** you need to produce a *family* of related objects
that must be used together consistently, and you want calling code to be
completely agnostic about which family it's using. Plain Factory Method
produces one product type (with variants); Abstract Factory produces
several related product types at once, from one factory object, guaranteeing
they're compatible with each other.

```ruby
# Product interfaces
class Button
  def render
    raise NotImplementedError
  end
end

class Checkbox
  def render
    raise NotImplementedError
  end
end

# Windows family
class WindowsButton < Button
  def render = "[Windows-style button]"
end

class WindowsCheckbox < Checkbox
  def render = "[Windows-style checkbox]"
end

# Mac family
class MacButton < Button
  def render = "(Mac-style button)"
end

class MacCheckbox < Checkbox
  def render = "(Mac-style checkbox)"
end

# Abstract factory interface + concrete factories, one per family
class UIFactory
  def create_button
    raise NotImplementedError
  end

  def create_checkbox
    raise NotImplementedError
  end
end

class WindowsUIFactory < UIFactory
  def create_button   = WindowsButton.new
  def create_checkbox = WindowsCheckbox.new
end

class MacUIFactory < UIFactory
  def create_button   = MacButton.new
  def create_checkbox = MacCheckbox.new
end

# Calling code depends only on UIFactory — never knows which OS family
def render_form(factory)
  puts factory.create_button.render
  puts factory.create_checkbox.render
end

render_form(WindowsUIFactory.new)
render_form(MacUIFactory.new)
```

**The distinction that interviewers actually check for:** Factory Method
answers "which one class do I build?" (one product axis — vehicle type).
Abstract Factory answers "which whole *set* of mutually-compatible classes
do I build?" (a family — you'd never want a `WindowsButton` paired with a
`MacCheckbox`, and the abstract factory makes that mismatch structurally
impossible, because both come from the same concrete factory instance).

### When NOT to use this

Abstract Factory adds a factory-of-factories layer of indirection — it's
only worth it when you truly have multiple parallel families that must stay
internally consistent (cross-platform UI kits, per-region compliance rule
sets, per-database-vendor query builders). If you only ever have one product
type varying, or the "families" never actually diverge in practice, this is
over-engineering; use plain Factory Method.

## Builder

**Problem it solves:** an object has many optional configuration
parameters, and a single constructor covering all combinations either
requires callers to pass `nil` for everything they don't care about, or
balloons into an unreadable pile of keyword arguments.

```ruby
# Before: constructor with 8 optional keyword args
class Pizza
  def initialize(size:, crust: "regular", cheese: true, pepperoni: false,
                  mushrooms: false, olives: false, extra_sauce: false,
                  gluten_free: false)
    # ...
  end
end

Pizza.new(size: "large", crust: "thin", mushrooms: true, extra_sauce: true)
# readable-ish here, but gets worse as options grow, and there's no
# validation step or intermediate state while building
```

```ruby
# After: Builder — chainable, step-by-step, construction separated from
# the final representation
class Pizza
  attr_reader :size, :toppings, :crust

  def initialize(size, crust, toppings)
    @size = size
    @crust = crust
    @toppings = toppings
  end

  def to_s
    "#{size} #{crust}-crust pizza with #{toppings.join(', ')}"
  end
end

class PizzaBuilder
  def initialize(size)
    @size = size
    @crust = "regular"
    @toppings = []
  end

  def crust(type)
    @crust = type
    self
  end

  def add_topping(topping)
    @toppings << topping
    self
  end

  def build
    Pizza.new(@size, @crust, @toppings)
  end
end

pizza = PizzaBuilder.new("large")
  .crust("thin")
  .add_topping("mushrooms")
  .add_topping("extra sauce")
  .build

puts pizza
# => "large thin-crust pizza with mushrooms, extra sauce"
```

Each `.add_topping` call returns `self`, which is what makes the chain
work — a common Ruby idiom worth having ready. The builder can also
validate incrementally (e.g., reject a 6th topping) or hold intermediate
state that the final `Pizza` doesn't need to carry at all.

### When NOT to use this

If an object has 2-3 optional parameters, Ruby keyword arguments with
defaults already solve this cleanly — a Builder is unnecessary ceremony.
Reach for Builder when the number of optional parameters is large, when
construction has meaningful multi-step validation, or when the same kind of
object needs to be assembled in noticeably different ways (a
`PizzaBuilder` vs. a hypothetical `CalzonePizzaBuilder` sharing steps).

## Prototype

**Problem it solves:** creating a new object from scratch is expensive
(expensive computation, an external call, heavy default setup), or you want
a pre-configured "template" instance that variations get cloned from rather
than rebuilt every time.

```ruby
class MonsterTemplate
  attr_accessor :name, :hp, :abilities

  def initialize(name, hp, abilities)
    @name = name
    @hp = hp
    @abilities = abilities   # an Array — mutable!
  end

  def initialize_copy(source)
    super
    # Without this override, @abilities on the clone would be the SAME
    # array object as the source's — mutating one mutates both. This is
    # Ruby's shallow-copy gotcha: dup/clone copy the object's instance
    # variables, but not what those variables point to.
    @abilities = source.abilities.dup
  end
end

goblin_template = MonsterTemplate.new("Goblin", 30, ["stab", "flee"])

goblin1 = goblin_template.dup
goblin1.abilities << "sneak"

goblin2 = goblin_template.dup
goblin2.abilities   # => ["stab", "flee"]  (NOT polluted by goblin1's mutation,
                     #     because initialize_copy gave it its own array)
```

`.dup` and `.clone` both trigger `initialize_copy`; the difference between
them is that `.clone` also copies frozen state and singleton methods, while
`.dup` does not — worth knowing but rarely the crux of an interview
question. The important thing to say out loud: **Ruby's default copy is
shallow**, so any object with nested mutable state (arrays, hashes, other
objects) needs an `initialize_copy` override, or those nested objects stay
shared between the original and every clone.

### When NOT to use this

If constructing a fresh instance from a constructor is already cheap and
simple, cloning buys you nothing but the shallow-copy footgun above. Reach
for Prototype when construction is genuinely expensive/complex, or when
"start from this known-good configured instance" is a meaningful concept in
the domain (game entity templates, document templates) — not as a generic
substitute for calling `.new`.

## Quick Recall — Self-Test

1. **Why is a naive `@instance ||= new` Singleton not safe under true
   thread-level parallelism?**
   Two threads can both evaluate `@instance` as `nil` before either
   assignment completes, so both proceed to call `new`, producing two
   instances. A mutex around the check-and-assign (or memoizing at class
   load time) closes the race.

2. **What's the single biggest reason interviewers are skeptical of
   Singletons, beyond "there can be more than one instance later"?**
   Hidden global state — any code can read/mutate it without that
   dependency appearing in a constructor or method signature, which makes
   coupling invisible and makes tests leak state into each other unless
   explicitly reset.

3. **How does Abstract Factory differ from plain Factory Method?**
   Factory Method produces one product type with variants (e.g., "which
   `Vehicle` subclass"). Abstract Factory produces a whole family of related
   product types from one factory object, guaranteeing the family members
   are mutually compatible (e.g., a `Button` and `Checkbox` from the same
   OS family).

4. **When is a Builder overkill?**
   When the object has only a couple of optional parameters — plain Ruby
   keyword arguments with defaults already handle that cleanly. Builder
   earns its keep with many optional parameters, multi-step validation, or
   genuinely different assembly sequences for the same kind of object.

5. **What's Ruby's shallow-copy gotcha with `.dup`/`.clone`, and how do you
   fix it?**
   `.dup`/`.clone` copy instance variables, not the objects those variables
   reference — a cloned object's array/hash instance variable is the same
   object as the source's until you override `initialize_copy` to
   explicitly `.dup` those nested values too.

6. **In the parking lot design, where would a Factory Method naturally
   fit, and why isn't it there from the start?**
   `VehicleFactory.create(type, plate)` would centralize turning a raw type
   input (e.g., a string from an API) into a `Bike`/`Car`/`Van`/`Truck`
   instance. It isn't needed in the base design because vehicles are
   constructed directly by test/caller code; it becomes worth adding once
   that type-to-class decision starts getting duplicated across call sites.

7. **Give one concrete reason to prefer dependency injection over a
   Singleton for a shared logger.**
   Injecting a logger instance into each class's constructor makes the
   dependency explicit and lets tests substitute a fake/spy logger per
   test without any shared global state to reset between tests.

8. **Why does Prototype specifically call out `initialize_copy`, rather
   than just relying on `.dup`?**
   Because `.dup` alone performs a shallow copy — nested mutable objects
   (arrays, hashes, other objects) remain shared between the original and
   the clone. `initialize_copy` is the hook where you explicitly deep-copy
   those nested values so clones are truly independent.

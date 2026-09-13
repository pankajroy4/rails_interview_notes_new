# Structural Design Patterns

Structural patterns are about **how objects and classes compose into larger
structures** while keeping those structures flexible — wrapping
incompatible interfaces, adding behavior without touching existing classes,
hiding complexity behind a simpler surface, controlling access to an
object, or treating a tree of objects uniformly. The common thread: none of
these patterns change *what* an object fundamentally does, they change how
it's **assembled with or exposed to** other objects.

## Interview Tips

**Decorator** and **Facade** are the two most likely to come up directly —
Decorator because "add optional behavior/pricing/toppings without an
explosion of subclasses" is a very common LLD prompt shape (coffee orders,
pizza toppings, middleware chains), and Facade because almost every
multi-class design eventually needs a single entry point that coordinates
several subsystems (checkout, order placement). **Adapter** comes up
whenever a design question involves integrating a third-party API or
legacy interface. **Proxy** and **Composite** are asked about less often as
the primary pattern of a question, but Composite specifically is the
correct answer whenever a problem has a recursive tree shape (file
systems, org charts, UI component trees) — recognizing that shape quickly
is the real skill being tested.

## Adapter

**Problem it solves:** you have code written against one interface, and you
need to use an object that exposes an incompatible interface — most often a
third-party library — without modifying either your code or the library.

```ruby
# The interface your application code is written against
class PaymentGateway
  def charge(amount)
    raise NotImplementedError
  end
end

# A third-party client you don't control, with an incompatible interface:
# takes cents (not dollars) and a separate currency argument
class StripeClient
  def create_charge(amount_cents, currency)
    puts "Stripe: charging #{amount_cents} #{currency}"
    { status: "succeeded" }
  end
end

# Adapter: translates PaymentGateway#charge(amount) into
# StripeClient#create_charge(cents, currency), so callers never know
# Stripe is involved
class StripeAdapter < PaymentGateway
  def initialize(stripe_client = StripeClient.new)
    @stripe_client = stripe_client
  end

  def charge(amount)
    cents = (amount * 100).round
    result = @stripe_client.create_charge(cents, "usd")
    result[:status] == "succeeded"
  end
end

def checkout(gateway, amount)
  gateway.charge(amount) ? "payment ok" : "payment failed"
end

checkout(StripeAdapter.new, 19.99)   # checkout code never mentions Stripe
```

If you later swap Stripe for a different processor, you write a new
adapter (`PaypalAdapter`) implementing the same `PaymentGateway` interface
— `checkout` and every other caller need zero changes.

### When NOT to use this

If you control both sides of the interface (e.g., it's all your own code),
just make them consistent directly instead of introducing an adapter layer
— that's solving a problem you don't have. Adapter earns its keep
specifically when one side is fixed and out of your control (a third-party
library, a legacy system you can't refactor).

## Decorator

**Problem it solves:** you need to add behavior to a *specific instance* of
an object at runtime, optionally in combination with other added behaviors,
without modifying the object's class and without that behavior affecting
every other instance of the same class.

**Contrast with inheritance, explicitly:** a subclass adds behavior to
*every* instance of that type, fixed at compile-time (`MilkCoffee < Coffee`
means every `MilkCoffee` always has milk). A decorator wraps one specific
object at runtime, and decorators can be stacked in any combination — you'd
need a subclass for every combination (`MilkSugarCoffee`,
`MilkSugarWhipCoffee`, ...) to get the same flexibility from inheritance
alone.

```ruby
class Coffee
  def cost = 2.00
  def description = "Coffee"
end

# Decorators share the same interface as the thing they wrap
class CoffeeDecorator
  def initialize(coffee)
    @coffee = coffee
  end

  def cost = @coffee.cost
  def description = @coffee.description
end

class MilkDecorator < CoffeeDecorator
  def cost = @coffee.cost + 0.50
  def description = "#{@coffee.description} + milk"
end

class SugarDecorator < CoffeeDecorator
  def cost = @coffee.cost + 0.25
  def description = "#{@coffee.description} + sugar"
end

order = SugarDecorator.new(MilkDecorator.new(Coffee.new))
order.description   # => "Coffee + milk + sugar"
order.cost           # => 2.75

# Any combination, in any order, no new class needed for each combination
plain = Coffee.new
just_milk = MilkDecorator.new(Coffee.new)
```

```text
Coffee  <---- wraps ---- MilkDecorator  <---- wraps ---- SugarDecorator
(cost=2.00)                (cost=2.50)                     (cost=2.75)

Each layer forwards to the one it wraps, then adds its own bit on top.
Stack as many layers as needed, in whatever order.
```

### When NOT to use this

If the set of behavior combinations is small and fixed, a handful of plain
subclasses (or even a single class with boolean flags) can be simpler to
read than a chain of decorator objects. Decorator earns its keep when
combinations genuinely need to compose freely at runtime — otherwise the
indirection of "call a method, which calls a method, which calls a method"
several layers deep makes debugging harder for no real benefit.

## Facade

**Problem it solves:** completing one logical operation requires
coordinating several subsystems in a specific sequence, and without a
facade, every piece of calling code that wants to "place an order" has to
know and correctly orchestrate all of those subsystems itself.

```ruby
class Inventory
  def reserve(item, qty)
    puts "Inventory: reserved #{qty}x #{item}"
    true
  end
end

class Payment
  def charge(amount)
    puts "Payment: charged $#{amount}"
    true
  end
end

class Shipping
  def schedule(item, address)
    puts "Shipping: scheduled #{item} to #{address}"
    true
  end
end

# Facade: one simple method, hides the orchestration of three subsystems
class CheckoutFacade
  def initialize
    @inventory = Inventory.new
    @payment = Payment.new
    @shipping = Shipping.new
  end

  def place_order(item, qty, amount, address)
    return false unless @inventory.reserve(item, qty)
    return false unless @payment.charge(amount)

    @shipping.schedule(item, address)
    true
  end
end

CheckoutFacade.new.place_order("Widget", 2, 39.98, "123 Main St")
# Caller doesn't touch Inventory, Payment, or Shipping directly.
```

The subsystems (`Inventory`, `Payment`, `Shipping`) still exist as
independently usable classes — the facade doesn't hide them, it just gives
callers who don't need fine-grained control a simpler default path.

### When NOT to use this

Don't build a facade if there's only one subsystem to coordinate, or if
callers genuinely need fine-grained control over each subsystem's calls
(a facade that just forwards one-to-one to a single method is pointless
wrapping). Also watch for a facade turning into a god object — if it
accumulates business logic itself rather than just orchestrating calls, that
logic belongs in the subsystems or a dedicated service, not the facade.

## Proxy

**Problem it solves:** you want to control access to an object — delay
creating it until it's actually needed, check permissions before letting a
call through, or cache expensive results — without the calling code having
to know it's not talking to the real object directly.

Three common variants, all following the same shape (an object presenting
the same interface as the real thing, deciding what to do before/instead of
delegating to it):

- **Lazy-loading proxy** — defers expensive construction until first use.
- **Protection proxy** — checks permissions, then delegates or refuses.
- **Caching proxy** — caches results of expensive calls, delegates only on
  a cache miss.

```ruby
class RealImage
  def initialize(filename)
    @filename = filename
    load_from_disk   # expensive — only want this to happen when needed
  end

  def render
    puts "Rendering #{@filename}"
  end

  private

  def load_from_disk
    puts "Loading #{@filename} from disk (expensive)..."
  end
end

# Lazy-loading proxy: same interface as RealImage, defers the expensive
# construction until #render is actually called
class LazyImageProxy
  def initialize(filename)
    @filename = filename
    @real_image = nil
  end

  def render
    @real_image ||= RealImage.new(@filename)
    @real_image.render
  end
end

gallery = [
  LazyImageProxy.new("photo1.jpg"),
  LazyImageProxy.new("photo2.jpg")
]
# Nothing loaded yet — RealImage.new hasn't run for either

gallery.first.render
# NOW "photo1.jpg" loads from disk, and only photo1
```

### When NOT to use this

If constructing/accessing the real object is already cheap, or there's no
actual access-control or caching need, a proxy is pure indirection with no
payoff. Also don't reach for a hand-rolled proxy when the language or
framework already gives you the behavior for free (e.g., Rails' lazy
association loading, memoization via `||=` inline where a whole proxy class
would be overkill for a one-off case).

## Composite

**Problem it solves:** you have a tree of objects — some are leaves,
some are containers of other objects (which may themselves be leaves or
containers) — and you want calling code to treat individual objects and
whole subtrees through the exact same interface, without special-casing
"is this a leaf or a branch" everywhere.

```ruby
class FileSystemEntry
  def size
    raise NotImplementedError
  end
end

class File < FileSystemEntry
  def initialize(name, size)
    @name = name
    @size = size
  end

  def size = @size
end

class Directory < FileSystemEntry
  def initialize(name)
    @name = name
    @children = []
  end

  def add(entry)
    @children << entry
    self
  end

  # Recursively sums children's sizes — doesn't care whether each child
  # is a File or another Directory, both respond to #size
  def size
    @children.sum(&:size)
  end
end

root = Directory.new("root")
docs = Directory.new("docs")
docs.add(File.new("resume.pdf", 200))
docs.add(File.new("cover_letter.pdf", 50))

root.add(docs)
root.add(File.new("readme.txt", 10))

root.size   # => 260 (200 + 50 + 10, recursively, uniformly)
```

The calling code (`root.size`) never needs to know how deep the tree is or
which nodes are files vs. directories — that's the entire point.

### When NOT to use this

If the structure isn't genuinely recursive/tree-shaped (no "a container of
these can itself contain more of these" relationship), Composite is the
wrong tool — a plain collection or a couple of distinct classes will be
clearer. Forcing a flat, fixed-depth structure (e.g., "an Order has Items,
full stop, no nesting") into a Composite shape adds recursive-traversal
complexity for a problem that doesn't need it.

## Quick Recall — Self-Test

1. **What's the key difference between Adapter and Decorator? They both
   "wrap" another object.**
   Adapter changes an object's *interface* to match what callers expect,
   without adding new behavior — it's a translation layer. Decorator keeps
   the same interface but *adds* behavior/responsibility on top, and is
   meant to be stacked in combinations.

2. **Why is inheritance a worse fit than Decorator for "a coffee with any
   combination of milk, sugar, and whip"?**
   Inheritance would need a subclass for every combination
   (`MilkSugarCoffee`, `MilkWhipCoffee`, `MilkSugarWhipCoffee`, ...) fixed
   at compile-time. Decorator composes the combination at runtime by
   wrapping objects, with no combinatorial explosion of classes.

3. **When does a Facade turn into an anti-pattern?**
   When it stops just orchestrating calls to subsystems and starts
   accumulating actual business logic itself — at that point it's become a
   god object, and that logic should move into the subsystems or a
   dedicated service.

4. **Name the three common Proxy variants and what each one guards.**
   Lazy-loading proxy (defers expensive object creation until first real
   use), protection proxy (checks permissions before delegating), and
   caching proxy (caches results of expensive calls, delegates only on a
   miss).

5. **Why does Composite require every node — leaf and container alike —
   to implement the same interface?**
   Because the whole point is that calling code (e.g., `root.size`)
   doesn't special-case "is this a File or a Directory" — it just calls
   the shared method, and a container's implementation recursively calls
   the same method on its children, whatever type each one is.

6. **Give a concrete example of when NOT to use Adapter.**
   When you control both sides of an interface mismatch directly — e.g.,
   two classes in your own codebase that could just be made consistent
   with each other instead of introducing a translation layer between
   them.

7. **In the parking lot design, if you needed to integrate a third-party
   "SmartGate" barrier system with its own incompatible API for
   detecting vehicle entry, which structural pattern fits, and why?**
   Adapter — wrap `SmartGateClient`'s incompatible methods behind an
   interface your `ParkingLot` code already expects (e.g., a
   `VehicleDetector#detect_entry` method), so `ParkingLot` never depends
   on SmartGate's actual API directly.

8. **Why might a caching proxy be a bad idea for a payment-charging call?**
   Payment charges are not idempotent/side-effect-free reads — caching and
   replaying a "charge" call could double-charge a customer. Caching
   proxies belong in front of expensive *read* operations whose results
   are safe to reuse, not operations with side effects.

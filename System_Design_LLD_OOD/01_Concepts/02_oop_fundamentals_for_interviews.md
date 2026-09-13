# OOP Fundamentals for Interviews

## Why it matters

Every Ruby developer has used classes, `attr_accessor`, `include`, and
inheritance thousands of times without necessarily naming *why* those tools
exist or what specific problem each one solves. That's fine for day-to-day
work — it stops being fine in an LLD interview, where the interviewer is
explicitly evaluating whether you understand the *purpose* behind the
syntax. A candidate who writes a working class but can't say "this is
polymorphism, and it's why I don't need a `case` statement here" is
demonstrating pattern-matching, not understanding — and interviewers probe
specifically to tell the difference, usually by asking "why did you do it
this way?" immediately after you write something.

The real failure mode: without these concepts internalized, every design
problem gets solved the same way — one class, a handful of instance
variables, and a growing pile of conditional branches (`if type == :van`,
`case status when :pending`) sprinkled through every method. It works, it
compiles, and it fails the interview, because it doesn't extend cleanly and
it doesn't demonstrate object-oriented thinking. This file covers the four
pillars, composition vs. inheritance, and how Ruby specifically expresses
interfaces and abstraction — the vocabulary and code patterns that turn "a
class with some methods" into a design an interviewer recognizes as OOP.

## The Four Pillars

### 1. Encapsulation

**Definition:** hiding an object's internal state and exposing only a
controlled, intentional interface for interacting with it. The object
decides what can be read, what can be changed, and under what conditions —
callers never reach in and mutate internals directly.

**Before (no encapsulation — internal state is public and unprotected):**

```ruby
class BankAccount
  attr_accessor :balance

  def initialize(balance)
    @balance = balance
  end
end

account = BankAccount.new(100)
account.balance = -500   # nothing stops this; balance is just a public number
```

Any caller anywhere can set `balance` to anything, including a negative
number, bypassing any notion of "withdrawals can't exceed the balance."
There's no single place that enforces the account's rules because there's
no boundary around its state.

**After (encapsulated — state is private, changes go through methods that
enforce invariants):**

```ruby
class BankAccount
  def initialize(balance)
    @balance = balance
  end

  def balance
    @balance
  end

  def deposit(amount)
    raise ArgumentError, "amount must be positive" unless amount.positive?
    @balance += amount
  end

  def withdraw(amount)
    raise ArgumentError, "amount must be positive" unless amount.positive?
    raise "insufficient funds" if amount > @balance
    @balance -= amount
  end
end

account = BankAccount.new(100)
account.withdraw(500)   # raises "insufficient funds" instead of corrupting state
```

Now there is exactly one place (`withdraw`) where the "can't overdraw" rule
lives. Every caller goes through it. This is the core value of
encapsulation: it turns "every caller must remember the rules" into "the
object enforces its own rules," which is what makes a codebase safe to
extend without re-auditing every call site.

### 2. Abstraction

**Definition:** exposing *what* an object does without exposing *how* it
does it. Callers depend on a stable, simple interface; the implementation
behind that interface can change freely as long as the interface's contract
holds.

```ruby
class ReportGenerator
  def generate(data)
    raise NotImplementedError, "#{self.class} must implement generate"
  end
end

class PdfReportGenerator < ReportGenerator
  def generate(data)
    # ... builds a PDF, using whatever PDF library, layout logic, etc.
    "PDF report with #{data.size} rows"
  end
end

class CsvReportGenerator < ReportGenerator
  def generate(data)
    data.map { |row| row.join(",") }.join("\n")
  end
end

def export_report(generator, data)
  generator.generate(data)   # caller has no idea, and doesn't need to know, HOW
end

export_report(PdfReportGenerator.new, [[1, 2], [3, 4]])
export_report(CsvReportGenerator.new, [[1, 2], [3, 4]])
```

`export_report` depends only on the fact that `generator` responds to
`generate(data)`. It doesn't know or care whether that means building a PDF
byte stream or joining strings with commas. This is what lets you swap
`PdfReportGenerator` for `CsvReportGenerator` — or add a third format later
— with zero changes to `export_report`. Abstraction is the base-class (or
module) side of the coin; polymorphism, below, is the caller-side payoff.

### 3. Inheritance

**Definition:** an **is-a** relationship where a subclass inherits the
attributes and behavior of a parent class and can override or extend parts
of it. Use it when the subclass really is a more specific version of the
parent, not merely something that happens to share some code with it.

```ruby
class Employee
  attr_reader :name, :base_salary

  def initialize(name, base_salary)
    @name = name
    @base_salary = base_salary
  end

  def annual_salary
    base_salary * 12
  end
end

class SalesEmployee < Employee
  def initialize(name, base_salary, commission)
    super(name, base_salary)
    @commission = commission
  end

  def annual_salary
    super + @commission
  end
end
```

```text
        Employee
        - name
        - base_salary
        + annual_salary()
            ^
            |
      SalesEmployee
      - commission
      + annual_salary()   (overrides, calls super)
```

A `SalesEmployee` **is an** `Employee` — every `Employee` method and
attribute applies to it, plus its own. That "is-a" test is the guardrail:
if you catch yourself inheriting from a class just to reuse a method,
without the is-a relationship actually holding, that's a sign you want
composition instead (see below).

### 4. Polymorphism

**Definition:** the same method call behaves differently depending on the
actual (runtime) class of the object it's called on. This is the single
most interview-relevant pillar, because it's the direct, concrete
replacement for `case type when :x ... when :y ...` chains — and an
interviewer watching you write one of those chains is watching you miss the
point of the exercise.

**Before (type-checking chain — the pattern interviewers are watching for):**

```ruby
def calculate_area(shape)
  case shape[:type]
  when :circle
    Math::PI * shape[:radius]**2
  when :rectangle
    shape[:width] * shape[:height]
  when :triangle
    0.5 * shape[:base] * shape[:height]
  else
    raise "unknown shape type"
  end
end
```

Every new shape means editing this method (and every other method that
branches on `:type`). The logic for "how a circle computes its area" lives
far away from anything called `Circle`, scattered across whichever methods
happen to have a `case` for it.

**After (polymorphism — each object answers for itself):**

```ruby
class Shape
  def area
    raise NotImplementedError, "#{self.class} must implement area"
  end
end

class Circle < Shape
  def initialize(radius) = @radius = radius
  def area = Math::PI * @radius**2
end

class Rectangle < Shape
  def initialize(width, height) = (@width, @height = width, height)
  def area = @width * @height
end

class Triangle < Shape
  def initialize(base, height) = (@base, @height = base, height)
  def area = 0.5 * @base * @height
end

shapes = [Circle.new(2), Rectangle.new(3, 4), Triangle.new(5, 6)]
shapes.map(&:area)   # => calls the correct area for each, no branching anywhere
```

`shapes.map(&:area)` works identically no matter what's in the array, and
adding `Square < Shape` requires touching nothing but a new class. This is
exactly the mechanism the parking lot example
(`LLD_OOD/02_Interview_Questions/01_parking_lot.md`) uses for
`Vehicle#spots_required`: instead of `ParkingLot` knowing "vans need 3 bike
spots," each `Vehicle` subclass answers `spots_required(spot_type)` for
itself, and `ParkingLot` just asks the question. That single design choice
is usually the clearest signal in the whole exercise that a candidate
understands OOP versus writing procedural code with class syntax on top.

## Composition vs. Inheritance

**The principle:** favor composition over inheritance. Composition means
building an object out of other objects (it *has-a* collaborator) rather
than extending a parent class (*is-a* the parent). Prefer composition when
the relationship isn't a true "is-a," or when you need to mix and match
behaviors flexibly.

**Why inheritance can go wrong:** it creates tight coupling to a parent's
*implementation*, not just its interface — a subclass can be broken by a
change to the parent it never touched. Deep hierarchies compound this: by
the third or fourth level, it's unclear which ancestor a given method
actually comes from, and a change anywhere in the chain risks breaking
every descendant. It also forces a single-axis classification — if a
`Duck` needs to be both "a bird" and "something that can swim," and
`Penguin` needs to be "a bird" but explicitly *not* swim like a duck,
inheritance alone can't cleanly express that combination.

**Before (a hierarchy that gets awkward as new combinations appear):**

```ruby
class Bird
  def fly = "flying"
end

class Duck < Bird
  def swim = "swimming"
end

class Penguin < Bird
  # Penguins can't fly - now we have to override fly to raise/no-op,
  # which means Penguin "is a" Bird but violates the Bird contract.
  def fly
    raise NotImplementedError, "penguins can't fly"
  end
end
```

Every new bird with a different combination of abilities (flies but
doesn't swim, swims but doesn't fly, does neither, does both) either forces
an override that violates the parent's contract or forces yet another
layer of subclassing (`FlightlessBird`, `SwimmingBird`,
`FlightlessSwimmingBird`...) that grows combinatorially.

**After (composed from small, independent, swappable behaviors):**

```ruby
module CanFly
  def fly = "flying"
end

module CanSwim
  def swim = "swimming"
end

class Bird
  def initialize(name) = @name = name
end

class Duck < Bird
  include CanFly
  include CanSwim
end

class Penguin < Bird
  include CanSwim   # simply doesn't include CanFly - no contract violation
end
```

Now abilities are independent modules mixed in per class, and no class is
ever forced to implement (or explicitly reject) a behavior it doesn't have.
This is composition via Ruby modules: `Duck` and `Penguin` are each
assembled from the pieces they actually need, and a new bird with a new
combination of abilities is just a new class including the right modules —
no hierarchy redesign required. The same idea applies to composing whole
objects, not just modules: a `Car` can be composed of an `Engine` object
and a `GPS` object (`@engine = Engine.new`, `@gps = GPS.new`) rather than
inheriting from an `EngineBehavior` base class — the engine can be swapped
for an `ElectricEngine` at runtime without touching `Car`'s class
hierarchy at all.

## Interfaces in Ruby (Duck Typing and Modules)

Ruby has no `interface` keyword like Java or C#. It achieves interface-like
contracts two ways:

**1. Duck typing:** "if it walks like a duck and quacks like a duck, it's a
duck" — any object that responds to the right method(s) can be used
polymorphically, regardless of its class or ancestry. No formal declaration
of "implements this interface" is required.

```ruby
class EmailSender
  def send(message) = puts "Emailing: #{message}"
end

class SmsSender
  def send(message) = puts "Texting: #{message}"
end

def notify(sender, message)
  sender.send(message)   # works with ANY object that responds to #send
end

notify(EmailSender.new, "hello")
notify(SmsSender.new, "hello")
```

`notify` never checks the class of `sender` — it just calls `send`. Any
object with a compatible `send` method works, including one from a test
double or a third-party library, with no shared ancestry required.

**2. Modules/mixins for shared behavior:** `include` brings a module's
methods into a class as if they were defined there, letting unrelated
classes share behavior without inheriting from a common (and potentially
awkward) parent — this is how Ruby's standard library gives you
`Comparable` (implement `<=>`, get `<`, `>`, `between?` for free) and
`Enumerable` (implement `each`, get `map`, `select`, `reduce` for free).

**3. `raise NotImplementedError` as an enforced contract:** since Ruby
won't stop you at compile time from instantiating an "abstract" class or
skipping a method, the idiomatic convention is a base class method that
immediately raises, forcing subclasses to override it before they're
usable. This is exactly the pattern in the parking lot example's
`Vehicle#spots_required`:

```ruby
class Vehicle
  def spots_required(spot_type)
    raise NotImplementedError, "#{self.class} must implement spots_required"
  end
end
```

Any subclass that forgets to implement `spots_required` will raise loudly
the first time it's called — not silently do the wrong thing. This is
Ruby's closest equivalent to a Java `abstract` method: not enforced by the
language at class-definition time, but enforced at call time, which is
enough to make the contract explicit and catch violations immediately.

## Abstract Classes in Ruby

Ruby also has no `abstract` keyword for classes. The convention is the same
`raise NotImplementedError` pattern, applied to a base class that is never
meant to be instantiated directly (only its subclasses are):

```ruby
class PaymentMethod
  def process(amount)
    raise NotImplementedError, "#{self.class} must implement process"
  end
end

class CreditCardPayment < PaymentMethod
  def process(amount) = "Charged $#{amount} to credit card"
end

class PayPalPayment < PaymentMethod
  def process(amount) = "Charged $#{amount} via PayPal"
end
```

Nothing stops a caller from writing `PaymentMethod.new.process(10)` — it
will simply raise `NotImplementedError` immediately, which is the intended
behavior: it signals "this class is a template, not a usable object,"
enforced the moment it's misused rather than by a compiler up front.

## Why interviewers care about polymorphism specifically

Of the four pillars, polymorphism is the one that most directly and
visibly separates a strong LLD answer from a weak one, because it shows up
as a structural difference in the code itself, not just a stylistic one.
Encapsulation, abstraction, and inheritance can all be present in code that
still has a `case vehicle_type` chain scattered through every method — that
code technically has classes and hides some state, but it hasn't actually
distributed responsibility to the right objects. The moment you see (or
write) a `case`/`if` chain that branches on an object's *type* to decide
what to do, that's the signal: the logic belongs inside the type-specific
object, not outside it, as a method each subclass implements differently.
Interviewers listen for this specifically because it's the fastest tell of
whether a candidate reaches for "does this object know how to answer this
itself?" as a reflex — which is precisely what the parking lot interview
in this repo was testing when it planted the van/bike-spot rule.

## Interview Tips

- When you catch yourself writing `case obj.type` or `if obj.is_a?(X)`
  inside a shared method, stop and ask: "should the object itself answer
  this?" Converting that branch into a polymorphic method call is usually
  the single highest-value edit you can make live in an interview.
- Say the pillar names out loud as you design: "I'm making `balance`
  private and only mutable through `deposit`/`withdraw` — that's
  encapsulation, so no caller can put the account into an invalid state."
  Narrating your reasoning is often worth as much as the code itself.
- When asked "how would you make this extensible," the answer is almost
  always some combination of "polymorphism instead of branching" and
  "composition instead of a rigid inheritance chain" — have both ready as
  concrete moves, not just words.
- If you inherit from a class purely to reuse a method, and the "is-a"
  relationship feels forced, say so and switch to composition or a shared
  module. Interviewers notice when a candidate defaults to inheritance out
  of habit rather than because it's the right relationship.
- Expect a direct follow-up: "how would Ruby express this without a formal
  interface keyword?" Have the duck-typing and `NotImplementedError`
  answers ready — this is a very common LLD-in-Ruby specific question.

## Quick Recall — Self-Test

1. **What problem does encapsulation solve that a plain class with
   `attr_accessor` on every field does not?**
   It prevents callers from putting an object into an invalid state by
   mutating internals directly (e.g., setting a bank balance to a negative
   number). Encapsulation funnels all state changes through methods that
   can enforce the object's own rules, so the rules live in one place.

2. **Give the definition of polymorphism, and explain why it's considered
   the most interview-relevant pillar.**
   Polymorphism is the same method call producing different behavior
   depending on the runtime class of the object it's called on. It's the
   most interview-relevant pillar because it directly replaces `case
   type`/`if is_a?` chains with each object answering for itself, and
   interviewers watch specifically for whether a candidate reaches for this
   instead of branching on type.

3. **Why does Ruby have no `interface` keyword, and what two mechanisms
   replace it?**
   Ruby is dynamically typed and doesn't enforce method contracts at
   compile time, so it has no formal interface construct. It replaces
   interfaces with duck typing (any object responding to the right methods
   can be used polymorphically) and modules/mixins (shared behavior via
   `include`, often paired with `raise NotImplementedError` in a base
   method to enforce "subclasses must implement this").

4. **What is the "is-a" test, and how do you use it to decide between
   inheritance and composition?**
   The is-a test asks whether the subclass is genuinely a more specific
   version of the parent (a `SalesEmployee` is an `Employee`). If the
   relationship doesn't hold — you're inheriting only to reuse a method, or
   the child needs to reject part of the parent's contract (like a penguin
   overriding `fly` to raise) — use composition (mix in a module, or hold a
   collaborator object) instead.

5. **Explain the `raise NotImplementedError` pattern and what real-world
   problem it prevents.**
   It's placed in a base class method that subclasses are expected to
   override; if a subclass forgets, calling that method raises immediately
   and loudly rather than silently doing nothing or returning `nil`. It's
   Ruby's idiomatic stand-in for both `abstract` classes/methods and
   enforced interface contracts, since the language provides neither
   natively.

6. **What specifically goes wrong with a deep inheritance hierarchy as new
   combinations of behavior are needed (e.g., birds that fly, swim, both,
   or neither)?**
   Inheritance is single-axis: modeling every combination forces either
   contract-violating overrides (a `Penguin < Bird` that overrides `fly` to
   raise) or a combinatorial explosion of subclasses
   (`FlightlessSwimmingBird`, etc.). Composition avoids this by mixing in
   only the behaviors (modules) a given class actually needs.

7. **In the parking lot example, what specifically makes
   `Vehicle#spots_required` an example of polymorphism rather than just
   "using classes"?**
   Each `Vehicle` subclass (`Bike`, `Car`, `Van`) implements
   `spots_required(spot_type)` differently, and `ParkingLot` calls
   `vehicle.spots_required(spot_type)` without ever checking which
   subclass it has — the same call produces different behavior per actual
   object, and no branching on vehicle type exists outside the vehicle
   classes themselves.

8. **What is abstraction, and how does it differ from encapsulation? Give
   an example distinguishing the two.**
   Abstraction exposes *what* an object does without exposing *how*
   (e.g., callers know `generator.generate(data)` produces a report, not
   how a PDF is assembled internally). Encapsulation hides internal *state*
   and controls how it's mutated (e.g., `balance` can only change through
   `deposit`/`withdraw`). Abstraction is about hiding implementation
   behind a behavioral contract; encapsulation is about hiding and
   protecting data.

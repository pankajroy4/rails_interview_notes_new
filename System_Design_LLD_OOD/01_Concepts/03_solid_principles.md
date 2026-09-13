# SOLID Principles

SOLID is an acronym for five object-oriented design principles, coined by
Robert C. Martin, that describe how to structure classes so a codebase
stays flexible and maintainable as it grows. Each letter names one
principle: **S**ingle Responsibility, **O**pen/Closed, **L**iskov
Substitution, **I**nterface Segregation, **D**ependency Inversion. None of
these is a Ruby-specific rule — they're language-agnostic OOP design
principles — but this file shows each one with idiomatic Ruby.

## Why it matters

SOLID violations are exactly the kind of thing that starts as "this is
fine, I'll clean it up later" and compounds into code nobody wants to
touch. A class that does five things is fine until you need to change one
of those five things and discover you can't do it without risking the
other four. A `case` statement is fine until the 6th type is added by
someone who didn't know about the other 5 places a similar `case` exists.
None of these problems are visible in a toy example with one or two types
— they become obvious exactly when a system grows, which is precisely the
moment an interviewer simulates by asking "now add a new payment type" or
"now support a new vehicle" right after your first pass at a design.

In an interview, SOLID gives you a **vocabulary** for justifying design
decisions instead of just having good instincts. "I split this into three
classes because each one has a single reason to change" is a far stronger
answer than "I just thought it looked cleaner." Being able to name which
principle a design choice serves is itself a signal the interviewer is
listening for — it shows the decision was deliberate, not accidental.

## S — Single Responsibility Principle (SRP)

**Definition:** a class should have one reason to change — one
responsibility, owned entirely by that class.

**Before (violates SRP — one class does validation, persistence, and
notification):**

```ruby
class UserRegistrar
  def register(params)
    # 1. Validation
    raise "invalid email" unless params[:email] =~ /\A[\w+\-.]+@[a-z\d\-]+\.[a-z]+\z/i
    raise "password too short" if params[:password].length < 8

    # 2. Persistence
    user = User.create!(email: params[:email], password_digest: BCrypt::Password.create(params[:password]))

    # 3. Notification
    EmailClient.new.send_mail(
      to: user.email,
      subject: "Welcome!",
      body: "Thanks for signing up, #{user.email}"
    )

    user
  end
end
```

This is exactly the kind of code that gets written under time pressure —
it's not a strawman, it's a Tuesday. It works. The problem shows up later:
a change to validation rules, a change to how users are persisted (maybe a
second data store), and a change to the welcome email template all now
require editing the same class, and a bug in any one of those concerns
risks breaking the others (a typo in the email step after the user is
already saved leaves the system in a half-done state with no clear owner
of "did registration actually succeed?").

**After (split by responsibility):**

```ruby
class UserValidator
  def validate!(params)
    raise "invalid email" unless params[:email] =~ /\A[\w+\-.]+@[a-z\d\-]+\.[a-z]+\z/i
    raise "password too short" if params[:password].length < 8
  end
end

class UserRepository
  def create(params)
    User.create!(email: params[:email], password_digest: BCrypt::Password.create(params[:password]))
  end
end

class WelcomeNotifier
  def notify(user)
    EmailClient.new.send_mail(to: user.email, subject: "Welcome!", body: "Thanks for signing up, #{user.email}")
  end
end

class UserRegistrar
  def initialize(validator: UserValidator.new, repository: UserRepository.new, notifier: WelcomeNotifier.new)
    @validator = validator
    @repository = repository
    @notifier = notifier
  end

  def register(params)
    @validator.validate!(params)
    user = @repository.create(params)
    @notifier.notify(user)
    user
  end
end
```

Now each class can change for exactly one reason: validation rules change
`UserValidator` only, switching data stores changes `UserRepository` only,
changing the email template changes `WelcomeNotifier` only. This matters
in practice because it shrinks the blast radius of every change — a
developer editing password rules can't accidentally break persistence, and
each class can be unit tested in isolation instead of requiring a full
integration test for every small change.

## O — Open/Closed Principle (OCP)

**Definition:** classes should be open for extension but closed for
modification — you should be able to add new behavior without editing
existing, already-working code.

**Before (violates OCP — a shared method must be edited for every new
type):**

```ruby
class ParkingLot
  def spots_needed(vehicle_type, spot_type)
    case vehicle_type
    when :bike
      spot_type == :bike_spot ? 1 : Float::INFINITY
    when :car
      spot_type == :car_spot ? 1 : Float::INFINITY
    when :van
      case spot_type
      when :van_spot then 1
      when :bike_spot then 3
      else Float::INFINITY
      end
    else
      raise "unknown vehicle type"
    end
  end
end
```

Adding a `Truck` means opening `ParkingLot` and editing this method (and
likely every other method with a similar `case`). Every edit to an
already-shipped, already-tested class carries risk of breaking existing
cases — and code review has to re-verify the whole method, not just the
new branch.

**After (polymorphic dispatch — this is exactly the parking lot example's
`Vehicle` hierarchy):**

```ruby
class Vehicle
  def spots_required(spot_type)
    raise NotImplementedError
  end
end

class Bike < Vehicle
  def spots_required(spot_type) = spot_type == :bike_spot ? 1 : Float::INFINITY
end

class Car < Vehicle
  def spots_required(spot_type) = spot_type == :car_spot ? 1 : Float::INFINITY
end

class Van < Vehicle
  def spots_required(spot_type)
    case spot_type
    when :van_spot then 1
    when :bike_spot then 3
    else Float::INFINITY
    end
  end
end

# Adding Truck requires zero changes to ParkingLot or any existing Vehicle class:
class Truck < Vehicle
  def spots_required(spot_type) = spot_type == :car_spot ? 2 : Float::INFINITY
end
```

`ParkingLot` calls `vehicle.spots_required(spot_type)` and never branches
on vehicle type at all — see `LLD_OOD/02_Interview_Questions/01_parking_lot.md`
for the full `ParkingLot#park` implementation built on exactly this. Adding
`Truck` is a new class, not an edit to a working one. This matters because
"new class, zero edits to existing code" means the existing, already-tested
code paths cannot regress — there's nothing to re-test except the new
class itself.

## L — Liskov Substitution Principle (LSP)

**Definition:** a subclass must be usable anywhere its parent is expected,
without breaking the correctness the parent promised — a subclass should
never make the contract *stricter* or *different* than what callers of the
parent type already rely on.

**Before (the classic Square-extends-Rectangle violation):**

```ruby
class Rectangle
  attr_accessor :width, :height

  def initialize(width, height)
    @width = width
    @height = height
  end

  def area = width * height
end

class Square < Rectangle
  def width=(value)
    @width = value
    @height = value   # keeps it "square" - but silently changes height too
  end

  def height=(value)
    @width = value
    @height = value
  end
end

def resize_and_check(rect)
  rect.width = 5
  rect.height = 10
  raise "broken!" unless rect.area == 50   # true for Rectangle, FALSE for Square
end

resize_and_check(Rectangle.new(2, 2))  # fine
resize_and_check(Square.new(2, 2))     # raises "broken!" - Square silently set both to 10, area = 100
```

`Square` is a `Rectangle` mathematically, but not behaviorally: any code
written against `Rectangle`'s contract ("setting `width` doesn't touch
`height`") silently breaks when handed a `Square`. This is worse than a
crash — `resize_and_check` doesn't error because of a missing method, it
errors because of a *wrong value* produced by code that looked completely
correct for `Rectangle`.

**After (restructure so the hierarchy doesn't lie about behavior):**

```ruby
class Shape
  def area
    raise NotImplementedError
  end
end

class Rectangle < Shape
  def initialize(width, height)
    @width = width
    @height = height
  end

  def area = @width * @height
end

class Square < Shape
  def initialize(side)
    @side = side
  end

  def area = @side * @side
end
```

`Square` no longer pretends to be a `Rectangle` with independently
settable `width`/`height` — it's its own `Shape` with its own contract (one
`side`, no separate width/height to desynchronize). Any code written
against `Shape` only relies on `area`, which both honor correctly. The
practical lesson: if making B a subclass of A forces B to override a
method in a way that changes A's promised behavior, B is not really an A —
model it as a sibling instead.

## I — Interface Segregation Principle (ISP)

**Definition:** don't force a class to implement methods it doesn't need —
prefer several small, focused interfaces (in Ruby: modules) over one large
one that bundles unrelated behavior.

**Before (a fat module forces an irrelevant method on an implementer):**

```ruby
module Worker
  def work
    raise NotImplementedError
  end

  def eat
    raise NotImplementedError
  end
end

class HumanWorker
  include Worker
  def work = "assembling parts"
  def eat = "eating lunch"
end

class RobotWorker
  include Worker
  def work = "assembling parts, tirelessly"

  def eat
    raise "RobotWorker does not eat"   # forced to implement something meaningless for it
  end
end
```

`RobotWorker` is forced to define `eat` just to satisfy the `Worker`
module's shape, even though "eating" has no meaning for a robot. Worse,
any caller that trusts "every `Worker` responds meaningfully to `eat`"
(because the module promises it) will get a runtime crash specifically
from `RobotWorker`, which is a subtler version of the same problem LSP
describes: an implementer that technically satisfies the interface's
method list but not its behavioral contract.

**After (split into smaller, focused modules — implement only what
applies):**

```ruby
module Workable
  def work
    raise NotImplementedError
  end
end

module Eatable
  def eat
    raise NotImplementedError
  end
end

class HumanWorker
  include Workable
  include Eatable
  def work = "assembling parts"
  def eat = "eating lunch"
end

class RobotWorker
  include Workable
  def work = "assembling parts, tirelessly"
  # no eat method at all - and none is expected, since RobotWorker never included Eatable
end
```

Now nothing forces `RobotWorker` to define a meaningless `eat`, and any
caller that specifically needs "something that eats" asks for an `Eatable`
(`worker.is_a?(Eatable)` or, more idiomatically in Ruby, just calls `eat`
and lets duck typing sort it out) rather than assuming every `Workable` can
eat. This matters in practice because fat interfaces tend to accumulate
methods relevant to only some implementers over time, and every
implementer pays the cost of stubbing out or raising on methods it never
needed.

## D — Dependency Inversion Principle (DIP)

**Definition:** depend on abstractions, not concrete implementations —
high-level, business-logic classes shouldn't directly instantiate or call
specific low-level classes; instead, a dependency (matching some expected
contract) should be handed to them, so the concrete implementation can be
swapped without editing the high-level class.

**Before (violates DIP — hardcodes a concrete low-level class):**

```ruby
class EmailSender
  def send(message) = puts "Emailing: #{message}"
end

class NotificationService
  def initialize
    @sender = EmailSender.new   # hardcoded - NotificationService owns this decision
  end

  def notify(message)
    @sender.send(message)
  end
end
```

`NotificationService` (high-level: "notify someone") is directly coupled
to `EmailSender` (low-level: "how to actually send"). Switching to SMS, or
supporting both, means editing `NotificationService` itself — and unit
testing `NotificationService` in isolation means either really sending
emails or monkey-patching `EmailSender`, since there's no seam to inject a
test double.

**After (depend on an injected, duck-typed contract):**

```ruby
class EmailSender
  def send(message) = puts "Emailing: #{message}"
end

class SmsSender
  def send(message) = puts "Texting: #{message}"
end

class NotificationService
  def initialize(sender)
    @sender = sender   # any object responding to #send works
  end

  def notify(message)
    @sender.send(message)
  end
end

NotificationService.new(EmailSender.new).notify("hello")
NotificationService.new(SmsSender.new).notify("hello")
```

`NotificationService` now depends only on "something with a `send`
method" — the abstraction — not on `EmailSender` specifically. This is
dependency **injection** as the mechanism that achieves dependency
**inversion**: instead of the high-level class reaching down to construct
its own low-level dependency, the dependency is handed in from outside.
Concretely, this makes `NotificationService` trivially testable (inject a
fake sender that just records calls) and trivially extensible (add
`PushNotificationSender` with zero changes to `NotificationService`).

## Why LLD interviews specifically probe for SOLID

All five principles are the concrete, nameable things an interviewer
points at when they say "this design won't scale/extend well" — and being
able to name *which* principle a design choice serves is a strong signal
on its own, independent of the code. "I made `Vehicle` an abstract base
class with `spots_required` so adding a new vehicle type doesn't require
editing `ParkingLot` — that's Open/Closed" tells the interviewer you
designed it that way on purpose, versus arriving at similar-looking code
by accident. In practice, most LLD interview follow-ups ("now add a new
type," "how would you test this in isolation," "what if we need to swap
this implementation") are really just probes for whether one of these five
principles was respected. Walking in with the vocabulary means you can
anticipate and name the follow-up before it's asked.

## Interview Tips

- When you introduce a new class specifically to isolate a responsibility,
  say the letter out loud: "I'm pulling validation into its own class —
  that's Single Responsibility, so a change to validation rules can't
  accidentally affect persistence."
- Expect "now add a new type" as a direct test of Open/Closed. If your
  design requires editing an existing class's method body to add the new
  type, that's the tell you're missing polymorphism somewhere.
- If a subclass overrides a parent method in a way that surprises callers
  of the parent (changes return type, raises where the parent didn't,
  silently changes unrelated state), flag it yourself as a possible LSP
  violation before the interviewer does.
- ISP rarely gets its own dedicated question, but shows up as a follow-up
  to module/interface design: "does every implementer of this module
  actually need all these methods?" is worth asking yourself proactively.
- DIP is the principle most directly tied to testability — if asked "how
  would you test this without hitting a real database/API," the answer is
  almost always "inject the dependency so I can substitute a test double,"
  which is DIP in action.
- Don't force all five into every design. A five-line parking spot class
  doesn't need a DIP-style injected collaborator. Apply each principle
  where it solves an actual problem the design has, and be ready to
  explain why you didn't need the others.

## Quick Recall — Self-Test

1. **State the Single Responsibility Principle in one sentence, and explain
   the concrete risk of violating it.**
   A class should have one reason to change. Violating it means unrelated
   concerns (e.g., validation, persistence, notification) share one class,
   so a change to any one concern risks breaking the others, and the class
   can't be tested or reasoned about in isolation.

2. **How does Open/Closed relate to polymorphism, using the parking lot
   example specifically?**
   Open/Closed is achieved through polymorphism: `Vehicle` subclasses each
   implement `spots_required`, so `ParkingLot` never branches on vehicle
   type. Adding a new vehicle type (e.g., `Truck`) means adding a new class
   — `ParkingLot` and existing `Vehicle` subclasses are never edited
   ("closed for modification, open for extension").

3. **Explain the Square-extends-Rectangle LSP violation: what specifically
   breaks, and why is it worse than a simple crash?**
   `Square` overrides `width=`/`height=` to keep both dimensions equal,
   which silently changes `height` when only `width` is set. Code written
   against `Rectangle`'s contract (setting width doesn't touch height)
   produces a wrong `area` value when given a `Square` — it's worse than a
   crash because the code runs without error and silently returns
   incorrect results.

4. **What does Interface Segregation warn against, and how is it different
   from Single Responsibility?**
   ISP warns against forcing an implementer to define methods it doesn't
   need, by making interfaces/modules too broad (a `Worker` module forcing
   `eat` on a `RobotWorker`). SRP is about a single class having only one
   reason to change; ISP is specifically about not bundling unrelated
   method contracts into one interface that all implementers must satisfy.

5. **What is Dependency Inversion, and what Ruby mechanism typically
   implements it?**
   DIP says high-level classes should depend on abstractions, not concrete
   low-level classes — e.g., a `NotificationService` should depend on
   "anything that responds to `send`," not `EmailSender` specifically.
   It's typically implemented via dependency injection: passing the
   collaborator object into the constructor rather than instantiating it
   inside the class.

6. **Why does DIP make unit testing easier? Give a concrete example.**
   Because the dependency is injected rather than hardcoded, a test can
   substitute a fake object (e.g., a test double that just records calls
   instead of really sending an email) without modifying the class under
   test. `NotificationService.new(fake_sender)` can be tested in complete
   isolation from any real email or SMS infrastructure.

7. **A candidate says "I split this into three classes because it looked
   cleaner." Why is that a weaker interview answer than naming a specific
   SOLID principle?**
   "Looked cleaner" is a vague, subjective justification that doesn't
   demonstrate deliberate design reasoning. Naming the principle ("I split
   this because each class should have a single reason to change — SRP")
   shows the decision was intentional and grounded in a recognized
   trade-off, which is what interviewers are specifically listening for.

8. **How do Open/Closed and Liskov Substitution interact? Can a design
   satisfy Open/Closed while violating Liskov?**
   Yes — a design can be extensible (new subclasses added without editing
   existing code, satisfying OCP) while some of those subclasses still
   violate their parent's behavioral contract (violating LSP), such as a
   new `Vehicle` subclass whose `spots_required` returns a nonsensical or
   inconsistent value for a spot type in a way that silently breaks
   `ParkingLot#park`'s assumptions. Extensibility and behavioral
   correctness under substitution are separate concerns.

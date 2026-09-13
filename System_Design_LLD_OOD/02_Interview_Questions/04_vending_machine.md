# Design a Vending Machine (Object-Oriented Design)

## Problem Statement

"Design a vending machine. It holds an inventory of items, each with a
price. A user inserts coins, selects an item, and the machine either
dispenses the item and returns change, or rejects the selection if there's
insufficient money or the item is sold out. A user can also request a
refund before selecting an item."

This is the textbook interview question for the **State pattern**, on
purpose — the entire specification is "what happens when you do X depends
on what the machine is currently doing." Inserting a coin means something
different before vs. after an item is selected; a refund request means
something different while idle vs. mid-dispense. A candidate who writes
`insert_coin`, `select_item`, and `refund` as three methods each containing
a `case @state` is demonstrating they haven't recognized the pattern the
question is built around — even if the code technically produces correct
output for the happy path.

## Step 1: Clarify Requirements

**Functional Requirements**
- The machine holds an inventory: item code → product, price, remaining
  count.
- A user inserts coins, accumulating a balance.
- A user selects an item by code.
- If balance ≥ price and the item is in stock, the machine dispenses the
  item and returns change (balance − price).
- If balance < price, the selection is rejected (or simply not fulfilled
  until more money is inserted — pick one and be explicit about it).
- If the item is sold out, the selection is rejected regardless of
  balance.
- A user can request a refund of their inserted balance, but only before
  an item has started dispensing.

**Non-Functional Requirements**
- **No `case @state` scattered across methods.** This is the requirement
  the question exists to test: `insert_coin`, `select_item`, `dispense`,
  and `refund` must each behave differently depending on machine state,
  and that behavior should live *in the state*, not as a conditional
  inside a monolithic `VendingMachine` class.
- **Single responsibility**: `VendingMachine` holds shared data
  (inventory, balance) and delegates every user action to its current
  state; it should not itself decide what's "allowed right now."
- **Extensibility**: adding a new state (e.g., `OutOfServiceState`) or a
  new machine-wide rule should be possible by adding/editing one state
  class, not by touching every existing method.
- **Correctness under sequencing**: money and inventory must never be lost
  or double-counted across a coin → select → dispense → change sequence,
  even when a step is rejected partway through.

## Step 2: Identify Core Objects / Entities

- **VendingMachineState** (abstract) → `IdleState`, `HasMoneyState`,
  `DispensingState`, `SoldOutState` — the behavior for each of
  `insert_coin`, `select_item`, `dispense`, and `refund` in that
  situation.
- **Inventory** — the machine's stock: a map of item code to `Product`,
  price, and remaining count; independent of what state the machine is in.
- **Product** — a simple value object: name and price (kept separate from
  `Inventory`'s count-tracking so "what an item is" and "how many are
  left" don't get conflated).
- **VendingMachine** — holds `current_state`, `balance`, and `inventory`;
  every public action delegates to `current_state`.

## Step 3: Identify Relationships (Class Diagram)

```text
  VendingMachineState (abstract)
  + insert_coin(machine, amount)   [abstract]
  + select_item(machine, code)     [abstract]
  + dispense(machine)              [abstract]
  + refund(machine)                [abstract]
       ^
       |________________________________________
       |              |                |          |
  IdleState    HasMoneyState    DispensingState   SoldOutState

  Product
  - name, price

  Inventory
  - slots: { code => { product: Product, count: Integer } }   (composition)
  + in_stock?(code) / price_of(code) / decrement(code)

  VendingMachine
  - state -----------------> VendingMachineState   (composition, current state)
  - balance: Money
  - inventory --------------> Inventory             (composition)
  - selected_code
  + insert_coin(amount)
  + select_item(code)
  + dispense()
  + refund()
```

Relationship types:
- `IdleState`/`HasMoneyState`/`DispensingState`/`SoldOutState` **inherit**
  from `VendingMachineState` (is-a) — same interface, different behavior
  per method.
- `VendingMachine` **composes** its `current_state`, its `Inventory`, and
  implicitly every `Product` in stock — none of them exist independently
  of the machine.
- `Inventory` **associates** each item code with a `Product` — the product
  catalog and the count-per-slot are related but distinct concerns kept in
  one composed object for convenience.

## Step 4: Design Decisions & Patterns Used

**Why State, and why it beats the naive conditional version.** Picture the
naive `insert_coin`:

```ruby
def insert_coin(amount)
  if @state == :dispensing
    reject_coin(amount) # or refuse silently — easy to get wrong
  elsif @state == :sold_out
    reject_coin(amount)
  else
    @balance += amount
    @state = :has_money
  end
end
```

Now imagine `select_item`, `dispense`, and `refund` each needing their own
version of this same four-way branch. Every new state (say, adding
`MaintenanceState`) means revisiting *all four* methods to add a branch,
and it's easy to forget one — the classic way these systems grow bugs.
With the State pattern, each state class implements all four methods for
*its own* situation only; `VendingMachine`'s methods become one-line
delegations (`@state.insert_coin(self, amount)`), and adding a state means
writing one new class. The interface (`insert_coin`, `select_item`,
`dispense`, `refund`) is fixed; only what each state *does* with it varies
— that's precisely what "state pattern" means.

**The design decision this problem forces you to make explicit: what does
`insert_coin` do during `DispensingState`?** The spec doesn't say, and a
strong candidate calls this out rather than guessing silently. Two
reasonable answers: (a) reject the coin outright (return it via the coin
return, don't add to balance) because the machine is mid-transaction and
shouldn't accept more input, or (b) accept it and just add to balance for
the *next* purchase. This file picks (a) — `DispensingState#insert_coin`
rejects — because it keeps "money currently on the machine" unambiguous
during a dispense in progress; state it out loud in an interview even if
you pick (b) instead.

**Why `Inventory` is a separate object from `VendingMachine`, not just a
hash on the machine.** Stock rules (is this in stock, decrement on
dispense) are logic, not just data — keeping them on `Inventory` means
`SoldOutState` transitions and stock checks go through one method
(`in_stock?`) instead of every state reaching into `@machine.slots[code][:count]`
directly. It also means swapping in a smarter inventory (e.g., one that
tracks expiry dates) doesn't touch any state class.

## Step 5: Code

```ruby
Product = Struct.new(:name, :price)

class Inventory
  def initialize
    @slots = {} # code => { product:, count: }
  end

  def stock(code, product, count)
    @slots[code] = { product: product, count: count }
  end

  def in_stock?(code) = @slots.key?(code) && @slots[code][:count].positive?
  def price_of(code) = @slots.fetch(code)[:product].price
  def product_at(code) = @slots.fetch(code)[:product]

  def decrement(code)
    @slots[code][:count] -= 1
  end
end

# --- States -----------------------------------------------------------

class VendingMachineState
  def insert_coin(machine, amount)
    raise NotImplementedError
  end

  def select_item(machine, code)
    raise NotImplementedError
  end

  def dispense(machine)
    raise NotImplementedError
  end

  def refund(machine)
    raise NotImplementedError
  end
end

class IdleState < VendingMachineState
  def insert_coin(machine, amount)
    machine.balance += amount
    machine.state = HasMoneyState.new
  end

  def select_item(machine, code)
    puts "Insert coins first."
  end

  def dispense(machine)
    puts "Nothing selected."
  end

  def refund(machine)
    puts "No balance to refund."
  end
end

class HasMoneyState < VendingMachineState
  def insert_coin(machine, amount)
    machine.balance += amount # accumulate more before selecting
  end

  def select_item(machine, code)
    unless machine.inventory.in_stock?(code)
      machine.state = SoldOutState.new(code)
      return
    end

    price = machine.inventory.price_of(code)
    if machine.balance < price
      puts "Insufficient funds: need #{price - machine.balance} more."
      return
    end

    machine.selected_code = code
    machine.state = DispensingState.new
    machine.dispense
  end

  def dispense(machine)
    puts "Select an item first."
  end

  def refund(machine)
    returned = machine.balance
    machine.balance = 0
    machine.state = IdleState.new
    puts "Refunded #{returned}."
  end
end

class DispensingState < VendingMachineState
  def insert_coin(machine, amount)
    # Design decision (stated explicitly, see Step 4): reject new coins
    # while a dispense is already in progress rather than silently adding
    # to balance.
    puts "Machine busy dispensing — coin returned."
  end

  def select_item(machine, code)
    puts "Already dispensing an item."
  end

  def dispense(machine)
    code = machine.selected_code
    price = machine.inventory.price_of(code)
    change = machine.balance - price

    machine.inventory.decrement(code)
    machine.balance = 0
    machine.selected_code = nil

    puts "Dispensing #{machine.inventory.product_at(code).name}."
    puts "Returning change: #{change}." if change.positive?

    machine.state = IdleState.new
  end

  def refund(machine)
    puts "Cannot refund mid-dispense."
  end
end

class SoldOutState < VendingMachineState
  def initialize(attempted_code)
    @attempted_code = attempted_code
  end

  def insert_coin(machine, amount)
    machine.balance += amount
    machine.state = HasMoneyState.new
  end

  def select_item(machine, code)
    puts "#{code} is sold out. Choose another item."
    machine.state = machine.balance.positive? ? HasMoneyState.new : IdleState.new
  end

  def dispense(machine)
    puts "Nothing to dispense."
  end

  def refund(machine)
    returned = machine.balance
    machine.balance = 0
    machine.state = IdleState.new
    puts "Refunded #{returned}."
  end
end

# --- Vending machine ----------------------------------------------------

class VendingMachine
  attr_accessor :state, :balance, :selected_code
  attr_reader :inventory

  def initialize(inventory)
    @inventory = inventory
    @state = IdleState.new
    @balance = 0
    @selected_code = nil
  end

  def insert_coin(amount) = @state.insert_coin(self, amount)
  def select_item(code)   = @state.select_item(self, code)
  def dispense             = @state.dispense(self)
  def refund               = @state.refund(self)
end
```

**Using it — a full worked transition sequence:**

```ruby
inventory = Inventory.new
inventory.stock("A1", Product.new("Cola", 150), 3)
inventory.stock("B2", Product.new("Chips", 200), 0) # sold out from the start

machine = VendingMachine.new(inventory)

machine.state.class            # => IdleState

machine.insert_coin(100)
machine.state.class            # => HasMoneyState
machine.insert_coin(100)
machine.balance                # => 200

machine.select_item("A1")
# => "Dispensing Cola."
# => "Returning change: 50."
machine.state.class            # => IdleState (dispense() transitions back)
machine.balance                # => 0

machine.select_item("B2")      # nothing inserted this time
# => "Insert coins first."     (IdleState#select_item)

machine.insert_coin(200)
machine.select_item("B2")
# => "B2 is sold out. Choose another item."
machine.state.class            # => HasMoneyState (balance kept for a retry)

machine.refund
# => "Refunded 200."
machine.state.class            # => IdleState
```

## Step 6: Edge Cases & Extensibility

- **Inserting insufficient money.** `HasMoneyState#select_item` checks
  `balance < price` and rejects without changing state, so the user's
  balance is preserved and they can add more coins — this is exactly why
  `insert_coin` must remain accepted in `HasMoneyState` (it wouldn't make
  sense to force a refund just because the first coin wasn't enough).
- **Selecting a sold-out item.** Handled by `SoldOutState`, which is
  reached instead of transitioning to `DispensingState` — critically, the
  user's balance is *not* lost; `SoldOutState` routes back to
  `HasMoneyState` (if they still have balance) so they can pick something
  else, rather than silently keeping their money with no path forward.
- **Requesting a refund after selecting an item.** `DispensingState#refund`
  explicitly refuses — once dispensing has started, the transaction is
  committed. This boundary (selection vs. dispensing as separate states)
  is what makes "can I still refund" an unambiguous question instead of a
  timing-dependent race.
- **Exact-change-only situations.** Not modeled above but a very common
  follow-up: add an `exact_change_only?` check on the machine (based on
  available coin denominations for making change — see Follow-up 1) that
  `HasMoneyState#select_item` consults before allowing a purchase that
  would require change the machine can't produce.
- **Coin jam / mechanical failure.** Maps naturally to adding an
  `OutOfServiceState` that rejects every action except perhaps `refund` —
  exactly the extensibility case the State pattern is designed for: one
  new class, zero changes to existing states.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you support multiple denominations and calculate exact
   change?"** Track a `CashInventory` of denomination → count (like
   `Inventory` but for coins/notes the machine holds), and compute change
   with a greedy algorithm: sort denominations descending, take as many of
   the largest as available and needed, then move to the next-smallest,
   verifying the exact total can be made — if not, refuse the sale
   (`exact_change_only?`) rather than shortchange the customer. This
   mirors the ATM's `CashDispenser` denomination-breakdown logic almost
   exactly (see `05_atm_machine.md`).
2. **"How would you support card payment as an alternative to inserting
   coins?"** This is a **Strategy** pattern question, deliberately distinct
   from the State pattern already in play: payment *method* (coins vs.
   card) is a pluggable algorithm for "how do we collect money," while
   machine *state* (idle, has-money, dispensing) is about "what the
   machine is currently doing" regardless of how money arrived. Concretely,
   introduce a `PaymentMethod` interface (`CoinPayment`, `CardPayment`)
   that each state's `select_item`/purchase flow delegates to for
   collecting funds — the state machine's transitions stay identical
   either way.
3. **"What if two items have the same price but different stock
   counts?"** No special handling needed — `Inventory` already tracks
   count per code independently; this is really testing whether you
   conflated `Product` (price/name) with per-slot stock count, which the
   design already avoids.
4. **"How would you add a 'restock' admin operation?"** Add
   `Inventory#restock(code, count)`, and optionally an `AdminState` (or a
   simple guard that doesn't go through the customer-facing state machine
   at all, since restocking isn't a customer transaction) — worth
   discussing whether admin operations belong in the same state hierarchy
   or a separate concern entirely.
5. **"How would you test this?"** Unit-test each state class's four
   methods against a stubbed/mocked `VendingMachine` in isolation
   (e.g., assert `DispensingState#insert_coin` never changes balance),
   then integration-test full sequences on a real `VendingMachine` +
   `Inventory` (coin → select → dispense → change, and each rejection
   path) to catch transition bugs between states.
6. **"What happens if the machine loses power mid-dispense?"** The
   `dispense` method currently decrements inventory and zeroes balance in
   sequence — a crash between those two lines either loses an item from
   inventory without charging for it, or charges without dispensing.
   Flagging this and describing an idempotent/transactional fix (log the
   intended dispense before mutating state, reconcile on restart) is a
   good bridge toward the ATM's crash-recovery discussion in
   `05_atm_machine.md`.

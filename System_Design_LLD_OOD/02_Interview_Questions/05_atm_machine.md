# Design an ATM Machine (Object-Oriented Design)

## Problem Statement

"Design an ATM. A user inserts a card, enters a PIN, and can withdraw
cash, deposit money, check their balance, or transfer funds. The machine
has a physical cash inventory it dispenses from. Handle wrong PINs,
insufficient balance, and the machine not having enough cash to fulfill a
withdrawal."

Like the vending machine, an ATM's user-facing flow (card → PIN →
transaction) is naturally a state machine, so many candidates stop there
and treat this as "the same question again." The part that actually
differentiates a strong answer here is the **transaction** side: withdraw,
deposit, check-balance, and transfer are independent operations that all
need to be logged, potentially retried, and executed uniformly — which is
exactly what the **Command pattern** is for, and it's a genuinely
different pattern than the vending machine's State pattern even though
both problems "sound similar." Recognizing that this question wants a
second pattern layered on top of the first, not a repeat of the first, is
the signal an interviewer is looking for.

## Step 1: Clarify Requirements

**Functional Requirements**
- A user inserts a card and enters a PIN; the machine validates it against
  the account before allowing any transaction.
- Supported transactions: withdraw cash, deposit cash, check balance,
  transfer to another account.
- The machine has a physical cash inventory (denominations and counts) it
  dispenses withdrawals from.
- A withdrawal must be validated against **two independent things**: the
  account's balance, and the machine's ability to physically dispense that
  amount in available denominations.
- Wrong PIN entries are limited; the card locks after N consecutive
  failures.

**Non-Functional Requirements**
- **Security**: a PIN must never be stored or compared in plaintext — it
  should be hashed at rest, and validated by comparing hashes, not raw
  digits. This is a real point interviewers probe, not boilerplate.
- **Uniform transaction handling**: the ATM's core loop should not contain
  a growing `if operation == :withdraw ... elsif operation == :deposit`
  conditional — each transaction type should be a self-contained object
  with a common execution interface, so new transaction types, logging,
  and retries all plug in without touching the ATM's dispatch logic.
- **Correctness under two distinct failure modes**: "the account doesn't
  have enough money" and "the machine doesn't have enough physical cash"
  are different failures with different causes and different recovery
  paths — the design must not conflate them into one generic "insufficient
  funds" error.
- **Extensibility**: adding a new transaction type (e.g., bill payment)
  or a new state (e.g., out-of-service) should require adding one class,
  not editing the ATM's core flow.

## Step 2: Identify Core Objects / Entities

- **Account** — balance and identity; independent of any specific card.
- **Card** — card number and a linked `Account`, plus a hashed PIN and
  failed-attempt count; the thing physically inserted into the machine.
- **ATMState** (abstract) → `IdleState`, `CardInsertedState`,
  `PinEnteredState`, `TransactionInProgressState`, `OutOfServiceState` —
  governs what actions the machine currently accepts (insert card, enter
  PIN, select transaction).
- **Transaction** (abstract, Command) → `Withdraw`, `Deposit`,
  `CheckBalance`, `Transfer` — each a self-contained command object with a
  common `#execute` interface, holding whatever data it needs (amount,
  target account for a transfer, etc.).
- **CashDispenser** — the machine's physical cash inventory; computes a
  denomination breakdown for a requested amount and tracks what's
  actually been dispensed.
- **TransactionLog** — records every executed `Transaction`, a natural
  extension once transactions are objects rather than inline logic.
- **ATM** — orchestrates state + holds the current `Card`, delegates
  transaction execution to `Transaction` commands.

## Step 3: Identify Relationships (Class Diagram)

```text
  Account                              Card
  - id, balance                        - number
  + debit(amount) / credit(amount)     - account ------> Account
                                        - pin_hash
                                        - failed_attempts
                                        + pin_valid?(pin)
                                        + locked?

  ATMState (abstract)
  + insert_card(atm, card)         [abstract]
  + enter_pin(atm, pin)            [abstract]
  + select_transaction(atm, txn)   [abstract]
       ^
       |_______________________________________________
       |             |               |                  |
  IdleState  CardInsertedState  PinEnteredState  TransactionInProgressState

  Transaction (abstract, Command)
  - account
  + execute(atm) : Result          [abstract]
       ^
       |__________________________________________
       |            |                |              |
   Withdraw      Deposit        CheckBalance      Transfer
   - amount      - amount                          - amount, target_account

  CashDispenser
  - drawer: { denomination => count }     (composition)
  + can_dispense?(amount) : Boolean
  + dispense(amount) : { denomination => count }

  TransactionLog
  - entries: [Transaction]                (composition)
  + record(transaction, result)

  ATM
  - state -------------------> ATMState        (composition)
  - current_card -------------> Card | nil      (association, transient)
  - dispenser ----------------> CashDispenser   (composition)
  - log -----------------------> TransactionLog (composition)
  + insert_card(card) / enter_pin(pin) / select_transaction(txn)
```

Relationship types:
- `IdleState`/`CardInsertedState`/`PinEnteredState`/
  `TransactionInProgressState` **inherit** from `ATMState` (is-a).
- `Withdraw`/`Deposit`/`CheckBalance`/`Transfer` **inherit** from
  `Transaction` (is-a) — the Command pattern's concrete commands.
- `Card` **associates** with `Account` (a card refers to an account but
  doesn't own its lifecycle — closing an account doesn't destroy old
  cards automatically, it invalidates them).
- `ATM` **composes** its `CashDispenser` and `TransactionLog`; **associates**
  transiently with whatever `Card` is currently inserted.

## Step 4: Design Decisions & Patterns Used

**State pattern for the login flow, for the same reason as the vending
machine.** What "enter PIN" or "select a transaction" means depends
entirely on whether a card is inserted, whether the PIN has been verified
yet, and whether a transaction is already mid-flight. Same shape, same
justification as `04_vending_machine.md` — not repeated in full here,
since it isn't the new idea this problem is testing.

**Command pattern for transactions — the actual new idea.** The naive
version dispatches on a symbol:

```ruby
def select_transaction(type, **params)
  case type
  when :withdraw then withdraw(params[:amount])
  when :deposit  then deposit(params[:amount])
  when :transfer then transfer(params[:amount], params[:target])
  when :balance  then check_balance
  end
end
```

This has two real problems beyond just being a long conditional: (1) every
new transaction type means editing `ATM` itself, and (2) there's nowhere
natural to log, retry, or undo an operation — you'd have to wrap each
branch individually. Modeling each transaction as a `Transaction` object
with `#execute(atm)` fixes both: the ATM's dispatch becomes
`transaction.execute(self)` regardless of type, `TransactionLog` can
record any `Transaction` uniformly (it only needs the common interface),
and a future "retry failed transaction" feature is just re-invoking
`#execute` on the same command object — none of which the conditional
version gives you for free.

**Why `Withdraw` must check two independent things, and why that's a
design decision, not just an implementation detail.** `Account#balance`
and `CashDispenser`'s physical inventory are two separate sources of
truth that can each independently fail a withdrawal: an account can have
$500 but the machine might be down to a single $20 bill (can't dispense
$500), or the machine could be fully stocked but the account only has $10.
Conflating these into one "insufficient funds" check would produce a
wrong or misleading error in one of the two cases (telling a user their
*account* is short when it's actually the *machine* that's short is a real
support-call-generating bug). `Withdraw#execute` deliberately checks
`account` and `dispenser` separately and returns which one failed.

**Why PINs are hashed, never compared in plaintext.** `Card` stores
`pin_hash`, not `pin`; `pin_valid?` hashes the input and compares hashes.
This isn't just "best practice" filler — an interviewer who asks "how do
you validate the PIN" is directly probing whether you'd store/compare raw
PINs, which is a genuine security defect in a real ATM design, not a
stylistic nitpick.

## Step 5: Code

```ruby
require "digest"

class Account
  attr_reader :id
  attr_reader :balance

  def initialize(id, balance)
    @id = id
    @balance = balance
  end

  def debit(amount)
    raise "insufficient account balance" if amount > @balance

    @balance -= amount
  end

  def credit(amount)
    @balance += amount
  end
end

class Card
  MAX_ATTEMPTS = 3

  attr_reader :number, :account
  attr_reader :failed_attempts

  def initialize(number, account, pin)
    @number = number
    @account = account
    @pin_hash = Digest::SHA256.hexdigest(pin)
    @failed_attempts = 0
  end

  def pin_valid?(pin)
    return false if locked?

    if Digest::SHA256.hexdigest(pin) == @pin_hash
      @failed_attempts = 0
      true
    else
      @failed_attempts += 1
      false
    end
  end

  def locked? = @failed_attempts >= MAX_ATTEMPTS
end

# --- Transactions (Command pattern) ---------------------------------------

Result = Struct.new(:success, :message, :data, keyword_init: true)

class Transaction
  attr_reader :account

  def initialize(account)
    @account = account
  end

  def execute(atm)
    raise NotImplementedError
  end
end

class Withdraw < Transaction
  attr_reader :amount

  def initialize(account, amount)
    super(account)
    @amount = amount
  end

  def execute(atm)
    return Result.new(success: false, message: "insufficient account balance") if amount > account.balance
    return Result.new(success: false, message: "machine cannot dispense this amount") unless atm.dispenser.can_dispense?(amount)

    breakdown = atm.dispenser.dispense(amount)
    account.debit(amount)
    Result.new(success: true, message: "dispensed", data: breakdown)
  end
end

class Deposit < Transaction
  attr_reader :amount

  def initialize(account, amount)
    super(account)
    @amount = amount
  end

  def execute(atm)
    account.credit(amount)
    Result.new(success: true, message: "deposited", data: amount)
  end
end

class CheckBalance < Transaction
  def execute(atm)
    Result.new(success: true, message: "balance", data: account.balance)
  end
end

class Transfer < Transaction
  attr_reader :amount, :target_account

  def initialize(account, amount, target_account)
    super(account)
    @amount = amount
    @target_account = target_account
  end

  def execute(atm)
    return Result.new(success: false, message: "insufficient account balance") if amount > account.balance

    account.debit(amount)
    target_account.credit(amount)
    Result.new(success: true, message: "transferred")
  end
end

# --- Cash dispenser --------------------------------------------------------

class CashDispenser
  def initialize(drawer)
    @drawer = drawer # { 100 => count, 50 => count, 20 => count, ... }
  end

  def can_dispense?(amount)
    !breakdown_for(amount).nil?
  end

  def dispense(amount)
    breakdown = breakdown_for(amount)
    raise "cannot dispense #{amount}" unless breakdown

    breakdown.each { |denom, count| @drawer[denom] -= count }
    breakdown
  end

  private

  # Greedy denomination breakdown: largest bills first. Returns nil if the
  # exact amount can't be made with what's currently in the drawer (e.g.,
  # enough total cash, but not enough $20s specifically).
  def breakdown_for(amount)
    remaining = amount
    breakdown = {}

    @drawer.keys.sort.reverse_each do |denom|
      available = @drawer[denom]
      needed = [remaining / denom, available].min
      next if needed.zero?

      breakdown[denom] = needed
      remaining -= needed * denom
    end

    remaining.zero? ? breakdown : nil
  end
end

class TransactionLog
  def initialize
    @entries = []
  end

  def record(transaction, result)
    @entries << { transaction: transaction, result: result, at: Time.now }
  end
end

# --- ATM states -------------------------------------------------------------

class ATMState
  def insert_card(atm, card) = raise("cannot insert card now")
  def enter_pin(atm, pin) = raise("no card inserted")
  def select_transaction(atm, transaction) = raise("not authenticated")
end

class IdleState < ATMState
  def insert_card(atm, card)
    return Result.new(success: false, message: "card locked") if card.locked?

    atm.current_card = card
    atm.state = CardInsertedState.new
  end
end

class CardInsertedState < ATMState
  def enter_pin(atm, pin)
    if atm.current_card.pin_valid?(pin)
      atm.state = PinEnteredState.new
      Result.new(success: true, message: "authenticated")
    else
      atm.state = IdleState.new if atm.current_card.locked?
      Result.new(success: false, message: "wrong pin")
    end
  end
end

class PinEnteredState < ATMState
  def select_transaction(atm, transaction)
    atm.state = TransactionInProgressState.new
    result = transaction.execute(atm)
    atm.log.record(transaction, result)
    atm.state = PinEnteredState.new # ready for another transaction, or eject_card
    result
  end
end

class TransactionInProgressState < ATMState
  # No actions accepted mid-transaction; the ATM itself controls the
  # transition back to PinEnteredState once execute() returns.
end

class OutOfServiceState < ATMState
end

# --- ATM ---------------------------------------------------------------

class ATM
  attr_accessor :state, :current_card
  attr_reader :dispenser, :log

  def initialize(dispenser)
    @state = IdleState.new
    @current_card = nil
    @dispenser = dispenser
    @log = TransactionLog.new
  end

  def insert_card(card) = @state.insert_card(self, card)
  def enter_pin(pin) = @state.enter_pin(self, pin)
  def select_transaction(transaction) = @state.select_transaction(self, transaction)

  def eject_card
    @current_card = nil
    @state = IdleState.new
  end
end
```

**Using it:**

```ruby
account = Account.new("ACC-1", 500)
card = Card.new("CARD-1", account, "1234")

drawer = { 100 => 5, 50 => 4, 20 => 2 } # $500 + $200 + $40 = $740 total
atm = ATM.new(CashDispenser.new(drawer))

atm.insert_card(card)
atm.enter_pin("9999") # wrong
atm.enter_pin("1234") # correct -> PinEnteredState

result = atm.select_transaction(Withdraw.new(account, 230))
result.success # => true
result.data    # => {100=>2, 20=>1}  (greedy: 2x$100 + 1x$20 = $220... )
```

Note the example above is deliberately worth tracing by hand: $230 needs
`2x$100 + 1x$20 + $10` — but there's no $10 note in the drawer, so
`breakdown_for` leaves `remaining = 10` non-zero and correctly returns
`nil`, meaning `can_dispense?(230)` is `false` and the withdrawal is
rejected with `"machine cannot dispense this amount"` even though the
account has $500 and the machine holds $740 total. This is exactly the
"physically can't dispense" edge case called out below.

## Step 6: Edge Cases & Extensibility

- **Insufficient account balance vs. insufficient machine cash — two
  different failures, and the code returns two different messages for
  them.** `Withdraw#execute` checks `account.balance` first, then
  `atm.dispenser.can_dispense?` second, and reports which one failed.
  Collapsing these into one generic error is the most common shortcut
  candidates take under time pressure, and it's exactly the distinction
  this question is designed to probe.
- **A withdrawal valid against balance but not dispensable in available
  denominations.** Walked through explicitly above ($230 against
  $100/$50/$20 notes with no $50 in this particular trace) — the
  `breakdown_for` greedy algorithm must fail closed (return `nil`, dispense
  nothing) rather than dispense a partial/wrong amount.
- **Wrong PIN retry limits.** `Card#pin_valid?` increments
  `failed_attempts` on failure and resets it on success; `Card#locked?`
  is checked both on insertion (`IdleState#insert_card`) and after a
  failed attempt inside `CardInsertedState#enter_pin`, ejecting the card
  back to `IdleState` once locked rather than leaving it stuck
  mid-authentication.
- **The greedy denomination algorithm isn't always optimal/correct for
  arbitrary denomination sets** (it works for standard bill sets like
  100/50/20/10/5/1, but a pathological denomination set can make greedy
  fail where a smarter combination would succeed) — worth a one-line
  mention that this is the same class of problem as the classic "coin
  change" algorithm, and that real ATMs constrain denominations
  specifically so greedy always works.
- **Multiple failed transactions inflating the log with noise.** Since
  every `Transaction` (successful or not) is logged uniformly via
  `atm.log.record`, this comes for free rather than needing special
  handling — another payoff of the Command pattern.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you support multiple accounts linked to one card (checking
   vs. savings)?"** Change `Card#account` to `Card#accounts` (a list), add
   an "account selection" step to the state flow (a new state or a
   parameter on `select_transaction`), and have each `Transaction` take an
   explicit account reference rather than implicitly using "the" account —
   the `Transaction` classes already take `account` as a constructor
   argument, so this mostly changes what selects it, not the commands
   themselves.
2. **"How do you make transaction execution safe against the machine
   losing power mid-dispense?"** This is the standout follow-up for this
   problem: `Withdraw#execute` currently dispenses cash and debits the
   account in two separate steps — a crash between them either dispenses
   without debiting (bank loses money) or debits without dispensing
   (customer loses money). The fix is to log the *intent* to withdraw
   (amount, account, breakdown) durably before touching either the
   dispenser or the account, then reconcile on restart by checking which
   step actually completed — an idempotency/recovery pattern. At real
   bank scale this becomes a distributed transaction / saga problem across
   the ATM, the core banking ledger, and the cash-management system —
   worth naming explicitly as the LLD/HLD boundary, and pointing to
   `System_Design/02_Interview_Questions/14_payment_system.md` for how
   that side is handled at scale.
3. **"How would you add bill payment or check deposit as new transaction
   types?"** Add `BillPayment < Transaction` / `CheckDeposit < Transaction`
   implementing `#execute` — zero changes to `ATM`'s dispatch logic or
   `TransactionLog`, which is the direct payoff of the Command pattern
   chosen in Step 4.
4. **"How is this different from the vending machine's design?"** Both use
   State for their front-facing flow, but the ATM additionally needs
   Command for its transactions because transactions here are richer
   (need logging, retries, and eventually undo/reversal) and more varied
   (four independent operations vs. the vending machine's single
   "dispense" action) — a good moment to show you understand *why* a
   pattern applies, not just that it does.
5. **"How would you test this?"** Unit-test `CashDispenser#breakdown_for`
   exhaustively against various drawer contents (including the
   can't-make-exact-change case), unit-test each `Transaction` subclass's
   `#execute` against stub accounts/dispensers, and integration-test the
   full `ATM` state flow (wrong PIN → lockout, correct PIN → withdraw →
   eject) to catch transition bugs between `ATMState`s.
6. **"What if the interviewer asks you to add fraud detection (e.g., flag
   unusual withdrawal patterns)?"** This is naturally a decorator or an
   observer around transaction execution — wrap `Transaction#execute` (or
   have `TransactionLog#record` notify a `FraudMonitor`) rather than
   embedding pattern-detection logic inside each `Transaction` subclass,
   keeping the commands themselves simple and the fraud logic centralized
   and independently testable.

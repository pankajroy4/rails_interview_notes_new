# Design Splitwise (Expense Sharing) (Object-Oriented Design)

## Problem Statement

"Design a simplified Splitwise. Users can be grouped together (e.g., a
trip, a shared apartment). Any user can add an expense paid by one person
and split among a set of participants — equally, by exact amounts, or by
percentage. At any point, show how much each user owes or is owed within
a group. Bonus: given everyone's balances, figure out the minimum number
of payments needed to settle the group up completely."

This problem is popular because it has two genuinely separate hard parts,
and interviewers are checking whether you notice both. The first is
**modeling the split itself** — equal/exact/percentage splits are
different enough in their math that cramming them into one `Expense`
class with a `split_type` flag and a bunch of `if`s is a code smell the
interviewer is watching for. The second, often saved as a follow-up, is
**debt simplification** — a real, nameable algorithm (a greedy variant of
the "minimum cash flow" problem), not just an OOP exercise, and a good
signal of whether you can move from class design into algorithm design
when pushed.

## Step 1: Clarify Requirements

**Functional Requirements**
- Users can belong to multiple groups.
- Any group member can add an `Expense`: who paid, total amount, and how
  it's split among participants.
- Support three split types: **equal** (divide evenly among participants),
  **exact** (each participant owes a specific, pre-agreed amount), and
  **percentage** (each participant owes a percentage of the total).
- Track each user's **net balance within a group** — positive means the
  group owes them, negative means they owe the group.
- Given a group's balances, compute a **minimal set of settle-up
  transactions** ("who pays whom how much") that zeroes everyone out.

**Non-Functional Requirements**
- **Correctness of splits**: an exact split must sum to the expense total;
  a percentage split must sum to 100%. Reject (don't silently accept) an
  expense whose split doesn't add up — this is a real source of production
  bugs in the actual app, not a hypothetical.
- **Balances scoped per group**: a user in five groups has five
  independent balances, not one blended number — mixing them would make
  "who owes whom" meaningless once you cross group boundaries.
- **Extensibility**: adding a new split type (e.g., "by shares," like 2
  shares for one roommate and 1 for another) should mean adding a class,
  not editing `Expense`.
- **No N² pairwise ledger**: don't store "Alice owes Bob $12, Bob owes
  Carol $7, ..." as a growing set of pairwise debts — that gets
  inconsistent and expensive to query fast. A single net balance per user
  per group is sufficient to answer every "who owes what" question and is
  what the settle-up algorithm operates on.

## Step 2: Identify Core Objects / Entities

- **User** — id and name.
- **Group** — a set of users sharing expenses; owns the per-user net
  balances for its own scope.
- **Expense** — paid_by user, total amount, participants, and a
  `SplitStrategy` that computes how much each participant owes.
- **SplitStrategy** (abstract) → `EqualSplit`, `ExactSplit`,
  `PercentSplit` — each knows how to turn "$total among these
  participants" into a `{user => owed_amount}` map, and how to validate
  itself.
- **Settlement** — a value object representing one "X pays Y $amount"
  instruction, the output of the debt-simplification algorithm.

## Step 3: Identify Relationships (Class Diagram)

```text
User
- id, name

                     SplitStrategy (abstract)
                     + compute_shares(total, participants, params) : {User => Float}
                     + validate!(total, participants, params)         [abstract]
                          ^
              ____________|____________________
             |               |                  |
        EqualSplit       ExactSplit         PercentSplit
    (total / N each)   (params: {User =>  (params: {User => pct},
                         exact amount})     validate sums to 100)

  Expense
  - paid_by --------> User
  - amount: Float
  - participants[] --> [User]
  - split_strategy --> SplitStrategy      (composition: owns-a strategy instance)
  - split_params: Hash                    (exact amounts or percentages, if any)
  + shares : {User => Float}              (delegates to split_strategy)

  Group
  - members[] -------> [User]              (association: uses-a)
  - expenses[] ------> [Expense]           (composition: owns-a)
  - balances: { User => Float }            (net balance, positive = owed)
  + add_expense(expense)
  + balance_for(user) : Float
  + simplify_debts : [Settlement]

  Settlement (value object)
  - from ------------> User   (the one who pays)
  - to --------------> User   (the one who receives)
  - amount: Float
```

Relationship types:
- `EqualSplit`/`ExactSplit`/`PercentSplit` **inherit** from
  `SplitStrategy` (is-a) — this is the Strategy pattern applied to "how do
  we divide this bill."
- `Expense` **composes** a `SplitStrategy` instance — the strategy has no
  meaning outside the expense using it.
- `Group` **composes** its `Expense`s and its `balances` — both are
  entirely owned by, and scoped to, that group.
- `Group` **associates** with `User`s — users exist independently of any
  one group (the same `User` object is referenced by several groups).

## Step 4: Design Decisions & Patterns Used

**Strategy pattern for splits.** The naive design puts a `split_type`
enum on `Expense` and an `if/elsif` chain (or `case`) inside a
`calculate_shares` method that handles equal/exact/percent math inline.
This fails the same way it always does: adding a fourth split type
("by shares") means editing `Expense` itself, and the validation rules for
each type (exact must sum to total; percent must sum to 100) end up
tangled together in one method that's hard to unit test in isolation.
Instead, each split type is its own `SplitStrategy` subclass responsible
for both `compute_shares` (the math) and `validate!` (the type-specific
correctness rule) — `Expense` just holds a strategy instance and delegates
to it. Testing `PercentSplit` never requires constructing a full `Expense`
or `Group`.

**Net balance per user per group, not a pairwise ledger.** A tempting but
wrong design stores every individual debt as it happens: "Alice owes Bob
$12 from lunch," "Bob owes Alice $5 from coffee." This is intuitive but
wrong at scale — it grows unbounded with expense count, requires summing
across potentially many entries just to answer "does Alice owe Bob
anything right now," and actively works against debt simplification
(which wants aggregate positions, not transaction-level detail). Instead,
every expense updates one running `net_balance` per user: the payer's
balance goes up by (amount - their own share, since they don't owe
themselves), and each other participant's balance goes down by their
share. This single number per user is both O(1) to query and exactly the
input the settlement algorithm needs.

**Debt simplification as a greedy max-creditor/max-debtor match — a named
algorithm, not just "some logic."** Given the net balances, the (well-known
"minimize cash flow") approach is: separate users into creditors (positive
balance) and debtors (negative balance), repeatedly take the creditor owed
the most and the debtor who owes the most, settle the smaller of the two
amounts between them directly, reduce both balances accordingly, and
repeat until everyone is at zero. This greedy approach doesn't always hit
the mathematically absolute minimum number of transactions in every case
(true optimality is closer to a subset-sum/partition style problem, which
is NP-hard in general), but it's the standard, practical answer expected
in this interview, it's O(N log N) dominated by sorting, and it's what
Splitwise actually approximates in production. Naming this as "greedy,
efficient, and the standard answer, with true optimality being much
harder" is exactly the kind of precision that separates a strong answer.

**Why `Expense` doesn't mutate `Group.balances` directly.** Keeping
balance mutation inside `Group#add_expense` (rather than, say,
`Expense#apply!`) keeps `Group` as the single owner and source of truth
for its balances — an `Expense` object is otherwise a pure, side-effect-free
computation (amount + strategy → shares), which makes it trivially testable
and reusable (e.g., "preview what this split would look like" before
committing it to a group).

## Step 5: Code

```ruby
class User
  attr_reader :id, :name

  def initialize(id, name)
    @id = id
    @name = name
  end
end

class SplitStrategy
  # Returns { User => Float } — how much each participant owes toward `total`.
  def compute_shares(total, participants, params = {})
    raise NotImplementedError
  end

  # Raises ArgumentError if the split is internally inconsistent.
  def validate!(total, participants, params = {})
    raise NotImplementedError
  end
end

class EqualSplit < SplitStrategy
  def compute_shares(total, participants, _params = {})
    base = (total / participants.size.to_f)
    shares = participants.each_with_object({}) { |u, h| h[u] = base.round(2) }
    fix_rounding_remainder!(shares, total, participants)
  end

  def validate!(total, participants, _params = {})
    raise ArgumentError, "need at least one participant" if participants.empty?
  end

  private

  # Splitting $10 among 3 people gives $3.33 each, totaling $9.99 — someone
  # has to absorb the missing cent. Convention: the remainder (in cents)
  # is distributed one cent at a time to the first N participants in
  # order, so the total always reconciles exactly to the original amount.
  def fix_rounding_remainder!(shares, total, participants)
    remainder_cents = ((total - shares.values.sum) * 100).round
    participants.first(remainder_cents.abs).each do |u|
      shares[u] += remainder_cents.positive? ? 0.01 : -0.01
    end
    shares
  end
end

class ExactSplit < SplitStrategy
  # params: { user => exact_amount }
  def compute_shares(_total, _participants, params = {})
    params.dup
  end

  def validate!(total, participants, params = {})
    missing = participants - params.keys
    raise ArgumentError, "missing exact amount for #{missing}" unless missing.empty?

    sum = params.values.sum
    raise ArgumentError, "exact amounts (#{sum}) must sum to total (#{total})" unless (sum - total).abs < 0.01
  end
end

class PercentSplit < SplitStrategy
  # params: { user => percentage }, e.g. { alice => 50.0, bob => 50.0 }
  def compute_shares(total, _participants, params = {})
    params.transform_values { |pct| (total * pct / 100.0).round(2) }
  end

  def validate!(_total, participants, params = {})
    missing = participants - params.keys
    raise ArgumentError, "missing percentage for #{missing}" unless missing.empty?

    sum = params.values.sum
    raise ArgumentError, "percentages must sum to 100 (got #{sum})" unless (sum - 100.0).abs < 0.01
  end
end

class Expense
  attr_reader :paid_by, :amount, :participants, :split_strategy, :split_params

  def initialize(paid_by:, amount:, participants:, split_strategy:, split_params: {})
    @paid_by = paid_by
    @amount = amount
    @participants = participants
    @split_strategy = split_strategy
    @split_params = split_params
    split_strategy.validate!(amount, participants, split_params)
  end

  def shares
    split_strategy.compute_shares(amount, participants, split_params)
  end
end

Settlement = Struct.new(:from, :to, :amount)

class Group
  attr_reader :members, :expenses

  def initialize(members)
    @members = members
    @expenses = []
    @balances = Hash.new(0.0)   # User => net balance, scoped to this group
  end

  def add_expense(expense)
    @expenses << expense
    shares = expense.shares

    shares.each do |user, owed|
      @balances[user] -= owed
    end
    @balances[expense.paid_by] += expense.amount
  end

  def balance_for(user)
    @balances[user].round(2)
  end

  # Greedy min-cash-flow settlement: repeatedly match the largest creditor
  # against the largest debtor. Runs in O(N log N), N = number of members
  # with a non-zero balance.
  def simplify_debts
    working = @balances.reject { |_, v| v.round(2).zero? }.transform_values { |v| v.round(2) }
    settlements = []

    loop do
      creditor = working.max_by { |_, bal| bal }
      debtor = working.min_by { |_, bal| bal }
      break if creditor.nil? || creditor[1] <= 0 || debtor[1] >= 0

      amount = [creditor[1], -debtor[1]].min.round(2)
      settlements << Settlement.new(debtor[0], creditor[0], amount)

      working[creditor[0]] -= amount
      working[debtor[0]] += amount
      working.delete(creditor[0]) if working[creditor[0]].round(2).zero?
      working.delete(debtor[0]) if working[debtor[0]].round(2).zero?
    end

    settlements
  end
end
```

**Using it:**

```ruby
alice = User.new(1, "Alice")
bob   = User.new(2, "Bob")
carol = User.new(3, "Carol")

trip = Group.new([alice, bob, carol])

# Alice pays $90 dinner, split equally three ways.
trip.add_expense(Expense.new(
  paid_by: alice, amount: 90.0, participants: [alice, bob, carol],
  split_strategy: EqualSplit.new
))
trip.balance_for(alice) # =>  60.0   (paid 90, owes 30 of it)
trip.balance_for(bob)   # => -30.0
trip.balance_for(carol) # => -30.0

# Bob pays $50 for a cab, split 70/30 between Bob and Carol.
trip.add_expense(Expense.new(
  paid_by: bob, amount: 50.0, participants: [bob, carol],
  split_strategy: PercentSplit.new, split_params: { bob => 30.0, carol => 70.0 }
))
trip.balance_for(bob)   # => -30.0 + 50.0 - 15.0 = 5.0
trip.balance_for(carol) # => -30.0 - 35.0 = -65.0

trip.simplify_debts
# => [Settlement(carol, alice, 60.0), ...]  -- minimum transactions to zero everyone out
```

## Step 6: Edge Cases & Extensibility

- **A split that doesn't sum to the total**: `ExactSplit#validate!` checks
  the sum against `amount`; `PercentSplit#validate!` checks against 100 —
  both raise at `Expense` construction time, not silently or lazily when
  balances are later queried, so bad data never enters a group's ledger.
- **A user in multiple groups**: each `Group` owns its own `@balances`
  hash — there's no shared or global balance object, so an expense in one
  group can never leak into another group's numbers.
- **Rounding on an uneven equal split**: `EqualSplit#fix_rounding_remainder!`
  explicitly reconciles the total back to the exact original amount by
  distributing leftover cents to the first N participants — call this out
  explicitly if asked, since it's a real bug class ("the total after
  splitting doesn't match the receipt") in this exact kind of feature.
- **An expense where the payer is also a non-participant** (e.g., a parent
  pays but isn't part of the split): supported naturally — `paid_by`
  doesn't have to be a member of `participants`; the payer's balance still
  increases by the full `amount`, they just don't owe any of it back.
- **Deleting/editing an expense**: not shown above, but the clean way is
  to reverse the exact same balance deltas the original `add_expense`
  applied (subtract what was added, add back what was subtracted) rather
  than recomputing all balances for the group from scratch — this only
  works cleanly because balance mutation is centralized in one method.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you support multi-currency groups?"** Store `amount` as a
   `Money` value object (amount + currency) instead of a raw float, and
   either (a) forbid mixing currencies within one group's balance, or (b)
   convert every expense to a group-level "home currency" at the exchange
   rate current at expense-creation time before folding it into
   `@balances`, recording the original currency/rate on the `Expense` for
   display purposes. Raw floats for money is itself worth flagging as a
   simplification made for interview time — real systems use integer
   cents or a decimal type to avoid floating-point drift.
2. **"How would you show a user's total balance across all their
   groups?"** Add a method that iterates every `Group` the user belongs to
   and sums `balance_for(user)` across them — note explicitly that this is
   a *display aggregate only*; it should never be stored as a single
   number or used to settle debts, since settlements are inherently
   per-group (you can't net a debt in the "Goa Trip" group against a debt
   in the "Apartment" group without the counterparties agreeing to that).
3. **"Is the greedy settlement algorithm actually optimal (fewest possible
   transactions)?"** Not always — finding the true minimum number of
   transactions is equivalent to a set-partition style problem and is
   NP-hard in general (you'd need to search subsets of debtors/creditors
   whose amounts can combine exactly). The greedy largest-vs-largest match
   is a good, fast, practical approximation and is what's expected here;
   naming the NP-hardness explicitly is a strong signal without needing to
   solve it.
4. **"How would you add a 'by shares' split (e.g., 2 shares for one
   roommate, 1 share each for two others)?"** Add a `SharesSplit <
   SplitStrategy` where `params` maps each user to a share count, and
   `compute_shares` divides `total` proportionally by
   `share / total_shares` — zero changes to `Expense`, `Group`, or any
   other strategy, which is the direct payoff of the Strategy pattern
   decision in Step 4.
5. **"How would you handle a user disputing or editing a recorded
   expense?"** Treat edits as "reverse the old expense's balance deltas,
   then apply the new one" (see Step 6) rather than mutating shares
   in-place — this also gives you a natural audit trail if you keep both
   the original and the correction as separate `Expense` records with a
   `superseded_by` link.
6. **"What if a user leaves a group with a non-zero balance?"** That's a
   product decision, not a class-design one: either block the removal
   until `balance_for(user)` is zero, or keep the user as a "ghost member"
   (retained in `@balances` and `simplify_debts` output but excluded from
   new expenses going forward) until settled — worth naming both options
   rather than picking one silently.

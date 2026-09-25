# Design Splitwise (Expense Sharing) (Object-Oriented Design)

## Problem Statement

"Ek simplified Splitwise design karo. Users ko group mein daala ja sakta
hai (jaise, ek trip, ek shared apartment). Koi bhi user ek expense add kar
sakta hai jo ek person ne pay kiya ho aur participants ke ek set mein split
ho — equally, exact amounts se, ya percentage se. Kisi bhi point pe,
dikhao ki ek group ke andar har user kitna owe karta hai ya kitna owed hai.
Bonus: sabke balances dekhkar, figure out karo ki group ko poori tarah
settle karne ke liye minimum kitne payments chahiye."

Yeh problem popular hai kyunki isme genuinely do separate hard parts hain,
aur interviewers check kar rahe hain ki aap dono notice karte ho ya nahi.
Pehla hai **split khud ko model karna** — equal/exact/percentage splits
apne math mein itne alag hain ki inhe ek `Expense` class mein `split_type`
flag aur bahut saare `if`s ke saath cram karna ek code smell hai jise
interviewer watch kar raha hai. Doosra, jo often follow-up ke liye bacha
jaata hai, wo hai **debt simplification** — ek real, nameable algorithm
("minimum cash flow" problem ka ek greedy variant), sirf ek OOP exercise
nahi, aur ek good signal ki kya aap class design se algorithm design mein
move kar sakte ho jab push kiya jaaye.

## Step 1: Clarify Requirements

**Functional Requirements**
- Users multiple groups ke part ho sakte hain.
- Koi bhi group member ek `Expense` add kar sakta hai: kisne pay kiya,
  total amount, aur yeh participants mein kaise split hota hai.
- Teen split types support karo: **equal** (participants mein evenly
  divide karo), **exact** (har participant ek specific, pre-agreed amount
  owe karta hai), aur **percentage** (har participant total ka ek
  percentage owe karta hai).
- Har user ka **group ke andar net balance** track karo — positive matlab
  group unhe owe karta hai, negative matlab wo group ko owe karte hain.
- Ek group ke balances dekhkar, **settle-up transactions ka minimal set**
  compute karo ("kaun kisko kitna pay kare") jo sabko zero kar de.

**Non-Functional Requirements**
- **Splits ki correctness**: ek exact split expense total tak sum hona
  chahiye; ek percentage split 100% tak sum hona chahiye. Ek aisa expense
  reject karo (silently accept mat karo) jiska split add up nahi hota —
  yeh actual app mein production bugs ka ek real source hai, hypothetical
  nahi.
- **Balances group ke hisaab se scoped hain**: ek user jo paanch groups
  mein hai, uske paanch independent balances hain, ek blended number nahi
  — inhe mix karna "kaun kisko owe karta hai" ko meaningless bana dega
  group boundaries cross karte hi.
- **Extensibility**: naya split type add karna (jaise, "by shares," jaise
  ek roommate ke 2 shares aur doosre ke 1) matlab ek class add karna, na
  ki `Expense` edit karna.
- **N² pairwise ledger nahi**: "Alice, Bob ko $12 owe karti hai, Bob,
  Carol ko $7 owe karta hai, ..." ko ek growing set of pairwise debts ke
  roop mein store mat karo — yeh inconsistent ho jaata hai aur fast query
  karna expensive ho jaata hai. Har user per group ek single net balance
  hi "kaun kya owe karta hai" ke har question ka answer dene ke liye
  sufficient hai aur yahi hai jispe settle-up algorithm operate karta hai.

## Step 2: Identify Core Objects / Entities

- **User** — id aur name.
- **Group** — users ka ek set jo expenses share karte hain; apne scope ke
  liye per-user net balances own karta hai.
- **Expense** — paid_by user, total amount, participants, aur ek
  `SplitStrategy` jo compute karta hai har participant kitna owe karta hai.
- **SplitStrategy** (abstract) → `EqualSplit`, `ExactSplit`,
  `PercentSplit` — har ek janta hai "$total in participants" ko ek
  `{user => owed_amount}` map mein kaise convert karna hai, aur khud ko
  kaise validate karna hai.
- **Settlement** — ek value object jo ek "X pays Y $amount" instruction
  represent karta hai, jo debt-simplification algorithm ka output hai.

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
- `EqualSplit`/`ExactSplit`/`PercentSplit` `SplitStrategy` se **inherit**
  karte hain (is-a) — yeh "bill ko kaise divide karein" pe applied Strategy
  pattern hai.
- `Expense` ek `SplitStrategy` instance ko **compose** karta hai —
  strategy ka use kar rahe expense ke bahar koi meaning nahi hai.
- `Group` apne `Expense`s aur apne `balances` ko **compose** karta hai —
  dono poori tarah uss group ke owned hain, aur uske hi scope tak limited
  hain.
- `Group` `User`s ke saath **associate** hota hai — users kisi ek group se
  independently exist karte hain (same `User` object multiple groups se
  reference hota hai).

## Step 4: Design Decisions & Patterns Used

**Splits ke liye Strategy pattern.** Naive design `Expense` pe ek
`split_type` enum daal deta hai aur ek `if/elsif` chain (ya `case`) ek
`calculate_shares` method ke andar jo equal/exact/percent math inline
handle karta hai. Yeh usi tarah fail karta hai jaise hamesha karta hai:
chautha split type ("by shares") add karna matlab `Expense` khud edit
karna, aur har type ke validation rules (exact ko total tak sum hona
chahiye; percent ko 100 tak sum hona chahiye) ek method mein tangled ho
jaate hain jo isolation mein unit test karna hard hai. Iski jagah, har
split type apna khud ka `SplitStrategy` subclass hai jo `compute_shares`
(math) aur `validate!` (type-specific correctness rule) dono ke liye
responsible hai — `Expense` bas ek strategy instance hold karta hai aur
usko delegate karta hai. `PercentSplit` test karne ke liye kabhi bhi ek
poora `Expense` ya `Group` construct karna zaroori nahi hai.

**Har user per group ek net balance, ek pairwise ledger nahi.** Ek
tempting lekin galat design har individual debt ko jaise hi ho, waise
store karta hai: "Alice, Bob ko lunch se $12 owe karti hai," "Bob, Alice
ko coffee se $5 owe karta hai." Yeh intuitive hai lekin scale pe galat hai
— yeh expense count ke saath unbounded grow karta hai, "kya Alice abhi
Bob ko kuch owe karti hai" ka answer dene ke liye potentially bahut saare
entries ko sum karna padta hai, aur actively debt simplification ke
against kaam karta hai (jise aggregate positions chahiye, transaction-level
detail nahi). Iski jagah, har expense ek running `net_balance` per user
update karta hai: payer ka balance (amount - unka khud ka share, kyunki
wo khud ko owe nahi karte) se badhta hai, aur har doosre participant ka
balance unke share se ghat jaata hai. Yeh single number per user O(1) mein
query karne layak bhi hai aur exactly wahi input hai jo settlement
algorithm ko chahiye.

**Debt simplification ek greedy max-creditor/max-debtor match ke roop mein
— ek named algorithm, sirf "kuch logic" nahi.** Net balances diye hue,
well-known "minimize cash flow" approach yeh hai: users ko creditors
(positive balance) aur debtors (negative balance) mein separate karo,
repeatedly sabse zyada owed creditor aur sabse zyada owe karne waale
debtor ko lo, unke beech directly dono mein se smaller amount settle karo,
dono balances accordingly reduce karo, aur repeat karo jab tak sab zero pe
na aa jaayein. Yeh greedy approach har case mein mathematically absolute
minimum number of transactions hit nahi karta (true optimality ek
subset-sum/partition style problem ke zyada close hai, jo generally
NP-hard hai), lekin yeh iss interview mein expect kiya jaane wala standard,
practical answer hai, yeh sorting se dominated O(N log N) hai, aur yeh
wahi hai jo Splitwise production mein actually approximate karta hai. Isse
"greedy, efficient, aur standard answer, with true optimality being much
harder" bolke name karna exactly wo precision hai jo ek strong answer ko
alag karta hai.

**`Expense` `Group.balances` ko directly mutate kyun nahi karta.** Balance
mutation ko `Group#add_expense` ke andar rakhna (na ki, kahiye,
`Expense#apply!` mein) `Group` ko apne balances ke single owner aur
source of truth ke roop mein rakhta hai — ek `Expense` object otherwise
ek pure, side-effect-free computation hai (amount + strategy → shares),
jo isse trivially testable aur reusable banata hai (jaise, "yeh split
dekhne mein kaisa lagega" preview karna kisi group mein commit karne se
pehle).

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

**Isko use karte hue:**

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

- **Ek split jo total tak sum nahi hota**: `ExactSplit#validate!` sum ko
  `amount` ke against check karta hai; `PercentSplit#validate!` 100 ke
  against check karta hai — dono `Expense` construction time pe raise
  karte hain, silently ya lazily nahi jab baad mein balances query hote
  hain, isliye bad data kabhi group ke ledger mein enter nahi hota.
- **Ek user multiple groups mein**: har `Group` apna khud ka `@balances`
  hash own karta hai — koi shared ya global balance object nahi hai,
  isliye ek group ka expense kabhi doosre group ke numbers mein leak nahi
  ho sakta.
- **Uneven equal split pe rounding**: `EqualSplit#fix_rounding_remainder!`
  explicitly total ko exact original amount tak reconcile karta hai
  leftover cents ko first N participants mein distribute karke — agar
  pucha jaaye toh isse explicitly call out karo, kyunki yeh isi tarah ke
  feature mein ek real bug class hai ("split karne ke baad total receipt
  se match nahi karta").
- **Ek expense jahan payer bhi non-participant hai** (jaise, ek parent pay
  karta hai lekin split ka part nahi hai): naturally supported hai —
  `paid_by` ka `participants` ka member hona zaroori nahi hai; payer ka
  balance abhi bhi full `amount` se increase hota hai, wo bas usme se
  kuch owe nahi karte.
- **Ek expense delete/edit karna**: upar nahi dikhaya gaya, lekin clean
  tareeka yeh hai ki original `add_expense` ne jo exact balance deltas
  apply kiye the unhe reverse karo (jo add hua tha wo subtract karo, jo
  subtract hua tha wo wapas add karo) instead of group ke saare balances
  scratch se recompute karna — yeh cleanly sirf isliye kaam karta hai
  kyunki balance mutation ek method mein centralized hai.

## Follow-up Questions an Interviewer Might Ask

1. **"Multi-currency groups kaise support karoge?"** `amount` ko raw
   float ke bajaye ek `Money` value object (amount + currency) ke roop
   mein store karo, aur ya toh (a) ek group ke balance ke andar
   currencies mix karna forbid karo, ya (b) expense-creation time pe
   current exchange rate pe har expense ko ek group-level "home currency"
   mein convert karo `@balances` mein fold karne se pehle, aur display
   purposes ke liye original currency/rate ko `Expense` pe record karo.
   Money ke liye raw floats khud bhi ek simplification hai jo interview
   time ke liye ki gayi hai, isse flag karna worth hai — real systems
   integer cents ya ek decimal type use karte hain floating-point drift
   avoid karne ke liye.
2. **"User ka total balance uske saare groups mein kaise dikhaoge?"** Ek
   method add karo jo user ke belong karne wale har `Group` ko iterate
   kare aur unke across `balance_for(user)` sum kare — explicitly note
   karo ki yeh sirf ek *display aggregate* hai; ise kabhi ek single number
   ke roop mein store nahi karna chahiye ya debts settle karne ke liye use
   nahi karna chahiye, kyunki settlements inherently per-group hain (aap
   "Goa Trip" group mein ek debt ko "Apartment" group mein ek debt ke
   against net nahi kar sakte bina counterparties ke agree kiye).
3. **"Kya greedy settlement algorithm actually optimal hai (fewest
   possible transactions)?"** Hamesha nahi — transactions ki true minimum
   number nikalna ek set-partition style problem ke equivalent hai aur
   generally NP-hard hai (aapko debtors/creditors ke subsets search karne
   padenge jinke amounts exactly combine ho sakein). Greedy
   largest-vs-largest match ek good, fast, practical approximation hai
   aur yahi yahan expect kiya jaata hai; NP-hardness ko explicitly name
   karna bina solve kiye ek strong signal hai.
4. **"Ek 'by shares' split kaise add karoge (jaise, ek roommate ke 2
   shares, doosre do ka 1-1 share)?"** Ek `SharesSplit < SplitStrategy`
   add karo jahan `params` har user ko ek share count se map karta hai,
   aur `compute_shares` `total` ko `share / total_shares` se
   proportionally divide karta hai — `Expense`, `Group`, ya kisi bhi
   doosri strategy mein zero changes, jo Step 4 ke Strategy pattern
   decision ka direct payoff hai.
5. **"Ek user ko recorded expense dispute ya edit karne kaise handle
   karoge?"** Edits ko "purane expense ke balance deltas reverse karo,
   phir naya apply karo" (Step 6 dekho) ke roop mein treat karo instead of
   shares ko in-place mutate karna — yeh aapko ek natural audit trail bhi
   deta hai agar aap original aur correction dono ko separate `Expense`
   records ke roop mein rakhte ho ek `superseded_by` link ke saath.
6. **"Agar ek user non-zero balance ke saath group chhod de toh kya
   hoga?"** Yeh ek product decision hai, class-design ka nahi: ya toh
   removal ko block karo jab tak `balance_for(user)` zero nahi ho jaata,
   ya user ko ek "ghost member" ke roop mein rakho (`@balances` aur
   `simplify_debts` output mein retained rehta hai lekin aage ke naye
   expenses se excluded hai) jab tak settle nahi ho jaata — dono options
   ko name karna worth hai, silently ek pick karne ke bajaye.

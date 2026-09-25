# Design an ATM Machine (Object-Oriented Design)

## Problem Statement

"Design an ATM. User card insert karta hai, PIN enter karta hai, aur cash
withdraw kar sakta hai, money deposit kar sakta hai, apna balance check kar
sakta hai, ya funds transfer kar sakta hai. Machine ke paas ek physical cash
inventory hai jisse wo dispense karti hai. Wrong PINs, insufficient balance,
aur machine ke paas withdrawal fulfill karne ke liye kaafi cash na hone jaise
cases handle karo."

Vending machine ki tarah, ATM ka user-facing flow bhi (card → PIN →
transaction) naturally ek state machine hai, isliye bahut se candidates
wahin ruk jaate hain aur ise "same question again" treat karte hain. Jo
cheez ek strong answer ko yahan actually differentiate karti hai wo hai
**transaction** wala side: withdraw, deposit, check-balance, aur transfer
independent operations hain jo sabko uniformly log, potentially retry, aur
execute karna hota hai — aur yahi exactly **Command pattern** ke liye hai,
aur yeh vending machine ke State pattern se ek genuinely different pattern
hai, chahe dono problems "sunne me similar" lagen. Yeh recognize karna ki
yeh question ek second pattern chahta hai jo pehle wale ke upar layer ho,
pehle wale ka repeat nahi, yehi wo signal hai jo interviewer dhundh raha
hota hai.

## Step 1: Clarify Requirements

**Functional Requirements**
- User card insert karta hai aur PIN enter karta hai; koi bhi transaction
  allow karne se pehle machine isko account ke against validate karti hai.
- Supported transactions: cash withdraw, cash deposit, balance check,
  dusre account me transfer.
- Machine ke paas ek physical cash inventory hai (denominations aur
  counts) jisse wo withdrawals dispense karti hai.
- Ek withdrawal ko **do independent cheezon** ke against validate hona
  chahiye: account ka balance, aur machine ki us amount ko available
  denominations me physically dispense karne ki ability.
- Wrong PIN entries limited hain; N consecutive failures ke baad card
  lock ho jaata hai.

**Non-Functional Requirements**
- **Security**: PIN kabhi bhi plaintext me store ya compare nahi hona
  chahiye — isko rest me hashed hona chahiye, aur validate raw digits se
  nahi, hashes compare karke hona chahiye. Yeh ek real point hai jo
  interviewers probe karte hain, sirf boilerplate nahi.
- **Uniform transaction handling**: ATM ke core loop me ek growing
  `if operation == :withdraw ... elsif operation == :deposit` conditional
  nahi hona chahiye — har transaction type ek self-contained object hona
  chahiye jiska common execution interface ho, taaki naye transaction
  types, logging, aur retries — sab ATM ke dispatch logic ko touch kiye
  bina plug in ho jaayen.
- **Do distinct failure modes ke under correctness**: "account ke paas
  kaafi paisa nahi hai" aur "machine ke paas kaafi physical cash nahi hai"
  — yeh do different failures hain jinke causes aur recovery paths bhi
  different hain — design inhe ek generic "insufficient funds" error me
  conflate nahi kar sakta.
- **Extensibility**: ek naya transaction type add karna (jaise, bill
  payment) ya ek naya state (jaise, out-of-service) sirf ek class add
  karke possible hona chahiye, ATM ke core flow ko edit kiye bina.

## Step 2: Identify Core Objects / Entities

- **Account** — balance aur identity; kisi specific card se independent.
- **Card** — card number aur ek linked `Account`, plus ek hashed PIN aur
  failed-attempt count; jo cheez physically machine me insert hoti hai.
- **ATMState** (abstract) → `IdleState`, `CardInsertedState`,
  `PinEnteredState`, `TransactionInProgressState`, `OutOfServiceState` —
  yeh govern karta hai ki machine abhi kaunse actions accept karti hai
  (card insert, PIN enter, transaction select).
- **Transaction** (abstract, Command) → `Withdraw`, `Deposit`,
  `CheckBalance`, `Transfer` — har ek ek self-contained command object hai
  jiska common `#execute` interface hai, jisme jo bhi data usko chahiye
  (amount, transfer ke liye target account, etc.) hold hota hai.
- **CashDispenser** — machine ki physical cash inventory; ek requested
  amount ke liye denomination breakdown compute karta hai aur track karta
  hai ki actually kya dispense hua hai.
- **TransactionLog** — har executed `Transaction` ko record karta hai, ek
  natural extension jab transactions inline logic ke bajaye objects ban
  jaate hain.
- **ATM** — state orchestrate karta hai + current `Card` hold karta hai,
  transaction execution ko `Transaction` commands ko delegate karta hai.

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
  `TransactionInProgressState` `ATMState` se **inherit** karte hain (is-a).
- `Withdraw`/`Deposit`/`CheckBalance`/`Transfer` `Transaction` se
  **inherit** karte hain (is-a) — Command pattern ke concrete commands.
- `Card` `Account` ke saath **associate** hota hai (ek card ek account ko
  refer karta hai lekin uski lifecycle own nahi karta — account close
  karne se purane cards automatically destroy nahi hote, unhe invalidate
  kar diya jaata hai).
- `ATM` apni `CashDispenser` aur `TransactionLog` ko **compose** karta hai;
  jo bhi `Card` abhi insert hai usse transiently **associate** hota hai.

## Step 4: Design Decisions & Patterns Used

**Login flow ke liye State pattern, vending machine jaise hi reason se.**
"PIN enter karna" ya "transaction select karna" ka matlab bilkul isi baat
par depend karta hai ki card insert hai ya nahi, PIN abhi tak verify hua
hai ya nahi, aur koi transaction already mid-flight hai ya nahi. Same
shape, same justification jaise `04_vending_machine.md` me — yahan poora
repeat nahi kiya gaya, kyunki yeh us naye idea ka hissa nahi hai jo yeh
problem test kar rahi hai.

**Transactions ke liye Command pattern — asli naya idea.** Naive version
ek symbol par dispatch karta hai:

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

Iske sirf ek lambi conditional hone se aage do real problems hain: (1) har
naye transaction type ka matlab hai `ATM` ko khud edit karna, aur (2) ek
operation ko log, retry, ya undo karne ke liye koi natural jagah nahi hai —
har branch ko individually wrap karna padega. Har transaction ko ek
`Transaction` object bana kar `#execute(atm)` ke saath model karna dono
fix kar deta hai: ATM ka dispatch bhi `transaction.execute(self)` ban jaata
hai chahe type kuch bhi ho, `TransactionLog` kisi bhi `Transaction` ko
uniformly record kar sakta hai (usko sirf common interface chahiye), aur
future ka "retry failed transaction" feature bas usi command object par
`#execute` phir se invoke karna hai — jo conditional version me free me
nahi milta.

**`Withdraw` ko do independent cheezein kyun check karni chahiye, aur yeh
implementation detail nahi ek design decision kyun hai.** `Account#balance`
aur `CashDispenser` ki physical inventory — yeh do separate sources of
truth hain jo ek withdrawal ko independently fail kar sakte hain: ek
account ke paas $500 ho sakte hain lekin machine ke paas sirf ek $20 ka
note bacha ho (isse $500 dispense nahi ho sakta), ya machine fully stocked
ho sakti hai lekin account ke paas sirf $10 ho. Inhe ek "insufficient
funds" check me conflate karne se do cases me se ek me galat ya
misleading error milega (user ko batana ki unka *account* short hai jab
actually *machine* short hai — yeh ek real support-call-generating bug
hai). `Withdraw#execute` deliberately `account` aur `dispenser` ko
separately check karta hai aur batata hai ki kaunsa fail hua.

**PINs kabhi bhi plaintext me compare kyun nahi hote.** `Card` `pin_hash`
store karta hai, `pin` nahi; `pin_valid?` input ko hash karke hashes
compare karta hai. Yeh sirf "best practice" filler nahi hai — jo
interviewer "PIN kaise validate karoge" poochta hai, wo directly probe
kar raha hai ki kya aap raw PINs store/compare karoge, jo ek real ATM
design me ek genuine security defect hai, koi stylistic nitpick nahi.

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

**Isko use karna:**

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

Upar wala example jaan-bujh kar haath se trace karne layak hai: $230 ke
liye chahiye `2x$100 + 1x$20 + $10` — lekin drawer me koi $10 ka note nahi
hai, isliye `breakdown_for` `remaining = 10` non-zero chhod deta hai aur
sahi tareeke se `nil` return karta hai, matlab `can_dispense?(230)`
`false` hai aur withdrawal `"machine cannot dispense this amount"` ke
saath reject ho jaata hai, chahe account ke paas $500 hain aur machine ke
paas total $740 hain. Yeh bilkul wahi "physically can't dispense" edge
case hai jo niche call out kiya gaya hai.

## Step 6: Edge Cases & Extensibility

- **Insufficient account balance vs. insufficient machine cash — do
  different failures, aur code inke liye do different messages return
  karta hai.** `Withdraw#execute` pehle `account.balance` check karta
  hai, phir `atm.dispenser.can_dispense?` — aur batata hai ki kaunsa fail
  hua. Inhe ek generic error me collapse karna sabse common shortcut hai
  jo candidates time pressure me lete hain, aur yehi bilkul wo distinction
  hai jise yeh question probe karne ke liye design kiya gaya hai.
- **Ek withdrawal jo balance ke against valid hai lekin available
  denominations me dispensable nahi.** Upar explicitly walk through kiya
  gaya hai ($230 against $100/$50/$20 notes, is particular trace me koi
  $50 nahi) — `breakdown_for` greedy algorithm ko fail closed hona chahiye
  (`nil` return karna, kuch bhi dispense na karna) partial/wrong amount
  dispense karne ke bajaye.
- **Wrong PIN retry limits.** `Card#pin_valid?` failure par
  `failed_attempts` increment karta hai aur success par reset kar deta
  hai; `Card#locked?` insertion par (`IdleState#insert_card`) aur ek
  failed attempt ke baad `CardInsertedState#enter_pin` ke andar — dono
  jagah check hota hai, aur lock hote hi card ko `IdleState` par wapas
  eject kar deta hai, na ki usko mid-authentication me atka choD deta hai.
- **Greedy denomination algorithm arbitrary denomination sets ke liye
  hamesha optimal/correct nahi hota** (yeh standard bill sets jaise
  100/50/20/10/5/1 ke liye kaam karta hai, lekin ek pathological
  denomination set greedy ko fail karwa sakta hai jahan ek smarter
  combination succeed ho jaata). Yeh mention karna worth hai ki yeh
  classic "coin change" algorithm jaisi hi problem class hai, aur real
  ATMs specifically denominations ko constrain karte hain taaki greedy
  hamesha work kare.
- **Multiple failed transactions se log me noise inflate hona.** Chunki
  har `Transaction` (successful ho ya na ho) `atm.log.record` se uniformly
  logged hoti hai, yeh free me mil jaata hai, koi special handling ki
  zaroorat nahi — Command pattern ka ek aur payoff.

## Follow-up Questions an Interviewer Might Ask

1. **"Ek card se linked multiple accounts (checking vs. savings) kaise
   support karoge?"** `Card#account` ko `Card#accounts` (ek list) me
   change karo, state flow me ek "account selection" step add karo (ek
   naya state ya `select_transaction` par ek parameter), aur har
   `Transaction` ko implicitly "the" account use karne ke bajaye ek
   explicit account reference lena chahiye — `Transaction` classes
   already constructor argument ke roop me `account` lete hain, isliye
   yeh mostly change karta hai ki *kaun* usko select karta hai, commands
   khud nahi.
2. **"Transaction execution ko machine ka power mid-dispense jaane ke
   against safe kaise banaoge?"** Yeh is problem ka standout follow-up
   hai: `Withdraw#execute` abhi do separate steps me cash dispense karta
   hai aur account debit karta hai — inke beech ek crash ya to bina
   debit kiye dispense kar deta hai (bank ka paisa lose), ya bina
   dispense kiye debit kar deta hai (customer ka paisa lose). Fix yeh hai
   ki withdraw karne ki *intent* ko (amount, account, breakdown) durably
   log karo, dispenser ya account ko touch karne se pehle, phir restart
   par reconcile karo yeh check karke ki kaunsa step actually complete
   hua — ek idempotency/recovery pattern. Real bank scale par yeh ATM,
   core banking ledger, aur cash-management system ke across ek
   distributed transaction / saga problem ban jaata hai — isko explicitly
   naam se bulana worth hai as LLD/HLD boundary, aur us side ko scale par
   kaise handle kiya jaata hai iske liye
   `System_Design/02_Interview_Questions/14_payment_system.md` point
   karna.
3. **"Bill payment ya check deposit ko naye transaction types ke roop me
   kaise add karoge?"** `BillPayment < Transaction` /
   `CheckDeposit < Transaction` add karo jo `#execute` implement karein —
   `ATM` ke dispatch logic ya `TransactionLog` me zero changes, jo Step 4
   me choose kiye gaye Command pattern ka direct payoff hai.
4. **"Yeh vending machine ke design se kaise different hai?"** Dono apne
   front-facing flow ke liye State use karte hain, lekin ATM ko additionally
   apne transactions ke liye Command chahiye kyunki yahan transactions
   richer hain (logging, retries, aur eventually undo/reversal chahiye)
   aur zyada varied hain (chaar independent operations vs. vending machine
   ka single "dispense" action) — yeh dikhane ka ek achha moment hai ki
   aap samajhte ho ek pattern *kyun* apply hota hai, sirf yeh nahi ki hota
   hai.
5. **"Isko test kaise karoge?"** `CashDispenser#breakdown_for` ko various
   drawer contents ke against exhaustively unit-test karo (including
   wo case jahan exact change nahi ban sakta), har `Transaction` subclass
   ke `#execute` ko stub accounts/dispensers ke against unit-test karo,
   aur poore `ATM` state flow ko integration-test karo (wrong PIN →
   lockout, correct PIN → withdraw → eject) `ATMState`s ke beech transition
   bugs pakadne ke liye.
6. **"Agar interviewer fraud detection add karne ko kahe (jaise, unusual
   withdrawal patterns flag karna) to kya hoga?"** Yeh naturally ek
   decorator ya ek observer ban jaata hai transaction execution ke ird
   gird — `Transaction#execute` ko wrap karo (ya `TransactionLog#record`
   ko `FraudMonitor` ko notify karwao) har `Transaction` subclass ke andar
   pattern-detection logic embed karne ke bajaye, taaki commands khud
   simple rahen aur fraud logic centralized aur independently testable
   rahe.

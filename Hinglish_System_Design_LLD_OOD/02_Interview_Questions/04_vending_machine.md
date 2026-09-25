# Design a Vending Machine (Object-Oriented Design)

## Problem Statement

"Design a vending machine. Isme items ka ek inventory hota hai, har ek ka
apna price hota hai. User coins insert karta hai, ek item select karta hai,
aur machine ya to item dispense karke change return karti hai, ya selection
reject kar deti hai agar paisa kam hai ya item sold out hai. User item
select karne se pehle refund bhi request kar sakta hai."

Yeh **State pattern** ka textbook interview question hai, aur yeh jaan-bujh
kar hai — poori specification hi yeh hai ki "jab aap X karte ho to kya hota
hai, yeh depend karta hai machine abhi kya kar rahi hai us par." Coin insert
karne ka matlab item select hone se pehle aur baad me alag hota hai; refund
request karna idle state me aur mid-dispense me alag matlab rakhta hai. Jo
candidate `insert_coin`, `select_item`, aur `refund` ko teen methods bana
deta hai jisme har ek ke andar ek `case @state` hai, wo dikha raha hai ki
usne is question ke peeche wala pattern pehchana hi nahi — chahe uska code
technically happy path ke liye sahi output produce kar raha ho.

## Step 1: Clarify Requirements

**Functional Requirements**
- Machine ek inventory hold karti hai: item code → product, price, remaining
  count.
- User coins insert karta hai, jisse balance accumulate hota hai.
- User code se ek item select karta hai.
- Agar balance ≥ price hai aur item stock me hai, machine item dispense
  karke change (balance − price) return karti hai.
- Agar balance < price hai, selection reject ho jaata hai (ya simply tab
  tak fulfill nahi hota jab tak aur money insert na ho — inme se ek pick
  karo aur usko explicitly state karo).
- Agar item sold out hai, selection reject ho jaata hai chahe balance
  kuch bhi ho.
- User apna inserted balance refund request kar sakta hai, lekin sirf tab
  tak jab tak item dispense start nahi hua hai.

**Non-Functional Requirements**
- **Methods me scattered `case @state` nahi hona chahiye.** Yahi wo
  requirement hai jiske liye yeh question exist karta hai:
  `insert_coin`, `select_item`, `dispense`, aur `refund` — inme se har ek
  ka behavior machine ki current state par depend karna chahiye, aur yeh
  behavior *state ke andar* hona chahiye, na ki ek monolithic
  `VendingMachine` class ke andar ek conditional ke roop me.
- **Single responsibility**: `VendingMachine` shared data (inventory,
  balance) hold karti hai aur har user action ko apni current state ko
  delegate karti hai; usko khud yeh decide nahi karna chahiye ki "abhi kya
  allowed hai."
- **Extensibility**: ek naya state add karna (jaise, `OutOfServiceState`)
  ya koi naya machine-wide rule add karna sirf ek state class add/edit
  karke possible hona chahiye, har existing method ko touch kiye bina.
- **Sequencing ke under correctness**: coin → select → dispense → change
  sequence ke poore flow me money aur inventory kabhi lose ya double-count
  nahi honi chahiye, chahe koi step beech me reject ho jaaye.

## Step 2: Identify Core Objects / Entities

- **VendingMachineState** (abstract) → `IdleState`, `HasMoneyState`,
  `DispensingState`, `SoldOutState` — har situation ke liye `insert_coin`,
  `select_item`, `dispense`, aur `refund` ka behavior.
- **Inventory** — machine ka stock: item code se `Product`, price, aur
  remaining count ka map; machine kis state me hai isse independent.
- **Product** — ek simple value object: name aur price (yeh `Inventory`
  ke count-tracking se separate rakha gaya hai taaki "item kya hai" aur
  "kitne bache hain" conflate na ho jaaye).
- **VendingMachine** — `current_state`, `balance`, aur `inventory` hold
  karti hai; har public action `current_state` ko delegate hoti hai.

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
- `IdleState`/`HasMoneyState`/`DispensingState`/`SoldOutState`
  `VendingMachineState` se **inherit** karte hain (is-a) — same interface,
  per method different behavior.
- `VendingMachine` apni `current_state`, apni `Inventory`, aur implicitly
  stock me har `Product` ko **compose** karti hai — inme se koi bhi machine
  se independently exist nahi karta.
- `Inventory` har item code ko ek `Product` ke saath **associate** karti
  hai — product catalog aur per-slot count related hain lekin distinct
  concerns hain, jo convenience ke liye ek composed object me rakhe gaye
  hain.

## Step 4: Design Decisions & Patterns Used

**State kyun, aur yeh naive conditional version se better kyun hai.**
Naive `insert_coin` ko imagine karo:

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

Ab imagine karo ki `select_item`, `dispense`, aur `refund` — in teeno ko
apna khud ka isi four-way branch chahiye. Har naye state ke liye (say,
`MaintenanceState` add karna) matlab hai ki *chaaro* methods me jaa kar
branch add karna, aur ek bhool jaana easy hai — yeh classic tareeka hai
jisse in systems me bugs grow karte hain. State pattern ke saath, har
state class apne *khud* ke situation ke liye chaaro methods implement
karti hai; `VendingMachine` ke methods one-line delegations ban jaate hain
(`@state.insert_coin(self, amount)`), aur ek naya state add karne ka
matlab hai sirf ek naya class likhna. Interface (`insert_coin`,
`select_item`, `dispense`, `refund`) fixed hai; sirf har state *kya karti
hai* usse woh varies karta hai — bilkul yahi "state pattern" ka matlab hai.

**Yeh problem jo design decision explicit karwati hai: `DispensingState`
ke dauran `insert_coin` kya karega?** Spec yeh nahi batati, aur ek strong
candidate isse silently guess karne ke bajaye explicitly call out karta
hai. Do reasonable answers hain: (a) coin ko outright reject kar do
(coin return se wapas kar do, balance me add mat karo) kyunki machine
mid-transaction hai aur usko aur input accept nahi karna chahiye, ya
(b) usko accept karke *agli* purchase ke liye balance me add kar do. Yeh
file (a) choose karti hai — `DispensingState#insert_coin` reject karta hai
— kyunki isse "machine par abhi kitna paisa hai" ek dispense ke dauran
unambiguous rehta hai; interview me isko zor se bolo chahe aap (b) choose
karo.

**`Inventory` `VendingMachine` se ek separate object kyun hai, machine par
sirf ek hash kyun nahi.** Stock rules (yeh stock me hai ya nahi, dispense
par decrement karna) logic hai, sirf data nahi — inhe `Inventory` par
rakhne ka matlab hai ki `SoldOutState` transitions aur stock checks ek hi
method (`in_stock?`) se guzarte hain, na ki har state directly
`@machine.slots[code][:count]` me reach karti hai. Isse yeh bhi matlab
hai ki ek smarter inventory swap karna (jaise, jo expiry dates track
karti hai) kisi bhi state class ko touch nahi karega.

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

**Isko use karna — ek full worked transition sequence:**

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

- **Insufficient money insert karna.** `HasMoneyState#select_item`
  `balance < price` check karta hai aur bina state change kiye reject
  karta hai, isliye user ka balance preserved rehta hai aur wo aur coins
  add kar sakta hai — yahi exact reason hai ki `insert_coin`
  `HasMoneyState` me accepted rehna chahiye (yeh sense nahi banega ki
  sirf isliye refund force kiya jaaye kyunki pehla coin kaafi nahi tha).
- **Sold-out item select karna.** `SoldOutState` isko handle karta hai,
  jo `DispensingState` me transition hone ke bajaye reach hota hai —
  critically, user ka balance *lose* nahi hota; `SoldOutState`
  `HasMoneyState` par wapas route karta hai (agar balance abhi bhi hai)
  taaki wo kuch aur pick kar sake, na ki silently unka paisa bina kisi
  forward path ke rakh le.
- **Item select karne ke baad refund request karna.** `DispensingState#refund`
  explicitly refuse kar deta hai — ek baar dispensing shuru ho jaaye,
  transaction committed hai. Yeh boundary (selection vs. dispensing ko
  separate states banana) hi "kya main abhi refund kar sakta hoon" ko ek
  timing-dependent race ke bajaye ek unambiguous question banata hai.
- **Exact-change-only situations.** Upar model nahi kiya gaya lekin ek bahut
  common follow-up hai: machine par ek `exact_change_only?` check add karo
  (available coin denominations ke basis par jo change bana sakte hain —
  dekho Follow-up 1) jisko `HasMoneyState#select_item` consult kare kisi
  bhi purchase ko allow karne se pehle jisme aisa change chahiye jo machine
  produce nahi kar sakti.
- **Coin jam / mechanical failure.** Yeh naturally ek `OutOfServiceState`
  add karne me map hota hai jo har action reject kare, shayad `refund`
  chhod kar — bilkul wahi extensibility case jiske liye State pattern
  designed hai: ek naya class, existing states me zero changes.

## Follow-up Questions an Interviewer Might Ask

1. **"Multiple denominations support kaise karoge aur exact change kaise
   calculate karoge?"** Denomination → count ka ek `CashInventory` track
   karo (`Inventory` jaisa hi lekin coins/notes ke machine ke paas hone
   ke liye), aur change ek greedy algorithm se compute karo: denominations
   ko descending sort karo, largest ke jitne available aur needed hain
   utne le lo, phir next-smallest par jaao, verify karo ki exact total
   ban sakta hai — agar nahi, sale refuse kar do (`exact_change_only?`)
   customer ko shortchange karne ke bajaye. Yeh ATM ke `CashDispenser`
   denomination-breakdown logic ko almost exactly mirror karta hai
   (dekho `05_atm_machine.md`).
2. **"Coins insert karne ke alternative ke roop me card payment kaise
   support karoge?"** Yeh deliberately State pattern se distinct ek
   **Strategy** pattern question hai: payment *method* (coins vs. card)
   "hum paisa kaise collect karein" ke liye ek pluggable algorithm hai,
   jabki machine ki *state* (idle, has-money, dispensing) is baat ke baare
   me hai ki "machine abhi kya kar rahi hai," chahe paisa kaise bhi aaya
   ho. Concretely, ek `PaymentMethod` interface introduce karo
   (`CoinPayment`, `CardPayment`) jisko har state ka `select_item`/purchase
   flow funds collect karne ke liye delegate kare — state machine ke
   transitions dono cases me identical rehte hain.
3. **"Agar do items ka price same ho lekin stock counts different ho to
   kya hoga?"** Koi special handling nahi chahiye — `Inventory` already
   har code ke liye count independently track karti hai; yeh actually
   test kar raha hai ki kahin aapne `Product` (price/name) ko per-slot
   stock count ke saath conflate to nahi kiya, jo design already avoid
   karta hai.
4. **"'Restock' admin operation kaise add karoge?"** `Inventory#restock(code,
   count)` add karo, aur optionally ek `AdminState` (ya ek simple guard jo
   customer-facing state machine se bilkul guzarta hi nahi, kyunki
   restocking koi customer transaction nahi hai) — yeh discuss karne
   layak hai ki admin operations same state hierarchy me belong karte hain
   ya ek bilkul separate concern me.
5. **"Isko test kaise karoge?"** Har state class ke chaaro methods ko ek
   stubbed/mocked `VendingMachine` ke against isolation me unit-test karo
   (jaise, assert karo ki `DispensingState#insert_coin` kabhi balance
   change nahi karta), phir ek real `VendingMachine` + `Inventory` par full
   sequences integration-test karo (coin → select → dispense → change,
   aur har rejection path) states ke beech transition bugs pakadne ke
   liye.
6. **"Mid-dispense machine ka power chala jaaye to kya hoga?"** `dispense`
   method abhi sequence me inventory decrement karta hai aur balance zero
   karta hai — un do lines ke beech ek crash ya to bina charge kiye
   inventory se ek item lose kar deta hai, ya bina dispense kiye charge
   kar deta hai. Isko flag karna aur ek idempotent/transactional fix
   describe karna (mutating state se pehle intended dispense ko log karo,
   restart par reconcile karo) ATM ki crash-recovery discussion
   (`05_atm_machine.md`) ki taraf ek achha bridge hai.

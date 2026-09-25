# Behavioral Design Patterns

Behavioral patterns ka focus hai **objects aapas mein kaise communicate
karte hain aur responsibility kaise distribute karte hain** — runtime par
algorithms swap karna, dependents ko changes ke baare mein notify karna,
internal state ke basis par behavior badalna, requests ko objects ke
roop mein encapsulate karna, ek request ko handlers ki chain se route
karna, aur ek algorithm ka skeleton subclasses ke beech share karna.
Agar creational patterns ka matlab hai "yeh object main kaise banaun" aur
structural patterns ka matlab hai "yeh objects saath mein kaise fit hote
hain," toh behavioral patterns ka matlab hai "kaun kya karta hai, aur woh
ek-doosre se kaise baat karte hain."

## Interview Tips

**Strategy** LLD interviews ke liye sabse zyada useful pattern hai, full
stop — yeh `case type` chains ka direct antidote hai, jo exactly wahi
mistake hai jo candidates ko Parking Lot jaise questions mein doobo deti
hai (dekho `02_Interview_Questions/01_parking_lot.md`). Agar interview se
pehle aapko sirf ek pattern deeply internalize karna hai, toh yehi karo.
**State** ek poore category ke prompts ka correct answer hai — jisme bhi
ek explicit status/mode field alag-alag behavior drive kar raha ho
(vending machines, ATMs, traffic lights, order lifecycles) — aur is
folder mein aage `04_vending_machine.md` aur `05_atm_machine.md` ko
directly power karta hai. **Observer** tab aata hai jab bhi prompt mein
"subscribers/watchers/listeners ko notify karo" involve ho. **Command**
aur **Chain of Responsibility** thode zyada systems-flavored LLD prompts
mein common hain (undo/redo, request pipelines, approval workflows).
**Template Method** ko recognize karna useful hai lekin yeh answer ka
star kam hi banta hai. **Visitor** sirf naam se jaanna kaafi hai — interview
mein live implement karna bahut hi rarely worth hota hai.

## Strategy

**Yeh kaunsa problem solve karta hai:** aapke paas same conceptual task
ko poora karne ke liye interchangeable algorithms/behaviors ka ek family
hai, aur is pattern ke bina woh family ek `case`/`if` chain ban jaata hai
jo directly us class mein bake ho jaata hai jise woh behavior chahiye —
matlab har naye variant ke liye us class ko edit karna padta hai, aur
class ko ab har variant ki details jaannni padti hain.

Yeh exactly wahi pattern hai jo parking lot design mein already kaam kar
raha hai. `Vehicle#spots_required(spot_type)` ek strategy method hai —
`Bike`, `Car`, aur `Van` isse alag-alag implement karte hain, aur
`ParkingLot#park` kabhi bhi vehicle type par branch nahi karta; yeh bas
jo bhi vehicle object hold kar raha hai usse poochta hai "yahan tumhe
kitne spots chahiye?" Har vehicle subclass khud ek spot-allocation
strategy *hai*, jo simply isse select hoti hai ki aap kaunsa object hold
kar rahe ho.

```text
   ParkingLot                     Vehicle (strategy interface)
   - park(vehicle)  ----uses---->  + spots_required(spot_type)
                                          ^        ^        ^
                                        Bike      Car      Van
                                      (needs 1) (needs 1) (needs 1 van_spot,
                                                            or 3 bike_spot)

   ParkingLot never branches on vehicle type — it just calls the method
   and lets whichever concrete strategy object is plugged in answer.
```

Follow-up jo parking lot file preview karti hai — pricing — usi pattern
ka doosra application hai:

```ruby
class PricingStrategy
  def calculate(ticket)
    raise NotImplementedError
  end
end

class HourlyPricing < PricingStrategy
  RATE_PER_HOUR = 2.0

  def calculate(ticket)
    hours = ((Time.now - ticket.entry_time) / 3600.0).ceil
    hours * RATE_PER_HOUR
  end
end

class FlatRatePricing < PricingStrategy
  def calculate(_ticket) = 15.0
end

class ParkingLot
  def initialize(pricing_strategy: HourlyPricing.new)
    @pricing_strategy = pricing_strategy
    # ...
  end

  def charge(ticket)
    @pricing_strategy.calculate(ticket)
  end
end

ParkingLot.new(pricing_strategy: FlatRatePricing.new)
# Swapping pricing models is a one-line change at construction time —
# ParkingLot's own code never changes.
```

### Isko kab NAHI use karna chahiye

Agar genuinely sirf ek hi algorithm hai, aur doosre ki expect karne ki
koi credible wajah nahi hai, toh Strategy unnecessary indirection hai —
ek plain method zyada clear hai. Isse introduce karne ka signal ya toh
(a) already ek se zyada variant exist karta hai, ya (b) aap ek concrete,
likely-next variant point out kar sakte ho (jaise parking lot file
pricing ke saath karti hai) — na ki "yeh kabhi kisi tarah vary karna pad
sakta hai."

## Observer

**Yeh kaunsa problem solve karta hai:** ek object ke state change ko
doosre objects ke ek open-ended, changeable set mein reactions trigger
karni hain, bina pehle object ko yeh jaanne ki zaroorat ke ki iski
parwaah karne wali har cheez ki concrete class kya hai.

```ruby
class Stock
  def initialize(symbol, price)
    @symbol = symbol
    @price = price
    @observers = []
  end

  def subscribe(observer)
    @observers << observer
  end

  def unsubscribe(observer)
    @observers.delete(observer)
  end

  def price=(new_price)
    @price = new_price
    notify_observers
  end

  private

  def notify_observers
    @observers.each { |o| o.update(@symbol, @price) }
  end
end

class PriceDisplay
  def update(symbol, price)
    puts "#{symbol} is now $#{price}"
  end
end

class PriceAlert
  def initialize(threshold)
    @threshold = threshold
  end

  def update(symbol, price)
    puts "ALERT: #{symbol} crossed #{@threshold}!" if price >= @threshold
  end
end

stock = Stock.new("ACME", 100)
stock.subscribe(PriceDisplay.new)
stock.subscribe(PriceAlert.new(120))

stock.price = 125
# => "ACME is now $125"
# => "ALERT: ACME crossed 120!"
```

Ruby ek built-in `Observable` module deta hai (`require "observable"`)
jo aapko `changed`/`notify_observers`/`add_observer` free mein deta hai,
lekin interviews mein utna hi common hai ki aap seedha subscribe/notify
list implement kar do, jaise upar dikhaya gaya hai — yeh bas chand lines
hain aur yeh dikhata hai ki aapko mechanics samajh mein aate hain, sirf
ek stdlib module ka naam lene se zyada.

Yeh exactly same shape hai jaise "jab kisi auction ka price badle toh
sabhi watchers ko notify karo" ya "jab koi YouTube channel naya video
upload kare toh sabhi subscribers ko notify karo" — koi bhi one-to-many
"cheez badli, sabko batao jinhe parwaah hai" scenario.

### Isko kab NAHI use karna chahiye

Agar interested party sirf ek hi hai, toh ek direct method call
subscribe/notify machinery se simpler hai. Yeh bhi dhyaan rakho ki
Observer kahin performance ya ordering problem ko hide na kar raha ho —
agar notification order matter karta hai, ya agar ek observer ka
`#update` throw kar sakta hai aur usse doosron ko block karna chahiye ya
nahi, yeh explicitly handle karna padega; Observer akele isse solve nahi
karta.

## State

**Yeh kaunsa problem solve karta hai:** kisi object ka behavior internal
status/mode ke basis par badalna zaroori hai, aur naive approach — ek
`status` field jo har method mein `if`/`case` se check hota hai — yehi
conditional poori class mein failaa deta hai aur har naye state ya har
naye state-aware method ke saath aur bura hota jaata hai.

Yeh Vending Machine ya ATM ke liye exactly sahi pattern hai — dekho
`02_Interview_Questions/04_vending_machine.md` aur `05_atm_machine.md`,
dono directly State use karte hain instead of ek `status` field jiske
conditionals uske methods mein scattered hon.

```ruby
class TrafficLightState
  def next
    raise NotImplementedError
  end

  def name
    raise NotImplementedError
  end
end

class RedState < TrafficLightState
  def next = GreenState.new
  def name = "red"
end

class GreenState < TrafficLightState
  def next = YellowState.new
  def name = "green"
end

class YellowState < TrafficLightState
  def next = RedState.new
  def name = "yellow"
end

class TrafficLight
  def initialize
    @state = RedState.new
  end

  def advance
    @state = @state.next
  end

  def current = @state.name
end

light = TrafficLight.new
light.current   # => "red"
light.advance
light.current   # => "green"
light.advance
light.current   # => "yellow"
```

```text
   RedState --next--> GreenState --next--> YellowState --next--> RedState
   (cycle: each state object knows only what it transitions to next —
    TrafficLight itself holds no transition logic at all)
```

Naive version ke saath contrast karo: `def advance; case @status; when
:red then @status = :green; when :green then @status = :yellow; when
:yellow then @status = :red; end; end` — 3 states ke liye functionally
similar hai, lekin har additional state-dependent method
(`can_cars_go?`, `duration_seconds`) ko apna parallel `case @status`
block chahiye hoga. State ke saath, in mein se har ek state classes par
ek method ban jaata hai instead, aur conditionals kabhi `TrafficLight`
mein accumulate nahi hote.

### Isko kab NAHI use karna chahiye

Agar sirf do states hain aur ek trivial transition hai (jaise, ek
boolean `open`/`closed` toggle), toh ek plain enum/boolean field state
classes ke set se simpler hai. State tabhi apna kaam saabit karta hai
jab aapke paas teen ya usse zyada states ho, transitions mein real logic
ho, ya multiple methods ho jinka behavior current state par depend karta
ho — tabhi alternative (conditionals jo methods ke across duplicate hote
hain) genuinely painful ban jaata hai.

## Command

**Yeh kaunsa problem solve karta hai:** aap ek request ya action ko
first-class object ki tarah treat karna chahte ho — taaki usse queue,
log, pass around, undo, ya redo kiya ja sake — instead of ek immediate
direct method call jo baad mein apna koi trace nahi chhodta.

```ruby
class Command
  def execute
    raise NotImplementedError
  end

  def undo
    raise NotImplementedError
  end
end

class InsertTextCommand < Command
  def initialize(document, text, position)
    @document = document
    @text = text
    @position = position
  end

  def execute
    @document.insert(@text, @position)
  end

  def undo
    @document.delete(@position, @text.length)
  end
end

class TextEditor
  def initialize(document)
    @document = document
    @history = []
  end

  def run(command)
    command.execute
    @history << command
  end

  def undo_last
    return if @history.empty?

    @history.pop.undo
  end
end

document = Document.new
editor = TextEditor.new(document)
editor.run(InsertTextCommand.new(document, "hello", 0))
editor.undo_last   # calls InsertTextCommand#undo, removing "hello" again
```

Same shape ek remote control ko bhi cover karta hai jo physical buttons
ko actions se map karta hai (`LightOnCommand`, `LightOffCommand` runtime
par ek button slot ko assign kiye jaate hain, `RemoteControl` class ko
change kiye bina swappable), ya ek job queue jaha har queued item ek
Command hai jo baad mein execute hone ka wait kar raha hai, possibly
kisi doosre thread ya process par.

### Isko kab NAHI use karna chahiye

Agar aapko kabhi kisi action ko queue, log, delay, ya undo nahi karna
hai — yeh bas ek direct method call hai, immediately — toh usse Command
object mein wrap karna pure ceremony hai. Iski zaroorat ka signal yeh
hai: requirements mein "undo," "queue," "replay," ya "har action ka log
rakho" jaise words ka aana.

## Chain of Responsibility

**Yeh kaunsa problem solve karta hai:** ek request ko several possible
handlers mein se exactly ek ko handle karna hai, aur kaunsa handle karega
yeh runtime conditions par depend karta hai — is pattern ke bina, yeh
decision ek bada `if`/`elsif` ban jaata hai jo har handler ke baare mein
jaanta hai aur jab bhi koi handler add, remove, ya reorder ho toh usse
edit karna padta hai.

```ruby
class TicketHandler
  attr_accessor :next_handler

  def handle(ticket)
    if can_handle?(ticket)
      resolve(ticket)
    elsif @next_handler
      @next_handler.handle(ticket)
    else
      puts "No handler available for: #{ticket}"
    end
  end
end

class Tier1Handler < TicketHandler
  def can_handle?(ticket) = ticket[:severity] == :low
  def resolve(ticket) = puts "Tier1 resolved: #{ticket[:issue]}"
end

class Tier2Handler < TicketHandler
  def can_handle?(ticket) = ticket[:severity] == :medium
  def resolve(ticket) = puts "Tier2 resolved: #{ticket[:issue]}"
end

class Tier3Handler < TicketHandler
  def can_handle?(ticket) = ticket[:severity] == :high
  def resolve(ticket) = puts "Tier3 resolved: #{ticket[:issue]}"
end

tier1 = Tier1Handler.new
tier2 = Tier2Handler.new
tier3 = Tier3Handler.new
tier1.next_handler = tier2
tier2.next_handler = tier3

tier1.handle(severity: :medium, issue: "Login broken")
# => "Tier2 resolved: Login broken"
# (Tier1 passed it along because can_handle? returned false)
```

```text
   request --> Tier1Handler --(can't handle)--> Tier2Handler --(can't handle)--> Tier3Handler
                    |handles it                       |handles it                     |handles it
                    v                                  v                               v
                 resolved                           resolved                        resolved

   The sender only ever talks to Tier1 — it doesn't know or care how
   many handlers exist downstream, or which one ends up handling it.
```

### Isko kab NAHI use karna chahiye

Agar yeh hamesha statically obvious hai ki ek diye gaye request ko
kaunsa single handler process karega, toh chain bina kisi benefit ke
indirection add karti hai — us handler ko directly call karo. Chain of
Responsibility tabhi apna kaam saabit karta hai jab possible handlers ka
set, ya jis order mein unhe try kiya jaata hai, woh sender se
independently badal sakta ho — aur jab "koi handler ne accept nahi kiya"
ek valid, handled outcome hona chahiye.

## Template Method

**Yeh kaunsa problem solve karta hai:** several related classes ko steps
ki same overall sequence perform karni hai, lekin un mein se ek ya do
steps har class ke liye alag hain — aur is pattern ke bina, har class ya
toh poori sequence duplicate karti hai (chhoti variations ke saath andar
buried), ya sequence khud kisi caller mein rehti hai jise har class ke
specific steps jaannne padte hain.

**Strategy ke saath contrast:** Template Method inheritance use karta
hai aur algorithm ka *shape* base class mein fix kar deta hai, subclasses
ko sirf specific steps override karne deta hai. Strategy composition use
karta hai aur *poore* algorithm ko ek interchangeable object ki tarah
swap karta hai. Agar sirf ek step vary karta hai aur overall sequence
fixed hai, toh woh Template Method hai; agar poora algorithm swappable
hona chahiye, toh woh Strategy hai.

```ruby
class DataExporter
  # The template method: fixed sequence, not overridden by subclasses
  def export
    data = fetch_data
    formatted = format(data)
    write(formatted)
  end

  def fetch_data
    raise NotImplementedError
  end

  def format(data)
    raise NotImplementedError
  end

  def write(formatted)
    puts formatted
  end
end

class CsvExporter < DataExporter
  def fetch_data = [["id", "name"], [1, "Alice"], [2, "Bob"]]

  def format(data)
    data.map { |row| row.join(",") }.join("\n")
  end
end

class JsonExporter < DataExporter
  def fetch_data = [{ id: 1, name: "Alice" }, { id: 2, name: "Bob" }]

  def format(data)
    require "json"
    data.to_json
  end
end

CsvExporter.new.export
# id,name
# 1,Alice
# 2,Bob

JsonExporter.new.export
# [{"id":1,"name":"Alice"},{"id":2,"name":"Bob"}]
```

Dono exporters exact same `export` sequence share karte hain — fetch,
format, write — aur sirf `format` (aur is example mein `fetch_data`)
override karte hain. `write` dono ke beech as-is shared hota hai, jo
dikhata hai ki subclasses ko sirf woh steps override karne chahiye jo
actually alag hain.

### Isko kab NAHI use karna chahiye

Agar subclasses ko steps ka overall *order* badalna hai, sirf ek ya do
steps ka content nahi, toh Template Method ki fixed sequence aapke
against fight karti hai — Strategy (poora algorithm swap karo) ya plain
composition zyada fit baithega. Isse bhi avoid karo jab currently sirf ek
hi class woh sequence kar rahi ho — ek shared base class abstract steps
ke saath tab tak premature hai jab tak ek doosri, genuinely similar class
exist na kare.

## Visitor (recognize karna zaroori, live implement karna rarely worth)

Visitor ek algorithm ko us object structure se alag karta hai jispar yeh
operate karta hai: har baar jab aapko ek naya operation chahiye (jaise,
ek AST mein har node type mein `#export_to_xml` add karna) toh hierarchy
ki har class mein naya method add karne ke bajaye, aap ek `Visitor`
define karte ho jisme har class ke liye ek `visit_X` method hota hai, aur
har class ko ek single `#accept(visitor)` method milta hai jo bas sahi
`visit_` method mein wapas call karta hai. Naye operations naye Visitor
classes ban jaate hain, visited classes mein zero changes ke saath — yeh
Template Method/Strategy ka inverse trade-off hai, jaha hierarchy mein
naya *type* add karna expensive hota hai (har visitor ko naya `visit_`
method chahiye), lekin naya *operation* add karna cheap hai. Yeh real
compilers/AST tooling mein dikhta hai aur agar poocha jaaye toh iska naam
lena aur shape sketch karna aana chahiye, lekin yeh kaafi dense hai
(double-dispatch, har node type ke liye ek visitor interface) ki yeh
rarely woh pattern hota hai jo interviewer expect karta hai ki aap 45
minutes mein scratch se working code produce kar do.

## Quick Recall — Self-Test

1. **Parking lot design already Strategy kaha use karti hai, jabki file
   kabhi bhi yeh word explicitly use nahi karti?**
   `Vehicle#spots_required(spot_type)` — har subclass (`Bike`, `Car`,
   `Van`) isse alag-alag implement karta hai, aur `ParkingLot#park` isse
   polymorphically call karta hai bina kabhi vehicle type par branch
   kiye. Har vehicle subclass effectively ek spot-allocation strategy
   hai.

2. **Strategy aur Template Method ke beech concrete difference kya hai?**
   Strategy composition use karta hai aur poore algorithm ko ek
   interchangeable object ki tarah swap karta hai; Template Method
   inheritance use karta hai aur overall sequence ko ek base class mein
   fix kar deta hai, subclasses ko us fixed sequence ke andar sirf
   specific steps override karne deta hai.

3. **Ek class mein jab 3+ states aur several state-dependent methods hon,
   toh State ek `status` field aur `case` statements se better fit kyun
   hai?**
   Kyunki har naye state-dependent method ko apna parallel `case @status`
   block chahiye hoga jo class mein scattered hoga. State har state ka
   behavior uski apni class mein move kar deta hai, isliye ek naya state
   ya ek naya state-aware method add karna original class ke across
   conditionals ko multiply nahi karta.

4. **Requirements doc mein kaunsa tell batata hai ki aapko plain method
   call ke bajaye Command chahiye?**
   Words jaise "undo," "redo," "isse baad ke liye queue karo," ya "har
   action ka log rakho" — koi bhi cheez jisme action ko khud data ki
   tarah treat karna pade jise aap hold kar sako, sirf immediately
   execute karne ke bajaye.

5. **Chain of Responsibility mein, agar chain ka koi bhi handler request
   handle nahi kar pata toh kya hota hai, aur yeh kyun matter karta hai?**
   Request chain ke end tak unresolved gir jaata hai — design ko
   explicitly define karna padta hai ki phir kya hoga (log karo, raise
   karo, ek default fallback handler). Yeh isliye matter karta hai kyunki
   is case ko bhoolna requests ko silently drop kar deta hai bina kisi
   visible error ke.

6. **"Jab koi YouTube channel upload kare toh sabhi subscribers ko notify
   karo" ke liye Observer achha fit kyun hai, aur ek limitation kya hai
   jo yeh khud solve nahi karta?**
   Yeh isliye fit hai kyunki channel (subject) ko har subscriber ki
   concrete type jaanne ki zaroorat nahi — yeh bas jo bhi subscribed hai
   uspar `#update` call karta hai. Yeh notification ordering ya failure
   isolation khud solve nahi karta — agar ek observer ka `#update` raise
   karta hai, toh aapko explicitly decide karna padega ki isse baaki
   sabko block karna chahiye ya nahi.

7. **Visitor 45-minute interview mein rarely hand-write karne wala
   pattern kyun hai, chahe aap recognize kar lo ki yeh fit baithta hai?**
   Isme double-dispatch chahiye hota hai (har visited class ke liye ek
   `#accept` method plus visitor par har type ke liye ek `visit_X`
   method) jo time pressure mein correctly set up karne ke liye kaafi
   boilerplate hai — isse live build karne ke bajaye iska naam lena aur
   trade-off describe karna (naye operations add karna cheap, naye types
   add karna expensive) zyada behtar hai.

8. **Ek vending machine ke states hain Idle, HasMoney, Dispensing,
   OutOfStock. Ek sentence mein sketch karo ki State yaha boolean flag
   se better kyun fit hota hai.**
   Yaha do se zyada states hain jinke genuinely alag valid transitions
   aur behavior hain (jaise, `insert_coin` Idle se valid hai lekin
   Dispensing se nahi), jise ek single boolean represent nahi kar sakta —
   har state ko apna object chahiye jo define kare ki usse kya valid hai,
   exactly wahi problem jo State solve karta hai.

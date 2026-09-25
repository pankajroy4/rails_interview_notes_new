# Creational Design Patterns

Creational patterns iske baare mein hain ki **objects kaise create hote
hain** — specifically, object-creation logic ko har uss jagah mein leak
hone aur clutter karne se kaise roka jaaye jahan bhi naya object chahiye.
Iska tell yeh hai ki aapko in mein se ek pattern ki zaroorat hai: aap khud
ko `.new` calls ke around `if`/`case` logic likhte hue paate ho, ya ek
constructor jo 8 optional keyword arguments tak grow ho gaya hai, ya code
jo assume karta hai "in mein se hamesha ek hi hota hai" bina usko actually
enforce kiye.

## Interview Tips

Yahan diye gaye paanch patterns mein se, **Factory Method** wo hai jiske
liye aap LLD interview mein actually sabse zyada reach karoge — almost
har worked example (vehicles, payment methods, notification channels) mein
related subclasses ka ek family hota hai jinhe kisi input se instantiate
karna hota hai, aur "aap kaise decide karte ho kaunsi class instantiate
karni hai" ek natural follow-up question hai. **Singleton** bhi
constantly aata hai, lekin more often ek trap ki tarah — interviewers
poochte hain "kya aap isse Singleton banaoge?" yeh dekhne ke liye ki aap
uske downsides samajhte ho ya nahi, isliye nahi ki woh chahte hain aap
ek use karo. **Builder** ko cold jaanna worth hai kisi bhi "is object
mein bahut saara optional configuration hai" scenario ke liye.
**Abstract Factory** aur **Prototype** ke baare mein bahut kam poocha
jaata hai — inka shape aur canonical example itna achhe se jaano ki
explain kar sako, lekin expect mat karo ki interview pressure mein
scratch se ek design karna padega.

## Singleton

**Yeh kaunsa problem solve karta hai:** system mein kuch cheezein
genuinely aisi honi chahiye jinka exactly ek instance ho — ek single
application-wide logger, ek single configuration object, ek single
connection pool. Bina enforcement ke, kuch bhi codebase ke do parts ko
independently do `Config` objects construct karne se nahi rok sakta jo
quietly out of sync drift kar jaate hain.

```ruby
# Using Ruby's built-in Singleton module
require "singleton"

class AppConfig
  include Singleton

  attr_accessor :max_retries, :timeout_seconds

  def initialize
    @max_retries = 3
    @timeout_seconds = 30
  end
end

AppConfig.instance.max_retries        # => 3
AppConfig.instance.max_retries = 5
AppConfig.instance.max_retries        # => 5 (same instance everywhere)
AppConfig.new                         # => NoMethodError: private method 'new'
```

```ruby
# Hand-rolled version (what Singleton does under the hood) — worth knowing
# because interviewers sometimes ask you to implement it, not just use it
class Logger
  @instance_mutex = Mutex.new

  class << self
    def instance
      return @instance if @instance

      @instance_mutex.synchronize do
        @instance ||= new
      end
      @instance
    end

    private :new
  end

  def log(message)
    puts "[LOG] #{message}"
  end
end
```

Mutex ko notice karo — ek naive `@instance ||= new` true parallelism ke
under thread-safe nahi hota (do threads dono `@instance` ko `nil` dekh
sakte hain aur dono `new` call kar sakte hain). Isko unprompted mention
karna ek accha signal hai.

**Interviewers Singletons pe push back kyun karte hain.** Yeh woh pattern
hai jiske baare mein ek real opinion rakhna sabse zyada worth hai, sirf
uski definition jaanna nahi. Problems yeh hain:

- **Hidden global state.** Koi bhi code, kahin bhi, singleton ko read aur
  mutate kar sakta hai. Do unrelated classes iske through coupled ho
  sakti hain bina uss dependency ke kisi bhi class ke constructor ya
  method signature mein dikhe — aapko implementation padhna padta hai
  isko discover karne ke liye.
- **Testing harder ho jaata hai.** Kyunki instance shared hota hai aur
  typically process ki puri life ke liye memoized hota hai, ek test jo
  singleton ka state mutate karta hai, next test mein leak kar sakta hai
  jab tak aap usko reset karna yaad na rakho — flaky, order-dependent
  test suites ka ek classic source.
- **Yeh dependency injection na karne ka ek workaround hai.** Zyadatar
  time, "mujhe chahiye ki har object same config/logger dekhe" better
  solve hota hai uss object ko composition root pe (jaise app boot pe)
  ek baar construct karke aur jisko bhi chahiye usme pass karke — ek
  plain object, explicitly injected, test karne mein easier hota hai
  (ek fake swap in karna) aur dependency ko constructor signature mein
  visible banata hai method bodies ke andar hidden rakhne ke bajaye.

Agar interviewer poochhe "kya yahan Singleton achhe se kaam karega?",
strong answer usually yeh hota hai: "Yeh kaam toh karega, lekin main
startup pe ek instance construct karna aur usko inject karna prefer
karunga, kyunki isse dependency explicit aur testable rehti hai — main
actual Singleton ke liye tabhi jaunga jab mujhe single-instance-ness ko
guarantee karna ho independent of ki object kaise wire together hota hai
(jaise, ek hardware resource handle)."

### When NOT to use this

Singleton use mat karo sirf isliye ki "abhi in mein se ek hi hai" — yeh
bahut saare objects ke liye true hota hai jinko global-access enforcement
ki zaroorat nahi hoti. Isko tabhi reach karo jab (a) exactly-one-instance
ek genuine invariant hai jise enforce karna zaroori hai, sirf current
fact nahi, aur (b) global access actually codebase mein required hai,
sirf convenient nahi. Otherwise, ek instance construct karo aur usko pass
around karo.

## Factory Method

**Yeh kaunsa problem solve karta hai:** calling code jisko kisi runtime
input (ek type string, ek config value) ke basis pe kai related
subclasses mein se ek create karna hota hai, woh `case`/`if` blocks se
litter ho jaata hai jo alag-alag constructors call karte hain — aur har
baar jab ek naya subclass add hota hai, un sabhi call sites ko dhoond
kar update karna padta hai.

```ruby
# Before: creation logic scattered across the codebase
def handle_new_vehicle(type, plate)
  case type
  when :bike then Bike.new(plate)
  when :car  then Car.new(plate)
  when :van  then Van.new(plate)
  else raise ArgumentError, "unknown vehicle type: #{type}"
  end
end
# ...and the same case statement, copy-pasted, shows up wherever else
# a Vehicle needs to be constructed from a type + plate.
```

```ruby
# After: one Factory Method, everyone else just calls it
class VehicleFactory
  VEHICLE_CLASSES = {
    bike: Bike,
    car:  Car,
    van:  Van
  }.freeze

  def self.create(type, plate)
    klass = VEHICLE_CLASSES.fetch(type) do
      raise ArgumentError, "unknown vehicle type: #{type}"
    end
    klass.new(plate)
  end
end

VehicleFactory.create(:van, "VAN-001")   # => #<Van ...>
```

Yeh directly parking lot design (`02_Interview_Questions/01_parking_lot.md`)
se connect hota hai: `Vehicle`/`Bike`/`Car`/`Van` already Factory Method
ke liye sahi hierarchy form karte hain. Agar interviewer problem ko
extend kare "vehicles ek API se raw strings ki tarah aate hain," toh
`VehicleFactory.create(type_string, plate)` bilkul wahi jagah hai jahan
woh translation belong karti hai — `ParkingLot` mein scattered nahi.
Calling code sirf `VehicleFactory` aur `Vehicle` interface pe depend
karta hai, concrete `Bike`/`Car`/`Van` classes pe directly kabhi nahi, toh
ek `Truck` add karna sirf `VEHICLE_CLASSES` mein ek line ka addition hai
plus naya class khud.

### When NOT to use this

Agar sirf ek concrete class create ho rahi hai, ya input se class ka
mapping trivial hai aur exactly ek jagah use hota hai, toh factory
unnecessary indirection hai — bas `.new` call karo. Factory Method tab
introduce karo jab same "kaunsi class instantiate karni hai" wala
decision multiple call sites mein duplicate ho raha ho, ya jab
construction khud mein nontrivial logic involve karta ho jo isolate
karne layak ho (sirf ek type lookup nahi).

## Abstract Factory

**Yeh kaunsa problem solve karta hai:** aapko related objects ki ek
*family* produce karni hai jo consistently saath use hone chahiye, aur
aap chahte ho calling code completely agnostic rahe ki woh kaunsi family
use kar rahi hai. Plain Factory Method ek product type produce karta hai
(variants ke saath); Abstract Factory ek saath kai related product types
produce karta hai, ek factory object se, guarantee karte hue ki woh
ek doosre ke saath compatible hain.

```ruby
# Product interfaces
class Button
  def render
    raise NotImplementedError
  end
end

class Checkbox
  def render
    raise NotImplementedError
  end
end

# Windows family
class WindowsButton < Button
  def render = "[Windows-style button]"
end

class WindowsCheckbox < Checkbox
  def render = "[Windows-style checkbox]"
end

# Mac family
class MacButton < Button
  def render = "(Mac-style button)"
end

class MacCheckbox < Checkbox
  def render = "(Mac-style checkbox)"
end

# Abstract factory interface + concrete factories, one per family
class UIFactory
  def create_button
    raise NotImplementedError
  end

  def create_checkbox
    raise NotImplementedError
  end
end

class WindowsUIFactory < UIFactory
  def create_button   = WindowsButton.new
  def create_checkbox = WindowsCheckbox.new
end

class MacUIFactory < UIFactory
  def create_button   = MacButton.new
  def create_checkbox = MacCheckbox.new
end

# Calling code depends only on UIFactory — never knows which OS family
def render_form(factory)
  puts factory.create_button.render
  puts factory.create_checkbox.render
end

render_form(WindowsUIFactory.new)
render_form(MacUIFactory.new)
```

**Woh distinction jo interviewers actually check karte hain:** Factory
Method jawab deta hai "main kaunsi ek class build karu?" (ek product
axis — vehicle type). Abstract Factory jawab deta hai "mutually-compatible
classes ka poora *set* mujhe kaunsa build karna hai?" (ek family — aap
kabhi nahi chahoge ki ek `WindowsButton` ek `MacCheckbox` ke saath pair
ho, aur abstract factory yeh mismatch structurally impossible bana deta
hai, kyunki dono same concrete factory instance se aate hain).

### When NOT to use this

Abstract Factory ek factory-of-factories layer of indirection add karta
hai — yeh sirf tab worth hai jab aapke paas truly multiple parallel
families hon jo internally consistent rehni chahiye (cross-platform UI
kits, per-region compliance rule sets, per-database-vendor query
builders). Agar aapke paas sirf ek hi product type vary ho raha hai, ya
"families" practically kabhi diverge hi nahi karti, toh yeh
over-engineering hai; plain Factory Method use karo.

## Builder

**Yeh kaunsa problem solve karta hai:** ek object ke paas bahut saare
optional configuration parameters hain, aur ek single constructor jo saari
combinations cover kare, toh ya to callers ko har cheez ke liye jo unko
care nahi karni woh `nil` pass karna padta hai, ya woh ek unreadable pile
of keyword arguments mein balloon ho jaata hai.

```ruby
# Before: constructor with 8 optional keyword args
class Pizza
  def initialize(size:, crust: "regular", cheese: true, pepperoni: false,
                  mushrooms: false, olives: false, extra_sauce: false,
                  gluten_free: false)
    # ...
  end
end

Pizza.new(size: "large", crust: "thin", mushrooms: true, extra_sauce: true)
# readable-ish here, but gets worse as options grow, and there's no
# validation step or intermediate state while building
```

```ruby
# After: Builder — chainable, step-by-step, construction separated from
# the final representation
class Pizza
  attr_reader :size, :toppings, :crust

  def initialize(size, crust, toppings)
    @size = size
    @crust = crust
    @toppings = toppings
  end

  def to_s
    "#{size} #{crust}-crust pizza with #{toppings.join(', ')}"
  end
end

class PizzaBuilder
  def initialize(size)
    @size = size
    @crust = "regular"
    @toppings = []
  end

  def crust(type)
    @crust = type
    self
  end

  def add_topping(topping)
    @toppings << topping
    self
  end

  def build
    Pizza.new(@size, @crust, @toppings)
  end
end

pizza = PizzaBuilder.new("large")
  .crust("thin")
  .add_topping("mushrooms")
  .add_topping("extra sauce")
  .build

puts pizza
# => "large thin-crust pizza with mushrooms, extra sauce"
```

Har `.add_topping` call `self` return karta hai, yahi cheez chain ko kaam
karvati hai — ek common Ruby idiom jo ready rakhna worth hai. Builder
incrementally validate bhi kar sakta hai (jaise, ek 6th topping reject
karna) ya intermediate state hold kar sakta hai jo final `Pizza` ko carry
karne ki bilkul zaroorat nahi hai.

### When NOT to use this

Agar ek object ke paas 2-3 optional parameters hain, Ruby keyword
arguments with defaults already isko cleanly solve karte hain — ek
Builder unnecessary ceremony hai. Builder ke liye tab reach karo jab
optional parameters ki number large ho, jab construction mein meaningful
multi-step validation ho, ya jab same kind ka object noticeably different
tareekon se assemble karna ho (ek `PizzaBuilder` vs. ek hypothetical
`CalzonePizzaBuilder` jo steps share karta hai).

## Prototype

**Yeh kaunsa problem solve karta hai:** scratch se naya object create
karna expensive hai (expensive computation, ek external call, heavy
default setup), ya aap ek pre-configured "template" instance chahte ho
jisse variations har baar rebuild karne ke bajaye clone ki jaayein.

```ruby
class MonsterTemplate
  attr_accessor :name, :hp, :abilities

  def initialize(name, hp, abilities)
    @name = name
    @hp = hp
    @abilities = abilities   # an Array — mutable!
  end

  def initialize_copy(source)
    super
    # Without this override, @abilities on the clone would be the SAME
    # array object as the source's — mutating one mutates both. This is
    # Ruby's shallow-copy gotcha: dup/clone copy the object's instance
    # variables, but not what those variables point to.
    @abilities = source.abilities.dup
  end
end

goblin_template = MonsterTemplate.new("Goblin", 30, ["stab", "flee"])

goblin1 = goblin_template.dup
goblin1.abilities << "sneak"

goblin2 = goblin_template.dup
goblin2.abilities   # => ["stab", "flee"]  (NOT polluted by goblin1's mutation,
                     #     because initialize_copy gave it its own array)
```

`.dup` aur `.clone` dono `initialize_copy` ko trigger karte hain; unke
beech difference yeh hai ki `.clone` frozen state aur singleton methods
bhi copy karta hai, jabki `.dup` nahi karta — jaanna worth hai lekin
rarely kisi interview question ka crux hota hai. Loud bolne wali important
baat yeh hai: **Ruby ka default copy shallow hota hai**, toh nested
mutable state (arrays, hashes, other objects) wale kisi bhi object ko
`initialize_copy` override chahiye hoti hai, warna woh nested objects
original aur har clone ke beech shared reh jaate hain.

### When NOT to use this

Agar constructor se ek fresh instance construct karna already cheap aur
simple hai, toh cloning aapko upar diye gaye shallow-copy footgun ke
alawa kuch nahi deta. Prototype ke liye tab reach karo jab construction
genuinely expensive/complex ho, ya jab "is known-good configured instance
se start karo" domain mein ek meaningful concept ho (game entity
templates, document templates) — `.new` call karne ka ek generic
substitute ki tarah nahi.

## Quick Recall — Self-Test

1. **Ek naive `@instance ||= new` Singleton true thread-level parallelism
   ke under safe kyun nahi hota?**
   Do threads dono `@instance` ko `nil` evaluate kar sakte hain isse
   pehle ki dono mein se koi assignment complete ho, toh dono `new` call
   karne ke liye proceed kar jaate hain, do instances produce karte
   hue. Check-and-assign ke around ek mutex (ya class load time pe
   memoize karna) yeh race close kar deta hai.

2. **Interviewers Singletons ke skeptical hone ki sabse badi wajah kya
   hai, "baad mein ek se zyada instance ho sakte hain" ke alawa?**
   Hidden global state — koi bhi code isko bina uss dependency ke
   constructor ya method signature mein appear kiye read/mutate kar
   sakta hai, jo coupling ko invisible banata hai aur tests ko ek doosre
   mein state leak karvata hai jab tak explicitly reset na kiya jaaye.

3. **Abstract Factory plain Factory Method se kaise differ karta hai?**
   Factory Method ek product type produce karta hai variants ke saath
   (jaise, "kaunsa `Vehicle` subclass"). Abstract Factory ek factory
   object se related product types ka poora family produce karta hai,
   guarantee karte hue ki family members mutually compatible hain
   (jaise, same OS family se ek `Button` aur `Checkbox`).

4. **Builder kab overkill hota hai?**
   Jab object ke paas sirf do-teen optional parameters hon — plain Ruby
   keyword arguments with defaults already usko cleanly handle kar dete
   hain. Builder apna keep earn karta hai bahut saare optional
   parameters, multi-step validation, ya same kind ke object ke liye
   genuinely different assembly sequences ke saath.

5. **`.dup`/`.clone` ke saath Ruby ka shallow-copy gotcha kya hai, aur
   isko kaise fix karte hain?**
   `.dup`/`.clone` instance variables copy karte hain, un objects ko
   nahi jinko woh variables reference karte hain — ek cloned object ka
   array/hash instance variable source ka same object rehta hai jab tak
   aap `initialize_copy` override na karo un nested values ko bhi
   explicitly `.dup` karne ke liye.

6. **Parking lot design mein, Factory Method naturally kahan fit hoga,
   aur yeh shuru se wahan kyun nahi hai?**
   `VehicleFactory.create(type, plate)` ek raw type input (jaise, ek API
   se ek string) ko ek `Bike`/`Car`/`Van`/`Truck` instance mein badalne
   ko centralize karega. Base design mein yeh zaroori nahi hai kyunki
   vehicles directly test/caller code se construct hote hain; yeh add
   karne layak tab ban jaata hai jab woh type-to-class decision multiple
   call sites mein duplicate hona start ho jaaye.

7. **Ek shared logger ke liye Singleton se zyada dependency injection
   prefer karne ki ek concrete wajah do.**
   Ek logger instance ko har class ke constructor mein inject karna
   dependency ko explicit banata hai aur tests ko har test ke liye ek
   fake/spy logger substitute karne deta hai bina kisi shared global
   state ke jise tests ke beech reset karna pade.

8. **Prototype specifically `initialize_copy` ko kyun call out karta hai,
   sirf `.dup` pe rely karne ke bajaye?**
   Kyunki `.dup` akela ek shallow copy perform karta hai — nested
   mutable objects (arrays, hashes, other objects) original aur clone ke
   beech shared reh jaate hain. `initialize_copy` woh hook hai jahan aap
   explicitly un nested values ko deep-copy karte ho taaki clones truly
   independent rahein.

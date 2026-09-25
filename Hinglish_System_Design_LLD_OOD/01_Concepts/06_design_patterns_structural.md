# Structural Design Patterns

Structural patterns ka focus hai **objects aur classes kaise compose hote
hain bade structures mein** while un structures ko flexible rakhte hue —
incompatible interfaces ko wrap karna, existing classes ko touch kiye
bina behavior add karna, complexity ko simpler surface ke peeche hide
karna, kisi object tak access control karna, ya objects ke tree ko
uniformly treat karna. Common thread yeh hai: in mein se koi bhi pattern
yeh nahi badalta ki object fundamentally *kya* karta hai, yeh sirf yeh
badalte hain ki woh doosre objects ke saath kaise **assemble ya expose**
hota hai.

## Interview Tips

**Decorator** aur **Facade** yeh do patterns hain jo directly aane ki
sabse zyada possibility hoti hai — Decorator isliye kyunki "optional
behavior/pricing/toppings add karo bina subclasses ka explosion kiye"
yeh ek bahut common LLD prompt shape hai (coffee orders, pizza toppings,
middleware chains), aur Facade isliye kyunki almost har multi-class
design ko eventually ek single entry point chahiye hota hai jo several
subsystems ko coordinate kare (checkout, order placement). **Adapter**
tab aata hai jab bhi design question mein third-party API ya legacy
interface ko integrate karna involve ho. **Proxy** aur **Composite**
primary pattern ke roop mein kam poocha jaata hai, lekin Composite
specifically correct answer hota hai jab bhi problem ka shape recursive
tree jaisa ho (file systems, org charts, UI component trees) — us shape
ko jaldi recognize karna hi actual skill hai jo test ki ja rahi hai.

## Adapter

**Yeh kaunsa problem solve karta hai:** aapke paas code hai jo ek
interface ke against likha gaya hai, aur aapko ek aisa object use karna
hai jo incompatible interface expose karta hai — most often ek
third-party library — bina apna code ya library modify kiye.

```ruby
# The interface your application code is written against
class PaymentGateway
  def charge(amount)
    raise NotImplementedError
  end
end

# A third-party client you don't control, with an incompatible interface:
# takes cents (not dollars) and a separate currency argument
class StripeClient
  def create_charge(amount_cents, currency)
    puts "Stripe: charging #{amount_cents} #{currency}"
    { status: "succeeded" }
  end
end

# Adapter: translates PaymentGateway#charge(amount) into
# StripeClient#create_charge(cents, currency), so callers never know
# Stripe is involved
class StripeAdapter < PaymentGateway
  def initialize(stripe_client = StripeClient.new)
    @stripe_client = stripe_client
  end

  def charge(amount)
    cents = (amount * 100).round
    result = @stripe_client.create_charge(cents, "usd")
    result[:status] == "succeeded"
  end
end

def checkout(gateway, amount)
  gateway.charge(amount) ? "payment ok" : "payment failed"
end

checkout(StripeAdapter.new, 19.99)   # checkout code never mentions Stripe
```

Agar aap baad mein Stripe ko kisi doosre processor se swap karte ho, toh
aap ek naya adapter likhoge (`PaypalAdapter`) jo same `PaymentGateway`
interface implement kare — `checkout` aur baaki har caller ko zero
changes chahiye honge.

### Isko kab NAHI use karna chahiye

Agar aap interface ke dono side control karte ho (jaise, sab kuch aapka
apna code hai), toh unhe directly consistent bana do adapter layer
introduce karne ke bajaye — yeh ek aisi problem solve karna hai jo aapke
paas hai hi nahi. Adapter tabhi apna kaam saabit karta hai jab ek side
fixed ho aur aapke control se bahar ho (ek third-party library, ek legacy
system jise aap refactor nahi kar sakte).

## Decorator

**Yeh kaunsa problem solve karta hai:** aapko kisi object ke *specific
instance* mein runtime par behavior add karna hai, optionally doosre
added behaviors ke combination mein, bina us object ki class modify kiye
aur bina us behavior ka same class ke har doosre instance par asar dale.

**Inheritance ke saath contrast, explicitly:** ek subclass us type ke
*har* instance mein behavior add karta hai, compile-time par fixed
(`MilkCoffee < Coffee` ka matlab hai har `MilkCoffee` mein hamesha milk
hoga). Decorator runtime par ek specific object ko wrap karta hai, aur
decorators ko kisi bhi combination mein stack kiya ja sakta hai — aapko
har combination ke liye ek subclass chahiye hoti (`MilkSugarCoffee`,
`MilkSugarWhipCoffee`, ...) sirf inheritance se same flexibility paane
ke liye.

```ruby
class Coffee
  def cost = 2.00
  def description = "Coffee"
end

# Decorators share the same interface as the thing they wrap
class CoffeeDecorator
  def initialize(coffee)
    @coffee = coffee
  end

  def cost = @coffee.cost
  def description = @coffee.description
end

class MilkDecorator < CoffeeDecorator
  def cost = @coffee.cost + 0.50
  def description = "#{@coffee.description} + milk"
end

class SugarDecorator < CoffeeDecorator
  def cost = @coffee.cost + 0.25
  def description = "#{@coffee.description} + sugar"
end

order = SugarDecorator.new(MilkDecorator.new(Coffee.new))
order.description   # => "Coffee + milk + sugar"
order.cost           # => 2.75

# Any combination, in any order, no new class needed for each combination
plain = Coffee.new
just_milk = MilkDecorator.new(Coffee.new)
```

```text
Coffee  <---- wraps ---- MilkDecorator  <---- wraps ---- SugarDecorator
(cost=2.00)                (cost=2.50)                     (cost=2.75)

Each layer forwards to the one it wraps, then adds its own bit on top.
Stack as many layers as needed, in whatever order.
```

### Isko kab NAHI use karna chahiye

Agar behavior combinations ka set chota aur fixed hai, toh chand plain
subclasses (ya ek hi class jisme boolean flags ho) decorator objects ki
chain se simpler read hongi. Decorator tabhi apna kaam saabit karta hai
jab combinations ko genuinely runtime par freely compose karna ho —
warna "ek method call karo, jo doosra method call karta hai, jo teesra
method call karta hai" kai layers deep, isse debugging harder hi hoti hai
bina kisi real benefit ke.

## Facade

**Yeh kaunsa problem solve karta hai:** ek logical operation complete
karne ke liye several subsystems ko ek specific sequence mein coordinate
karna padta hai, aur facade ke bina, har calling code jo "order place"
karna chahta hai, use un sabhi subsystems ko khud jaanna aur correctly
orchestrate karna padta hai.

```ruby
class Inventory
  def reserve(item, qty)
    puts "Inventory: reserved #{qty}x #{item}"
    true
  end
end

class Payment
  def charge(amount)
    puts "Payment: charged $#{amount}"
    true
  end
end

class Shipping
  def schedule(item, address)
    puts "Shipping: scheduled #{item} to #{address}"
    true
  end
end

# Facade: one simple method, hides the orchestration of three subsystems
class CheckoutFacade
  def initialize
    @inventory = Inventory.new
    @payment = Payment.new
    @shipping = Shipping.new
  end

  def place_order(item, qty, amount, address)
    return false unless @inventory.reserve(item, qty)
    return false unless @payment.charge(amount)

    @shipping.schedule(item, address)
    true
  end
end

CheckoutFacade.new.place_order("Widget", 2, 39.98, "123 Main St")
# Caller doesn't touch Inventory, Payment, or Shipping directly.
```

Subsystems (`Inventory`, `Payment`, `Shipping`) ab bhi independently
usable classes ke roop mein exist karte hain — facade unhe hide nahi
karta, yeh sirf un callers ko ek simpler default path deta hai jinhe
fine-grained control ki zaroorat nahi hoti.

### Isko kab NAHI use karna chahiye

Facade mat banao agar coordinate karne ke liye sirf ek hi subsystem hai,
ya agar callers ko genuinely har subsystem ke calls par fine-grained
control chahiye (ek facade jo sirf ek-to-one forward karta hai ek single
method tak, woh pointless wrapping hai). Yeh bhi dekhte raho ki facade
kahin god object na ban jaaye — agar yeh khud business logic accumulate
karne lagta hai instead of sirf calls orchestrate karne ke, toh woh logic
subsystems mein ya ek dedicated service mein hona chahiye, facade mein
nahi.

## Proxy

**Yeh kaunsa problem solve karta hai:** aap kisi object tak access control
karna chahte ho — usse tabhi create karna jab actually zaroorat ho, call
allow karne se pehle permissions check karna, ya expensive results cache
karna — bina calling code ko yeh jaane diye ki woh real object se directly
baat nahi kar raha.

Teen common variants, sab same shape follow karte hain (ek object jo
real cheez jaisa hi interface present karta hai, delegate karne se
pehle/uski jagah kya karna hai yeh decide karta hai):

- **Lazy-loading proxy** — expensive construction ko first use tak defer
  karta hai.
- **Protection proxy** — permissions check karta hai, phir delegate karta
  hai ya refuse karta hai.
- **Caching proxy** — expensive calls ke results cache karta hai, sirf
  cache miss par delegate karta hai.

```ruby
class RealImage
  def initialize(filename)
    @filename = filename
    load_from_disk   # expensive — only want this to happen when needed
  end

  def render
    puts "Rendering #{@filename}"
  end

  private

  def load_from_disk
    puts "Loading #{@filename} from disk (expensive)..."
  end
end

# Lazy-loading proxy: same interface as RealImage, defers the expensive
# construction until #render is actually called
class LazyImageProxy
  def initialize(filename)
    @filename = filename
    @real_image = nil
  end

  def render
    @real_image ||= RealImage.new(@filename)
    @real_image.render
  end
end

gallery = [
  LazyImageProxy.new("photo1.jpg"),
  LazyImageProxy.new("photo2.jpg")
]
# Nothing loaded yet — RealImage.new hasn't run for either

gallery.first.render
# NOW "photo1.jpg" loads from disk, and only photo1
```

### Isko kab NAHI use karna chahiye

Agar real object ko construct/access karna already cheap hai, ya waha
koi actual access-control ya caching ki zaroorat nahi hai, toh proxy pure
indirection hai bina kisi payoff ke. Yeh bhi mat karo ki hand-rolled proxy
banao jab language ya framework already yeh behavior free mein de raha
ho (jaise, Rails ka lazy association loading, ya `||=` inline ke saath
memoization jaha ek poori proxy class ek-off case ke liye overkill hogi).

## Composite

**Yeh kaunsa problem solve karta hai:** aapke paas objects ka ek tree hai
— kuch leaves hain, kuch doosre objects ke containers hain (jo khud
leaves ya containers ho sakte hain) — aur aap chahte ho ki calling code
individual objects aur poore subtrees ko exact same interface se treat
kare, bina har jagah "yeh leaf hai ya branch" ka special-case kiye.

```ruby
class FileSystemEntry
  def size
    raise NotImplementedError
  end
end

class File < FileSystemEntry
  def initialize(name, size)
    @name = name
    @size = size
  end

  def size = @size
end

class Directory < FileSystemEntry
  def initialize(name)
    @name = name
    @children = []
  end

  def add(entry)
    @children << entry
    self
  end

  # Recursively sums children's sizes — doesn't care whether each child
  # is a File or another Directory, both respond to #size
  def size
    @children.sum(&:size)
  end
end

root = Directory.new("root")
docs = Directory.new("docs")
docs.add(File.new("resume.pdf", 200))
docs.add(File.new("cover_letter.pdf", 50))

root.add(docs)
root.add(File.new("readme.txt", 10))

root.size   # => 260 (200 + 50 + 10, recursively, uniformly)
```

Calling code (`root.size`) ko kabhi yeh jaanne ki zaroorat nahi hoti ki
tree kitna deep hai ya kaunse nodes files hain vs. directories — yehi
poora point hai.

### Isko kab NAHI use karna chahiye

Agar structure genuinely recursive/tree-shaped nahi hai (koi "in cheezo
ka container khud aur inhi cheezo ko contain kar sakta hai" relationship
nahi hai), toh Composite galat tool hai — ek plain collection ya do-teen
alag classes zyada clear rahenge. Ek flat, fixed-depth structure (jaise,
"ek Order mein Items hote hain, bas, koi nesting nahi") ko forcefully
Composite shape mein daalna un problems ke liye recursive-traversal
complexity add karta hai jinhe uski zaroorat hi nahi.

## Quick Recall — Self-Test

1. **Adapter aur Decorator ke beech key difference kya hai? Dono hi
   doosre object ko "wrap" karte hain.**
   Adapter ek object ka *interface* badalta hai taaki callers ke
   expectations se match kare, bina koi naya behavior add kiye — yeh ek
   translation layer hai. Decorator same interface rakhta hai lekin
   uske upar behavior/responsibility *add* karta hai, aur combinations
   mein stack hone ke liye bana hai.

2. **"Milk, sugar, aur whip ke kisi bhi combination wali coffee" ke liye
   inheritance, Decorator se worse fit kyun hai?**
   Inheritance ko har combination ke liye ek subclass chahiye hogi
   (`MilkSugarCoffee`, `MilkWhipCoffee`, `MilkSugarWhipCoffee`, ...) jo
   compile-time par fixed hoti hai. Decorator objects ko wrap karke
   combination ko runtime par compose karta hai, bina classes ke
   combinatorial explosion ke.

3. **Facade kab anti-pattern ban jaata hai?**
   Jab yeh sirf subsystems ke calls orchestrate karna band kar deta hai
   aur khud actual business logic accumulate karna start kar deta hai —
   us point par yeh god object ban chuka hota hai, aur woh logic
   subsystems mein ya ek dedicated service mein move hona chahiye.

4. **Teen common Proxy variants ke naam batao aur har ek kya guard karta
   hai.**
   Lazy-loading proxy (expensive object creation ko first real use tak
   defer karta hai), protection proxy (delegate karne se pehle
   permissions check karta hai), aur caching proxy (expensive calls ke
   results cache karta hai, sirf miss par delegate karta hai).

5. **Composite ko kyun zaroorat hai ki har node — leaf ho ya container —
   same interface implement kare?**
   Kyunki poora point yeh hai ki calling code (jaise, `root.size`) yeh
   special-case nahi karta ki "yeh File hai ya Directory" — yeh bas
   shared method call karta hai, aur ek container ka implementation
   recursively usi method ko apne children par call karta hai, chahe har
   ek kisi bhi type ka ho.

6. **Adapter ko kab NAHI use karna chahiye, iska ek concrete example do.**
   Jab aap interface mismatch ke dono side directly control karte ho —
   jaise, apne hi codebase ki do classes jinhe bas ek-doosre ke saath
   consistent banaya ja sakta hai, unke beech translation layer
   introduce karne ke bajaye.

7. **Parking lot design mein, agar aapko ek third-party "SmartGate"
   barrier system integrate karna ho jiska apna incompatible API ho
   vehicle entry detect karne ke liye, toh kaunsa structural pattern fit
   baithega, aur kyun?**
   Adapter — `SmartGateClient` ke incompatible methods ko ek aise
   interface ke peeche wrap karo jo aapka `ParkingLot` code already
   expect karta hai (jaise, ek `VehicleDetector#detect_entry` method),
   taaki `ParkingLot` kabhi bhi SmartGate ke actual API par directly
   depend na kare.

8. **Payment-charging call ke liye caching proxy kyun bad idea ho sakta
   hai?**
   Payment charges idempotent/side-effect-free reads nahi hote —
   "charge" call ko cache karke replay karna customer ko double-charge
   kar sakta hai. Caching proxies expensive *read* operations ke aage
   hone chahiye jinke results reuse karna safe ho, side effects wale
   operations ke aage nahi.

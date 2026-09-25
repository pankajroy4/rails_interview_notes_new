# OOP Fundamentals for Interviews

## Why it matters

Har Ruby developer ne classes, `attr_accessor`, `include`, aur inheritance
hazaaron baar use kiya hai bina necessarily yeh naam liye ki *why* woh tools
exist karte hain ya kaunsi specific problem har ek solve karta hai. Yeh
day-to-day work ke liye fine hai — LLD interview mein yeh fine hona band ho
jaata hai, jahan interviewer explicitly evaluate kar raha hota hai ki
aapko syntax ke peeche ka *purpose* pata hai ya nahi. Ek candidate jo ek
working class likh sakta hai lekin yeh nahi bol sakta "this is
polymorphism, and it's why I don't need a `case` statement here," woh
pattern-matching demonstrate kar raha hai, understanding nahi — aur
interviewers specifically probe karte hain difference batane ke liye,
usually pooch ke "why did you do it this way?" turant jab aap kuch likh
dete hain.

Real failure mode yeh hai: bina in concepts ko internalize kiye, har design
problem ek hi tarah se solve hota hai — ek class, kuch instance variables,
aur conditional branches ka ek badhta hua pile (`if type == :van`, `case
status when :pending`) har method mein sprinkle hua. Yeh kaam karta hai,
compile hota hai, aur interview fail karta hai, kyunki yeh cleanly extend
nahi hota aur object-oriented thinking demonstrate nahi karta. Yeh file
char pillars, composition vs. inheritance, aur Ruby specifically interfaces
aur abstraction ko kaise express karta hai — yeh vocabulary aur code
patterns cover karti hai jo "kuch methods wali ek class" ko ek aisa design
banate hain jise interviewer OOP ki tarah recognize karta hai.

## The Four Pillars

### 1. Encapsulation

**Definition:** ek object ke internal state ko hide karna aur usse
interact karne ke liye sirf ek controlled, intentional interface expose
karna. Object khud decide karta hai ki kya read ho sakta hai, kya change ho
sakta hai, aur kis condition mein — callers kabhi bhi directly andar reach
karke internals mutate nahi karte.

**Before (no encapsulation — internal state public aur unprotected hai):**

```ruby
class BankAccount
  attr_accessor :balance

  def initialize(balance)
    @balance = balance
  end
end

account = BankAccount.new(100)
account.balance = -500   # nothing stops this; balance is just a public number
```

Koi bhi caller kahin se bhi `balance` ko kuch bhi set kar sakta hai,
including ek negative number, "withdrawals can't exceed the balance" wale
kisi bhi notion ko bypass karke. Koi single jagah nahi hai jo account ke
rules enforce kare kyunki uske state ke around koi boundary hi nahi hai.

**After (encapsulated — state private hai, changes un methods se guzarte
hain jo invariants enforce karte hain):**

```ruby
class BankAccount
  def initialize(balance)
    @balance = balance
  end

  def balance
    @balance
  end

  def deposit(amount)
    raise ArgumentError, "amount must be positive" unless amount.positive?
    @balance += amount
  end

  def withdraw(amount)
    raise ArgumentError, "amount must be positive" unless amount.positive?
    raise "insufficient funds" if amount > @balance
    @balance -= amount
  end
end

account = BankAccount.new(100)
account.withdraw(500)   # raises "insufficient funds" instead of corrupting state
```

Ab exactly ek jagah hai (`withdraw`) jahan "can't overdraw" rule rehta hai.
Har caller usi se guzarta hai. Yahi encapsulation ki core value hai: yeh
"har caller ko rules yaad rakhne padte hain" ko "object khud apne rules
enforce karta hai" mein badal deta hai, jo hi ek codebase ko har call site
re-audit kiye bina extend karne ke liye safe banata hai.

### 2. Abstraction

**Definition:** ek object *kya* karta hai woh expose karna bina yeh expose
kiye ki *kaise* karta hai. Callers ek stable, simple interface pe depend
karte hain; us interface ke peeche ki implementation freely change ho sakti
hai jab tak interface ka contract hold karta hai.

```ruby
class ReportGenerator
  def generate(data)
    raise NotImplementedError, "#{self.class} must implement generate"
  end
end

class PdfReportGenerator < ReportGenerator
  def generate(data)
    # ... builds a PDF, using whatever PDF library, layout logic, etc.
    "PDF report with #{data.size} rows"
  end
end

class CsvReportGenerator < ReportGenerator
  def generate(data)
    data.map { |row| row.join(",") }.join("\n")
  end
end

def export_report(generator, data)
  generator.generate(data)   # caller has no idea, and doesn't need to know, HOW
end

export_report(PdfReportGenerator.new, [[1, 2], [3, 4]])
export_report(CsvReportGenerator.new, [[1, 2], [3, 4]])
```

`export_report` sirf is fact pe depend karta hai ki `generator`
`generate(data)` respond karta hai. Usse koi matlab nahi ki iska matlab ek
PDF byte stream banana hai ya strings ko commas se join karna. Yahi hai jo
aapko `PdfReportGenerator` ko `CsvReportGenerator` se swap karne deta hai —
ya baad mein ek third format add karne deta hai — `export_report` mein zero
changes ke saath. Abstraction sikke ka base-class (ya module) side hai;
polymorphism, neeche, caller-side payoff hai.

### 3. Inheritance

**Definition:** ek **is-a** relationship jahan ek subclass parent class ke
attributes aur behavior ko inherit karta hai aur uske parts ko override ya
extend kar sakta hai. Isse tab use kariye jab subclass really parent ka ek
more specific version ho, sirf aisi cheez nahi jo kuch code share karne ke
liye ho.

```ruby
class Employee
  attr_reader :name, :base_salary

  def initialize(name, base_salary)
    @name = name
    @base_salary = base_salary
  end

  def annual_salary
    base_salary * 12
  end
end

class SalesEmployee < Employee
  def initialize(name, base_salary, commission)
    super(name, base_salary)
    @commission = commission
  end

  def annual_salary
    super + @commission
  end
end
```

```text
        Employee
        - name
        - base_salary
        + annual_salary()
            ^
            |
      SalesEmployee
      - commission
      + annual_salary()   (overrides, calls super)
```

Ek `SalesEmployee` **is an** `Employee` — har `Employee` method aur
attribute isko apply hota hai, plus uske apne. Woh "is-a" test guardrail
hai: agar aap khud ko sirf ek method reuse karne ke liye ek class se inherit
karte hue paate hain, bina is-a relationship actually hold kiye, yeh sign
hai ki aapko composition chahiye (neeche dekhiye).

### 4. Polymorphism

**Definition:** same method call jis object pe call hua hai uski actual
(runtime) class ke depend karke different behave karta hai. Yeh single
sabse interview-relevant pillar hai, kyunki yeh `case type when :x ...
when :y ...` chains ka direct, concrete replacement hai — aur ek
interviewer jo aapko unme se ek likhte hue dekhta hai, woh dekh raha hai ki
aap exercise ka point miss kar rahe hain.

**Before (type-checking chain — woh pattern jise interviewers watch karte
hain):**

```ruby
def calculate_area(shape)
  case shape[:type]
  when :circle
    Math::PI * shape[:radius]**2
  when :rectangle
    shape[:width] * shape[:height]
  when :triangle
    0.5 * shape[:base] * shape[:height]
  else
    raise "unknown shape type"
  end
end
```

Har naya shape ka matlab hai is method ko edit karna (aur har dusra method
jo `:type` pe branch karta hai). "Circle apna area kaise compute karta hai"
ki logic kisi bhi cheez se door rehti hai jiska naam `Circle` ho, scattered
across jinme bhi methods ke paas iske liye ek `case` hota hai.

**After (polymorphism — har object khud apne liye answer karta hai):**

```ruby
class Shape
  def area
    raise NotImplementedError, "#{self.class} must implement area"
  end
end

class Circle < Shape
  def initialize(radius) = @radius = radius
  def area = Math::PI * @radius**2
end

class Rectangle < Shape
  def initialize(width, height) = (@width, @height = width, height)
  def area = @width * @height
end

class Triangle < Shape
  def initialize(base, height) = (@base, @height = base, height)
  def area = 0.5 * @base * @height
end

shapes = [Circle.new(2), Rectangle.new(3, 4), Triangle.new(5, 6)]
shapes.map(&:area)   # => calls the correct area for each, no branching anywhere
```

`shapes.map(&:area)` identically kaam karta hai chahe array mein kuch bhi
ho, aur `Square < Shape` add karne ke liye sirf ek naya class touch karna
padta hai, kuch aur nahi. Yeh exactly wahi mechanism hai jo parking lot
example
(`LLD_OOD/02_Interview_Questions/01_parking_lot.md`) `Vehicle#spots_required`
ke liye use karta hai: instead of `ParkingLot` ko yeh pata hone ke "vans
need 3 bike spots," har `Vehicle` subclass khud apne liye
`spots_required(spot_type)` answer karta hai, aur `ParkingLot` bas question
poochta hai. Yeh single design choice usually poori exercise ka sabse clear
signal hota hai ki candidate OOP samajhta hai versus class syntax ke saath
procedural code likh raha hai.

## Composition vs. Inheritance

**The principle:** inheritance ke over composition favor kariye.
Composition ka matlab hai ek object ko dusre objects se banana (yeh ek
collaborator ko *has-a* karta hai) instead of ek parent class ko extend
karna (parent ko *is-a* karna). Composition tab prefer kariye jab
relationship ek true "is-a" na ho, ya jab aapko behaviors ko flexibly mix
aur match karna ho.

**Why inheritance can go wrong:** yeh ek parent ki *implementation* se
tight coupling banata hai, sirf uske interface se nahi — ek subclass ek
parent mein change se break ho sakta hai jise usne kabhi touch bhi nahi
kiya. Deep hierarchies isko compound karti hain: third ya fourth level tak,
yeh unclear hota hai ki ek given method actually kaunse ancestor se aa raha
hai, aur chain mein kahin bhi ek change har descendant ko break karne ka
risk rakhta hai. Yeh ek single-axis classification bhi force karta hai —
agar ek `Duck` ko "a bird" aur "something that can swim" dono hona hai, aur
`Penguin` ko "a bird" hona hai lekin explicitly duck ki tarah swim *nahi*
karna hai, akela inheritance is combination ko cleanly express nahi kar
sakta.

**Before (ek hierarchy jo naye combinations aane pe awkward ho jaati hai):**

```ruby
class Bird
  def fly = "flying"
end

class Duck < Bird
  def swim = "swimming"
end

class Penguin < Bird
  # Penguins can't fly - now we have to override fly to raise/no-op,
  # which means Penguin "is a" Bird but violates the Bird contract.
  def fly
    raise NotImplementedError, "penguins can't fly"
  end
end
```

Abilities ke har different combination wala har naya bird (fly karta hai
lekin swim nahi karta, swim karta hai lekin fly nahi karta, dono nahi karta,
dono karta hai) ya to ek override force karta hai jo parent ke contract ko
violate karta hai, ya subclassing ka ek aur layer force karta hai
(`FlightlessBird`, `SwimmingBird`, `FlightlessSwimmingBird`...) jo
combinatorially grow karta hai.

**After (small, independent, swappable behaviors se composed):**

```ruby
module CanFly
  def fly = "flying"
end

module CanSwim
  def swim = "swimming"
end

class Bird
  def initialize(name) = @name = name
end

class Duck < Bird
  include CanFly
  include CanSwim
end

class Penguin < Bird
  include CanSwim   # simply doesn't include CanFly - no contract violation
end
```

Ab abilities independent modules hain jo per class mix in kiye jaate hain,
aur koi class kabhi ek behavior implement karne (ya explicitly reject
karne) ke liye force nahi hoti jo uske paas hai hi nahi. Yeh Ruby modules ke
zariye composition hai: `Duck` aur `Penguin` dono apne actual zaroorat ke
pieces se assemble kiye gaye hain, aur abilities ke ek naye combination wala
naya bird bas ek naya class hai jo sahi modules include karta hai — koi
hierarchy redesign nahi chahiye. Yahi idea poore objects compose karne pe
bhi apply hota hai, sirf modules pe nahi: ek `Car` ek `Engine` object aur
ek `GPS` object se compose ho sakta hai (`@engine = Engine.new`, `@gps =
GPS.new`) instead of ek `EngineBehavior` base class se inherit karne ke —
engine ko runtime pe ek `ElectricEngine` se swap kiya ja sakta hai `Car`
ki class hierarchy ko bina touch kiye.

## Interfaces in Ruby (Duck Typing and Modules)

Ruby ke paas Java ya C# jaisa koi `interface` keyword nahi hai. Yeh
interface-like contracts do tareeke se achieve karta hai:

**1. Duck typing:** "agar yeh duck ki tarah chalta hai aur duck ki tarah
quack karta hai, to yeh ek duck hai" — koi bhi object jo right method(s) ko
respond karta hai, usse polymorphically use kiya ja sakta hai, uski class
ya ancestry se independent. "Implements this interface" ka koi formal
declaration required nahi hai.

```ruby
class EmailSender
  def send(message) = puts "Emailing: #{message}"
end

class SmsSender
  def send(message) = puts "Texting: #{message}"
end

def notify(sender, message)
  sender.send(message)   # works with ANY object that responds to #send
end

notify(EmailSender.new, "hello")
notify(SmsSender.new, "hello")
```

`notify` kabhi `sender` ki class check nahi karta — yeh bas `send` call
karta hai. Koi bhi object jiske paas compatible `send` method ho woh kaam
karta hai, including ek test double ya ek third-party library se aaya hua
object, bina kisi shared ancestry ke.

**2. Modules/mixins for shared behavior:** `include` ek module ke methods
ko ek class mein aise le aata hai jaise woh wahin define hue hon, unrelated
classes ko ek common (aur potentially awkward) parent se inherit kiye bina
behavior share karne deta hai — yahi tareeka hai jisse Ruby ki standard
library aapko `Comparable` (implement `<=>`, aur `<`, `>`, `between?` free
mein) aur `Enumerable` (implement `each`, aur `map`, `select`, `reduce` free
mein) deti hai.

**3. `raise NotImplementedError` as an enforced contract:** kyunki Ruby
aapko compile time pe ek "abstract" class instantiate karne ya ek method
skip karne se nahi rokta, idiomatic convention ek base class method hai jo
turant raise karta hai, subclasses ko usable hone se pehle usse override
karne ke liye force karta hai. Yeh exactly wahi pattern hai jo parking lot
example ke `Vehicle#spots_required` mein hai:

```ruby
class Vehicle
  def spots_required(spot_type)
    raise NotImplementedError, "#{self.class} must implement spots_required"
  end
end
```

Koi bhi subclass jo `spots_required` implement karna bhool jaaye, jaise hi
usse call kiya jaayega loudly raise karega — silently wrong cheez nahi
karega. Yeh Ruby ka Java ke `abstract` method ke sabse closest equivalent
hai: language dwara class-definition time pe enforce nahi kiya jaata,
lekin call time pe enforce kiya jaata hai, jo contract ko explicit banane
aur violations ko turant catch karne ke liye kaafi hai.

## Abstract Classes in Ruby

Ruby ke paas classes ke liye bhi `abstract` keyword nahi hai. Convention
wahi `raise NotImplementedError` pattern hai, ek base class pe apply kiya
hua jise kabhi directly instantiate nahi karna hota (sirf uske subclasses
hi hote hain):

```ruby
class PaymentMethod
  def process(amount)
    raise NotImplementedError, "#{self.class} must implement process"
  end
end

class CreditCardPayment < PaymentMethod
  def process(amount) = "Charged $#{amount} to credit card"
end

class PayPalPayment < PaymentMethod
  def process(amount) = "Charged $#{amount} via PayPal"
end
```

Kuch bhi ek caller ko `PaymentMethod.new.process(10)` likhne se rokta nahi
— yeh bas turant `NotImplementedError` raise karega, jo intended behavior
hai: yeh signal karta hai "this class is a template, not a usable object,"
enforced jab yeh misuse ho, ek compiler se pehle se nahi.

## Why interviewers care about polymorphism specifically

Char pillars mein se, polymorphism woh hai jo sabse directly aur visibly
ek strong LLD answer ko ek weak answer se alag karta hai, kyunki yeh khud
code mein ek structural difference ki tarah dikhta hai, sirf ek stylistic
difference ki tarah nahi. Encapsulation, abstraction, aur inheritance sab
aisi code mein present ho sakte hain jisme abhi bhi ek `case vehicle_type`
chain har method mein scattered ho — us code mein technically classes hain
aur kuch state hide karti hai, lekin usne responsibility ko sahi objects
tak actually distribute nahi kiya. Jis moment aap ek `case`/`if` chain
dekhte ho (ya likhte ho) jo ek object ki *type* pe branch karta hai yeh
decide karne ke liye ki kya karna hai, wahi signal hai: logic type-specific
object ke andar belong karti hai, bahar nahi, ek method ki tarah jise har
subclass differently implement karta hai. Interviewers isko specifically
isliye sunte hain kyunki yeh sabse fastest tell hai ki candidate reflex ki
tarah "kya yeh object khud yeh answer karna jaanta hai?" reach karta hai ki
nahi — jo exactly wahi hai jo parking lot interview is repo mein test kar
raha tha jab usne van/bike-spot rule plant kiya tha.

## Interview Tips

- Jab aap khud ko ek shared method ke andar `case obj.type` ya `if
  obj.is_a?(X)` likhte hue paayein, ruk jaayein aur poochein: "kya object
  khud isko answer kare?" Us branch ko ek polymorphic method call mein
  convert karna usually live interview mein sabse highest-value edit hota
  hai jo aap kar sakte ho.
- Design karte waqt pillar names ko out loud boliye: "I'm making `balance`
  private and only mutable through `deposit`/`withdraw` — that's
  encapsulation, so no caller can put the account into an invalid state."
  Apni reasoning ko narrate karna aksar code ke barabar hi worth hota hai.
- Jab poocha jaaye "how would you make this extensible," answer almost
  hamesha "polymorphism instead of branching" aur "composition instead of
  a rigid inheritance chain" ka kuch combination hota hai — dono ko concrete
  moves ki tarah ready rakhiye, sirf words ki tarah nahi.
- Agar aap sirf ek method reuse karne ke liye ek class se inherit karte
  hain, aur "is-a" relationship forced feel hota hai, to yeh boliye aur
  composition ya ek shared module pe switch kariye. Interviewers notice
  karte hain jab ek candidate habit se inheritance default kar leta hai,
  na ki isliye ki yeh right relationship hai.
- Ek direct follow-up expect kariye: "how would Ruby express this without
  a formal interface keyword?" Duck-typing aur `NotImplementedError`
  answers ready rakhiye — yeh ek bahut common LLD-in-Ruby specific
  question hai.

## Quick Recall — Self-Test

1. **Encapsulation kaunsi problem solve karta hai jo ek plain class har
   field pe `attr_accessor` ke saath nahi karti?**
   Yeh callers ko internals directly mutate karke ek object ko invalid
   state mein daalne se rokta hai (e.g., ek bank balance ko negative
   number set karna). Encapsulation saari state changes ko un methods se
   funnel karta hai jo object ke apne rules enforce kar sakte hain, taaki
   rules ek jagah rahein.

2. **Polymorphism ki definition dijiye, aur explain kariye yeh sabse
   interview-relevant pillar kyun consider hota hai.**
   Polymorphism woh hai jahan same method call jis object pe call hua hai
   uski runtime class ke depend karke different behavior produce karta
   hai. Yeh sabse interview-relevant pillar hai kyunki yeh directly `case
   type`/`if is_a?` chains ko replace karta hai har object khud apne liye
   answer karne se, aur interviewers specifically dekhte hain ki candidate
   type pe branch karne ke bajaye isko reach karta hai ki nahi.

3. **Ruby ke paas `interface` keyword kyun nahi hai, aur kaunse do
   mechanisms isko replace karte hain?**
   Ruby dynamically typed hai aur compile time pe method contracts enforce
   nahi karta, to iske paas koi formal interface construct nahi hai. Yeh
   interfaces ko duck typing se replace karta hai (koi bhi object jo right
   methods respond karta hai use polymorphically use kiya ja sakta hai)
   aur modules/mixins se (`include` ke zariye shared behavior, aksar
   `raise NotImplementedError` ke saath ek base method mein pair kiya hua
   yeh enforce karne ke liye ki "subclasses must implement this").

4. **"Is-a" test kya hai, aur aap ise inheritance aur composition ke beech
   decide karne ke liye kaise use karte hain?**
   Is-a test poochta hai ki kya subclass genuinely parent ka ek more
   specific version hai (ek `SalesEmployee` ek `Employee` hai). Agar
   relationship hold nahi karti — aap sirf ek method reuse karne ke liye
   inherit kar rahe ho, ya child ko parent ke contract ka kuch part reject
   karna hai (jaise ek penguin jo `fly` ko override karke raise karta hai)
   — to composition use kariye (ek module mix in kariye, ya ek collaborator
   object hold kariye) instead.

5. **`raise NotImplementedError` pattern ko explain kariye aur yeh
   real-world mein kaunsi problem prevent karta hai.**
   Yeh ek base class method mein rakha jaata hai jise subclasses ko
   override karna expected hota hai; agar ek subclass bhool jaaye, us
   method ko call karna turant aur loudly raise karta hai, instead of
   silently kuch na karne ya `nil` return karne ke. Yeh Ruby ka idiomatic
   stand-in hai `abstract` classes/methods aur enforced interface
   contracts dono ke liye, kyunki language natively na to deta hai.

6. **Ek deep inheritance hierarchy mein specifically kya galat ho jaata hai
   jab behavior ke naye combinations chahiye hote hain (e.g., birds jo
   fly karte hain, swim karte hain, dono karte hain, ya kuch nahi karte)?**
   Inheritance single-axis hai: har combination model karne ke liye ya to
   contract-violating overrides force hote hain (ek `Penguin < Bird` jo
   `fly` ko override karke raise karta hai) ya subclasses ka ek
   combinatorial explosion (`FlightlessSwimmingBird`, etc.). Composition
   isse avoid karta hai sirf un behaviors (modules) ko mix in karke jo ek
   given class ko actually chahiye.

7. **Parking lot example mein, specifically kya cheez `Vehicle#spots_required`
   ko polymorphism ka ek example banati hai, sirf "classes use karna"
   nahi?**
   Har `Vehicle` subclass (`Bike`, `Car`, `Van`) `spots_required(spot_type)`
   ko differently implement karta hai, aur `ParkingLot`
   `vehicle.spots_required(spot_type)` call karta hai bina kabhi yeh check
   kiye ki uske paas kaunsa subclass hai — same call har actual object ke
   hisaab se different behavior produce karta hai, aur vehicle classes ke
   bahar vehicle type pe koi branching exist hi nahi karti.

8. **Abstraction kya hai, aur yeh encapsulation se kaise differ karta hai?
   Dono ko distinguish karne wala ek example dijiye.**
   Abstraction expose karta hai ek object *kya* karta hai bina yeh expose
   kiye ki *kaise* (e.g., callers ko pata hai `generator.generate(data)`
   ek report produce karta hai, yeh nahi ki ek PDF internally kaise
   assemble hota hai). Encapsulation internal *state* ko hide karta hai
   aur control karta hai ki yeh kaise mutate hoti hai (e.g., `balance`
   sirf `deposit`/`withdraw` ke zariye hi change ho sakta hai). Abstraction
   implementation ko ek behavioral contract ke peeche hide karne ke baare
   mein hai; encapsulation data ko hide aur protect karne ke baare mein
   hai.

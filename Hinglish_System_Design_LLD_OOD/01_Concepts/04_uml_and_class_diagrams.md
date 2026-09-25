# UML and Class Diagrams

**UML (Unified Modeling Language)** diagram notations ka ek standardized set
hai jo software design ko visualize karne ke liye use hota hai. LLD
interviews mein, UML ka bas ek hi corner matter karta hai — **class
diagram** — jisse aap classes, unke members, aur unke beech ke relationships
ko code likhne se pehle (ya likhte waqt) sketch kar sakte ho.

## Why it matters

Class diagram sabse fast tarika hai apna object model kisi doosre insaan
tak pahunchane ka. Yeh baat "ek `ParkingLot` hai jo bahut saare
`ParkingSpot`s ko own karta hai, aur `Vehicle` ek base class hai jiske
`Bike`, `Car`, aur `Van` subclasses hain" — yeh sentence by sentence bol
ke explain karna slow hota hai aur track lose karna easy hota hai — aapke
liye bhi aur interviewer ke liye bhi. Ek das-second ka sketch jisme boxes
aur arrows hon, same structure instantly convey kar deta hai aur
interviewer ko kuch concrete de deta hai jispe woh point kar sake jab woh
poochhe "yahan agar aisa ho jaaye toh kya hoga..." Bahut saare interviewers
explicitly poochte hain ki code likhne se pehle ya sath-sath class diagram
sketch karo (whiteboard pe, shared doc mein, ya code comment mein), specifically
isliye kyunki yeh aapka object model line-by-line code padhne se zyada
fast reveal karta hai.

Is skill ke bina, do cheezein galat hoti hain. Pehli, candidates seedha
code mein jump kar jaate hain object model ko kabhi externalize kiye bina,
toh interviewer ko design tab tak dikhta hi nahi jab tak woh fully type ho
na jaaye — koi bhi misunderstanding late catch hoti hai, kaafi time waste
hone ke baad. Doosri, jo candidates diagram banane ki koshish karte hain,
woh often relationship types ko blur kar dete hain (har connection ko
plain line se draw karke, ya usse bhi bura, composition ko galti se
"inheritance" bolke describe karke), jo underlying concepts ke baare mein
confusion signal karta hai, sirf notation ke baare mein nahi. Arrows mein
precision hi design mein precision hai.

## Class Box Notation

Ek UML class box mein teen compartments hote hain: **class name**,
**attributes**, **methods**. Visibility ek prefix se mark hoti hai: `+`
public, `-` private, `#` protected.

```text
+-----------------------------------+
|              ParkingSpot           |
+-----------------------------------+
| + id: String                       |
| + spot_type: Symbol                |
| - occupied_by: Vehicle             |
+-----------------------------------+
| + occupied?() : Boolean            |
| + occupy(vehicle: Vehicle) : void  |
| + vacate() : void                  |
+-----------------------------------+
```

Yeh box padhte hue: `ParkingSpot` ke paas public `id` aur `spot_type` hai,
ek private `occupied_by` (sirf class ke andar se accessible, jaise ki
parking lot example mein `ParkingSpot` apna `occupied_by` sirf ek
controlled accessor ke through expose karta hai, kahin se bhi raw mutation
ke through nahi), aur teen public methods. Interview mein, poore
three-compartment box ko har attribute ke type ke saath draw karna usually
overkill hota hai — kitna detail actually expected hai yeh dekhne ke liye
neeche "Practical Interview Guidance" section dekho.

## Relationship Types

Yahi wo part hai jahan log genuinely confuse ho jaate hain — neeche diye
gaye chaaron relationship types superficially similar dikhte hain (boxes
ke beech lines aur arrows) lekin structurally alag cheezein mean karte
hain, aur yahan precision exactly wahi cheez hai jo interviewers sun rahe
hote hain.

### Association

**Definition:** do classes ke beech ek general "uses/knows about"
relationship, jisme kisi bhi direction mein ownership implied nahi hai —
koi bhi object doosre ke lifecycle ko control nahi karta.

```text
Driver ------------- Car
       "drives"
```

**Example:** ek `Driver` us `Car` se associate hota hai jo woh currently
drive kar raha hai. `Driver` object ek `Car` ka reference hold karta hai
(ya `Car` apne current `Driver` ka reference hold karta hai, ya dono),
lekin `Driver` object destroy karne se `Car` destroy nahi hota, aur vice
versa — dono ke fully independent lifecycles hote hain aur woh sirf
association ki duration ke liye ek doosre ko refer karte hain.

```ruby
class Car
  attr_accessor :current_driver
end

class Driver
  attr_reader :name
  def initialize(name) = @name = name
end

car = Car.new
driver = Driver.new("Alex")
car.current_driver = driver   # association: car knows about driver, but doesn't own it
```

### Aggregation ("has-a," hollow diamond)

**Definition:** ek whole/part relationship jisme part **whole se
independently exist kar sakta hai** — agar whole destroy ho jaaye, toh
parts zinda rehte hain.

```text
Department  o------------  Employee
  (whole)   hollow diamond   (part)
```

**Example:** ek `Department` ke paas `Employee`s hote hain, lekin agar
department dissolve ho jaaye, toh employees phir bhi exist karte hain (unko
kisi doosre department mein reassign kiya ja sakta hai, ya woh simply
company mein kahin aur job karne wale log hain hi). `Department` un
`Employee` objects ka reference hold karta hai jinko woh exclusively own
nahi karta.

```ruby
class Employee
  attr_reader :name
  def initialize(name) = @name = name
end

class Department
  def initialize(name)
    @name = name
    @employees = []
  end

  def add_employee(employee)
    @employees << employee   # aggregation: employees can be added/removed,
  end                          # and outlive the department if it's dissolved
end
```

### Composition ("owns-a," filled diamond)

**Definition:** ek stricter whole/part relationship jisme part ka
**lifecycle whole se bound hota hai** — part independently meaningfully
exist nahi karta, aur whole ko destroy karne se uske parts bhi destroy ho
jaate hain.

```text
ParkingLot  *------------  ParkingSpot
  (whole)   filled diamond    (part)
```

**Example, aur cross-reference:** yahi exactly wo relationship hai
`ParkingLot` aur `ParkingSpot` ke beech
`LLD_OOD/02_Interview_Questions/01_parking_lot.md` mein — spots create hote
hain `ParkingLot` ke through aur uske andar store hote hain
(`@spots = Hash.new { |h, k| h[k] = [] }`, jo `add_spots` ke through
populate hota hai), aur kisi lot ke bina spot ka koi meaningful existence
nahi hota. Agar `ParkingLot` object chala jaaye, toh uske spots bhi chale
jaate hain — system mein kahin aur kisi ke paas bhi ek bare `ParkingSpot`
ka independent reference nahi hota.

```ruby
class ParkingSpot
  def initialize(id, spot_type)
    @id = id
    @spot_type = spot_type
  end
end

class ParkingLot
  def initialize
    @spots = Hash.new { |h, k| h[k] = [] }
  end

  def add_spots(spot_type, count)
    # ParkingLot CREATES its ParkingSpots - composition, not just a reference
    count.times { |i| @spots[spot_type] << ParkingSpot.new("#{spot_type}_#{i}", spot_type) }
  end
end
```

Structurally telltale sign yeh hai: aggregation mein, part typically kahin
aur construct hota hai aur whole ko *handed to* kiya jaata hai
(`add_employee(existing_employee)`). Composition mein, whole typically part
ko khud *construct* karta hai (`ParkingSpot.new(...)` `ParkingLot` ke andar
hota hai), aur whole ke bahar koi bhi part ka isolated reference hold karne
ki expectation nahi rakhta.

### Inheritance ("is-a," hollow triangle arrow to parent)

**Definition:** ek subclass relationship — child parent ka ek zyada
specific version **hota hai**, jo uska interface aur behavior inherit
karta hai.

```text
                Vehicle
                    ^
        ____________|____________
       |            |            |
     Bike          Car          Van
```

**Example:** parking lot file se `Vehicle`/`Bike`/`Car`/`Van` hierarchy.
Hollow triangle arrow hamesha **upar** point karta hai, child se parent ki
taraf — `Bike ---|> Vehicle` yeh padha jaata hai "Bike is a Vehicle." Har
subclass `Vehicle` ka interface (`spots_required`) inherit karta hai aur
apna khud ka implementation deta hai, jo ki
`02_oop_fundamentals_for_interviews.md` mein cover kiye gaye polymorphism
ki class-diagram picture hai.

### Realization / Implementation (dashed hollow triangle)

**Definition:** ek class jo kisi interface ya contract ke methods
implement karti hai, uss se koi concrete implementation inherit kiye
bina — un languages mein jahan formal `interface` keyword hota hai, yeh
ek class aur uske implement kiye gaye interface ke beech ka relationship
hai.

```text
       <<interface>>
         PricingStrategy
              ^
              . (dashed)
              |
       HourlyPricing
```

**Ruby mein mapped:** kyunki Ruby mein `interface` keyword nahi hota, yeh
relationship `02_oop_fundamentals_for_interviews.md` ke module/duck-typing
convention se map hota hai — ek class jo ek module `include` karti hai aur
us module ke expect kiye gaye methods implement karti hai (ya ek class jo
simply convention se sahi method names implement karti hai, duck typing
satisfy karte hue, bina kisi shared ancestry ke) — woh UML ke sense mein
uss contract ko "realize" kar rahi hai, chahe Ruby isse structurally
alag express kare kisi class ke literally ek abstract base se inherit
karne ke mukable. Inheritance se distinction: realization ek *contract*
(expected method signatures ka ek set) implement karta hai; inheritance
ek concrete ya semi-concrete parent se actual *implementation* share
karta hai.

```text
Inheritance (solid, hollow triangle):     Realization (dashed, hollow triangle):
  Bike ─────▷ Vehicle                       CreditCardPayment ┄┄┄▷ <<PaymentMethod contract>>
  (inherits Vehicle's code + contract)      (implements the `process` method Ruby-style,
                                              via a NotImplementedError-raising base class
                                              or simply duck typing - no shared code required)
```

## Multiplicity Notation

Multiplicity yeh mark karta hai ki ek class ke kitne instances doosri
class ke kitne instances se relate karte hain, jo relationship line ke
har end pe likha jaata hai:

| Symbol | Meaning |
|---|---|
| `1` | exactly one |
| `0..1` | zero or one (optional single reference) |
| `*` (or `0..*`) | zero or more |
| `1..*` | one or more (at least one required) |

**Worked example:**

```text
ParkingLot  "1" ────────── "*"  ParkingSpot
```

Left se right padhte hue: ek `ParkingLot` bahut saare (`*`, zero ya zyada)
`ParkingSpot`s se relate karta hai. Right se left padhte hue: har
`ParkingSpot` exactly ek (`1`) `ParkingLot` se relate karta hai — ek spot
lots ke beech float nahi karta. Agar instead ek spot theoretically kisi
lot ko assign kiye bina exist kar sakta, toh right-hand side `1` ke bajaye
`0..1` hota. Isi domain se ek doosra example:

```text
Vehicle  "1" ────────── "0..1"  ParkingTicket
```

Ek `Vehicle` ke paas ek time pe zero ya ek active `ParkingTicket` hota hai
(ho sakta hai woh currently parked hi na ho, lekin is design mein kabhi bhi
do simultaneous tickets nahi hold kar sakta) — `0..1` ek hi symbol mein
"optional, aur zyada se zyada ek" capture kar leta hai.

## Practical Interview Guidance

Interview mein aapko almost kabhi bhi ek formally correct, tool-drawn UML
diagram ki zaroorat nahi hoti — koi bhi yeh grade nahi kar raha ki aapke
diamonds ruler se precisely hollow ya filled hain ya nahi. Jo expected
hai woh hai simple ASCII-art ya boxes-and-arrows, chahe hand se draw kiya
ho ya shared doc mein type kiya ho, jo teen cheezein fast correctly convey
kare:

1. **Class names** — aapke design mein nouns kya hain.
2. **Key methods** — sirf woh jo discussion ke liye relevant hain, poora
   attribute/method inventory nahi.
3. **Relationship types** — inheritance vs. composition vs. association,
   correctly distinguish kiya gaya, kyunki yahi actually reveal karta hai
   ki aap object model samajhte ho ya nahi (jo candidate har connection ko
   same plain line se draw karta hai woh signal karta hai ki usne
   ownership aur lifecycle ke baare mein socha hi nahi, chahe class list
   khud correct ho).

Parking lot file ke Step 3 wala diagram jaisa — plain-text boxes,
inheritance ke liye `^`, composition/association ke liye ek comment mein
annotate kiya `[composition]` ya `--->` jaisa word — bilkul sahi level ki
formality hai. Diagram ko tool-perfect banane mein, har attribute ko full
type annotations dene mein, ya har relationship ko textbook-exact
diamond/triangle glyphs se draw karne mein interview time spend karna,
interview ke uss part se time le leta hai jo actually score ho raha
hai: design reasoning aur code. Bas itna diagram use karo ki aap loud
soch sako aur interviewer ko ek map de sako — phir code pe move karo, aur
code ko woh precision carry karne do jo diagram sirf sketch kar raha tha.

## Interview Tips

- Default karo ek quick ASCII sketch pe (boxes, kuch key methods,
  inheritance ke liye `^`, composition/association ke liye ek labeled
  arrow) coding start karne se pehle ya waise hi start karte waqt — yeh
  ek minute se kam time leta hai aur turant misunderstandings surface
  karta hai.
- Jab loud bolke relationship types distinguish karne ko kaha jaaye, to
  lifecycle test use karo: "kya part whole ke bina sense banata hai?"
  Haan → aggregation ya plain association. Nahi → composition. "Kya
  child parent ka actual code/behavior reuse karta hai, ya sirf ek
  method contract satisfy karta hai?" Code reuse → inheritance. Sirf
  contract → realization (Ruby mein module/duck typing).
- Agar interviewer aapse kisi relationship ko formalize karne ko kahe
  jo aapne plain line se draw kiya tha, uska justification ready rakho:
  "Maine `ParkingLot` se `ParkingSpot` ko composition se draw kiya
  kyunki lot apne spots ko construct karta hai aur own karta hai — is
  design mein `ParkingSpot` ke independently exist karne ka koi rasta
  nahi hai."
- Diagram mein zyada over-invest mat karo. Agar aapko lagta hai ki aap
  box formatting perfect karne mein ek-do minute se zyada spend kar rahe
  ho, toh yeh sign hai code pe move karne ka — diagram conversation ke
  liye scaffolding hai, deliverable nahi.
- Multiplicity ko verbally mention karna worth hai chahe aap use diagram
  pe annotate na karo: "har `Vehicle` ke paas zyada se zyada ek active
  `ParkingTicket` hota hai" bolna `0..1` draw kiye bina bhi wahi
  precision demonstrate kar deta hai.

## Quick Recall — Self-Test

1. **UML class box ke teen compartments kya hain, aur `+`, `-`, aur `#`
   ka kya matlab hai?**
   Class name, attributes, aur methods. `+` kisi member ko public mark
   karta hai, `-` private, aur `#` protected.

2. **Aggregation aur composition ko distinguish karne ka structural test
   kya hai?**
   Kya part whole ke lifecycle se independently exist kar sakta hai.
   Aggregation: part typically kahin aur construct hota hai aur handed in
   hota hai, aur whole ke destruction ko survive karta hai (ek `Employee`
   ek dissolve hue `Department` se outlive karta hai). Composition: whole
   typically part ko khud construct karta hai, aur part ka uske bahar
   koi meaningful existence nahi hota (ek `ParkingSpot` ka apne
   `ParkingLot` ke bina koi purpose nahi hota).

3. **Parking lot example mein, `ParkingLot` aur `ParkingSpot` ke beech
   relationship aggregation hai ya composition? Structurally justify
   karo, sirf definition se nahi.**
   Composition. `ParkingLot#add_spots` khud `ParkingSpot` instances
   construct karta hai (`ParkingSpot.new(...)` `ParkingLot` ke andar
   hota hai), aur system ka koi aur part ek bare, lot-less `ParkingSpot`
   hold ya expect nahi karta — part whole ke through create hota hai
   aur usi tak scoped hota hai.

4. **UML notation mein inheritance ko realization/implementation se kya
   visually distinguish karta hai, aur dono Ruby mein kaise map hote
   hain?**
   Dono hollow triangle arrowhead use karte hain jo parent/interface ki
   taraf point karta hai, lekin inheritance solid line use karta hai aur
   realization dashed line use karta hai. Inheritance Ruby ke
   `class Bike < Vehicle` se map hota hai (shared code aur contract);
   realization Ruby ke module/duck-typing convention se map hota hai —
   expected methods implement karna (often `NotImplementedError` ke
   through ek base class mein enforce kiya gaya) bina zaroori concrete
   ancestor share kiye.

5. **Multiplicity `ParkingLot "1" --- "*" ParkingSpot` ka kya matlab hai,
   dono directions mein padhte hue?**
   Left se right padho: ek `ParkingLot` bahut saare (zero ya zyada)
   `ParkingSpot`s se relate karta hai. Right se left padho: har
   `ParkingSpot` exactly ek `ParkingLot` ka hota hai.

6. **Ek candidate apne design mein har relationship — inheritance,
   composition, aur plain association — ko same undifferentiated line
   se draw karta hai. Yeh interviewer ko kya signal karta hai, chahe
   class list khud otherwise correct ho?**
   Yeh signal karta hai ki candidate ne objects ke beech ownership aur
   lifecycle relationships ke baare mein socha hi nahi, chahe usne sahi
   classes identify kar li hon. Relationship type wahi jagah hai jahan
   actual design reasoning rehti hai; ek uniform line woh distinction
   flatten kar deti hai aur aisa lagta hai jaise usko consider hi nahi
   kiya gaya.

7. **Association aggregation se kaise differ karta hai? Dono ka ek-ek
   example do.**
   Association ek general "uses/knows about" relationship hai jisme
   koi whole/part structure bilkul bhi implied nahi hoti (ek `Driver`
   us `Car` se associate karta hai jo woh currently drive kar raha hai —
   koi bhi doosre ko own nahi karta). Aggregation specifically ek
   whole/part structure imply karta hai jahan part whole se outlive kar
   sakta hai (ek `Department` ke paas `Employee`s hote hain jo agar
   department dissolve ho jaaye toh kahin aur employed rehte hain).

8. **Interview mein hand-drawn ASCII diagram usually sufficient kyun
   hota hai, aur uske over-formatting ka actual risk kya hai?**
   Interviewers evaluate kar rahe hain ki aapka diagram class names, key
   methods, aur relationship types correctly convey karta hai ya nahi —
   yeh nahi ki woh tool-perfect UML hai ya nahi. Over-formatting ka risk
   (precise diamond/triangle glyphs, types ke saath full attribute
   lists) yeh hai ki aap interview time presentation polish pe spend
   kar rahe ho design reasoning aur code ke bajaye jo actually score ho
   rahe hain.

# Design a Car Rental System (Object-Oriented Design)

## Problem Statement

"Design a car rental system. Multiple rental locations hain, har ek ki
apni vehicles ki inventory categories ke across (economy, SUV, luxury).
Ek customer ek given category ka vehicle search karta hai, ek given date
range ke liye, ek given location par available, aur usse reserve karta hai.
System ko rental ki pricing karni hai aur reservation ko booking se return
tak track karna hai."

Is problem mein trap yeh hai ki inheritance ki taraf bahut jaldi reach kar
lo — `Economy < Vehicle`, `SUV < Vehicle`, `Luxury < Vehicle` — kyunki yeh
pattern Parking Lot problem mein achha kaam kiya tha. Yeh automatically
yahan transfer nahi hota, aur yeh notice karna ki *kyun* nahi hota, khud
ek good answer ka part hai. Is problem ka actual hard part future date
ranges ke across availability checking hai, category modeling nahi.

## Step 1: Clarify Requirements

**Functional Requirements**
- Multiple `RentalLocation`s, har ek ki apni vehicle inventory.
- Search: ek category, ek date range, aur ek location diya gaya, us category
  ke vehicles return karo jinki us range mein koi conflicting reservation
  nahi hai.
- Ek date range ke liye vehicle reserve karo; reservation status track karo
  (reserved, active/picked-up, completed/returned, cancelled).
- Vehicle category, rental duration, aur potentially seasonal/demand
  multipliers ke basis par price compute karo.
- Ek existing reservation ki end date extend karo, conflicts ko phir se
  check karte hue.
- One-way rentals support karo: ek location par pick up karo, doosri par
  return karo.

**Non-Functional Requirements**
- **Correct overlap detection**: reservations future date ranges ke liye
  banti hain, sirf "kya yeh car abhi bahar hai" nahi — availability check
  genuinely range-based honi chahiye, jo is problem mein rush karne par
  subtle bugs ka main source hai.
- **Pricing ki extensibility**: naye pricing dimensions (loyalty tiers,
  seasonal demand) ko existing pricing rewrite kiye bina compose hona
  chahiye — yeh phir se Strategy ki taraf point karta hai.
- **Vehicle behavior ko over-model mat karo**: is domain mein category
  differences almost entirely *data* ke baare mein hain (base rate, seating
  capacity), *behavior* ke baare mein nahi — yeh explicitly bolna worth
  hai kyunki yeh Parking Lot ki `Vehicle` hierarchy ka opposite lesson hai,
  aur interview pressure ke andar in dono ko conflate karna ek common
  mistake hai.

## Step 2: Identify Core Objects / Entities

- **Vehicle** — ek physical car: make, model, category, license plate,
  home `RentalLocation`. Step 4 dekho ki yeh ek single class kyun hai ek
  `category` attribute ke saath, `Economy`/`SUV`/`Luxury` subclass
  hierarchy ke bajaye.
- **RentalLocation** (branch) — `Vehicle`s ki ek inventory owns karta hai,
  apne aap tak scoped availability search expose karta hai.
- **Reservation** — central association object: `customer`, `vehicle`,
  `pickup_location`, `return_location`, `start_date`, `end_date`, `status`.
  Yeh wahi recurring shape hai jo is folder mein aur jagah dikhi hai —
  `ParkingTicket` (Parking Lot), ek `Loan` (Library), ek booked
  `Seat`/`Booking` (Ticket Booking) — ek explicit object jo *do entities ke
  beech ek transaction* represent karta hai, dono entities ko ek doosre ka
  state directly mutate karwane ke bajaye. Is series ke is point tak, isse
  apna ek pattern maan kar naam dena worth hai: jab bhi do domain objects ko
  ek time-bounded relationship chahiye apni khud ki status aur history ke
  saath, us relationship ko ek first-class object ki tarah model karo,
  kisi bhi side par flags bolt mat karo.
- **PricingStrategy** — ek `Reservation` ke vehicle category aur duration
  se (aur baad mein, loyalty tier / seasonal multiplier) cost compute karta
  hai, `Reservation` se poori tarah alag rakha gaya.

## Step 3: Identify Relationships (Class Diagram)

```text
  Vehicle
  - id, make, model, category (:economy | :suv | :luxury)
  - license_plate
  - home_location ---> RentalLocation

  RentalLocation
  - id, name
  - vehicles: [Vehicle]                    (composition: owns its inventory)
  - reservations: [Reservation]
  + available_vehicles(category, start_date, end_date) : [Vehicle]
  + reserve(customer, vehicle, start_date, end_date, return_location) : Reservation

  Reservation
  - customer ------------> Customer
  - vehicle --------------> Vehicle
  - pickup_location -------> RentalLocation
  - return_location -------> RentalLocation      (may differ: one-way rental)
  - start_date, end_date
  - status: :reserved | :active | :completed | :cancelled
  - price: Money                                  (computed via PricingStrategy)

  PricingStrategy (interface)             StandardPricing
  + calculate(reservation) : Money    <--------  implements  --------  (+ SeasonalPricing, LoyaltyPricing...)
```

Relationship types:
- `RentalLocation` apni `Vehicle` inventory ko **composes** karta hai (ek
  vehicle exactly ek home location ki inventory ka hissa hota hai;
  composition).
- `Reservation` `Customer`, `Vehicle`, aur do `RentalLocation`s ko
  **associate** karta hai — inme se koi bhi reservation ke through owned
  nahi hai, har ek ki independent lifecycle hai (association, ownership
  nahi) — yahi Step 2 mein bataya gaya "explicit association object"
  pattern hai.
- `RentalLocation` reservations ko price karne ke liye ek `PricingStrategy`
  **uses-a** hai (injected, association) — classic Strategy pattern.
- `StandardPricing`/`SeasonalPricing`/`LoyaltyPricing` sab `PricingStrategy`
  ko **implement** karte hain (interface implementation).

## Step 4: Design Decisions & Patterns Used

**`Vehicle` ek class kyun hai ek `category` attribute ke saath, har
category ke liye ek subclass nahi — aur yeh Parking Lot ki `Vehicle`
hierarchy se DIFFERENT kyun hai.** Parking Lot mein, `Bike`/`Car`/`Van`
genuinely *behavior* mein differ karte hain — har ek `spots_required
(spot_type)` ko alag implement karta hai, aur woh method polymorphically
un code se call hota hai jise pata nahi hota woh kaunsa vehicle type hold
kar raha hai. Wahi wo moment hai jab inheritance/polymorphism apni keep
kamata hai. Yahan, "Economy" vs. "SUV" vs. "Luxury" behavior mein bilkul
differ nahi karte — is system mein kuch bhi kisi aise method ko call nahi
karta jise `SUV` `Luxury` se alag implement kare. Woh sirf *data* mein
differ karte hain: base rental rate, seating capacity, shayad fuel type.
Isko ek subclass hierarchy (`class SUV < Vehicle`) ki tarah model karne ka
matlab hoga ki data differences ka har ek instance ek overridden constant
ya ek literal return karne wala method ban jaaye — inheritance ka use
sirf data carry karne ke liye, jo ek smell hai. Sahi call hai ek single
`Vehicle` class jiske paas ek `category` symbol/enum attribute ho, jahan
category-specific *values* (base rate, waghera) ek lookup table mein ya
`PricingStrategy` mein rahein, class hierarchy mein nahi. Yeh
`LLD_OOD/01_Concepts/02_oop_fundamentals_for_interviews.md` ki
composition-over-inheritance guidance directly apply karne jaisa hai:
inheritance/polymorphism ki taraf reach karo jab behavior genuinely type ke
saath vary karta ho, sirf isliye nahi kyunki ek `Vehicle` hierarchy "last
time kaam kiya tha." Agar baad mein koi genuine behavioral difference
appear ho (jaise `ElectricVehicle` ko charging-station logic chahiye jo gas
vehicles ko nahi chahiye), toh wahi moment hai us specific behavior ke
liye ek subclass ya ek chhota mixin introduce karne ka — pehle nahi.

**`Reservation` ek explicit object kyun hai, `Vehicle` aur `Customer` par
flags ke bajaye.** Naive design `vehicle.rented = true` mark karta hai aur
`customer.rented_vehicles` mein append karta hai. Yeh turant do real
requirements ke against break hota hai: reservations *future* date ranges
ke liye banti hain (ek boolean "kya yeh rented hai" "abhi available hai,
lekin agle Tuesday se booked hai" represent nahi kar sakta), aur ek
reservation ki apni lifecycle hoti hai (reserved -> active -> completed, ya
cancelled) jo kisi bhi side ke state par cleanly map nahi hoti. Ek explicit
`Reservation` object khud date range aur status hold karta hai, isliye
availability checking ban jaati hai "kya is vehicle ke liye koi
`Reservation` is range ko overlap karti hai," aur lifecycle transitions
reservation par hote hain, vehicle ko mutate karke nahi. Jaise Step 2 mein
note kiya gaya, yeh wahi shape hai `ParkingTicket`, `Loan`, aur
ticket-booking ke `Booking` jaisi — is repeated pattern ko recognize karna
(association-with-a-lifecycle ko apna object chahiye) zubaan se bolne
layak hai; yeh signal karta hai ki aap har LLD problem scratch se solve
nahi kar rahe, ek recurring shape recognize kar rahe hain.

**`PricingStrategy` ko `Reservation` se kyun pull out kiya.** Pricing logic
(base rate x duration, plus seasonal/demand multipliers, plus baad mein ek
loyalty discount) reservation lifecycle logic se kahin zyada baar aur
kahin zyada independent dimensions ke saath change hoti hai. `calculate
(reservation)` ko ek alag, injectable `PricingStrategy` par rakhne ka
matlab hai `Reservation` ko kabhi change nahi karna padta jab ek nayi
pricing rule add ho — sirf ek nayi `PricingStrategy` implementation
change hoti hai, aur woh existing ones ke saath compose hoti hai (Follow-up
1 dekho).

## Step 5: Code

```ruby
class Vehicle
  attr_reader :id, :make, :model, :category, :license_plate, :home_location

  def initialize(id, make:, model:, category:, license_plate:, home_location:)
    @id = id
    @make = make
    @model = model
    @category = category # :economy | :suv | :luxury
    @license_plate = license_plate
    @home_location = home_location
  end
end

class Reservation
  attr_reader :customer, :vehicle, :pickup_location, :return_location, :start_date, :end_date
  attr_accessor :status, :price

  def initialize(customer:, vehicle:, pickup_location:, return_location:, start_date:, end_date:)
    @customer = customer
    @vehicle = vehicle
    @pickup_location = pickup_location
    @return_location = return_location
    @start_date = start_date
    @end_date = end_date
    @status = :reserved
    @price = nil
  end

  # Two date ranges overlap unless one ends before the other starts.
  # This is the crux of correct availability checking in this problem.
  def overlaps?(other_start, other_end)
    return false if [:cancelled, :completed].include?(@status)

    !(other_end < @start_date || other_start > @end_date)
  end
end

class RentalLocation
  attr_reader :id, :name

  def initialize(id, name, pricing_strategy: StandardPricing.new)
    @id = id
    @name = name
    @vehicles = []          # inventory homed at this location
    @reservations = []      # every reservation ever made picking up here
    @pricing_strategy = pricing_strategy
  end

  def add_vehicle(vehicle)
    @vehicles << vehicle
  end

  # The core non-trivial method in this problem: vehicles of `category`
  # homed here, with no existing (non-cancelled/completed) reservation
  # that overlaps [start_date, end_date].
  def available_vehicles(category, start_date, end_date)
    @vehicles.select do |vehicle|
      vehicle.category == category &&
        @reservations.none? { |r| r.vehicle == vehicle && r.overlaps?(start_date, end_date) }
    end
  end

  def reserve(customer, vehicle, start_date, end_date, return_location: self)
    conflict = @reservations.any? { |r| r.vehicle == vehicle && r.overlaps?(start_date, end_date) }
    raise "vehicle unavailable for that range" if conflict

    reservation = Reservation.new(
      customer: customer, vehicle: vehicle,
      pickup_location: self, return_location: return_location,
      start_date: start_date, end_date: end_date
    )
    reservation.price = @pricing_strategy.calculate(reservation)
    @reservations << reservation
    reservation
  end

  # Re-check conflicts against the SAME overlap logic before committing —
  # extending a reservation is just "would a new reservation with the
  # extended range conflict with anything else."
  def extend_reservation(reservation, new_end_date)
    conflict = @reservations.any? do |r|
      r != reservation && r.vehicle == reservation.vehicle && r.overlaps?(reservation.start_date, new_end_date)
    end
    raise "extension conflicts with another reservation" if conflict

    reservation.instance_variable_set(:@end_date, new_end_date)
    reservation.price = @pricing_strategy.calculate(reservation)
    reservation
  end
end

class StandardPricing
  DAILY_RATE = { economy: 30, suv: 55, luxury: 120 }.freeze

  def calculate(reservation)
    days = (reservation.end_date - reservation.start_date).to_i + 1
    DAILY_RATE.fetch(reservation.vehicle.category) * days
  end
end
```

**Isse use karna — one-way rental case sameth:**

```ruby
downtown = RentalLocation.new(1, "Downtown")
airport  = RentalLocation.new(2, "Airport")

civic = Vehicle.new(101, make: "Honda", model: "Civic", category: :economy,
                     license_plate: "ABC-123", home_location: downtown)
downtown.add_vehicle(civic)

downtown.available_vehicles(:economy, Date.new(2026, 9, 20), Date.new(2026, 9, 25))
# => [civic]   (no conflicting reservation yet)

res = downtown.reserve(customer, civic, Date.new(2026, 9, 20), Date.new(2026, 9, 25),
                        return_location: airport) # one-way: picked up downtown, returned at airport
res.price # => 30 * 6 = 180

downtown.available_vehicles(:economy, Date.new(2026, 9, 22), Date.new(2026, 9, 23))
# => []   (overlaps the existing reservation's range)

downtown.available_vehicles(:economy, Date.new(2026, 9, 26), Date.new(2026, 9, 28))
# => [civic]   (no overlap — starts the day after the existing reservation ends)
```

## Step 6: Edge Cases & Extensibility

- **Do customers ek category ke last available vehicle ke liye race kar
  rahe hain.** Upar wale `available_vehicles` aur `reserve` do alag
  reads/writes hain — concurrency ke under, do requests dono vehicle ko
  available dekh sakte hain aur dono usse reserve karne ki koshish kar
  sakte hain. Yeh ek real concern hai, lekin yeh explicitly ek
  HLD/infrastructure-level fix hai, LLD layer par over-design karne wali
  cheez nahi: database level par ek unique constraint (jaise, same vehicle
  ke liye do non-cancelled reservations overlapping ranges ke saath nahi ho
  sakte, ek DB exclusion constraint ke through ya optimistic
  locking/version column ke saath ek application-level compare-and-swap ke
  through enforce kiya gaya) is file mein ek poori concurrency solution
  build kiye bina naam lene layak sahi answer hai.
- **Ek existing reservation ki end date extend karna.** Naye reservations
  ke liye use hone wala exact same overlap check re-run hona chahiye
  (upar wala `extend_reservation`), extend ho rahi reservation ko khud
  conflict check se exclude karte hue (`r != reservation`) — ek common bug
  hai khud usi reservation samet sab reservations ke against check karna,
  jo hamesha "khud se conflict" dega.
- **One-way rentals aur per-location inventory tracking.** Ek `Reservation`
  `pickup_location` aur `return_location` ko alag alag track karti hai; jab
  `:completed` status ho jaaye (return process ho chuka), vehicle ki
  *effective* location future availability searches ke liye reflect karni
  chahiye ki woh kahan return hui thi, `vehicle.home_location` nahi. Clean
  fix: ek location par `available_vehicles` ko actually "abhi is location
  par jo vehicles hain" ke basis par scope hona chahiye (derivable
  most-recent completed reservation ki `return_location` se, ya
  `home_location` se agar kabhi rent nahi hui) — yeh refinement explicitly
  bolna worth hai, kyunki naively hamesha `home_location` par bharosa karna
  ek one-way-rented car ko permanently ek aisi location ka "belong" bana
  dega jahan woh physically hai hi nahi.
- **Ek reservation cancel karna.** `status = :cancelled` set karna kaafi
  hai kyunki `overlaps?` already cancelled/completed reservations ko
  conflict checks se exclude karta hai — koi alag cleanup nahi chahiye, jo
  status ko external bookkeeping ke bajaye `Reservation` PAR rakhne ka
  direct payoff hai.
- **Zero-length ya inverted date ranges** (`end_date < start_date`): koi
  bhi overlap logic chalne se pehle `reserve`/`extend_reservation` boundary
  par reject karo — ek guard clause layak hai, aur mention karne layak hai
  chahe live code na ho.

## Follow-up Questions an Interviewer Might Ask

1. **"Pricing mein ek loyalty/membership discount tier kaise add
   karoge?"** Isse `StandardPricing` edit karne ke bajaye `PricingStrategy`
   par compose karo — ya toh ek `LoyaltyPricing` decorator jo ek base
   strategy ko wrap kare (`LoyaltyPricing.new(StandardPricing.new,
   discount: 0.10)` jo base price compute kare phir discount apply kare),
   ya ek strategy jo customer ke tier ko directly account mein le. Decorator
   form specifically naam lene layak hai: isse loyalty discounts, seasonal
   multipliers, aur base category pricing sab independently stack ho sakte
   hain bina ek doosre ke baare mein jaane.
2. **"Late returns aur penalty pricing kaise handle karoge?"** `Reservation`
   mein ek `actual_return_date` add karo, jab status `:completed` mein
   transition ho tab set ho; agar `actual_return_date > end_date`, toh ek
   `LateFeeCalculator` (ek aur chhota Strategy-shaped object, ya
   `PricingStrategy` par ek method) overage ke basis par ek additional
   charge compute kare — original `price` se alag rakha gaya taaki
   reservation "base price" aur "late fee" ko alag line items ki tarah
   dikha sake, ek opaque total ke bajaye.
3. **"Agar customer ko SAARI locations ke across search karna ho, ek nahi?"**
   Ek `RentalNetwork`/`RentalCompany` add karo jo multiple
   `RentalLocation`s ko own kare aur unke across `available_vehicles`
   aggregate kare — Parking Lot ke "multiple floors add karo" follow-up jaisi
   hi shape: aggregator sirf query ko fan out karta hai aur results merge
   karta hai, `RentalLocation` mein khud koi change nahi.
4. **"Add-ons — insurance, GPS, child seat — kaise model karoge?"** Ek
   `Reservation` par attached optional line items ki tarah (ek chhota
   `AddOn` value object apni khud ki price ke saath), final total mein sum
   kiya gaya `PricingStrategy` ya ek thin `Invoice` object jo reservation
   ko wrap karta hai ke through — deliberately `Vehicle` se door rakha
   gaya, kyunki add-ons booking ki property hain, physical car ki nahi.
5. **"Availability logic ko specifically kaise test karoge?"**
   `Reservation#overlaps?` ko directly aur exhaustively classic interval
   cases ke saath unit-test karo (fully before, fully after, exact match,
   partial overlap har side par, ek range doosre ko fully contain kare) —
   yahi wo jagah hai jahan is problem mein off-by-one bugs actually rehte
   hain, aur `RentalLocation` se complete isolation mein test karna cheap
   hai.
6. **"Yeh ek peer-to-peer rental system se (jaise Turo) kaise different
   hai, jahan 'inventory' individual hosts ke through owned hoti hai, ek
   company with branches ke through nahi?"** Core `Reservation`/overlap-
   checking/`PricingStrategy` design barely change hoti hai; jo change
   hota hai woh hai `RentalLocation` ka ek `Host` ki listing ke close ho
   jaana plus ek pickup/dropoff location jo host har vehicle ke liye define
   karta hai, aur ownership/approval workflows (ek host ka ek booking
   request approve karna) upar add ho jaate hain — yeh note karne ka achha
   moment hai ki Step 2 ka *transaction-object* pattern hi stable rehta hai
   is variation ke across.

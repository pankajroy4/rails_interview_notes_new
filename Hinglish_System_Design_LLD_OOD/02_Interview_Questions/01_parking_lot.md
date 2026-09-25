# Design a Parking Lot (Object-Oriented Design)

## Problem Statement

"Design a parking lot using OOP. It should track the total number of spots,
remaining spots, whether the lot is full or empty. There are different
vehicle types (bike, car, van) and different spot types. A van can also
park in a bike spot, but it takes up 3 bike spots. Tell me the number of
remaining spots per vehicle type, and whether parking for vans specifically
is full."

Ye ek real question hai jo ek small/mid-size product company ke interview mein
pucha gaya tha — aur ye achha question isliye hai kyunki "van 3 bike spots
leta hai" wala rule jaan-boojh kar plant kiya gaya hai ye dekhne ke liye ki
aap **polymorphism** ka use karte ho ya phir apni parking-lot class mein
`if vehicle_type == :van` jaise checks ka dher laga dete ho. Doosra approach
is interview mein fail hota hai chahe code technically kaam kyun na kare.

## Step 1: Clarify Requirements

**Functional Requirements**
- Parking spots ko type ke hisaab se track karna (bike spot, car spot, van spot).
- Ek vehicle ko park karna: appropriate spot (ya spots) dhundhna aur occupy karna.
- Vehicle ko un-park karna: jo bhi spot(s) wo occupy kar raha tha unhe free karna.
- Ek van **bike spot** mein park ho sakta hai, lekin ek saath **3 bike spots**
  consume karta hai (ye wahi rule hai jo interviewer ne explicitly plant kiya
  hai — ise ek general "kuch vehicles ek chhota/different spot type use kar
  sakte hain lekin ek se zyada consume karte hain" rule ki tarah treat karo,
  ek one-off special case ki tarah nahi).
- Har spot type ke liye report karna: total spots, remaining spots, is full,
  is empty.

**Non-Functional Requirements (jo ek strong candidate LLD interview mein bhi
zor de kar bolta hai — ye justify karte hain ki *kyun* aap design ek particular
tarike se karte ho)**
- **Extensibility**: naya vehicle type add karna (jaise Truck) ya naya spot
  type add karna, existing classes edit karne se nahi, ek naya class add
  karne se hona chahiye (Open/Closed Principle).
- **Single responsibility**: `ParkingLot` mein per-vehicle business rules nahi
  hone chahiye; vehicle ko khud apni spot requirements pata honi chahiye.
- Exit ke time correctness: jab ek van (3 spots occupy karke) nikalta hai, to
  **saare 3** spots ek saath free hone chahiye, sirf ek nahi.

## Step 2: Identify Core Objects / Entities

Problem statement mein nouns dhundo — usually wahi aapki class list hoti hai:

- **Vehicle** (abstract) → `Bike`, `Car`, `Van` — har vehicle instance.
- **ParkingSpot** — ek single physical spot, jiska type aur occupancy state hota hai.
- **ParkingTicket** — ek active parking session ko represent karta hai; track
  karta hai ki ek vehicle kaunse spot(s) occupy kar raha hai (yahi object hai
  jo "saare 3 spots ek saath free karo" requirement ko messy hone se bacha kar
  trivial bana deta hai).
- **ParkingLot** — spots ka collection own karta hai, parking/un-parking
  orchestrate karta hai, aggregate queries (full/empty/remaining) ka jawaab
  deta hai.

## Step 3: Identify Relationships (Class Diagram)

```text
                 Vehicle (abstract)
                 - license_plate
                 + spots_required(spot_type) : Integer   [abstract]
                      ^
        ___________|___________
       |            |           |
     Bike          Car         Van
  (1 bike_spot) (1 car_spot)  (1 van_spot, OR 3 bike_spot)

  ParkingSpot                    ParkingTicket
  - id                           - vehicle -----------> Vehicle
  - spot_type                    - spot_ids[] ---------> [ParkingSpot.id]
  - occupied_by ---> Vehicle|nil

  ParkingLot
  - spots: { spot_type => [ParkingSpot] }     (composition: owns the spots)
  - tickets: { license_plate => ParkingTicket }
  + add_spots(spot_type, count)
  + park(vehicle) : ParkingTicket
  + unpark(vehicle) : Boolean
  + total_spots(spot_type) / remaining_spots(spot_type)
  + full?(spot_type) / empty?(spot_type)
```

Relationship types, precisely (ye exact vocabulary hai jo interviewer sun kar
dhoondh raha hota hai):
- `Bike`/`Car`/`Van` `Vehicle` se **inherit** karte hain (is-a).
- `ParkingLot`, `ParkingSpot`s ko **compose** karta hai — spots lot ke bina
  independently exist nahi karte; agar lot destroy ho jaaye to uske spots bhi
  destroy ho jaate hain (composition, aggregation nahi).
- `ParkingSpot`, `occupied_by` ke through `Vehicle` se **associate** hota
  hai — ek spot ek vehicle ko reference karta hai, lekin vehicle ki lifecycle
  spot se independent hoti hai (association, ownership nahi).
- `ParkingTicket`, ek `Vehicle` ko un `ParkingSpot`s se associate karta hai jo
  wo hold karta hai — yahi wo object hai jo "multi-spot" requirement ko
  cleanly solve karta hai.

## Step 4: Design Decisions & Patterns Used

**`ParkingLot` mein case statement ki jagah polymorphism kyun.** Naive
approach `ParkingLot` ke andar `if vehicle.type == :van && spot.type ==
:bike_spot then needs = 3` jaisa logic daal deta hai. Ye Single
Responsibility (ab lot ko har vehicle ka parking rule pata hai) aur
Open/Closed (naya `Truck` add karne ke liye `ParkingLot` edit karna padega)
dono violate karta hai. Iski jagah, har `Vehicle` subclass `spots_required(spot_type)`
implement karta hai aur khud apna jawaab deta hai. `ParkingLot` sirf ye pucha
hai "yahan tumhe kitne chahiye?" aur kabhi vehicle type par branch nahi karta.
Ye effectively **Strategy pattern** hai — har vehicle apni khud ki
spot-allocation strategy carry karta hai.

**Spots ko sirf occupied mark karne ke bajaye `ParkingTicket` object kyun.**
Ticket ke bina, van ko un-park karna matlab kisi tarah "ye exact van kaunse
spots par hai" ye search karke dhundhna hoga — error-prone aur slow. Ticket
park-time par spot IDs capture kar leta hai, isliye un-parking ek direct
lookup aur release ban jaata hai, aur ye baad mein park-time, duration-based
pricing waghera add karne ke liye ek natural jagah bhi deta hai, wo bhi
`ParkingSpot` ko touch kiye bina.

**Spots ko ek flat list ki jagah `spot_type => [spots]` hash mein group kyun
kiya gaya.** Har required query (`total_spots(:bike_spot)`,
`remaining_spots(:van_spot)`) naturally spot type se scoped hoti hai —
upfront grouping karne se har ek query O(spots of that type) ban jaati hai,
uske bajaye ki har baar sab kuch scan karke filter kiya jaaye.

## Step 5: Code

```ruby
class Vehicle
  attr_reader :license_plate

  def initialize(license_plate)
    @license_plate = license_plate
  end

  # How many spots of `spot_type` this vehicle needs to park here.
  # Float::INFINITY means "this vehicle cannot use this spot type at all."
  def spots_required(spot_type)
    raise NotImplementedError, "#{self.class} must implement spots_required"
  end
end

class Bike < Vehicle
  def spots_required(spot_type)
    spot_type == :bike_spot ? 1 : Float::INFINITY
  end
end

class Car < Vehicle
  def spots_required(spot_type)
    spot_type == :car_spot ? 1 : Float::INFINITY
  end
end

class Van < Vehicle
  def spots_required(spot_type)
    case spot_type
    when :van_spot  then 1
    when :bike_spot then 3   # the interview's planted rule, isolated here
    else Float::INFINITY
    end
  end
end

class ParkingSpot
  attr_reader :id, :spot_type
  attr_accessor :occupied_by

  def initialize(id, spot_type)
    @id = id
    @spot_type = spot_type
    @occupied_by = nil
  end

  def occupied?
    !@occupied_by.nil?
  end
end

class ParkingTicket
  attr_reader :vehicle, :spot_ids

  def initialize(vehicle, spot_ids)
    @vehicle = vehicle
    @spot_ids = spot_ids
  end
end

class ParkingLot
  def initialize
    @spots = Hash.new { |h, k| h[k] = [] }   # spot_type => [ParkingSpot]
    @tickets = {}                             # license_plate => ParkingTicket
  end

  def add_spots(spot_type, count)
    offset = @spots[spot_type].size
    count.times { |i| @spots[spot_type] << ParkingSpot.new("#{spot_type}_#{offset + i}", spot_type) }
  end

  def total_spots(spot_type)
    @spots[spot_type].size
  end

  def remaining_spots(spot_type)
    @spots[spot_type].count { |s| !s.occupied? }
  end

  def full?(spot_type)
    remaining_spots(spot_type).zero?
  end

  def empty?(spot_type)
    remaining_spots(spot_type) == total_spots(spot_type)
  end

  # Tries spot types most-specific-first (a van's own spot before it
  # cannibalizes 3 bike spots), and picks the first type where enough
  # free spots of that type exist.
  def park(vehicle, preferred_order = [:van_spot, :car_spot, :bike_spot])
    preferred_order.each do |spot_type|
      needed = vehicle.spots_required(spot_type)
      next if needed == Float::INFINITY

      free = @spots[spot_type].reject(&:occupied?)
      next if free.size < needed

      chosen = free.first(needed)
      chosen.each { |s| s.occupied_by = vehicle }
      ticket = ParkingTicket.new(vehicle, chosen.map(&:id))
      @tickets[vehicle.license_plate] = ticket
      return ticket
    end
    nil # no spot type could accommodate this vehicle right now
  end

  def unpark(vehicle)
    ticket = @tickets.delete(vehicle.license_plate)
    return false unless ticket

    all_spots = @spots.values.flatten
    ticket.spot_ids.each do |id|
      spot = all_spots.find { |s| s.id == id }
      spot.occupied_by = nil
    end
    true
  end
end
```

**Isko use karte hue:**

```ruby
lot = ParkingLot.new
lot.add_spots(:bike_spot, 5)
lot.add_spots(:car_spot, 3)
lot.add_spots(:van_spot, 1)

van = Van.new("VAN-001")
ticket = lot.park(van)          # parks in the dedicated van_spot first
lot.remaining_spots(:van_spot)  # => 0
lot.full?(:van_spot)            # => true

van2 = Van.new("VAN-002")
lot.park(van2)                  # no van_spot left, falls back to 3 bike spots
lot.remaining_spots(:bike_spot) # => 2   (5 - 3)

lot.unpark(van2)
lot.remaining_spots(:bike_spot) # => 5   (all 3 freed together, via the ticket)
```

Original interview ka har sub-question directly answer ho jaata hai:
`total_spots`, `remaining_spots`, `full?`, `empty?` — sab spot type se
parameterized hain, isliye "kya van parking full hai" bas
`lot.full?(:van_spot)` hai, aur 3-bike-spot wala rule `Van#spots_required`
ke bahar kabhi appear hi nahi hota.

## Step 6: Edge Cases & Extensibility

- **Ek `Truck` add karna jise 2 car spots ya 6 bike spots chahiye**:
  `class Truck < Vehicle` likho jo `spots_required` implement kare —
  `ParkingLot`, `ParkingSpot`, ya `ParkingTicket` mein zero changes. Ye
  Open/Closed Principle ka directly fayda hai, aur exactly wahi hai jo
  interviewer test karta hai jab wo aapke first pass ke turant baad "ab ek
  naya vehicle type add karo" pucha jaata hai.
- **Ek vehicle jo already parked hai wo dobara park karne ki koshish kare**:
  `park` ko pehle `@tickets.key?(vehicle.license_plate)` check karna chahiye
  aur double-allocating spots karne ke bajaye existing ticket reject/return
  karna chahiye — agar live code na bhi karo to mention karne wali achhi
  baat hai.
- **Partial spot availability** (jaise, sirf 2 bike spots free hain aur van
  ko 3 chahiye): current `park` correctly `free.size < needed` find karta
  hai aur agle spot type try karne chala jaata hai (ya fail ho jaata hai) —
  ye 2 spots ko partially occupy NAHI karta. Ye explicitly point out karo;
  time pressure mein ye ek common bug hai.
- **Pricing/duration**: `ParkingTicket` `entry_time` add karne ke liye
  natural jagah hai, aur ek `Pricing` strategy object (phir se Strategy
  pattern) jo `Time.now - entry_time` aur vehicle type se cost calculate
  kare — ek common immediate follow-up question hai.
- **Thread-safety** (agar pucha jaaye "agar exact same time par do log park
  karein to kya hoga"): `park` method ka read-then-write free spots par ek
  race condition hai concurrency ke under — fix ke tor par
  find-and-occupy step ke around mutex/lock, ya har spot ke state par atomic
  compare-and-swap mention karo. Agar interviewer "ab imagine karo ye multiple
  servers ke across run hota hai" ki taraf push kare to ye ek achha bridge
  hai — us point par aap HLD territory mein le jaaye ja rahe ho (dekho
  `System_Design/01_Concepts/09_distributed_systems_core.md` distributed
  locks ke liye), jise explicitly naam lena worth hai ye dikhane ke liye ki
  aapko LLD/HLD boundary pata hai.

## Follow-up Questions an Interviewer Might Ask

1. **"Multiple floors ka support add karo."** Ek `Floor` class add karo jo
   apna khud ka `spots` hash own kare (wahi structure jo abhi `ParkingLot` ke
   paas hai); `ParkingLot` `Floor`s ka collection ban jaata hai aur unke
   across totals aggregate karta hai. Per-type query methods barely change
   hote hain — wo bas floors ke across sum karte hain.
2. **"Vehicle type aur duration ke basis par pricing add karo."** Ek
   `PricingStrategy` interface introduce karo jisme `calculate(ticket)` ho,
   aur concrete strategies jaise `HourlyPricing` ya `FlatRatePricing` ko
   `ParkingLot` mein inject karo — classic Strategy pattern, jo pricing
   logic ko `ParkingLot` aur `Vehicle` dono se bahar rakhta hai.
3. **"Agar ek vehicle type ko different times par different spots assign kiye
   ja sakte hain (jaise, agar bikes/cars full hain to car van spot bhi use
   kar sakti hai)?"** Ye already handle ho jaata hai kyunki
   `spots_required` ek se zyada spot type ke liye finite value return karta
   hai — bas `Car#spots_required` ko `Van#spots_required` ki tarah extend
   karo, aur `park` mein `preferred_order` adjust karo.
4. **"Isko test kaise karoge?"** Har `Vehicle` subclass ke `spots_required`
   ko isolation mein unit test karo (pure logic, `ParkingLot` ki zaroorat
   nahi), phir `ParkingLot#park`/`unpark` ko full flow ke liye integration-test
   karo, jisme van-spanning-3-bike-spots wala case aur "not enough spots"
   wala case bhi shamil ho.
5. **"Ye Amazon/Google scale par design karne se kaise different hoga, jahan
   ek city mein hazaaron parking lots hon?"** Ye is question ka HLD version
   hai — multiple lots ek distributed system problem ban jaate hain (kaunse
   lot mein availability hai, locations ke across real-time spot-count sync,
   `System_Design/01_Concepts/07_database_scaling.md` aur
   `12_ride_sharing_uber.md` ke geospatial-search deep dive ka cross-reference
   "nearby lots with availability" dhundhne ke liye). Ye distinction
   explicitly naam lena khud ek strong signal hai.

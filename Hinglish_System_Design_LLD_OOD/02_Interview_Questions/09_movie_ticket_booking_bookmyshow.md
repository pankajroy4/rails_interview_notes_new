# Design a Movie Ticket Booking System (Object-Oriented Design)

## Problem Statement

"Ek movie ticket booking system design karo, jaisa BookMyShow. Theaters,
screens, movies, showtimes, aur seats model karo. Ek user ko ek specific
show ke liye available seats dikhne chahiye aur usme se ek ya zyada book
karne chahiye. Alag-alag seat categories ke prices alag hote hain."

Iss repo mein iss exact prompt ka **HLD version** already
`System_Design/02_Interview_Questions/16_ticket_booking_system.md` pe hai
— wo file iss problem ke distributed-systems half ke baare mein hai:
concurrent access ke under seat-hold TTLs, on-sale stampedes ke liye ek
virtual waiting room, aur servers ke across reads/writes scale karna.
**Yeh file ek different interview hai**: koi servers nahi, koi Redis
nahi, koi distributed locks nahi — bas ek single booking transaction ka
class model, ek process mein run hone wala. Dono files saath mein padhne
ke liye hain, lekin ek ka answer dete waqt doosre ke concerns pe mat
jaao; inhe conflate karna khud ek signal hai ki aapko nahi pata LLD kahan
khatam hoti hai aur HLD kahan shuru.

## Step 1: Clarify Requirements

**Functional Requirements**
- Ek `Theater` ke multiple `Screen`s hote hain.
- Ek `Movie` ek `Screen` pe ek specific time pe chalti hai — yeh pairing
  ek `Show` hai.
- Har `Screen` ka `Seat`s ka ek fixed physical layout hota hai, har ek
  ek category (Silver, Gold, Premium) se belong karta hai jiska apna
  price hai.
- Ek given `Show` ke liye, list karo kaunse seats available/booked hain.
- Ek `Show` ke liye ek ya zyada seats book karo; seat categories se
  (aur, optionally, show-specific pricing rules se) total price compute
  karo.
- Ek booking cancel karo, uske seats uss show ke liye wapas free kar dena.

**Non-Functional Requirements**
- **Seat availability per-show hai, per-screen nahi.** Ek screen din
  bhar mein bahut saare shows host karta hai; ek seat ka 3pm show ke liye
  booked hona uske 7pm show pe usi screen pe availability ke baare mein
  kuch nahi kehta. Yeh distinction sahi karna hi iss problem ka central
  point hai jo test kiya ja raha hai.
- **Multi-seat bookings ki atomicity**: 4 seats saath mein book karna
  aisi state nahi chhodni chahiye jahan 2 succeed ho gaye aur 2 silently
  nahi hue — ek behavior pick karo aur justify karo (yeh file
  all-or-nothing pick karti hai).
- **Pricing ki extensibility**: pricing seat category ke hisaab se
  pluggable honi chahiye aur per-show rules ke adaptable honi chahiye
  (jaise, weekend/prime-time surcharge) bina booking flow rewrite kiye.

## Step 2: Identify Core Objects / Entities

- **Movie** — title, duration, language, genre.
- **Theater** — ek physical venue; multiple `Screen`s own karta hai.
- **Screen** — theater ke andar ek physical auditorium; `Seat`s ka ek
  fixed layout own karta hai (seats permanently screen se belong karte
  hain — wo shows ke beech move nahi hote).
- **Seat** — ek `Screen` pe ek physical seat; ek category
  (Silver/Gold/Premium) hoti hai jo base price decide karti hai.
- **Show** — ek specific `Movie` jo ek specific `Screen` pe ek specific
  start time pe chal rahi hai. Yeh wahi entity hai jispe seat ki
  *bookability* actually scoped hai.
- **ShowSeat** — ek `Show` aur ek `Seat` ke beech ka association, track
  karta hai ki kya wo seat *uss specific show ke liye* booked hai. Yeh
  wahi object hai jo poori "screen vs. show" ambiguity resolve karta hai.
- **Booking** — ek user ki reservation: kaunsi show, kaunse seats (via
  `ShowSeat`s), total price, status.
- **PricingStrategy** — ek given show ke liye ek seat ka price compute
  karta hai (base category price, optionally show-time rules se adjusted).

## Step 3: Identify Relationships (Class Diagram)

```text
Movie                          Theater
- title, duration, language    - name, location
                                - screens[] ---------> [Screen]   (composition)

Screen
- theater ------------> Theater                     (association)
- seats[] -------------> [Seat]                      (composition: fixed layout)

Seat
- screen --------------> Screen                      (association)
- seat_number, category: :silver | :gold | :premium

Show
- movie ---------------> Movie                        (association)
- screen --------------> Screen                       (association)
- start_time
- show_seats[] --------> [ShowSeat]                   (composition, one per Seat on the screen)
+ available_seats : [ShowSeat]

ShowSeat                             <-- the Show-vs-Screen distinction lives here
- show ----------------> Show
- seat ----------------> Seat
- status: :available | :booked | :held
- booking -------------> Booking | nil

                    PricingStrategy (abstract)
                    + price_for(show, seat) : Float
                         ^
          ________________|________________
         |                                  |
   StandardPricing                    SurchargePricing
  (flat price per category)      (category price + weekend/prime-time %)

Booking
- user ----------------> User
- show ----------------> Show
- show_seats[] --------> [ShowSeat]                   (association: the seats it holds)
- total_price: Float
- status: :pending | :confirmed | :cancelled

BookingService
- pricing_strategy ----> PricingStrategy
+ book_seats(show, seat_ids, user) : Booking
+ cancel(booking) : Boolean
```

Relationship types:
- `Theater` `Screen`s ko **compose** karta hai; `Screen` `Seat`s ko
  **compose** karta hai — dono permanent physical structure hain jo
  independently exist nahi karte.
- `Show` `ShowSeat`s ko **compose** karta hai (uske screen pe har seat
  ke liye ek, jab show schedule hoti hai tab create hote hain) lekin sirf
  `Movie` aur `Screen` ke saath **associate** hota hai — ek show ek
  movie aur ek screen ko reference karti hai lekin unka lifecycle own
  nahi karti.
- `ShowSeat` `Show` ko `Seat` ke saath **associate** karta hai — yeh
  wahi join entity hai jo booking state ko per-show banata hai per-screen
  ke bajaye, bilkul parallel jaise ek library ka `BookCopy`, ek `Book`
  title ko ek physical, individually-loanable copy ke saath associate
  karta hai (same "shared definition, per-instance state" pattern, alag
  domain).
- `Booking` un `ShowSeat`s ke saath **associate** hota hai jo wo claim
  karta hai — ek booking seats permanently own nahi karti, wo bas iss
  show ke liye unpe ek claim hold karti hai, status changes ke through
  track hota hai.

## Step 4: Design Decisions & Patterns Used

**Seats `Screen` ke belong kyun hote hain, lekin bookability `ShowSeat` pe
kyun hai, `Seat` pe directly nahi.** Yahi poore problem ka crux hai. Ek
`Seat` object (jaise, "Screen 3, Row F, Seat 12, Gold") ek physical fact
hai jo din bhar change nahi hota. Agar aap `Seat` pe directly ek `booked`
flag daal do, toh 3pm show ke liye uss seat ko book karna incorrectly
usse 7pm show ke liye bhi booked dikha dega — kyunki sirf ek `Seat`
object hai aur ek flag hai. Fix wahi modeling move hai jo ek library
system mein ek `Book` (title/ISBN) ko ek `BookCopy` (ek physical,
individually-checkout-able instance) se separate karne mein hota hai:
`Seat` permanent, physical definition hai; `ShowSeat` uss seat ke booking
state ka fresh, per-show record hai, jo har `Seat` ke liye ek baar create
hota hai jab ek `Show` schedule hoti hai. `Show#available_seats`
`show_seats` ko status se filter karta hai — `Seat` state ko kabhi touch
nahi karta. Yeh exactly wo distinction hai jo zyadatar candidates first
pass mein galat karte hain, aur interviewer ke pucne se pehle hi isse
explicitly bolna worth hai.

**Pricing ke liye Strategy pattern.** Naive design `{silver: 100, gold:
200, premium: 350}` price lookups ko inline hardcode kar deta hai jahan
bhi total compute hota hai. Jaise hi business "Friday/Saturday evening
shows ke liye 20% zyada" chahta hai, uss logic ko har call site ke through
thread karna padta hai. Iski jagah, `PricingStrategy#price_for(show,
seat)` hi single seam hai: `StandardPricing` bas seat ki category price
return karta hai; `SurchargePricing` usse wrap karta hai aur
`show.start_time` ke based ek percentage add karta hai. `BookingService`
sirf abstract interface pe depend karta hai, isliye pricing rules ko
swap ya compose karna kabhi booking logic ko touch nahi karta — same
Strategy-pattern shape jaisa parking lot follow-ups mein `PricingStrategy`
aur Splitwise problem mein `SplitStrategy`.

**Bookings all-or-nothing kyun hain, partial nahi.** Agar ek user 4 seats
request karta hai aur booking execute hone tak sirf 2 actually free hain,
toh do designs possible hain: silently jo 2 available hain unhe book kar
do (partial success), ya poori request fail kar do aur kuch bhi book mat
karo (atomic failure). Iss domain ke liye partial success almost hamesha
galat hai — 4 friends ka group nahi chahta ki 2 seated ho jaayein aur 2
reject ho jaayein bina un 2 ko undo karne ke easy way ke. Yeh design
**all-or-nothing** pick karta hai: `book_seats` pehle har requested seat
ki availability check karta hai, aur sirf tab state mutate karta hai jab
sab free hon; koi bhi unavailable seat poori request ko cleanly abort
kar deta hai `ShowSeat` status touch karne se pehle. Yeh tradeoff
explicitly state karna chahiye, assume nahi, kyunki ek reasonable
interviewer kisi doosre domain ke liye opposite bhi chah sakta hai
(jaise, "in servers mein se jo bhi free hain wo grab kar lo" partially
karna theek hai).

**`Booking` directly `Seat.booked` kyun nahi flip karta.** `ShowSeat`
design ke consistent: `Booking` `ShowSeat#status` change karta hai, kabhi
`Seat` ko touch nahi karta — yeh "kya yeh seat booked hai" ko hamesha "iss
specific show ke liye" hi mean karne deta hai, koi code path aisa nahi hai
jo accidentally ek seat ko saari shows ke across booked dikha de.

## Step 5: Code

```ruby
Movie = Struct.new(:title, :duration_minutes, :language)

class Theater
  attr_reader :name, :screens

  def initialize(name)
    @name = name
    @screens = []
  end

  def add_screen(screen) = screens << screen
end

class Screen
  attr_reader :theater, :name, :seats

  def initialize(theater, name, seat_layout)
    @theater = theater
    @name = name
    # seat_layout: [[seat_number, category], ...]
    @seats = seat_layout.map { |number, category| Seat.new(self, number, category) }
  end
end

class Seat
  attr_reader :screen, :seat_number, :category

  def initialize(screen, seat_number, category)
    @screen = screen
    @seat_number = seat_number
    @category = category # :silver, :gold, :premium
  end
end

class ShowSeat
  attr_reader :show, :seat
  attr_accessor :status, :booking

  def initialize(show, seat)
    @show = show
    @seat = seat
    @status = :available
    @booking = nil
  end

  def available? = status == :available
end

class Show
  attr_reader :movie, :screen, :start_time, :show_seats

  def initialize(movie, screen, start_time)
    @movie = movie
    @screen = screen
    @start_time = start_time
    # One ShowSeat per physical seat on the screen -- created fresh for
    # THIS show, so booking state never leaks across shows on the same screen.
    @show_seats = screen.seats.map { |seat| ShowSeat.new(self, seat) }
  end

  def available_seats
    show_seats.select(&:available?)
  end

  def show_seat_for(seat_number)
    show_seats.find { |ss| ss.seat.seat_number == seat_number }
  end
end

class PricingStrategy
  def price_for(show, seat)
    raise NotImplementedError
  end
end

class StandardPricing < PricingStrategy
  BASE_PRICE = { silver: 100, gold: 200, premium: 350 }.freeze

  def price_for(_show, seat)
    BASE_PRICE.fetch(seat.category)
  end
end

class SurchargePricing < PricingStrategy
  def initialize(base_strategy, surcharge_pct:, prime_time_start:, prime_time_end:)
    @base_strategy = base_strategy
    @surcharge_pct = surcharge_pct
    @prime_time_start = prime_time_start
    @prime_time_end = prime_time_end
  end

  def price_for(show, seat)
    base = @base_strategy.price_for(show, seat)
    prime_time?(show) ? (base * (1 + @surcharge_pct / 100.0)).round(2) : base
  end

  private

  def prime_time?(show)
    hour = show.start_time.hour
    (hour >= @prime_time_start && hour < @prime_time_end) &&
      [6, 0].include?(show.start_time.wday) # Sat/Sun
  end
end

class Booking
  attr_reader :user, :show, :show_seats, :total_price
  attr_accessor :status

  def initialize(user, show, show_seats, total_price)
    @user = user
    @show = show
    @show_seats = show_seats
    @total_price = total_price
    @status = :confirmed
  end

  def cancel!
    return false if status == :cancelled

    show_seats.each do |ss|
      ss.status = :available
      ss.booking = nil
    end
    @status = :cancelled
    true
  end
end

class SeatsUnavailableError < StandardError; end

class BookingService
  def initialize(pricing_strategy = StandardPricing.new)
    @pricing_strategy = pricing_strategy
  end

  # All-or-nothing: validates every requested seat is available for THIS
  # show before mutating any state, so a partially-unavailable request
  # never leaves some seats booked and others not.
  def book_seats(show, seat_numbers, user)
    show_seats = seat_numbers.map { |num| show.show_seat_for(num) }

    if show_seats.any?(&:nil?)
      raise SeatsUnavailableError, "one or more seats don't exist on this screen"
    end

    unavailable = show_seats.reject(&:available?)
    unless unavailable.empty?
      raise SeatsUnavailableError, "seats already booked for this show: #{unavailable.map { |ss| ss.seat.seat_number }}"
    end

    total = show_seats.sum { |ss| @pricing_strategy.price_for(show, ss.seat) }
    booking = Booking.new(user, show, show_seats, total)

    show_seats.each do |ss|
      ss.status = :booked
      ss.booking = booking
    end

    booking
  end

  def cancel(booking)
    booking.cancel!
  end
end
```

**Isko use karte hue:**

```ruby
theater = Theater.new("PVR Downtown")
layout = (1..10).map { |n| [n, n <= 3 ? :premium : (n <= 6 ? :gold : :silver)] }
screen1 = Screen.new(theater, "Screen 1", layout)
theater.add_screen(screen1)

inception = Movie.new("Inception", 148, "English")
show_3pm = Show.new(inception, screen1, Time.new(2026, 9, 19, 15, 0))
show_7pm = Show.new(inception, screen1, Time.new(2026, 9, 19, 19, 0))

service = BookingService.new(StandardPricing.new)

booking = service.book_seats(show_3pm, [1, 2], user)
booking.total_price          # => 700 (2 premium seats @ 350)
show_3pm.available_seats.size # => 8

# Seat 1 is physically the SAME Seat object on screen1, but it's still
# free for the 7pm show -- because booking state lives on ShowSeat, per show.
show_7pm.available_seats.size # => 10

service.book_seats(show_3pm, [1], other_user)
# => raises SeatsUnavailableError ("seat 1 already booked for the 3pm show")

service.cancel(booking)
show_3pm.available_seats.size # => 10, seats 1 and 2 freed together
```

## Step 6: Edge Cases & Extensibility

- **Ek seat jo uss show ke liye already booked hai, lekin usi screen ki
  ek different show ke liye free hai**: exactly wahi scenario jo upar
  demonstrate kiya gaya — `show_3pm.show_seat_for(1)` booked hai jabki
  `show_7pm.show_seat_for(1)` (same physical `Seat` ko wrap karne wala
  ek distinct `ShowSeat`) available rehta hai. Yeh `Show`-vs-`Screen`
  seat-ownership design ka direct payoff hai.
- **Ek booking cancel karna**: `Booking#cancel!` uske har `ShowSeat` ko
  wapas `:available` pe reset karta hai aur unka `booking` reference
  clear karta hai — kyunki `Booking` uss exact list of `ShowSeat`s hold
  karta hai jo usne claim kiye the (same role jo `ParkingTicket` parking
  lot problem mein multi-spot release ke liye play karta hai), "iss
  booking ke paas kaunse seats the" search karne ki koi zaroorat nahi hai.
- **Ek multi-seat request mein partial failure**: `book_seats` *saare*
  requested seats validate karta hai *kisi bhi* ko mutate karne se pehle
  — agar seat 1 free hai lekin seat 2 nahi, kuch bhi book nahi hota aur
  `SeatsUnavailableError` raise hota hai. Alternative (jo available hai
  wo book karo, jo nahi hua wo report karo) bhi ek legitimate design hai,
  lekin ek deliberate choice honi chahiye, write-as-you-go looping ka
  accident nahi.
- **Ek `seat_number` jo iss screen pe exist hi nahi karta**: "already
  booked" se separately check kiya jaata hai, taaki caller ko clear
  signal mile ki yeh ek bad request hai, race condition nahi.
- **Do users ek hi seat ko concurrently book karne ki koshish karein**:
  yahan dikhaye gaye single-process class-design level pe, yeh handle
  nahi kiya gaya hai (`book_seats` ke check-then-set mein wahi
  read-then-write gap hai jo parking lot ke `park` method mein hai) —
  yeh problem legitimately kahan HLD concern ban jaati hai, uske liye
  neeche follow-up dekho.

## Follow-up Questions an Interviewer Might Ask

1. **"Seat-hold-with-timeout kaise add karoge — ek seat 5 minutes ke liye
   reserve rehta hai jab user checkout mein hai, phir agar confirm nahi
   karta toh release ho jaata hai?"** Class-design level pe: `ShowSeat` pe
   ek `HoldExpiry` timestamp aur ek `:held` status add karo jo `:booked`
   se distinct ho; `available?` `status == :available || (status ==
   :held && Time.now > hold_expiry)` ban jaata hai, aur booking confirm
   karna `:held → :booked` transition karta hai. Yeh answer ka easy 80%
   hai. Honest remainder: iss hold ko *actually* reliably aur
   consistently expire karna jab bahut saare users usi show pe
   concurrently hit karte hain — bina ek background sweep ke ek
   confirming user ke against race kiye, aur multiple app servers ke
   across consistent — yahi exactly wo distributed seat-hold-TTL problem
   hai jo `System_Design/02_Interview_Questions/16_ticket_booking_system.md`
   (section 6.1) mein cover hai. Iss crossover point ko explicitly name
   karna hi yahan sabse strong answer hai, iss file ke scope ke andar
   concurrency solve karne ki koshish nahi.
2. **"Adjacent/group seating kaise support karoge (4 logon ki ek family
   saath baithna chahti hai)?"** Yeh `available_seats` ke upar ek
   allocation algorithm ban jaata hai: available seats ko row se group
   karo, ek row ke andar N free seat-numbers ka ek contiguous run dhundho
   (ek sliding-window scan), aur agar multiple options hon toh "best"
   row/category ke closest run prefer karo — `BookingService` ko ek
   `find_adjacent_seats(show, count, category:)` helper milega jo existing
   `book_seats` mein feed karega.
3. **"Yeh System Design version ke iss question se kaise different hai?"**
   Yeh file ek single process mein ek booking transaction ki classes
   model karti hai — koi networking nahi, koi persistence layer nahi,
   upar note kiya gaya se zyada koi concurrency concerns nahi. HLD file
   cover karti hai ki kya hota hai jab lakhon users ek hi on-sale show
   pe simultaneously hit karte hain: ek simple status flag ke bajaye
   distributed locks ya hold-TTLs, load shed karne ke liye ek virtual
   waiting room, aur read-heavy seat-map views ke liye database/cache
   scaling. Dono superficially similar prompts ke "correct" answers hain
   — jo skill test ho raha hai wo yeh janna hai ki interviewer actually
   kaunsa pooch raha hai.
4. **"Demand ke based seats ko dynamically kaise price karoge (surge
   pricing jaise-jaise show fill hoti hai)?"** Ek `DemandPricing` strategy
   add karo jo `price_for` ke andar `show.available_seats.size` ko
   `show.show_seats.size` ke relative account mein le — `BookingService`
   ya `Booking` mein koi changes nahi, kyunki pricing already poori tarah
   `PricingStrategy` ke peeche abstracted hai.
5. **"User ko ek booking pe discount code ya wallet credit apply karne
   kaise doge?"** `total_price` ko seat-derived subtotal hi rakho, aur
   `BookingService` mein ek separate `apply_discount(booking, discount)`
   step add karo jo ek final payable amount produce kare — deliberately
   discount logic ko `PricingStrategy` mein fold nahi karna, kyunki ek
   discount ek poori booking pe apply hota hai (seats ke across), jabki
   `PricingStrategy` ek single seat ke price tak scoped hai.
6. **"Agar ek show reschedule ho jaaye ya poori tarah cancel ho jaaye toh
   existing bookings ka kya hoga?"** Ek cancelled `Show` ko uske
   `ShowSeat`s ko reference karne wali har `Booking` ko cascade-cancel
   karna chahiye (refund karna, users ko notify karna) — worth mention
   karna as ek lifecycle concern jo argue karta hai ki `Show` ke paas
   active bookings ka ek back-reference hona chahiye, ya `BookingService`
   show se query kare, kuch aisa nahi jo `Show` khud handle kare.

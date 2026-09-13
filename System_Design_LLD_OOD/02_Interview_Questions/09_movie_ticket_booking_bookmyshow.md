# Design a Movie Ticket Booking System (Object-Oriented Design)

## Problem Statement

"Design a movie ticket booking system like BookMyShow. Model theaters,
screens, movies, showtimes, and seats. A user should be able to see
available seats for a specific show and book one or more of them.
Different seat categories have different prices."

This repo already has the **HLD version** of this exact prompt at
`System_Design/02_Interview_Questions/16_ticket_booking_system.md` — that
file is about the distributed-systems half of the problem: seat-hold TTLs
under concurrent access, a virtual waiting room for on-sale stampedes, and
scaling reads/writes across servers. **This file is a different
interview**: no servers, no Redis, no distributed locks — just the class
model for a single booking transaction, run in one process. The two files
are meant to be read together, but don't reach for either's concerns while
answering the other; conflating them is itself a signal of not knowing
where LLD ends and HLD begins.

## Step 1: Clarify Requirements

**Functional Requirements**
- A `Theater` has multiple `Screen`s.
- A `Movie` plays on a `Screen` at a specific time — this pairing is a
  `Show`.
- Each `Screen` has a fixed physical layout of `Seat`s, each belonging to
  a category (Silver, Gold, Premium) with its own price.
- For a given `Show`, list which seats are available/booked.
- Book one or more seats for a `Show`; compute total price from seat
  categories (and, optionally, show-specific pricing rules).
- Cancel a booking, freeing its seats back up for that show.

**Non-Functional Requirements**
- **Seat availability is per-show, not per-screen.** A screen hosts many
  shows across a day; a seat being booked for the 3pm show says nothing
  about its availability at 7pm on the same screen. Getting this
  distinction right is the central thing this problem is testing.
- **Atomicity of multi-seat bookings**: booking 4 seats together should
  not leave the system in a state where 2 succeeded and 2 silently
  didn't — pick and justify one behavior (this file picks all-or-nothing).
- **Extensibility of pricing**: pricing should be pluggable per seat
  category and adaptable to per-show rules (e.g., weekend/prime-time
  surcharge) without rewriting the booking flow.

## Step 2: Identify Core Objects / Entities

- **Movie** — title, duration, language, genre.
- **Theater** — a physical venue; owns multiple `Screen`s.
- **Screen** — a physical auditorium within a theater; owns a fixed
  layout of `Seat`s (seats belong to the screen permanently — they don't
  move between shows).
- **Seat** — one physical seat on a `Screen`; has a category
  (Silver/Gold/Premium) that determines its base price.
- **Show** — a specific `Movie` playing on a specific `Screen` at a
  specific start time. This is the entity that seat *bookability* is
  actually scoped to.
- **ShowSeat** — the association between one `Show` and one `Seat`,
  tracking whether that seat is booked *for that show specifically*. This
  is the object that resolves the whole "screen vs. show" ambiguity.
- **Booking** — a user's reservation: which show, which seats (via
  `ShowSeat`s), total price, status.
- **PricingStrategy** — computes a seat's price for a given show (base
  category price, optionally adjusted by show-time rules).

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
- `Theater` **composes** `Screen`s; `Screen` **composes** `Seat`s — both
  are permanent physical structure that doesn't exist independently.
- `Show` **composes** `ShowSeat`s (one per seat on its screen, created
  when the show is scheduled) but only **associates** with `Movie` and
  `Screen` — a show references a movie and a screen but doesn't own their
  lifecycle.
- `ShowSeat` **associates** `Show` with `Seat` — this is the join entity
  that makes booking state per-show instead of per-screen, exactly
  parallel to how a library's `BookCopy` associates a `Book` title with one
  physical, individually-loanable copy (same "shared definition, per-
  instance state" pattern, different domain).
- `Booking` **associates** with the `ShowSeat`s it claims — a booking
  doesn't own the seats permanently, it just holds a claim on them for
  this show, tracked through status changes.

## Step 4: Design Decisions & Patterns Used

**Why seats belong to `Screen`, but bookability lives on `ShowSeat`, not
`Seat` directly.** This is the crux of the whole problem. A `Seat` object
(e.g., "Screen 3, Row F, Seat 12, Gold") is a physical fact that doesn't
change across the day. If you put a `booked` flag directly on `Seat`,
booking that seat for the 3pm show would incorrectly make it look booked
for the 7pm show too — because there's only one `Seat` object and one flag.
The fix is the same modeling move as separating a `Book` (the title/ISBN)
from a `BookCopy` (one physical, individually-checkout-able instance) in a
library system: `Seat` is the permanent, physical definition; `ShowSeat`
is a fresh, per-show record of that seat's booking state, created once per
`Seat` when a `Show` is scheduled. `Show#available_seats` filters
`show_seats` by status — never touches `Seat` state at all. This is
precisely the distinction most candidates get wrong on a first pass,
and it's worth stating out loud even before the interviewer asks.

**Strategy pattern for pricing.** A naive design hardcodes
`{silver: 100, gold: 200, premium: 350}` price lookups inline wherever a
total is computed. The moment the business wants "20% more for Friday/
Saturday evening shows," that logic has to be threaded through every
call site. Instead, `PricingStrategy#price_for(show, seat)` is the single
seam: `StandardPricing` just returns the seat's category price;
`SurchargePricing` wraps that and adds a percentage based on
`show.start_time`. `BookingService` depends only on the abstract
interface, so swapping or composing pricing rules never touches booking
logic — same Strategy-pattern shape as `PricingStrategy` in the parking
lot follow-ups and `SplitStrategy` in the Splitwise problem.

**Why bookings are all-or-nothing, not partial.** If a user requests 4
seats and only 2 are actually free by the time the booking executes, two
designs are possible: silently book the 2 that are available (partial
success), or fail the whole request and book nothing (atomic failure).
Partial success is almost always wrong for this domain — a group of 4
friends does not want 2 of them seated and 2 rejected with no easy way to
undo the 2 that went through. This design picks **all-or-nothing**:
`book_seats` checks availability for every requested seat first, and only
mutates state if all are free; any unavailable seat aborts the entire
request cleanly before touching `ShowSeat` status. This tradeoff should be
stated explicitly rather than assumed, since a reasonable interviewer
might want the opposite for a different domain (e.g., "grab whichever of
these servers are free" is fine to do partially).

**Why `Booking` doesn't directly flip `Seat.booked`.** Consistent with the
`ShowSeat` design: `Booking` changes `ShowSeat#status`, never touches
`Seat` — this keeps "is this seat booked" always meaning "for this
specific show," with no code path that could accidentally make a seat
look booked across all shows.

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

**Using it:**

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

- **Booking a seat already booked for that show, but free for a different
  show on the same screen**: exactly the scenario demonstrated above —
  `show_3pm.show_seat_for(1)` is booked while `show_7pm.show_seat_for(1)`
  (a distinct `ShowSeat` wrapping the same physical `Seat`) remains
  available. This is the direct payoff of the `Show`-vs-`Screen`
  seat-ownership design.
- **Cancelling a booking**: `Booking#cancel!` resets every one of its
  `ShowSeat`s back to `:available` and clears their `booking` reference —
  because `Booking` holds the exact list of `ShowSeat`s it claimed (same
  role `ParkingTicket` plays for multi-spot release in the parking lot
  problem), there's no need to search for "which seats did this booking
  have."
- **Partial failure on a multi-seat request**: `book_seats` validates
  *all* requested seats before mutating *any* — if seat 1 is free but seat
  2 isn't, nothing is booked and `SeatsUnavailableError` is raised. The
  alternative (book what's available, report what wasn't) is a legitimate
  design too, but should be a deliberate choice, not an accident of
  write-as-you-go looping.
- **A `seat_number` that doesn't exist on this screen**: checked
  separately from "already booked," so the caller gets a clear signal
  it's a bad request, not a race condition.
- **Concurrent booking of the same seat by two users at once**: at the
  single-process class-design level shown here, this isn't handled (the
  check-then-set in `book_seats` has the same read-then-write gap the
  parking lot's `park` method has) — see the follow-up below for where
  this problem legitimately becomes an HLD concern.

## Follow-up Questions an Interviewer Might Ask

1. **"How would you add seat-hold-with-timeout — a seat is reserved for 5
   minutes while a user is in checkout, then released if they don't
   confirm?"** At the class-design level: add a `HoldExpiry` timestamp on
   `ShowSeat` and a `:held` status distinct from `:booked`; `available?`
   becomes `status == :available || (status == :held && Time.now >
   hold_expiry)`, and confirming a booking transitions `:held → :booked`.
   That's the easy 80% of the answer. The honest remainder: making this
   hold *actually* expire reliably and consistently when many users hit
   the same show concurrently — without a background sweep racing a
   confirming user, and consistent across multiple app servers — is
   exactly the distributed seat-hold-TTL problem covered in
   `System_Design/02_Interview_Questions/16_ticket_booking_system.md`
   (section 6.1). Naming that crossover point explicitly is the strongest
   answer here, not trying to solve concurrency inside this file's scope.
2. **"How would you support adjacent/group seating (a family of 4 wants
   to sit together)?"** This becomes an allocation algorithm layered on
   top of `available_seats`: group available seats by row, find a
   contiguous run of N free seat-numbers within a row (a sliding-window
   scan), and prefer the run closest to a "best" row/category if multiple
   options exist — `BookingService` would gain a
   `find_adjacent_seats(show, count, category:)` helper feeding into the
   existing `book_seats`.
3. **"How is this different from the System Design version of this
   question?"** This file models one booking transaction's classes in a
   single process — no networking, no persistence layer, no concurrency
   concerns beyond what's noted above. The HLD file covers what happens
   when millions of users hit the same on-sale show simultaneously:
   distributed locks or hold-TTLs instead of a simple status flag, a
   virtual waiting room to shed load, and database/cache scaling for
   read-heavy seat-map views. Both are "correct" answers to superficially
   similar prompts — the skill being tested is knowing which one the
   interviewer is actually asking for.
4. **"How would you price seats dynamically based on demand (surge
   pricing as a show fills up)?"** Add a `DemandPricing` strategy that
   takes `show.available_seats.size` relative to `show.show_seats.size`
   into account inside `price_for` — no changes to `BookingService` or
   `Booking`, since pricing is already fully abstracted behind
   `PricingStrategy`.
5. **"How would you let a user apply a discount code or wallet credit to
   a booking?"** Keep `total_price` as the seat-derived subtotal, and add
   a separate `apply_discount(booking, discount)` step in
   `BookingService` that produces a final payable amount — deliberately
   not folding discount logic into `PricingStrategy`, since a discount
   applies to a whole booking (crossing seats) while `PricingStrategy`
   is scoped to a single seat's price.
6. **"What happens to existing bookings if a show is rescheduled or
   cancelled entirely?"** A cancelled `Show` should cascade-cancel every
   `Booking` referencing its `ShowSeat`s (refunding, notifying users) —
   worth mentioning as a lifecycle concern that argues for `Show` keeping
   a back-reference to active bookings, or `BookingService` querying by
   show, rather than something `Show` handles by itself.

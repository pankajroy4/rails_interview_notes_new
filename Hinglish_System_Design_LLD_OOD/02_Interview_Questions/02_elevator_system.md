# Design an Elevator System (Object-Oriented Design)

## Problem Statement

"Design an elevator system for a building with multiple elevator cars and
multiple floors. Users can call an elevator from any floor by pressing an
up/down button (a hall call), and once inside, select a destination floor
(a car call). Given several elevators and an incoming request, your system
should decide which car handles it. Model the elevator's own behavior too —
what it does when idle, moving, or with its doors open."

Ye question popular isliye hai kyunki isme do alag hard parts ek hi prompt
mein pack ho jaate hain: (1) ek single elevator ka **behavior ek state
machine ki tarah** — "button press karna" ka matlab hi poori tarah depend
karta hai ki elevator currently kya kar raha hai — aur (2) fleet ke across
ek **scheduling problem**. Jo candidate in dono concerns ko separate kiye
bina seedha code likhne kood padta hai, usually har method mein bikhra hua
`case @status` aur ek aisa scheduler bana leta hai jo bas `elevators.first`
pick kar leta hai. Dono hi actual bugs hain jo ye question surface karne ke
liye design kiya gaya hai.

## Step 1: Clarify Requirements

**Functional Requirements**
- Ek building mein `N` floors aur `M` elevator cars hain.
- Ek floor par user **up** ya **down** press kar sakta hai (hall call) —
  ye kisi bhi elevator ke liye request hai, jiski direction pata hai, aur ye
  kisi car ke bahar se aati hai.
- Car ke andar user ek destination floor select karta hai (car call) — ye
  request *usi specific car* ke liye hai, alag se koi direction nahi hoti
  (car khud infer karta hai direction ki wo pehle se kahan hai us hisaab se).
- System ko decide karna hoga ki aane wale hall call ko kaunsa elevator serve
  karega.
- Har elevator apna current floor, direction, aur door state track karta
  hai, aur idle / moving / doors-open ke beech correctly transition karta
  hai.
- Ek elevator ek hi trip mein multiple requests bina needless back-and-forth
  ke serve karta hai (floor-by-floor zig-zag nahi karna chahiye).

**Non-Functional Requirements**
- **Single responsibility**: ek `Elevator` ko ye pata nahi hona chahiye ki
  fleet mein se *khud ko* kaise pick karna hai — ye ek fleet-level concern
  hai, car-level nahi. `ElevatorController` (fleet/scheduling) aur `Elevator`
  (ek car ki apni state machine) ko alag classes rakho.
- **Extensibility**: ek naya elevator behavior add karna (jaise, ek express
  car jo floors skip kare) ya scheduling algorithm switch karna,
  `Elevator` ki state transition logic ko rewrite kiye bina hona chahiye.
- **Koi scattered conditionals nahi**: button press hone par kya hota hai ye
  kabhi `Elevator` ke andar `case @status` nahi hona chahiye — valid actions
  aur transitions har state ke liye alag hote hain, jo textbook signal hai
  **State pattern** ke liye.
- **Concurrent requests ke under correctness**: jab ek car already move kar
  rahi hai tab aane wale multiple hall/car calls ko uski current trip mein
  integrate karna chahiye, arbitrarily interrupt karke handle nahi karna
  chahiye.

## Step 2: Identify Core Objects / Entities

- **Elevator** — ek physical car: current floor, direction, door state, aur
  wo floors jo abhi bhi visit karni baaki hain.
- **ElevatorState** (abstract) → `IdleState`, `MovingUpState`,
  `MovingDownState`, `DoorsOpenState` — car "arrived at a floor," "doors
  should open/close" jaise events par kya karta hai, aur abhi kaunse
  requests accept karega.
- **Request** (abstract) → `HallCall` (floor + direction, kisi bhi car ke
  bahar se ki gayi), `CarCall` (sirf floor, ek specific car ke andar se ki
  gayi) — ye genuinely alag objects hain kyunki hall call ko controller ke
  through ek car se *match* karna padta hai, jabki car call pehle se hi ek
  car ka hota hai.
- **ElevatorController** — saare `Elevator` instances ko own karta hai,
  aane wale `HallCall`s receive karta hai, aur ek car assign karne ke liye
  scheduling algorithm run karta hai.

## Step 3: Identify Relationships (Class Diagram)

```text
                  ElevatorState (abstract)
                  + on_arrival(elevator, floor)
                  + request_floor(elevator, floor)  [abstract]
                       ^
       ________________|__________________________
      |            |               |                |
  IdleState   MovingUpState   MovingDownState   DoorsOpenState

  Request (abstract)
  - floor
       ^
       |________________
       |                 |
  HallCall           CarCall
  - direction (:up/:down)   (no direction; belongs to one car)

  Elevator
  - id
  - current_floor
  - door_open: Boolean
  - state ------------------> ElevatorState   (composition: state owned by elevator)
  - stops: SortedSet<Integer> (floors still queued to visit)
  + press_button(floor)
  + step()                    (simulate one floor of movement / one state tick)
  + direction : :up | :down | :idle

  ElevatorController
  - elevators: [Elevator]     (composition: controller owns the fleet)
  + request_elevator(floor, direction) : Elevator   (assigns a HallCall)
  + dispatch(elevator, floor)
```

Relationship types:
- `IdleState`/`MovingUpState`/`MovingDownState`/`DoorsOpenState`,
  `ElevatorState` se **inherit** karte hain (is-a) — har ek same interface
  ko differently implement karta hai.
- `Elevator` apne current `ElevatorState` ko **compose** karta hai — state
  object ka koi meaning ya lifecycle us elevator ke bahar nahi hota jo use
  hold karta hai.
- `HallCall`/`CarCall`, `Request` se **inherit** karte hain (is-a);
  `ElevatorController`, `HallCall`s ko us `Elevator` se **associate** karta
  hai jo unhe serve karne ke liye choose kiya gaya hai.
- `ElevatorController` fleet of `Elevator`s ko **compose** karta hai (unhe
  building ke system ki lifetime ke liye own karta hai).

## Step 4: Design Decisions & Patterns Used

**`Elevator` ke liye State pattern kyun, `@status` flag ki jagah.** Naive
version `@status = :idle` rakhta hai aur `press_button` ko aise likhta hai:

```ruby
def press_button(floor)
  if @status == :idle
    # start moving
  elsif @status == :moving_up
    # maybe add stop, maybe ignore
  elsif @status == :doors_open
    # reject or queue
  end
end
```

Jaise-jaise behavior zyada realistic hota jaata hai, `Elevator` ke har
method mein ek aur branch grow hota hai (kya button press karne par doors
closing ke dauraan re-open hone chahiye? kya *wrong* direction mein ek car
call accept hona chahiye?). State pattern isko invert kar deta hai: har
`ElevatorState` subclass `on_arrival` aur `request_floor` ko sirf *apni*
situation ke liye implement karta hai, aur `Elevator` bas `@state` ko
delegate kar deta hai. Naya state add karna (jaise, `OutOfServiceState`)
matlab ek class add karna hai, `Elevator` ke har method ko edit karna nahi.

**Hall calls aur car calls alag classes kyun hain.** `CarCall` pehle se hi
unambiguous hai — ye us car ka hai jiske andar isse press kiya gaya tha, aur
iska matlab hai "please is floor par bhi ruko." `HallCall` design se hi
ambiguous hai — ye *kisi bhi* elevator ke liye request hai, jo direction se
qualify hoti hai (floor 5 par ek up-call ko ek aisi car satisfy nahi kar
sakti jo down ki taraf floor 5 se aage nikal rahi ho). Inhe ek hi
`Request(floor, direction: nil)` class mein collapse karne se har consumer
ko `direction` null-check karna padega ye janne ke liye ki uske paas kis
tarah ka request hai — ye ek sign hai ki dono ko alag types hona chahiye.

**Scheduling algorithm ek SCAN-style direction match kyun hai, "nearest idle
car" nahi.** "Sabse closest elevator pick karo" sahi lagta hai jab tak aap
ye imagine na karo: elevator A floor 2 par hai aur up move kar raha hai,
elevator B floor 10 par idle hai. Floor 5 par ek up jaane wala hall call
aata hai. Nearest-*idle* car B hai (5 floors door) lekin A *already usi
taraf ja raha hai* aur jaldi aur zyada efficiently wahan pahunchega —
iski jagah B ko bhejne ka matlab hai ki do cars nearby floors par converge
karte hain jabki baaki requests wait karte hain. Real elevator systems ek
**SCAN / LOOK**-style algorithm use karte hain: ek car apni current
direction mein continue karti hai, reverse hone se pehle raaste mein aane
wale har compatible request ko pick up karti hai. Controller ka kaam ye
dhundhna hai ki kaunsi car sabse sasti (cheaply) is request ko apni current
sweep mein absorb kar sakti hai — chahe wo ek idle car ho (cost = distance)
ya ek moving car jo already usi direction mein us floor ki taraf ja rahi ho
(cost = distance, lekin sirf tab jab floor abhi bhi uske aage ho).

## Step 5: Code

```ruby
# --- Requests ---------------------------------------------------------

class Request
  attr_reader :floor

  def initialize(floor)
    @floor = floor
  end
end

class HallCall < Request
  attr_reader :direction # :up or :down

  def initialize(floor, direction)
    super(floor)
    @direction = direction
  end
end

class CarCall < Request
end

# --- Elevator states ----------------------------------------------------

class ElevatorState
  # Called every time the elevator arrives at a floor. Decides whether to
  # stop (open doors) and what state comes next.
  def on_arrival(elevator, floor)
    raise NotImplementedError
  end

  # Called when a floor is requested (hall call assigned by the controller,
  # or a car call pressed inside). Returns true if accepted.
  def request_floor(elevator, floor)
    elevator.stops.add(floor)
    true
  end
end

class IdleState < ElevatorState
  def on_arrival(elevator, floor)
    # Idle elevators don't move, so arrival doesn't apply; no-op.
  end

  def request_floor(elevator, floor)
    super
    elevator.state = floor > elevator.current_floor ? MovingUpState.new : MovingDownState.new
    true
  end
end

class MovingUpState < ElevatorState
  def on_arrival(elevator, floor)
    return unless elevator.stops.include?(floor)

    elevator.stops.delete(floor)
    elevator.state = DoorsOpenState.new
  end

  def request_floor(elevator, floor)
    # Accept immediately if the floor is ahead in the current direction;
    # otherwise it still gets queued and served after the direction flips
    # (the SCAN behavior — no interrupting the current sweep).
    super
  end
end

class MovingDownState < ElevatorState
  def on_arrival(elevator, floor)
    return unless elevator.stops.include?(floor)

    elevator.stops.delete(floor)
    elevator.state = DoorsOpenState.new
  end

  def request_floor(elevator, floor)
    super
  end
end

class DoorsOpenState < ElevatorState
  def on_arrival(elevator, floor)
    # Already stopped; nothing to do until doors close.
  end

  def request_floor(elevator, floor)
    # A new request while doors are open just queues; it doesn't reopen
    # doors or interrupt the close-and-move cycle.
    elevator.stops.add(floor)
    true
  end

  def close_doors(elevator)
    elevator.state = elevator.next_travel_state
  end
end

# --- Elevator -------------------------------------------------------------

class Elevator
  MAX_OCCUPANTS = 10

  attr_reader :id, :current_floor, :stops
  attr_accessor :state
  attr_reader :occupants

  def initialize(id, current_floor: 0)
    @id = id
    @current_floor = current_floor
    @stops = SortedSet.new
    @state = IdleState.new
    @occupants = 0
  end

  def direction
    case @state
    when MovingUpState then :up
    when MovingDownState then :down
    else :idle
    end
  end

  def press_button(floor)
    @state.request_floor(self, floor)
  end

  # Advances the car by one floor toward its next stop, or opens/closes
  # doors if it has arrived. In a real system this is driven by a timer;
  # here it's exposed as an explicit tick for testability.
  def step
    if @state.is_a?(DoorsOpenState)
      @state.close_doors(self)
      return
    end

    return if @stops.empty?

    @current_floor += (direction == :up ? 1 : -1) if @state.is_a?(MovingUpState) || @state.is_a?(MovingDownState)
    @state.on_arrival(self, @current_floor)
  end

  # After doors close, decide the next direction: continue the same way if
  # there are still stops ahead, reverse if stops remain behind, else idle.
  def next_travel_state
    return IdleState.new if @stops.empty?

    ahead_up = @stops.any? { |f| f > @current_floor }
    ahead_down = @stops.any? { |f| f < @current_floor }
    return MovingUpState.new if ahead_up
    return MovingDownState.new if ahead_down

    IdleState.new
  end

  def idle? = @state.is_a?(IdleState)
  def full? = @occupants >= MAX_OCCUPANTS
end

# --- Fleet controller / scheduler -----------------------------------------

class ElevatorController
  def initialize(elevators)
    @elevators = elevators
  end

  # SCAN-style assignment: prefer a car already moving toward the floor in
  # the matching direction (it "picks up" the request for free), otherwise
  # fall back to the closest idle car. Cars that are full are skipped.
  def request_elevator(floor, direction)
    candidates = @elevators.reject(&:full?)

    en_route = candidates.select do |e|
      e.direction == direction &&
        ((direction == :up && floor >= e.current_floor) ||
         (direction == :down && floor <= e.current_floor))
    end
    best = en_route.min_by { |e| (e.current_floor - floor).abs }

    best ||= candidates.select(&:idle?).min_by { |e| (e.current_floor - floor).abs }

    best&.tap { |e| e.press_button(floor) }
  end
end
```

**Isko use karte hue:**

```ruby
fleet = [Elevator.new(1, current_floor: 0), Elevator.new(2, current_floor: 10)]
controller = ElevatorController.new(fleet)

# Hall call: someone at floor 5 wants to go up.
chosen = controller.request_elevator(5, :up)
chosen.id # => 1 (closer, and idle beats the farther idle car)

chosen.press_button(8) # car call from inside, once boarded
chosen.stops # => #<SortedSet: {5, 8}>

chosen.step until chosen.current_floor == 5 && chosen.state.is_a?(DoorsOpenState)
```

## Step 6: Edge Cases & Extensibility

- **Beech mein aane wale naye requests current sweep ko interrupt nahi
  karne chahiye.** Ye sabse common mistake hai: agar elevator A floors 5 aur
  8 serve karte hue up move kar raha hai, aur floor 3 ke liye ek down jaane
  wala hall call aata hai, to A ko turant reverse **nahi** hona chahiye —
  pehle wo floors 5 aur 8 finish karega, phir reverse karega.
  `request_floor` methods sirf `stops` mein *add* karte hain; direction
  changes sirf `next_travel_state` mein hoti hain, wo bhi tab jab current
  sweep exhaust ho chuki ho. Ye galat karo to elevator effectively
  First-Come-First-Served ban jaata hai, jo average mein slower bhi hai aur
  jo ek real elevator kabhi nahi karta.
- **Capacity / weight limits.** `Elevator#full?` gate karta hai ki
  controller kisi car ko consider bhi karega ya nahi. Ek zyada complete
  model ek baar full hone ke baad *car call* ke liye `press_button` reject
  kar dega (jo pehle se andar hai aur floor select kar raha hai wo theek
  hai; jo naya board karna chahta hai jab full ho, use door par hi mana kar
  dena chahiye, button par nahi).
- **Ek elevator ka request ke beech mein out of service ho jaana.** Ek
  `OutOfServiceState` add karo jo `request_floor` ko poori tarah reject kare;
  controller ko us car ke liye already queued kisi bhi hall call ko
  **reassign** bhi karna padega — iska matlab hai ki jo `HallCall`s
  controller ne assign kiye the unhe controller ko khud track karna padega
  (sirf `stops` mein push karke bhool nahi jaana), taaki unhe redirect kiya
  ja sake. Agar live fully code na bhi karo, mention karna worth hai.
- **Starvation.** Ek naive "closest car wins" scheduler ek door floor ko
  starve kar sakta hai agar requests baaki cars ke closer aate rahein. Ek
  production system har request ke liye wait time cap karta hai aur ek
  threshold ke baad assignment force karta hai — ye ek refinement ki tarah
  mention karne layak baat hai, over-engineer karne wali nahi.
- **Doors ka obstruction par reopen hona** (ek real elevator ka door sensor)
  naturally `DoorsOpenState` mein ek `door_blocked` transition ke roop mein
  map hota hai jo apna close timer reset kar de — State pattern isko baaki
  kisi state ko touch kiye bina absorb kar leta hai.

## Follow-up Questions an Interviewer Might Ask

1. **"Bahut saare elevators ke across average wait time kaise minimize
   karoge?"** Har car ki queue length aur estimated time-to-arrival track
   karo (sirf floor distance nahi — direction aur current stops bhi matter
   karte hain), aur request ko us car ko assign karo jiska estimated cost
   sabse kam ho, pure distance nahi. Real scale par ye ek live optimization
   problem ban jaata hai (bulk elevator dispatch algorithms), lekin LLD-level
   jawaab ye hai: `request_elevator` jo cost function use karta hai use
   `(floor - current_floor).abs` se richer banao.
2. **"Express/priority floors add karo (jaise, ek penthouse floor jiski
   dedicated car ho)."** Kuch elevators ko ek `serviceable_floors` set do,
   aur `request_elevator` mein `candidates` ko filter karo taaki sirf wahi
   cars milein jinke liye wo floor serviceable ho — state machine mein
   koi changes nahi chahiye.
3. **"Agar ek hi floor par do hall calls opposite directions request karein
   to?"** Ye do distinct `HallCall`s ki tarah model hote hain (alag
   `direction`), isliye ye legitimately do alag cars se serve ho sakte hain,
   ya ek hi car do alag visits kar sakti hai — model bina kisi special-casing
   ke isse already support karta hai.
4. **"Elevator ko do close floors ke beech oscillate hone se kaise bachaoge?"**
   Ye SCAN design se hi fall out ho jaata hai: stops sirf current direction
   mein exhaust hone tak serve hote hain, isliye car ke peeche wala request
   kabhi immediate reversal cause nahi karta — wo next sweep par pick up ho
   jaata hai.
5. **"Isko kaise test karoge?"** Har `ElevatorState` subclass ke
   `on_arrival`/`request_floor` ko ek stub elevator ke saath isolation mein
   unit-test karo, phir full ride sequences ko integration-test karo
   (`press_button`, repeated `step`, assert karo ki stops sensible order mein
   serve ho rahe hain) aur controller ki assignment logic ko separately, ek
   fixed fleet of elevators ke known states use karke.
6. **"Ye kaise change hoga jab hazaaron elevators kayi buildings ke across
   hon (jaise, elevator fleets monitor karne wala ek SaaS platform)?"** Ye
   HLD territory mein push karta hai — telemetry ingestion, per-building
   partitioning, aur network ke across car state ki eventual consistency —
   isko explicitly LLD/HLD boundary ki tarah naam lena worth hai, bilkul
   waise hi jaise Parking Lot example
   `System_Design/01_Concepts/09_distributed_systems_core.md` se bridge
   karta hai.
